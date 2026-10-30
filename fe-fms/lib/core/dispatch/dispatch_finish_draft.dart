import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'dispatch_constants.dart';

/// The Finish form as it was when the crew left for the camera or gallery,
/// so the page comes back as it was if Android kills the app while the
/// picker is up (#78). One draft at a time: a crew finishes one job at once.
class DispatchFinishDraft {
  const DispatchFinishDraft({
    required this.jobId,
    this.photoPaths = const [],
    this.meter = '',
    this.notes = '',
  });

  final int jobId;
  final List<String> photoPaths;
  final String meter;
  final String notes;

  static Future<DispatchFinishDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(DispatchConstants.prefFinishDraft);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return DispatchFinishDraft(
        jobId: m['jobId'] as int,
        photoPaths: (m['photos'] as List).cast<String>(),
        meter: m['meter'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DispatchConstants.prefFinishDraft,
      jsonEncode({
        'jobId': jobId,
        'photos': photoPaths,
        'meter': meter,
        'notes': notes,
      }),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(DispatchConstants.prefFinishDraft);
  }
}
