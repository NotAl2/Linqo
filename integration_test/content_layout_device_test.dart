import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/main.dart';
import 'package:linqo/ui/save_detail.dart';
import 'package:linqo/ui/welcome_screen.dart';
import 'package:linqo/theme.dart';
import 'phone_english_reel_test.dart' show protectedState;

const samples = [
  (
    '[Test] Sunday tomato pasta',
    SaveKind.link,
    'Sunday tomato pasta\nServes 2\nIngredients:\n200 g pasta\n2 tomatoes\n1 tbsp olive oil\nMethod:\nBoil pasta for 10 minutes.\nChop the tomatoes.\nToss tomatoes with olive oil and mix with the pasta.',
  ),
  (
    '[Test] Choosing a local AI model',
    SaveKind.link,
    'Choosing a local AI model\nAdd MakeUseOf on Google\nAdd as Preferred Source\nSmall quantized models use less memory than full precision models.\nA local model runs on your hardware and does not send prompts to a server.\nChoose a model that fits your available memory.\nYadullah Abidi is a Computer Science graduate from the University of Delhi.',
  ),
  (
    '[Test] Set up a backup',
    SaveKind.link,
    'Setup guide\nOpen Linqo Settings.\nSelect Export saves.\nChoose a folder for the ZIP backup.\nKeep the backup file in a safe place.',
  ),
  (
    '[Test] National Gallery visit',
    SaveKind.place,
    'Place: National Gallery\nAddress: Trafalgar Square, London\nVisit National Gallery to explore the paintings.\nCheck the official website for current opening hours.',
  ),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'typed grounded extraction, native demos and authorized sample saves',
    (tester) async {
      final normalPath = '${await getDatabasesPath()}/linqo-library.db';
      final before = await protectedState(normalPath);
      final original = await openDatabase(
        normalPath,
        readOnly: true,
        singleInstance: false,
      );
      final oldRows = (await original.query('saves', orderBy: 'id'))
          .where(
            (row) => !(row['source_share_id'] as String? ?? '').startsWith(
              'linqo-v082-sample-',
            ),
          )
          .toList();
      final oldPreferences = await original.query(
        'preferences',
        orderBy: 'key',
      );
      await original.close();
      final qaPath = '${await getDatabasesPath()}/linqo-content-layout-qa.db';
      await deleteDatabase(qaPath);
      final store = await LibraryStore.open(path: qaPath);
      final c = LibraryController(store);
      await c.initialize(restoreModel: false);
      await c.lab.initialize();
      expect(
        c.modelAvailable,
        isTrue,
        reason:
            'Use the already installed model, never download automatically.',
      );
      final runs = <Map<String, Object?>>[];
      binding.reportData = {
        'normal_before': before,
        'runs': runs,
        'threads': c.lab.threads,
      };
      Future<void> settle() async {
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
      }

      Future<void> waitUntil(bool Function() ready) async {
        final watch = Stopwatch()..start();
        while (!ready()) {
          if (watch.elapsed > const Duration(minutes: 4)) {
            throw TimeoutException('Extraction timed out');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      final extracted = <SavedItem>[];
      try {
        await tester.pumpWidget(
          LinqoApp(
            controller: c,
            enableSharing: false,
            enableSupportPrompts: false,
            enableOnboarding: false,
          ),
        );
        await settle();
        await binding.convertFlutterSurfaceToImage();
        for (final sample in samples) {
          final id = await store.save(
            SaveDraft(
              title: sample.$1,
              kind: sample.$2,
              body: sample.$3,
              automaticContent: false,
              autoExtract: false,
            ),
          );
          final watch = Stopwatch()..start();
          await c.extract((await store.get(id))!);
          await waitUntil(() => !c.processing);
          final item = (await store.get(id))!;
          expect(item.error, isEmpty);
          expect(item.extraction, isNotNull);
          final type = item.extraction!.type;
          final expected = sample.$1.contains('pasta')
              ? 'recipe'
              : sample.$1.contains('backup')
              ? 'tutorial'
              : sample.$2 == SaveKind.place
              ? 'place'
              : 'general';
          expect(type, expected);
          if (type == 'recipe') {
            expect(item.extraction!.recipe!.ingredients.length, 3);
            expect(item.extraction!.recipe!.steps.length, 3);
            expect(item.extraction!.recipe!.servings, 'Serves 2');
          }
          expect(
            item.extraction!.facts.any(
              (f) => f.value.contains('Preferred Source'),
            ),
            isFalse,
          );
          final query = Stopwatch()..start();
          await store.query(query: 'test');
          runs.add({
            'title': sample.$1,
            'type': type,
            'milliseconds': watch.elapsedMilliseconds,
            'query_ms': query.elapsedMilliseconds,
            'ingredients': item.extraction!.recipe?.ingredients.length,
            'steps': item.extraction!.recipe?.steps.length,
          });
          extracted.add(item);
        }
        // Exercise native reading views without per-fact dropdowns or raw body.
        for (final item in extracted.take(2)) {
          await tester.pumpWidget(
            MaterialApp(
              theme: linqoTheme(Brightness.dark),
              home: SaveDetail(controller: c, id: item.id),
            ),
          );
          await settle();
          expect(find.text('Content for extraction'), findsNothing);
          expect(find.byType(ExpansionTile), findsNothing);
          await tester.ensureVisible(
            find.text(
              item.extraction!.type == 'recipe'
                  ? 'Ingredients'
                  : 'Key takeaways',
            ),
          );
          await settle();
          await binding.takeScreenshot(
            item.extraction!.type == 'recipe' ? 'v082-recipe' : 'v082-article',
          );
        }
        for (final index in [0, 2]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: linqoTheme(Brightness.light),
              home: WelcomeScreen(
                key: ValueKey(index),
                controller: c,
                onDone: (_) async {},
              ),
            ),
          );
          await settle();
          await tester.tap(find.text('Take a quick look'));
          await settle();
          if (index == 2) {
            await tester.tap(find.text('Next'));
            await settle();
            await tester.tap(find.text('Next'));
            await settle();
          }
          await binding.takeScreenshot('v082-demo-$index');
          expect(tester.takeException(), isNull);
        }
        // Seed only these explicit, synthetic items into the real library.
        final normal = await LibraryStore.open();
        final seeded = <int>[];
        try {
          for (final entry in extracted.indexed) {
            final item = entry.$2;
            final id = await normal.save(
              SaveDraft(
                title: item.title,
                body: item.body,
                kind: item.kind,
                notes: 'Synthetic Linqo test sample. Safe to delete.',
                automaticContent: false,
                autoExtract: false,
                shareId: 'linqo-v082-sample-${entry.$1}',
              ),
            );
            await normal.extraction(
              id,
              item.body,
              item.extractionJson,
              item.extraction!,
              evidenceSource: item.extractedFrom,
            );
            seeded.add(id);
          }
          final afterRows = await normal.db.query(
            'saves',
            where: 'id NOT IN (${seeded.map((_) => '?').join(',')})',
            whereArgs: seeded,
            orderBy: 'id',
          );
          expect(
            sha256.convert(utf8.encode(jsonEncode(afterRows))).toString(),
            sha256.convert(utf8.encode(jsonEncode(oldRows))).toString(),
            reason: 'Existing saves must be byte-for-byte unchanged.',
          );
          final currentPreferences = await normal.db.query(
            'preferences',
            orderBy: 'key',
          );
          expect(
            currentPreferences
                .where((row) => row['key'] != 'support_save_count_v1')
                .toList(),
            oldPreferences
                .where((row) => row['key'] != 'support_save_count_v1')
                .toList(),
          );
        } finally {
          await normal.close();
        }
        final after = await protectedState(normalPath);
        for (final key in [
          'collections',
          'memberships',
          'model_selection_sha256',
        ]) {
          expect(after[key], before[key]);
        }
        binding.reportData!.addAll({
          'normal_after': after,
          'seeded_ids': seeded,
          'existing_data_preserved': true,
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        await c.background();
        c.dispose();
        await store.close();
        await deleteDatabase(qaPath);
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
