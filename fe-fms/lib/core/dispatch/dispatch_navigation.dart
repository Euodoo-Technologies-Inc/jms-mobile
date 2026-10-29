import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/app_feedback.dart';

/// Opens Google Maps (or the platform default maps app) with turn-by-turn
/// directions from the user's current location to ([lat], [lng]).
///
/// Returns true on success. On failure (no app available, etc.) surfaces a
/// notice via [AppFeedback] if [context] is still mounted and returns false.
Future<bool> launchMapsDirections(
  BuildContext context, {
  required double lat,
  required double lng,
}) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
  );
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      AppFeedback.error('No maps app available to open directions.');
    }
    return ok;
  } catch (e) {
    if (context.mounted) {
      AppFeedback.error("Couldn't open maps. Try again.");
    }
    return false;
  }
}
