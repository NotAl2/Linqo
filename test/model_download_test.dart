import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/inference/model_download.dart';
import 'package:linqo/inference/model_store.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  final bytes = [71, 71, 85, 70, ...List.generate(512 * 1024, (i) => i % 251)];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('linqo-download-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  ModelDownload downloader({String? hash}) => ModelDownload(
    directory: Directory('${directory.path}/downloads'),
    store: ModelStore(directory: Directory('${directory.path}/models')),
    url: Uri.parse('http://127.0.0.1:${server.port}/model'),
    sha: hash ?? sha256.convert(bytes).toString(),
  );
  test(
    'optional download verifies and installs without retaining a duplicate',
    () async {
      server.listen((request) async {
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      final download = downloader();
      final result = await download.start();
      expect(result, isNotNull);
      expect(download.phase, DownloadPhase.complete);
      expect(
        (await ModelStore(
          directory: Directory('${directory.path}/models'),
        ).restore())!.sha256,
        sha256.convert(bytes).toString(),
      );
      expect(
        await File(
          '${directory.path}/downloads/english-model.gguf.part',
        ).exists(),
        isFalse,
      );
      download.dispose();
    },
  );
  test(
    'paused download survives a new instance and resumes with a validated range',
    () async {
      final ranges = <String?>[];
      server.listen((request) async {
        final range = request.headers.value('range');
        ranges.add(range);
        final offset = range == null
            ? 0
            : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
        if (offset > 0) {
          request.response.statusCode = 206;
          request.response.headers.set(
            'content-range',
            'bytes $offset-${bytes.length - 1}/${bytes.length}',
          );
        }
        request.response.contentLength = bytes.length - offset;
        try {
          for (var index = offset; index < bytes.length; index += 8192) {
            request.response.add(
              bytes.sublist(index, (index + 8192).clamp(0, bytes.length)),
            );
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 8));
          }
          await request.response.close();
        } catch (_) {
          /* Expected disconnect on pause. */
        }
      });
      final first = downloader();
      first.addListener(() {
        if (first.received > 0 && first.phase == DownloadPhase.downloading) {
          first.pause();
        }
      });
      expect(await first.start(), isNull);
      expect(first.phase, DownloadPhase.paused);
      first.dispose();
      final resumed = downloader();
      await resumed.initialize();
      expect(resumed.phase, DownloadPhase.paused);
      expect(await resumed.start(), isNotNull);
      expect(ranges.last, startsWith('bytes='));
      resumed.dispose();
    },
  );
  test('corrupt download preserves the previous selected model', () async {
    final store = ModelStore(directory: Directory('${directory.path}/models'));
    final original = File('${directory.path}/original.gguf');
    await original.writeAsBytes(bytes);
    final selected = await store.import(original.path, 'original.gguf');
    server.listen((request) async {
      request.response.add(bytes);
      await request.response.close();
    });
    final download = downloader(hash: '0' * 64);
    expect(await download.start(), isNull);
    expect(download.phase, DownloadPhase.failed);
    expect((await store.restore())!.path, selected.path);
    expect(
      await File(
        '${directory.path}/downloads/english-model.gguf.part',
      ).exists(),
      isFalse,
    );
    download.dispose();
  });
}
