import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'model_store.dart';
import '../services/diagnostics.dart';

enum DownloadPhase { idle, downloading, paused, verifying, complete, failed }

class ModelDownload extends ChangeNotifier {
  ModelDownload({
    ModelStore? store,
    Directory? directory,
    Uri? url,
    String? sha,
    int? bytes,
  }) : store = store ?? ModelStore(),
       _directory = directory,
       url =
           url ??
           Uri.parse(
             'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/50968a4468ef4233ed78cd7c3de230dd1d61a56b/Qwen3-0.6B-Q4_K_M.gguf',
           ),
       expectedBytes = bytes ?? (url == null ? 396705472 : null),
       expectedSha =
           sha ??
           'ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a';
  final ModelStore store;
  final Directory? _directory;
  final Uri url;
  final String expectedSha;
  final int? expectedBytes;
  DownloadPhase phase = DownloadPhase.idle;
  int received = 0;
  int? total;
  String? error;
  bool _paused = false, _disposed = false;
  HttpClient? _client;
  bool get busy =>
      phase == DownloadPhase.downloading || phase == DownloadPhase.verifying;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<File> _partial() async {
    final root =
        _directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/downloads');
    await root.create(recursive: true);
    return File('${root.path}/english-model.gguf.part');
  }

  Future<void> initialize() async {
    try {
      final file = await _partial();
      if (await file.exists() && !busy) {
        received = await file.length();
        phase = DownloadPhase.paused;
        _emit();
      }
    } catch (e) {
      error = 'Could not prepare model storage. $e';
      phase = DownloadPhase.failed;
      _emit();
    }
  }

  void pause() {
    if (phase != DownloadPhase.downloading) return;
    _paused = true;
    _client?.close(force: true);
  }

  Future<void> discard() async {
    if (busy) throw StateError('Pause the download before removing it.');
    final file = await _partial();
    if (await file.exists()) await file.delete();
    phase = DownloadPhase.idle;
    received = 0;
    total = null;
    error = null;
    _emit();
  }

  Future<ImportedModel?> start() async {
    if (busy || _disposed) return null;
    _paused = false;
    error = null;
    phase = DownloadPhase.downloading;
    _emit();
    File? partial;
    final client = _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final file = await _partial();
      partial = file;
      var offset = await file.exists() ? await file.length() : 0;
      received = offset;
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 40),
      );
      var alreadyComplete = false;
      if (response.statusCode == 416 &&
          response.headers.value('content-range') == 'bytes */$offset') {
        alreadyComplete = true;
        total = offset;
      } else if (response.statusCode == 206) {
        final range = RegExp(
          r'^bytes (\d+)-(\d+)/(\d+)$',
        ).firstMatch(response.headers.value('content-range') ?? '');
        if (range == null ||
            int.parse(range[1]!) != offset ||
            int.parse(range[2]!) < offset ||
            int.parse(range[2]!) >= int.parse(range[3]!)) {
          throw const HttpException('Invalid resume response.');
        }
        total = int.parse(range[3]!);
      } else if (response.statusCode == 200) {
        offset = 0;
        received = 0;
        total = response.contentLength >= 0 ? response.contentLength : null;
      } else {
        throw HttpException('Download server returned ${response.statusCode}.');
      }
      if ((total ?? 0) > 700 * 1024 * 1024) {
        throw const HttpException('Unexpected model download size.');
      }
      if (expectedBytes != null && total != null && total != expectedBytes) {
        throw const FormatException('Unexpected model download size.');
      }
      if (!alreadyComplete) {
        final sink = file.openWrite(
          mode: offset == 0 ? FileMode.write : FileMode.append,
        );
        final progress = Stopwatch()..start();
        var buffered = 0;
        try {
          await for (final chunk in response.timeout(
            const Duration(seconds: 40),
          )) {
            if (_paused || _disposed) break;
            received += chunk.length;
            if (received > (expectedBytes ?? 700 * 1024 * 1024)) {
              throw const FormatException('Unexpected model download size.');
            }
            sink.add(chunk);
            buffered += chunk.length;
            // Bound buffered I/O without a filesystem flush for every packet.
            if (buffered >= 256 * 1024) {
              await sink.flush();
              buffered = 0;
            }
            if (progress.elapsedMilliseconds >= 150) {
              progress.reset();
              _emit();
            }
          }
        } finally {
          await sink.close();
        }
      }
      if (_paused || _disposed) {
        phase = DownloadPhase.paused;
        _emit();
        return null;
      }
      if (total != null && received != total) {
        throw const HttpException(
          'Download was incomplete. Resume to continue.',
        );
      }
      if (expectedBytes != null && received != expectedBytes) {
        throw const HttpException(
          'Download was incomplete. Resume to continue.',
        );
      }
      phase = DownloadPhase.verifying;
      _emit();
      final model = await store.installDownload(
        file.path,
        'Qwen3-0.6B-Q4_K_M.gguf',
        expectedSha,
      );
      phase = DownloadPhase.complete;
      Diagnostics.instance.record('model.download_complete');
      _emit();
      return model;
    } catch (e) {
      if (!_paused && !_disposed) {
        Diagnostics.instance.record('model.download_failed', error: e);
      }
      phase = _paused || _disposed
          ? DownloadPhase.paused
          : DownloadPhase.failed;
      if (!_paused && !_disposed) error = 'Download could not finish. $e';
      if (e is FormatException && partial != null && await partial.exists()) {
        await partial.delete();
        received = 0;
      }
      _emit();
      return null;
    } finally {
      client.close(force: true);
      _client = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _paused = true;
    _client?.close(force: true);
    super.dispose();
  }
}
