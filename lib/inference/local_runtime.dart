import '../domain/extraction.dart';

class RuntimeSettings {
  const RuntimeSettings({this.threads = 2});
  final int threads;
  static const contextSize = 2048;
  static const maxOutputTokens = 512;
  static const batchSize = 64;
  static const microBatchSize = 16;
}

abstract interface class ProgressRuntime {
  set onProgress(void Function(int part, int total, bool firstToken)? callback);
}

abstract interface class LocalRuntime {
  Future<void> load(String path, RuntimeSettings settings);
  Stream<String> extract(SourceDocument source);
  void cancel();
  Future<void> unload();
  Future<void> dispose();
}
