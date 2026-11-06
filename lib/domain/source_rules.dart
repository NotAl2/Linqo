import 'extraction.dart';

class NamedSourcePlace {
  const NamedSourcePlace(this.name, this.lineId);
  final String name;
  final int lineId;
}

/// Conservative structural recovery, not invented recipe/place knowledge.
/// Unrecognized source material remains available for review.
class SourceRules {
  /// Classify the whole save before splitting it into model-sized parts.
  /// Generic imperatives ("Add a preferred source") are not cooking evidence.
  static String classify(SourceDocument source) {
    final structure = recipeLines(source);
    if (looksLikeRecipe(source.text) ||
        structure.ingredients.isNotEmpty ||
        (_food.hasMatch(source.text) && structure.steps.isNotEmpty)) {
      return 'recipe';
    }
    if (RegExp(
          r'^Place(?: name from saved link)?:',
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(source.text) ||
        namedPlaces(source).length >= 2) {
      return 'place';
    }
    if (RegExp(
          r'^(?:how to |installation|setup guide|instructions:|steps:)',
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(source.text) &&
        RegExp(
          r'\b(?:click|install|open|select|run|tap|connect|configure)\b',
          caseSensitive: false,
        ).hasMatch(source.text)) {
      return 'tutorial';
    }
    return 'general';
  }

  static final _food = RegExp(
    r'\b(?:flour|sugar|salt|pepper|onion|garlic|tomato|pasta|rice|chicken|egg|eggs|butter|milk|cream|spinach|potato|potatoes|cheese|yogurt|yoghurt|lentils|chickpeas|olive oil|baking powder|oats|banana|chocolate|cumin|paprika|tofu|salmon|bread|lemon)\b',
    caseSensitive: false,
  );

  static bool looksLikeRecipe(String text) =>
      _food.hasMatch(text) &&
      (RegExp(r'\bingredients?\s*:', caseSensitive: false).hasMatch(text) ||
          (RegExp(
                r'\b\d+\s*(?:g|kg|ml|cups?|tbsp|tsp|tablespoons?|teaspoons?)\b',
                caseSensitive: false,
              ).hasMatch(text) &&
              RegExp(
                r'\b(?:boil|bake|simmer|fry|roast|whisk|knead|chop|cook)\b',
                caseSensitive: false,
              ).hasMatch(text)));

  /// Split compact recipe captions into source spans, never generated prose.
  /// All selected spans remain findable in the untouched saved caption.
  static List<String> recipeSegments(String text) {
    if (!looksLikeRecipe(text)) return text.split('\n');
    final separated = text
        .replaceAllMapped(RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9])'), (_) => '\n')
        .replaceAllMapped(
          RegExp(
            r'\b(Ingredients?\s*:|Method\s*:|Instructions?\s*:|Directions?\s*:)',
            caseSensitive: false,
          ),
          (m) => '\n${m[0]}\n',
        );
    final lines = <String>[];
    var ingredients = false;
    for (final part in separated.split('\n')) {
      final value = part.trim();
      if (ingredientHeading.hasMatch(value)) {
        ingredients = true;
        lines.add(value);
        continue;
      }
      if (methodHeading.hasMatch(value) || isPreparationText(value)) {
        ingredients = false;
      }
      lines.addAll(ingredients ? value.split(RegExp(r',\s+')) : [value]);
    }
    return lines;
  }

  /// Exclude publisher controls, author bios and engagement prompts, including
  /// old saved content; preserve the original body for editing/source review.
  static bool isNoise(String value) {
    final text = value.trim();
    return isSocialFooter(text) ||
        RegExp(
          r'^(?:(?:shared text|fetched content|follow|followed|thread|advertisement|read more|related articles|about the author)\s*:?|\d+|add (?:.+ on google|as (?:a )?preferred source)|follow on google discover|screenshot by .+|.{1,60} / MakeUseOf|(?:sign|log) in(?: to .*)?|subscribe(?: to .*)?)$',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(
          r'\b(?:is a .{0,65}graduate (?:from|of)|holds a .{0,50}degree|currently writes for|as a staff writer|combines (?:his|her|their|deep) .{0,35}(?:knowledge|technical)|covering cybersecurity, gaming)\b',
          caseSensitive: false,
        ).hasMatch(text);
  }

  static String? articleHint(SourceDocument source) =>
      recipeLines(source).ingredients.isEmpty && namedPlaces(source).isEmpty
      ? 'general'
      : null;
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
    final culinary =
        _food.hasMatch(source.text) ||
        source.lines.any((line) => ingredientHeading.hasMatch(line.text));
    var section = '';
    for (final line in source.lines) {
      final text = line.text.replaceFirst(_listPrefix, '');
      // Social captions often end an ingredient list with creator credits,
      // hashtag blocks and separator dots rather than a new section heading.
      if (isNoise(text)) {
        section = '';
        continue;
      }
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
      if (culinary &&
          (_englishAction.hasMatch(text) || _hindiAction.hasMatch(text))) {
        steps.add(line.id);
        section = 'steps';
      } else if (_isOtherSection(text)) {
        section = '';
      } else if (section == 'ingredients') {
        ingredients.add(line.id);
      } else if (culinary &&
          section == 'steps' &&
          _listPrefix.hasMatch(line.text)) {
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

  static bool _isSocialFooter(String text) => RegExp(
    r'^(?:[@#][\w\p{L}]|[.·•…\s]+$|(?:please\s+)?(?:follow\s+(?:me|us|@)|subscribe\b)|(?:like|share|save)\s+(?:this|my|the)\s+(?:post|reel|recipe|video)\b|comment\s+below\b|(?:for|find|see)\s+(?:more|the full)\s+(?:recipes?|content)\b)',
    caseSensitive: false,
    unicode: true,
  ).hasMatch(text);

  static bool isSocialFooter(String text) =>
      _isSocialFooter(text.replaceFirst(_listPrefix, ''));

  /// A citation proves where text came from, not that it describes a method.
  /// Keep uncommon numbered methods, imperatives and conditional directions;
  /// reject marketing prose and creator credits selected by a small model.
  static bool isPreparationText(String original) {
    final text = original.replaceFirst(_listPrefix, '');
    if (isNoise(text) || isSectionHeading(text)) return false;
    final unprefixed = text.replaceFirst(
      RegExp(
        r'^(?:then|next|finally|meanwhile|now)\s*[:,]?\s+',
        caseSensitive: false,
      ),
      '',
    );
    if (_englishAction.hasMatch(unprefixed) ||
        RegExp(
          r'^(?:whip|beat|melt|place|put|set|scoop|spread|press|top|fill|taste|shake|roll|flatten|sift|rub|break|crack|brush|arrange|refrigerate|freeze|cool|rest|ferment|trim|flip|keep|use|prepare|steam|soak|microwave|grate|squeeze|crush|sear|toast|grease|line|coat|dip|dredge|blanch|braise|broil|drizzle|garnish|divide|shape|stuff|wrap|uncover|reheat|defrost|thaw|air-fry|deep-fry|pan-fry)(?=\s|[.,:;!?]|$)',
          caseSensitive: false,
        ).hasMatch(unprefixed) ||
        _hindiAction.hasMatch(text) ||
        RegExp(r'^\s*\d+[.)]\s+').hasMatch(original)) {
      return true;
    }
    return RegExp(
          r'^(?:once|after|before|when|while|until|as soon as)\b',
          caseSensitive: false,
        ).hasMatch(text) &&
        RegExp(
          r'\b(?:add|mix|stir|pour|cook|bake|fry|simmer|boil|flip|remove|serve|fold|turn|cover|transfer|whisk|knead|reduce|drain)\b',
          caseSensitive: false,
        ).hasMatch(text);
  }

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
