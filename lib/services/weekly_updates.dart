import 'dart:convert';
import '../app_version.dart';
import '../library/library_store.dart';
import 'update_checker.dart';

/// Foreground-only checks, with persisted cadence and a daily failure backoff.
class WeeklyUpdates {
  WeeklyUpdates(
    this.store, {
    DateTime Function()? now,
    Future<AvailableRelease?> Function(bool previews)? lookup,
  }) : now = now ?? DateTime.now,
       lookup =
           lookup ??
           ((previews) =>
               UpdateChecker().check(linqoVersion, previews: previews));
  final LibraryStore store;
  final DateTime Function() now;
  final Future<AvailableRelease?> Function(bool) lookup;
  bool _checking = false;
  static const enabledKey = 'updates_weekly_enabled';
  static const previewsKey = 'updates_include_previews';
  static const successKey = 'updates_last_success';
  static const attemptKey = 'updates_last_attempt';
  static const promptKey = 'updates_last_prompt';
  static const pendingKey = 'updates_pending_release';
  Future<bool> enabled() async => await store.preference(enabledKey) != 'false';
  Future<bool> previews() async =>
      await store.preference(previewsKey) != 'false';
  Future<void> setEnabled(bool value) =>
      store.setPreference(enabledKey, '$value');
  Future<void> setPreviews(bool value) async {
    await store.setPreference(previewsKey, '$value');
    await store.setPreference(successKey, '');
    await store.setPreference(attemptKey, '');
    await store.setPreference(pendingKey, '');
  }

  bool _recent(String? raw, Duration period) {
    final time = int.tryParse(raw ?? '');
    if (time == null) return false;
    final age = now().millisecondsSinceEpoch - time;
    return age >= 0 && age < period.inMilliseconds;
  }

  Future<void> manualAttempt() =>
      store.setPreference(attemptKey, '${now().millisecondsSinceEpoch}');
  Future<void> success(AvailableRelease? release, {bool manual = false}) async {
    await store.setPreference(successKey, '${now().millisecondsSinceEpoch}');
    await store.setPreference(
      pendingKey,
      release == null
          ? ''
          : jsonEncode({
              'version': release.version,
              'preview': release.preview,
            }),
    );
    if (manual) {
      await store.setPreference(promptKey, '${now().millisecondsSinceEpoch}');
    }
  }

  Future<void> poll() async {
    if (_checking) return;
    _checking = true;
    try {
      if (!await enabled() ||
          _recent(
            await store.preference(successKey),
            const Duration(days: 7),
          ) ||
          _recent(await store.preference(attemptKey), const Duration(days: 1))) {
        return;
      }
      await manualAttempt();
      await success(await lookup(await previews()));
    } catch (_) {
      // Offline failures stay quiet; a later foreground visit can retry tomorrow.
    } finally {
      _checking = false;
    }
  }

  Future<AvailableRelease?> pending() async {
    if (!await enabled() ||
        _recent(await store.preference(promptKey), const Duration(days: 7))) {
      return null;
    }
    try {
      final data = jsonDecode(await store.preference(pendingKey) ?? '') as Map;
      final version = data['version'];
      final installed = ReleaseVersion.parse(linqoVersion)!;
      final parsed = version is String ? ReleaseVersion.parse(version) : null;
      if (parsed == null ||
          parsed.compareTo(installed) <= 0 ||
          data['preview'] is! bool ||
          (data['preview'] == true && !await previews())) {
        return null;
      }
      return AvailableRelease(
        version as String,
        Uri.https('github.com', '/NotAl2/Linqo/releases/tag/$version'),
        data['preview'] as bool,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> claim(AvailableRelease release) async {
    final candidate = await pending();
    if (candidate?.version != release.version) return false;
    await store.setPreference(promptKey, '${now().millisecondsSinceEpoch}');
    return true;
  }
}
