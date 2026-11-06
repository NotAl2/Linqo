import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/ui/welcome_screen.dart';
import 'package:linqo/ui/settings_screen.dart';
import 'package:linqo/ui/release_settings.dart';
import 'package:linqo/theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('v0.8.2 welcome, clips, settings and hidden diagnostics', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/linqo-v080-ui-qa.db';
    await deleteDatabase(path);
    final store = await LibraryStore.open(path: path);
    final c = LibraryController(store);
    await c.initialize(restoreModel: false);
    final viewport =
        tester.view.physicalSize.width / tester.view.devicePixelRatio > 700
        ? 'tablet'
        : 'phone';
    binding.reportData = {
      'synthetic_qa': true,
      'viewport': viewport,
      'model_started': false,
    };
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      await binding.takeScreenshot(name);
    }

    try {
      await tester.pumpWidget(
        LinqoApp(controller: c, enableSharing: false, enableOnboarding: true),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await shot('v080-$viewport-welcome');
      await tester.tap(find.text('Take a quick look'));
      await tester.pumpAndSettle();
      await shot('v080-$viewport-share-tour');
      await tester.tap(find.text('Try saving'));
      await tester.pumpAndSettle();
      expect(find.text('Saved to Linqo'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await shot('v080-$viewport-ai-tour');
      await tester.tap(find.text('Start my library'));
      await tester.pumpAndSettle();
      expect(await store.preference('onboarding_completed'), '1');
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await shot('v080-$viewport-settings');
      await tester.scrollUntilVisible(
        find.text('Linqo 0.8.2'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await shot('v080-$viewport-updates');
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.text('Linqo 0.8.2'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(find.byType(DiagnosticsScreen), findsOneWidget);
      await shot('v080-$viewport-diagnostics');
      nav.pop();
      nav.pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          theme: linqoTheme(Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              textScaler: const TextScaler.linear(1.5),
              disableAnimations: true,
            ),
            child: WelcomeScreen(controller: c, onDone: (_) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await shot('v080-$viewport-dark-large-welcome');
      await tester.tap(find.text('Take a quick look'));
      await tester.pumpAndSettle();
      expect(find.text('Try saving'), findsOneWidget);
      await shot('v080-$viewport-dark-large-tour');
      expect(c.modelAvailable, isFalse);
      expect(c.download.busy, isFalse);
      expect(tester.takeException(), isNull);
      binding.reportData!['onboarding_persisted'] = true;
      binding.reportData!['diagnostics_hidden_entry'] = true;
      binding.reportData!['native_tutorial_interaction'] = true;
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
      await deleteDatabase(path);
    }
  });
}
