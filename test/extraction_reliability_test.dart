import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/domain/evidence_matcher.dart';
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/prototype/lab_screen.dart';

Map<String, Object> selection({
  String type = 'recipe',
  List<int> ingredients = const [],
  List<int> steps = const [],
  List<Map<String, Object>> places = const [],
  List<int> details = const [],
}) => {
  'schema_version': 2,
  'title': 'Saved source',
  'summary': 'A short source summary.',
  'type': type,
  'ingredient_lines': ingredients,
  'step_lines': steps,
  'places': places,
  'detail_lines': details,
};

void main() {
  test(
    'source structure repairs model ingredient and step category conflicts',
    () {
      final result = ExtractionResult.parse(
        jsonEncode(selection(ingredients: [2, 3, 4, 5], steps: [2, 6])),
        SourceDocument(englishSample),
      );
      expect(result.recipe!.ingredients.map((f) => f.lineIds.single), [2]);
      expect(result.recipe!.steps.map((f) => f.lineIds.single), [3, 4, 5, 6]);
      expect(result.isPartial, isFalse);
    },
  );

  test(
    'typed places repair a wrong recipe enum without fake recipe warnings',
    () {
      final result = ExtractionResult.parse(
        jsonEncode(
          selection(
            places: [
              {
                'name': 'Monmouth Coffee',
                'lines': [2],
              },
              {
                'name': 'Tate Modern',
                'lines': [3],
              },
              {
                'name': 'South Bank',
                'lines': [4],
              },
            ],
          ),
        ),
        SourceDocument(placesSample),
      );
      expect(result.type, 'place');
      expect(result.recipe, isNull);
      expect(result.places, hasLength(3));
      expect(result.isPartial, isFalse);
    },
  );

  test(
    'recovers every missing English method and serving line from the phone fixture',
    () {
      final source = SourceDocument(englishSample);
      final result = ExtractionResult.parse(
        jsonEncode(selection(ingredients: [2])),
        source,
      );
      expect(result.recipe!.steps.map((step) => step.lineIds.single), [
        3,
        4,
        5,
        6,
      ]);
      expect(
        result.recipe!.steps[2].value,
        'Simmer for 10 minutes. Stir in the spinach.',
      );
      expect(result.recipe!.steps.last.origin, FactOrigin.sourceRule);
      expect(result.isPartial, isFalse);
    },
  );

  test(
    'Hindi selection preserves quantities, steps and the original danda without model recopying',
    () {
      final source = SourceDocument(hindiSample);
      final result = ExtractionResult.parse(
        jsonEncode(selection(ingredients: [2], steps: [3])),
        source,
      );
      expect(result.recipe!.ingredients.single.value, source.lines[1].text);
      expect(result.recipe!.steps.map((step) => step.lineIds.single), [
        3,
        4,
        5,
      ]);
      expect(
        result.recipe!.steps.every((step) => step.value.endsWith('।')),
        isTrue,
      );
      expect(result.isPartial, isFalse);
    },
  );

  test(
    'accepts the actual old Hindi punctuation failure and displays original source punctuation',
    () {
      final source = SourceDocument(hindiSample);
      final result = ExtractionResult.parse(
        jsonEncode({
          'title': 'चना सलाद',
          'summary': 'चना सलाद की विधि।',
          'type': 'recipe',
          'facts': [
            {
              'label': 'Ingredients',
              'value': '1 कप उबले चने, 1 टमाटर, 1 प्याज़, नींबू का रस.',
              'lines': [2],
            },
          ],
        }),
        source,
      );
      expect(result.recipe!.ingredients.single.value, source.lines[1].text);
      expect(result.recipe!.steps, hasLength(3));
    },
  );

  test(
    'recovers actual venue names when the model selects only surrounding areas',
    () {
      final source = SourceDocument(placesSample);
      final result = ExtractionResult.parse(
        jsonEncode(
          selection(
            type: 'place',
            places: [
              {
                'name': 'Borough Market.',
                'lines': [2],
              },
              {
                'name': 'Bankside.',
                'lines': [3],
              },
            ],
          ),
        ),
        source,
      );
      final names = result.places.map((place) => place.name).toList();
      expect(
        names,
        containsAll(['Monmouth Coffee', 'Tate Modern', 'South Bank']),
      );
      expect(
        result.places
            .firstWhere((place) => place.name == 'Tate Modern')
            .lineIds,
        [3],
      );
      expect(result.isPartial, isFalse);
    },
  );

  test('name recovery generalizes to unseen names and internal connectors', () {
    final source = SourceDocument(
      'Weekend\nHave lunch at Cedar & Finch in Manchester.\nVisit the Museum of Modern Art on Queens Road.',
    );
    final result = ExtractionResult.parse(
      jsonEncode(selection(type: 'place')),
      source,
    );
    expect(
      result.places.map((place) => place.name),
      containsAll(['Cedar & Finch', 'Museum of Modern Art']),
    );
  });

  test('ingredient-only source is partial rather than inventing a method', () {
    final result = ExtractionResult.parse(
      jsonEncode(selection(ingredients: [2])),
      SourceDocument('Dinner\nIngredients: 1 onion, 1 can chickpeas.'),
    );
    expect(result.recipe!.steps, isEmpty);
    expect(result.isPartial, isTrue);
  });

  test('uncategorized recipe safety notes remain visible and require review', () {
    final result = ExtractionResult.parse(
      jsonEncode(selection(ingredients: [2])),
      SourceDocument(
        'Dinner\nIngredients: 1 onion.\nChop the onion.\nImportant: this recipe contains nuts.',
      ),
    );
    expect(result.additionalSource.single.text, contains('contains nuts'));
    expect(result.isPartial, isTrue);
  });

  test('sectioned ingredients and numbered directions retain their order', () {
    final source = SourceDocument(
      'Soup\nIngredients:\n- 1 onion\n- 2 cups stock\nMethod:\n1. Chop the onion.\n2. Cook for 10 minutes.',
    );
    final result = ExtractionResult.parse(jsonEncode(selection()), source);
    expect(result.recipe!.ingredients.map((line) => line.lineIds.single), [
      3,
      4,
    ]);
    expect(result.recipe!.steps.map((line) => line.lineIds.single), [6, 7]);
    expect(result.isPartial, isFalse);
  });

  test(
    'reference schema rejects nonexistent line IDs and invented place names',
    () {
      final source = SourceDocument('Visit Tate Modern.');
      expect(
        () =>
            ExtractionResult.parse(jsonEncode(selection(steps: [999])), source),
        throwsFormatException,
      );
      expect(
        () => ExtractionResult.parse(
          jsonEncode(
            selection(
              type: 'place',
              places: [
                {
                  'name': 'Imaginary Cafe',
                  'lines': [1],
                },
              ],
            ),
          ),
          source,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'matching preserves emoji offsets, smart quotes and nonbreaking spaces',
    () {
      expect(
        EvidenceMatcher.originalSpan(
          '🍲 “नींबू\u00a0का रस।”',
          '"नींबू का रस."',
        ),
        '“नींबू\u00a0का रस।”',
      );
    },
  );

  test(
    'punctuation handling never erases decimal, fraction, amount or unit differences',
    () {
      for (final pair in [
        ('Use 1.5 g salt.', '15 g salt.'),
        ('Use 1/2 cup milk.', '12 cup milk.'),
        ('Use 15 g salt.', '5 g salt.'),
        ('Use 1.5 g salt.', '1'),
        ('Use 1 tbsp oil.', '1 tsp oil.'),
        ('Use 1।5 g salt.', '1.5 g salt.'),
      ]) {
        expect(
          EvidenceMatcher.originalSpan(pair.$1, pair.$2),
          isNull,
          reason: '${pair.$1} / ${pair.$2}',
        );
      }
    },
  );

  test(
    'v1 substring selection cannot remove negation from the displayed fact',
    () {
      final result = ExtractionResult.parse(
        jsonEncode({
          'title': 'Note',
          'summary': 'A note.',
          'type': 'general',
          'facts': [
            {
              'label': 'Instruction',
              'value': 'add salt',
              'lines': [1],
            },
          ],
        }),
        SourceDocument('Do not add salt.'),
      );
      expect(result.facts.single.value, 'Do not add salt.');
    },
  );
}
