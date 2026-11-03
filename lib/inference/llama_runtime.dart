import 'package:llamadart/llamadart.dart';

import '../domain/extraction.dart';
import 'local_runtime.dart';

/// llamadart's native backend owns a long-lived worker isolate. Never call
/// synchronous inference FFI on Flutter's UI isolate.
class LlamaLocalRuntime implements LocalRuntime {
  LlamaEngine? _engine;
  bool _cancelled = false;

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
    final messages = [
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: extractionInstructions,
      ),
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text:
            '${source.typeHint == null ? '' : 'User-selected content type: ${source.typeHint}. Use this type.\n'}SOURCE START\n${source.numbered}\nSOURCE END',
      ),
    ];
    final format = <String, dynamic>{
      'type': 'json_schema',
      'json_schema': {
        'name': 'linqo_extract',
        'strict': true,
        'schema': extractionSchema,
      },
    };
    final template = await engine.chatTemplate(
      messages,
      enableThinking: false,
      responseFormat: format,
    );
    final promptTokens =
        template.tokenCount ?? (await engine.tokenize(template.prompt)).length;
    if (_cancelled) return;
    if (promptTokens + RuntimeSettings.maxOutputTokens + 128 >
        RuntimeSettings.contextSize) {
      throw StateError(
        'This source exceeds the prototype context. Shorten it; no text was silently removed.',
      );
    }
    await for (final chunk in engine.create(
      messages,
      enableThinking: false,
      responseFormat: format,
      params: const GenerationParams(
        maxTokens: RuntimeSettings.maxOutputTokens,
        temp: 0.2,
        topP: 0.9,
        seed: 42,
      ),
    )) {
      if (_cancelled) break;
      final text = chunk.choices.isEmpty
          ? null
          : chunk.choices.first.delta.content;
      if (text != null && text.isNotEmpty) yield text;
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
