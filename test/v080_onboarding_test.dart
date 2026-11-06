import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/ui/welcome_screen.dart';
import 'package:linqo/ui/release_settings.dart';

void main() {
  sqfliteFfiInit();
  testWidgets('first-run Skip persists and never downloads a model', (
    tester,
  ) async {
    final store = await LibraryStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    final c = LibraryController(store);
    await c.initialize(restoreModel: false);
    try {
      await tester.pumpWidget(
        LinqoApp(controller: c, enableSharing: false, enableOnboarding: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Linqo'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(await store.preference('onboarding_completed'), '1');
      expect(c.modelAvailable, isFalse);
      expect(c.download.busy, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        LinqoApp(controller: c, enableSharing: false, enableOnboarding: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Linqo'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
    }
  });
  testWidgets('tour remains readable with large text and reduced motion', (
    tester,
  ) async {
    final store = await LibraryStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    final c = LibraryController(store);
    await c.initialize(restoreModel: false);
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: linqoTheme(Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(1.8),
            ),
            child: WelcomeScreen(controller: c, onDone: (_) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a quick look'));
      await tester.pumpAndSettle();
      expect(find.text('Try saving'), findsOneWidget);
      await tester.ensureVisible(find.text('Try saving'));
      await tester.tap(find.text('Try saving'));
      await tester.pumpAndSettle();
      expect(find.text('Saved to Linqo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
    }
  });
  testWidgets('diagnostics entry stays hidden until seven version taps', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: linqoTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(child: ReleaseSettings()),
        ),
      ),
    );
    expect(find.text('Local diagnostics'), findsNothing);
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Linqo 0.8.2'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('Local diagnostics'), findsOneWidget);
    expect(find.text('Keep local diagnostic logs'), findsOneWidget);
  });
}
