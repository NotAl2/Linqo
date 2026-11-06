import 'dart:convert';
import 'dart:async';
import 'package:llamadart/llamadart.dart';

import '../domain/extraction.dart';
import 'local_runtime.dart';
import '../domain/source_parts.dart';
import '../domain/source_rules.dart';

/// llamadart's native backend owns a long-lived worker isolate. Never call
/// synchronous inference FFI on Flutter's UI isolate.
class LlamaLocalRuntime implements LocalRuntime, ProgressRuntime {
  LlamaEngine? _engine;
  bool _cancelled = false;
  @override
  void Function(int, int, bool)? onProgress;

  @override
  Future<void> load(String path, RuntimeSettings settings) async {
    await unload();
    final engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(path)),
      params: ModelParams(
        contextSize: RuntimeSettings.contextSize,
        device: ComputeDevice.cpu,
        gpuLayers: 0,
        numberOfThreads: settings.threads,
        numberOfThreadsBatch: settings.threads,
        batchSize: RuntimeSettings.batchSize,
        microBatchSize: RuntimeSettings.microBatchSize,
        flashAttention: FlashAttention.enabled,
        cacheTypeK: KvCacheType.q8_0,
        cacheTypeV: KvCacheType.q8_0,
        useMmap: true,
      ),
    );
    _engine = engine;
  }

  @override
  Stream<String> extract(SourceDocument source) async* {
    final engine = _engine;
    if (engine == null) throw StateError('Import and load a GGUF model first.');
    _cancelled = false;
    List<LlamaChatMessage> messages(SourceDocument part) => [
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: extractionInstructions,
      ),
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text:
            '${part.typeHint == null ? '' : 'User-selected content type: ${part.typeHint}. Use this type.\n'}SOURCE START\n${part.numbered}\nSOURCE END',
      ),
    ];
    Map<String, dynamic> format(SourceDocument part) {
      final schema =
          jsonDecode(jsonEncode(extractionSchema)) as Map<String, dynamic>;
      for (final key in [
        'summary_lines',
        'ingredient_lines',
        'step_lines',
        'detail_lines',
      ]) {
        schema['properties'][key]['items']['maximum'] = part.lines.length;
        schema['properties'][key]['maxItems'] = key == 'summary_lines'
            ? 3
            : part.lines.length;
      }
      schema['properties']['title']['maxLength'] = 120;
      schema['properties']['title']['minLength'] = 1;
      schema['properties']['places']['items']['properties']['lines']['items']['maximum'] =
          part.lines.length;
      schema['properties']['places']['items']['properties']['lines']['maxItems'] =
          part.lines.length;
      schema['properties']['places']['items']['properties']['name']['maxLength'] =
          120;
      return <String, dynamic>{
        'type': 'json_schema',
        'json_schema': {
          'name': 'linqo_extract',
          'strict': true,
          'schema': schema,
        },
      };
    }

    final category = SourceRules.classify(source);
    // Strong source structure is a guardrail. Otherwise let the model choose
    // its category; parsing still rejects unsupported recipe classifications.
    final hinted = source.typeHint ?? (category == 'general' ? null : category);
    final plannedSource = SourceDocument(source.text, typeHint: hinted);
    final parts = await planSourceParts(plannedSource, (part) async {
      if (_cancelled) throw const _InferenceCancelled();
      final template = await engine.chatTemplate(
        messages(part),
        enableThinking: false,
        responseFormat: format(part),
      );
      final tokens =
          template.tokenCount ??
          (await engine.tokenize(template.prompt)).length;
      return tokens + RuntimeSettings.maxOutputTokens + 128 <=
          RuntimeSettings.contextSize;
    });
    final outputs = <Map<String, dynamic>>[];
    for (var index = 0; index < parts.length; index++) {
      if (_cancelled) return;
      final part = parts[index].document;
      onProgress?.call(index + 1, parts.length, false);
      final buffer = StringBuffer();
      var first = true;
      try {
        await for (final chunk
            in engine
                .create(
                  messages(part),
                  enableThinking: false,
                  responseFormat: format(part),
                  params: const GenerationParams(
                    maxTokens: RuntimeSettings.maxOutputTokens,
                    temp: 0,
                    topP: 0.9,
                    seed: 42,
                  ),
                )
                .timeout(const Duration(seconds: 90))) {
          if (_cancelled) break;
          final text = chunk.choices.isEmpty
              ? null
              : chunk.choices.first.delta.content;
          if (text != null && text.isNotEmpty) {
            if (first) {
              first = false;
              onProgress?.call(index + 1, parts.length, true);
            }
            buffer.write(text);
            if (buffer.length > 64000) {
              throw const FormatException('A model response was too large.');
            }
          }
        }
        if (_cancelled) return;
        final value = jsonDecode(buffer.toString()) as Map<String, dynamic>;
        if (value['schema_version'] != 3) {
          throw const FormatException(
            'Unexpected extraction response version.',
          );
        }
        ExtractionResult.parse(buffer.toString(), part);
        outputs.add(value);
      } catch (error) {
        engine.cancelGeneration();
        if (_cancelled) return;
        if (outputs.isEmpty) rethrow;
        // Kept private with the extraction for diagnostics, never presented as
        // source content or an asserted fact.
        outputs.first['_part_failure'] = error.toString();
        break; // Preserve verified completed parts, with explicit partial coverage.
      }
    }
    if (!_cancelled && outputs.isNotEmpty) {
      final merged =
          jsonDecode(
                mergeSourceParts(
                  source,
                  parts,
                  outputs,
                  totalParts: parts.length,
                ),
              )
              as Map<String, dynamic>;
      if (outputs.first['_part_failure'] != null) {
        merged['part_failure'] = outputs.first['_part_failure'];
      }
      yield jsonEncode(merged);
    }
  }

  @override
  void cancel() {
    _cancelled = true;
    _engine?.cancelGeneration();
  }

  @override
  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }

  @override
  Future<void> dispose() => unload();
}

class _InferenceCancelled implements Exception {
  const _InferenceCancelled();
}
