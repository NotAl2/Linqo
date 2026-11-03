import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/sharing/link_preview.dart';

class _ReadyPreview extends PreviewJob {
  @override
  Future<LinkPreview> get future async => const LinkPreview(
    title: 'Recovered title',
    available: true,
    imageStatus: 'unavailable',
  );
  @override
  void cancel() {}
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LibraryStore store;
  late LibraryController controller;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('linqo-release-');
    store = await LibraryStore.open(
      path: '${directory.path}/library.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    controller = LibraryController(
      store,
      attachmentDirectory: directory,
      previewFactory: (_) => _ReadyPreview(),
    );
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  test('restart recovers previews beyond the first sixteen saves', () async {
    for (var i = 0; i < 41; i++) {
      await store.save(
        SaveDraft(
          title: 'Offline save $i',
          url: 'https://example.org/$i',
          kind: SaveKind.link,
          autoTitle: true,
          previewStatus: 'pending',
          imageStatus: 'pending',
        ),
      );
    }
    await store.close();
    store = await LibraryStore.open(
      path: '${directory.path}/library.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    controller.dispose();
    controller = LibraryController(
      store,
      previewFactory: (_) => _ReadyPreview(),
    );
    await controller.initialize(restoreModel: false);
    final timer = Stopwatch()..start();
    while ((await store.pendingPreviews()).isNotEmpty &&
        timer.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await store.pendingPreviews(), isEmpty);
    final all = await store.query(limit: 100);
    expect(all, hasLength(41));
    expect(all.every((item) => item.title == 'Recovered title'), isTrue);
  });

  test('old attachment is removed only after replacement commits', () async {
    final oldFile = await File(
      '${directory.path}/100.txt',
    ).writeAsString('old');
    final replacement = await File(
      '${directory.path}/200.txt',
    ).writeAsString('new');
    final id = await controller.save(
      const SaveDraft(
        title: 'File',
        kind: SaveKind.file,
        fileName: 'old.txt',
        attachment: '100.txt',
      ),
    );
    await expectLater(
      controller.save(
        const SaveDraft(
          title: 'File',
          kind: SaveKind.file,
          fileName: 'new.txt',
          attachment: '200.txt',
          collectionIds: [999],
        ),
        id: id,
      ),
      throwsA(anything),
    );
    expect(await oldFile.exists(), isTrue);
    expect((await store.get(id))!.attachment, '100.txt');
    await controller.save(
      const SaveDraft(
        title: 'File',
        kind: SaveKind.file,
        fileName: 'new.txt',
        attachment: '200.txt',
      ),
      id: id,
    );
    expect(await oldFile.exists(), isFalse);
    expect(await replacement.exists(), isTrue);
    await controller.remove((await store.get(id))!);
    expect(await replacement.exists(), isFalse);
  });
}
