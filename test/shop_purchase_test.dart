import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/services/shop_purchase.dart';
import 'package:linqo/services/tiers.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/ui/shop_purchase_dialog.dart';

Map<String, dynamic> fixture(AppTier tier) => {
  'tier': tier.name,
  'amount_cents': tier == AppTier.xl ? 500 : 700,
  'currency': 'USD',
  'claim_code': 'LQ-${'A' * 32}',
  'shop_url': 'https://buymeacoffee.com/notal2/e/101',
  'expires_at': DateTime.now()
      .add(const Duration(days: 30))
      .millisecondsSinceEpoch,
};

void main() {
  test('published tier limits and fixed one-time prices match XL and XXL', () {
    expect(
      (
        const LibraryLimits(AppTier.free, enforced: true).saves,
        const LibraryLimits(AppTier.free, enforced: true).collections,
      ),
      (50, 5),
    );
    expect(
      (
        const LibraryLimits(AppTier.xl, enforced: true).saves,
        const LibraryLimits(AppTier.xl, enforced: true).collections,
      ),
      (250, 25),
    );
    expect(
      (
        const LibraryLimits(AppTier.xxl, enforced: true).saves,
        const LibraryLimits(AppTier.xxl, enforced: true).collections,
      ),
      (null, null),
    );
    for (final tier in [AppTier.xl, AppTier.xxl]) {
      final purchase = ShopPurchase.parse(
        fixture(tier),
        tier,
        accountId: 'owner',
      );
      expect(purchase.accountId, 'owner');
      expect(purchase.tier, tier);
    }
  });
  test(
    'purchase sessions reject another product, stale code, altered price and unsafe destinations',
    () {
      final changes = <Map<String, dynamic>>[
        {'tier': 'xxl'},
        {'amount_cents': 1},
        {'amount_cents': 1000},
        {'currency': 'INR'},
        {'claim_code': 'receipt-123'},
        {'expires_at': 0},
        {'shop_url': 'https://attacker.example/notal2/e/101'},
        {'shop_url': 'https://buymeacoffee.com/another/e/101'},
        {'shop_url': 'https://buymeacoffee.com/notal2/e/101?code=leak'},
        {'shop_url': 'https://buymeacoffee.com/notal2/e/101#leak'},
        {'shop_url': 'https://user@buymeacoffee.com/notal2/e/101'},
        {'shop_url': 'http://buymeacoffee.com/notal2/e/101'},
      ];
      for (final change in changes) {
        expect(
          () => ShopPurchase.parse(
            {...fixture(AppTier.xl), ...change},
            AppTier.xl,
            accountId: 'owner',
          ),
          throwsFormatException,
        );
      }
      expect(
        () =>
            ShopPurchase.parse(fixture(AppTier.xl), AppTier.xl, accountId: ''),
        throwsFormatException,
      );
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'purchase instructions require copying the code and fit large text in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? clipboard;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboard = (call.arguments as Map)['text'] as String;
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final purchase = ShopPurchase.parse(
          fixture(AppTier.xl),
          AppTier.xl,
          accountId: 'owner',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: linqoTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => ShopPurchaseDialog(
                      purchase: purchase,
                      accountLabel: 'buyer@example.com',
                    ),
                  ),
                  child: const Text('Prepare purchase'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Prepare purchase'));
        await tester.pumpAndSettle();
        final open = find.widgetWithText(FilledButton, 'Open Shop');
        expect(tester.widget<FilledButton>(open).onPressed, isNull);
        await tester.tap(find.text('Copy code'));
        await tester.pumpAndSettle();
        expect(clipboard, purchase.code);
        expect(tester.widget<FilledButton>(open).onPressed, isNotNull);
        expect(find.textContaining('US\$5 once'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
