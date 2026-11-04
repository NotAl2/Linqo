import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../domain/extraction.dart';
import '../sharing/link_preview.dart';
import '../sharing/source_content.dart';
import 'models.dart';

class LibraryStore {
  LibraryStore._(this.db);
  final Database db;
  static Future<LibraryStore> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final location = path ?? '${await getDatabasesPath()}/linqo-library.db';
    final database = await (factory ?? databaseFactory).openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys=ON');
          await db.rawQuery('PRAGMA journal_mode=WAL');
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE saves (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL DEFAULT "", url TEXT NOT NULL DEFAULT "", kind TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, favorite INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT "idle", summary TEXT NOT NULL DEFAULT "", extraction TEXT NOT NULL DEFAULT "", extracted_from TEXT NOT NULL DEFAULT "", error TEXT NOT NULL DEFAULT "", file_name TEXT NOT NULL DEFAULT "", attachment TEXT NOT NULL DEFAULT "")',
          );
          await db.execute(
            'CREATE TABLE collections (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE, color INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE memberships (save_id INTEGER NOT NULL REFERENCES saves(id) ON DELETE CASCADE, collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE, PRIMARY KEY(save_id, collection_id))',
          );
          await db.execute(
            'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX saves_order ON saves(created_at DESC, id DESC)',
          );
          await db.execute(
            'CREATE INDEX saves_kind ON saves(kind, created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX memberships_collection ON memberships(collection_id, save_id)',
          );
          final options = await db.rawQuery('PRAGMA compile_options');
          final hasFts5 = options.any(
            (row) => row.values.contains('ENABLE_FTS5'),
          );
          // Never probe a missing module with a failing CREATE inside the
          // migration transaction: Android SQLite can abort that transaction.
          await db.execute(
            hasFts5
                ? "CREATE VIRTUAL TABLE save_search USING fts5(title, body, summary, details, tokenize='unicode61')"
                : 'CREATE VIRTUAL TABLE save_search USING fts4(title, body, summary, details, tokenize=unicode61)',
          );
          await _addPreviewSchema(db);
          await _addNotesSchema(db);
          await _addContentSchema(db);
        },
        onUpgrade: (db, old, _) async {
          if (old < 2) await _addPreviewSchema(db);
          if (old < 3) await _addNotesSchema(db);
          if (old < 4) await _addContentSchema(db);
        },
      ),
    );
    final store = LibraryStore._(database);
    await database.update(
      'saves',
      {
        'status': 'interrupted',
        'error': 'Processing was interrupted. Tap Extract to try again.',
      },
      where: 'status IN (?, ?)',
      whereArgs: ['queued', 'running'],
    );
    return store;
  }

  static Future<void> _addPreviewSchema(Database db) async {
    for (final definition in [
      "description TEXT NOT NULL DEFAULT ''",
      "preview_image TEXT NOT NULL DEFAULT ''",
      "preview_status TEXT NOT NULL DEFAULT 'none'",
      "resolved_url TEXT NOT NULL DEFAULT ''",
      'source_share_id TEXT',
      'auto_title INTEGER NOT NULL DEFAULT 0',
    ]) {
      await db.execute('ALTER TABLE saves ADD COLUMN $definition');
    }
    await db.execute(
      'CREATE UNIQUE INDEX saves_share_receipt ON saves(source_share_id)',
    );
  }

  static Future<void> _addContentSchema(DatabaseExecutor db) async {
    for (final definition in [
      'auto_content INTEGER NOT NULL DEFAULT 0',
      'auto_extract INTEGER NOT NULL DEFAULT 0',
      "content_status TEXT NOT NULL DEFAULT 'none'",
      "content_kind TEXT NOT NULL DEFAULT ''",
    ]) {
      await db.execute('ALTER TABLE saves ADD COLUMN $definition');
    }
    await db.execute(
      "UPDATE saves SET auto_content=1, auto_extract=1, content_status='pending' WHERE url<>'' AND trim(body)=''",
    );
    await db.execute(
      "UPDATE saves SET content_status='ready', content_kind='manual' WHERE trim(body)<>''",
    );
  }

  static Future<void> _addNotesSchema(Database db) async {
    await db.execute(
      "ALTER TABLE saves ADD COLUMN notes TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE saves ADD COLUMN image_status TEXT NOT NULL DEFAULT 'none'",
    );
    await db.execute(
      "UPDATE saves SET image_status=CASE WHEN preview_image<>'' THEN 'ready' WHEN preview_status='pending' THEN 'pending' WHEN preview_status='unavailable' THEN 'unavailable' ELSE 'none' END",
    );
  }

  Future<void> _index(DatabaseExecutor tx, int id) async {
    final row = (await tx.query(
      'saves',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    await tx.delete('save_search', where: 'rowid=?', whereArgs: [id]);
    await tx.rawInsert(
      'INSERT INTO save_search(rowid, title, body, summary, details) VALUES (?, ?, ?, ?, ?)',
      [id, row['title'], row['body'], row['summary'], _searchDetails(row)],
    );
  }

  String _searchDetails(Map<String, Object?> row) {
    var facts = '';
    try {
      facts = ExtractionResult.parse(
        row['extraction'] as String,
        SourceDocument(
          row['extracted_from'] as String,
          typeHint: SaveKind.values
              .byName(row['kind'] as String)
              .extractionType,
        ),
      ).facts.map((f) => f.value).join(' ');
    } catch (_) {
      /* Unprocessed saves still index their links and filenames. */
    }
    return '${row['url']} ${row['file_name']} ${row['description'] ?? ''} ${row['notes'] ?? ''} $facts';
  }

  Future<int> save(SaveDraft draft, {int? id}) async {
    final title = draft.title.trim();
    if (title.isEmpty || title.length > 180) {
      throw const FormatException(
        'Give this save a title of 1–180 characters.',
      );
    }
    if (draft.body.length > 30000 || draft.notes.length > 30000) {
      throw const FormatException(
        'Keep each text field under 30,000 characters.',
      );
    }
    final url = normalizeWebUrl(draft.url);
    return db.transaction((tx) async {
      if (id == null && draft.shareId.isNotEmpty) {
        final existing = await tx.query(
          'saves',
          columns: ['id'],
          where: 'source_share_id=?',
          whereArgs: [draft.shareId],
        );
        if (existing.isNotEmpty) return existing.single['id'] as int;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = <String, Object?>{
        'title': title,
        'body': draft.body.trim(),
        'notes': draft.notes.trim(),
        'image_status': draft.imageStatus,
        'url': url,
        'kind': draft.kind.name,
        'updated_at': now,
        'file_name': draft.fileName,
        'attachment': draft.attachment,
        'description': draft.description,
        'preview_image': draft.previewImage,
        'preview_status': draft.previewStatus,
        'resolved_url': draft.resolvedUrl,
        'auto_title': draft.autoTitle ? 1 : 0,
        'auto_content': draft.automaticContent ? 1 : 0,
        'auto_extract': draft.autoExtract ? 1 : 0,
        'content_status':
            draft.contentKind == 'shared' &&
                draft.automaticContent &&
                url.isNotEmpty &&
                ![
                  'ready',
                  'partial',
                  'unavailable',
                ].contains(draft.contentStatus)
            ? 'pending'
            : draft.body.trim().isNotEmpty
            ? (draft.contentStatus == 'partial' ? 'partial' : 'ready')
            : url.isEmpty || !draft.automaticContent
            ? 'none'
            : draft.contentStatus == 'unavailable'
            ? 'unavailable'
            : 'pending',
        'content_kind': draft.body.trim().isEmpty
            ? ''
            : draft.contentKind.isEmpty
            ? 'manual'
            : draft.contentKind,
        if (id == null)
          'source_share_id': draft.shareId.isEmpty ? null : draft.shareId,
      };
      final int savedId;
      if (id == null) {
        savedId = await tx.insert('saves', {...values, 'created_at': now});
      } else {
        final original = await tx.query(
          'saves',
          where: 'id=?',
          whereArgs: [id],
        );
        if (original.isEmpty) throw StateError('This save no longer exists.');
        if (original.single['body'] != values['body'] ||
            original.single['url'] != url ||
            original.single['kind'] != draft.kind.name) {
          values.addAll({
            'summary': '',
            'extraction': '',
            'extracted_from': '',
            'status': 'idle',
            'error': '',
          });
        }
        await tx.update('saves', values, where: 'id=?', whereArgs: [id]);
        savedId = id;
      }
      await tx.delete('memberships', where: 'save_id=?', whereArgs: [savedId]);
      for (final collection in draft.collectionIds.toSet()) {
        await tx.insert('memberships', {
          'save_id': savedId,
          'collection_id': collection,
        });
      }
      await _index(tx, savedId);
      return savedId;
    });
  }

  Future<List<SavedItem>> query({
    String query = '',
    SaveKind? kind,
    int? collection,
    bool favorites = false,
    int offset = 0,
    int limit = 40,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    final tokens = RegExp(
      r'[\p{L}\p{N}]+',
      unicode: true,
    ).allMatches(query).take(8).map((m) => '"${m.group(0)}"*').toList();
    if (query.trim().isNotEmpty && tokens.isEmpty) return [];
    if (tokens.isNotEmpty) {
      conditions.add(
        's.id IN (SELECT rowid FROM save_search WHERE save_search MATCH ?)',
      );
      // Whitespace is implicit AND in both FTS5 and Android's standard FTS4
      // syntax. An explicit AND is searched as a literal on some Android builds.
      args.add(tokens.join(' '));
    }
    if (kind != null) {
      conditions.add('s.kind=?');
      args.add(kind.name);
    }
    if (collection != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM memberships m WHERE m.save_id=s.id AND m.collection_id=?)',
      );
      args.add(collection);
    }
    if (favorites) conditions.add('s.favorite=1');
    final rows = await db.rawQuery(
      "SELECT s.id, s.title, substr(s.body,1,360) AS body, s.url, s.kind, s.created_at, s.favorite, s.status, substr(s.summary,1,400) AS summary, '' AS extraction, '' AS extracted_from, s.error, s.file_name, s.attachment, substr(s.notes,1,360) AS notes, s.image_status, s.description, s.preview_image, s.preview_status, s.resolved_url, s.auto_title, s.auto_content, s.auto_extract, s.content_status, s.content_kind, 1 AS preview FROM saves s ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'} ORDER BY s.created_at DESC, s.id DESC LIMIT ? OFFSET ?",
      [...args, limit, offset],
    );
    return _hydrate(rows);
  }

  Future<List<SavedItem>> _hydrate(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return [];
    final memberships = await db.rawQuery(
      'SELECT m.save_id, c.id, c.name FROM memberships m JOIN collections c ON c.id=m.collection_id WHERE m.save_id IN (${List.filled(rows.length, '?').join(',')}) ORDER BY c.name',
      rows.map((r) => r['id']).toList(),
    );
    return rows.map((row) {
      final assigned = memberships
          .where((m) => m['save_id'] == row['id'])
          .toList();
      return SavedItem.fromRow({
        ...row,
        'collection_ids': jsonEncode(assigned.map((m) => m['id']).toList()),
        'collection_names': jsonEncode(assigned.map((m) => m['name']).toList()),
      });
    }).toList();
  }

  Future<SavedItem?> get(int id) async {
    final rows = await db.query('saves', where: 'id=?', whereArgs: [id]);
    final items = await _hydrate(rows);
    return items.isEmpty ? null : items.single;
  }

  Future<int?> receivedShare(String receipt) async {
    final rows = await db.query(
      'saves',
      columns: ['id'],
      where: 'source_share_id=?',
      whereArgs: [receipt],
    );
    return rows.isEmpty ? null : rows.single['id'] as int;
  }

  Future<List<SavedItem>> pendingPreviews({
    int? beforeId,
    bool includeUnavailable = false,
  }) async => _hydrate(
    await db.query(
      'saves',
      where:
          "(preview_status='pending' OR image_status='pending' OR content_status='pending'${includeUnavailable ? " OR (auto_content=1 AND content_status='unavailable' AND trim(body)='')" : ''})${beforeId == null ? '' : ' AND id < ?'}",
      whereArgs: beforeId == null ? null : [beforeId],
      orderBy: 'id DESC',
      limit: 16,
    ),
  );

  Future<void> applyPreview(
    int id,
    String url,
    String expectedTitle,
    LinkPreview preview,
  ) => db.transaction((tx) async {
    final rows = await tx.query(
      'saves',
      where: 'id=? AND url=?',
      whereArgs: [id, url],
    );
    if (rows.isEmpty) return;
    final row = rows.single;
    final canFillContent =
        row['auto_content'] == 1 &&
        ((row['body'] as String).trim().isEmpty ||
            row['content_kind'] == 'shared');
    final merged = row['content_kind'] == 'shared' && preview.content.isNotEmpty
        ? mergeSharedContent(row['body'] as String, preview.content)
        : preview.content;
    final sourceStatus = merged.length > 30000
        ? 'partial'
        : merged.isNotEmpty
        ? (preview.contentStatus == 'partial' ? 'partial' : 'ready')
        : (row['body'] as String).trim().isNotEmpty &&
              preview.contentStatus != 'pending'
        ? 'ready'
        : preview.contentStatus;
    await tx.update(
      'saves',
      {
        if (row['auto_title'] == 1 &&
            row['title'] == expectedTitle &&
            preview.title.isNotEmpty)
          'title': preview.title,
        if (preview.description.isNotEmpty) 'description': preview.description,
        if (preview.image.isNotEmpty) 'preview_image': preview.image,
        if (preview.resolvedUrl.isNotEmpty) 'resolved_url': preview.resolvedUrl,
        'preview_status': preview.available || row['preview_status'] == 'ready'
            ? 'ready'
            : 'unavailable',
        'image_status':
            preview.image.isNotEmpty ||
                (row['preview_image'] as String).isNotEmpty
            ? 'ready'
            : preview.imageStatus,
        if (canFillContent) ...{
          'content_status': sourceStatus,
          if (preview.content.isNotEmpty) ...{
            'body': cleanContentText(merged, 30000),
            'content_kind': preview.contentKind,
            if (row['body'] != cleanContentText(merged, 30000)) ...{
              'summary': '',
              'extraction': '',
              'extracted_from': '',
              'status': 'idle',
              'error': '',
            },
          },
        },
        // This flag describes ownership, not whether a lookup has run. Failed
        // requests and later refreshes remain eligible until a user edits it.
      },
      where: 'id=?',
      whereArgs: [id],
    );
    await _index(tx, id);
  });

  Future<int> count() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM saves')) ??
      0;
  Future<List<int>> pendingExtractions({
    int? beforeId,
  }) async => (await db.query(
    'saves',
    columns: ['id'],
    where:
        "auto_extract=1 AND status='idle' AND trim(body)<>''${beforeId == null ? '' : ' AND id < ?'}",
    whereArgs: beforeId == null ? null : [beforeId],
    orderBy: 'id DESC',
    limit: 40,
  )).map((row) => row['id'] as int).toList();
  Future<List<SaveCollection>> collections() async {
    final rows = await db.rawQuery(
      'SELECT c.*, COUNT(m.save_id) AS count, (SELECT s.title FROM saves s JOIN memberships x ON x.save_id=s.id WHERE x.collection_id=c.id ORDER BY s.created_at DESC LIMIT 1) AS preview FROM collections c LEFT JOIN memberships m ON m.collection_id=c.id GROUP BY c.id ORDER BY c.name COLLATE NOCASE',
    );
    return rows
        .map(
          (r) => SaveCollection(
            id: r['id'] as int,
            name: r['name'] as String,
            color: r['color'] as int,
            count: r['count'] as int,
            preview: r['preview'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<int> saveCollection(String name, int color, {int? id}) async {
    if (name.trim().isEmpty || name.trim().length > 40) {
      throw const FormatException('Use a collection name of 1–40 characters.');
    }
    if (id == null) {
      return db.insert('collections', {'name': name.trim(), 'color': color});
    }
    await db.update(
      'collections',
      {'name': name.trim(), 'color': color},
      where: 'id=?',
      whereArgs: [id],
    );
    return id;
  }

  Future<void> deleteCollection(int id) async {
    await db.delete('collections', where: 'id=?', whereArgs: [id]);
  }

  Future<void> favorite(int id, bool value) async {
    await db.update(
      'saves',
      {'favorite': value ? 1 : 0},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> remove(int id) async {
    await db.transaction((tx) async {
      await tx.delete('save_search', where: 'rowid=?', whereArgs: [id]);
      await tx.delete('saves', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<void> status(int id, String status, {String error = ''}) async {
    await db.update(
      'saves',
      {'status': status, 'error': error},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<bool> extraction(
    int id,
    String source,
    String raw,
    ExtractionResult result,
  ) => db.transaction((tx) async {
    final updated = await tx.update(
      'saves',
      {
        'extraction': raw,
        'extracted_from': source,
        'summary': result.summary,
        'status': result.isPartial ? 'partial' : 'complete',
        'error': '',
      },
      where: 'id=? AND body=?',
      whereArgs: [id, source],
    );
    if (updated == 0) return false;
    await _index(tx, id);
    return true;
  });
  Future<String?> preference(String key) async {
    final rows = await db.query(
      'preferences',
      where: 'key=?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> setPreference(String key, String value) async {
    await db.insert('preferences', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() => db.close();
}
