import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/domain/extraction.dart';

void main() {
  final source = SourceDocument('1 cup chickpeas\n\nSimmer for 10 minutes.\n');
  Map<String, Object> response() => {
    'title': 'Chickpeas',
    'summary': 'Simmer chickpeas.',
    'type': 'recipe',
    'facts': [
      {
        'label': 'Timing',
        'value': '10 minutes',
        'lines': [2],
      },
    ],
  };
  test('assigns stable evidence IDs to nonempty lines', () {
    expect(source.numbered, '[1] 1 cup chickpeas\n[2] Simmer for 10 minutes.');
  });
  test('accepts structured extracts with existing evidence', () {
    final parsed = ExtractionResult.parse(jsonEncode(response()), source);
    expect(parsed.facts.single.lineIds, [2]);
  });
  test('rejects invented evidence references', () {
    final invalid = response()
      ..['facts'] = [
        {
          'label': 'Address',
          'value': 'London',
          'lines': [99],
        },
      ];
    expect(
      () => ExtractionResult.parse(jsonEncode(invalid), source),
      throwsFormatException,
    );
  });
  test('rejects facts with no evidence', () {
    final invalid = response()
      ..['facts'] = [
        {'label': 'Timing', 'value': '10 minutes', 'lines': []},
      ];
    expect(
      () => ExtractionResult.parse(jsonEncode(invalid), source),
      throwsFormatException,
    );
  });

  test('rejects valid line IDs that do not support the quoted detail', () {
    final invalid = response()
      ..['facts'] = [
        {
          'label': 'Ingredient',
          'value': '2 cups rice',
          'lines': [1],
        },
      ];
    expect(
      () => ExtractionResult.parse(jsonEncode(invalid), source),
      throwsFormatException,
    );
  });
  test('preserves Hindi source and output', () {
    final hindi = SourceDocument('चना सलाद\n1 कप चने');
    final parsed = ExtractionResult.parse(
      jsonEncode({
        'title': 'चना सलाद',
        'summary': 'चने का सलाद',
        'type': 'recipe',
        'facts': [
          {
            'label': 'सामग्री',
            'value': '1 कप चने',
            'lines': [2],
          },
        ],
      }),
      hindi,
    );
    expect(parsed.facts.single.value, '1 कप चने');
  });
  test('rejects malformed or truncated output', () {
    expect(
      () => ExtractionResult.parse('{"title":', source),
      throwsFormatException,
    );
  });
  test('accepts an empty facts list without inventing details', () {
    final data = response()
      ..['facts'] = <Object>[]
      ..['type'] = 'general';
    expect(ExtractionResult.parse(jsonEncode(data), source).facts, isEmpty);
  });
}
