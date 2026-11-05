import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/services/update_checker.dart';
import 'package:linqo/services/diagnostics.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';

void main() {
  sqfliteFfiInit();
  test(
    'uncaught marker is synchronous, sanitized and clearable after restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('linqo-crash-');
      final d = Diagnostics(directory: dir);
      final restored = Diagnostics(directory: dir);
      try {
        await d.initialize();
        await d.setEnabled(true);
        d.recordFatal('dart.uncaught', error: StateError('private caption'));
        final file = File('${dir.path}/events.json.crash');
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), isNot(contains('private caption')));
        await restored.initialize();
        expect(
          restored.events.any((e) => e['code'] == 'dart.uncaught'),
          isTrue,
        );
        await restored.clear();
        expect(file.existsSync(), isFalse);
        await d.setEnabled(false);
      } finally {
        d.dispose();
        restored.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'release selection uses semantic versions and trusted APK release pages',
    () {
      Map<String, dynamic> release(
        String tag, {
        bool preview = false,
        String? page,
      }) => {
        'tag_name': tag,
        'draft': false,
        'prerelease': preview,
        'html_url': page ?? 'https://github.com/NotAl2/Linqo/releases/tag/$tag',
        'assets': [
          {'name': 'Linqo-$tag-android-arm64.apk', 'state': 'uploaded'},
        ],
      };
      final rows = [
        release('v0.8.0'),
        release('v0.9.0', preview: true),
        release('v0.10.0'),
        release('v99.0.0', page: 'https://evil.example/update'),
      ];
      expect(UpdateChecker.select(rows, '0.8.0')!.version, 'v0.10.0');
      expect(
        UpdateChecker.select(
          [release('v0.9.0', preview: true)],
          '0.8.0',
          previews: false,
        ),
        isNull,
      );
      expect(UpdateChecker.select([release('v0.8.0')], '0.8.0'), isNull);
      expect(
        UpdateChecker.select([release('v0.9.0')..['draft'] = true], '0.8.0'),
        isNull,
      );
    },
  );
  test(
    'diagnostics are opt-in, bounded and never retain error messages',
    () async {
      final dir = await Directory.systemTemp.createTemp('linqo-diagnostics-');
      final d = Diagnostics(directory: dir);
      try {
        d.record('disabled');
        expect(d.events, isEmpty);
        await d.setEnabled(true);
        for (var i = 0; i < 120; i++) {
          d.record(
            'model.failed',
            error: StateError('secret saved caption https://private.example'),
          );
        }
        expect(d.events.length, 100);
        expect(d.export(), isNot(contains('secret saved caption')));
        expect(d.export(), isNot(contains('private.example')));
        await d.setEnabled(false);
        final restored = Diagnostics(directory: dir);
        await restored.initialize();
        expect(restored.enabled, isFalse);
        expect(restored.events, isEmpty);
        restored.dispose();
      } finally {
        d.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('library has no paid save or collection limits', () async {
    final store = await LibraryStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    try {
      for (var i = 0; i < 60; i++) {
        await store.save(SaveDraft(title: 'Save $i', kind: SaveKind.note));
      }
      for (var i = 0; i < 8; i++) {
        await store.saveCollection('Collection $i', 0);
      }
      expect(
        (await store.db.rawQuery(
          'SELECT COUNT(*) AS n FROM saves',
        )).single['n'],
        60,
      );
      expect((await store.collections()).length, 8);
    } finally {
      await store.close();
    }
  });
}
