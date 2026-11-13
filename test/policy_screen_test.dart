import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/ui/policy_screen.dart';

void main() {
  testWidgets('Windows line endings separate heading and body', (tester) async {
    const asset = 'test/policy-crlf.md';
    const body = 'This paragraph must use the readable body text style.';
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      if (utf8.decode(message!.buffer.asUint8List()) == asset) {
        return ByteData.sublistView(
          Uint8List.fromList(utf8.encode('# Test policy\r\n\r\n$body')),
        );
      }
      return null;
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    await tester.pumpWidget(
      const MaterialApp(
        home: PolicyScreen(title: 'Notice', asset: asset),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test policy'), findsOneWidget);
    expect(tester.widget<Text>(find.text(body)).style?.height, 1.6);
  });
  for (final (title, asset, expected) in const [
    ('Privacy notice', 'policies/PRIVACY.md', 'Your library'),
    ('Terms of use', 'policies/TERMS.md', 'Your content and the app'),
    ('Access policy', 'policies/PURCHASES.md', 'Full prebuild access:'),
  ]) {
    testWidgets('$title is bundled and readable offline', (tester) async {
      var firstHeading = '';
      await tester.runAsync(() async {
        final text = await rootBundle.loadString(asset);
        expect(text, isNotEmpty);
        firstHeading = text
            .split('\n')
            .first
            .replaceFirst(RegExp(r'^#+ '), '')
            .trim();
        await tester.pumpWidget(
          MaterialApp(
            home: PolicyScreen(title: title, asset: asset),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining(expected), findsWidgets);
      // A whole document rendered as one heading must fail this check.
      expect(find.text(firstHeading), findsOneWidget);
      final paragraphs = tester.widgetList<Text>(find.byType(Text));
      expect(
        paragraphs.any(
          (text) => text.style?.height == 1.6 && (text.data?.length ?? 0) > 30,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
