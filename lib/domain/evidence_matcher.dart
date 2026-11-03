/// Matches conservative typographic equivalents and returns the original span.
/// Digits, decimal points, fractions, units and negation are never stripped.
class EvidenceMatcher {
  static String? originalSpan(String evidence, String quote) {
    final source = _canonical(evidence);
    final target = _canonical(quote).text;
    if (target.isEmpty) return null;
    var from = 0;
    while (from < source.text.length) {
      final index = source.text.indexOf(target, from);
      if (index < 0) return null;
      if (_wholeSpan(source.text, target, index)) {
        return evidence.substring(
          source.starts[index],
          source.ends[index + target.length - 1],
        );
      }
      from = index + 1;
    }
    return null;
  }

  static final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _digit = RegExp(r'\p{N}', unicode: true);
  static bool _wholeSpan(String source, String target, int start) {
    final end = start + target.length;
    if (start > 0 &&
        _word.hasMatch(target[0]) &&
        _word.hasMatch(source[start - 1])) {
      return false;
    }
    if (end < source.length &&
        _word.hasMatch(target[target.length - 1]) &&
        _word.hasMatch(source[end])) {
      return false;
    }
    if (_digit.hasMatch(target[0]) &&
        start > 1 &&
        './,'.contains(source[start - 1]) &&
        _digit.hasMatch(source[start - 2])) {
      return false;
    }
    if (_digit.hasMatch(target[target.length - 1]) &&
        end + 1 < source.length &&
        './,'.contains(source[end]) &&
        _digit.hasMatch(source[end + 1])) {
      return false;
    }
    return true;
  }

  static ({String text, List<int> starts, List<int> ends}) _canonical(
    String raw,
  ) {
    final buffer = StringBuffer();
    final starts = <int>[];
    final ends = <int>[];
    var offset = 0;
    var previousSpace = false;
    for (final rune in raw.runes) {
      final character = String.fromCharCode(rune);
      final next = offset + character.length;
      final space = RegExp(r'\s', unicode: true).hasMatch(character);
      if (space && previousSpace) {
        ends[ends.length - 1] = next;
        offset = next;
        continue;
      }
      final normalized = space
          ? ' '
          : switch (character) {
              '।' =>
                offset > 0 &&
                        next < raw.length &&
                        _digit.hasMatch(raw[offset - 1]) &&
                        _digit.hasMatch(raw[next])
                    ? '।'
                    : '.',
              '‘' || '’' => "'",
              '“' || '”' => '"',
              _ => character,
            };
      buffer.write(normalized);
      for (var i = 0; i < normalized.length; i++) {
        starts.add(offset);
        ends.add(next);
      }
      previousSpace = space;
      offset = next;
    }
    return (text: buffer.toString(), starts: starts, ends: ends);
  }
}
