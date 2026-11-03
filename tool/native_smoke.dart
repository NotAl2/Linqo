import 'dart:convert';
import 'dart:io';
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/inference/llama_runtime.dart';
import 'package:linqo/inference/local_runtime.dart';

/// Real native inference, not a mock. Runs on the developer host, not Android.
/// dart run tool/native_smoke.dart /absolute/path/model.gguf
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/native_smoke.dart /path/model.gguf');
    exitCode = 64;
    return;
  }
  final runtime = LlamaLocalRuntime();
  final loadWatch = Stopwatch()..start();
  try {
    await runtime.load(args.single, const RuntimeSettings());
    loadWatch.stop();
    final results = <Map<String, Object?>>[];
    for (final fixture in <String, String>{
      'english':
          'Chickpea skillet\nIngredients: 1 onion, 1 can chickpeas, 200 ml coconut milk.\nChop the onion. Add chickpeas and coconut milk.\nSimmer for 10 minutes.',
      'hindi':
          'चना सलाद\nसामग्री: 1 कप उबले चने, 1 टमाटर।\nटमाटर काटें और चने के साथ मिलाएँ।',
    }.entries) {
      final source = SourceDocument(fixture.value);
      final watch = Stopwatch()..start();
      final buffer = StringBuffer();
      await for (final delta in runtime.extract(source)) {
        buffer.write(delta);
      }
      final parsed = ExtractionResult.parse(buffer.toString(), source);
      if (parsed.facts.isEmpty) {
        throw StateError('No facts returned for ${fixture.key}.');
      }
      final details = parsed.facts.map((fact) => fact.value).join(' ');
      final expectedDetail = fixture.key == 'english' ? '10 minutes' : 'मिलाएँ';
      if (!details.contains(expectedDetail)) {
        throw StateError(
          'The ${fixture.key} extract omitted a stated method/timing. Output: $buffer',
        );
      }
      results.add({
        'fixture': fixture.key,
        'elapsed_ms': watch.elapsedMilliseconds,
        'title': parsed.title,
        'summary': parsed.summary,
        'type': parsed.type,
        'facts': parsed.facts
            .map(
              (f) => {'label': f.label, 'value': f.value, 'lines': f.lineIds},
            )
            .toList(),
      });
    }
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'platform': Platform.operatingSystem,
        'load_ms': loadWatch.elapsedMilliseconds,
        'process_peak_rss_bytes': ProcessInfo.maxRss,
        'results': results,
        'scope':
            'Host runtime smoke test only; not Android performance or semantic accuracy certification.',
      }),
    );
  } finally {
    await runtime.dispose();
  }
}
