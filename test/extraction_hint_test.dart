import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/domain/extraction.dart';

void main() {
  test(
    'explicit note type preserves selected details without recipe warnings',
    () {
      final source = SourceDocument(
        'A weekend plan\nBring a notebook and a camera.\nMeet at 10 AM on Saturday.',
        typeHint: 'general',
      );
      final result = ExtractionResult.parse(
        jsonEncode({
          'schema_version': 2,
          'title': 'Weekend plan',
          'summary': 'Bring a notebook and meet at 10 AM on Saturday.',
          'type': 'recipe',
          'ingredient_lines': [],
          'step_lines': [2],
          'places': [],
          'detail_lines': [3],
        }),
        source,
      );
      expect(result.type, 'general');
      expect(result.recipe, isNull);
      expect(result.warnings, isEmpty);
      expect(
        result.facts.map((f) => f.value),
        containsAll([
          'Bring a notebook and a camera.',
          'Meet at 10 AM on Saturday.',
        ]),
      );
    },
  );
}
