import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_store.dart';
import '../integration_test/phone_english_reel_test.dart' show protectedState;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('library fingerprints work with and without a selected model', () async {
    final work = await Directory.systemTemp.createTemp(
      'linqo-fingerprint-test-',
    );
    databaseFactory = databaseFactoryFfiNoIsolate;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => work.path);
    try {
      final path = '${work.path}/library.db';
      final store = await LibraryStore.open(path: path);
      await store.close();
      final withoutModel = await protectedState(path);
      expect(withoutModel['model_selection_sha256'], isNull);
      expect((withoutModel['saves'] as Map)['count'], 0);
      final models = await Directory('${work.path}/models').create();
      final manifest = File('${models.path}/selected.json');
      await manifest.writeAsString(
        jsonEncode({
          'file': 'model.gguf',
          'name': 'Test model',
          'bytes': 100,
          'sha256': 'test',
        }),
      );
      final withModel = await protectedState(path);
      expect(
        withModel['model_selection_sha256'],
        matches(RegExp(r'^[a-f0-9]{64}$')),
      );
      expect(withModel['saves'], withoutModel['saves']);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await work.delete(recursive: true);
    }
  });
}
