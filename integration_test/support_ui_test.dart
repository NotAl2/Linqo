import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/ui/settings_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'support and licenses remain usable in both themes and large text',
    (tester) async {
      final store = await LibraryStore.open(
        path: '${await getDatabasesPath()}/linqo-support-qa.db',
      );
      final controller = LibraryController(store);
      await controller.initialize(restoreModel: false);
      try {
        await tester.pumpWidget(
          LinqoApp(controller: controller, enableSharing: false),
        );
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        for (final variant in [
          (ThemeMode.light, 1.0, 'light'),
          (ThemeMode.dark, 1.0, 'dark'),
          (ThemeMode.light, 2.0, 'large-text'),
        ]) {
          await controller.appearance(variant.$1);
          unawaited(
            navigator.push(
              MaterialPageRoute<void>(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(variant.$2)),
                  child: SettingsScreen(controller: controller),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Buy me a coffee'),
            300,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await binding.takeScreenshot('release-support-${variant.$3}');
          await tester.scrollUntilVisible(
            find.text('Open-source licenses'),
            -180,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.tap(find.text('Open-source licenses'));
          await tester.pumpAndSettle();
          expect(find.byType(LicensePage), findsOneWidget);
          navigator.pop();
          await tester.pumpAndSettle();
          navigator.pop();
          await tester.pumpAndSettle();
        }
        expect(controller.modelAvailable, isFalse);
        expect(controller.processing, isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await store.close();
      }
    },
  );
}
