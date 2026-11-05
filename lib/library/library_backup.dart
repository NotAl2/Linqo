import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'library_store.dart';
import 'models.dart';

/// Portable, versioned library backups. Model weights and expendable image
/// caches are deliberately excluded. Compression and file checks run off UI.
class LibraryBackup {
  LibraryBackup(this.store, this.attachments);
  final LibraryStore store;
  final Directory attachments;
  static const maxBytes = 512 * 1024 * 1024;
  static const maxManifest = 16 * 1024 * 1024;
  static const maxItems = 10000;
  static final attachmentName = RegExp(r'^\d+(?:\.[a-zA-Z0-9]{1,8})?$');
  static const textLimits = {
    'title': 180,
    'body': 30000,
    'notes': 30000,
    'url': 8192,
    'kind': 20,
    'summary': 30000,
    'extraction': 100000,
    'extracted_from': 32768,
    'file_name': 1024,
    'description': 30000,
    'resolved_url': 8192,
    'content_kind': 40,
  };
  static const defaults = <String, Object?>{
    'title': '',
    'body': '',
    'notes': '',
    'url': '',
    'kind': 'link',
    'created_at': 0,
    'updated_at': 0,
    'favorite': 0,
    'summary': '',
    'extraction': '',
    'extracted_from': '',
    'file_name': '',
    'description': '',
    'resolved_url': '',
    'auto_title': 0,
    'auto_content': 0,
    'auto_extract': 0,
    'content_kind': '',
  };

  static Map<String, Object?> portable(Map<String, Object?> row) => {
    for (final entry in defaults.entries)
      entry.key: row[entry.key] ?? entry.value,
  };

  static String newKey() {
    final random = Random.secure();
    return sha256
        .convert(List.generate(32, (_) => random.nextInt(256)))
        .toString();
  }

  Future<File> export(Directory workspace) async {
    final snapshot = await store.db.transaction((tx) async {
      await tx.execute(
        'CREATE TABLE IF NOT EXISTS backup_receipts (fingerprint TEXT PRIMARY KEY, save_id INTEGER NOT NULL REFERENCES saves(id) ON DELETE CASCADE)',
      );
      final saves = await tx.query('saves');
      final keyed = <Map<String, Object?>>[];
      for (final row in saves) {
        final existing = await tx.query(
          'backup_receipts',
          where: 'save_id=?',
          whereArgs: [row['id']],
          limit: 1,
        );
        final key = existing.isEmpty
            ? newKey()
            : existing.single['fingerprint'] as String;
        if (existing.isEmpty) {
          await tx.insert('backup_receipts', {
            'fingerprint': key,
            'save_id': row['id'],
          });
        }
        keyed.add({...row, 'key': key});
      }
      return {
        'format': 'linqo-backup',
        'version': 1,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'saves': keyed,
        'collections': await tx.query('collections'),
        'memberships': await tx.query('memberships'),
      };
    });
    return File(
      await Isolate.run(
        () => _pack(snapshot, attachments.path, workspace.path),
      ),
    );
  }

  static Future<String> _pack(
    Map<String, Object?> snapshot,
    String attachmentRoot,
    String work,
  ) async {
    final saves = snapshot['saves'] as List<Map<String, Object?>>;
    if (saves.length > maxItems) {
      throw const FormatException('Backups support up to 10,000 saves.');
    }
    final files = <String, String>{};
    final exported = <Map<String, Object?>>[];
    var total = 0;
    for (final row in saves) {
      final attachment = row['attachment'] as String;
      var asset = '';
      if (attachment.isNotEmpty) {
        if (!attachmentName.hasMatch(attachment)) {
          throw const FormatException('A file copy has an invalid name.');
        }
        final file = File('$attachmentRoot/$attachment');
        if (!await file.exists()) {
          throw FormatException(
            'Missing file copy: ${row['file_name']}. Keep the original or remove this save before exporting.',
          );
        }
        total += await file.length();
        if (total > maxBytes) {
          throw const FormatException(
            'File copies exceed the 512 MB backup limit.',
          );
        }
        asset = (await sha256.bind(file.openRead()).first).toString();
        files[asset] = file.path;
      }
      exported.add({
        ...portable(row),
        'id': row['id'],
        'key': row['key'],
        'asset': asset,
      });
    }
    final manifest = jsonEncode({...snapshot, 'saves': exported});
    if (utf8.encode(manifest).length > maxManifest) {
      throw const FormatException(
        'Library text exceeds the 16 MB backup limit.',
      );
    }
    final path = '$work/linqo-backup.zip';
    final encoder = ZipFileEncoder()..create(path);
    try {
      encoder.addArchiveFile(ArchiveFile.string('library.json', manifest));
      for (final entry in files.entries) {
        await encoder.addFile(File(entry.value), 'files/${entry.key}');
      }
    } finally {
      await encoder.close();
    }
    return path;
  }

