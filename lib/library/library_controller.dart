import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../inference/llama_runtime.dart';
import '../inference/local_runtime.dart';
import '../inference/model_download.dart';
import '../prototype/lab_controller.dart';
import 'library_store.dart';
import 'models.dart';
import '../sharing/link_preview.dart';
import '../domain/extraction.dart';
import '../domain/source_rules.dart';
import '../services/local_notifications.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(
    this.store, {
    LocalRuntime? runtime,
    ModelDownload? downloader,
    this.previewFactory,
    this.attachmentDirectory,
  }) : lab = LabController(runtime: runtime ?? LlamaLocalRuntime()),
       download = downloader ?? ModelDownload();
  final LibraryStore store;
  final LabController lab;
  final ModelDownload download;
  final PreviewJob Function(String)? previewFactory;
  final Directory? attachmentDirectory;
  final ValueNotifier<int> changes = ValueNotifier(0);
  final List<int> _queue = [];
  final Map<int, PreviewJob> _previews = {};
  int? activeId;
  bool processing = false, _disposed = false, _suspended = false;
  bool _deletingModel = false;
  bool get modelManagementBusy => _deletingModel || lab.busy || download.busy;
  Completer<void>? _processingDone;
  Future<void>? _pressureRelease;
  String activeTitle = '', processingError = '';
  ThemeMode theme = ThemeMode.light;
  bool grid = true;
  bool autoExtract = true, _foreground = true;
  bool _recoveringPreviews = false;
  DateTime? _lastRecovery;
  List<SaveCollection> collections = [];
  int total = 0;
  int supportSaveEpoch = 0;
  bool get hasPreviewWork => _previews.isNotEmpty;
  bool get modelAvailable => lab.model != null;
  bool get compactModelInstalled => lab.model?.sha256 == download.expectedSha;
  bool previewBusy(int id) => _previews.containsKey(id);
  Future<void> initialize({bool restoreModel = true}) async {
    final mode = await store.preference('theme');
    theme = ThemeMode.values.firstWhere(
      (t) => t.name == mode,
      orElse: () => ThemeMode.light,
    );
    grid = await store.preference('layout') != 'list';
    autoExtract = await store.preference('auto_extract') != 'false';
    await refresh();
    unawaited(_resumePreviews());
    if (restoreModel) {
      unawaited(
        lab.initialize().then((_) {
          if (!_disposed) notifyListeners();
          if (!_disposed) unawaited(_queueReadySources());
        }),
      );
      unawaited(download.initialize());
    }
  }

  Future<void> _resumePreviews() async {
    if (_recoveringPreviews ||
        _disposed ||
        !_foreground ||
        (_lastRecovery != null &&
            DateTime.now().difference(_lastRecovery!) <
                const Duration(minutes: 1))) {
      return;
    }
    _recoveringPreviews = true;
    _lastRecovery = DateTime.now();
    try {
      int? beforeId;
      while (!_disposed) {
        final page = await store.pendingPreviews(
          beforeId: beforeId,
          includeUnavailable: true,
        );
        if (page.isEmpty) break;
        for (final item in page) {
          if (_disposed || !_foreground) return;
          if (_previews.containsKey(item.id)) continue;
          await enrichPreview(item.id, item.url, item.title);
        }
        // Move past attempted rows even if a request remains pending/fails.
        // A bounded page must not silently strand all older offline saves.
        beforeId = page.last.id;
      }
    } catch (_) {
      /* Core library stays usable if preview recovery fails. */
    } finally {
      _recoveringPreviews = false;
    }
  }

  Future<void> enrichPreview(
    int id,
    String url,
    String expectedTitle, {
    PreviewJob? request,
    LinkPreview? ready,
  }) async {
    if (_disposed || url.isEmpty) {
      request?.cancel();
      return;
    }
    _previews.remove(id)?.cancel();
    if (ready != null) {
      try {
        await store.applyPreview(id, url, expectedTitle, ready);
        if (!_disposed) await refresh();
      } catch (_) {
        /* A preview must not undo a saved link. */
      } finally {
        request?.cancel();
      }
      if (!_disposed) await _maybeAutoExtract(id);
      return;
    }
    final job = request ?? previewFactory?.call(url) ?? PreviewRequest(url);
    _previews[id] = job;
    try {
      final metadata = await job.metadata;
      if (_disposed || !identical(_previews[id], job)) return;
      await store.applyPreview(id, url, expectedTitle, metadata);
      if (!_disposed) await refresh();
      final preview = ready ?? await job.future;
      if (_disposed || !identical(_previews[id], job)) return;
      await store.applyPreview(id, url, expectedTitle, preview);
      if (!_disposed) await refresh();
      if (!_disposed) await _maybeAutoExtract(id);
    } catch (_) {
      /* Original link and title remain intact. */
    } finally {
      if (identical(_previews[id], job)) _previews.remove(id);
      job.cancel();
    }
  }

  Future<void> refresh() async {
    collections = await store.collections();
    total = await store.count();
    if (!_disposed) {
      changes.value++;
      notifyListeners();
    }
  }

  Future<void> appearance(ThemeMode value) async {
    await store.setPreference('theme', value.name);
    theme = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> layout(bool value) async {
    await store.setPreference('layout', value ? 'grid' : 'list');
    grid = value;
    if (!_disposed) {
      changes.value++;
      notifyListeners();
    }
  }

  Future<void> automaticExtraction(bool value) async {
    await store.setPreference('auto_extract', value.toString());
    autoExtract = value;
    if (!_disposed) notifyListeners();
    if (value) {
      _suspended = false;
      await _queueReadySources();
    }
  }

  Future<void> _maybeAutoExtract(int id) async {
    if (_disposed ||
        !_foreground ||
        _suspended ||
        !autoExtract ||
        !modelAvailable ||
        download.busy) {
      return;
    }
    try {
      final item = await store.get(id);
      if (item == null ||
          !item.autoExtract ||
          item.status != 'idle' ||
          item.contentStatus == 'pending' ||
          item.contentKind == 'place_link' ||
          item.body.trim().isEmpty ||
          item.body.length > 30000 ||
          !supportsEnglishExtraction(item.body)) {
        return;
      }
      await extract(item, automatic: true);
    } catch (_) {
      /* Source stays available for manual extraction. */
    }
  }

  Future<void> _queueReadySources() async {
    if (_disposed ||
        !_foreground ||
        _suspended ||
        !autoExtract ||
        !modelAvailable) {
      return;
    }
    int? beforeId;
    try {
      while (!_disposed && _foreground && !_suspended && autoExtract) {
        final page = await store.pendingExtractions(beforeId: beforeId);
        if (page.isEmpty) break;
        for (final id in page) {
          await _maybeAutoExtract(id);
        }
        beforeId = page.last;
      }
    } catch (_) {
      /* A setup/recovery failure never blocks the library. */
    }
  }

  void foreground() {
    _foreground = true;
    _suspended = false;
    unawaited(recheckModel());
    unawaited(_resumePreviews());
  }

  Future<void> recheckModel() async {
    await lab.refreshModel();
    if (!_disposed) {
      notifyListeners();
      await _queueReadySources();
    }
  }

  Future<void> deleteModel() async {
    if (download.busy || lab.phase == LabPhase.importing) {
      throw StateError('Wait for model setup to finish first.');
    }
    if (_deletingModel) return;
    _deletingModel = true;
    notifyListeners();
    try {
      await stop();
      await lab.releaseMemory();
      await _processingDone?.future;
      await lab.deleteModel();
      await download.discard();
    } finally {
      _deletingModel = false;
      if (_foreground) _suspended = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<int> save(SaveDraft draft, {int? id}) async {
    if (id != null && (id == activeId || _queue.contains(id))) {
      throw StateError('Stop extraction before editing this save.');
    }
    final previous = id == null ? null : await store.get(id);
    final saved = await store.save(draft, id: id);
    if (id == null) supportSaveEpoch++;
    if (previous != null && previous.attachment != draft.attachment) {
      await _deleteAttachment(previous.attachment);
    }
    await refresh();
    unawaited(_maybeAutoExtract(saved));
    return saved;
  }

  Future<void> favorite(SavedItem item) async {
    await store.favorite(item.id, !item.favorite);
    await refresh();
  }

  Future<void> remove(SavedItem item) async {
    if (activeId == item.id || _queue.contains(item.id)) {
      throw StateError('Stop extraction before deleting this save.');
    }
    await store.remove(item.id);
    await _deleteAttachment(item.attachment);
    await refresh();
  }

  Future<void> _deleteAttachment(String name) async {
    if (RegExp(r'^\d+(?:\.[a-zA-Z0-9]{1,8})?$').hasMatch(name)) {
      try {
        final directory =
            attachmentDirectory ??
            Directory(
              '${(await getApplicationSupportDirectory()).path}/attachments',
            );
        final file = File('${directory.path}/$name');
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        /* A missing private copy does not undo deletion. */
      }
    }
  }

  Future<void> collection(String name, int color, {int? id}) async {
    await store.saveCollection(name, color, id: id);
    await refresh();
  }

  Future<void> removeCollection(int id) async {
    await store.deleteCollection(id);
    await refresh();
  }

  Future<void> extract(SavedItem item, {bool automatic = false}) async {
    item =
        await store.get(item.id) ??
        (throw StateError('This save no longer exists.'));
    if (automatic &&
        (_disposed ||
            !_foreground ||
            _suspended ||
            !autoExtract ||
            !item.autoExtract ||
            item.status != 'idle')) {
      return;
    }
    if (download.busy || lab.phase == LabPhase.importing) {
      throw StateError('Wait for model setup to finish before extracting.');
    }
    if (_pressureRelease != null) {
      throw StateError(
        'Android is reclaiming memory. Please retry in a moment.',
      );
    }
    if (!modelAvailable) {
      throw StateError(
        'Download or import the optional AI model in Settings first.',
      );
    }
    if (item.body.trim().isEmpty) {
      throw StateError(
        'Add English text, a caption or transcript first. A link alone cannot be summarized.',
      );
    }
    if (item.body.length > 30000) {
      throw StateError(
        'Keep extraction text within the 30,000-character save limit.',
      );
    }
    if (!supportsEnglishExtraction(item.body)) {
      throw StateError(
        'Extraction currently supports English text. Your original save is kept unchanged.',
      );
    }
    if (_queue.contains(item.id) || activeId == item.id) return;
    _suspended = false;
    _queue.add(item.id);
    await store.status(item.id, 'queued');
    await refresh();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (processing || _suspended || _disposed) return;
    processing = true;
    final done = _processingDone = Completer<void>();
    processingError = '';
    notifyListeners();
    try {
      while (_queue.isNotEmpty && !_suspended && !_disposed) {
        final id = _queue.removeAt(0);
        final item = await store.get(id);
        if (_disposed) break;
        if (item == null) continue;
        activeId = id;
        activeTitle = item.title;
        notifyListeners();
        await store.status(id, 'running');
        await refresh();
        await lab.whenIdle();
        if (!_suspended && !_disposed && !lab.modelLoaded) await lab.load();
        if (_suspended || _disposed || !lab.modelLoaded) {
          await store.status(
            id,
            _suspended ? 'cancelled' : 'failed',
            error: lab.error ?? 'Processing stopped. Tap Extract to try again.',
          );
          if (!_suspended) {
            await LocalNotifications.instance.show(saveId: id, failed: true);
          }
          continue;
        }
        final hint =
            item.kind.extractionType ??
            (item.contentKind == 'article'
                ? SourceRules.articleHint(SourceDocument(item.body))
                : null);
        await lab.extract(item.body, typeHint: hint);
        if (_disposed) break;
        if (lab.result != null && !_suspended) {
          final saved = await store.extraction(
            id,
            item.body,
            lab.rawOutput,
            lab.result!,
            evidenceSource: lab.evidence?.text,
          );
          if (saved) {
            await LocalNotifications.instance.show(
              saveId: id,
              partial: lab.result!.isPartial,
            );
          }
        } else {
          await store.status(
            id,
            lab.phase == LabPhase.cancelled || _suspended
                ? 'cancelled'
                : 'failed',
            error: lab.error ?? 'Extraction stopped. Your source is safe.',
          );
          if (lab.phase != LabPhase.cancelled && !_suspended) {
            await LocalNotifications.instance.show(saveId: id, failed: true);
          }
        }
        await refresh();
      }
    } catch (e) {
      processingError = 'Processing stopped. $e';
      if (activeId != null && !_disposed) {
        await store.status(activeId!, 'failed', error: processingError);
        if (!_suspended) {
          await LocalNotifications.instance.show(
            saveId: activeId,
            failed: true,
          );
        }
      }
    } finally {
      // Browsing does not need the model resident after the queue drains.
      if (!_disposed) await lab.unload();
      activeId = null;
      activeTitle = '';
      processing = false;
      _processingDone = null;
      done.complete();
      if (!_disposed) {
        await refresh();
        notifyListeners();
        if (_queue.isNotEmpty && !_suspended) {
          unawaited(_drain());
        } else if (!_suspended) {
          unawaited(_queueReadySources());
        }
      }
    }
  }

  Future<void> stop() async {
    _suspended = true;
    lab.cancel();
    final pending = _queue.toList();
    _queue.clear();
    for (final id in pending) {
      await store.status(
        id,
        'cancelled',
        error: 'Extraction stopped. Tap Extract to try again.',
      );
    }
    if (!_disposed) await refresh();
  }

  Future<void> background() async {
    _foreground = false;
    download.pause();
    await stop();
    await lab.releaseMemory();
  }

  /// A low-memory warning is not an app-background event. Drain native work
  /// before releasing its context, then keep future foreground saves eligible
  /// for automatic extraction. Interrupted work requires an explicit retry.
  Future<void> memoryPressure() =>
      _pressureRelease ??= _releaseForPressure().whenComplete(() {
        _pressureRelease = null;
      });

  Future<void> _releaseForPressure() async {
    final affected = <int>{?activeId, ..._queue};
    final active = _processingDone?.future;
    try {
      await stop();
      await lab.releaseMemory();
      await active;
      if (_disposed) return;
      for (final id in affected) {
        await store.status(
          id,
          'interrupted',
          error:
              'Android needed memory. Your save is safe. Tap Extract to retry.',
        );
      }
      await refresh();
    } finally {
      if (!_disposed && _foreground) _suspended = false;
    }
  }

  Future<void> downloadModel() async {
    if (_deletingModel) throw StateError('Wait for model deletion to finish.');
    if (compactModelInstalled) return;
    if (processing || lab.busy) {
      throw StateError('Stop extraction before changing the model.');
    }
    await lab.unload();
    final installed = await download.start();
    if (installed != null && !_disposed) {
      lab.model = installed;
      lab.selectionManaged = true;
      lab.error = null;
      lab.phase = LabPhase.idle;
      notifyListeners();
      unawaited(_queueReadySources());
    }
  }

  Future<void> importModel(String path, String name) async {
    if (processing || download.busy) {
      throw StateError('Stop processing before changing the model.');
    }
    await lab.importModel(path, name);
    if (lab.error != null) throw StateError(lab.error!);
    if (!_disposed) notifyListeners();
    if (!_disposed) unawaited(_queueReadySources());
  }

  @override
  void dispose() {
    _disposed = true;
    for (final job in _previews.values) {
      job.cancel();
    }
    _previews.clear();
    _suspended = true;
    _queue.clear();
    lab.dispose();
    download.dispose();
    changes.dispose();
    super.dispose();
  }
}
