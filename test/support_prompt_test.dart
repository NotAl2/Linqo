import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/library/support_prompt_policy.dart';
import 'package:linqo/main.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/ui/support_prompt.dart';

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  setUp(() async {
    store = await LibraryStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() => store.close());
  test(
    'first save then both randomized save interval and week cooldown; opt-out persists across policy recreation',
    () async {
      var now = DateTime(2026, 11, 5);
      final policy = SupportPromptPolicy(
        store.db,
        now: () => now,
        random: Random(42),
      );
      expect(await policy.claim(), isFalse);
      await store.save(
        const SaveDraft(title: 'First find', kind: SaveKind.note),
      );
      expect(await policy.claim(), isTrue);
      expect(await policy.claim(), isFalse);
      final state =
          jsonDecode((await store.preference(SupportPromptPolicy.stateKey))!)
              as Map;
      expect(state['next_count'], inInclusiveRange(6, 13));
      for (var count = 1; count < state['next_count']; count++) {
        await store.save(SaveDraft(title: 'Find $count', kind: SaveKind.note));
      }
      expect(await policy.claim(), isFalse);
      now = now.add(const Duration(days: 7));
      expect(await policy.claim(), isTrue);
      await policy.setOptedOut(true);
      now = now.add(const Duration(days: 30));
      final restored = SupportPromptPolicy(store.db, now: () => now);
      expect(await restored.optedOut(), isTrue);
      expect(await restored.claim(), isFalse);
    },
  );
  test(
    'share replay, edits and rolled-back saves do not advance support reminders',
    () async {
      const draft = SaveDraft(
        title: 'A note',
        kind: SaveKind.note,
        shareId: 'one-receipt',
      );
      final id = await store.save(draft);
      expect(await store.save(draft), id);
      await store.save(
        const SaveDraft(title: 'Edited note', kind: SaveKind.note),
        id: id,
      );
      await expectLater(
        store.save(
          const SaveDraft(
            title: 'Invalid collection',
            kind: SaveKind.note,
            collectionIds: [999],
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.preference(SupportPromptPolicy.countKey), '1');
      expect(await store.count(), 1);
    },
  );
  testWidgets(
    'prompt fits themes and enlarged text and remembers checkbox even on back',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final policy = SupportPromptPolicy(store.db);
      for (final variant in [
        (Brightness.light, 1.0),
        (Brightness.dark, 1.0),
        (Brightness.light, 2.0),
      ]) {
        await policy.setOptedOut(false);
        await tester.pumpWidget(
          MaterialApp(
            theme: linqoTheme(variant.$1),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(variant.$2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => SupportPrompt(policy: policy),
                    ),
                    child: const Text('Open support'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open support'));
        await tester.pumpAndSettle();
        expect(find.text('Support Linqo'), findsOneWidget);
        expect(find.text('Buy me a coffee'), findsOneWidget);
        await tester.ensureVisible(find.text('Don’t show again'));
        await tester.tap(find.byType(CheckboxListTile));
        expect(await tester.runAsync(policy.optedOut), isTrue);
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(SupportPrompt), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'first save waits for editor to close, then appears only once per app session',
    (tester) async {
      final c = LibraryController(store);
      await c.initialize(restoreModel: false);
      try {
        await tester.pumpWidget(
          LinqoApp(
            controller: c,
            enableSharing: false,
            enableSupportPrompts: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(SupportPrompt), findsNothing);
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Editing a find')),
          ),
        );
        await tester.pumpAndSettle();
        await c.save(const SaveDraft(title: 'First find', kind: SaveKind.note));
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(SupportPrompt), findsNothing);
        c.processing = true;
        nav.pop();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(SupportPrompt), findsNothing);
        c.processing = false;
        await c.refresh();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        expect(find.byType(SupportPrompt), findsOneWidget);
        await tester.tap(find.text('Later'));
        await tester.pumpAndSettle();
        await c.save(
          const SaveDraft(title: 'Second find', kind: SaveKind.note),
        );
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(SupportPrompt), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );
}
