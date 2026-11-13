import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_backup.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/services/tiers.dart';

void main() {
  sqfliteFfiInit();
  late Directory root, files;
  late LibraryStore source, target;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('linqo-backup-test-');
    files = await Directory('${root.path}/source-files').create();
    source = await LibraryStore.open(
      path: '${root.path}/source.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    target = await LibraryStore.open(
      path: '${root.path}/target.db',
      factory: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() async {
    await source.close();
    await target.close();
    await root.delete(recursive: true);
  });
  Future<Directory> work() => root.createTemp('work-');
  test(
    'restoring an over-limit library preserves content and blocks only new additions',
    () async {
      for (var i = 0; i < 101; i++) {
        await source.save(SaveDraft(title: 'Restored $i'));
      }
      for (var i = 0; i < 6; i++) {
        await source.saveCollection('Restored collection $i', 0);
      }
      target.limits = () => const LibraryLimits(AppTier.free, enforced: true);
      final archive = await LibraryBackup(source, files).export(await work());
      final backup = LibraryBackup(
        target,
        Directory('${root.path}/restored-files'),
      );
      final result = await backup.import(archive, await work());
      expect(result.added, 101);
      expect(await target.count(), 101);
      expect((await target.collections()).length, 6);
      await expectLater(
        target.save(SaveDraft(title: 'Extra')),
        throwsA(isA<TierLimitException>()),
      );
      await expectLater(
        target.saveCollection('Extra', 0),
        throwsA(isA<TierLimitException>()),
      );
      expect((await backup.import(archive, await work())).added, 0);
      final existing = (await target.query()).first;
      await target.save(
        SaveDraft(title: 'Edited restored save'),
        id: existing.id,
      );
      expect((await target.get(existing.id))!.title, 'Edited restored save');
    },
  );
  test(
    'backup workers do not capture the live controller policy or timer',
    () async {
      final timer = Timer.periodic(const Duration(hours: 1), (_) {});
      LibraryLimits livePolicy() {
        if (!timer.isActive) throw StateError('Controller was disposed.');
        return const LibraryLimits(AppTier.free, enforced: false);
      }

      source.limits = livePolicy;
      target.limits = livePolicy;
      try {
        await source.save(
          const SaveDraft(title: 'Preserved save', body: 'Keep the source.'),
        );
        final archive = await LibraryBackup(source, files).export(await work());
        final importer = LibraryBackup(
          target,
          Directory('${root.path}/restored-live'),
        );
        expect(await importer.import(archive, await work()), (
          added: 1,
          skipped: 0,
        ));
        expect((await target.query()).single.body, 'Keep the source.');
        expect(timer.isActive, isTrue);
      } finally {
        timer.cancel();
        source.limits = null;
        target.limits = null;
      }
    },
  );
  Future<File> mutate(
    File original,
    void Function(Map<String, dynamic>) change, {
    bool traversal = false,
  }) async {
    final zip = ZipDecoder().decodeBytes(await original.readAsBytes());
    final data =
        jsonDecode(utf8.decode(zip.find('library.json')!.content))
            as Map<String, dynamic>;
    change(data);
    final changed = Archive()
      ..add(ArchiveFile.string('library.json', jsonEncode(data)));
    for (final entry in zip.where((f) => f.name != 'library.json')) {
      changed.add(ArchiveFile.bytes(entry.name, entry.content));
    }
    if (traversal) changed.add(ArchiveFile.string('../escape.txt', 'bad'));
    return File(
      '${root.path}/changed.zip',
    ).writeAsBytes(ZipEncoder().encode(changed));
  }

  test(
    'portable backup restores text, results, favourites, files, memberships and search without changing settings',
    () async {
      await File('${files.path}/123.txt').writeAsString('My keepsake');
      final collection = await source.saveCollection('Cookbook', 2);
      final id = await source.save(
        SaveDraft(
          title: 'Weekend recipe',
          body: 'Ingredients:\n2 tomatoes\nMethod:\nChop the tomatoes.',
          notes: 'For Mum',
          kind: SaveKind.recipe,
          fileName: 'recipe.txt',
          attachment: '123.txt',
          collectionIds: [collection],
        ),
      );
      await source.favorite(id, true);
      await source.db.update(
        'saves',
        {'summary': 'A tomato recipe', 'status': 'partial'},
        where: 'id=?',
        whereArgs: [id],
      );
      await target.setPreference('theme', 'dark');
      final backup = await LibraryBackup(source, files).export(await work());
      final restoredFiles = Directory('${root.path}/restored-files');
      final importer = LibraryBackup(target, restoredFiles);
      expect(await importer.import(backup, await work()), (
        added: 1,
        skipped: 0,
      ));
      final saved = (await target.query(query: 'Mum')).single;
      final full = (await target.get(saved.id))!;
      expect(full.body, contains('Chop the tomatoes.'));
      expect(
        full.summary,
        isEmpty,
      ); // A summary with no extraction evidence is not trusted.
      expect(full.notes, 'For Mum');
      expect(full.favorite, isTrue);
      expect(full.collectionNames, ['Cookbook']);
      expect(
        await File('${restoredFiles.path}/${full.attachment}').readAsString(),
        'My keepsake',
      );
      expect(await target.preference('theme'), 'dark');
      await target.db.update(
        'saves',
        {'title': 'My edited title'},
        where: 'id=?',
        whereArgs: [full.id],
      );
      expect(await importer.import(backup, await work()), (
        added: 0,
        skipped: 1,
      ));
      expect((await target.get(full.id))!.title, 'My edited title');
      expect(await restoredFiles.list().length, 1);
      expect((await target.collections()).single.count, 1);
    },
  );
  test(
    'same-library import and empty backup do not duplicate or erase saves',
    () async {
      final backup = await LibraryBackup(source, files).export(await work());
      await target.save(const SaveDraft(title: 'Keep me', kind: SaveKind.note));
      expect(await LibraryBackup(target, files).import(backup, await work()), (
        added: 0,
        skipped: 0,
      ));
      expect(await target.count(), 1);
      final same = await LibraryBackup(target, files).export(await work());
      expect(await LibraryBackup(target, files).import(same, await work()), (
        added: 0,
        skipped: 1,
      ));
    },
  );
  test(
    'malformed, unsupported and traversal backups leave existing library intact',
    () async {
      await source.save(const SaveDraft(title: 'Recipe', kind: SaveKind.note));
      await target.save(const SaveDraft(title: 'Keep me', kind: SaveKind.note));
      final original = await LibraryBackup(source, files).export(await work());
      final importer = LibraryBackup(
        target,
        Directory('${root.path}/restored-files'),
      );
      for (final update in <void Function(Map<String, dynamic>)>[
        (data) => data['version'] = 99,
        (data) => (data['saves'] as List).first['title'] = 42,
        (data) => (data['memberships'] as List).add({
          'save_id': 999,
          'collection_id': 4,
        }),
        (data) => (data['saves'] as List).first['asset'] = 'a' * 64,
      ]) {
        await expectLater(
          importer.import(await mutate(original, update), await work()),
          throwsFormatException,
        );
        expect((await target.query()).single.title, 'Keep me');
      }
      await expectLater(
        importer.import(
          await mutate(original, (_) {}, traversal: true),
          await work(),
        ),
        throwsFormatException,
      );
      expect(await File('${root.path}/escape.txt').exists(), isFalse);
    },
  );
  test(
    'missing source files fail export instead of silently losing a keepsake',
    () async {
      await source.save(
        const SaveDraft(
          title: 'A file',
          kind: SaveKind.file,
          attachment: '123.pdf',
          fileName: 'keepsake.pdf',
        ),
      );
      await expectLater(
        LibraryBackup(source, files).export(await work()),
        throwsFormatException,
      );
    },
  );
  test(
    'distinct identical saves retain their identities and shared file content gets independent copies',
    () async {
      await File('${files.path}/123.txt').writeAsString('Keepsake');
      for (var i = 0; i < 2; i++) {
        await source.save(
          const SaveDraft(
            title: 'Same title',
            kind: SaveKind.file,
            fileName: 'keep.txt',
            attachment: '123.txt',
          ),
        );
      }
      await source.db.update('saves', {'created_at': 1000});
      final importer = LibraryBackup(target, Directory('${root.path}/copies'));
      final backup = await LibraryBackup(source, files).export(await work());
      expect(await importer.import(backup, await work()), (
        added: 2,
        skipped: 0,
      ));
      final items = await target.query();
      expect(items.map((s) => s.attachment).toSet(), hasLength(2));
      expect(await importer.import(backup, await work()), (
        added: 0,
        skipped: 2,
      ));
    },
  );
  test(
    'failed database commit rolls back imported rows and removes newly copied files',
    () async {
      await File('${files.path}/123.txt').writeAsString('My keepsake');
      final collection = await source.saveCollection('New collection', 1);
      await source.save(
        SaveDraft(
          title: 'Import me',
          kind: SaveKind.file,
          attachment: '123.txt',
          fileName: 'keep.txt',
          collectionIds: [collection],
        ),
      );
      await target.save(const SaveDraft(title: 'Keep me', kind: SaveKind.note));
      await target.db.execute(
        "CREATE TRIGGER reject_import BEFORE INSERT ON saves BEGIN SELECT RAISE(ABORT, 'Simulated storage failure'); END",
      );
      final output = Directory('${root.path}/restored-files');
      final backup = await LibraryBackup(source, files).export(await work());
      await expectLater(
        LibraryBackup(target, output).import(backup, await work()),
        throwsA(isA<DatabaseException>()),
      );
      expect((await target.query()).single.title, 'Keep me');
      expect(await target.collections(), isEmpty);
      expect(await output.list().length, 0);
    },
  );
  test('backup rejects symlink metadata before decoding its payload', () async {
    await target.save(const SaveDraft(title: 'Keep me'));
    final archive = Archive()..add(ArchiveFile.bytes('library.json', [0xff]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    final central = directory.centralDirectoryOffset;
    ByteData.sublistView(bytes)
      ..setUint16(central + 4, (3 << 8) | 20, Endian.little)
      ..setUint32(central + 38, 0xa1ff << 16, Endian.little);
    final malicious = await File(
      '${root.path}/symlink.zip',
    ).writeAsBytes(bytes);
    await expectLater(
      LibraryBackup(target, files).import(malicious, await work()),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'This is not a valid Linqo backup.',
        ),
      ),
    );
    expect((await target.query()).single.title, 'Keep me');
  });

  test('corrupted file content is rejected before library changes', () async {
    await File('${files.path}/123.txt').writeAsString('Original content');
    await source.save(
      const SaveDraft(
        title: 'File',
        kind: SaveKind.file,
        attachment: '123.txt',
        fileName: 'keep.txt',
      ),
    );
    final original = await LibraryBackup(source, files).export(await work());
    final zip = ZipDecoder().decodeBytes(await original.readAsBytes());
    final broken = Archive();
    for (final entry in zip) {
      broken.add(
        entry.name == 'library.json'
            ? ArchiveFile.bytes(entry.name, entry.content)
            : ArchiveFile.string(entry.name, 'Changed content'),
      );
    }
    final damaged = await File(
      '${root.path}/damaged.zip',
    ).writeAsBytes(ZipEncoder().encode(broken));
    await expectLater(
      LibraryBackup(
        target,
        Directory('${root.path}/copies'),
      ).import(damaged, await work()),
      throwsFormatException,
    );
    expect(await target.count(), 0);
  });
}
