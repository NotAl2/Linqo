import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/ui/policy_screen.dart';

void main() {
  for (final (title, asset, expected) in const [
    ('Privacy notice', 'policies/PRIVACY.md', 'Your library'),
    ('Terms of use', 'policies/TERMS.md', 'Your content and the app'),
    ('Access policy', 'policies/PURCHASES.md', 'Full prebuild access:'),
  ]) {
    testWidgets('$title is bundled and readable offline', (tester) async {
      await tester.runAsync(() async {
        final text = await rootBundle.loadString(asset);
        expect(text,isNotEmpty);
        await tester.pumpWidget(MaterialApp(home:PolicyScreen(title:title,asset:asset)));
        await Future<void>.delayed(const Duration(milliseconds:50));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining(expected), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
