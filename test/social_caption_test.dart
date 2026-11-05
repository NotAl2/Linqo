import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/domain/source_rules.dart';

void main() {
  test(
    'social footer is not recovered as ingredients and missing methods stay missing',
    () {
      final source = SourceDocument('''A creamy coffee drink.
Ingredients:
• 1 tsp instant coffee + 1 tbsp hot water
• 1 tsp honey
• 1 tsp brown sugar
• Ice
• Milk of choice
Please follow me & share my work for more Coffee Content :)
@a_creator
.
.
#coffee #homebarista''');
      final rules = SourceRules.recipeLines(source);
      expect(rules.ingredients, {3, 4, 5, 6, 7});
      expect(rules.steps, isEmpty);
      final result = ExtractionResult.parse(
        jsonEncode({
          'schema_version': 2,
          'title': 'Coffee drink',
          'summary':
              'Includes ingredients and instructions for a coffee drink.',
          'type': 'recipe',
          'ingredient_lines': [3],
          'step_lines': [1, 8, 9, 10, 11, 12],
          'places': [],
          'detail_lines': [],
        }),
        source,
      );
      expect(result.recipe!.ingredients, hasLength(5));
      expect(result.recipe!.steps, isEmpty);
      expect(result.warnings, isNotEmpty);
      expect(result.summary, contains('instant coffee'));
      expect(result.summary, isNot(contains('instructions for')));
      expect(
        result.recipe!.ingredients.any(
          (i) => i.value.contains('follow') || i.value.contains('#coffee'),
        ),
        isFalse,
      );
    },
  );
  test(
    'method validation keeps legitimate less common and conditional instructions',
    () {
      for (final line in [
        'Whip until fluffy.',
        'Steam the vegetables.',
        'Soak chickpeas overnight.',
        'Then flip the pancakes.',
        'Once the sauce thickens, add milk.',
        '2. Leave in a warm place overnight.',
      ]) {
        expect(SourceRules.isPreparationText(line), isTrue, reason: line);
      }
      expect(
        SourceRules.isPreparationText('This latte is creamy and delicious.'),
        isFalse,
      );
      expect(
        SourceRules.isPreparationText('Please follow me for more recipes.'),
        isFalse,
      );
    },
  );
  test(
    'footer filtering does not discard real preparation or later method sections',
    () {
      final source = SourceDocument('''Ingredients:
2 tomatoes
@creator
#recipe
Method:
Chop the tomatoes.
Add water and simmer.
Serve with bread.''');
      final rules = SourceRules.recipeLines(source);
      expect(rules.ingredients, {2});
      expect(rules.steps, {6, 7, 8});
    },
  );
}
