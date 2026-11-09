import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'account_identity.dart';
import 'cloud_config.dart';

class CloudRequestError extends StateError {
  CloudRequestError(this.code, super.message);
  final String code;
}

class CloudApi {
  CloudApi(this.identity, {http.Client? client})
    : client = client ?? http.Client();
  final AccountIdentity identity;
  final http.Client client;
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (!CloudConfig.backendReady) {
      throw StateError('Cloud services are not configured in this build.');
    }
    final request = http.Request(
      method,
      Uri.parse('${CloudConfig.backend.replaceAll(RegExp(r'/$'), '')}$path'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer ${await identity.idToken()}',
      'Content-Type': 'application/json',
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 15));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('Cloud response was too large.');
      }
    }
    final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudRequestError(
        value['error'] is String ? value['error'] as String : 'request_failed',
        switch (value['error']) {
          'checkout_not_live' =>
            'Checkout is not live yet. No payment was taken.',
          'try_tomorrow' =>
            'Too many purchase attempts today. Try again tomorrow.',
          'invalid_checkout_phone' =>
            'Enter a phone number with + and country code.',
          'purchase_request_expired' =>
            'Checkout expired. Close this screen and start again.',
          'payment_provider_unavailable' =>
            'Cashfree could not connect. Retry checkout; your saves are safe.',
          'contribution_not_accepted' =>
            'Contribution allowance reached or sample already received.',
          'contributions_paused' =>
            'Contributions are paused. Your library is unaffected.',
          'sign_in_required' => 'Sign in again to reconnect.',
          _ => 'Cloud request could not finish. Try again later.',
        },
      );
    }
    return value;
  }

  void close() => client.close();
}
