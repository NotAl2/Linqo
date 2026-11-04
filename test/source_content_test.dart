import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/sharing/link_preview.dart';

void main() {
  test('generic Maps viewer text is not treated as the saved place data', () {
    final result = parsePreviewHtml(
      '<title>Google Maps</title><main><p>${'A map of an unrelated viewer area. ' * 8}</p></main>',
      Uri.parse('https://maps.google.com/?q=National+Gallery+London'),
    );
    expect(result['contentKind'], 'place_link');
    expect(result['content'], contains('National Gallery London'));
    expect(result['content'], isNot(contains('unrelated')));
  });
  test(
    'Instagram retains a full caption and final recipe step, not a 400-character preview',
    () {
      final caption =
          'Ingredients: flour, water and salt.\n${List.filled(30, 'Mix gently and allow the dough to rest.').join('\n')}\nBake for 20 minutes. Serve warm.';
      final result = parsePreviewHtml(
        '<title>Instagram</title><div class="Caption"><a class="CaptionUsername">author</a>${htmlEscape.convert(caption)}<div class="CaptionComments">View all comments</div></div>',
        Uri.parse('https://www.instagram.com/p/example/embed/captioned/'),
      );
      expect(result['content'], caption);
      expect(result['contentKind'], 'caption');
      expect(result['description']!.length, lessThanOrEqualTo(400));
      expect(result['content'], isNot(contains('View all comments')));
      expect(result['content'], isNot(contains('author')));
    },
  );
  test(
    'Instagram metadata caption strips engagement wrapper without inventing text',
    () {
      final result = parsePreviewHtml(
        '<meta property="og:description" content="42 likes, 3 comments - chef on June 1: &quot;Chop onions.\nCook until soft.&quot;">',
        Uri.parse('https://www.instagram.com/reel/example/'),
      );
      expect(result['content'], 'Chop onions.\nCook until soft.');
      expect(
        parsePreviewHtml(
          '<meta property="og:description" content="12 likes, 3 comments">',
          Uri.parse('https://www.instagram.com/p/example/'),
        )['content'],
        isEmpty,
      );
    },
  );
  test(
    'structured recipe keeps ingredients and nested ordered steps, without comments/navigation',
    () {
      final recipe = {
        '@graph': [
          {'@type': 'WebPage'},
          {
            '@type': ['Recipe'],
            'name': 'Simple soup',
            'recipeYield': '2 servings',
            'recipeIngredient': ['2 tomatoes', '1 cup water'],
            'recipeInstructions': [
              {
                '@type': 'HowToSection',
                'name': 'Prepare',
                'itemListElement': [
                  {'@type': 'HowToStep', 'text': 'Chop the tomatoes.'},
                  {
                    '@type': 'HowToStep',
                    'text': '<p>Add water.</p><p>Simmer for 15 minutes.</p>',
                  },
                ],
              },
              {'@type': 'HowToStep', 'text': 'Serve warm.'},
            ],
          },
        ],
      };
      final result = parsePreviewHtml(
        '<nav>Subscribe now</nav><script type="application/ld+json">${jsonEncode(recipe)}</script><article>Wrong generic article content with a very long introduction and unrelated comments.</article>',
        Uri.parse('https://example.org/soup'),
      );
      expect(result['contentKind'], 'recipe');
      expect(
        result['content'],
        contains('Ingredients:\n2 tomatoes\n1 cup water'),
      );
      expect(result['content'], contains('Chop the tomatoes.'));
      expect(result['content'], contains('Simmer for 15 minutes.'));
      expect(result['content'], endsWith('Serve warm.'));
      expect(result['content'], isNot(contains('Subscribe')));
      expect(result['content'], isNot(contains('Wrong generic')));
    },
  );
  test(
    'readable article excludes embedded scripts, navigation and related content',
    () {
      final result = parsePreviewHtml(
        '<main><nav>Sign up for spam</nav><article><h1>A useful guide</h1><p>This is the first paragraph of the article. It has useful details for the reader to keep.</p><p>This is the second paragraph with the remaining important source details.</p><script>stealCookies()</script><aside>Recommended unrelated content</aside></article></main>',
        Uri.parse('https://example.org/guide'),
      );
      expect(result['contentKind'], 'article');
      expect(result['content'], contains('remaining important source details'));
      expect(result['content'], isNot(contains('stealCookies')));
      expect(result['content'], isNot(contains('Recommended')));
      expect(result['content'], isNot(contains('spam')));
    },
  );
  test(
    'YouTube uses the actual matching video description, never a pretend transcript',
    () {
      final data = jsonEncode({
        'videoDetails': {
          'videoId': 'aqz-KE-bpKQ',
          'shortDescription':
              'A public description with {braces} and "quotes".\nCreator details.',
        },
      });
      final page =
          '<script>var ytInitialPlayerResponse = $data; ignored();</script>';
      final result = parsePreviewHtml(
        page,
        Uri.parse('https://www.youtube.com/watch?v=aqz-KE-bpKQ'),
      );
      expect(result['contentKind'], 'video_description');
      expect(result['content'], contains('Creator details.'));
      expect(
        parsePreviewHtml(
          page,
          Uri.parse('https://www.youtube.com/watch?v=WRONG-ID-00'),
        )['content'],
        isEmpty,
      );
      expect(
        parsePreviewHtml(
          '<title>A video title</title><meta name="description" content="Video by an author">',
          Uri.parse('https://www.youtube.com/watch?v=aqz-KE-bpKQ'),
        )['content'],
        isEmpty,
      );
    },
  );
  test(
    'login walls do not become extraction content and long text is marked partial',
    () {
      final blocked = parsePreviewHtml(
        '<title>Log in • Instagram</title><main>${'Log in to continue. ' * 20}</main>',
        Uri.parse('https://www.instagram.com/accounts/login/'),
      );
      expect(blocked['content'], isNull);
      final long = parsePreviewHtml(
        '<article><p>${'Useful source text. ' * 2000}</p></article>',
        Uri.parse('https://example.org/long'),
      );
      expect(long['content']!.length, lessThanOrEqualTo(30000));
      expect(long['contentStatus'], 'partial');
    },
  );
}
