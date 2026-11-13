import 'dart:convert';
import 'dart:io';
import 'package:linqo/domain/extraction.dart';

// Uses the app's real parser and prompt, rather than a separate permissive
// approximation of the evidence schema in Python/JavaScript.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    throw ArgumentError('Pass the private JSONL paths to validate.');
  }
  final staged = <String, File>{};
  final work = <Directory>[];
  try {
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
      final directory = await File(path).parent.createTemp('.linqo-validated-');
      work.add(directory);
      final temporary = await File(path).copy('${directory.path}/validated.jsonl');
      await temporary.writeAsString('${validated.join('\n')}\n', flush: true);
      staged[path] = temporary;
    }
    // shortcut: replacement is atomic per file; use a transaction if cross-file crash recovery is needed.
    for (final entry in staged.entries) {
      await entry.value.rename(entry.key);
    }
  } finally {
    for (final directory in work) {
      await directory.delete(recursive: true);
    }
  }
  stdout.writeln(
    'Reviewed targets passed the Linqo evidence parser; prompts match the app.',
  );
}
