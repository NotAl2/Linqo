import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/services/checkout_purchase.dart';
import 'package:linqo/services/tiers.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/ui/checkout_dialog.dart';

Map<String, dynamic> fixture(AppTier tier) => {
  'provider': 'cashfree',
  'tier': tier.name,
  'amount_minor': tier == AppTier.xl ? 44900 : 64900,
  'currency': 'INR',
  'sandbox': true,
  'order_id': 'lq_s_12345678-1234-4123-8123-123456789abc',
  'checkout_url': 'https://linqo.example/checkout/${'a' * 64}',
  'expires_at': DateTime.now()
      .add(const Duration(hours: 1))
      .millisecondsSinceEpoch,
};
void main() {
  test('tiers and INR prices match the owner-approved products', () {
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
      final purchase = CheckoutPurchase.parse(
        fixture(tier),
        tier,
        accountId: 'owner',
        checkoutOrigin: 'https://linqo.example',
      );
      expect(purchase.sandbox, true);
      expect(purchase.accountId, 'owner');
    }
    final ids = List.generate(20, (_) => newPurchaseRequestId());
    expect(ids.toSet().length, 20);
    expect(
      ids.every(
        (id) => RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(id),
      ),
      true,
    );
  });
  test(
    'checkout rejects old Shop, hostile URL, wrong price, currency, account, mode and expired response',
    () {
      final changes = <Map<String, dynamic>>[
        {'provider': 'buymeacoffee'},
        {'tier': 'xxl'},
        {'amount_minor': 500},
        {'currency': 'USD'},
        {'sandbox': false},
        {'order_id': 'receipt-123'},
        {'expires_at': 0},
        {'checkout_url': 'https://attacker.example/checkout/${'a' * 64}'},
        {
          'checkout_url':
              'https://linqo.example/checkout/${'a' * 64}?uid=other',
        },
        {'checkout_url': 'https://user@linqo.example/checkout/${'a' * 64}'},
        {'checkout_url': 'https://linqo.example:8443/checkout/${'a' * 64}'},
        {'checkout_url': 'http://linqo.example/checkout/${'a' * 64}'},
        {'checkout_url': 'https://linqo.example/checkout/${'a' * 64}#leak'},
        {'checkout_url': 'https://buymeacoffee.com/notal2/e/596224'},
      ];
      for (final change in changes) {
        expect(
          () => CheckoutPurchase.parse(
            {...fixture(AppTier.xl), ...change},
            AppTier.xl,
            accountId: 'owner',
            checkoutOrigin: 'https://linqo.example',
          ),
          throwsFormatException,
        );
      }
      expect(
        () => CheckoutPurchase.parse(
          fixture(AppTier.xl),
          AppTier.xl,
          accountId: '',
          checkoutOrigin: 'https://linqo.example',
        ),
        throwsFormatException,
      );
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'Cashfree phone disclosure validates input and fits large text/keyboard in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? phone;
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
                  onPressed: () async {
                    phone = await showDialog<String>(
                      context: context,
                      builder: (_) => const CheckoutDialog(
                        tier: AppTier.xl,
                        accountLabel: 'buyer@example.com',
                        sandbox: true,
                      ),
                    );
                  },
                  child: const Text('Upgrade'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Upgrade'));
        await tester.pumpAndSettle();
        expect(find.text('Linqo XL · ₹449 once'), findsOneWidget);
        expect(find.text('Sandbox test · no paid unlock'), findsOneWidget);
        await tester.tap(find.text('Continue to Cashfree'));
        await tester.pumpAndSettle();
        expect(find.text('Include + and your country code.'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), '+919876543210');
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Continue to Cashfree'));
        await tester.pumpAndSettle();
        expect(phone, '+919876543210');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
