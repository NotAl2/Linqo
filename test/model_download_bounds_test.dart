import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/inference/model_store.dart';
import 'package:linqo/inference/model_download.dart';

void main() {
  test(
    'bounded download resumes, verifies exact size and installs only once',
    () async {
      final root = await Directory.systemTemp.createTemp('linqo-download-');
      final bytes = [71, 71, 85, 70, ...List.filled(256 * 1024, 42)];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final partial = File('${root.path}/downloads/english-model.gguf.part');
      await partial.parent.create();
      await partial.writeAsBytes(bytes.take(100).toList());
      server.listen((req) async {
        expect(req.headers.value('range'), 'bytes=100-');
        req.response.statusCode = 206;
        req.response.headers.set(
          'content-range',
          'bytes 100-${bytes.length - 1}/${bytes.length}',
        );
        req.response.contentLength = bytes.length - 100;
        req.response.add(bytes.sublist(100));
        await req.response.close();
      });
      final store = ModelStore(directory: Directory('${root.path}/models'));
      final download = ModelDownload(
        store: store,
        directory: partial.parent,
        url: Uri.parse('http://127.0.0.1:${server.port}/model'),
        sha: sha256.convert(bytes).toString(),
        bytes: bytes.length,
      );
      try {
        await download.initialize();
        expect(download.phase, DownloadPhase.paused);
        final installed = await download.start();
        expect(installed!.bytes, bytes.length);
        expect(download.phase, DownloadPhase.complete);
        expect(await partial.exists(), isFalse);
        expect((await store.restore())!.sha256, installed.sha256);
      } finally {
        download.dispose();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
  test('wrong advertised size is discarded before installation', () async {
    final root = await Directory.systemTemp.createTemp(
      'linqo-download-reject-',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.contentLength = 24;
      req.response.add(List.filled(24, 0));
      await req.response.close();
    });
    final store = ModelStore(directory: Directory('${root.path}/models'));
    final download = ModelDownload(
      store: store,
      directory: Directory('${root.path}/downloads'),
      url: Uri.parse('http://127.0.0.1:${server.port}/model'),
      sha: 'unused',
      bytes: 100,
    );
    try {
      expect(await download.start(), isNull);
      expect(download.phase, DownloadPhase.failed);
      expect(download.received, 0);
      expect(await store.restore(), isNull);
    } finally {
      download.dispose();
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });
}
