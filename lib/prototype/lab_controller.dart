import 'dart:async';
import '../domain/extraction_progress.dart';
import '../services/diagnostics.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../domain/extraction.dart';
import '../inference/local_runtime.dart';
import '../inference/model_store.dart';

enum LabPhase {
  idle,
  restoring,
  importing,
  loading,
  unloading,
  ready,
  extracting,
  cancelling,
  complete,
  partial,
  cancelled,
  failed,
}

class RunReport {
  const RunReport({
    required this.elapsedMs,
    required this.firstOutputMs,
    required this.outputCharacters,
    required this.frames,
    required this.uiP95Ms,
    required this.rasterP95Ms,
    required this.overBudgetFrames,
    required this.outcome,
  });
  final int elapsedMs;
  final int? firstOutputMs;
  final int outputCharacters;
  final int frames;
  final double? uiP95Ms;
  final double? rasterP95Ms;
  final int overBudgetFrames;
  final String outcome;
  Map<String, Object?> toJson() => {
    'outcome': outcome,
    'elapsed_ms': elapsedMs,
    'first_output_ms': firstOutputMs,
    'output_characters': outputCharacters,
    'sampled_frames': frames,
    'ui_p95_ms': uiP95Ms,
    'raster_p95_ms': rasterP95Ms,
    'frames_above_16_7_ms': overBudgetFrames,
    'frame_sample_limit': 10000,
    'note':
        'Frame timings cover active Flutter frames, not idle time. Profile build on physical hardware required. Characters are not tokens.',
  };
}

class LabController extends ChangeNotifier {
  LabController({required LocalRuntime runtime, ModelStore? modelStore})
    : _runtime = runtime,
      _modelStore = modelStore ?? ModelStore() {
    if (runtime is ProgressRuntime) {
      (runtime as ProgressRuntime).onProgress = (part, total, firstToken) {
        currentPart = part.clamp(1, total.clamp(1, 64));
        totalParts = total;
        progress.boundary(part, total, _runWatch?.elapsedMilliseconds ?? 0);
        if (firstToken) activeFirstOutputMs ??= _runWatch?.elapsedMilliseconds;
        _emit();
      };
    }
  }
  final LocalRuntime _runtime;
  final ModelStore _modelStore;
  LabPhase phase = LabPhase.idle;
  ImportedModel? model;
  bool modelLoaded = false;
  String? error;
  int threads = 2;
  int currentPart = 0, totalParts = 0;
  final progress = ExtractionProgress();
  Duration get extractionElapsed =>
      Duration(milliseconds: _runWatch?.elapsedMilliseconds ?? 0);
  Stopwatch? _runWatch;
  bool selectionManaged = false;
  int? modelLoadMs;
  int? modelLoadedRssBytes;
  int? runStartRssBytes;
  int? runEndRssBytes;
  ExtractionResult? result;
  SourceDocument? evidence;
  RunReport? report;
  String rawOutput = '';
  final _frames = <FrameTiming>[];
  bool _collecting = false;
  bool _disposed = false;
  bool _cancelRequested = false;
  bool _releaseRequested = false;
  Stopwatch? _cancelWatch;
  int? cancellationMs;
  int? activeFirstOutputMs;
  Completer<void>? _operation;
  Future<void>? _disposal;

