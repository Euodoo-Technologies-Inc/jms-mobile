/// Represents a geographical point with latitude and longitude.
class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);
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
  final MapMarkerKind kind;
  const MapMarkerModel({
    required this.id,
    required this.position,
    this.title,
    this.iconUrl,
    this.subtitle,
    this.data,
    this.rotation,
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
