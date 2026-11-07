import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/ui/account_screen.dart';

void main() {
  sqfliteFfiInit();
  for (final brightness in Brightness.values) {
    testWidgets(
      'account settings remain usable at large text in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await LibraryStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfiNoIsolate,
        );
        final controller = LibraryController(store);
        await controller.initialize(restoreModel: false);
        await tester.pumpWidget(
          MaterialApp(
            theme: linqoTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.5),
              ),
              child: AccountScreen(controller: controller),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Account & backup'), findsOneWidget);
        expect(
          find.text(
            'Google sign-in is not configured in this preview. Your local library and ZIP backups still work.',
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Enable Drive backup'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Contribute automatic samples'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Switch), findsWidgets);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await store.close();
      },
    );
  }
}
