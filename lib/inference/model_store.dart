import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class ImportedModel {
  const ImportedModel({
    required this.path,
    required this.name,
    required this.bytes,
    required this.sha256,
  });
  final String path;
  final String name;
  final int bytes;
  final String sha256;
}

class ModelImportCancelled implements Exception {}

/// Owns private model files and a recoverable, relative-path selection manifest.
class ModelStore {
  ModelStore({Directory? directory}) : _directory = directory;
  final Directory? _directory;
  SendPort? _importControl;
  bool _importActive = false;
  bool _cancelRequested = false;
  bool _committing = false;
  bool get importCommitting => _committing;

  Future<void> remove() async {
    if (_importActive) throw StateError('Wait for model setup to finish.');
    _importActive = true;
    try {
      final root = await _root();
      await for (final entry in root.list(followLinks: false)) {
        final name = entry.uri.pathSegments.last;
        if (entry is File &&
            RegExp(
              r'^(?:(?:prototype|model-[0-9]+)\.gguf(?:\.part)?|selected\.json(?:\.bak|\.new)?)$',
            ).hasMatch(name)) {
          await entry.delete();
        }
      }
    } finally {
      _importActive = false;
    }
  }

  Future<void> _forget(Directory root) async {
    for (final suffix in ['', '.bak', '.new']) {
      final file = File('${root.path}/selected.json$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  /// The optional downloader already owns this private file. Verify it and
  /// move it into the selection transaction instead of keeping a second copy.
  Future<ImportedModel> installDownload(
    String path,
    String name,
    String expectedSha,
  ) async {
    if (_importActive) throw StateError('A model import is already running.');
    _importActive = true;
    try {
      final inspected = await Isolate.run(() => _inspect(path, name));
      if (inspected.sha256 != expectedSha) {
        throw const FormatException(
          'Download checksum did not match. Please download again.',
        );
      }
      final root = await _root();
      final target =
          '${root.path}/model-${DateTime.now().microsecondsSinceEpoch}.gguf';
      await File(path).rename(target);
      final installed = ImportedModel(
        path: target,
        name: name,
        bytes: inspected.bytes,
        sha256: inspected.sha256,
      );
      try {
        await _remember(root, installed);
      } catch (_) {
        await File(target).rename(path);
        rethrow;
      }
      await _reclaim(root, target);
      return installed;
    } finally {
      _importActive = false;
    }
  }

  Future<Directory> _root() async {
    final directory =
        _directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/models');
    await directory.create(recursive: true);
    return directory;
  }

  bool cancelImport() {
    if (!_importActive || _committing) return false;
    _cancelRequested = true;
    _importControl?.send('cancel');
    return true;
  }

  Future<ImportedModel?> restore() async {
    final root = await _root();
    final manifest = File('${root.path}/selected.json');
    final backup = File('${manifest.path}.bak');
    if (!await manifest.exists() && await backup.exists()) {
      await backup.rename(manifest.path);
    }
    if (!await manifest.exists()) {
      // Adopt the preceding prototype's private copy once, without recopying it.
      final legacy = File('${root.path}/prototype.gguf');
      if (!await legacy.exists()) {
        final candidates = await root
            .list(followLinks: false)
            .where(
              (entry) =>
                  entry is File &&
                  RegExp(
                    r'^model-[0-9]+\.gguf$',
                  ).hasMatch(entry.uri.pathSegments.last),
            )
            .take(2)
            .toList();
        if (candidates.length != 1) return null;
        final recovered = await Isolate.run(
          () => _inspect(candidates.single.path, 'Recovered GGUF model'),
        );
        await _remember(root, recovered);
        return recovered;
      }
      final model = await Isolate.run(
        () => _inspect(legacy.path, 'Imported GGUF'),
      );
      await _remember(root, model);
      await _reclaim(root, model.path);
      return model;
    }
    final raw = jsonDecode(await manifest.readAsString());
    if (raw is! Map<String, dynamic> ||
        raw['version'] != 1 ||
        raw['file'] is! String ||
        raw['name'] is! String ||
        (raw['name'] as String).trim().isEmpty ||
        raw['bytes'] is! int ||
        raw['sha256'] is! String ||
        !RegExp(r'^(?:prototype|model-[0-9]+)\.gguf$').hasMatch(raw['file']) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sha256'])) {
      throw const FormatException(
        'The remembered model selection is invalid. Import the model again.',
      );
    }
    final path = '${root.path}/${raw['file']}';
    final name = raw['name'] as String;
    final file = File(path);
    if (!await file.exists()) {
      await _forget(root);
      return null;
    }
    await _checkHeader(file);
    final stat = await file.stat();
    if (stat.size != raw['bytes']) {
      throw const FormatException(
        'The remembered model changed size. Import it again.',
      );
    }
    // These files are private to Linqo and were hashed during import. Reuse
    // that digest only while size, mtime and metadata-change time match.
    // Old manifests without a fingerprint are fully verified once on upgrade.
    final unchanged =
        stat.modified.microsecondsSinceEpoch == raw['modified_us'] &&
        stat.changed.microsecondsSinceEpoch == raw['changed_us'];
    final model = unchanged
        ? ImportedModel(
            path: path,
            name: name,
            bytes: stat.size,
            sha256: raw['sha256'],
          )
        : await Isolate.run(() => _inspect(path, name));
    if (model.bytes != raw['bytes'] || model.sha256 != raw['sha256']) {
      throw const FormatException(
        'The remembered model changed or is damaged. Import it again.',
      );
    }
    if (!unchanged) await _remember(root, model);
    await _reclaim(root, model.path);
    return model;
  }

  Future<ImportedModel> import(String sourcePath, String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Model name must not be empty.');
    }
    if (_importActive) throw StateError('A model import is already running.');
    _importActive = true;
    _cancelRequested = false;
    final port = ReceivePort();
    File? staged;
    try {
      final root = await _root();
      final destination =
          '${root.path}/model-${DateTime.now().microsecondsSinceEpoch}.gguf';
      staged = File('$destination.part');
      await Isolate.spawn(
        _copyWorker,
        (port.sendPort, sourcePath, staged.path, name),
        onError: port.sendPort,
        onExit: port.sendPort,
      );
      ImportedModel? copied;
      await for (final message in port) {
        if (message is SendPort) {
          _importControl = message;
          if (_cancelRequested) message.send('cancel');
        } else if (message is ImportedModel) {
          copied = message;
          break;
        } else if (message == 'cancelled') {
          throw ModelImportCancelled();
        } else if (message is String) {
          throw FileSystemException(message);
        } else {
          throw StateError(
            'The model import worker stopped unexpectedly: $message',
          );
        }
      }
      if (_cancelRequested) throw ModelImportCancelled();
      if (copied == null) {
        throw StateError('Model import ended without a result.');
      }
      // Commit begins here. Stop accepting cancellation during the tiny metadata
      // transaction; the old selection stays intact until it has succeeded.
      _committing = true;
      await staged.rename(destination);
      final model = ImportedModel(
        path: destination,
        name: name,
        bytes: copied.bytes,
        sha256: copied.sha256,
      );
      try {
        await _remember(root, model);
      } catch (_) {
        await File(destination).delete();
        rethrow;
      }
      // Remove only our unselected model files after the selection commits.
      // Failure to reclaim disk space must not turn a committed import into failure.
      await _reclaim(root, destination);
      return model;
    } finally {
      port.close();
      _importControl = null;
      _importActive = false;
      _committing = false;
      if (staged != null && await staged.exists()) await staged.delete();
    }
  }

  static Future<void> _reclaim(Directory root, String selectedPath) async {
    try {
      await for (final entry in root.list()) {
        final leaf = entry.uri.pathSegments.last;
        if (entry is File &&
            leaf != File(selectedPath).uri.pathSegments.last &&
            RegExp(
              r'^(?:prototype|model-[0-9]+)\.gguf(?:\.part)?$',
            ).hasMatch(leaf)) {
          await entry.delete();
        }
      }
    } on FileSystemException {
      /* Retry reclamation on the next restore/import. */
    }
  }

  static Future<void> _remember(Directory root, ImportedModel model) async {
    final stat = await File(model.path).stat();
    final file = File('${root.path}/selected.json');
    final temporary = File('${file.path}.new');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'file': File(model.path).uri.pathSegments.last,
        'name': model.name,
        'bytes': model.bytes,
        'sha256': model.sha256,
        'modified_us': stat.modified.microsecondsSinceEpoch,
        'changed_us': stat.changed.microsecondsSinceEpoch,
      }),
      flush: true,
    );
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
    } catch (_) {
      if (await backup.exists()) await backup.rename(file.path);
      rethrow;
    }
    // Keep the previous manifest until the next transaction for crash recovery.
  }
}