  /// Validate everything before changing the library. Files are staged under
  /// generated private names; never extract archive paths to disk directly.
  Future<({int added, int skipped})> import(
    File file,
    Directory workspace,
  ) async {
    final manifest = await Isolate.run(
      () => _unpack(file.path, workspace.path),
    );
    final created = <File>[];
    var committed = false;
    try {
      await attachments.create(recursive: true);
      final assets = <String, String>{};
      for (final row in manifest.saves) {
        final asset = row['asset'] as String;
        if (asset.isEmpty) continue;
        final suffix =
            RegExp(
              r'\.[a-zA-Z0-9]{1,8}$',
            ).firstMatch(row['file_name'] as String)?.group(0) ??
            '';
        final target = File(
          '${attachments.path}/${DateTime.now().microsecondsSinceEpoch}$suffix',
        );
        if (await target.exists()) throw StateError('Please retry the import.');
        created.add(target);
        await File('${workspace.path}/$asset').copy(target.path);
        assets['${row['id']}'] = target.uri.pathSegments.last;
      }
      final result = await store.mergeBackup(
        manifest.saves,
        manifest.collections,
        manifest.memberships,
        assets,
      );
      committed = true;
      // Repeated imports need no new file copies.
      for (final file in created) {
        final used = await store.db.query(
          'saves',
          columns: ['id'],
          where: 'attachment=?',
          whereArgs: [file.uri.pathSegments.last],
          limit: 1,
        );
        if (used.isEmpty) {
          try {
            await file.delete();
          } on FileSystemException {
            /* Retry cleanup with the OS cache lifecycle. */
          }
        }
      }
      return result;
    } finally {
      if (!committed) {
        for (final file in created) {
          if (await file.exists()) await file.delete();
        }
      }
    }
  }

  static Future<
    ({
      List<Map<String, Object?>> saves,
      List<Map<String, Object?>> collections,
      List<Map<String, Object?>> memberships,
    })
  >
  _unpack(String path, String work) async {
    if (await File(path).length() > maxBytes + maxManifest) {
      throw const FormatException('This backup exceeds the 528 MB limit.');
    }
    final input = InputFileStream(path);
    try {
      final zip = ZipDecoder().decodeStream(input);
      if (zip.length > maxItems + 1) {
        throw const FormatException('Too many backup files.');
      }
      var total = 0;
      for (final entry in zip) {
        total += entry.size;
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            entry.size < 0 ||
            total > maxBytes + maxManifest ||
            (entry.name != 'library.json' &&
                !RegExp(r'^files/[a-f0-9]{64}$').hasMatch(entry.name))) {
          throw const FormatException('This is not a valid Linqo backup.');
        }
      }
      final json = zip.find('library.json');
      if (json == null || json.size > maxManifest) {
        throw const FormatException(
          'Backup library manifest is missing or too large.',
        );
      }
      final manifestFile = File('$work/library.json');
      final manifestOutput = _BoundedBackupOutput(
        manifestFile.path,
        maxManifest,
      );
      try {
        json.decompress(manifestOutput);
      } finally {
        await manifestOutput.close();
      }
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map ||
          decoded['format'] != 'linqo-backup' ||
          decoded['version'] != 1) {
        throw const FormatException('Unsupported Linqo backup version.');
      }
      List<Map<String, Object?>> rows(String key, int limit) {
        final value = decoded[key];
        if (value is! List ||
            value.length > limit ||
            value.any((r) => r is! Map)) {
          throw FormatException('Invalid backup $key.');
        }
        return value.map((r) => Map<String, Object?>.from(r as Map)).toList();
      }

