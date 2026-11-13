import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/validate_training_dataset.dart' as validator;

void main() {
  late Directory work;
  late File train, evaluation;
  late String original;
  setUp(() async {
    work = await Directory.systemTemp.createTemp('linqo-dataset-validation-');
    train = File('${work.path}/train.jsonl');
    evaluation = File('${work.path}/eval.jsonl');
    original =
        '${jsonEncode({
          'source': 'Browser caches are stored locally.',
          'category': 'general',
          'target': jsonEncode({
            'schema_version': 3,
            'title': 'Browser cache',
            'type': 'general',
            'summary_lines': [1],
            'ingredient_lines': [],
            'step_lines': [],
            'places': [],
            'detail_lines': [],
          }),
        })}\n';
    await train.writeAsString(original);
    await evaluation.writeAsString(original);
  });
  tearDown(() => work.delete(recursive: true));

  test(
    'a later invalid split leaves every original untouched and cleans staging',
    () async {
      await evaluation.writeAsString('invalid json\n');
      await expectLater(
        validator.main([train.path, evaluation.path]),
        throwsFormatException,
      );
      expect(await train.readAsString(), original);
      expect(await evaluation.readAsString(), 'invalid json\n');
      expect(await work.list().length, 2);
    },
  );

  test(
    'all valid splits are replaced with app prompts and staging is removed',
    () async {
      await validator.main([train.path, evaluation.path]);
      for (final file in [train, evaluation]) {
        final text = await file.readAsString();
        final row = jsonDecode(text) as Map;
        expect(text.endsWith('\n'), isTrue);
        expect(row['messages'], hasLength(2));
        expect(row['messages'][1]['content'], contains('[1] Browser caches'));
      }
      expect(await work.list().length, 2);
    },
  );
}
