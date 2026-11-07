import 'dart:convert';
import 'dart:io';
import 'package:linqo/domain/extraction.dart';

// Uses the app's real parser and prompt, rather than a separate permissive
// approximation of the evidence schema in Python/JavaScript.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    throw ArgumentError('Pass the private JSONL paths to validate.');
  }
  for (final path in args) {
    final validated = <String>[];
    for (final line in await File(path).readAsLines()) {
      if (line.trim().isEmpty) continue;
      final row = jsonDecode(line) as Map<String, dynamic>;
      final source = SourceDocument(row['source'] as String);
      final target = row['target'] as String;
      if ((jsonDecode(target) as Map)['schema_version'] != 3) {
        throw const FormatException(
          'Reviewed targets must use the current reference schema 3.',
        );
      }
      final result = ExtractionResult.parse(target, source);
      final expected = row['category'] == 'article'
          ? 'general'
          : row['category'];
      if (result.type != expected) {
        throw const FormatException('Reviewed category and target disagree.');
      }
      row['messages'] = [
        {'role': 'system', 'content': extractionInstructions},
        {
          'role': 'user',
          'content': 'SOURCE START\n${source.numbered}\nSOURCE END',
        },
      ];
      validated.add(jsonEncode(row));
    }
    await File(path).writeAsString('${validated.join('\n')}\n', flush: true);
  }
  stdout.writeln(
    'Reviewed targets passed the Linqo evidence parser; prompts match the app.',
  );
}
