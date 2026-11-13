// Small, deterministic query expansion; no inference or library text leaves SQLite.
class SearchTerms {
  SearchTerms(String query) {
    final tokens = RegExp(
      r'[\p{L}\p{N}]+',
      unicode: true,
    ).allMatches(query.toLowerCase()).map((match) => match.group(0)!).toSet();
    final filtered = tokens.where((word) => !_filler.contains(word));
    final words = (filtered.isEmpty ? tokens : filtered).take(8);
    for (final word in words) {
      final forms = _forms(word);
      final related = _related.where((group) => group.any(forms.contains));
      exact.add(_match(forms));
      expanded.add(_match({...forms, ...related.expand((group) => group)}));
    }
    phrase = words.join(' ');
  }

  final exact = <String>[];
  final expanded = <String>[];
  late final String phrase;

  static const _filler = {
    'a',
    'an',
    'the',
    'and',
    'or',
    'of',
    'for',
    'to',
    'with',
    'in',
    'on',
    'me',
    'my',
    'i',
    'please',
    'find',
    'show',
    'saved',
    'saves',
    'something',
    'about',
    'some',
  };
  // shortcut: curated English relations, add evaluated concepts when needed;
  // this does not claim arbitrary semantic understanding or spell correction.
  static const _related = [
    {'cold', 'iced', 'chilled'},
    {'recipe', 'ingredient', 'cooking'},
    {'vegetarian', 'veggie'},
    {'chickpea', 'garbanzo'},
    {'aubergine', 'eggplant'},
    {'courgette', 'zucchini'},
    {'coriander', 'cilantro'},
    {'workout', 'exercise', 'fitness'},
    {'tutorial', 'guide', 'instructions'},
  ];

  static Set<String> _forms(String word) => {
    word,
    if (word.length > 4 && word.endsWith('ies'))
      '${word.substring(0, word.length - 3)}y'
    else if (word.length > 4 &&
        RegExp(r'(ches|shes|xes|zes|sses)$').hasMatch(word))
      word.substring(0, word.length - 2)
    else if (word.length > 3 &&
        word != 'news' &&
        word.endsWith('s') &&
        !word.endsWith('ss') &&
        !word.endsWith('us'))
      word.substring(0, word.length - 1),
  };

  static String _match(Set<String> words) =>
      // Tokens contain letters/numbers only; bare prefixes work on FTS4 and 5.
      words.map((word) => '$word*').join(' OR ');
}
