import 'package:intl/intl.dart';

/// Formats ISO-8601 timestamps coming back from the dispatch API into the
/// same human-readable shape the web admin uses (`Carbon::parse(...)->format('M d, Y H:i')`).
/// Returns [fallback] when the input is null, empty, or unparseable so the
/// UI never leaks raw ISO blobs.
String formatDispatchTimestamp(String? raw, {String fallback = '—'}) {
  if (raw == null || raw.isEmpty) return fallback;
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw; // upstream sent a non-ISO label — show as-is.
  final local = dt.isUtc ? dt.toLocal() : dt;
  return DateFormat('MMM dd, yyyy HH:mm').format(local);
}

/// Road-distance formatter used for the "850 m away" / "1.5 km away" label
/// on the carousel cards. [meters] comes from OSRM's `route.distance` field.
String formatTravelDistance(double meters) {
  if (meters < 1) return '0 m';
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}

/// Travel-time formatter used for "12 min away" / "1h 25m" labels on the
/// carousel cards. [seconds] comes from OSRM's `route.duration` field.
String formatTravelDuration(int seconds) {
  if (seconds < 30) return 'arriving';
  if (seconds < 60) return '<1 min';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Date-only variant for fields like `job_date` that don't carry a time
/// component.
String formatDispatchDate(String? raw, {String fallback = '—'}) {
  if (raw == null || raw.isEmpty) return fallback;
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  return DateFormat('MMM dd, yyyy').format(dt);
}
