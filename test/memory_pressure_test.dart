import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/inference/local_runtime.dart';
import 'package:linqo/inference/model_store.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';

class _PressureRuntime implements LocalRuntime {
  Completer<void>? pendingLoad = Completer<void>();
  int loads = 0, unloads = 0;
  @override
  Future<void> load(String path, RuntimeSettings settings) async {
    loads++;
    await pendingLoad?.future;
  }

  @override
  Stream<String> extract(SourceDocument source) async* {
    yield jsonEncode({
      'schema_version': 2,
      'title': 'Dinner',
      'summary': 'Cook and serve.',
      'type': 'recipe',
      'ingredient_lines': [],
      'step_lines': [1],
      'places': [],
      'detail_lines': [],
    });
  }

  @override
  void cancel() {}
  @override
  Future<void> unload() async {
    unloads++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'memory pressure drains loading and queued work, then new foreground saves still extract automatically',
    () async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final runtime = _PressureRuntime();
      final c = LibraryController(store, runtime: runtime);
      c.lab.model = const ImportedModel(
        path: '/fake.gguf',
        name: 'fake',
        bytes: 42,
        sha256: 'fake',
      );
      Future<void> until(bool Function() condition) async {
        final clock = Stopwatch()..start();
        while (!condition() && clock.elapsedMilliseconds < 3000) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(condition(), isTrue);
      }

      try {
        await c.initialize(restoreModel: false);
        final first = await c.save(
          const SaveDraft(
            title: 'First',
            body: 'Cook and serve.',
            kind: SaveKind.recipe,
            autoExtract: true,
          ),
        );
        await until(() => runtime.loads == 1);
        final second = await c.save(
          const SaveDraft(
            title: 'Second',
            body: 'Cook and serve.',
            kind: SaveKind.recipe,
            autoExtract: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect((await store.get(second))!.status, 'queued');
        final release = c.memoryPressure();
        expect(identical(release, c.memoryPressure()), isTrue);
        runtime.pendingLoad!.complete();
        runtime.pendingLoad = null;
        await release;
        expect(c.processing, isFalse);
        expect(c.lab.modelLoaded, isFalse);
        expect((await store.get(first))!.status, 'interrupted');
        expect((await store.get(second))!.status, 'interrupted');
        final third = await c.save(
          const SaveDraft(
            title: 'New save',
            body: 'Cook and serve.',
            kind: SaveKind.recipe,
            autoExtract: true,
          ),
        );
        await until(() => runtime.loads == 2 && !c.processing);
        expect((await store.get(third))!.status, 'partial');
        expect(
          (await store.get(third))!.extraction?.recipe?.steps,
          hasLength(1),
        );
        expect(c.lab.modelLoaded, isFalse);
      } finally {
        c.dispose();
        await store.close();
      }
    },
  );
}
