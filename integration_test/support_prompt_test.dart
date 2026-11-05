import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/library/support_prompt_policy.dart';
import 'package:linqo/ui/support_prompt.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('support reminder after first save and durable opt-out', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/linqo-support-prompt-qa.db';
    await deleteDatabase(path);
    var store = await LibraryStore.open(path: path);
    var c = LibraryController(store);
    await c.initialize(restoreModel: false);
    binding.reportData = {'synthetic_fixtures': true, 'model_started': false};
    Future<void> waitForPrompt() async {
      final watch = Stopwatch()..start();
      while (find.byType(SupportPrompt).evaluate().isEmpty &&
          watch.elapsedMilliseconds < 10000) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SupportPrompt), findsOneWidget);
      await tester.pumpAndSettle();
    }

    try {
      await tester.pumpWidget(
        LinqoApp(
          controller: c,
          enableSharing: false,
          enableSupportPrompts: true,
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      expect(find.byType(SupportPrompt), findsNothing);
      await c.save(
        const SaveDraft(
          title: 'A little discovery',
          body: 'Try the new walking route on Sunday.',
          kind: SaveKind.note,
        ),
      );
      await waitForPrompt();
      await binding.takeScreenshot('support-prompt-light');
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      final policy = SupportPromptPolicy(store.db);
      for (final variant in [
        (ThemeMode.dark, 1.0, 'dark'),
        (ThemeMode.light, 2.0, 'large-text'),
      ]) {
        await c.appearance(variant.$1);
        await tester.pumpAndSettle();
        unawaited(
          showDialog<void>(
            context: nav.context,
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(variant.$2)),
              child: SupportPrompt(policy: policy),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await binding.takeScreenshot('support-prompt-${variant.$3}');
        expect(tester.takeException(), isNull);
        if (variant.$3 == 'large-text') {
          await tester.ensureVisible(find.text('Don’t show again'));
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          expect(await policy.optedOut(), isTrue);
        }
        await nav.maybePop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
      store = await LibraryStore.open(path: path);
      c = LibraryController(store);
      await c.initialize(restoreModel: false);
      await tester.pumpWidget(
        LinqoApp(
          controller: c,
          enableSharing: false,
          enableSupportPrompts: true,
        ),
      );
      await tester.pumpAndSettle();
      await c.save(
        const SaveDraft(title: 'Another little discovery', kind: SaveKind.note),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(SupportPrompt), findsNothing);
      expect(await SupportPromptPolicy(store.db).optedOut(), isTrue);
      binding.reportData!['first_save_automatic_prompt'] = true;
      binding.reportData!['opt_out_survived_database_reopen'] = true;
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
      await deleteDatabase(path);
    }
  });
}
