import 'dart:async';
import 'package:linqo/services/entitlements.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/services/account_identity.dart';
import 'package:linqo/services/cloud_services.dart';
import 'package:linqo/services/checkout_purchase.dart';
import 'package:linqo/services/cloud_config.dart';
import 'package:linqo/services/tiers.dart';

class _SwitchIdentity implements AccountIdentity {
  String? current = 'a';
  String next = 'b';
  Completer<String>? pendingToken;
  int tokenCalls = 0;
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
  Future<String> idToken() async {
    tokenCalls++;
    return await pendingToken?.future ?? 'unused';
  }

  @override
  Future<Map<String, String>> driveHeaders({bool interactive = false}) async =>
      {};
}

class _SuccessfulAccountCheck extends CloudServices {
  _SuccessfulAccountCheck(
    super.store, {
    bool healthEnabled = true,
    this.grantPayments = false,
  }) : super(
         identity: _SwitchIdentity(),
         idle: () => true,
         refreshed: () async {},
         httpClient: MockClient((request) async {
           expect(request.url.path, '/health');
           return http.Response(
             '{"payments_enabled":$healthEnabled,"sandbox":false}',
             200,
           );
         }),
       );
  final bool grantPayments;
  int restores = 0;
  @override
  Future<void> restorePurchase() async {
    restores++;
    paymentsLive = grantPayments;
  }
}

class _WriteGateStore implements LibraryStore {
  _WriteGateStore(this.delegate);
  final LibraryStore delegate;
  final entered = Completer<void>(), resume = Completer<void>();
  @override
  Future<void> setPreference(String key, String value) async {
    if (key == 'entitlement_a') {
      entered.complete();
      await resume.future;
    }
    await delegate.setPreference(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureVerifier extends EntitlementVerifier {
  _FixtureVerifier() : super('synthetic-only');
  @override
  Future<AppTier> verify(String token, String uid) async =>
      uid == 'a' ? AppTier.xl : AppTier.xxl;
}

class _RaceCloud extends CloudServices {
  _RaceCloud(super.store, {required super.identity})
    : super(
        idle: () => false,
        refreshed: () async {},
        httpClient: MockClient(
          (_) async => http.Response(
            '{"token":"fixture","provider":"polar","payments_enabled":false,"sandbox":false}',
            200,
          ),
        ),
      );
  @override
  EntitlementVerifier get verifier => _FixtureVerifier();
}

class _ConsentCloud extends CloudServices {
  _ConsentCloud(super.store, AccountIdentity identity)
    : super(identity: identity, idle: () => false, refreshed: () async {});
  @override
  Future<void> restorePurchase() async {}
}

void main() {
  sqfliteFfiInit();
  test(
    'successful account checks clear only their own error and cannot enable checkout from health',
    () async {
      const failedCheck =
          'Account check could not finish. Cached purchases and local saves are available; export a backup through Files in Settings.';
      for (final previous in [failedCheck, 'Previous operation failed']) {
        final store = await LibraryStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfiNoIsolate,
        );
        final cloud = _SuccessfulAccountCheck(store);
        try {
          cloud.initialized = true;
          cloud.error = previous;
          await cloud.tick();
          expect(cloud.restores, 1);
          expect(cloud.error, previous == failedCheck ? '' : previous);
          expect(
            cloud.paymentsLive,
            isFalse,
            reason:
                'Only an owner-specific entitlement response may enable checkout.',
          );
        } finally {
          cloud.dispose();
          await store.close();
        }
      }
    },
    skip: !CloudConfig.backendReady,
  );
  test(
    'background checks preserve errors and do not lock account actions',
    () async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final cloud = CloudServices(
        store,
        identity: _SwitchIdentity(),
        idle: () => true,
        refreshed: () async {},
      );
      try {
        cloud.initialized = true;
        cloud.error = 'Previous operation failed';
        var sawBusy = false;
        cloud.addListener(() => sawBusy |= cloud.busy);
        await cloud.tick();
        expect(sawBusy, isFalse);
        expect(cloud.error, 'Previous operation failed');
      } finally {
        cloud.dispose();
        await store.close();
      }
    },
    skip: CloudConfig.backendReady,
  );

  test(
    'pending account checks allow user actions and reject overlapping ticks',
    () async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final identity = _SwitchIdentity()..pendingToken = Completer<String>();
      final cloud = CloudServices(
        store,
        identity: identity,
        idle: () => true,
        refreshed: () async {},
      );
      try {
        cloud.initialized = true;
        cloud.error = 'Previous operation failed';
        final ticking = cloud.tick();
        final waiting = Stopwatch()..start();
        while (identity.tokenCalls == 0) {
          if (waiting.elapsed > const Duration(seconds: 5)) {
            fail('tick() never requested an ID token');
          }
          await Future<void>.delayed(Duration.zero);
        }
        expect(cloud.busy, isFalse);
        expect(cloud.error, 'Previous operation failed');
        await cloud.tick();
        expect(identity.tokenCalls, 1);
        var ran = false;
        await cloud.run(() async {
          ran = true;
        });
        expect(ran, isTrue);
        identity.pendingToken!.completeError(StateError('offline'));
        await ticking;
        expect(cloud.error, contains('Account check could not finish'));
        await cloud.tick();
        expect(identity.tokenCalls, 1);
      } finally {
        cloud.dispose();
        await store.close();
      }
    },
    skip: !CloudConfig.backendReady,
  );
  test(
    'health disable wins over an account-specific checkout enable',
    () async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final cloud = _SuccessfulAccountCheck(
        store,
        healthEnabled: false,
        grantPayments: true,
      );
      try {
        cloud.initialized = true;
        await cloud.tick();
        expect(cloud.restores, 1);
        expect(cloud.paymentsLive, false);
      } finally {
        cloud.dispose();
        await store.close();
      }
    },
    skip: !CloudConfig.backendReady,
  );
  test(
    'a delayed entitlement write cannot replace the next account tier',
    () async {
      final store = await LibraryStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final gate = _WriteGateStore(store), identity = _SwitchIdentity();
      final cloud = _RaceCloud(gate, identity: identity);
      try {
        final old = cloud.restorePurchase();
        await gate.entered.future;
        identity.current = 'b';
        await cloud.restorePurchase();
        expect(cloud.tier, AppTier.xxl);
        gate.resume.complete();
        await old;
        expect(cloud.tier, AppTier.xxl);
      } finally {
        cloud.dispose();
        await store.close();
      }
    },
    skip: !CloudConfig.backendReady || CloudConfig.entitlementKey.isEmpty,
  );
  test(
    'configured quotas apply before account initialization completes',
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
        expect(cloud.initialized, false);
        expect(cloud.limits.enforced, CloudConfig.limitsEnabled);
        if (CloudConfig.limitsEnabled) {
          expect(cloud.limits.saves, 100);
          expect(cloud.limits.collections, 5);
          expect(cloud.limits.customModels, false);
        }
      } finally {
        cloud.dispose();
        await store.close();
      }
    },
  );
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
        final purchase = CheckoutPurchase(
          tier: AppTier.xl,
          orderId: 'lq_p_12345678-1234-4123-8123-123456789abc',
          sandbox: false,
          url: Uri.parse('https://linqo.example/checkout/${'a' * 64}'),
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
      final cloud = _ConsentCloud(store, identity);
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
        httpClient: MockClient(
          (_) async => throw StateError('Synthetic offline test'),
        ),
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
