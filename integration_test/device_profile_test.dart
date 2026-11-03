import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linqo/inference/llama_runtime.dart';
import 'package:linqo/inference/model_store.dart';
import 'package:linqo/prototype/lab_controller.dart';
import 'package:linqo/prototype/lab_screen.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/domain/extraction.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile Linqo on the connected phone', (tester) async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'Run this target with flutter drive --profile.',
    );
    var path = const String.fromEnvironment('LINQO_MODEL_PATH');
    const modelUrl = String.fromEnvironment('LINQO_MODEL_URL');
    const reuseImported = bool.fromEnvironment('LINQO_REUSE_IMPORTED_MODEL');
    if (reuseImported) {
      path = (await ModelStore().restore())!.path;
    }
    if (modelUrl.isNotEmpty) {
      final directory = await getApplicationSupportDirectory();
      path = '${directory.path}/device-test-source.gguf';
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(
          Uri.parse(modelUrl),
        )).close();
        expect(response.statusCode, 200);
        await response.pipe(File(path).openWrite());
      } finally {
        client.close(force: true);
      }
    }
    expect(await File(path).exists(), isTrue);
    final lab = LabController(runtime: LlamaLocalRuntime());
    final runs = <Map<String, dynamic>>[];
    const languageOnly = bool.fromEnvironment('LINQO_LANGUAGE_ONLY');
    const reliabilityOnly = bool.fromEnvironment('LINQO_RELIABILITY_ONLY');
    const management = bool.fromEnvironment('LINQO_MODEL_MANAGEMENT');
    binding.reportData = {
      'runs': runs,
      'build_mode': 'profile',
      'language_only': languageOnly,
      'reliability_only': reliabilityOnly,
      'reused_imported_model': reuseImported,
    };
    await tester.pumpWidget(_DeviceHarness(lab: lab));

    Future<void> waitIdle() async {
      final watch = Stopwatch()..start();
      while (lab.busy) {
        if (watch.elapsed > const Duration(minutes: 5)) {
          throw TimeoutException(
            'Device extraction did not settle in five minutes.',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump();
    }

    var taps = 0;
    Future<void> runFixture(String name, String source) async {
      final chip = source == hindiSample
          ? 'हिन्दी'
          : source == placesSample
          ? 'Places'
          : 'Recipe';
      final sampleButton = find.widgetWithText(ActionChip, chip);
      await tester.ensureVisible(sampleButton);
      await tester.tap(sampleButton);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        source,
      );
      await tester.ensureVisible(find.text('Extract on device'));
      await tester.tap(find.text('Extract on device'));
      await tester.pump(const Duration(milliseconds: 300));
      final check = find.text('Tap check · $taps');
      await tester.ensureVisible(check);
      final interaction = Stopwatch()..start();
      await tester.tap(check);
      await tester.pump();
      interaction.stop();
      taps++;
      expect(find.text('Tap check · $taps'), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 250),
      );
      await tester.pump();
      await waitIdle();
      expect(lab.evidence!.numbered, SourceDocument(source).numbered);
      final result = lab.result;
      final expectedSteps = source == englishSample
          ? <int>[3, 4, 5, 6]
          : source == hindiSample
          ? <int>[3, 4, 5]
          : <int>[];
      final stepIds = result?.recipe?.steps.expand((s) => s.lineIds).toSet();
      final names = result?.places.map((p) => p.name).toSet() ?? <String>{};
      final qualityPassed =
          result != null &&
          !result.isPartial &&
          (expectedSteps.isEmpty ||
              (result.type == 'recipe' &&
                  result.recipe!.ingredients.length == 1 &&
                  result.recipe!.ingredients.single.lineIds.single == 2 &&
                  result.recipe!.steps.length == expectedSteps.length)) &&
          (expectedSteps.isEmpty ||
              expectedSteps.every((id) => stepIds?.contains(id) ?? false)) &&
          (source != placesSample ||
              (result.type == 'place' &&
                  result.recipe == null &&
                  <String>[
                    'Monmouth Coffee',
                    'Tate Modern',
                    'South Bank',
                  ].every(names.contains))) &&
          (source != hindiSample ||
              result.recipe!.ingredients.any((f) => f.value.contains('रस।')));
      runs.add({
        'fixture': name,
        'source_verified': true,
        'diagnostics': jsonDecode(lab.diagnosticsJson()),
        'synthetic_tap_dispatch_and_pump_ms': interaction.elapsedMilliseconds,
        'tap_confirmed': true,
        'error': lab.error,
        'title': lab.result?.title,
        'summary': lab.result?.summary,
        'quality_passed': qualityPassed,
        'warnings': result?.warnings,
        'recipe_steps': result?.recipe?.steps
            .map((f) => {'value': f.value, 'lines': f.lineIds})
            .toList(),
        'place_entities': result?.places
            .map((p) => {'name': p.name, 'lines': p.lineIds})
            .toList(),
        'facts': lab.result?.facts
            .map(
              (f) => {'label': f.label, 'value': f.value, 'lines': f.lineIds},
            )
            .toList(),
        'raw_output_on_failure': lab.result == null ? lab.rawOutput : null,
      });
      debugPrint('LINQO_RUN ${jsonEncode(runs.last)}');
    }

    try {
      if (management) {
        final importing = lab.importModel(path, 'Cancelled replacement.gguf');
        await tester.pump(const Duration(milliseconds: 100));
        final cancelWatch = Stopwatch()..start();
        lab.cancel();
        await waitIdle();
        await importing;
        binding.reportData!['import_cancel_ms'] =
            cancelWatch.elapsedMilliseconds;
        expect(lab.phase, LabPhase.cancelled);
        expect((await ModelStore().restore())!.path, path);
        binding.reportData!['cancelled_import_preserved_selection'] = true;
      }
      final importWatch = Stopwatch()..start();
      await lab.importModel(path, 'Qwen3-1.7B-Q4_K_M.gguf');
      binding.reportData!['import_ms'] = importWatch.elapsedMilliseconds;
      expect(lab.error, isNull);
      expect(
        lab.model!.sha256,
        'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897',
      );
      if (management) {
        final restored = LabController(runtime: LlamaLocalRuntime());
        final restoreWatch = Stopwatch()..start();
        await restored.initialize();
        binding.reportData!['restore_ms'] = restoreWatch.elapsedMilliseconds;
        expect(restored.error, isNull);
        expect(restored.model!.path, lab.model!.path);
        expect(restored.model!.sha256, lab.model!.sha256);
        expect(restored.modelLoaded, isFalse);
        expect(restored.threads, 2);
        restored.dispose();
        binding.reportData!['selection_restored_without_loading'] = true;
      }
      await lab.load();
      expect(lab.modelLoaded, isTrue, reason: lab.error);
      binding.reportData!['cold_load_ms'] = lab.modelLoadMs;
      binding.reportData!['loaded_rss_bytes'] = ProcessInfo.currentRss;
      await tester.pump();
      if (management) {
        final prefill = lab.extract(englishSample);
        await tester.pump(const Duration(milliseconds: 700));
        expect(lab.activeFirstOutputMs, isNull);
        final stopWatch = Stopwatch()..start();
        lab.cancel();
        await waitIdle();
        await prefill;
        binding.reportData!['prefill_cancel_ms'] =
            stopWatch.elapsedMilliseconds;
        expect(lab.phase, LabPhase.cancelled);
        expect(lab.result, isNull);
      }
      if (!languageOnly) await runFixture('english_2_threads', englishSample);
      await runFixture('hindi_2_threads', hindiSample);
      await runFixture('places_2_threads', placesSample);
      if (management) {
        final generation = lab.extract(englishSample);
        final firstOutputWatch = Stopwatch()..start();
        while (lab.activeFirstOutputMs == null && lab.busy) {
          if (firstOutputWatch.elapsed > const Duration(minutes: 2)) {
            throw TimeoutException('No first output for cancellation test.');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(lab.activeFirstOutputMs, isNotNull);
        final stopWatch = Stopwatch()..start();
        lab.cancel();
        await waitIdle();
        await generation;
        binding.reportData!['decode_cancel_ms'] = stopWatch.elapsedMilliseconds;
        expect(lab.phase, LabPhase.cancelled);
        expect(lab.result, isNull);
        await runFixture('english_after_cancel', englishSample);
        await lab.releaseMemory();
        binding.reportData!['released_rss_bytes'] = ProcessInfo.currentRss;
        expect(lab.modelLoaded, isFalse);
        expect(lab.model, isNotNull);
        binding.reportData!['release_preserved_selection'] = true;
      }

      if (!languageOnly && !reliabilityOnly) {
        await lab.unload();
        binding.reportData!['unloaded_rss_bytes'] = ProcessInfo.currentRss;
        lab.threads = 1;
        await lab.load();
        expect(lab.modelLoaded, isTrue, reason: lab.error);
        await runFixture('english_1_thread', englishSample);

        final cancelled = lab.extract(englishSample);
        await tester.pump(const Duration(milliseconds: 700));
        final cancelWatch = Stopwatch()..start();
        lab.cancel();
        await waitIdle();
        await cancelled;
        binding.reportData!['cancellation_ms'] =
            cancelWatch.elapsedMilliseconds;
        binding.reportData!['cancellation_phase'] = lab.phase.name;
        expect(lab.phase, LabPhase.cancelled);
        expect(lab.result, isNull);

        await lab.unload();
        lab.threads = 2;
        await lab.load();
        await runFixture('english_after_cancel_reload', englishSample);
      }
      // Screenshot conversion runs after benchmarks because it changes the surface.
      await tester.ensureVisible(find.text('Your saves.\nYour device.'));
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 200));
      await binding.takeScreenshot('phone-light');
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark').last);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('phone-dark');
      await lab.unload();
      binding.reportData!['final_unloaded_rss_bytes'] = ProcessInfo.currentRss;
      expect(
        runs.every(
          (run) =>
              run['error'] == null &&
              run['quality_passed'] == true &&
              (run['diagnostics']
                      as Map<String, dynamic>)['report']['outcome'] ==
                  'complete' &&
              run['title'] != null,
        ),
        isTrue,
        reason:
            'Some fixtures failed; inspect build/device-profile/results.json.',
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      lab.dispose();
      if (modelUrl.isNotEmpty && await File(path).exists()) {
        await File(path).delete();
      }
      if (reuseImported) {
        final directory = await getApplicationSupportDirectory();
        final bootstrap = File('${directory.path}/device-test-source.gguf');
        if (await bootstrap.exists()) await bootstrap.delete();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}

class _DeviceHarness extends StatefulWidget {
  const _DeviceHarness({required this.lab});
  final LabController lab;
  @override
  State<_DeviceHarness> createState() => _DeviceHarnessState();
}

class _DeviceHarnessState extends State<_DeviceHarness> {
  ThemeMode mode = ThemeMode.light;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: linqoTheme(Brightness.light),
    darkTheme: linqoTheme(Brightness.dark),
    themeMode: mode,
    home: LabScreen(
      controller: widget.lab,
      themeMode: mode,
      onThemeChanged: (value) => setState(() => mode = value),
    ),
  );
}
