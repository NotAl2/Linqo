import 'extraction.dart';

class NamedSourcePlace {
  const NamedSourcePlace(this.name, this.lineId);
  final String name;
  final int lineId;
}

/// Conservative structural recovery, not invented recipe/place knowledge.
/// Unrecognized source material remains available for review.
class SourceRules {
  static final ingredientHeading = RegExp(
    r'^(?:ingredients?|सामग्री)\s*[:：]?\s*',
    caseSensitive: false,
  );
  static final methodHeading = RegExp(
    r'^(?:instructions?|method|directions?|preparation|steps?|विधि|बनाने की विधि|तरीका)\s*[:：]?\s*',
    caseSensitive: false,
  );
  static final _englishAction = RegExp(
    r"^(?:(?:do not|don't)\s+)?(?:dice|chop|mince|slice|cut|sauté|saute|fry|heat|add|stir|mix|combine|whisk|pour|bring|boil|simmer|cook|bake|roast|grill|season|serve|blend|fold|knead|marinate|drain|rinse|wash|peel|cover|remove|leave|let|allow|turn|preheat|transfer|reduce|sprinkle|toss|strain)(?=\s|[.,:;!?]|$)",
    caseSensitive: false,
  );
  static final _hindiAction = RegExp(
    r'(?:काटें|मिलाएँ|मिलाएं|डालें|डालकर|परोसें|भूनें|पकाएँ|पकाएं|उबालें|चलाएँ|चलाएं|छानें|पीसें|रखें|गरम करें|गर्म करें|कर दें|करें)(?:[।.!?\s]|$)',
  );
  static final _listPrefix = RegExp(r'^\s*(?:[-*•]|\d+[.)]|[०-९]+[.)])\s*');

  static ({Set<int> ingredients, Set<int> steps}) recipeLines(
    SourceDocument source,
  ) {
    final ingredients = <int>{};
    final steps = <int>{};
    var section = '';
    for (final line in source.lines) {
      final text = line.text.replaceFirst(_listPrefix, '');
      final ingredient = ingredientHeading.firstMatch(text);
      final method = methodHeading.firstMatch(text);
      if (ingredient != null) {
        section = 'ingredients';
        if (text.substring(ingredient.end).trim().isNotEmpty) {
          ingredients.add(line.id);
        }
        continue;
      }
      if (method != null) {
        section = 'steps';
        if (text.substring(method.end).trim().isNotEmpty) steps.add(line.id);
        continue;
      }
      if (_englishAction.hasMatch(text) || _hindiAction.hasMatch(text)) {
        steps.add(line.id);
        section = 'steps';
      } else if (_isOtherSection(text)) {
        section = '';
      } else if (section == 'ingredients') {
        ingredients.add(line.id);
      } else if (section == 'steps' && _listPrefix.hasMatch(line.text)) {
        steps.add(line.id);
      }
    }
    return (ingredients: ingredients, steps: steps);
  }

  static bool isSectionHeading(String text) {
    final ingredients = ingredientHeading.firstMatch(text);
    final method = methodHeading.firstMatch(text);
    return (ingredients != null &&
            text.substring(ingredients.end).trim().isEmpty) ||
        (method != null && text.substring(method.end).trim().isEmpty);
  }

  static bool _isOtherSection(String text) => RegExp(
    r'^(?:notes?|nutrition|tips?|storage|नोट|पोषण)\s*[:：]',
    caseSensitive: false,
  ).hasMatch(text);

  static bool isAbsenceContext(String text) => RegExp(
    r'^(?:no .*(?:provided|stated|specified)|(?:opening hours|booking details|servings|timing).*(?:not provided|not stated|unknown))\.?$',
    caseSensitive: false,
  ).hasMatch(text);

  // Recover explicit capitalized names after visit/at/etc. Internal connectors
  // allow names such as Museum of Modern Art, without swallowing "in London".
  static final _namedPlace = RegExp(
    r"\b(?:[Vv]isit(?:ing)?|[Ee]xplor(?:e|ing)|[Cc]heck out|[Aa]t|[Aa]long)\s+(?:[Tt]he\s+)?([\p{Lu}][\p{L}\p{N}'’&-]*(?:(?:\s+(?:of|the|de|la|le|&))?\s+[\p{Lu}][\p{L}\p{N}'’&-]*){0,7})",
    unicode: true,
  );

  static List<NamedSourcePlace> namedPlaces(SourceDocument source) => [
    for (final line in source.lines)
      for (final match in _namedPlace.allMatches(line.text))
        NamedSourcePlace(match.group(1)!, line.id),
  ];
}
