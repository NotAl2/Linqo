import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/domain/source_rules.dart';
import 'package:linqo/sharing/source_content.dart';
import 'package:linqo/ui/extracted_details.dart';
import 'package:linqo/theme.dart';

String response({
  String type = 'recipe',
  List<int> summary = const [],
  List<int> steps = const [],
  List<int> details = const [],
}) => jsonEncode({
  'schema_version': 3,
  'title': 'Saved content',
  'type': type,
  'summary_lines': summary,
  'ingredient_lines': [],
  'step_lines': steps,
  'detail_lines': details,
  'places': [],
});
void main() {
  testWidgets('article highlights do not repeat their title', (tester) async {
    const result = ExtractionResult(
      title: 'Local AI',
      summary:
          'Local AI … Smaller models use less memory. … Keep enough memory free for other apps.',
      type: 'general',
      facts: [],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExtractedDetails(result: result)),
      ),
    );
    expect(find.text('Local AI'), findsNothing);
    expect(find.text('Smaller models use less memory.'), findsOneWidget);
  });
  test(
    'single-paragraph recipe captions become grounded ingredients and steps',
    () {
      const caption =
          'Sunday pasta! Serves 2. Ingredients: 200 g pasta, 2 tomatoes, 1 tbsp olive oil. Boil pasta for 10 minutes. Chop tomatoes and mix with pasta.';
      final source = SourceDocument.segmented(caption);
      expect(SourceRules.classify(source), 'recipe');
      final result = ExtractionResult.parse(response(), source);
      expect(result.recipe!.ingredients.length, 3);
      expect(result.recipe!.steps.length, 2);
      for (final fact in result.facts) {
        expect(caption.contains(fact.value), isTrue);
      }
    },
  );
  const tech =
      'Local models need memory\nAdd MakeUseOf on Google\nAdd as Preferred Source\nLocal models run on your hardware.\nSmaller quantized models use less memory.\nYadullah Abidi is a Computer Science graduate from the University of Delhi.';
  test('publisher controls are never recipe evidence, even in old outputs', () {
    final source = SourceDocument(tech);
    expect(SourceRules.classify(source), 'general');
    expect(SourceRules.recipeLines(source).steps, isEmpty);
    final result = ExtractionResult.parse(
      response(summary: [2, 3], steps: [2, 3], details: [6]),
      source,
    );
    expect(result.type, 'general');
    expect(result.recipe, isNull);
    expect(result.summary, isNot(contains('Preferred Source')));
    expect(result.facts, isEmpty);
    expect(result.summary, isNot(contains('graduate')));
  });
  test('readable article omits author bios and preferred-source widgets', () {
    final parsed = extractPageContent(
      html.parse(
        '<article><div class="author-bio">Writer background and history</div><div>Add MakeUseOf on Google</div><div>Add as Preferred Source</div><p>Local models run on your own hardware and need enough memory to hold their weights and active context.</p><p>A smaller quantized model reduces storage requirements and leaves more room for other apps.</p></article>',
      ),
      Uri.parse('https://example.com/tech'),
    );
    expect(parsed['contentKind'], 'article');
    expect(parsed['content'], isNot(contains('Writer background')));
    expect(parsed['content'], isNot(contains('Preferred Source')));
    expect(parsed['content'], contains('quantized model'));
  });
  testWidgets(
    'recipe shows stated yield, ingredients and steps without dropdowns',
    (tester) async {
      final result = ExtractionResult.parse(
        response(),
        SourceDocument(
          'Sunday pasta\nServes 2\nIngredients:\n200 g pasta\n2 tomatoes\nMethod:\nBoil pasta for 10 minutes.\nChop tomatoes and mix with pasta.',
        ),
      );
      expect(result.recipe?.servings, 'Serves 2');
      await tester.pumpWidget(
        MaterialApp(
          theme: linqoTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExtractedDetails(result: result),
            ),
          ),
        ),
      );
      expect(find.text('Ingredients'), findsOneWidget);
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('200 g pasta'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test('missing serving size is not guessed', () {
    final result = ExtractionResult.parse(
      response(),
      SourceDocument(
        'Toast\nIngredients:\n1 slice bread\nMethod:\nToast the bread.',
      ),
    );
    expect(result.recipe?.servings, isNull);
  });
  test('classification distinguishes setup instructions and places', () {
    expect(
      SourceRules.classify(
        SourceDocument('Setup guide\nInstall the package.\nOpen the app.'),
      ),
      'tutorial',
    );
    expect(
      SourceRules.classify(
        SourceDocument(
          'Place: National Gallery\nAddress: Trafalgar Square, London',
        ),
      ),
      'place',
    );
  });
}
