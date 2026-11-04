import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/inference/local_runtime.dart';
import 'package:linqo/inference/model_store.dart';
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/sharing/link_preview.dart';

class _DelayedContent extends PreviewJob {
  final text = Completer<LinkPreview>();
  final complete = Completer<LinkPreview>();
  @override
  Future<LinkPreview> get metadata => text.future;
  @override
  Future<LinkPreview> get future => complete.future;
  @override
  void cancel() {}
}

class _Runtime implements LocalRuntime {
  String? received;
  int? threads;
  @override
  Future<void> load(String path, RuntimeSettings settings) async {
    threads = settings.threads;
  }

  @override
  Stream<String> extract(SourceDocument source) async* {
    received = source.lines.map((line) => line.text).join('\n');
    yield jsonEncode({
      'schema_version': 2,
      'title': 'Onion soup',
      'summary': 'Cook onions and serve warm.',
      'type': 'recipe',
      'ingredient_lines': [],
      'step_lines': [1, 2, 3],
      'places': [],
      'detail_lines': [],
    });
  }

  @override
  void cancel() {}
  @override
  Future<void> unload() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LibraryStore store;
  late LibraryController controller;
  late _Runtime runtime;
  const caption = 'Chop onions.\nSimmer for ten minutes.\nServe warm.';
  const fetched = LinkPreview(
    title: 'Onion soup',
    available: true,
    content: caption,
    contentKind: 'caption',
    contentStatus: 'ready',
    imageStatus: 'unavailable',
  );
  setUp(() async {
    store = await LibraryStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    runtime = _Runtime();
    controller = LibraryController(store, runtime: runtime);
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
  });
  Future<void> waitUntil(bool Function() predicate) async {
    final timer = Stopwatch()..start();
    while (!predicate() && timer.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(predicate(), isTrue);
  }

  void model() {
    controller.lab.model = const ImportedModel(
      path: '/fake.gguf',
      name: 'fake',
      bytes: 42,
      sha256: 'fake',
    );
  }

  test(
    'save immediately, persist late caption and automatically extract with two threads',
    () async {
      model();
      final id = await controller.save(
        const SaveDraft(
          title: 'Instagram reel',
          url: 'https://example.org/reel',
          kind: SaveKind.recipe,
          notes: 'Try this on Sunday',
          autoTitle: true,
          autoExtract: true,
        ),
      );
      final job = _DelayedContent();
      final enriching = controller.enrichPreview(
        id,
        'https://example.org/reel',
        'Instagram reel',
        request: job,
      );
      expect((await store.get(id))!.body, isEmpty);
      expect(runtime.received, isNull);
      job.text.complete(
        const LinkPreview(
          title: 'Onion soup',
          available: true,
          contentStatus: 'pending',
        ),
      );
      job.complete.complete(fetched);
      await enriching;
      await waitUntil(() => runtime.received != null && !controller.processing);
      final item = (await store.get(id))!;
      expect(item.body, caption);
      expect(item.notes, 'Try this on Sunday');
      expect(item.contentKind, 'caption');
      expect(item.contentStatus, 'ready');
      expect(item.summary, isNotEmpty);
      expect(runtime.received, caption);
      expect(runtime.threads, 2);
      expect((await store.query(query: 'onions')).single.id, id);
    },
  );

  test(
    'background caption cannot overwrite text edited while the request ran',
    () async {
      final id = await controller.save(
        const SaveDraft(title: 'Saved link', url: 'https://example.org/reel'),
      );
      final job = _DelayedContent();
      final enriching = controller.enrichPreview(
        id,
        'https://example.org/reel',
        'Saved link',
        request: job,
      );
      job.text.complete(
        const LinkPreview(available: true, contentStatus: 'pending'),
      );
      await controller.save(
        const SaveDraft(
          title: 'My title',
          url: 'https://example.org/reel',
          body: 'My carefully edited source.',
          notes: 'Personal comment',
          automaticContent: false,
        ),
        id: id,
      );
      job.complete.complete(fetched);
      await enriching;
      final item = (await store.get(id))!;
      expect(item.body, 'My carefully edited source.');
      expect(item.notes, 'Personal comment');
      expect(item.title, 'My title');
      expect(item.contentKind, 'manual');
    },
  );
  test('sender text is retained while the fetched caption is added', () async {
    final id = await controller.save(
      const SaveDraft(
        title: 'Shared link',
        url: 'https://example.org/reel',
        body: 'Take a look at this!',
        contentKind: 'shared',
      ),
    );
    expect((await store.get(id))!.contentStatus, 'pending');
    await controller.enrichPreview(
      id,
      'https://example.org/reel',
      'Shared link',
      ready: fetched,
    );
    final item = (await store.get(id))!;
    expect(item.body, contains('Take a look at this!'));
    expect(item.body, contains(caption));
    expect(item.contentKind, 'caption');
    expect(item.contentStatus, 'ready');
  });

  test(
    'content is fetched without a model, and opt-out/background prevent AI loading',
    () async {
      final id = await controller.save(
        const SaveDraft(
          title: 'Saved link',
          url: 'https://example.org/reel',
          autoExtract: true,
        ),
      );
      await controller.enrichPreview(
        id,
        'https://example.org/reel',
        'Saved link',
        ready: fetched,
      );
      expect((await store.get(id))!.body, caption);
      expect(runtime.received, isNull);
      model();
      await controller.automaticExtraction(false);
      controller.foreground();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.received, isNull);
      await controller.background();
      await controller.automaticExtraction(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.received, isNull);
      controller.foreground();
      await waitUntil(() => runtime.received != null && !controller.processing);
      expect(runtime.received, caption);
    },
  );

  test(
    'v3 migration preserves manual text, notes/settings and queues empty link content',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'linqo-v3-migration-',
      );
      var disk = await LibraryStore.open(
        path: '${directory.path}/library.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final collection = await disk.saveCollection('Saved recipes', 0);
        final empty = await disk.save(
          const SaveDraft(title: 'Old link', url: 'https://example.org/reel'),
        );
        final manual = await disk.save(
          SaveDraft(
            title: 'My recipe',
            body: 'Original handwritten source.',
            collectionIds: [collection],
            notes: 'Personal note',
            url: 'https://example.org/recipe',
          ),
        );
        await disk.favorite(manual, true);
        await disk.setPreference('theme', 'dark');
        for (final column in [
          'auto_content',
          'auto_extract',
          'content_status',
          'content_kind',
        ]) {
          await disk.db.execute('ALTER TABLE saves DROP COLUMN $column');
        }
        await disk.db.setVersion(3);
        await disk.close();
        disk = await LibraryStore.open(
          path: '${directory.path}/library.db',
          factory: databaseFactoryFfiNoIsolate,
        );
        final restored = (await disk.get(manual))!;
        expect(restored.body, 'Original handwritten source.');
        expect(restored.notes, 'Personal note');
        expect(restored.favorite, isTrue);
        expect(restored.collectionIds, [collection]);
        expect(restored.automaticContent, isFalse);
        expect(restored.autoExtract, isFalse);
        expect(await disk.preference('theme'), 'dark');
        final pending = (await disk.get(empty))!;
        expect(pending.contentStatus, 'pending');
        expect(pending.automaticContent, isTrue);
        expect(pending.autoExtract, isTrue);
      } finally {
        await disk.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
