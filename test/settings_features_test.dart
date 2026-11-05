import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/inference/model_store.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/ui/settings_screen.dart';

void main() {
  sqfliteFfiInit();
  testWidgets(
    'installed compact model and backup controls work in both themes and large text',
    (tester) async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final c = LibraryController(store);
      await c.initialize(restoreModel: false);
      c.lab.model = ImportedModel(
        path: 'unused.gguf',
        name: 'English model',
        bytes: 396705472,
        sha256: c.download.expectedSha,
      );
      try {
        for (final variant in [
          (Brightness.light, 1.0),
          (Brightness.dark, 1.0),
          (Brightness.light, 2.0),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: linqoTheme(variant.$1),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 800),
                  textScaler: TextScaler.linear(variant.$2),
                ),
                child: SettingsScreen(key: UniqueKey(), controller: c),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scrollable = find.byType(Scrollable).first;
          await tester.scrollUntilVisible(
            find.text('Already installed'),
            200,
            scrollable: scrollable,
          );
          final button = tester.widget<FilledButton>(
            find.ancestor(
              of: find.text('Already installed'),
              matching: find.byType(FilledButton),
            ),
          );
          expect(button.onPressed, isNull);
          expect(c.compactModelInstalled, isTrue);
          await c
              .downloadModel(); // A duplicate action is guarded below the UI too.
          expect(c.download.busy, isFalse);
          await tester.scrollUntilVisible(
            find.text('Export saves'),
            200,
            scrollable: scrollable,
          );
          expect(find.text('Import saves'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.text('Why we made Linqo'),
            200,
            scrollable: scrollable,
          );
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await store.close();
      }
    },
  );
}
