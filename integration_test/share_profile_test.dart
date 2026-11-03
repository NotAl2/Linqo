import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/main.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/ui/save_editor.dart';
import 'package:linqo/ui/save_detail.dart';
import 'package:linqo/sharing/shared_content.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Android incoming shares save without waiting for previews', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/linqo-share-qa.db';
    await deleteDatabase(path);
    final store = await LibraryStore.open(path: path);
    final controller = LibraryController(store);
    await controller.initialize(restoreModel: false);
    // Recover only this harness's interrupted fixtures, never a personal share.
    for (var i = 0; i < 32; i++) {
      final pending = await AndroidShareInbox().peek();
      if (pending == null) break;
      expect(
        const bool.fromEnvironment('LINQO_RESET_TEST_INBOX') ||
            [
              'https://youtu.be/jNQXAC9IVRw',
              'https://example.com/',
              'https://maps.google.com/?q=National+Gallery+London',
              'https://www.instagram.com/reel/C68_iOZOZf-/',
              'https://www.instagram.com/p/De5LCBKuASV/?psln=MXc4ZzcxOTdjYWdkZA==',
            ].contains(pending.text),
        isTrue,
        reason:
            'A personal share is pending; preserve it unless a full reset was explicitly authorized.',
      );
      await AndroidShareInbox().acknowledge(pending.id);
    }
    final cases = <Map<String, Object?>>[];
    final previousReport = binding.reportData;
    binding.reportData = {
      'synthetic_test_session': true,
      'shares': cases,
      if (previousReport?['native_extraction'] != null)
        'performance': previousReport,
    };
    Future<void> waitFor(bool Function() condition, {int seconds = 25}) async {
      final watch = Stopwatch()..start();
      while (!condition()) {
        if (watch.elapsed > Duration(seconds: seconds)) {
          throw TimeoutException('Share UI timed out');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    try {
      await tester.pumpWidget(
        LinqoApp(controller: controller, enableSharing: true),
      );
      await tester.pumpAndSettle();
      for (final name in ['YOUTUBE', 'WEBSITE', 'PLACE', 'REEL', 'USER_POST']) {
        debugPrint('LINQO_SHARE_READY_$name');
        await waitFor(
          () => find.byType(SaveEditor).evaluate().isNotEmpty,
          seconds: 60,
        );
        await tester.pumpAndSettle();
        final fields = tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .toList();
        expect(fields[0].controller!.text, isNotEmpty);
        final originalUrl = fields[1].controller!.text;
        expect(originalUrl.startsWith('https://'), isTrue);
        if (name == 'WEBSITE') {
          fields[0].controller!.text = 'My reading list';
          fields[0].onChanged!('My reading list');
        }
        await tester.scrollUntilVisible(
          find.text('Save to Linqo'),
          300,
          scrollable: find
              .descendant(
                of: find.byType(SaveEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        final watch = Stopwatch()..start();
        await tester.tap(find.text('Save to Linqo'));
        await waitFor(() => find.byType(SaveEditor).evaluate().isEmpty);
        final saveMs = watch.elapsedMilliseconds;
        final item = (await store.query()).first;
        expect(item.url, originalUrl);
        expect(controller.processing, isFalse);
        final deadline = Stopwatch()..start();
        var full = (await store.get(item.id))!;
        while ((full.previewStatus == 'pending' ||
                controller.previewBusy(item.id)) &&
            deadline.elapsed < const Duration(seconds: 16)) {
          await tester.pump(const Duration(milliseconds: 100));
          full = (await store.get(item.id))!;
        }
        if (name == 'WEBSITE') expect(full.title, 'My reading list');
        if (name == 'YOUTUBE') {
          expect(full.previewStatus, 'ready');
          expect(full.title, isNot('YouTube video'));
          expect(full.previewImage, isNotEmpty);
        }
        if (name == 'PLACE') {
          expect(full.kind.name, 'place');
          expect(full.title, 'National Gallery London');
        }
        expect(full.previewStatus, isNot('pending'));
        cases.add({
          'case': name,
          'save_ui_ms': saveMs,
          'title': full.title,
          'preview_status': full.previewStatus,
          'image_status': full.imageStatus,
          'has_thumbnail': full.previewImage.isNotEmpty,
          'kind': full.kind.name,
        });
      }
      expect(await store.count(), 5);
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('share-library');
      final video = (await store.query()).last;
      final navigation = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigation.push(
          MaterialPageRoute(
            builder: (_) => SaveDetail(controller: controller, id: video.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('share-detail');
      navigation.pop();
      await tester.pumpAndSettle();
      debugPrint('LINQO_SHARE_READY_SCREENSHOT');
      await waitFor(
        () => find.byType(SaveEditor).evaluate().isNotEmpty,
        seconds: 60,
      );
      await tester.pumpAndSettle();
      await waitFor(() => find.text('Looking up preview…').evaluate().isEmpty);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('share-editor');
      await tester.tap(find.text('Content for extraction'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('save-source')));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('share-editor-expanded');
      navigation.pop();
      await tester.pumpAndSettle();
      final drain = Stopwatch()..start();
      while (await AndroidShareInbox().peek() != null &&
          drain.elapsed < const Duration(seconds: 3)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(await AndroidShareInbox().peek(), isNull);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await store.close();
    }
  }, timeout: const Timeout(Duration(minutes: 7)));
}
