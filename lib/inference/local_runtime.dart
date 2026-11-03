import '../domain/extraction.dart';

class RuntimeSettings {
  const RuntimeSettings({this.threads = 2});
  final int threads;
  static const contextSize = 2048;
  static const maxOutputTokens = 768;
  static const batchSize = 64;
  static const microBatchSize = 16;
}

abstract interface class LocalRuntime {
  Future<void> load(String path, RuntimeSettings settings);
  Stream<String> extract(SourceDocument source);
  void cancel();
  Future<void> unload();
  Future<void> dispose();
}
