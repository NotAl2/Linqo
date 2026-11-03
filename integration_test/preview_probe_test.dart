import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linqo/sharing/link_preview.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('public preview diagnostic on device', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Checking public link previews…')),
      ),
    );
    binding.reportData = {};
    final addresses = await InternetAddress.lookup('example.com');
    binding.reportData!['dns'] = addresses
        .map(
          (a) => {
            'address': a.address,
            'public': isPublicAddress(a),
            'type': a.type.name,
          },
        )
        .toList();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final response = await (await client.getUrl(
        Uri.parse('https://example.com/'),
      )).close().timeout(const Duration(seconds: 8));
      binding.reportData!['plain_http_status'] = response.statusCode;
      await response.take(0).drain<void>();
    } catch (e) {
      binding.reportData!['plain_failure'] = e.toString();
    } finally {
      client.close(force: true);
    }
    final preview = PreviewRequest('https://example.com/');
    final result = await preview.future;
    binding.reportData!['preview_title'] = result.title;
    binding.reportData!['preview_failure'] = preview.failure?.toString();
  });
}
