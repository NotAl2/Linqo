import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/domain/extraction.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LibraryStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('linqo-library-');
    store = await LibraryStore.open(
      path: '${directory.path}/library.db',
      factory: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test(
    'saves, membership, favourites and preferences survive reopening',
    () async {
      final collection = await store.saveCollection('Weekend food', 0);
      final id = await store.save(
        SaveDraft(
          title: 'Chickpea dinner',
          body: 'Simmer chickpeas for 10 minutes.',
          url: 'example.com/recipe',
          kind: SaveKind.recipe,
          collectionIds: [collection],
        ),
      );
      await store.favorite(id, true);
      await store.setPreference('theme', 'dark');
      await store.close();
      store = await LibraryStore.open(
        path: '${directory.path}/library.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      final item = (await store.get(id))!;
      expect(item.title, 'Chickpea dinner');
      expect(item.url, 'https://example.com/recipe');
      expect(item.favorite, isTrue);
      expect(item.collectionIds, [collection]);
      expect(item.collectionNames, ['Weekend food']);
      expect(await store.preference('theme'), 'dark');
    },
  );
  test(
    'indexed prefix search covers titles, notes and URLs, with punctuation safely handled',
    () async {
      await store.save(
        const SaveDraft(
          title: 'A dinner idea',
          body: 'Coconut chickpeas',
          url: 'https://example.com/food',
          kind: SaveKind.recipe,
        ),
      );
      await store.save(
        const SaveDraft(
          title: 'A walk',
          body: 'River path',
          kind: SaveKind.place,
        ),
      );
      expect((await store.query(query: 'chick')).single.title, 'A dinner idea');
      expect(
        (await store.query(query: 'coco chick')).single.title,
        'A dinner idea',
      );
      expect(await store.query(query: 'chick river'), isEmpty);
      expect(
        (await store.query(query: 'example')).single.title,
        'A dinner idea',
      );
      expect(await store.query(query: '" OR *()'), isEmpty);
      expect(await store.query(query: '***'), isEmpty);
      expect((await store.query(kind: SaveKind.place)).single.title, 'A walk');
    },
  );
  test(
    'editing atomically updates search and invalidates stale extraction',
    () async {
      final id = await store.save(
        const SaveDraft(
          title: 'Old title',
          body: 'Ingredients: onions\nChop onions.',
          kind: SaveKind.recipe,
        ),
      );
      const raw =
          '{"schema_version":2,"title":"Onions","summary":"A fragrant supper","type":"recipe","ingredient_lines":[1],"step_lines":[2],"places":[],"detail_lines":[]}';
      final result = ExtractionResult.parse(
        raw,
        SourceDocument('Ingredients: onions\nChop onions.'),
      );
      await store.extraction(
        id,
        'Ingredients: onions\nChop onions.',
        raw,
        result,
      );
      expect((await store.query(query: 'fragrant')).single.id, id);
      await store.save(
        const SaveDraft(
          title: 'New title',
          body: 'A completely different source.',
          kind: SaveKind.note,
        ),
        id: id,
      );
      expect(await store.query(query: 'onions'), isEmpty);
      expect(await store.query(query: 'fragrant'), isEmpty);
      expect((await store.query(query: 'different')).single.id, id);
      expect((await store.get(id))!.extraction, isNull);
      expect(
        await store.extraction(
          id,
          'Ingredients: onions\nChop onions.',
          raw,
          result,
        ),
        isFalse,
      );
    },
  );
  test(
    'collection deletion keeps saves and removing saves clears their index',
    () async {
      final collection = await store.saveCollection('Someday', 2);
      final id = await store.save(
        SaveDraft(title: 'Monmouth Coffee', collectionIds: [collection]),
      );
      await store.deleteCollection(collection);
      expect((await store.get(id))!.collectionIds, isEmpty);
      expect(await store.count(), 1);
      await store.remove(id);
      expect(await store.query(query: 'Monmouth'), isEmpty);
      expect(await store.count(), 0);
    },
  );
  test(
    'invalid membership rolls back the entire save and search transaction',
    () async {
      await expectLater(
        store.save(
          const SaveDraft(title: 'Should not exist', collectionIds: [999]),
        ),
        throwsA(anything),
      );
      expect(await store.count(), 0);
      expect(await store.query(query: 'exist'), isEmpty);
    },
  );
  test(
    'pagination is stable and interrupted jobs become retryable on restart',
    () async {
      for (var i = 0; i < 45; i++) {
        await store.save(SaveDraft(title: 'Save $i'));
      }
      final first = await store.query();
      final next = await store.query(offset: 40);
      expect(first.length, 40);
      expect(next.length, 5);
      expect({...first.map((s) => s.id), ...next.map((s) => s.id)}.length, 45);
      await store.status(first.first.id, 'running');
      await store.close();
      store = await LibraryStore.open(
        path: '${directory.path}/library.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      expect((await store.get(first.first.id))!.status, 'interrupted');
    },
  );
  test(
    'English extraction gating does not prevent saving Unicode notes',
    () async {
      expect(supportsEnglishExtraction('चना सलाद सामग्री'), isFalse);
      expect(
        supportsEnglishExtraction('Chop the onions. Serve with rice.'),
        isTrue,
      );
      await store.save(
        const SaveDraft(title: 'A personal note', body: 'मेरी नोटबुक'),
      );
      expect((await store.query(query: 'नोटबुक')).length, 1);
    },
  );
  test('unsafe URI schemes are rejected', () {
    expect(
      () => normalizeWebUrl('javascript://alert(1)'),
      throwsFormatException,
    );
    expect(
      () => normalizeWebUrl('file:///private/file'),
      throwsFormatException,
    );
  });
  test(
    'list previews stay bounded while the full source remains searchable',
    () async {
      final body = '${'long source ' * 1500}hiddenkeyword';
      final id = await store.save(SaveDraft(title: 'Long note', body: body));
      final preview = (await store.query(query: 'hiddenkeyword')).single;
      expect(preview.preview, isTrue);
      expect(preview.body.length, lessThanOrEqualTo(360));
      expect((await store.get(id))!.body, body);
      expect((await store.get(id))!.preview, isFalse);
    },
  );
}
