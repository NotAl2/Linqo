import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/inference/local_runtime.dart';
import 'package:linqo/inference/model_store.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/main.dart';
import 'package:linqo/services/local_notifications.dart';
import 'package:linqo/ui/notification_settings.dart';
import 'package:linqo/ui/settings_screen.dart';
import 'package:linqo/theme.dart';
import 'phone_english_reel_test.dart' show protectedState;

/// A controlled worker tests notification outcomes and long-running UI states;
/// its durations are not model benchmarks. The real selected model is untouched.
class ControlledRuntime implements LocalRuntime, ProgressRuntime {
  @override
  void Function(int, int, bool)? onProgress;
  Completer<void> gate = Completer<void>();
  bool fail = false, cancelled = false;
  @override
  Future<void> load(String path, RuntimeSettings settings) async {}
  @override
  Stream<String> extract(SourceDocument source) async* {
    cancelled = false;
    onProgress?.call(1, 3, false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    onProgress?.call(2, 3, false);
    await gate.future;
    if (cancelled) return;
    if (fail) throw const FormatException('Controlled QA failure');
    onProgress?.call(4, 3, false);
    yield jsonEncode({
      'schema_version': 3,
      'title': 'Sample',
      'type': 'general',
      'summary_lines': [2],
      'ingredient_lines': [],
      'step_lines': [],
      'detail_lines': [],
      'places': [],
    });
  }

  @override
  void cancel() {
    cancelled = true;
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<void> unload() async {}
  @override
  Future<void> dispose() async {
    cancel();
  }

  void reset({bool failed = false}) {
    gate = Completer<void>();
    fail = failed;
    cancelled = false;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'native opt-in alerts, cancellation, progress and visible diagnostics',
    (tester) async {
      final before = await protectedState(
        '${await getDatabasesPath()}/linqo-library.db',
      );
      final notices = LocalNotifications.instance;
      final original = await notices.status();
      expect(original['available'], true);
      final path = '${await getDatabasesPath()}/linqo-notifications-qa.db';
      await deleteDatabase(path);
      final store = await LibraryStore.open(path: path);
      final runtime = ControlledRuntime();
      final c = LibraryController(store, runtime: runtime);
      await c.initialize(restoreModel: false);
      c.lab.model = const ImportedModel(
        path: '/controlled-qa-model',
        name: 'UI simulation',
        bytes: 100,
        sha256: 'qa',
      );
      Future<void> pumpUntil(bool Function() ready) async {
        final time = Stopwatch()..start();
        while (!ready()) {
          if (time.elapsed > const Duration(seconds: 30)) {
            throw TimeoutException('QA state stalled');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> shot(String name) async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await binding.takeScreenshot(name);
      }

      final id = await store.save(
        const SaveDraft(
          title: 'Simulated progress test',
          body:
              'Sample\nSmall models fit older devices.\nKeep your library local.',
          kind: SaveKind.note,
          automaticContent: false,
          autoExtract: false,
        ),
      );
      binding.reportData = {'simulated_worker': true, 'before': before};
      try {
        await notices.setEnabled(false);
        expect(await notices.show(test: true), false);
        expect((await notices.status())['hasNotification'], false);
        final allowed = await notices.setEnabled(true);
        expect(
          allowed,
          true,
          reason:
              'Native notification posting must be allowed for this connected-device test.',
        );
        await tester.pumpWidget(
          LinqoApp(
            controller: c,
            enableSharing: false,
            enableSupportPrompts: false,
            enableOnboarding: false,
          ),
        );
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await c.extract((await store.get(id))!);
        await pumpUntil(() => c.lab.progress.completed == 1);
        expect(c.lab.progress.fraction, closeTo(1 / 3, .001));
        await shot('v083-progress');
        await tester.tap(find.byIcon(Icons.search_rounded).last);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.enterText(
          find.byKey(const ValueKey('library-search')),
          'simulated',
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(c.processing, true);
        runtime.gate.complete();
        await pumpUntil(() => !c.processing);
        expect((await notices.status())['hasNotification'], true);
        binding.reportData!['completion_notification'] = true;
        await notices.setEnabled(false);
        await notices.setEnabled(true);
        runtime.reset(failed: true);
        await c.extract((await store.get(id))!);
        await pumpUntil(() => c.lab.progress.completed == 1);
        runtime.gate.complete();
        await pumpUntil(() => !c.processing);
        expect((await store.get(id))!.status, 'failed');
        expect((await notices.status())['hasNotification'], true);
        binding.reportData!['failure_notification'] = true;
        await notices.setEnabled(false);
        await notices.setEnabled(true);
        runtime.reset();
        await c.extract((await store.get(id))!);
        await pumpUntil(() => c.lab.progress.completed == 1);
        await c.stop();
        await pumpUntil(() => !c.processing);
        expect((await notices.status())['hasNotification'], false);
        binding.reportData!['cancellation_silent'] = true;
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: linqoTheme(dark ? Brightness.dark : Brightness.light),
              home: SettingsScreen(controller: c),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Diagnostics & logs'), findsOneWidget);
          await shot('v083-settings-${dark ? 'dark' : 'light'}');
        }
        await tester.tap(find.text('Diagnostics & logs'));
        await tester.pumpAndSettle();
        expect(find.text('Keep local diagnostic logs'), findsOneWidget);
        await shot('v083-diagnostics');
        await tester.pumpWidget(
          MaterialApp(
            key: const ValueKey('notification-settings-capture'),
            theme: linqoTheme(Brightness.light),
            home: const NotificationSettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();
        await shot('v083-notifications');
        binding.reportData!['after'] = await protectedState(
          '${await getDatabasesPath()}/linqo-library.db',
        );
        expect(binding.reportData!['after'], before);
        binding.reportData!['normal_data_preserved'] = true;
      } finally {
        await notices.takeOpenSave();
        await notices.setEnabled(original['enabled'] == true);
        await tester.pumpWidget(const SizedBox());
        await c.background();
        c.dispose();
        await store.close();
        await deleteDatabase(path);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
