import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/ui/backup_password_dialog.dart';
import 'package:linqo/theme.dart';

void main() {
  testWidgets('backup password validates confirmation and fits enlarged text', (
    tester,
  ) async {
    String? result;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: linqoTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await backupPassword(context, creating: true);
                },
                child: const Text('Export'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encrypt backup'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your backup password.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'correct horse battery',
    );
    await tester.enterText(find.byType(TextFormField).last, 'different');
    await tester.tap(find.text('Encrypt backup'));
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).last,
      'correct horse battery',
    );
    await tester.tap(find.text('Encrypt backup'));
    await tester.pumpAndSettle();
    expect(result, 'correct horse battery');
    expect(tester.takeException(), isNull);
  });
}
