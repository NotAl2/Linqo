import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/inference/local_runtime.dart';
import 'package:linqo/inference/model_store.dart';
import 'package:linqo/prototype/lab_controller.dart';
import 'package:linqo/prototype/lab_screen.dart';
import 'package:linqo/theme.dart';

class TestRuntime implements LocalRuntime {
  final output = StreamController<String>();
  int calls = 0;
  bool cancelled = false;
  int unloads = 0;
  int loads = 0;
  int disposals = 0;
  Completer<void>? pendingLoad;
  Completer<void>? pendingUnload;
  @override
  Future<void> load(String path, RuntimeSettings settings) async {
    loads++;
    expect(settings.threads, 2);
    await pendingLoad?.future;
  }

  @override
  Stream<String> extract(SourceDocument source) {
    calls++;
    return output.stream;
  }

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Future<void> unload() async {
    unloads++;
    await pendingUnload?.future;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _RestoreFailureStore extends ModelStore {
  @override
  Future<ImportedModel?> restore() async =>
      throw const FormatException('damaged model');
}

class _UnloadFailureRuntime extends TestRuntime {
  @override
  Future<void> unload() async => throw StateError('cleanup failed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestRuntime runtime;
  late LabController controller;
  test(
    'failed model restore and unload leave operations recoverable',
    () async {
      final lab =
          LabController(
              runtime: _UnloadFailureRuntime(),
              modelStore: _RestoreFailureStore(),
            )
            ..selectionManaged = true
            ..modelLoaded = true;
      await lab.refreshModel();
      expect(lab.phase, LabPhase.failed);
      expect(lab.busy, false);
      expect(lab.modelLoaded, false);
      await lab.refreshModel();
      expect(lab.busy, false);
      lab.dispose();
    },
  );
  setUp(() {
    runtime = TestRuntime();
    controller = LabController(runtime: runtime);
    controller.model = const ImportedModel(
      path: '/test.gguf',
      name: 'test.gguf',
      bytes: 100,
      sha256: 'test',
    );
    controller.modelLoaded = true;
  });
  tearDown(() {
    controller.dispose();
  });

  test('cancel before copying starts retains the previous selection', () async {
    runtime.pendingUnload = Completer<void>();
    final importing = controller.importModel('/not-read.gguf', 'replacement');
    controller.cancel();
    runtime.pendingUnload!.complete();
    await importing;
    expect(controller.phase, LabPhase.cancelled);
    expect(controller.model!.name, 'test.gguf');
    expect(controller.error, isNull);
  });

  test('load error after cancellation is reported as cancelled', () async {
    controller.modelLoaded = false;
    runtime.pendingLoad = Completer<void>();
    final loading = controller.load();
    controller.cancel();
    runtime.pendingLoad!.completeError(StateError('load stopped'));
    await loading;
    expect(controller.phase, LabPhase.cancelled);
    expect(controller.modelLoaded, isFalse);
    expect(controller.error, isNull);
  });

  test(
    'cancel during load discards the completed context and permits retry',
    () async {
      controller.modelLoaded = false;
      runtime.pendingLoad = Completer<void>();
      final loading = controller.load();
      controller.cancel();
      expect(controller.phase, LabPhase.cancelling);
      expect(controller.canExtract, isFalse);
      runtime.pendingLoad!.complete();
      await loading;
      expect(controller.modelLoaded, isFalse);
      expect(controller.phase, LabPhase.cancelled);
      expect(runtime.unloads, 1);
      runtime.pendingLoad = null;
      await controller.load();
      expect(controller.modelLoaded, isTrue);
    },
  );

  test(
    'memory release drains active generation before unloading and retains selection',
    () async {
      final extracting = controller.extract('Test evidence.');
      await Future<void>.delayed(Duration.zero);
      final release = controller.releaseMemory();
      expect(runtime.cancelled, isTrue);
      expect(runtime.unloads, 0);
      expect(controller.canExtract, isFalse);
      await runtime.output.close();
      await extracting;
      await release;
      expect(runtime.unloads, 1);
      expect(controller.modelLoaded, isFalse);
      expect(controller.model, isNotNull);
      expect(controller.result, isNull);
    },
  );

  test('memory pressure while loading never publishes a ready model', () async {
    controller.modelLoaded = false;
    runtime.pendingLoad = Completer<void>();
    final loading = controller.load();
    final release = controller.releaseMemory();
    runtime.pendingLoad!.complete();
    await loading;
    await release;
    expect(controller.modelLoaded, isFalse);
    expect(runtime.unloads, 1);
  });

  test(
    'native error after cancellation stays cancelled and can be unloaded',
    () async {
      final extracting = controller.extract('Test evidence.');
      await Future<void>.delayed(Duration.zero);
      controller.cancel();
      runtime.output.addError(StateError('native cancellation'));
      await runtime.output.close();
      await extracting;
      expect(controller.phase, LabPhase.cancelled);
      expect(controller.error, isNull);
      expect(controller.result, isNull);
      await controller.unload();
      expect(controller.modelLoaded, isFalse);
    },
  );

  test(
    'single-flight extraction and cancellation never publish partial facts',
    () async {
      final first = controller.extract('Test evidence.');
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        controller.extract('Another source.'),
        throwsStateError,
      );
      expect(controller.evidence!.text, 'Test evidence.');
      expect(runtime.calls, 1);
      runtime.output.add('{"title":');
      controller.cancel();
      await runtime.output.close();
      await first;
      expect(runtime.cancelled, isTrue);
      expect(controller.phase, LabPhase.cancelled);
      expect(controller.result, isNull);
      expect(controller.report!.outcome, 'cancelled');
    },
  );

  test(
    'successful result excludes content from exported diagnostics',
    () async {
      final pending = controller.extract('Private ingredient.');
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        controller.extract('Another source.'),
        throwsStateError,
      );
      expect(controller.evidence!.text, 'Private ingredient.');
      runtime.output.add(
        jsonEncode({
          'title': 'Private dish',
          'summary': 'Private ingredient.',
          'type': 'general',
          'facts': [
            {
              'label': 'Ingredient',
              'value': 'Private ingredient.',
              'lines': [1],
            },
          ],
        }),
      );
      await runtime.output.close();
      await pending;
      expect(controller.phase, LabPhase.complete);
      expect(controller.evidence!.text, contains('Private ingredient.'));
      expect(controller.diagnosticsJson(), isNot(contains('Private')));
    },
  );

  test('oversized input is rejected rather than truncated', () async {
    await controller.extract('x' * 30001);
    expect(runtime.calls, 0);
    expect(controller.error, contains('30,000'));
  });

  for (final rejection in ['oversized', 'busy', 'unloaded']) {
    test(
      '$rejection retry cannot silently reuse the previous result',
      () async {
        final pending = controller.extract('Private ingredient.');
        runtime.output.add(
          jsonEncode({
            'title': 'Previous save',
            'summary': 'Previous content.',
            'type': 'general',
            'facts': [
              {
                'label': 'Fact',
                'value': 'Private ingredient.',
                'lines': [1],
              },
            ],
          }),
        );
        await runtime.output.close();
        await pending;
        expect(controller.result, isNotNull);
        if (rejection == 'busy') controller.phase = LabPhase.restoring;
        if (rejection == 'unloaded') controller.modelLoaded = false;
        if (rejection != 'oversized') {
          final previousResult = controller.result;
          final previousEvidence = controller.evidence;
          await expectLater(
            controller.extract('New source.'),
            throwsStateError,
          );
          expect(controller.result, same(previousResult));
          expect(controller.evidence, same(previousEvidence));
          return;
        }
        await controller.extract(
          rejection == 'oversized' ? 'x' * 30001 : 'New source.',
        );
        expect(controller.result, isNull);
        expect(controller.report, isNull);
        expect(controller.evidence, isNull);
        expect(controller.rawOutput, isEmpty);
      },
    );
  }

  testWidgets('phone and tablet layouts support light, dark and large text', (
    tester,
  ) async {
    for (final size in [const Size(360, 800), const Size(1024, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: linqoTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: LabScreen(
                controller: controller,
                themeMode: ThemeMode.system,
                onThemeChanged: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Linqo'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '$size / $brightness / $scale',
          );
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('reduced motion removes indeterminate progress animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: linqoTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: LabScreen(
          controller: controller,
          themeMode: ThemeMode.light,
          onThemeChanged: (_) {},
        ),
      ),
    );
    final pending = controller.extract('Test evidence.');
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    controller.cancel();
    await runtime.output.close();
    await pending;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stale enabled extraction button reports rejection safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: linqoTheme(Brightness.light),
        home: LabScreen(
          controller: controller,
          themeMode: ThemeMode.light,
          onThemeChanged: (_) {},
        ),
      ),
    );
    await tester.ensureVisible(find.text('Extract on device'));
    controller.phase = LabPhase.restoring;
    await tester.tap(find.text('Extract on device'));
    await tester.pump();
    expect(
      find.text(
        'The model is not ready. Wait for processing to finish and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(runtime.calls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tap check stays interactive during a pending inference stream', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: linqoTheme(Brightness.light),
        home: LabScreen(
          controller: controller,
          themeMode: ThemeMode.light,
          onThemeChanged: (_) {},
        ),
      ),
    );
    final pending = controller.extract('Test evidence.');
    await tester.pump();
    await tester.ensureVisible(find.text('Tap check · 0'));
    await tester.tap(find.text('Tap check · 0'));
    await tester.pump();
    expect(find.text('Tap check · 1'), findsOneWidget);
    controller.cancel();
    await runtime.output.close();
    await pending;
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
