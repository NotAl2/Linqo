import 'dart:convert';
import 'dart:io';
import 'package:linqo/inference/llama_runtime.dart';
import 'package:linqo/inference/local_runtime.dart';
import 'package:linqo/domain/extraction.dart';

Future<void> main(List<String> args) async {
  final runtime = LlamaLocalRuntime();
  final fixtures = {
    'recipe':
        'Chickpea skillet\nIngredients: onion, garlic, chickpeas, coconut milk, spinach.\nDice the onion.\nSauté the onion and garlic, then add chickpeas and coconut milk.\nSimmer for 10 minutes. Stir in spinach.\nServe with rice.',
    'places':
        'Weekend in London\nTry a coffee at Monmouth Coffee in Borough Market.\nVisit the Tate Modern on Bankside.\nWalk along the South Bank in the afternoon.',
    'note':
        'A weekend plan\nBring a notebook and a camera.\nMeet at 10 AM on Saturday.',
  };
  final results = <Map<String, Object?>>[];
  try {
    await runtime.load(args.single, const RuntimeSettings());
    for (final entry in fixtures.entries) {
      final source = SourceDocument(
        entry.value,
        typeHint: entry.key == 'note'
            ? 'general'
            : entry.key == 'recipe'
            ? 'recipe'
            : 'place',
      );
      final watch = Stopwatch()..start();
      final raw = await runtime.extract(source).join();
      try {
        final result = ExtractionResult.parse(raw, source);
        final passed =
            !result.isPartial &&
            (entry.key != 'recipe' || result.recipe?.steps.length == 4) &&
            (entry.key != 'places' || result.places.length >= 3);
        results.add({
          'fixture': entry.key,
          'passed': passed,
          'elapsed_ms': watch.elapsedMilliseconds,
          'type': result.type,
          'summary': result.summary,
          'facts': result.facts.map((f) => f.value).toList(),
        });
      } catch (e) {
        results.add({
          'fixture': entry.key,
          'passed': false,
          'error': e.toString(),
          'raw': raw,
        });
      }
    }
  } finally {
    await runtime.unload();
  }
  stdout.writeln(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'model': 'Qwen3-0.6B-Q4_K_M', 'results': results}),
  );
  if (results.any((r) => r['passed'] != true)) exitCode = 1;
}
