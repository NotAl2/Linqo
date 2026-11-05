import 'dart:convert';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'shared_content.dart';

/// Public page content only. No scripts, login, transcript or media download.
/// Runs with the metadata parser on its worker isolate.
Map<String, String> extractPageContent(Document document, Uri uri) {
  Map<String, String> result(String text, String kind) {
    text = text.trim();
    final truncated = text.length > 30000;
    return {
      'content': cleanContentText(text, 30000),
      'contentKind': text.isEmpty ? '' : kind,
      'contentStatus': text.isEmpty
          ? 'unavailable'
          : truncated
          ? 'partial'
          : 'ready',
    };
  }

  String meta(String key) =>
      document
          .querySelector('meta[property="$key"], meta[name="$key"]')
          ?.attributes['content'] ??
      '';

  if (isHost(uri.host, 'instagram.com')) {
    final caption = document.querySelector('.Caption');
    if (caption != null) {
      final text = _nodeText(caption);
      if (text.isNotEmpty) return result(text, 'caption');
    }
    final description = meta('og:description');
    final quoted = RegExp(
      r':\s*["“](.+)["”]\s*\.?$',
      dotAll: true,
    ).firstMatch(description);
    if (quoted != null) {
      final excerpt = result(_plain(quoted[1]!), 'caption_excerpt');
      excerpt['contentStatus'] = 'partial';
      return excerpt;
    }
    // Engagement counters, generic Instagram blurbs and a post's title are
    // not substitutes for a caption.
    return result('', '');
  }

  if (isHost(uri.host, 'youtube.com') || uri.host == 'youtu.be') {
    for (final script in document.querySelectorAll('script')) {
      final match = RegExp(
        r'(?:var\s+)?ytInitialPlayerResponse\s*=\s*',
      ).firstMatch(script.text);
      if (match == null) continue;
      final object = _jsonObject(script.text, match.end);
      final details = object?['videoDetails'];
      if (details is! Map) continue;
      final id = uri.queryParameters['v'];
      if (id != null && details['videoId'] != id) continue;
      final description = details['shortDescription'];
      if (description is String && description.trim().isNotEmpty) {
        return result(description, 'video_description');
      }
    }
    return result('', '');
  }

  final objects = <Map>[];
  var visited = 0;
  void collect(Object? value, [int depth = 0]) {
    if (depth > 12 || ++visited > 2000) return;
    if (value is List) {
      for (final child in value.take(200)) {
        collect(child, depth + 1);
      }
    } else if (value is Map) {
      objects.add(value);
      // Main entities precede incidental objects such as recommended links.
      collect(value['mainEntity'], depth + 1);
      collect(value['@graph'], depth + 1);
    }
  }

  for (final script in document.querySelectorAll(
    'script[type="application/ld+json"]',
  )) {
    if (script.text.length > 512 * 1024) continue;
    try {
      collect(jsonDecode(script.text));
    } on FormatException {
      /* Next block. */
    }
  }
  bool type(Map object, String name) {
    final value = object['@type'];
    return value == name || value is List && value.contains(name);
  }

  for (final recipe in objects.where((o) => type(o, 'Recipe'))) {
    final ingredients = <String>[];
    final raw = recipe['recipeIngredient'];
    if (raw is List) {
      for (final item in raw.take(200)) {
        if (item is String) ingredients.add(_plain(item));
        if (item is Map) {
          ingredients.add(
            [item['value'], item['name']]
                .whereType<Object>()
                .where((v) => v is String || v is num)
                .join(' '),
          );
        }
      }
    }
    final steps = <String>[];
    void instructions(Object? value, [int depth = 0]) {
      if (depth > 10 || steps.length >= 200) return;
      if (value is String) {
        steps.add(_plain(value));
      }
      if (value is List) {
        for (final step in value.take(200)) {
          instructions(step, depth + 1);
        }
      }
      if (value is Map) {
        if (value['text'] is String) {
          instructions(value['text'], depth + 1);
        } else if (value['name'] is String) {
          instructions(value['name'], depth + 1);
        }
        instructions(value['itemListElement'], depth + 1);
      }
    }

    instructions(recipe['recipeInstructions']);
    if (ingredients.isEmpty && steps.isEmpty) continue;
    final lines = <String>[
      if (recipe['name'] is String) _plain(recipe['name'] as String),
      for (final field in [
        ('recipeYield', 'Servings'),
        ('prepTime', 'Prep time'),
        ('cookTime', 'Cook time'),
        ('totalTime', 'Total time'),
      ])
        if (recipe[field.$1] is String || recipe[field.$1] is num)
          '${field.$2}: ${recipe[field.$1]}',
      if (ingredients.isNotEmpty) 'Ingredients:',
      ...ingredients,
      if (steps.isNotEmpty) 'Steps:',
      ...steps,
    ];
    return result(lines.join('\n'), 'recipe');
  }
  for (final object in objects) {
    final body = object['articleBody'];
    if (body is String && body.trim().length >= 40) {
      return result(_plain(body), 'article');
    }
    if (type(object, 'Place') ||
        type(object, 'LocalBusiness') ||
        type(object, 'Restaurant')) {
      final address = object['address'];
      final lines = <String>[
        if (object['name'] is String) 'Place: ${object['name']}',
        if (address is String) 'Address: $address',
        if (address is Map) address.values.whereType<String>().join(', '),
        if (object['openingHours'] is String)
          'Opening hours: ${object['openingHours']}',
        if (object['telephone'] is String) 'Phone: ${object['telephone']}',
      ];
      if (lines.length > 1) return result(lines.join('\n'), 'place');
    }
  }
  if (uri.host == 'maps.google.com' ||
      isHost(uri.host, 'google.com') && uri.path.startsWith('/maps')) {
    final name = fallbackLinkTitle(uri);
    return result(
      name == 'Saved place' ? '' : 'Place name from saved link: $name',
      'place_link',
    );
  }
  final candidates = document.querySelectorAll(
    '[itemprop="articleBody"], .article-body, .entry-content, .post-content',
  );
  // Prefer the article body over a surrounding <main> containing follows,
  // comments, recommended stories and site controls.
  final preferred = candidates.isNotEmpty
      ? candidates
      : document.querySelectorAll('article, main, [role="main"]');
  for (final candidate in preferred) {
    final text = _nodeText(candidate);
    if (text.length >= 80) return result(text, 'article');
  }
  // Fallback to prose paragraphs, never the entire navigation-heavy body.
  final paragraphs = document
      .querySelectorAll('body p')
      .where((p) {
        for (var parent = p.parent; parent != null; parent = parent.parent) {
          if ([
            'nav',
            'footer',
            'header',
            'aside',
            'form',
            'dialog',
          ].contains(parent.localName)) {
            return false;
          }
        }
        return p.text.trim().length >= 60 &&
            p.querySelectorAll('a').fold<int>(0, (n, a) => n + a.text.length) <
                p.text.length / 2;
      })
      .take(100)
      .map(_nodeText)
      .toList();
  if (paragraphs.length >= 2) return result(paragraphs.join('\n\n'), 'article');
  final description = meta('og:description').isNotEmpty
      ? meta('og:description')
      : meta('description');
  return result(_plain(description), 'page_description');
}

