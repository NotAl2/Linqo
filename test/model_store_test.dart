import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/inference/model_store.dart';

void main() {
  late Directory sandbox;
  late ModelStore store;
  late File source;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('linqo-model-test-');
    store = ModelStore(directory: Directory('${sandbox.path}/models'));
    source = File('${sandbox.path}/source.gguf');
    await source.writeAsBytes([71, 71, 85, 70, ...List.filled(128, 42)]);
  });
  tearDown(() => sandbox.delete(recursive: true));

  test(
    'selection survives a new store and loss of the external source',
    () async {
      final imported = await store.import(source.path, 'My Qwen.gguf');
      await source.delete();
      final restored = await ModelStore(
        directory: Directory('${sandbox.path}/models'),
      ).restore();
      expect(restored!.path, imported.path);
      expect(restored.name, 'My Qwen.gguf');
      expect(restored.sha256, imported.sha256);
      expect(restored.bytes, imported.bytes);
    },
  );

  test('same-size corruption is detected by checksum on restore', () async {
    final imported = await store.import(source.path, 'model.gguf');
    final bytes = await File(imported.path).readAsBytes();
    bytes[10] = 1;
    await File(imported.path).writeAsBytes(bytes);
    await File(
      imported.path,
    ).setLastModified(DateTime.now().add(const Duration(seconds: 1)));
    await expectLater(store.restore(), throwsFormatException);
  });

  test(
    'cancelled replacement keeps the previous file and remembered selection',
    () async {
      final original = await store.import(source.path, 'original.gguf');
      final replacement = store.import(source.path, 'replacement.gguf');
      expect(store.cancelImport(), isTrue);
      await expectLater(replacement, throwsA(isA<ModelImportCancelled>()));
      expect((await store.restore())!.path, original.path);
      expect(await File(original.path).exists(), isTrue);
      expect(
        await Directory(
          '${sandbox.path}/models',
        ).list().where((f) => f.path.endsWith('.part')).isEmpty,
        isTrue,
      );
    },
  );

  test('invalid replacement cannot destroy the selected model', () async {
    final original = await store.import(source.path, 'original.gguf');
    await source.writeAsString('not a model');
    await expectLater(
      store.import(source.path, 'bad.gguf'),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.restore())!.sha256, original.sha256);
  });

  test(
    'replaces successfully and reclaims only owned unselected weights',
    () async {
      final original = await store.import(source.path, 'original.gguf');
      final unrelated = File('${sandbox.path}/models/keep.txt');
      await unrelated.writeAsString('keep');
      final replacement = await store.import(source.path, 'replacement.gguf');
      expect((await store.restore())!.name, 'replacement.gguf');
      expect(await File(original.path).exists(), isFalse);
      expect(await File(replacement.path).exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
    },
  );

  test('recovers a manifest interrupted during replacement', () async {
    final original = await store.import(source.path, 'original.gguf');
    await File(
      '${sandbox.path}/models/selected.json',
    ).rename('${sandbox.path}/models/selected.json.bak');
    expect((await store.restore())!.path, original.path);
  });

  test('adopts the previous prototype copy without duplication', () async {
    final root = Directory('${sandbox.path}/models');
    await root.create();
    await source.copy('${root.path}/prototype.gguf');
    final adopted = await store.restore();
    expect(adopted!.path, endsWith('prototype.gguf'));
    expect((await store.restore())!.sha256, adopted.sha256);
    expect(await root.list().where((f) => f.path.endsWith('.gguf')).length, 1);
  });

  test('rejects a manifest path outside private model storage', () async {
    final imported = await store.import(source.path, 'model.gguf');
    final manifest = File('${sandbox.path}/models/selected.json');
    await manifest.writeAsString(
      '{"version":1,"file":"../source.gguf","name":"escape","bytes":132,"sha256":"${imported.sha256}"}',
    );
    await expectLater(store.restore(), throwsFormatException);
  });

  test('restore removes only abandoned owned staging files', () async {
    final imported = await store.import(source.path, 'model.gguf');
    final abandoned = File('${sandbox.path}/models/model-123.gguf.part');
    final unrelated = File('${sandbox.path}/models/other.part');
    await abandoned.writeAsString('interrupted copy');
    await unrelated.writeAsString('keep');
    expect((await store.restore())!.path, imported.path);
    expect(await abandoned.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });

  test(
    'touching unchanged weights rechecks and refreshes the fingerprint',
    () async {
      final imported = await store.import(source.path, 'model.gguf');
      await File(
        imported.path,
      ).setLastModified(DateTime.now().add(const Duration(seconds: 1)));
      expect((await store.restore())!.sha256, imported.sha256);
      expect((await store.restore())!.sha256, imported.sha256);
    },
  );
}
