import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/domain/extraction.dart';
import 'package:linqo/inference/local_runtime.dart';
import 'package:linqo/inference/model_store.dart';
import 'package:linqo/ui/save_editor.dart';
import 'package:linqo/ui/library_shell.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/sharing/shared_content.dart';
import 'package:linqo/sharing/link_preview.dart';

class PendingPreview extends PreviewJob {
  final result = Completer<LinkPreview>();
  Completer<LinkPreview>? early;
  @override
  Future<LinkPreview> get metadata => early?.future ?? future;
  bool cancelled = false;
  @override
  Future<LinkPreview> get future => result.future;
  @override
  void cancel() {
    cancelled = true;
  }
}

class PendingRuntime implements LocalRuntime {
  final stream = StreamController<String>();
  @override
  Future<void> load(String path, RuntimeSettings settings) async {}
  @override
  Stream<String> extract(SourceDocument source) => stream.stream;
  @override
  void cancel() {}
  @override
  Future<void> unload() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late LibraryController controller;
  late PendingRuntime runtime;
  setUp(() async {
    store = await LibraryStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    runtime = PendingRuntime();
    controller = LibraryController(store, runtime: runtime);
    await controller.initialize(restoreModel: false);
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
  });
  testWidgets(
    'title arrives before image and notes stay separate from shared content',
    (tester) async {
      final job = PendingPreview()..early = Completer<LinkPreview>();
      await tester.pumpWidget(
        MaterialApp(
          home: SaveEditor(
            controller: controller,
            shared: const SharedContent(
              id: 'split',
              text: 'A shared caption https://example.org',
            ),
            previewFactory: (_) => job,
          ),
        ),
      );
      await tester.pumpAndSettle();
      job.early!.complete(
        const LinkPreview(
          title: 'Automatic title',
          available: true,
          imageStatus: 'pending',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Automatic title',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('save-notes')));
      await tester.enterText(
        find.byKey(const ValueKey('save-notes')),
        'Try this on Sunday',
      );
      await tester.tap(find.text('Save to Linqo'));
      await tester.pumpAndSettle();
      expect((await store.query()).single.body, 'A shared caption');
      expect((await store.query()).single.notes, 'Try this on Sunday');
      job.result.complete(
        const LinkPreview(
          title: 'Automatic title',
          available: true,
          imageStatus: 'unavailable',
        ),
      );
      await tester.pumpAndSettle();
      expect((await store.query()).single.title, 'Automatic title');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'refresh after failed metadata fills the title without extraction',
    (tester) async {
      final first = PendingPreview(), retry = PendingPreview();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SaveEditor(
            controller: controller,
            shared: const SharedContent(
              id: 'retry',
              text: 'https://example.org',
            ),
            previewFactory: (_) => calls++ == 0 ? first : retry,
          ),
        ),
      );
      first.result.complete(const LinkPreview());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Refresh details'));
      await tester.tap(find.text('Refresh details'));
      await tester.pumpAndSettle();
      retry.result.complete(
        const LinkPreview(title: 'Recovered title', available: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Linqo'));
      await tester.pumpAndSettle();
      expect((await store.query()).single.title, 'Recovered title');
      expect(controller.processing, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('shared Save stays above the keyboard with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final job = PendingPreview();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
            viewInsets: EdgeInsets.only(bottom: 300),
          ),
          child: SaveEditor(
            controller: controller,
            shared: const SharedContent(
              id: 'keyboard-share',
              text: 'https://example.org',
            ),
            previewFactory: (_) => job,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Save to Linqo')).bottom,
      lessThanOrEqualTo(500),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Save to Linqo'));
    await tester.pumpAndSettle();
    expect(await store.count(), 1);
    job.result.complete(const LinkPreview());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('shared save commits before preview and enriches afterwards', (
    tester,
  ) async {
    final job = PendingPreview();
    await tester.pumpWidget(
      MaterialApp(
        home: SaveEditor(
          controller: controller,
          shared: const SharedContent(
            id: 'receipt-fast',
            text: 'A caption https://example.org/article',
          ),
          previewFactory: (_) => job,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Looking up preview…'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save to Linqo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save to Linqo'));
    await tester.pumpAndSettle();
    expect(await store.count(), 1);
    expect((await store.query()).single.title, 'A caption');
    expect((await store.query()).single.body, 'A caption');
    expect(controller.processing, isFalse);
    job.result.complete(
      const LinkPreview(
        title: 'A useful article',
        description: 'Page description',
        available: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      (await store.query(query: 'useful article')).single.description,
      'Page description',
    );
    expect(await store.receivedShare('receipt-fast'), isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('late preview preserves a title the user types', (tester) async {
    final job = PendingPreview();
    await tester.pumpWidget(
      MaterialApp(
        home: SaveEditor(
          controller: controller,
          shared: const SharedContent(
            id: 'receipt-edit',
            text: 'https://example.org/article',
          ),
          previewFactory: (_) => job,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'My own title');
    job.result.complete(
      const LinkPreview(
        title: 'Automatic title',
        description: 'A page preview',
        available: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'My own title',
    );
    await tester.scrollUntilVisible(
      find.text('Save to Linqo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save to Linqo'));
    await tester.pumpAndSettle();
    expect((await store.query()).single.title, 'My own title');
    expect((await store.query()).single.description, 'A page preview');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('library and search remain usable while inference is pending', (
    tester,
  ) async {
    final id = await controller.save(
      const SaveDraft(
        title: 'Chickpea skillet',
        body: 'Ingredients: chickpeas\nSimmer for 10 minutes.',
        kind: SaveKind.recipe,
      ),
    );
    await controller.save(
      const SaveDraft(
        title: 'Coffee on Saturday',
        body: 'Visit Monmouth Coffee.',
        kind: SaveKind.place,
      ),
    );
    controller.lab.model = const ImportedModel(
      path: '/test.gguf',
      name: 'test',
      bytes: 100,
      sha256: 'test',
    );
    await tester.pumpWidget(LinqoApp(controller: controller));
    await tester.pumpAndSettle();
    await controller.extract((await store.get(id))!);
    await tester.pump();
    expect(controller.processing, isTrue);
    await tester.tap(find.byIcon(Icons.search_rounded).last);
    // Indeterminate progress deliberately animates while the job is pending.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      find.byKey(const ValueKey('library-search')),
      'coffee',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Coffee on Saturday'), findsWidgets);
    expect(controller.processing, isTrue);
    await controller.stop();
    await runtime.stream.close();
    await tester.pumpAndSettle();
    expect((await store.get(id))!.status, 'cancelled');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('save editor creates a durable note without a model', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SaveEditor(controller: controller)),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Note'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'A small idea');
    await tester.enterText(fields.at(1), 'Take the scenic route.');
    await tester.scrollUntilVisible(
      find.text('Save to Linqo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save to Linqo'));
    await tester.pumpAndSettle();
    expect((await store.query()).single.title, 'A small idea');
    expect((await store.query()).single.body, 'Take the scenic route.');
  });
  testWidgets('typing source text enables optional extraction', (tester) async {
    controller.lab.model = const ImportedModel(
      path: '/test.gguf',
      name: 'test',
      bytes: 100,
      sha256: 'test',
    );
    await tester.pumpWidget(
      MaterialApp(home: SaveEditor(controller: controller)),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'An English note.',
    );
    await tester.scrollUntilVisible(
      find.byType(SwitchListTile),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'phone, tablet, dark and large-text library layouts do not overflow',
    (tester) async {
      await controller.save(
        const SaveDraft(
          title:
              'A long title for a very useful little discovery worth keeping',
          body: 'Some source notes that wrap naturally and remain readable.',
          kind: SaveKind.note,
        ),
      );
      await controller.collection('A collection with a long name', 0);
      for (final size in [const Size(360, 800), const Size(1100, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          controller.theme = mode;
          for (final scale in [1.0, 2.0]) {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(
              MaterialApp(
                theme: linqoTheme(
                  mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: LibraryShell(controller: controller),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$size $mode $scale',
            );
          }
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
