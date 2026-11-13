import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/services/account_identity.dart';
import 'package:linqo/services/cloud_services.dart';
import 'package:linqo/ui/account_screen.dart';

class _Identity implements AccountIdentity {
  @override
  String? uid = 'signed-in-test';
  @override
  String? get email => 'test@example.com';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {
    uid = null;
  }

  @override
  Future<void> deleteAccount() async {
    uid = null;
  }

  @override
  Future<String> idToken() async => 'unused';
  @override
  Future<Map<String, String>> driveHeaders({bool interactive = false}) async =>
      {};
}

void main() {
  sqfliteFfiInit();
  testWidgets(
    'bottom sign-out requires confirmation and preserves local settings',
    (tester) async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final controller = LibraryController(store);
      await controller.initialize(restoreModel: false);
      controller.cloud!.dispose();
      final identity = _Identity();
      final cloud = CloudServices(
        store,
        identity: identity,
        idle: () => false,
        refreshed: () async {},
      );
      controller.cloud = cloud;
      cloud.initialized = true;
      await store.setPreference('theme', 'dark');
      await tester.pumpWidget(
        MaterialApp(
          theme: linqoTheme(Brightness.dark),
          home: AccountScreen(controller: controller),
        ),
      );
      final button = find.text('Sign out · keep local saves');
      await tester.scrollUntilVisible(
        button,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Sign out of Linqo?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(identity.uid, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(identity.uid, isNull);
      expect(await store.preference('theme'), 'dark');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await store.close();
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'account settings remain usable at large text in ${brightness.name}',
      (tester) async {
        String? launched;
        const emailChannel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          emailChannel,
          (call) async {
            if (call.method == 'launch') {
              launched = (call.arguments as Map)['url'] as String;
            }
            return true;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            emailChannel,
            null,
          ),
        );
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await LibraryStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfiNoIsolate,
        );
        final controller = LibraryController(store);
        await controller.initialize(restoreModel: false);
        await tester.pumpWidget(
          MaterialApp(
            theme: linqoTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.5),
              ),
              child: AccountScreen(controller: controller),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Account & backup'), findsOneWidget);
        expect(
          find.text(
            'Google sign-in is not configured in this preview. Your local library and ZIP backups still work.',
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Email for full prebuild access'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Email for full prebuild access'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Email for full prebuild access'));
        await tester.pumpAndSettle();
        expect(
          launched,
          isNull,
          reason: 'Access requests must include the verified account code.',
        );
        expect(
          find.textContaining('Sign in with Google at the top'),
          findsOneWidget,
        );
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
            .removeCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Email the developer'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Email the developer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Email the developer'));
        await tester.pumpAndSettle();
        expect(
          launched,
          isNotNull,
          reason: 'An actual launch call is required.',
        );
        final email = Uri.parse(launched!);
        expect(email.scheme, 'mailto');
        expect(email.path, 'aryandurgude123@gmail.com');
        expect(email.query, contains('subject=Linqo%20support'));
        expect(email.query, isNot(contains('+')));
        expect(email.queryParameters['body'], isNull);
        await tester.scrollUntilVisible(
          find.text('Connect earlier Drive backups'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Contribute automatic samples'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Switch), findsWidgets);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await store.close();
      },
    );
  }
}
