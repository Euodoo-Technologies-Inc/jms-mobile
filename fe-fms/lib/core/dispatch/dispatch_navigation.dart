import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens Google Maps (or the platform default maps app) with turn-by-turn
/// directions from the user's current location to ([lat], [lng]).
///
/// Returns true on success. On failure (no app available, etc.) surfaces a
/// SnackBar through [context] if mounted and returns false.
Future<bool> launchMapsDirections(
  BuildContext context, {
  required double lat,
  required double lng,
  String? label,
}) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
    '${label != null ? '&destination_place_id=${Uri.encodeComponent(label)}' : ''}',
  );
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No maps app available to open directions.')),
      );
    }
    return ok;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open maps: $e')),
      );
    }
    return false;
  }
}