  bool get busy =>
      _operation != null ||
      [
        LabPhase.restoring,
        LabPhase.importing,
        LabPhase.loading,
        LabPhase.unloading,
        LabPhase.extracting,
        LabPhase.cancelling,
      ].contains(phase);
  bool get canExtract =>
      modelLoaded && !busy && !_releaseRequested && !_disposed;
  Future<void> whenIdle() => _operation?.future ?? Future<void>.value();
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (busy || model != null || _disposed) return;
    final operation = _operation = Completer<void>();
    selectionManaged = true;
    phase = LabPhase.restoring;
    error = null;
    _emit();
    try {
      model = await _modelStore.restore();
      phase = LabPhase.idle;
    } catch (e) {
      phase = LabPhase.failed;
      error = 'Could not restore the selected model: $e';
    } finally {
      await _finishOperation(operation);
      _emit();
    }
  }

  Future<void> _finishOperation(Completer<void> operation) async {
    try {
      if (_releaseRequested && modelLoaded) {
        await _runtime.unload();
        modelLoaded = false;
        if (phase == LabPhase.ready) phase = LabPhase.idle;
      }
      if (_disposed) await (_disposal ??= _runtime.dispose());
    } catch (e) {
      modelLoaded = false;
      phase = LabPhase.failed;
      error = 'Could not release model memory: $e';
    } finally {
      _releaseRequested = false;
      _operation = null;
      operation.complete();
    }
  }

  /// Waits for native work to stop before freeing its context. New extraction
  /// remains disabled until the release has finished.
  Future<void> releaseMemory() async {
    _releaseRequested = true;
    cancel();
    final active = _operation;
    if (active != null) {
      await active.future;
    } else {
      await unload();
      _releaseRequested = false;
    }
  }

  Future<void> importModel(String path, String name) async {
    if (busy || _disposed) return;
    final operation = _operation = Completer<void>();
    selectionManaged = true;
    _cancelRequested = false;
    phase = LabPhase.importing;
    error = null;
    result = null;
    report = null;
    modelLoadMs = null;
    _emit();
    try {
      modelLoaded = false;
      await _runtime.unload();
      if (_disposed || _cancelRequested) {
        phase = LabPhase.cancelled;
        return;
      }
      model = await _modelStore.import(path, name);
      if (_disposed) return;
      phase = LabPhase.idle;
    } on ModelImportCancelled {
      phase = LabPhase.cancelled;
    } catch (e) {
      error = 'Model import failed: $e';
      phase = LabPhase.failed;
    } finally {
      await _finishOperation(operation);
    }
    _emit();
  }

  Future<void> refreshModel() async {
    if (!selectionManaged || busy || _disposed) return;
    final operation = _operation = Completer<void>();
    phase = LabPhase.restoring;
    try {
      final restored = await _modelStore.restore();
      if (modelLoaded &&
          (restored == null ||
              restored.path != model?.path ||
              restored.sha256 != model?.sha256)) {
        await _runtime.unload();
        modelLoaded = false;
      }
      model = restored;
      error = null;
      phase = modelLoaded ? LabPhase.ready : LabPhase.idle;
    } catch (_) {
      if (modelLoaded) {
        await _runtime.unload();
        modelLoaded = false;
      }
      model = null;
      error = 'The model is missing or damaged. Download or import it again.';
      phase = LabPhase.failed;
    } finally {
      await _finishOperation(operation);
      _emit();
    }
  }

  Future<void> deleteModel() async {
    if (busy || _disposed) {
      throw StateError('Wait for model processing to stop.');
    }
    final operation = _operation = Completer<void>();
    phase = LabPhase.unloading;
    _emit();
    try {
      await _runtime.unload();
      modelLoaded = false;
      await _modelStore.remove();
      model = null;
      error = null;
      result = null;
      report = null;
      phase = LabPhase.idle;
    } catch (e) {
      model = null;
      phase = LabPhase.failed;
      error = 'Could not remove all model files. Try again. $e';
      rethrow;
    } finally {
      await _finishOperation(operation);
      _emit();
    }
  }

  Future<void> load() async {
    final selected = model;
    if (selected == null || busy || modelLoaded || _disposed) return;
    final operation = _operation = Completer<void>();
    _cancelRequested = false;
    phase = LabPhase.loading;
    error = null;
    _emit();
    final watch = Stopwatch()..start();
    try {
      if (selectionManaged) {
        try {
          model = await _modelStore.restore();
        } catch (_) {
          model = null;
          rethrow;
        }
        if (model == null) {
          throw StateError(
            'The model file is missing. Download or import it again in Settings.',
          );
        }
      }
      if (_cancelRequested || _disposed || _releaseRequested) {
        phase = LabPhase.cancelled;
        return;
      }
      await _runtime.load(model!.path, RuntimeSettings(threads: threads));
      if (_disposed || _cancelRequested || _releaseRequested) {
        await _runtime.unload();
        phase = LabPhase.cancelled;
        return;
      }
      modelLoadMs = watch.elapsedMilliseconds;
      modelLoadedRssBytes = ProcessInfo.currentRss;
      modelLoaded = true;
      phase = LabPhase.ready;
    } catch (e) {
      modelLoaded = false;
      if (_cancelRequested) {
        phase = LabPhase.cancelled;
      } else {
        phase = LabPhase.failed;
        error =
            'Could not load this model. Free memory or choose a smaller compatible GGUF. Details: $e';
      }
    } finally {
      await _finishOperation(operation);
      _emit();
    }
    _emit();
  }

  Future<void> unload() async {
    if (busy || !modelLoaded) return;
    final operation = _operation = Completer<void>();
    phase = LabPhase.unloading;
    _emit();
    try {
      await _runtime.unload();
      modelLoaded = false;
      phase = LabPhase.idle;
    } catch (e) {
      error = 'Could not unload the model: $e';
      phase = LabPhase.failed;
    } finally {
      await _finishOperation(operation);
    }
    _emit();
  }

  Future<void> extract(String text, {String? typeHint}) async {
    // A skipped run must not look successful to callers persisting its result.
    if (!canExtract) {
      throw StateError(
        'The model is not ready. Wait for processing to finish and try again.',
      );
    }
    result = null;
    report = null;
    evidence = null;
    rawOutput = '';
    final source = SourceDocument.segmented(text, typeHint: typeHint);
    if (source.lines.isEmpty || text.length > 30000) {
      error =
          'Use 1–30,000 characters of source text. Your saved original is unchanged.';
      _emit();
      return;
    }
    final operation = _operation = Completer<void>();
    phase = LabPhase.extracting;
    error = null;
    result = null;
    report = null;
    evidence = source;
    rawOutput = '';
    _cancelRequested = false;
    final buffer = StringBuffer();
    _cancelWatch = null;
    cancellationMs = null;
    activeFirstOutputMs = null;
    final watch = _runWatch = Stopwatch()..start();
    currentPart = 0;
    totalParts = 0;
    progress.start('${model?.sha256}:$threads', source.text.length);
    runStartRssBytes = ProcessInfo.currentRss;
    int? firstOutputMs;
    var outcome = 'failed';
    _frames.clear();
    _collecting = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _emit();
    try {
      await for (final delta in _runtime.extract(source)) {
        if (_cancelRequested || _disposed) break;
        firstOutputMs ??= watch.elapsedMilliseconds;
        activeFirstOutputMs ??= firstOutputMs;
        buffer.write(delta);
        if (buffer.length > 64000) {
          throw const FormatException(
            'Model output exceeded the prototype limit.',
          );
        }
      }
      rawOutput = buffer.toString();
      if (_cancelRequested || _disposed) {
        outcome = 'cancelled';
        phase = LabPhase.cancelled;
      } else {
        result = ExtractionResult.parse(rawOutput, source);
        outcome = result!.isPartial ? 'partial' : 'complete';
        phase = result!.isPartial ? LabPhase.partial : LabPhase.complete;
      }
    } catch (e) {
      _runtime.cancel();
      rawOutput = buffer.toString();
      if (_cancelRequested) {
        outcome = 'cancelled';
        phase = LabPhase.cancelled;
      } else {
        phase = LabPhase.failed;
        error = 'Extraction did not produce a valid evidence-linked result. $e';
      }
    } finally {
      watch.stop();
      progress.finish(
        watch.elapsedMilliseconds,
        successful: outcome == 'complete',
      );
      cancellationMs = _cancelWatch?.elapsedMilliseconds;
      _cancelWatch?.stop();
      runEndRssBytes = ProcessInfo.currentRss;
      _stopTimings();
      Diagnostics.instance.record('model.$outcome');
      report = RunReport(
        elapsedMs: watch.elapsedMilliseconds,
        firstOutputMs: activeFirstOutputMs ?? firstOutputMs,
        outputCharacters: buffer.length,
        frames: _frames.length,
        uiP95Ms: _percentile(
          _frames.map((f) => f.buildDuration.inMicroseconds),
        ),
        rasterP95Ms: _percentile(
          _frames.map((f) => f.rasterDuration.inMicroseconds),
        ),
        overBudgetFrames: _frames
            .where(
              (f) =>
                  f.buildDuration.inMicroseconds > 16700 ||
                  f.rasterDuration.inMicroseconds > 16700,
            )
            .length,
        outcome: outcome,
      );
      _emit();
      await _finishOperation(operation);
      _emit();
    }
  }

  void cancel() {
    final cancellingExtraction = phase == LabPhase.extracting;
    if (phase == LabPhase.importing) {
      if (_modelStore.importCommitting) return;
      _modelStore.cancelImport();
    } else if (phase == LabPhase.extracting || phase == LabPhase.loading) {
      _runtime.cancel();
    } else {
      return;
    }
    _cancelRequested = true;
    if (cancellingExtraction) _cancelWatch = Stopwatch()..start();
    phase = LabPhase.cancelling;
    _emit();
  }

  void _onTimings(List<FrameTiming> frames) {
    if (_collecting && _frames.length < 10000) {
      _frames.addAll(frames.take(10000 - _frames.length));
    }
  }

  void _stopTimings() {
    if (!_collecting) return;
    _collecting = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  double? _percentile(Iterable<int> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) return null;
    return sorted[(sorted.length * 0.95).ceil() - 1] / 1000;
  }

  String diagnosticsJson() => const JsonEncoder.withIndent('  ').convert({
    'app': 'Linqo processing prototype',
    'platform': defaultTargetPlatform.name,
    'build_mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'model': model?.name,
    'model_sha256': model?.sha256,
    'model_bytes': model?.bytes,
    'model_load_ms': modelLoadMs,
    'process_rss_after_load_bytes': modelLoadedRssBytes,
    'process_rss_at_run_start_bytes': runStartRssBytes,
    'process_rss_at_run_end_bytes': runEndRssBytes,
    'process_lifetime_peak_rss_bytes': ProcessInfo.maxRss,
    'runtime': 'llamadart 0.15.6 / llama.cpp / CPU',
    'threads': threads,
    'context_tokens': RuntimeSettings.contextSize,
    'max_output_tokens': RuntimeSettings.maxOutputTokens,
    'batch_tokens': RuntimeSettings.batchSize,
    'micro_batch_tokens': RuntimeSettings.microBatchSize,
    'kv_cache': 'q8_0',
    'cancellation_ms': cancellationMs,
    'extraction_schema_version': 2,
    'recipe_step_count': result?.recipe?.steps.length,
    'place_count': result?.places.length,
    'review_warning_count': result?.warnings.length,
    'report': report?.toJson(),
    'privacy': 'Source text and generated content excluded from this report.',
  });

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    _modelStore.cancelImport();
    _runtime.cancel();
    _stopTimings();
    if (_operation == null) unawaited(_disposal ??= _runtime.dispose());
    super.dispose();
  }
}
