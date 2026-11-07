import 'package:flutter/services.dart';

/// Android-only local bridge. No backend, token registration or saved text.
class LocalNotifications {
  static final instance = LocalNotifications();
  static const channel = MethodChannel('dev.linqo/notifications');
  Future<Map<String, dynamic>> status() async {
    try {
      return Map<String, dynamic>.from(
        await channel.invokeMapMethod<String, dynamic>('status') ?? {},
      );
    } catch (_) {
      return {'available': false, 'enabled': false, 'allowed': false};
    }
  }

  Future<bool> setEnabled(bool value) async {
    try {
      return await channel.invokeMethod<bool>('enable', {'enabled': value}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> settings() async {
    try {
      await channel.invokeMethod<void>('settings');
    } catch (_) {
      /* Optional. */
    }
  }

  Future<bool> show({
    int? saveId,
    bool failed = false,
    bool partial = false,
    bool test = false,
  }) async {
    try {
      return await channel.invokeMethod<bool>('show', {
            'saveId': saveId,
            'failed': failed,
            'partial': partial,
            'test': test,
          }) ??
          false;
    } catch (_) {
      /* Notifications must never turn a successful save into failure. */
      return false;
    }
  }

  Future<int?> takeOpenSave() async {
    try {
      return await channel.invokeMethod<int>('takeOpenSave');
    } catch (_) {
      return null;
    }
  }

  void listen(void Function() opened) =>
      channel.setMethodCallHandler((call) async {
        if (call.method == 'openSaveAvailable') opened();
      });
  void disposeListener() => channel.setMethodCallHandler(null);
}
