import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/services/weekly_updates.dart';
import 'package:linqo/services/update_checker.dart';
import 'package:linqo/ui/update_prompt.dart';
import 'package:linqo/theme.dart';

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late DateTime time;
  final release = AvailableRelease(
    'v0.8.4',
    Uri.parse('https://github.com/NotAl2/Linqo/releases/tag/v0.8.4'),
    true,
  );
  setUp(() async {
    time = DateTime.utc(2026, 11, 7);
    store = await LibraryStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() async {
    await store.close();
  });
  test('weekly cadence and snooze survive app restarts', () async {
    int calls = 0;
    WeeklyUpdates policy() => WeeklyUpdates(
      store,
      now: () => time,
      lookup: (_) async {
        calls++;
        return release;
      },
    );
    await policy().poll();
    expect(calls, 1);
    expect((await policy().pending())?.version, 'v0.8.4');
    expect(await policy().claim(release), true);
    expect(await policy().claim(release), false);
    time = time.add(const Duration(days: 6));
    await policy().poll();
    expect(calls, 1);
    expect(await policy().pending(), isNull);
    time = time.add(const Duration(days: 1));
    await policy().poll();
    expect(calls, 2);
    expect(await policy().claim(release), true);
  });
  test(
    'failed checks are quiet and retry the next day, not each resume',
    () async {
      int calls = 0;
      final p = WeeklyUpdates(
        store,
        now: () => time,
        lookup: (_) async {
          calls++;
          if (calls == 1) {
            throw StateError('Offline');
          }
          return release;
        },
      );
      await p.poll();
      expect(await p.pending(), isNull);
      time = time.add(const Duration(hours: 23));
      await p.poll();
      expect(calls, 1);
      time = time.add(const Duration(hours: 1));
      await p.poll();
      expect(calls, 2);
      expect(await p.pending(), isNotNull);
    },
  );
  test(
    'no popup for current versions, disabled checks or excluded previews',
    () async {
      int calls = 0;
      final p = WeeklyUpdates(
        store,
        now: () => time,
        lookup: (_) async {
          calls++;
          return null;
        },
      );
      await p.poll();
      expect(await p.pending(), isNull);
      await p.setEnabled(false);
      time = time.add(const Duration(days: 8));
      await p.poll();
      expect(calls, 1);
      await p.success(release);
      expect(await p.pending(), isNull);
      await p.setEnabled(true);
      await p.setPreviews(false);
      await p.success(release);
      expect(await p.pending(), isNull);
      await store.setPreference(
        WeeklyUpdates.pendingKey,
        jsonEncode({'version': 'v0.8.3', 'preview': false}),
      );
      expect(await p.pending(), isNull);
      await store.setPreference(
        WeeklyUpdates.pendingKey,
        jsonEncode({
          'version': 'https://untrusted.example/evil',
          'preview': false,
        }),
      );
      expect(await p.pending(), isNull);
    },
  );
  test(
    'manual checks suppress an immediate duplicate automatic prompt',
    () async {
      final p = WeeklyUpdates(store, now: () => time);
      await p.manualAttempt();
      await p.success(release, manual: true);
      expect(await p.pending(), isNull);
      time = time.add(const Duration(days: 7));
      expect(await p.pending(), isNotNull);
    },
  );
  test('overlapping foreground events perform one request', () async {
    final gate = Completer<AvailableRelease?>();
    int calls = 0;
    final p = WeeklyUpdates(
      store,
      now: () => time,
      lookup: (_) {
        calls++;
        return gate.future;
      },
    );
    final first = p.poll();
    while (calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await p.poll();
    expect(calls, 1);
    gate.complete(release);
    await first;
  });
  test('a clock rollback cannot suppress checks forever', () async {
    await store.setPreference(
      WeeklyUpdates.successKey,
      '${time.add(const Duration(days: 100)).millisecondsSinceEpoch}',
    );
    int calls = 0;
    final p = WeeklyUpdates(
      store,
      now: () => time,
      lookup: (_) async {
        calls++;
        return null;
      },
    );
    await p.poll();
    expect(calls, 1);
  });
  testWidgets('update popup fits enlarged text and Later closes it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: linqoTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: UpdatePrompt(release: release),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Linqo v0.8.4 is ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Linqo v0.8.4 is ready'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
