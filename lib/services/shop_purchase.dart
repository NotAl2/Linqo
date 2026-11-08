import 'tiers.dart';

class ShopPurchase {
  const ShopPurchase({
    required this.tier,
    required this.code,
    required this.url,
    required this.expires,
    required this.accountId,
  });
  final AppTier tier;
  final String code;
  final Uri url;
  final DateTime expires;
  final String accountId;

  factory ShopPurchase.parse(
    Map<String, dynamic> value,
    AppTier expected, {
    required String accountId,
  }) {
    final price = switch (expected) {
      AppTier.xl => 500,
      AppTier.xxl => 700,
      AppTier.free => 0,
    };
    final url = Uri.tryParse(
      value['shop_url'] is String ? value['shop_url'] as String : '',
    );
    final code = value['claim_code'];
    final expires = value['expires_at'];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (accountId.isEmpty ||
        price == 0 ||
        value['tier'] != expected.name ||
        value['amount_cents'] != price ||
        value['currency'] != 'USD' ||
        code is! String ||
        !RegExp(r'^LQ-[A-F0-9]{32}$').hasMatch(code) ||
        expires is! int ||
        expires <= now ||
        expires > now + const Duration(days: 31).inMilliseconds ||
        url == null ||
        url.scheme != 'https' ||
        url.host != 'buymeacoffee.com' ||
        url.userInfo.isNotEmpty ||
        url.hasPort ||
        url.hasQuery ||
        url.hasFragment ||
        !RegExp(r'^/notal2/e/[1-9][0-9]{0,14}$').hasMatch(url.path)) {
      throw const FormatException(
        'The Shop purchase could not be prepared. Try again.',
      );
    }
    return ShopPurchase(
      tier: expected,
      code: code,
      url: url,
      expires: DateTime.fromMillisecondsSinceEpoch(expires),
      accountId: accountId,
    );
  }
}
