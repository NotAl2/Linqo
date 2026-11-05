import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../app_version.dart';

/// Local opt-in codes and stack frames only: never exception messages or saves.
class Diagnostics extends ChangeNotifier {
  Diagnostics({this.directory});
  static final instance = Diagnostics();
  final Directory? directory;
  File? _storage;
  bool enabled = false;
  final List<Map<String, Object?>> _events = [];
  List<Map<String, Object?>> get events => List.unmodifiable(_events);
  Future<void> _writes = Future.value();
  Future<File> _file() async {
    final root =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/diagnostics',
        );
    await root.create(recursive: true);
    return _storage = File('${root.path}/events.json');
  }

  Future<void> initialize() async {
    try {
      final file = await _file();
      if (await file.exists() && await file.length() <= 256 * 1024) {
        final data = jsonDecode(await file.readAsString()) as Map;
        enabled = data['enabled'] == true;
        if (enabled) {
          for (final e in (data['events'] as List).take(100)) {
            if (e is Map<String, dynamic>) _events.add(e);
          }
        }
      }
      final fatal = File('${file.path}.crash');
      if (await fatal.exists()) {
        if (enabled && await fatal.length() <= 16 * 1024) {
          final event = jsonDecode(await fatal.readAsString());
          if (event is Map<String, dynamic> &&
              !_events.any(
                (e) => e['time'] == event['time'] && e['code'] == event['code'],
              )) {
            _events.add(event);
            if (_events.length > 100) _events.removeAt(0);
            await _save();
          }
        }
        await fatal.delete();
      }
    } catch (_) {
      /* Diagnostics must never prevent startup. */
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    if (!value) _events.clear();
    notifyListeners();
    await _save();
    if (!value) await _clearFatal();
  }

  Future<void> _clearFatal() async {
    if (_storage != null) {
      final fatal = File('${_storage!.path}.crash');
      try {
        if (await fatal.exists()) await fatal.delete();
      } catch (_) {
        /* Cleared on the next launch too. */
      }
    }
  }

  /// Write one small opt-in marker before normal uncaught-error handling.
  void recordFatal(String code, {required Object error, StackTrace? stack}) {
    if (!enabled) return;
    record(code, error: error, stack: stack, notify: false);
    try {
      if (_storage != null) {
        File(
          '${_storage!.path}.crash',
        ).writeAsStringSync(jsonEncode(_events.last), flush: true);
      }
    } catch (_) {
      /* Fatal logging is best effort, never recursive. */
    }
  }

  void record(
    String code, {
    Object? error,
    StackTrace? stack,
    bool notify = true,
  }) {
    if (!enabled) return;
    _events.add({
      'time': DateTime.now().toUtc().toIso8601String(),
      'version': linqoVersion,
      'code': RegExp(r'^[a-z0-9_.]{1,64}$').hasMatch(code) ? code : 'event',
      if (error != null) 'type': error.runtimeType.toString(),
      if (stack != null)
        'frames': stack
            .toString()
            .split('\n')
            .where((s) => s.contains('package:linqo/'))
            .take(8)
            .map(
              (s) => RegExp(
                r'package:linqo/[a-zA-Z0-9_/]+\.dart:\d+:\d+',
              ).firstMatch(s)?.group(0),
            )
            .whereType<String>()
            .toList(),
    });
    if (_events.length > 100) _events.removeAt(0);
    if (notify) notifyListeners();
    unawaited(_save());
  }

  String export() => const JsonEncoder.withIndent('  ').convert({
    'app': 'Linqo',
    'version': linqoVersion,
    'build': linqoBuild,
    'events': _events,
  });
  Future<void> clear() async {
    _events.clear();
    notifyListeners();
    await _save();
    await _clearFatal();
  }

  Future<void> _save() {
    final body = jsonEncode({'enabled': enabled, 'events': _events});
    _writes = _writes.then((_) async {
      try {
        final file = await _file();
        final temp = File('${file.path}.new');
        await temp.writeAsString(body, flush: true);
        await temp.rename(file.path);
      } catch (_) {
        /* Best effort; no recursive error logging. */
      }
    });
    return _writes;
  }
}
