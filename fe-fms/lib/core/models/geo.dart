import 'dart:math' as math;

/// Represents a geographical point with latitude and longitude.
class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);
}

/// Where [p] sits against [line]: metres to the nearest point on it, and the
/// share (0–1) of the line's length still ahead of that point. Flat-earth
/// projection around [p], which is well under 1% off at city scale.
({double offMeters, double remaining}) projectOnPolyline(
    GeoPoint p, List<GeoPoint> line) {
  const my = 111320.0; // metres per degree of latitude
  final mx = my * math.cos(p.lat * math.pi / 180);
  var best = double.infinity, bestAlong = 0.0, total = 0.0;
  for (var i = 1; i < line.length; i++) {
    final ax = (line[i - 1].lng - p.lng) * mx;
    final ay = (line[i - 1].lat - p.lat) * my;
    final dx = (line[i].lng - p.lng) * mx - ax;
    final dy = (line[i].lat - p.lat) * my - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
    final off = math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2));
    final len = math.sqrt(len2);
    if (off < best) {
      best = off;
      bestAlong = total + t * len;
    }
    total += len;
  }
  return (offMeters: best, remaining: total == 0 ? 0 : 1 - bestAlong / total);
}

/// An axis-aligned latitude/longitude rectangle. Used to frame a set of points
/// (e.g. rider + job) inside the map's visible area instead of relying on a
/// hand-tuned center/zoom pair.
class GeoBounds {
  const GeoBounds({required this.southWest, required this.northEast});

  final GeoPoint southWest;
  final GeoPoint northEast;

  /// Tightest box containing every point in [points], which must be non-empty.
  factory GeoBounds.fromPoints(Iterable<GeoPoint> points) {
    final iter = points.iterator;
    if (!iter.moveNext()) {
      throw ArgumentError('GeoBounds.fromPoints requires at least one point');
    }
    var minLat = iter.current.lat, maxLat = iter.current.lat;
    var minLng = iter.current.lng, maxLng = iter.current.lng;
    while (iter.moveNext()) {
      final p = iter.current;
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    return GeoBounds(
      southWest: GeoPoint(minLat, minLng),
      northEast: GeoPoint(maxLat, maxLng),
    );
  }

  /// True when the box has collapsed to a single point — fitting a camera to
  /// it is meaningless, so callers should fall back to a fixed zoom.
  bool get isPoint =>
      southWest.lat == northEast.lat && southWest.lng == northEast.lng;

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      other.southWest.lat == southWest.lat &&
      other.southWest.lng == southWest.lng &&
      other.northEast.lat == northEast.lat &&
      other.northEast.lng == northEast.lng;

  @override
  int get hashCode =>
      Object.hash(southWest.lat, southWest.lng, northEast.lat, northEast.lng);
}

/// Visual variant for a marker. Job stops get the default pin; the rider's
/// own position gets a distinct dot so the two are never confused on map.
enum MapMarkerKind { job, rider }

/// Model representing a marker on the map.
class MapMarkerModel {
  final String id;
  final GeoPoint position;
  final String? title;
  final String? iconUrl;
  final String? subtitle;
  final Object? data;
  final double?
  rotation; // Rotation angle in degrees (0-360), based on compass direction

  /// Short text drawn on the marker itself — e.g. a job's stop number.
  final String? label;
  final MapMarkerKind kind;
  const MapMarkerModel({
    required this.id,
    required this.position,
    this.title,
    this.iconUrl,
    this.subtitle,
    this.data,
    this.rotation,
    this.label,
    this.kind = MapMarkerKind.job,
  });
}

/// Enum defining the type of map zone (polygon or polyline).
enum MapZoneType { polygon, polyline }

/// Style configuration for a map zone.
class MapZoneStyle {
  final String? fillColorHex;
  final double? fillOpacity;
  final String? strokeColorHex;
  final double? strokeWidth;
  final double? strokeOpacity;

  const MapZoneStyle({
    this.fillColorHex,
    this.fillOpacity,
    this.strokeColorHex,
    this.strokeWidth,
    this.strokeOpacity,
  });
}

/// Model representing a zone on the map (e.g., geofence).
class MapZoneModel {
  final String id;
  final MapZoneType type;
  final List<GeoPoint> points;
  final MapZoneStyle? style;
  final String? name;

  const MapZoneModel({
    required this.id,
    required this.type,
    required this.points,
    this.style,
    this.name,
  });
}
