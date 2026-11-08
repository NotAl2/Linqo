import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/services/account_identity.dart';
import 'package:linqo/services/cloud_services.dart';
import 'package:linqo/services/shop_purchase.dart';
import 'package:linqo/services/tiers.dart';

class _SwitchIdentity implements AccountIdentity {
  String? current = 'a';
  String next = 'b';
  @override
  String? get uid => current;
  @override
  String? get email => current == null ? null : '$current@example.com';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signIn() async {
    current = next;
  }

  @override
  Future<void> signOut() async {
    current = null;
  }

  @override
  Future<void> deleteAccount() async {
    current = null;
  }

  @override
  Future<String> idToken() async => 'unused';
  @override
  Future<Map<String, String>> driveHeaders({bool interactive = false}) async =>
      {};
}

void main() {
  sqfliteFfiInit();
  test(
    'switching Google accounts cannot open a purchase prepared for someone else',
    () async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final cloud = CloudServices(
        store,
        identity: _SwitchIdentity(),
        idle: () => false,
        refreshed: () async {},
      );
      try {
        final purchase = ShopPurchase(
          tier: AppTier.xl,
          code: 'LQ-${'A' * 32}',
          url: Uri.parse('https://buymeacoffee.com/notal2/e/101'),
          expires: DateTime.now().add(const Duration(days: 1)),
          accountId: 'different',
        );
        await expectLater(cloud.openPurchase(purchase), throwsStateError);
      } finally {
        cloud.dispose();
        await store.close();
      }
    },
  );
  test(
    'switching accounts requires Drive consent again even for a previously enabled account',
    () async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      await store.setPreference('last_cloud_account', 'a');
      await store.setPreference('drive_enabled_b', '1');
      final identity = _SwitchIdentity();
      final cloud = CloudServices(
        store,
        identity: identity,
        idle: () => false,
        refreshed: () async {},
      );
      try {
        await cloud.initialize();
        await cloud.signOut();
        await cloud.signIn();
        expect(identity.uid, 'b');
        expect(cloud.driveEnabled, false);
        expect(await store.preference('drive_enabled_b'), '0');
        await cloud.enableDrive(true);
        expect(cloud.driveEnabled, true);
        await cloud.signOut();
        identity.next = 'a';
        await cloud.signIn();
        expect(cloud.driveEnabled, false);
      } finally {
        cloud.dispose();
        await store.close();
      }
    },
  );
  test(
    'opting out persists locally even if the cloud is unavailable',
    () async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      await store.setPreference('contribute_a', '1');
      final cloud = CloudServices(
        store,
        identity: _SwitchIdentity(),
        idle: () => false,
        refreshed: () async {},
      );
      try {
        await cloud.initialize();
        expect(cloud.contributions, false);
        await expectLater(
          cloud.setContributions(true),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('paused in this preview'),
            ),
          ),
        );
        expect(
          await store.preference('contribute_a'),
          '1',
        ); // Rejected enabling changed no stored consent.
        await expectLater(cloud.setContributions(false), throwsStateError);
        expect(cloud.contributions, false);
        expect(await store.preference('contribute_a'), '0');
        expect(await store.preference('consent_pending_a'), '1');
      } finally {
        cloud.dispose();
        await store.close();
      }
    },
  );
}
