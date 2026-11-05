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
import 'package:linqo/inference/local_runtime.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/prototype/lab_controller.dart';
import 'package:linqo/sharing/shared_content.dart';
import 'package:linqo/ui/save_editor.dart';
import 'phone_english_reel_test.dart' show protectedState;

const cookingText = '''Ingredients:
1 onion
3 cloves garlic
1 can chickpeas
200 ml coconut milk
A handful of spinach
Method:
Dice the onion and mince the garlic.
Sauté the onion and garlic, then add chickpeas and coconut milk.
Simmer for 10 minutes. Stir in the spinach.
Serve with rice.''';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('older Android automatic model reliability and responsiveness', (
    tester,
  ) async {
    expect(kProfileMode, isTrue);
    final normal = '${await getDatabasesPath()}/linqo-library.db';
    final before = await protectedState(normal);
    final path =
        '${await getDatabasesPath()}/linqo-redmi-qa-${DateTime.now().millisecondsSinceEpoch}.db';
    final store = await LibraryStore.open(path: path);
    final c = LibraryController(store);
    await c.initialize(restoreModel: false);
    await c.lab.initialize();
    final runs = <Map<String, Object?>>[];
    binding.reportData = {
      'normal_before': before,
      'runs': runs,
      'threads': c.lab.threads,
      'batch': RuntimeSettings.batchSize,
      'micro_batch': RuntimeSettings.microBatchSize,
    };
    Future<void> until(bool Function() done, {int seconds = 180}) async {
      final clock = Stopwatch()..start();
      while (!done()) {
        if (clock.elapsed > Duration(seconds: seconds)) {
          throw TimeoutException(
            'Redmi test exceeded ${seconds}s: ${c.lab.phase} ${c.lab.error}',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<SavedItem> settleRun(int id, String name) async {
      await until(() => c.processing);
      final searchMs = <int>[];
      for (var i = 0; i < 5; i++) {
        final watch = Stopwatch()..start();
        await store.query(query: i.isEven ? 'chickpea' : 'latte');
        searchMs.add(watch.elapsedMilliseconds);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.widgetWithText(NavigationDestination, 'Search'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(find.byType(TextField).first, 'latte');
      await tester.pump(const Duration(milliseconds: 250));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Library'));
      await tester.pump(const Duration(milliseconds: 250));
      await until(() => !c.processing && !c.previewBusy(id));
      final item = (await store.get(id))!;
      runs.add({
        'name': name,
        'status': item.status,
        'error': item.error,
        'caption_characters': item.body.length,
        'content_kind': item.contentKind,
        'summary': item.summary,
        'ingredients': item.extraction?.recipe?.ingredients.length,
        'steps': item.extraction?.recipe?.steps.length,
        'places': item.extraction?.places.map((p) => p.name).toList(),
        'native': c.lab.report?.toJson(),
        'load_ms': c.lab.modelLoadMs,
        'loaded_rss_bytes': c.lab.modelLoadedRssBytes,
        'run_end_rss_bytes': c.lab.runEndRssBytes,
        'idle_rss_bytes': ProcessInfo.currentRss,
        'peak_rss_bytes': ProcessInfo.maxRss,
        'search_ms': searchMs,
        'unloaded': !c.lab.modelLoaded,
      });
      debugPrint('LINQO_REDMi_RUN ${jsonEncode(runs.last)}');
      expect(item.error, isEmpty);
      expect(['partial', 'complete'], contains(item.status));
      expect(c.lab.modelLoaded, isFalse);
      return item;
    }

    try {
      expect(c.compactModelInstalled, isTrue);
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
                id: 'redmi-reel',
                text: 'https://www.instagram.com/reel/DemSJV-plAO/',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Save to Linqo'));
      await until(() => c.total == 1);
      final reelId = (await store.query()).single.id;
      final reel = await settleRun(reelId, 'public_english_reel');
      expect(reel.contentKind, 'caption');
      expect(reel.extraction?.recipe?.ingredients, hasLength(5));
      expect(reel.extraction?.recipe?.steps, isEmpty);
      final recipeId = await c.save(
        const SaveDraft(
          title: 'Chickpea dinner',
          body: cookingText,
          kind: SaveKind.recipe,
          autoExtract: true,
          automaticContent: false,
        ),
      );
      final recipe = await settleRun(recipeId, 'complete_recipe');
      expect(recipe.extraction?.recipe?.steps, hasLength(4));
      expect(recipe.extraction?.recipe?.ingredients, hasLength(5));
      final placesId = await c.save(
        const SaveDraft(
          title: 'London afternoon',
          body:
              'Visit the Tate Modern on Bankside.\nTry coffee at Monmouth Coffee in Borough Market.',
          kind: SaveKind.place,
          autoExtract: true,
          automaticContent: false,
        ),
      );
      final places = await settleRun(placesId, 'named_places');
      expect(places.extraction?.places.length, greaterThanOrEqualTo(2));
      final cancelId = await c.save(
        const SaveDraft(
          title: 'Cancel safely',
          body: cookingText,
          kind: SaveKind.recipe,
          autoExtract: true,
          automaticContent: false,
        ),
      );
      await until(() => c.lab.phase == LabPhase.extracting);
      await tester.pump(const Duration(milliseconds: 150));
      final cancelWatch = Stopwatch()..start();
      await c.stop();
      await until(() => !c.processing, seconds: 45);
      binding.reportData!['prefill_cancel_ms'] =
          cancelWatch.elapsedMilliseconds;
      expect((await store.get(cancelId))!.status, 'cancelled');
      expect(c.lab.modelLoaded, isFalse);
      await c.extract((await store.get(cancelId))!);
      await until(
        () =>
            c.lab.activeFirstOutputMs != null &&
            c.lab.phase == LabPhase.extracting,
      );
      final decodeWatch = Stopwatch()..start();
      await c.background();
      await until(() => !c.processing, seconds: 45);
      binding.reportData!['background_decode_cancel_ms'] =
          decodeWatch.elapsedMilliseconds;
      expect(c.lab.modelLoaded, isFalse);
      expect((await store.get(cancelId))!.status, 'cancelled');
      c.foreground();
      await c.extract((await store.get(cancelId))!);
      final recovered = await settleRun(cancelId, 'after_cancel_reload');
      expect(recovered.extraction?.recipe?.steps, hasLength(4));
      final pressureId = await c.save(
        const SaveDraft(
          title: 'Memory-pressure check',
          body: cookingText,
          kind: SaveKind.recipe,
          autoExtract: true,
          automaticContent: false,
        ),
      );
      await until(() => c.lab.phase == LabPhase.extracting);
      final pressureWatch = Stopwatch()..start();
      debugPrint('LINQO_REDMi_PRESSURE_READY');
      // The host delivers Android's RUNNING_CRITICAL trim-memory signal to
      // this app only; no actual RAM exhaustion or other apps are involved.
      await until(() => !c.processing, seconds: 45);
      await c.memoryPressure();
      binding.reportData!['android_memory_callback_delivery_and_release_ms'] =
          pressureWatch.elapsedMilliseconds;
      expect((await store.get(pressureId))!.status, 'interrupted');
      expect(c.processing, isFalse);
      expect(c.lab.modelLoaded, isFalse);
      final followingId = await c.save(
        const SaveDraft(
          title: 'Automatic after memory warning',
          body: cookingText,
          kind: SaveKind.recipe,
          autoExtract: true,
          automaticContent: false,
        ),
      );
      final following = await settleRun(
        followingId,
        'automatic_after_memory_warning',
      );
      expect(following.extraction?.recipe?.steps, hasLength(4));
      final support = await getApplicationSupportDirectory();
      binding.reportData!['selected_manifest_exists'] = await File(
        '${support.path}/models/selected.json',
      ).exists();
      await binding.takeScreenshot('redmi-library-after-model-checks');
      expect(tester.takeException(), isNull);
    } finally {
      await c.stop();
      await c.lab.whenIdle();
      await until(() => !c.processing, seconds: 45);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
      await deleteDatabase(path);
      final after = await protectedState(normal);
      binding.reportData!['normal_after'] = after;
      binding.reportData!['normal_library_unchanged'] =
          jsonEncode(before) == jsonEncode(after);
      expect(after, before);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
