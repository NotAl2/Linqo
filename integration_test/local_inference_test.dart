import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/inference/llama_runtime.dart';
import 'package:linqo/inference/local_runtime.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real model generates evidence-linked extraction on target device',
    (tester) async {
      const modelPath = String.fromEnvironment('LINQO_MODEL_PATH');
      expect(
        modelPath,
        isNotEmpty,
        reason: 'Supply --dart-define=LINQO_MODEL_PATH=/device/path/model.gguf',
      );
      expect(await File(modelPath).exists(), isTrue);
      final runtime = LlamaLocalRuntime();
      try {
        await runtime.load(modelPath, const RuntimeSettings());
        final source = SourceDocument(
          'Chickpea skillet\nIngredients: 1 can chickpeas, 1 onion.\nChop the onion, add chickpeas and simmer for 10 minutes.',
        );
        final output = StringBuffer();
        await for (final delta in runtime.extract(source)) {
          output.write(delta);
        }
        final result = ExtractionResult.parse(output.toString(), source);
        expect(result.type, 'recipe');
        expect(result.facts, isNotEmpty);
      } finally {
        await runtime.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
