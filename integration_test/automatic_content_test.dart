import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/sharing/shared_content.dart';
import 'package:linqo/ui/save_editor.dart';
import 'package:linqo/ui/save_detail.dart';
import 'package:linqo/ui/settings_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'saving a public share fetches source content without copying captions',
    (tester) async {
      final path = '${await getDatabasesPath()}/linqo-automatic-content-qa.db';
      await deleteDatabase(path);
      final store = await LibraryStore.open(path: path);
      final controller = LibraryController(store);
      await controller.initialize(restoreModel: false);
      final results = <String, Object?>{};
      try {
        await tester.pumpWidget(
          LinqoApp(controller: controller, enableSharing: false),
        );
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        const url = 'https://www.instagram.com/p/De5LCBKuASV/';
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => SaveEditor(
                controller: controller,
                shared: const SharedContent(
                  id: 'auto-content-fixture',
                  text: url,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save to Linqo'));
        await tester.pumpAndSettle();
        final id = (await store.query()).single.id;
        final clock = Stopwatch()..start();
        while (controller.previewBusy(id) &&
            clock.elapsed < const Duration(seconds: 20)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final item = (await store.get(id))!;
        results['instagram'] = {
          'characters': item.body.length,
          'kind': item.contentKind,
          'status': item.contentStatus,
          'notes_untouched': item.notes.isEmpty,
        };
        expect(item.body.length, greaterThan(400));
        expect(item.contentKind, 'caption');
        expect(item.notes, isEmpty);
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => SaveDetail(controller: controller, id: item.id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await binding.takeScreenshot('automatic-content-detail');
        await tester.scrollUntilVisible(
          find.text('Fetched public caption'),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('automatic-content-caption');
        nav.pop();
        await tester.pumpAndSettle();
        for (final entry in [
          ('recipe', 'https://www.budgetbytes.com/basic-chili/'),
          ('youtube', 'https://www.youtube.com/watch?v=aqz-KE-bpKQ'),
        ]) {
          final saveId = await controller.save(
            SaveDraft(
              title: 'Saved ${entry.$1}',
              url: entry.$2,
              kind: SaveKind.link,
              automaticContent: true,
              autoExtract: false,
            ),
          );
          await controller.enrichPreview(saveId, entry.$2, 'Saved ${entry.$1}');
          final saved = (await store.get(saveId))!;
          results[entry.$1] = {
            'characters': saved.body.length,
            'kind': saved.contentKind,
            'status': saved.contentStatus,
          };
        }
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Summarize saves automatically'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await binding.takeScreenshot('automatic-content-settings');
        expect(controller.modelAvailable, isFalse);
        expect(controller.processing, isFalse);
        binding.reportData ??= {};
        binding.reportData!.addAll({
          'content_results': results,
          'model_loaded': false,
          'qa_database': true,
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await store.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
