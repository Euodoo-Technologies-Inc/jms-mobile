import 'package:flutter/material.dart';
import 'package:fms/core/config/app_config.dart';
import 'package:fms/core/models/geo.dart';
import 'package:fms/core/widgets/flutter_map_widget.dart';
import 'package:fms/core/widgets/google_map_widget.dart';

/// A map widget that adapts between Google Maps and Flutter Map (OpenStreetMap)
/// based on configuration.
class AdaptiveMap extends StatelessWidget {
  final GeoPoint center;
  final double zoom;
  final List<MapMarkerModel> markers;
  final List<MapZoneModel> zones;
  final void Function(MapMarkerModel marker)? onMarkerTap;
  /// Monotonic counter that forces the camera to re-snap to [center]/[zoom]
  /// even when those values are unchanged from the previous build (e.g. the
  /// user pinched to zoom out, then tapped "center on me" again).
  final int recenterTick;
  const AdaptiveMap({
    super.key,
    required this.center,
    this.zoom = 14,
    this.markers = const [],
    this.zones = const [],
    this.onMarkerTap,
    this.recenterTick = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasKey = AppConfig.hasGoogleMapsKey;
    if (hasKey) {
      return GoogleMapWidget(
        center: center,
        zoom: zoom,
        markers: markers,
        zones: zones,
        onMarkerTap: onMarkerTap,
        recenterTick: recenterTick,
      );
    } else {
      return FlutterMapWidget(
        center: center,
        zoom: zoom,
        markers: markers,
        zones: zones,
        onMarkerTap: onMarkerTap,
        recenterTick: recenterTick,
      );
    }
  }
}
