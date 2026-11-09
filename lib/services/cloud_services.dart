import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../library/library_backup.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import 'account_identity.dart';
import 'cloud_api.dart';
import 'cloud_config.dart';
import 'contribution_sample.dart';
import 'drive_backup.dart';
import 'entitlements.dart';
import 'tiers.dart';
import 'checkout_purchase.dart';

class CloudServices extends ChangeNotifier {
  CloudServices(
    this.store, {
    AccountIdentity? identity,
    required this.idle,
    required this.refreshed,
    this.attachments,
  }) : identity = identity ?? GoogleAccountIdentity() {
    api = CloudApi(this.identity);
    drive = DriveBackup(this.identity);
  }
  final LibraryStore store;
  final AccountIdentity identity;
  final bool Function() idle;
  final Future<void> Function() refreshed;
  final Directory? attachments;
  late final CloudApi api;
  late final DriveBackup drive;
  final verifier = EntitlementVerifier(CloudConfig.entitlementKey);
  AppTier _tier = AppTier.free;
  String? _tierOwner;
  AppTier get tier => identity.uid == _tierOwner ? _tier : AppTier.free;
  LibraryLimits get limits =>
      LibraryLimits(tier, enforced: CloudConfig.limitsEnabled && initialized);
  bool busy = false,
      initialized = false,
      driveEnabled = false,
      contributions = false,
      paymentsLive = false;
  bool foreground = true, _disposed = false;
  bool sandboxCheckout = true;
  String? _checkoutRequestId, _checkoutAccount, _checkoutPhone;
  AppTier? _checkoutProduct;
  String status = '', error = '';
  String? lastBackup;
  Timer? _timer;
  DateTime? _lastRefresh;
  DateTime? _nextAccountCheck;
  Map<String, dynamic>? _sample;
  String? _sampleOwner;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await identity.initialize();
      await _loadAccount();
    } catch (_) {
      error =
          'Account services could not connect. Your local library is available.';
    }
    initialized = true;
    _changed();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(tick()),
    );
    unawaited(tick());
  }

  Future<void> _loadAccount() async {
    final uid = identity.uid;
    _tier = AppTier.free;
    _tierOwner = uid;
    driveEnabled = false;
    contributions = false;
    _sample = null;
    _nextAccountCheck = null;
    paymentsLive = false;
    _checkoutRequestId = _checkoutAccount = _checkoutPhone = null;
    _checkoutProduct = null;
    if (uid != null) {
      final previous = await store.preference('last_cloud_account');
      if (previous != null && previous != uid) {
        // A returning account must not inherit consent to upload the current
        // device library after another account has used this installation.
        await store.setPreference('drive_enabled_$uid', '0');
      }
      await store.setPreference('last_cloud_account', uid);
      _tier = await verifier.restore(store, uid);
      driveEnabled = await store.preference('drive_enabled_$uid') == '1';
      contributions =
          CloudConfig.contributionsEnabled &&
          await store.preference('contribute_$uid') == '1';
      lastBackup = await store.preference('drive_success_$uid');
    } else {
      lastBackup = null;
    }
  }

  Future<void> signIn() => run(() async {
    await identity.signIn();
    await _loadAccount();
    await restorePurchase();
  });
  Future<void> signOut() => run(() async {
    // Stop contributions locally before any network work; cached tier never crosses accounts.
    contributions = false;
    driveEnabled = false;
    _sample = null;
    await identity.signOut();
    await _loadAccount();
  });
  Future<void> run(Future<void> Function() action) async {
    if (busy) {
      throw StateError('Wait for the current cloud operation to finish.');
    }
    busy = true;
    error = '';
    _changed();
    try {
      await action();
    } catch (e) {
      error = e is StateError
          ? e.message.toString()
          : 'The operation could not finish. Your local saves are safe.';
      rethrow;
    } finally {
      busy = false;
      status = '';
      _changed();
    }
  }

  Future<void> restorePurchase() async {
    final uid = identity.uid;
    if (uid == null ||
        !CloudConfig.backendReady ||
        CloudConfig.entitlementKey.isEmpty) {
      return;
    }
    final response = await api.call('/entitlement');
    final token = response['token'] as String;
    final restored = await verifier.verify(token, uid);
    if (identity.uid != uid) return;
    await store.setPreference('entitlement_$uid', token);
    _tier = restored;
    _tierOwner = uid;
    paymentsLive = response['payments_enabled'] == true;
    sandboxCheckout = response['sandbox'] != false;
    _lastRefresh = DateTime.now();
    _changed();
  }

  Future<CheckoutPurchase> preparePurchase(
    AppTier product,
    String phone,
  ) async {
    CheckoutPurchase? purchase;
    await run(() async {
      final uid = identity.uid;
      if (uid == null) {
        throw StateError('Sign in with Google to purchase and restore a tier.');
      }
      if (!CloudConfig.checkoutEnabled || !paymentsLive) {
        throw StateError(
          'Checkout is not live in this preview. No payment was taken.',
        );
      }
      if (_checkoutAccount != uid ||
          _checkoutProduct != product ||
          _checkoutPhone != phone) {
        _checkoutRequestId = newPurchaseRequestId();
        _checkoutAccount = uid;
        _checkoutProduct = product;
        _checkoutPhone = phone;
      }
      Map<String, dynamic> response;
      try {
        response = await api.call(
          '/checkout/start',
          method: 'POST',
          body: {
            'tier': product.name,
            'phone': phone,
            'request_id': _checkoutRequestId,
          },
        );
      } on CloudRequestError catch (error) {
        if (error.code == 'purchase_request_expired') {
          _checkoutRequestId = _checkoutPhone = null;
        }
        rethrow;
      }
      if (identity.uid != uid) {
        throw StateError('Account changed. Start the purchase again.');
      }
      purchase = CheckoutPurchase.parse(
        response,
        product,
        accountId: uid,
        checkoutOrigin: CloudConfig.backend,
      );
    });
    return purchase!;
  }

  Future<void> openPurchase(CheckoutPurchase purchase) async {
    if (identity.uid != purchase.accountId ||
        purchase.expires.isBefore(DateTime.now())) {
      throw StateError('Sign in and start the purchase again.');
    }
    if (!await launchUrl(purchase.url, mode: LaunchMode.externalApplication)) {
      throw StateError('Checkout could not open.');
    }
    _lastRefresh = null;
    _nextAccountCheck = null;
  }

  Future<void> enableDrive(bool enabled) => run(() async {
    final uid = identity.uid;
    if (uid == null) throw StateError('Sign in to connect Drive.');
    if (enabled) await identity.driveHeaders(interactive: true);
    if (identity.uid != uid) return;
    await store.setPreference('drive_enabled_$uid', enabled ? '1' : '0');
    driveEnabled = enabled;
  });
  Future<void> setContributions(bool enabled) async {
    if (enabled && !CloudConfig.contributionsEnabled) {
      throw StateError(
        'Contributions are paused in this preview. No source samples will be uploaded.',
      );
    }
    final uid = identity.uid;
    if (uid == null) {
      throw StateError('Sign in before changing contribution consent.');
    }
    if (!enabled) {
      contributions = false;
      _sample = null;
      await store.setPreference('contribute_$uid', '0');
      await store.setPreference('consent_pending_$uid', '1');
      _changed();
    }
    await run(() async {
      await api.call(
        '/consent',
        method: 'PUT',
        body: {'enabled': enabled, 'version': 1},
      );
      if (identity.uid != uid) return;
      await store.setPreference('contribute_$uid', enabled ? '1' : '0');
      await store.setPreference('consent_pending_$uid', '0');
      contributions = enabled;
    });
  }

  void consider(
    SavedItem item,
    String source,
    String output,
    String category,
    String model,
  ) {
    if (!CloudConfig.contributionsEnabled ||
        !contributions ||
        identity.uid == null) {
      return;
    }
    _sample = ContributionSample.fromSave(
      item,
      source,
      output,
      category,
      model,
    );
    _sampleOwner = identity.uid;
  }

  Future<bool> _wifi() async => (await Connectivity().checkConnectivity())
      .contains(ConnectivityResult.wifi);
  Future<void> tick() async {
    if (_disposed ||
        !initialized ||
        busy ||
        !foreground ||
        !idle() ||
        identity.uid == null) {
      return;
    }
    try {
      await run(() async {
        final uid = identity.uid!;
        if (CloudConfig.backendReady) {
          try {
            if (await store.preference('consent_pending_$uid') == '1') {
              await api.call(
                '/consent',
                method: 'PUT',
                body: {'enabled': false, 'version': 1},
              );
              await store.setPreference('consent_pending_$uid', '0');
            }
            if ((_nextAccountCheck == null ||
                    DateTime.now().isAfter(_nextAccountCheck!)) &&
                (_lastRefresh == null ||
                    DateTime.now().difference(_lastRefresh!) >
                        const Duration(hours: 1))) {
              _nextAccountCheck = DateTime.now().add(
                const Duration(minutes: 15),
              );
              final health = await api.call('/health');
              paymentsLive = health['payments_enabled'] == true;
              sandboxCheckout = health['sandbox'] != false;
              await restorePurchase();
              _nextAccountCheck = DateTime.now().add(const Duration(hours: 1));
            }
          } catch (_) {
            error =
                'Account check could not finish. Cached purchases and local saves are available; Drive backup can still run.';
          }
        }
        if ((!driveEnabled && _sample == null) ||
            !await _wifi() ||
            !idle() ||
            !foreground ||
            identity.uid != uid) {
          return;
        }
        if (CloudConfig.contributionsEnabled &&
            _sample != null &&
            contributions &&
            _sampleOwner == uid &&
            CloudConfig.backendReady) {
          final sample = _sample!;
          _sample = null;
          try {
            await api.call('/samples', method: 'POST', body: sample);
          } catch (_) {
            error =
                'The optional contribution was not sent. Your library is unaffected.';
          }
        }
        final then = DateTime.tryParse(lastBackup ?? '');
        final attempt = DateTime.tryParse(
          await store.preference('drive_attempt_$uid') ?? '',
        );
        final revision = await store.preference('library_revision') ?? '0';
        if (driveEnabled &&
            (attempt == null ||
                DateTime.now().difference(attempt) >
                    const Duration(hours: 1)) &&
            (then == null ||
                DateTime.now().difference(then) > const Duration(days: 1)) &&
            revision != await store.preference('drive_revision_$uid')) {
          await _backup(uid, revision);
        }
      });
    } catch (_) {
      /* Display the error in Settings; never break local work or retry in a tight loop. */
    }
  }

  Future<LibraryBackup> _backupStore() async => LibraryBackup(
    store,
    attachments ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/attachments',
        ),
  );
  Future<void> backupNow() => run(() async {
    if (!driveEnabled || identity.uid == null) {
      throw StateError('Enable Drive backup first.');
    }
    await _backup(
      identity.uid!,
      await store.preference('library_revision') ?? '0',
    );
  });
  Future<void> _backup(String uid, String revision) async {
    if (!idle()) {
      throw StateError(
        'Wait for extraction and downloads to finish before backing up.',
      );
    }
    await store.setPreference(
      'drive_attempt_$uid',
      DateTime.now().toUtc().toIso8601String(),
    );
    final work = await (await getTemporaryDirectory()).createTemp(
      'linqo-drive-',
    );
    bool allowed() =>
        !_disposed &&
        foreground &&
        idle() &&
        driveEnabled &&
        identity.uid == uid;
    try {
      status = 'Preparing your Drive backup…';
      _changed();
      final file = await (await _backupStore()).export(work);
      if (!allowed()) {
        throw StateError('Backup paused. Try again when Linqo is idle.');
      }
      var device = await store.preference('drive_device');
      device ??= LibraryBackup.newKey();
      await store.setPreference('drive_device', device);
      status = 'Uploading and verifying…';
      _changed();
      await drive.upload(file, device, allowed);
      if (!allowed()) return;
      lastBackup = DateTime.now().toUtc().toIso8601String();
      await store.setPreference('drive_success_$uid', lastBackup!);
      await store.setPreference('drive_revision_$uid', revision);
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<void> restoreSnapshot(DriveSnapshot snapshot) => run(() async {
    if (!idle()) {
      throw StateError(
        'Wait for extraction and downloads to finish before restoring.',
      );
    }
    final uid = identity.uid;
    final work = await (await getTemporaryDirectory()).createTemp(
      'linqo-restore-',
    );
    try {
      status = 'Downloading and checking your backup…';
      _changed();
      final file = await drive.download(
        snapshot,
        work,
        allowed: () =>
            !_disposed && uid == identity.uid && foreground && idle(),
      );
      if (uid != identity.uid || !foreground || !idle()) {
        throw StateError(
          'Restore paused before changing the library. Try again when idle.',
        );
      }
      await (await _backupStore()).import(file, work);
      await refreshed();
    } finally {
      await work.delete(recursive: true);
    }
  });
  Future<void> deleteAccount() => run(() async {
    final uid = identity.uid;
    if (uid == null) return;
    contributions = false;
    driveEnabled = false;
    _sample = null;
    await store.setPreference('contribute_$uid', '0');
    await store.setPreference('drive_enabled_$uid', '0');
    await api.call('/account', method: 'DELETE');
    await identity.deleteAccount();
    await _loadAccount();
  });
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    api.close();
    drive.close();
    super.dispose();
  }
}
