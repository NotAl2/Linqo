import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';

/// Local-only reminder state. A save counter is updated in the same transaction
/// as a new save, so retries, edits and failed saves never advance reminders.
class SupportPromptPolicy {
  SupportPromptPolicy(this.db, {DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure();
  final Database db;
  final DateTime Function() _now;
  final Random _random;
  static const countKey = 'support_save_count_v1';
  static const stateKey = 'support_prompt_v1';

  static Future<void> recordSave(DatabaseExecutor tx) async {
    final rows = await tx.query(
      'preferences',
      where: 'key=?',
      whereArgs: [countKey],
    );
    final count = rows.isEmpty
        ? 0
        : int.tryParse(rows.single['value'] as String) ?? 0;
    await tx.insert('preferences', {
      'key': countKey,
      'value': '${max(0, count) + 1}',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>> _state(DatabaseExecutor tx) async {
    final rows = await tx.query(
      'preferences',
      where: 'key=?',
      whereArgs: [stateKey],
    );
    if (rows.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(
        jsonDecode(rows.single['value'] as String) as Map,
      );
    } catch (_) {
      return {'opted_out': true};
    } // A damaged preference should not nag.
  }

  Future<bool> optedOut() async => (await _state(db))['opted_out'] == true;
  Future<void> setOptedOut(bool value) => db.transaction((tx) async {
    final state = await _state(tx);
    await tx.insert('preferences', {
      'key': stateKey,
      'value': jsonEncode({...state, 'opted_out': value}),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  /// Claim before presenting. Dismissal/back also starts the cooldown; opening
  /// the external support page never creates a second reminder on return.
  Future<bool> claim() => db.transaction((tx) async {
    final state = await _state(tx);
    if (state['opted_out'] == true) return false;
    final rows = await tx.query(
      'preferences',
      where: 'key=?',
      whereArgs: [countKey],
    );
    final count = rows.isEmpty
        ? 0
        : int.tryParse(rows.single['value'] as String) ?? 0;
    final next = state['next_count'] is int ? state['next_count'] as int : 1;
    final notBefore = state['not_before'] is int
        ? state['not_before'] as int
        : 0;
    if (count < max(1, next) || _now().millisecondsSinceEpoch < notBefore) {
      return false;
    }
    await tx.insert('preferences', {
      'key': stateKey,
      'value': jsonEncode({
        ...state,
        'next_count': count + 5 + _random.nextInt(8),
        'not_before': _now()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  });
}
