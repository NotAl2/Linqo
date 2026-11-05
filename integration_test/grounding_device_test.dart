import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/sharing/shared_content.dart';
import 'package:linqo/ui/save_editor.dart';
import 'package:linqo/ui/save_detail.dart';
import 'package:linqo/ui/settings_screen.dart';
import 'package:linqo/inference/model_store.dart';
import 'redmi_device_test.dart' show cookingText;
import 'phone_english_reel_test.dart' show protectedState;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('grounded sources, long article and model recovery on Redmi', (
    tester,
  ) async {
    expect(kProfileMode, isTrue);
    final recovery = File(
      '${(await getApplicationSupportDirectory()).path}/device-test-backups/grounding-model/restore.gguf',
    );
    final models = ModelStore();
    if (await models.restore() == null && await recovery.exists()) {
      await models.import(recovery.path, 'Qwen3-0.6B-Q4_K_M.gguf');
    }
    final normal = '${await getDatabasesPath()}/linqo-library.db';
    final before = await protectedState(normal);
    final path =
        '${await getDatabasesPath()}/linqo-grounding-qa-${DateTime.now().millisecondsSinceEpoch}.db';
    final store = await LibraryStore.open(path: path);
    final c = LibraryController(store);
    await c.initialize(restoreModel: false);
    await c.lab.initialize();
    final modelBefore = c.lab.model!;
    expect(
      c.compactModelInstalled,
      isTrue,
      reason: 'Do not replace a custom user model in this test.',
    );
    final runs = <Map<String, Object?>>[];
    binding.reportData = {
      'runs': runs,
      'normal_before': before,
      'threads': c.lab.threads,
    };
    Future<void> until(bool Function() ready, {int seconds = 300}) async {
      final watch = Stopwatch()..start();
      while (!ready()) {
        if (watch.elapsed > Duration(seconds: seconds)) {
          throw TimeoutException(
            'Device check timed out: ${c.lab.phase} ${c.lab.error}',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<SavedItem> finish(int id, String name) async {
      await until(() => c.processing);
      final queryTimes = <int>[];
      for (var i = 0; i < 4; i++) {
        final watch = Stopwatch()..start();
        await store.query(query: 'local');
        queryTimes.add(watch.elapsedMilliseconds);
        await tester.pump(const Duration(milliseconds: 150));
      }
      await until(() => !c.processing && !c.previewBusy(id), seconds: 600);
      final item = (await store.get(id))!;
      expect(item.error, isEmpty);
      expect(item.extraction, isNotNull);
      expect(item.summary, isNotEmpty);
      for (final excerpt in item.summary.split(' … ')) {
        expect(
          item.body.contains(excerpt),
          isTrue,
          reason: 'Every highlight must be an original source span.',
        );
      }
      runs.add({
        'name': name,
        'characters': item.body.length,
        'parts': c.lab.totalParts,
        'status': item.status,
        'type': item.extraction?.type,
        'warnings': item.extraction?.warnings,
        'coverage': jsonDecode(item.extractionJson),
        'summary_grounded': true,
        'native': c.lab.report?.toJson(),
        'search_ms': queryTimes,
        'peak_rss_bytes': ProcessInfo.maxRss,
        'idle_rss_bytes': ProcessInfo.currentRss,
        'unloaded': !c.lab.modelLoaded,
      });
      debugPrint('LINQO_GROUNDED_RUN ${jsonEncode(runs.last)}');
      expect(c.lab.modelLoaded, isFalse);
      return item;
    }

    File? temporarilyMoved;
    File? safetyCopy;
    String? originalPath;
    try {
      await tester.pumpWidget(LinqoApp(controller: c, enableSharing: false));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      final recipeId = await c.save(
        const SaveDraft(
          title: 'Chickpea dinner',
          body: cookingText,
          kind: SaveKind.recipe,
          automaticContent: false,
          autoExtract: true,
        ),
      );
      final recipe = await finish(recipeId, 'recipe_no_invented_summary');
      expect(recipe.summary, isNot(contains('spiced')));
      expect(recipe.extraction!.recipe!.steps, hasLength(4));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => SaveEditor(
              controller: c,
              shared: const SharedContent(
                id: 'grounded-real-article',
                text: 'https://share.google/cxSheI4Fi2EKxpSgE',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Save to Linqo'));
      await until(() => c.total == 2);
      final articleId = (await store.query()).first.id;
      final article = await finish(
        articleId,
        'user_exact_google_share_article',
      );
      expect(article.body.length, greaterThan(4000));
      expect(c.lab.totalParts, greaterThan(1));
      expect(article.status, 'complete');
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => SaveDetail(controller: c, id: articleId),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Summary · excerpts from your saved text'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('grounded-user-article-summary');
      nav.pop();
      await tester.pumpAndSettle();
      final cancelId = await c.save(
        SaveDraft(
          title: 'Cancel long article',
          body: article.body,
          kind: SaveKind.link,
          automaticContent: false,
          autoExtract: true,
        ),
      );
      await until(() => c.lab.currentPart >= 2 && c.processing);
      final cancel = Stopwatch()..start();
      await c.stop();
      await until(() => !c.processing, seconds: 45);
      binding.reportData!['multi_part_cancel_ms'] = cancel.elapsedMilliseconds;
      expect((await store.get(cancelId))!.status, 'cancelled');
      expect((await store.get(cancelId))!.body, article.body);
      originalPath = c.lab.model!.path;
      temporarilyMoved = await File(
        originalPath,
      ).rename('$originalPath.hidden-qa');
      await c.recheckModel();
      expect(c.modelAvailable, isFalse);
      binding.reportData!['missing_file_detected'] = true;
      await temporarilyMoved.rename(originalPath);
      temporarilyMoved = null;
      await c.recheckModel();
      expect(c.compactModelInstalled, isTrue);
      binding.reportData!['lost_manifest_recovered'] = true;
      final privateRoot = await getApplicationSupportDirectory();
      final safetyRoot = await Directory(
        '${privateRoot.path}/device-test-backups/grounding-model',
      ).create(recursive: true);
      safetyCopy = await File(
        c.lab.model!.path,
      ).copy('${safetyRoot.path}/restore.gguf');
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete model'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Delete model'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete model'),
        ),
      );
      await until(() => !c.modelManagementBusy && !c.modelAvailable);
      await tester.pumpAndSettle();
      final support = await getApplicationSupportDirectory();
      expect(
        await Directory(
          '${support.path}/models',
        ).list().where((f) => f.path.endsWith('.gguf')).length,
        0,
      );
      binding.reportData!['delete_model_ui_verified'] = true;
      await tester.scrollUntilVisible(
        find.text('Download English model · 397 MB'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Download English model · 397 MB')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download English model · 397 MB'));
      await until(
        () => c.compactModelInstalled && !c.download.busy,
        seconds: 300,
      );
      expect(c.lab.model!.sha256, modelBefore.sha256);
      expect(c.lab.model!.bytes, modelBefore.bytes);
      binding.reportData!['redownload_verified_sha256'] = true;
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Already installed'),
        -150,
        scrollable: find.byType(Scrollable).last,
      );
      await binding.takeScreenshot('grounded-redownload-installed');
      nav.pop();
      await tester.pumpAndSettle();
      final lastId = await c.save(
        const SaveDraft(
          title: 'After redownload',
          body: cookingText,
          kind: SaveKind.recipe,
          automaticContent: false,
          autoExtract: true,
        ),
      );
      await finish(lastId, 'automatic_after_redownload');
      expect(tester.takeException(), isNull);
    } finally {
      if (temporarilyMoved != null && await temporarilyMoved.exists()) {
        await temporarilyMoved.rename(originalPath!);
      }
      if (c.download.busy) {
        c.download.pause();
        await until(() => !c.download.busy, seconds: 50);
      }
      await c.stop();
      await c.lab.whenIdle();
      await until(() => !c.processing, seconds: 45);
      if (safetyCopy != null && await safetyCopy.exists()) {
        if (c.lab.model?.sha256 != modelBefore.sha256) {
          await c.lab.importModel(safetyCopy.path, modelBefore.name);
          await c.download.discard();
        }
        expect(c.lab.model?.sha256, modelBefore.sha256);
        await safetyCopy.delete();
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
      await deleteDatabase(path);
      final after = await protectedState(normal);
      before.remove('model_selection_sha256');
      after.remove('model_selection_sha256');
      binding.reportData!['normal_after'] = after;
      binding.reportData!['normal_library_unchanged'] =
          jsonEncode(before) == jsonEncode(after);
      expect(after, before);
    }
  }, timeout: const Timeout(Duration(minutes: 22)));
}
