import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/services/entitlements.dart';
import 'package:linqo/services/tiers.dart';

void main() {
  sqfliteFfiInit();
  late Directory work;
  late LibraryStore store;
  setUp(() async {
    work = await Directory.systemTemp.createTemp('linqo-tiers-');
    store = await LibraryStore.open(
      path: '${work.path}/library.db',
      factory: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() async {
    await store.close();
    await work.delete(recursive: true);
  });
  for (final tier in [AppTier.free, AppTier.xl]) {
    test(
      '${tier.name} enforces current save and collection limits atomically, preserving edits and receipts',
      () async {
        final policy = LibraryLimits(tier, enforced: true);
        store.limits = () => policy;
        final first = await store.save(
          SaveDraft(title: 'First', shareId: 'receipt'),
        );
        for (var i = 1; i < policy.saves!; i++) {
          await store.save(SaveDraft(title: 'Save $i'));
        }
        expect(await store.count(), policy.saves);
        await expectLater(
          store.save(SaveDraft(title: 'Too many')),
          throwsA(isA<TierLimitException>()),
        );
        expect(
          await store.save(SaveDraft(title: 'Replay', shareId: 'receipt')),
          first,
        );
        await store.save(SaveDraft(title: 'Edited'), id: first);
        await store.remove(first);
        await store.save(SaveDraft(title: 'Replacement'));
        for (var i = 0; i < policy.collections!; i++) {
          await store.saveCollection('Collection $i', 0);
        }
        await expectLater(
          store.saveCollection('Extra', 0),
          throwsA(isA<TierLimitException>()),
        );
        final collection = (await store.collections()).first;
        await store.saveCollection('Renamed', 0, id: collection.id);
        await store.deleteCollection(collection.id);
        await store.saveCollection('Replacement', 0);
      },
    );
  }
  test(
    'XXL and unactivated previews have no product quota; downgrading preserves existing saves',
    () async {
      var policy = const LibraryLimits(AppTier.free, enforced: false);
      store.limits = () => policy;
      for (var i = 0; i < 151; i++) {
        await store.save(SaveDraft(title: 'Existing $i'));
      }
      policy = const LibraryLimits(AppTier.free, enforced: true);
      expect(await store.count(), 151);
      await expectLater(
        store.save(SaveDraft(title: 'Extra')),
        throwsA(isA<TierLimitException>()),
      );
      policy = const LibraryLimits(AppTier.xxl, enforced: true);
      await store.save(SaveDraft(title: 'XXL extra'));
      expect(policy.customModels, true);
      expect(
        const LibraryLimits(AppTier.xl, enforced: true).customModels,
        false,
      );
      expect(
        const LibraryLimits(AppTier.free, enforced: true).customModels,
        false,
      );
    },
  );
  test(
    'library revision changes for edits, memberships, deletion, and extraction metadata but not account preferences',
    () async {
      final before = await store.preference('library_revision');
      await store.setPreference('cloud_preference', '1');
      expect(await store.preference('library_revision'), before);
      final id = await store.save(SaveDraft(title: 'A'));
      final one = int.parse((await store.preference('library_revision'))!);
      await store.save(SaveDraft(title: 'B'), id: id);
      expect(
        int.parse((await store.preference('library_revision'))!),
        greaterThan(one),
      );
      final two = await store.preference('library_revision');
      await store.remove(id);
      expect(await store.preference('library_revision'), isNot(two));
    },
  );
  test(
    'signed entitlement verifies ownership, rejects forgery and restores from a fresh offline store',
    () async {
      final algorithm = Ed25519(), key = await Ed25519().newKeyPair();
      final public = await key.extractPublicKey();
      String enc(List<int> bytes) =>
          base64Url.encode(bytes).replaceAll('=', '');
      final verifier = EntitlementVerifier(enc(public.bytes));
      final body =
          '${enc(utf8.encode(jsonEncode({'alg': 'EdDSA', 'kid': 'v1'})))}.${enc(utf8.encode(jsonEncode({'sub': 'alice', 'aud': 'dev.linqo.linqo', 'iss': 'linqo-cloud', 'version': 1, 'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'tier': 'xxl'})))}';
      final sig = await algorithm.sign(utf8.encode(body), keyPair: key);
      final token = '$body.${enc(sig.bytes)}';
      expect(await verifier.verify(token, 'alice'), AppTier.xxl);
      await expectLater(verifier.verify(token, 'bob'), throwsFormatException);
      await expectLater(
        verifier.verify('$body.${enc(List.filled(64, 0))}', 'alice'),
        throwsFormatException,
      );
      await store.setPreference('entitlement_alice', token);
      expect(await verifier.restore(store, 'alice'), AppTier.xxl);
      expect(await verifier.restore(store, 'bob'), AppTier.free);
    },
  );
}
