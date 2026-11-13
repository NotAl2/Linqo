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
  test('hybrid WebPage Article content is not hidden by breadcrumb metadata', () {
    final structured = jsonEncode({
      '@graph': [
        {
          '@type': ['WebPage', 'Article'],
          'url': 'https://example.org/article',
          'articleBody':
              'This is the real article about local model memory and browser storage.',
        },
        {'@type': 'BreadcrumbList', '@id': '#breadcrumb'},
      ],
    });
    final result = extractPageContent(
      html.parse('<script type="application/ld+json">$structured</script>'),
      Uri.parse('https://example.org/article'),
    );
    expect(result['contentKind'], 'article');
    expect(result['content'], contains('real article'));
  });

  test(
    'page metadata keeps unlabelled content and ignores only tracking query fields',
    () {
      for (final article in [false, true]) {
        final content = article
            ? {
                '@type': 'Article',
                'articleBody':
                    'This primary article explains browser storage and cached local files.',
              }
            : {
                '@type': 'Recipe',
                'recipeIngredient': ['2 eggs'],
                'recipeInstructions': ['Fry eggs.'],
              };
        final structured = jsonEncode({
          '@graph': [
            {'@type': 'WebPage', 'url': 'https://example.org/recipe'},
            content,
          ],
        });
        final result = extractPageContent(
          html.parse('<script type="application/ld+json">$structured</script>'),
          Uri.parse('https://example.org/recipe'),
        );
        expect(result['contentKind'], article ? 'article' : 'recipe');
      }
      Map<String, String> parse(String saved, String canonical) {
        final structured = jsonEncode({
          '@type': 'Recipe',
          'url': canonical,
          'recipeIngredient': ['2 eggs'],
          'recipeInstructions': ['Fry eggs.'],
        });
        return extractPageContent(
          html.parse('<script type="application/ld+json">$structured</script>'),
          Uri.parse(saved),
        );
      }

      expect(
        parse(
          'https://example.org/recipe?utm_source=share',
          'https://example.org/recipe',
        )['contentKind'],
        'recipe',
      );
      expect(
        parse(
          'https://example.org/recipe?id=2',
          'https://example.org/recipe?id=1',
        )['contentKind'],
        isNot('recipe'),
      );
    },
  );

  test('merging retains recipe references promoted into general details', () {
    final source = SourceDocument(
      'Useful ingredient fact.\nA useful preparation fact.',
      typeHint: 'general',
    );
    final part = SourcePart(source.lines, 'general');
    final raw = {
      ...output(),
      'ingredient_lines': [1],
      'step_lines': [2],
    };
    final merged = jsonDecode(
      mergeSourceParts(source, [part], [raw], totalParts: 1),
    );
    expect(merged['detail_lines'], [1, 2]);
  });
  test('cross-part duplicate places do not crowd out distinct venues', () {
    final names = List.generate(
      9,
      (i) => 'Venue ${String.fromCharCode(65 + i)}',
    );
    final source = SourceDocument([...names.take(8), ...names].join('\n'));
    final parts = [
      SourcePart(source.lines.take(8).toList(), null),
      SourcePart(source.lines.skip(8).toList(), null),
    ];
    Map<String, dynamic> places(int count) => {
      ...output(),
      'type': 'place',
      'places': List.generate(
        count,
        (i) => {
          'name': names[i],
          'lines': [i + 1],
        },
      ),
    };
    final merged = jsonDecode(
      mergeSourceParts(source, parts, [places(8), places(9)], totalParts: 2),
    );
    final selected = merged['places'] as List;
    expect(selected.length, 9);
    expect(selected.last['name'], 'Venue I');
    expect(selected.first['lines'], [1, 9]);
  });
  test('primary article beats an unrelated JSON-LD recipe recommendation', () {
    final structured = jsonEncode({
      '@graph': [
        {
          '@type': 'WebPage',
          '@id': 'https://example.org/current#page',
          'mainEntity': {'@id': 'https://example.org/current#article'},
        },
        {
          '@type': 'Recipe',
          'url': 'https://example.org/other',
          'recipeIngredient': ['2 eggs'],
          'recipeInstructions': ['Fry the eggs.'],
        },
        {
          '@type': 'Article',
          '@id': 'https://example.org/current#article',
          'articleBody':
              'This is the primary article about browser storage and cached local files.',
        },
      ],
    });
    final doc = html.parse(
      '<script type="application/ld+json">$structured</script>',
    );
    final result = extractPageContent(
      doc,
      Uri.parse('https://example.org/current'),
    );
    expect(result['contentKind'], 'article');
    expect(result['content'], contains('primary article'));
    expect(result['content'], isNot(contains('eggs')));
  });

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
