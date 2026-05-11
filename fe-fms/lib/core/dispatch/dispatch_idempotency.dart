import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'dispatch_constants.dart';
import 'dispatch_uuid.dart';

/// Persisted store of in-flight Idempotency-Keys, keyed by a logical action
/// like `start:901` or `finish:901`. Per the contract §6, a network retry of
/// the same logical action MUST reuse the same key so the server can replay.
///
/// Keys are cleared on terminal responses (2xx / 4xx). Server TTL is 24h.
class DispatchIdempotencyStore {
  static Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance();

  static String keyFor({required String action, required int jobId}) =>
      '$action:$jobId';

  /// Returns the persisted key for [action]+[jobId], creating + persisting
  /// a fresh UUID v4 on first call.
  static Future<String> getOrCreate({
    required String action,
    required int jobId,
  }) async {
    final prefs = await _prefs();
    final raw = prefs.getString(DispatchConstants.prefIdempotencyKeys);
    final map = _decode(raw);
    final field = keyFor(action: action, jobId: jobId);
    final existing = map[field];
    if (existing is String && existing.isNotEmpty) return existing;

    final fresh = generateUuidV4();
    map[field] = fresh;
    await prefs.setString(
      DispatchConstants.prefIdempotencyKeys,
      jsonEncode(map),
    );
    return fresh;
  }

  /// Drops the persisted key. Call after any terminal response.
  static Future<void> clear({
    required String action,
    required int jobId,
  }) async {
    final prefs = await _prefs();
    final raw = prefs.getString(DispatchConstants.prefIdempotencyKeys);
    final map = _decode(raw);
    map.remove(keyFor(action: action, jobId: jobId));
    await prefs.setString(
      DispatchConstants.prefIdempotencyKeys,
      jsonEncode(map),
    );
  }

  /// Wipes all persisted keys. Called on logout / 401.
  static Future<void> wipe() async {
    final prefs = await _prefs();
    await prefs.remove(DispatchConstants.prefIdempotencyKeys);
  }

  static Map<String, dynamic> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }
}
