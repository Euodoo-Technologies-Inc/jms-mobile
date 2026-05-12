import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:fms/core/models/geo.dart';

/// A map widget implementation using `google_maps_flutter`.
class GoogleMapWidget extends StatefulWidget {
  final GeoPoint center;
  final double zoom;
  final List<MapMarkerModel> markers;
  final List<MapZoneModel> zones;
  final void Function(MapMarkerModel marker)? onMarkerTap;
  const GoogleMapWidget({
    super.key,
    required this.center,
    this.zoom = 14,
    this.markers = const [],
    this.zones = const [],
    this.onMarkerTap,
  });

  @override
  State<GoogleMapWidget> createState() => _GoogleMapWidgetState();
}

class _GoogleMapWidgetState extends State<GoogleMapWidget> {
  GoogleMapController? _controller;

  @override
  void didUpdateWidget(GoogleMapWidget old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null) return;
    final centerChanged = old.center.lat != widget.center.lat ||
        old.center.lng != widget.center.lng;
    final zoomChanged = old.zoom != widget.zoom;
    if (centerChanged || zoomChanged) {
      c.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(widget.center.lat, widget.center.lng),
          widget.zoom,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = widget.markers
        .map(
          (m) => Marker(
            markerId: MarkerId(m.id),
            position: LatLng(m.position.lat, m.position.lng),
            rotation: m.rotation ?? 0.0, // Apply rotation from ang field
            // Rider markers get a distinct azure hue so they don't blend in
            // with the red job pins.
            icon: m.kind == MapMarkerKind.rider
                ? BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  )
                : BitmapDescriptor.defaultMarker,
            infoWindow: InfoWindow(
              title: m.title,
              snippet: m.subtitle,
              onTap: widget.onMarkerTap != null
                  ? () => widget.onMarkerTap!(m)
                  : null,
            ),
            onTap: widget.onMarkerTap != null
                ? () => widget.onMarkerTap!(m)
                : null,
          ),
        )
        .toSet();

    final polygons = widget.zones
        .where((z) => z.type == MapZoneType.polygon)
        .map(
          (zone) => Polygon(
            polygonId: PolygonId(zone.id),
            points: zone.points.map((p) => LatLng(p.lat, p.lng)).toList(),
            fillColor:
                _parseColor(
                  zone.style?.fillColorHex,
                  zone.style?.fillOpacity,
                ) ??
                Colors.blue.withValues(alpha: 0.2),
            strokeColor:
                _parseColor(
                  zone.style?.strokeColorHex,
                  zone.style?.strokeOpacity,
                ) ??
                Colors.blue,
            strokeWidth: (zone.style?.strokeWidth ?? 2).round(),
          ),
        )
        .toSet();

    final polylines = widget.zones
        .where((z) => z.type == MapZoneType.polyline)
        .map(
          (zone) => Polyline(
            polylineId: PolylineId(zone.id),
            points: zone.points.map((p) => LatLng(p.lat, p.lng)).toList(),
            color:
                _parseColor(
                  zone.style?.strokeColorHex,
                  zone.style?.strokeOpacity,
                ) ??
                Colors.blue,
            width: (zone.style?.strokeWidth ?? 2).round(),
          ),
        )
        .toSet();

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.center.lat, widget.center.lng),
        zoom: widget.zoom,
      ),
      markers: markers,
      polygons: polygons,
      polylines: polylines,
      onMapCreated: (c) => _controller = c,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  Color? _parseColor(String? hex, double? opacity) {
    if (hex == null || hex.isEmpty) {
      return null;
    }
    var formatted = hex.replaceAll('#', '');
    if (formatted.length == 3) {
      formatted = formatted.split('').map((c) => '$c$c').join();
    }
    if (formatted.length == 6) {
      formatted = 'FF$formatted';
    }
    if (formatted.length != 8) {
      return null;
    }
    final value = int.tryParse(formatted, radix: 16);
    if (value == null) {
      return null;
    }
    final baseColor = Color(value);
    if (opacity != null) {
      return baseColor.withValues(alpha: opacity.clamp(0, 1));
    }
    return baseColor;
  }
}