      final saves = rows('saves', maxItems);
      final collections = rows('collections', maxItems);
      final memberships = rows('memberships', 100000);
      final ids = <int>{}, collectionIds = <int>{};
      final keys = <String>{};
      for (final row in collections) {
        if (row['id'] is! int ||
            !collectionIds.add(row['id'] as int) ||
            row['name'] is! String ||
            (row['name'] as String).trim().isEmpty ||
            (row['name'] as String).length > 40 ||
            row['color'] is! int) {
          throw const FormatException('Invalid backup collection.');
        }
      }
      final checked = <String>{};
      var referencedBytes = 0;
      for (final row in saves) {
        if (row['key'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['key'] as String) ||
            !keys.add(row['key'] as String)) {
          throw const FormatException('Invalid backup save key.');
        }
        if (row['id'] is! int || !ids.add(row['id'] as int)) {
          throw const FormatException('Invalid backup save identifier.');
        }
        for (final entry in defaults.entries) {
          final value = row[entry.key];
          if ((entry.value is int && value is! int) ||
              (entry.value is String && value is! String) ||
              (value is String &&
                  value.length > (textLimits[entry.key] ?? 30000))) {
            throw FormatException('Invalid backup ${entry.key}.');
          }
        }
        if ((row['title'] as String).trim().isEmpty ||
            !SaveKind.values.any((k) => k.name == row['kind']) ||
            ![0, 1].contains(row['favorite']) ||
            [
              'auto_title',
              'auto_content',
              'auto_extract',
            ].any((k) => ![0, 1].contains(row[k]))) {
          throw const FormatException('Invalid backup save.');
        }
        for (final field in ['created_at', 'updated_at']) {
          final timestamp = row[field] as int;
          if (timestamp < 0 || timestamp > 8640000000000000) {
            throw const FormatException('Invalid backup date.');
          }
        }
        normalizeWebUrl(row['url'] as String);
        final asset = row['asset'];
        if (asset is! String ||
            (asset.isNotEmpty && !RegExp(r'^[a-f0-9]{64}$').hasMatch(asset))) {
          throw const FormatException('Invalid backup file reference.');
        }
        if (asset.isNotEmpty) {
          final entry = zip.find('files/$asset');
          if (entry == null) {
            throw const FormatException('A backup file is missing.');
          }
          referencedBytes += entry.size;
          if (referencedBytes > maxBytes) {
            throw const FormatException(
              'File copies exceed the 512 MB backup limit.',
            );
          }
          if (!checked.add(asset)) continue;
          final target = File('$work/$asset');
          final output = _BoundedBackupOutput(target.path, entry.size);
          try {
            entry.decompress(output);
          } finally {
            await output.close();
          }
          if ((await sha256.bind(target.openRead()).first).toString() !=
              asset) {
            throw const FormatException(
              'A backup file failed its integrity check.',
            );
          }
        }
      }
      for (final row in memberships) {
        if (!ids.contains(row['save_id']) ||
            !collectionIds.contains(row['collection_id'])) {
          throw const FormatException('Invalid backup collection membership.');
        }
      }
      return (saves: saves, collections: collections, memberships: memberships);
    } finally {
      await input.close();
    }
  }
}

/// Enforce actual decompressed writes, not only untrusted ZIP size headers.
class _BoundedBackupOutput extends OutputFileStream {
  _BoundedBackupOutput(String path, this.maximum)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));
  final int maximum;
  void check(int count) {
    if (length + count > maximum) {
      throw const FormatException(
        'Backup decompressed data exceeds its size limit.',
      );
    }
  }

  @override
  void writeByte(int value) {
    check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }
}
