import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/domain/extraction_progress.dart';
import 'package:linqo/services/local_notifications.dart';
import 'package:linqo/ui/notification_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('part coverage only advances after a validated part boundary', () {
    final p = ExtractionProgress()..start('model:2', 2400);
    expect(p.fraction, isNull);
    p.boundary(1, 3, 100);
    expect(p.fraction, 0);
    expect(p.remainingSeconds(5000), isNull);
    p.boundary(2, 3, 10000);
    expect(p.fraction, closeTo(1 / 3, .001));
    expect(p.remainingSeconds(12000), 20);
    p.boundary(2, 3, 13000);
    expect(
      p.remainingSeconds(12000),
      20,
      reason:
          'Duplicate start/first-token events must not alter the timing sample.',
    );
    p.boundary(4, 3, 29000);
    expect(p.fraction, 1);
    expect(p.remainingSeconds(29000), isNull);
  });
  test('ETA uses comparable completed runs and never sticks at zero', () {
    final p = ExtractionProgress()
      ..start('small:2', 300)
      ..boundary(1, 1, 0);
    expect(p.remainingSeconds(2000), isNull);
    p.finish(17000, successful: true);
    p.start('small:2', 310);
    p.boundary(1, 1, 0);
    expect(p.remainingSeconds(3000), 15);
    expect(p.remainingSeconds(18000), isNull);
    p.start('different:2', 310);
    p.boundary(1, 1, 0);
    expect(p.remainingSeconds(3000), isNull);
    p.start('small:4', 310);
    p.boundary(1, 1, 0);
    expect(p.remainingSeconds(3000), isNull);
    p.start('small:2', 2000);
    p.boundary(1, 1, 0);
    expect(p.remainingSeconds(3000), isNull);
  });
  test('failed and cancelled runs do not train ETA', () {
    final p = ExtractionProgress()
      ..start('small:2', 300)
      ..boundary(1, 1, 0);
    p.finish(500, successful: false);
    p.start('small:2', 300);
    p.boundary(1, 1, 0);
    expect(p.remainingSeconds(1), isNull);
  });
  test('notifications stay optional if native bridge is unavailable', () async {
    expect((await LocalNotifications.instance.status())['available'], false);
    expect(await LocalNotifications.instance.setEnabled(true), false);
    await LocalNotifications.instance.show(saveId: 12);
    expect(await LocalNotifications.instance.takeOpenSave(), isNull);
  });
  testWidgets('notification permission is requested only after user action', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    bool enabled = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(LocalNotifications.channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'status') {
        return {'available': true, 'enabled': enabled, 'allowed': true};
      }
      if (call.method == 'enable') {
        enabled = (call.arguments as Map)['enabled'] == true;
        return enabled;
      }
      return null;
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(LocalNotifications.channel, null),
    );
    await tester.pumpWidget(
      const MaterialApp(home: NotificationSettingsScreen()),
    );
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'enable'), isEmpty);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    await tester.tap(find.text('Send test notification'));
    await tester.pumpAndSettle();
    final payload =
        calls.firstWhere((c) => c.method == 'show').arguments as Map;
    expect(payload['test'], true);
    expect(payload.keys, isNot(contains('title')));
    expect(payload.keys, isNot(contains('body')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('permission denial leaves alerts off and explains recovery', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(LocalNotifications.channel, (
      call,
    ) async {
      if (call.method == 'status') {
        return {'available': true, 'enabled': false, 'allowed': false};
      }
      if (call.method == 'enable') return false;
      return null;
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(LocalNotifications.channel, null),
    );
    await tester.pumpWidget(
      const MaterialApp(home: NotificationSettingsScreen()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    expect(
      find.text(
        'Notifications are blocked. You can allow them in Android notification settings.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