String cleanContentText(String text, int limit) {
  final cleaned = text
      .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '')
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[\t \u00a0]+'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (cleaned.length <= limit) return cleaned;
  var end = limit;
  final unit = cleaned.codeUnitAt(end - 1);
  if (unit >= 0xd800 && unit <= 0xdbff) end--;
  return cleaned.substring(0, end).trimRight();
}

/// Keep sender text while adding a public source; never mix in personal notes.
String mergeSharedContent(String shared, String fetched) {
  if (shared.trim().isEmpty) return fetched;
  if (shared.contains(fetched)) return shared;
  if (fetched.contains(shared.trim())) return fetched;
  return 'Shared text:\n${shared.trim()}\n\nFetched content:\n$fetched';
}

String _plain(String text) => _nodeText(html.parseFragment(text));
String _nodeText(Node node) {
  final copy = node.clone(true);
  if (copy is Element || copy is DocumentFragment) {
    final elements = copy is Element
        ? copy.querySelectorAll(
            'script, style, noscript, nav, footer, header, aside, form, dialog, button, svg, iframe, .CaptionUsername, .CaptionComments, [hidden], [aria-hidden="true"], [role="button"], [role="navigation"], .comments, .related-posts, .cookie-banner, .valnet-threads, [data-component="threads"]',
          )
        : (copy as DocumentFragment).querySelectorAll(
            'script, style, noscript, iframe',
          );
    for (final element in elements) {
      element.remove();
    }
    if (copy is Element) {
      for (final control in copy.querySelectorAll(
        '[class*="w-google-addus-btn"]',
      )) {
        control.remove();
      }
      for (final hidden in copy.querySelectorAll('[style]')) {
        if (RegExp(
          r'(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*hidden)\b',
          caseSensitive: false,
        ).hasMatch(hidden.attributes['style'] ?? '')) {
          hidden.remove();
        }
      }
    }
  }
  final out = StringBuffer();
  void visit(Node current) {
    if (current is Text) {
      out.write(current.data);
      return;
    }
    final tag = current is Element ? current.localName : '';
    final block = [
      'p',
      'div',
      'li',
      'br',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'section',
      'tr',
    ].contains(tag);
    if (block) out.writeln();
    for (final child in current.nodes) {
      visit(child);
    }
    if (block) out.writeln();
  }

  visit(copy);
  return cleanContentText(out.toString(), 60000);
}

Map? _jsonObject(String text, int start) {
  while (start < text.length && text[start].trim().isEmpty) {
    start++;
  }
  if (start >= text.length || text[start] != '{') return null;
  var depth = 0, quoted = false, escaped = false;
  for (var i = start; i < text.length && i - start < 1024 * 1024; i++) {
    final char = text[i];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == '{') {
      depth++;
    } else if (char == '}' && --depth == 0) {
      try {
        final value = jsonDecode(text.substring(start, i + 1));
        return value is Map ? value : null;
      } on FormatException {
        return null;
      }
    }
  }
  return null;
}
