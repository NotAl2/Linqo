import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/sharing/link_preview.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LibraryStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('linqo-share-');
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
    'receipt is idempotent and metadata becomes searchable after reopening',
    () async {
      const draft = SaveDraft(
        title: 'YouTube video',
        url: 'https://youtu.be/jNQXAC9IVRw',
        kind: SaveKind.video,
        shareId: 'receipt-1',
        autoTitle: true,
        previewStatus: 'pending',
      );
      final id = await store.save(draft);
      expect(await store.save(draft), id);
      expect(await store.count(), 1);
      await store.applyPreview(
        id,
        draft.url,
        draft.title,
        const LinkPreview(
          title: 'Me at the zoo',
          description: 'Elephant enclosure',
          image: 'abc.img',
          available: true,
        ),
      );
      await store.close();
      store = await LibraryStore.open(
        path: '${directory.path}/library.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      expect(await store.receivedShare('receipt-1'), id);
      expect(
        (await store.query(query: 'elephant')).single.title,
        'Me at the zoo',
      );
      expect((await store.get(id))!.previewImage, 'abc.img');
    },
  );
  test(
    'late metadata cannot overwrite an edited title, changed URL or deleted save',
    () async {
      final id = await store.save(
        const SaveDraft(
          title: 'My own title',
          url: 'https://example.org',
          autoTitle: false,
        ),
      );
      const preview = LinkPreview(
        title: 'Automatic title',
        description: 'Page preview',
        available: true,
      );
      await store.applyPreview(
        id,
        'https://example.org',
        'My own title',
        preview,
      );
      expect((await store.get(id))!.title, 'My own title');
      await store.save(
        const SaveDraft(title: 'Changed source', url: 'https://example.com'),
        id: id,
      );
      await store.applyPreview(
        id,
        'https://example.org',
        'Changed source',
        preview,
      );
      expect((await store.get(id))!.description, isEmpty);
      await store.remove(id);
      await store.applyPreview(
        id,
        'https://example.com',
        'Changed source',
        preview,
      );
      expect(await store.count(), 0);
    },
  );
  test(
    'v1 migration preserves saves, collections, preferences and full-text search',
    () async {
      final group = await store.saveCollection('Keep me', 0);
      final id = await store.save(
        SaveDraft(
          title: 'Original save',
          body: 'Unchanged source',
          collectionIds: [group],
        ),
      );
      await store.favorite(id, true);
      await store.setPreference('theme', 'dark');
      await store.db.execute('DROP INDEX saves_share_receipt');
      for (final column in [
        'description',
        'auto_content',
        'auto_extract',
        'content_status',
        'content_kind',
        'preview_image',
        'preview_status',
        'resolved_url',
        'source_share_id',
        'auto_title',
        'notes',
        'image_status',
      ]) {
        await store.db.execute('ALTER TABLE saves DROP COLUMN $column');
      }
      await store.db.setVersion(1);
      await store.close();
      store = await LibraryStore.open(
        path: '${directory.path}/library.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      expect((await store.get(id))!.favorite, isTrue);
      expect((await store.get(id))!.collectionIds, [group]);
      expect(await store.preference('theme'), 'dark');
      expect((await store.query(query: 'unchanged source')).single.id, id);
      expect((await store.get(id))!.previewStatus, 'none');
    },
  );

  test(
    'failed lookup stays automatic and successful retry keeps earlier metadata on failure',
    () async {
      final id = await store.save(
        const SaveDraft(
          title: 'Instagram post',
          url: 'https://www.instagram.com/p/fixture/',
          autoTitle: true,
        ),
      );
      await store.applyPreview(
        id,
        'https://www.instagram.com/p/fixture/',
        'Instagram post',
        const LinkPreview(imageStatus: 'unavailable'),
      );
      expect((await store.get(id))!.autoTitle, isTrue);
      await store.close();
      store = await LibraryStore.open(
        path: '${directory.path}/library.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      await store.applyPreview(
        id,
        'https://www.instagram.com/p/fixture/',
        'Instagram post',
        const LinkPreview(
          title: 'A real caption',
          description: 'Details',
          image: 'cached.img',
          imageStatus: 'ready',
          available: true,
        ),
      );
      expect((await store.get(id))!.title, 'A real caption');
      await store.applyPreview(
        id,
        'https://www.instagram.com/p/fixture/',
        'A real caption',
        const LinkPreview(imageStatus: 'unavailable'),
      );
      final result = (await store.get(id))!;
      expect(result.title, 'A real caption');
      expect(result.description, 'Details');
      expect(result.previewImage, 'cached.img');
      expect(result.previewStatus, 'ready');
      expect(result.imageStatus, 'ready');
    },
  );

  test(
    'v2 upgrade preserves source and independently stores and searches personal notes',
    () async {
      final id = await store.save(
        const SaveDraft(title: 'Original', body: 'Original caption'),
      );
      await store.db.execute('ALTER TABLE saves DROP COLUMN notes');
      for (final column in [
        'auto_content',
        'auto_extract',
        'content_status',
        'content_kind',
      ]) {
        await store.db.execute('ALTER TABLE saves DROP COLUMN $column');
      }
      await store.db.execute('ALTER TABLE saves DROP COLUMN image_status');
      await store.db.setVersion(2);
      await store.close();
      store = await LibraryStore.open(
        path: '${directory.path}/library.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      expect((await store.get(id))!.body, 'Original caption');
      expect((await store.get(id))!.notes, isEmpty);
      await store.save(
        const SaveDraft(
          title: 'Original',
          body: 'Original caption',
          notes: 'Birthday inspiration',
        ),
        id: id,
      );
      expect(
        (await store.query(query: 'birthday')).single.notes,
        'Birthday inspiration',
      );
      expect(
        (await store.query(query: 'caption')).single.body,
        'Original caption',
      );
    },
  );

  test(
    'a title-ready save with an interrupted image remains resumable',
    () async {
      final id = await store.save(
        const SaveDraft(
          title: 'A fetched title',
          url: 'https://example.org',
          previewStatus: 'ready',
          imageStatus: 'pending',
          autoTitle: true,
        ),
      );
      await store.close();
      store = await LibraryStore.open(
        path: '${directory.path}/library.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      expect((await store.pendingPreviews()).single.id, id);
      await store.applyPreview(
        id,
        'https://example.org',
        'A fetched title',
        const LinkPreview(
          title: 'A fetched title',
          available: true,
          imageStatus: 'unavailable',
        ),
      );
      expect(await store.pendingPreviews(), isEmpty);
    },
  );
}