Future<void> _checkHeader(File file) async {
  final bytes = await file.length();
  if (bytes < 24 || bytes > 2500 * 1024 * 1024) {
    throw const FormatException('Choose a GGUF model smaller than 2.5 GB.');
  }
  final handle = await file.open();
  try {
    final magic = await handle.read(4);
    if (magic.length != 4 ||
        magic[0] != 71 ||
        magic[1] != 71 ||
        magic[2] != 85 ||
        magic[3] != 70) {
      throw const FormatException('This file is not a GGUF model.');
    }
  } finally {
    await handle.close();
  }
}

Future<ImportedModel> _inspect(String path, String name) async {
  final file = File(path);
  await _checkHeader(file);
  final digest = await sha256.bind(file.openRead()).first;
  return ImportedModel(
    path: path,
    name: name,
    bytes: await file.length(),
    sha256: digest.toString(),
  );
}

Future<void> _copyWorker((SendPort, String, String, String) args) async {
  final (reply, sourcePath, stagingPath, name) = args;
  final control = ReceivePort();
  var cancelled = false;
  control.listen((_) => cancelled = true);
  reply.send(control.sendPort);
  try {
    final source = File(sourcePath);
    await _checkHeader(source);
    final sink = File(stagingPath).openWrite();
    final digest = Completer<Digest>();
    final hash = sha256.startChunkedConversion(_DigestSink(digest));
    var bytes = 0;
    try {
      await for (final chunk in source.openRead()) {
        if (cancelled) throw ModelImportCancelled();
        hash.add(chunk);
        sink.add(chunk);
        bytes += chunk.length;
        if (bytes > 2500 * 1024 * 1024) {
          throw const FormatException('Model grew beyond the import limit.');
        }
        // Backpressure bounds memory and yields for cancellation messages.
        await sink.flush();
      }
      hash.close();
    } finally {
      await sink.close();
    }
    if (cancelled) throw ModelImportCancelled();
    reply.send(
      ImportedModel(
        path: stagingPath,
        name: name,
        bytes: bytes,
        sha256: (await digest.future).toString(),
      ),
    );
  } on ModelImportCancelled {
    reply.send('cancelled');
  } catch (error) {
    reply.send(error.toString());
  } finally {
    control.close();
  }
}

class _DigestSink implements Sink<Digest> {
  _DigestSink(this.result);
  final Completer<Digest> result;
  @override
  void add(Digest data) => result.complete(data);
  @override
  void close() {}
}
