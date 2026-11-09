import 'dart:math';
import 'tiers.dart';

String newPurchaseRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class CheckoutPurchase {
  const CheckoutPurchase({
    required this.tier,
    required this.orderId,
    required this.url,
    required this.expires,
    required this.accountId,
    required this.sandbox,
  });
  final AppTier tier;
  final String orderId;
  final Uri url;
  final DateTime expires;
  final String accountId;
  final bool sandbox;

  factory CheckoutPurchase.parse(
    Map<String, dynamic> value,
    AppTier expected, {
    required String accountId,
    required String checkoutOrigin,
  }) {
    final price = switch (expected) {
      AppTier.xl => 44900,
      AppTier.xxl => 64900,
      AppTier.free => 0,
    };
    final url = Uri.tryParse(
      value['checkout_url'] is String ? value['checkout_url'] as String : '',
    );
    final backend = Uri.tryParse(checkoutOrigin);
    final expires = value['expires_at'];
    final order = value['order_id'];
    final sandbox = value['sandbox'];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (accountId.isEmpty ||
        price == 0 ||
        value['provider'] != 'cashfree' ||
        value['tier'] != expected.name ||
        value['amount_minor'] != price ||
        value['currency'] != 'INR' ||
        sandbox is! bool ||
        order is! String ||
        !RegExp(
          r'^lq_[ps]_[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(order) ||
        !order.startsWith(sandbox ? 'lq_s_' : 'lq_p_') ||
        expires is! int ||
        expires <= now ||
        expires > now + const Duration(hours: 2).inMilliseconds ||
        backend == null ||
        backend.scheme != 'https' ||
        backend.host.isEmpty ||
        backend.userInfo.isNotEmpty ||
        backend.hasPort ||
        backend.hasQuery ||
        backend.hasFragment ||
        (backend.path.isNotEmpty && backend.path != '/') ||
        url == null ||
        url.scheme != 'https' ||
        url.host != backend.host ||
        url.userInfo.isNotEmpty ||
        url.hasPort ||
        url.hasQuery ||
        url.hasFragment ||
        !RegExp(r'^/checkout/[a-f0-9]{64}$').hasMatch(url.path)) {
      throw const FormatException('Checkout could not be prepared. Try again.');
    }
    return CheckoutPurchase(
      tier: expected,
      orderId: order,
      url: url,
      expires: DateTime.fromMillisecondsSinceEpoch(expires),
      accountId: accountId,
      sandbox: sandbox,
    );
  }
}
