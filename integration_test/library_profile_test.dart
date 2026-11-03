import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/ui/save_detail.dart';
import 'package:linqo/ui/save_editor.dart';
import 'package:linqo/ui/library_shell.dart';
import 'package:linqo/ui/settings_screen.dart';

const recipe =
    '''Ingredients: 1 onion, 3 cloves garlic, 1 can chickpeas, 200 ml coconut milk, spinach.
Dice the onion and mince the garlic.
Sauté the onion and garlic, then add chickpeas and coconut milk.
Simmer for 10 minutes. Stir in the spinach.
Serve with rice.''';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('persistent library browsing during real on-device extraction', (
    tester,
  ) async {
    expect(kProfileMode, isTrue);
    final path = '${await getDatabasesPath()}/linqo-library-qa.db';
    await deleteDatabase(path);
    var store = await LibraryStore.open(path: path);
    var c = LibraryController(store);
    await c.initialize(restoreModel: false);
    final food = await store.saveCollection('The kitchen notebook', 0);
    final places = await store.saveCollection('A little adventure', 2);
    final ideas = await store.saveCollection('Things to come back to', 3);
    final fixture = <SaveDraft>[
      SaveDraft(
        title: 'Creamy chickpea skillet',
        body: recipe,
        kind: SaveKind.recipe,
        collectionIds: [food],
      ),
      SaveDraft(
        title: 'An afternoon on the South Bank',
        body: 'Visit the Tate Modern on Bankside. Walk along the South Bank.',
        url: 'https://www.tate.org.uk/visit/tate-modern',
        kind: SaveKind.place,
        collectionIds: [places],
      ),
      SaveDraft(
        title: 'Coffee, then a long walk',
        body: 'Try a coffee at Monmouth Coffee in Borough Market.',
        url: 'https://www.monmouthcoffee.co.uk',
        kind: SaveKind.place,
        collectionIds: [places],
      ),
      SaveDraft(
        title: 'The little things worth noticing',
        body:
            'Leave a little room in the day for something unplanned. A walk, a book, a different way home.',
        kind: SaveKind.note,
        collectionIds: [ideas],
      ),
      SaveDraft(
        title: 'A weekend pasta idea',
        body:
            'Tomatoes, good olive oil and a little patience. A recipe to try on Saturday.',
        kind: SaveKind.video,
        url: 'https://youtu.be/jNQXAC9IVRw',
        collectionIds: [food],
      ),
      SaveDraft(
        title: 'A quieter kind of reading list',
        body: 'Long reads for a slow Sunday morning.',
        kind: SaveKind.link,
        url: 'https://www.wikipedia.org',
        collectionIds: [ideas],
      ),
    ];
    final ids = <int>[];
    for (final draft in fixture) {
      ids.add(await store.save(draft));
    }
    for (var i = 0; i < 54; i++) {
      await store.save(
        SaveDraft(
          title: 'Example reading note ${i + 1}',
          body:
              'A synthetic test note about design, food and little discoveries.',
          kind: SaveKind.note,
        ),
      );
    }
    // Put the authored examples first while retaining a multi-page library.
    for (final id in ids) {
      await store.db.update(
        'saves',
        {'created_at': DateTime.now().millisecondsSinceEpoch + id},
        where: 'id=?',
        whereArgs: [id],
      );
    }
    await store.favorite(ids.first, true);
    await c.refresh();
    await tester.pumpWidget(LinqoApp(controller: c));
    await tester.pump(const Duration(milliseconds: 500));
    Future<void> settle() async {
      await tester.pumpAndSettle();
    }

    try {
      // Close and reopen the actual SQLite file, using a new controller.
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
      store = await LibraryStore.open(path: path);
      c = LibraryController(store);
      await c.initialize();
      expect(c.total, 60);
      expect(c.collections.length, 3);
      expect((await store.get(ids.first))!.favorite, isTrue);
      binding.reportData = {
        'synthetic_fixtures': true,
        'persistence_after_reopen': true,
        'total_saves': c.total,
      };
      await tester.pumpWidget(LinqoApp(controller: c));
      await settle();
      final ready = Stopwatch()..start();
      while (c.lab.busy) {
        if (ready.elapsed > const Duration(minutes: 2)) {
          throw TimeoutException('Model restore timed out.');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      var qaModelPath = const String.fromEnvironment('LINQO_MODEL_PATH');
      const qaModelUrl = String.fromEnvironment('LINQO_MODEL_URL');
      if (!c.modelAvailable && qaModelUrl.isNotEmpty) {
        final root = await getApplicationSupportDirectory();
        qaModelPath = '${root.path}/qa-source-model.gguf';
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(
            Uri.parse(qaModelUrl),
          )).close();
          expect(response.statusCode, 200);
          await response.pipe(File(qaModelPath).openWrite());
        } finally {
          client.close(force: true);
        }
      }
      if (!c.modelAvailable && qaModelPath.isNotEmpty) {
        await c.lab.importModel(qaModelPath, 'Qwen3-0.6B-Q4_K_M.gguf');
      }
      expect(
        c.modelAvailable,
        isTrue,
        reason:
            'A model is required for real inference test. ${c.lab.error ?? ''}',
      );
      final frames = <FrameTiming>[];
      void onFrames(List<FrameTiming> values) => frames.addAll(values);
      SchedulerBinding.instance.addTimingsCallback(onFrames);
      final run = Stopwatch()..start();
      await c.extract((await store.get(ids.first))!);
      unawaited(
        c.enrichPreview(
          ids[4],
          'https://youtu.be/jNQXAC9IVRw',
          'A weekend pasta idea',
        ),
      );
      binding.reportData!['preview_requested_during_real_inference'] = true;
      await tester.pump(const Duration(milliseconds: 500));
      final queryTimes = <int>[];
      for (final term in ['coffee', 'skillet', 'reading', 'design', 'South']) {
        final watch = Stopwatch()..start();
        await store.query(query: term);
        queryTimes.add(watch.elapsedMilliseconds);
      }
      await tester.fling(
        find.byType(CustomScrollView).first,
        const Offset(0, -650),
        1200,
      );
      await settle();
      await tester.tap(
        find.widgetWithText(NavigationDestination, 'Collections'),
      );
      await settle();
      expect(find.text('The kitchen notebook'), findsOneWidget);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Search'));
      await settle();
      final search = tester.widget<TextField>(
        find.byKey(const ValueKey('library-search')),
      );
      search.controller!.text = 'coffee';
      search.onChanged!('coffee');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Coffee, then a long walk'), findsWidgets);
      binding.reportData!['browsing_while_processing'] = c.processing;
      expect(c.processing, isTrue);
      debugPrint('LINQO_CAPTURE_PROCESSING');
      await tester.pump(const Duration(seconds: 6));
      final timeout = Stopwatch()..start();
      while (c.processing) {
        if (timeout.elapsed > const Duration(minutes: 4)) {
          throw TimeoutException('Extraction timed out.');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      SchedulerBinding.instance.removeTimingsCallback(onFrames);
      final item = (await store.get(ids.first))!;
      expect(item.status, 'complete', reason: item.error);
      expect(item.extraction!.recipe!.steps.length, 4);
      expect(
        (await store.query(query: 'spinach')).any((s) => s.id == item.id),
        isTrue,
      );
      double? p95(Iterable<int> values) {
        final sorted = values.toList()..sort();
        return sorted.isEmpty
            ? null
            : sorted[(sorted.length * .95).ceil() - 1] / 1000;
      }

      binding.reportData!.addAll({
        'query_ms': queryTimes,
        'elapsed_ms_including_interactions': run.elapsedMilliseconds,
        'native_extraction': jsonDecode(c.lab.diagnosticsJson()),
        'recipe_steps': item.extraction!.recipe!.steps.length,
        'ui_p95_ms': p95(frames.map((f) => f.buildDuration.inMicroseconds)),
        'raster_p95_ms': p95(
          frames.map((f) => f.rasterDuration.inMicroseconds),
        ),
        'sampled_frames': frames.length,
        'over_budget_frames': frames
            .where(
              (f) =>
                  f.buildDuration.inMicroseconds > 16700 ||
                  f.rasterDuration.inMicroseconds > 16700,
            )
            .length,
      });
      await c.lab.unload();
      // Exercise an actual save form. Text controllers are set explicitly because
      // profile-mode platform text input was unreliable in earlier device tests.
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      final navigation = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigation.push(
          MaterialPageRoute(builder: (_) => SaveEditor(controller: c)),
        ),
      );
      await settle();
      final noteChip = find.widgetWithText(ChoiceChip, 'Note');
      await tester.ensureVisible(noteChip);
      await tester.tap(noteChip);
      await settle();
      expect(tester.widget<ChoiceChip>(noteChip).selected, isTrue);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields.length, 2);
      fields[0].controller!.text = 'Saved through the real form';
      fields[1].controller!.text = 'A persistent English note.';
      await tester.scrollUntilVisible(
        find.text('Save to Linqo'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(SaveEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await settle();
      await tester.ensureVisible(find.text('Save to Linqo'));
      await settle();
      await tester.tap(find.text('Save to Linqo'));
      await tester.pump();
      final saveWatch = Stopwatch()..start();
      while ((await store.query(query: 'persistent English')).isEmpty &&
          saveWatch.elapsed < const Duration(seconds: 8)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settle();
      expect(
        (await store.query(query: 'persistent English')).single.title,
        'Saved through the real form',
      );
      binding.reportData!['save_form_persisted'] = true;
      await c.remove((await store.query(query: 'persistent English')).single);
      // Capture only after timing the native workload.
      await tester.tap(find.widgetWithText(NavigationDestination, 'Library'));
      await settle();
      tester
          .state<LibraryBrowserState>(find.byType(LibraryBrowser).first)
          .scroll
          .jumpTo(0);
      await settle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 250));
      await binding.takeScreenshot('library-light');
      await tester.tap(
        find.widgetWithText(NavigationDestination, 'Collections'),
      );
      await settle();
      await binding.takeScreenshot('collections-light');
      await tester.tap(find.widgetWithText(NavigationDestination, 'Search'));
      await settle();
      await binding.takeScreenshot('search-light');
      await tester.tap(find.widgetWithText(NavigationDestination, 'Library'));
      await settle();
      unawaited(
        navigation.push(
          MaterialPageRoute(
            builder: (_) => SaveDetail(controller: c, id: item.id),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await binding.takeScreenshot('detail-light');
      navigation.pop();
      await settle();
      await c.appearance(ThemeMode.dark);
      await tester.pump(const Duration(milliseconds: 350));
      await binding.takeScreenshot('library-dark');
      await c.appearance(ThemeMode.light);
      await settle();
      unawaited(
        navigation.push(
          MaterialPageRoute(builder: (_) => SettingsScreen(controller: c)),
        ),
      );
      await settle();
      await binding.takeScreenshot('settings-light');
      navigation.pop();
      await settle();
      unawaited(
        navigation.push(
          MaterialPageRoute(builder: (_) => SaveEditor(controller: c)),
        ),
      );
      await settle();
      await binding.takeScreenshot('editor-light');
      binding.reportData!['app_model_downloaded_automatically'] = false;
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
