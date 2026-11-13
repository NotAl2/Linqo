import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/sharing/shared_content.dart';
import 'package:linqo/ui/save_editor.dart';
import 'package:linqo/ui/save_detail.dart';

/// Read-only fingerprints never export the user's original save contents.
Future<Map<String, Object?>> protectedState(String databasePath) async {
  final db = await openDatabase(
    databasePath,
    readOnly: true,
    singleInstance: false,
  );
  final state = <String, Object?>{};
  try {
    for (final table in [
      'saves',
      'collections',
      'memberships',
      'preferences',
    ]) {
      final order = switch (table) {
        'memberships' => 'save_id, collection_id',
        'preferences' => 'key',
        _ => 'id',
      };
      final rows = await db.query(table, orderBy: order);
      state[table] = {
        'count': rows.length,
        'sha256': sha256.convert(utf8.encode(jsonEncode(rows))).toString(),
      };
    }
  } finally {
    await db.close();
  }
  final root = await getApplicationSupportDirectory();
  final file = File('${root.path}/models/selected.json');
  if (!await file.exists()) {
    state['model_selection_sha256'] = null;
    return state;
  }
  final manifest = jsonDecode(await file.readAsString()) as Map;
  final selected = {
    for (final key in ['file', 'name', 'bytes', 'sha256']) key: manifest[key],
  };
  state['model_selection_sha256'] = sha256
      .convert(utf8.encode(jsonEncode(selected)))
      .toString();
  return state;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'real English reel caption and automatic native extraction preserve normal library',
    (tester) async {
      expect(kProfileMode, isTrue);
      const url = String.fromEnvironment('LINQO_COOKING_REEL');
      expect(Uri.parse(url).host, 'www.instagram.com');
      final databaseRoot = await getDatabasesPath();
      final normal = '$databaseRoot/linqo-library.db';
      final support = await getApplicationSupportDirectory();
      final backup = Directory(
        '${support.path}/device-test-backups/english-reel-${DateTime.now().millisecondsSinceEpoch}',
      );
      await backup.create(recursive: true);
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$normal$suffix');
        if (await file.exists()) {
          await file.copy('${backup.path}/linqo-library.db$suffix');
        }
      }
      final manifest = File('${support.path}/models/selected.json');
      if (await manifest.exists()) {
        await manifest.copy('${backup.path}/selected.json');
      }
      final before = await protectedState(normal);
      binding.reportData = {
        'normal_before': before,
        'private_backup_created': true,
      };
      final qaPath =
          '$databaseRoot/linqo-phone-english-${DateTime.now().millisecondsSinceEpoch}.db';
      final store = await LibraryStore.open(path: qaPath);
      final c = LibraryController(store);
      await c.initialize(restoreModel: false);
      await c.lab.initialize();
      try {
        expect(
          c.modelAvailable,
          isTrue,
          reason:
              'An existing selected model is required; nothing is downloaded.',
        );
        binding.reportData!.addAll({
          'model_name': c.lab.model!.name,
          'model_bytes': c.lab.model!.bytes,
          'threads': c.lab.threads,
        });
        await tester.pumpWidget(LinqoApp(controller: c, enableSharing: false));
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => SaveEditor(
                controller: c,
                shared: const SharedContent(
                  id: 'phone-english-reel-qa',
                  text: url,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Save to Linqo'));
        final clock = Stopwatch()..start();
        while ((await store.count()) == 0 &&
            clock.elapsed < const Duration(seconds: 15)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(await store.count(), 1);
        final id = (await store.query()).single.id;
        while (clock.elapsed < const Duration(seconds: 120)) {
          final item = (await store.get(id))!;
          if (item.body.isNotEmpty && c.processing) break;
          if (['failed', 'complete', 'partial'].contains(item.status) &&
              !c.processing) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        final source = (await store.get(id))!;
        binding.reportData!.addAll({
          'caption_characters': source.body.length,
          'content_kind': source.contentKind,
          'automatic_requested': source.autoExtract,
          'processing_seen': c.processing,
        });
        expect(source.body, isNotEmpty);
        expect(source.contentKind, 'caption');
        expect(source.notes, isEmpty);
        // Read the local search index while native work runs.
        expect((await store.query(query: 'latte')).single.id, id);
        await tester.tap(find.widgetWithText(NavigationDestination, 'Search'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.enterText(find.byType(TextField).first, 'latte');
        await tester.pump(const Duration(milliseconds: 350));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot('phone-english-reel-search');
        while ((c.processing || c.previewBusy(id)) &&
            clock.elapsed < const Duration(seconds: 180)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final result = (await store.get(id))!;
        final extracted = result.extraction;
        binding.reportData!.addAll({
          'status': result.status,
          'error': result.error,
          'summary': result.summary,
          'extraction_type': extracted?.type,
          'ingredients': extracted?.recipe?.ingredients
              .map((i) => i.value)
              .toList(),
          'steps': extracted?.recipe?.steps.map((i) => i.value).toList(),
          'warnings': extracted?.warnings,
          'run': c.lab.report?.toJson(),
          'model_unloaded_after_queue': !c.lab.modelLoaded,
        });
        expect(c.processing, isFalse);
        expect(result.summary, isNotEmpty, reason: result.error);
        expect(extracted?.type, 'recipe');
        expect(extracted!.recipe!.ingredients, hasLength(5));
        // This real caption supplies ingredients only. Missing steps must be
        // reported instead of invented from the unseen video.
        expect(extracted.recipe!.steps, isEmpty);
        expect(extracted.warnings, isNotEmpty);
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => SaveDetail(controller: c, id: id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('The useful details'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await binding.takeScreenshot('phone-english-reel-result');
        expect(tester.takeException(), isNull);
      } finally {
        await c.stop();
        await c.lab.whenIdle();
        final cleanup = Stopwatch()..start();
        while (c.processing && cleanup.elapsed < const Duration(seconds: 30)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await store.close();
        await deleteDatabase(qaPath);
        final after = await protectedState(normal);
        binding.reportData!['normal_after'] = after;
        binding.reportData!['normal_library_unchanged'] =
            jsonEncode(before) == jsonEncode(after);
        expect(
          after,
          before,
          reason:
              'Normal saves, collections, settings and model selection must remain unchanged.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
