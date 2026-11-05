import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/domain/source_parts.dart';
import 'package:linqo/domain/source_rules.dart';
import 'package:linqo/sharing/source_content.dart';

Map<String, dynamic> output({
  List<int> summary = const [1],
  List<int> details = const [],
}) => {
  'schema_version': 3,
  'title': 'Saved source',
  'type': 'general',
  'summary_lines': summary,
  'ingredient_lines': [],
  'step_lines': [],
  'places': [],
  'detail_lines': details,
};
void main() {
  test(
    'v3 highlights and legacy summaries cannot add unsupported descriptions or quantities',
    () {
      final source = SourceDocument(
        'Cook chickpeas with spinach.\nServe with rice.',
      );
      final legacy = ExtractionResult.parse(
        jsonEncode({
          'schema_version': 2,
          'title': 'Recipe',
          'summary': 'A spicy, protein-rich meal for four people.',
          'type': 'recipe',
          'ingredient_lines': [],
          'step_lines': [1, 2],
          'places': [],
          'detail_lines': [],
        }),
        source,
      );
      expect(legacy.summary, 'Cook chickpeas with spinach. … Serve with rice.');
      final current = ExtractionResult.parse(
        jsonEncode(output(summary: [2])),
        source,
      );
      expect(current.summary, 'Serve with rice.');
      expect(
        () => ExtractionResult.parse(jsonEncode(output(summary: [3])), source),
        throwsFormatException,
      );
    },
  );
  test(
    'long paragraphs split into source spans and token-aware plans retain every line',
    () async {
      final text = List.generate(
        100,
        (i) => 'Source sentence $i describes a quiet walk beside the river.',
      ).join(' ');
      final source = SourceDocument.segmented(text);
      expect(source.lines.length, greaterThan(10));
      expect(
        source.lines.every(
          (l) => l.text.length <= 240 && text.contains(l.text),
        ),
        isTrue,
      );
      final parts = await planSourceParts(
        source,
        (part) async => part.lines.length <= 2,
      );
      expect(
        parts.expand((p) => p.lines).map((l) => l.id).toList(),
        source.lines.map((l) => l.id).toList(),
      );
      final outputs = parts
          .map((p) => output(summary: [p.lines.length], details: [1]))
          .toList();
      final merged = mergeSourceParts(
        source,
        parts,
        outputs,
        totalParts: parts.length,
      );
      final result = ExtractionResult.parse(merged, source);
      for (final excerpt in result.summary.split(' … ')) {
        expect(text.contains(excerpt), isTrue);
      }
      expect(result.facts.last.lineIds.single, parts.last.lines.first.id);
    },
  );
  test(
    'verified earlier parts survive later failure with explicit partial coverage',
    () async {
      final source = SourceDocument('First fact.\nSecond fact.\nLast fact.');
      final parts = await planSourceParts(
        source,
        (part) async => part.lines.length == 1,
      );
      final result = ExtractionResult.parse(
        mergeSourceParts(source, parts, [
          output(details: [1]),
        ], totalParts: parts.length),
        source,
      );
      expect(result.isPartial, isTrue);
      expect(result.warnings.join(), contains('1 of 3'));
      expect(result.summary, 'First fact.');
      expect(source.text, contains('Last fact.'));
    },
  );
  test(
    'article body is preferred over surrounding follow and thread controls',
    () {
      final document = html.parse(
        '<main><div role="button">Follow</div><p>Followed</p><div>Thread 5</div>'
        '<div class="article-body"><p>${'Original article sentence about local memory. ' * 5}</p></div></main>',
      );
      final result = extractPageContent(
        document,
        Uri.parse('https://example.org/article'),
      );
      expect(result['content'], contains('Original article sentence'));
      expect(result['content'], isNot(contains('Follow')));
      expect(result['content'], isNot(contains('Thread')));
    },
  );
  test(
    'one inconsistent part does not relabel an entire article as a recipe',
    () async {
      final source = SourceDocument('First fact.\nSecond fact.\nLast fact.');
      final parts = await planSourceParts(
        source,
        (p) async => p.lines.length == 1,
      );
      final outputs = [
        output(details: [1]),
        output(details: [1]),
        {
          ...output(details: [1]),
          'type': 'recipe',
        },
      ];
      final result = ExtractionResult.parse(
        mergeSourceParts(source, parts, outputs, totalParts: 3),
        source,
      );
      expect(result.type, 'general');
      expect(result.isPartial, isFalse);
    },
  );
  test(
    'ordinary articles default to general while recipes and actual venues retain recognition',
    () {
      expect(
        SourceRules.articleHint(
          SourceDocument(
            'Local models need memory.\nAdd this website on Google.',
          ),
        ),
        'general',
      );
      expect(
        SourceRules.articleHint(
          SourceDocument('Ingredients:\n2 onions\nMethod:\nChop the onions.'),
        ),
        isNull,
      );
      expect(
        SourceRules.articleHint(
          SourceDocument('Visit the Tate Modern in London.'),
        ),
        isNull,
      );
      final page = html.parse(
        '<article><div class="article-body"><p>${'Real original text. ' * 10}</p>'
        '<div class="w-google-addus-btn">Add as Preferred Source</div>'
        '<figcaption style="display: none;">Credit Example/MUO</figcaption></div></article>',
      );
      final text = extractPageContent(
        page,
        Uri.parse('https://example.org'),
      )['content']!;
      expect(text, isNot(contains('Preferred Source')));
      expect(text, isNot(contains('Credit Example')));
    },
  );
}
