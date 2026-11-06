import 'package:flutter/material.dart';
import '../domain/extraction.dart';
import '../domain/source_rules.dart';

/// Reading layout; source material is available separately rather than hidden
/// under an identical dropdown for every sentence.
class ExtractedDetails extends StatelessWidget {
  const ExtractedDetails({super.key, required this.result});
  final ExtractionResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String value) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(value, style: theme.textTheme.titleMedium),
    );
    Widget line(String text, {int? number}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              number == null ? '•' : '$number.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(text, style: theme.textTheme.bodyLarge),
          ),
        ],
      ),
    );
    final recipe = result.recipe;
    final highlights = <String>[];
    for (final value in [
      if (result.type == 'tutorial') ...result.facts.map((fact) => fact.value),
      ...result.summary.split(' … '),
      if (result.type != 'recipe' && result.type != 'tutorial')
        ...result.facts.map((fact) => fact.value),
    ]) {
      final text = value.trim();
      if (text == result.title &&
          text.length < 100 &&
          !RegExp(r'[.!?]$').hasMatch(text)) {
        continue;
      }
      if (text.isEmpty ||
          SourceRules.isNoise(text) ||
          highlights.any(
            (entry) =>
                entry == text || entry.contains(text) || text.contains(entry),
          )) {
        continue;
      }
      highlights.add(text);
      if (highlights.length == (result.type == 'tutorial' ? 12 : 3)) break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recipe != null) ...[
          Text(
            recipe.servings ?? 'Serving size not provided',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          heading('Ingredients'),
          if (recipe.ingredients.isEmpty)
            const Text('Ingredients weren’t included in the saved caption.'),
          for (final ingredient in recipe.ingredients)
            line(
              ingredient.value.replaceFirst(
                RegExp(r'^ingredients?\s*:\s*', caseSensitive: false),
                '',
              ),
            ),
          heading('Steps'),
          if (recipe.steps.isEmpty)
            const Text(
              'Preparation steps weren’t included. Open the original for the full method.',
            ),
          for (final step in recipe.steps.indexed)
            line(
              step.$2.value.replaceFirst(
                RegExp(r'^\s*(?:\d+[.)]|[-•])\s*'),
                '',
              ),
              number: step.$1 + 1,
            ),
        ] else if (result.type == 'place' && result.places.isNotEmpty) ...[
          for (final place in result.places) line(place.name),
          if (highlights.isNotEmpty) heading('Good to know'),
          for (final highlight in highlights) line(highlight),
        ] else ...[
          for (final entry in highlights.indexed)
            line(
              entry.$2,
              number: result.type == 'tutorial' ? entry.$1 + 1 : null,
            ),
          if (highlights.isEmpty)
            const Text(
              'No useful highlights found. Try refreshing the source.',
            ),
        ],
        for (final warning in result.warnings)
          if (warning.startsWith('Only ') || warning.startsWith('No useful'))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(warning, style: theme.textTheme.bodySmall),
            ),
        const SizedBox(height: 8),
        Text(
          'From your saved text · check the original for context.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
