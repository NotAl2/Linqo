import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/main.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/ui/brand.dart';
import 'package:linqo/ui/save_editor.dart';
import 'package:linqo/ui/save_detail.dart';
import 'package:linqo/ui/settings_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('mascot identity across library, editing and appearance', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/linqo-brand-qa.db';
    await deleteDatabase(path);
    final store = await LibraryStore.open(path: path);
    final c = LibraryController(store);
    await c.initialize(restoreModel: false);
    binding.reportData = {'synthetic_fixtures': true, 'model_loaded': false};
    Future<void> settle() async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> shot(String name) async {
      await settle();
      await binding.takeScreenshot('brand-$name');
    }

    try {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: linqoTheme(Brightness.light),
          home: const LinqoSplash(),
        ),
      );
      await settle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await shot('splash');
      await tester.pumpWidget(LinqoApp(controller: c));
      await shot('empty');
      final food = await store.saveCollection('Things to cook', 0);
      await store.saveCollection('Little adventures', 2);
      final first = await store.save(
        SaveDraft(
          title: 'Miso butter noodles',
          body:
              'A cosy dinner for the weekend. Miso, butter, spring onions and noodles.',
          kind: SaveKind.recipe,
          collectionIds: [food],
          notes: 'Try this on a rainy Sunday.',
        ),
      );
      await store.save(
        const SaveDraft(
          title: 'A café worth the detour',
          body: 'Coffee and a window seat in the old neighbourhood.',
          kind: SaveKind.place,
        ),
      );
      await store.save(
        const SaveDraft(
          title: 'A slow Sunday playlist',
          body: 'A few songs for a quiet afternoon.',
          kind: SaveKind.video,
        ),
      );
      await store.save(
        const SaveDraft(
          title: 'Small spaces, big ideas',
          body: 'Colourful corners and clever shelves for a little home.',
          kind: SaveKind.link,
        ),
      );
      await store.save(
        const SaveDraft(
          title: 'A tiny reminder',
          body: 'Make a little time for the things you love.',
          kind: SaveKind.note,
        ),
      );
      await store.save(
        const SaveDraft(
          title: 'A recipe to come back to',
          body: 'Roasted tomatoes, good olive oil and a little patience.',
          kind: SaveKind.recipe,
        ),
      );
      await c.refresh();
      await shot('library-light');
      await tester.tap(
        find.widgetWithText(NavigationDestination, 'Collections'),
      );
      await shot('collections');
      await tester.tap(find.widgetWithText(NavigationDestination, 'Search'));
      await settle();
      final search = tester.widget<TextField>(
        find.byKey(const ValueKey('library-search')),
      );
      search.controller!.text = 'noodles';
      search.onChanged!('noodles');
      await tester.pump(const Duration(milliseconds: 400));
      FocusManager.instance.primaryFocus?.unfocus();
      await shot('search');
      await tester.tap(find.widgetWithText(NavigationDestination, 'Library'));
      await settle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(
        nav.push(
          MaterialPageRoute(
            builder: (_) => SaveDetail(controller: c, id: first),
          ),
        ),
      );
      await shot('detail');
      nav.pop();
      await settle();
      unawaited(
        nav.push(MaterialPageRoute(builder: (_) => SaveEditor(controller: c))),
      );
      await shot('editor');
      nav.pop();
      await settle();
      unawaited(
        nav.push(
          MaterialPageRoute(builder: (_) => SettingsScreen(controller: c)),
        ),
      );
      await shot('settings');
      nav.pop();
      await settle();
      await c.appearance(ThemeMode.dark);
      await shot('library-dark');
      unawaited(
        nav.push(
          MaterialPageRoute(builder: (_) => SettingsScreen(controller: c)),
        ),
      );
      await shot('settings-dark');
      nav.pop();
      await settle();
      await c.appearance(ThemeMode.light);
      debugPrint('LINQO_BRAND_TABLET_READY');
      final timer = Stopwatch()..start();
      while (MediaQuery.sizeOf(
            tester.element(find.byType(Scaffold).first),
          ).width <
          840) {
        if (timer.elapsed > const Duration(seconds: 60)) {
          throw TimeoutException('Waiting for host tablet resize');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await shot('tablet');
      debugPrint('LINQO_BRAND_PHONE_READY');
      timer.reset();
      while (MediaQuery.sizeOf(
            tester.element(find.byType(Scaffold).first),
          ).width >=
          840) {
        if (timer.elapsed > const Duration(seconds: 60)) {
          throw TimeoutException('Waiting for host phone restore');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      while (MediaQuery.textScalerOf(
            tester.element(find.byType(Scaffold).first),
          ).scale(10) <
          12.9) {
        if (timer.elapsed > const Duration(seconds: 60)) {
          throw TimeoutException('Waiting for large text setting');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await shot('large-text');
      expect(c.modelAvailable, isFalse);
      expect(c.processing, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
