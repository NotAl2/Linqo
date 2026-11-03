import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 25),
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final directory = Directory('build/device-profile');
    await directory.create(recursive: true);
    final screenshots = data?.remove('screenshots') as List<dynamic>?;
    final performance = data?['performance'] as Map<String, dynamic>?;
    final performanceShots =
        performance?.remove('screenshots') as List<dynamic>?;
    for (final shot in [...?screenshots, ...?performanceShots]) {
      await File(
        '${directory.path}/${shot['screenshotName']}.png',
      ).writeAsBytes((shot['bytes'] as List).cast<int>());
    }
    await File(
      '${directory.path}/results.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
