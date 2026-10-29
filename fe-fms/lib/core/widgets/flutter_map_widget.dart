import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:fms/core/models/geo.dart';

/// Breathing room (logical px) kept between framed content and the edges of
/// the *visible* map area when fitting to [FlutterMapWidget.fitBounds].
const double _kFitPadding = 40;

/// A map widget implementation using `flutter_map` (OpenStreetMap).
class FlutterMapWidget extends StatefulWidget {
  final GeoPoint center;
  final double zoom;
  final List<MapMarkerModel> markers;
  final List<MapZoneModel> zones;
  final void Function(MapMarkerModel marker)? onMarkerTap;
  final int recenterTick;

  /// When non-null the camera frames this box instead of [center]/[zoom].
  final GeoBounds? fitBounds;

  /// Logical pixels obscured at the bottom of the map by the job panel.
  final double bottomInset;

  /// Logical pixels at the top of the map kept clear of framed content — the
  /// status bar / notch / Dynamic Island region, now that the map is
  /// full-bleed and no AppBar guards the top edge.
  final double topInset;

  const FlutterMapWidget({
    super.key,
    required this.center,
    this.zoom = 4,
    this.markers = const [],
    this.zones = const [],
    this.onMarkerTap,
    this.recenterTick = 0,
    this.fitBounds,
    this.bottomInset = 0,
    this.topInset = 0,
  });

  @override
  State<FlutterMapWidget> createState() => _FlutterMapWidgetState();
}

class _FlutterMapWidgetState extends State<FlutterMapWidget>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  AnimationController? _camAnim;

  /// flutter_map's camera has no valid size until the map is laid out — guards
  /// the [CameraFit] math, which divides by the viewport size.
  bool _mapReady = false;

  /// Latest measured height of the map area (logical px), from [LayoutBuilder].
  double _mapHeight = 0;

  @override
  void didUpdateWidget(FlutterMapWidget old) {
    super.didUpdateWidget(old);

    // Fit mode: frame the route. Re-fit when the box moves, when the obscuring
    // panel resizes (so the route re-centres into the new visible area), or on
    // an explicit recenter request.
    if (widget.fitBounds != null) {
      final boundsChanged = widget.fitBounds != old.fitBounds;
      final insetChanged = widget.bottomInset != old.bottomInset;
      final recenterRequested = widget.recenterTick != old.recenterTick;
      if (boundsChanged || insetChanged || recenterRequested) {
        if (recenterRequested) _mapController.rotate(0);
        _fitToBounds();
      }
      return;
    }

    final centerChanged = old.center.lat != widget.center.lat ||
        old.center.lng != widget.center.lng;
    final zoomChanged = old.zoom != widget.zoom;
    final recenterRequested = old.recenterTick != widget.recenterTick;
    if (centerChanged || zoomChanged || recenterRequested) {
      // An explicit recenter also re-orients the map to north-up.
      if (recenterRequested) _mapController.rotate(0);
      _animateTo(widget.center.lat, widget.center.lng, widget.zoom);
    }
  }

  /// Frames [FlutterMapWidget.fitBounds] into the map area *above* the job
  /// panel. flutter_map has no camera-padding property, so we let [CameraFit]
  /// solve the centre/zoom against an asymmetric inset, then tween to it with
  /// the existing [_animateTo] so the move glides like the other transitions.
  void _fitToBounds() {
    final b = widget.fitBounds;
    if (b == null || !_mapReady) return;
    // Never let the panel claim the whole map — keep at least 20% usable.
    final maxInset = _mapHeight > 0 ? _mapHeight * 0.8 : widget.bottomInset;
    final inset = widget.bottomInset.clamp(0.0, maxInset);
    final fitted = CameraFit.bounds(
      bounds: LatLngBounds(
        ll.LatLng(b.southWest.lat, b.southWest.lng),
        ll.LatLng(b.northEast.lat, b.northEast.lng),
      ),
      padding: EdgeInsets.fromLTRB(
        _kFitPadding,
        // Keep framed content below the status bar / notch.
        _kFitPadding + widget.topInset,
        _kFitPadding,
        inset + _kFitPadding,
      ),
    ).fit(_mapController.camera);
    _animateTo(fitted.center.latitude, fitted.center.longitude, fitted.zoom);
  }

  /// flutter_map's MapController.move() is instant. Tween it ourselves so the
  /// camera glides between overview/focused selections instead of teleporting.
  void _animateTo(double lat, double lng, double zoom) {
    _camAnim?.dispose();
    final cam = _mapController.camera;
    final startLat = cam.center.latitude;
    final startLng = cam.center.longitude;
    final startZoom = cam.zoom;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final curve = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);
    void tick() {
      final t = curve.value;
      _mapController.move(
        ll.LatLng(
          startLat + (lat - startLat) * t,
          startLng + (lng - startLng) * t,
        ),
        startZoom + (zoom - startZoom) * t,
      );
    }
    curve.addListener(tick);
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        ctrl.dispose();
        if (identical(_camAnim, ctrl)) _camAnim = null;
      }
    });
    _camAnim = ctrl;
    ctrl.forward();
  }

  @override
  void dispose() {
    _camAnim?.dispose();
    _camAnim = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final worldBounds = LatLngBounds(
      ll.LatLng(-85.0511, -180.0),
      ll.LatLng(85.0511, 180.0),
    );
    final markers = widget.markers;
    final zones = widget.zones;
    final onMarkerTap = widget.onMarkerTap;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight.isFinite) {
          _mapHeight = constraints.maxHeight;
        }
        return FlutterMap(
      mapController: _mapController,
        options: MapOptions(
          initialCenter: ll.LatLng(widget.center.lat, widget.center.lng),
          initialZoom: widget.zoom,
          cameraConstraint: CameraConstraint.contain(bounds: worldBounds),
          maxZoom: 15,
          // Camera size is valid only once laid out — run the first fit here
          // so a job selected before the map mounted still frames correctly.
          onMapReady: () {
            _mapReady = true;
            if (widget.fitBounds != null) _fitToBounds();
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.querta.fms',
            maxZoom: 15,
            // Cancels in-flight requests for tiles pruned during the
            // fit-to-bounds camera animation, instead of letting them tie up
            // OSM's per-IP connection limit and starve the tiles actually in
            // view. Drop-in for the default NetworkTileProvider.
            tileProvider: CancellableNetworkTileProvider(),
          ),
          if (zones.isNotEmpty)
            PolygonLayer(
              polygons: zones.where((z) => z.type == MapZoneType.polygon).map((
                zone,
              ) {
                final fillColor =
                    _parseColor(
                      zone.style?.fillColorHex,
                      zone.style?.fillOpacity,
                    ) ??
                    Colors.blue.withValues(alpha: 0.2);
                final borderColor =
                    _parseColor(
                      zone.style?.strokeColorHex,
                      zone.style?.strokeOpacity,
                    ) ??
                    Colors.blue;
                return Polygon(
                  points: zone.points
                      .map((p) => ll.LatLng(p.lat, p.lng))
                      .toList(),
                  color: fillColor,
                  borderColor: borderColor,
                  borderStrokeWidth: (zone.style?.strokeWidth ?? 2).toDouble(),
                );
              }).toList(),
            ),
          if (zones.any((z) => z.type == MapZoneType.polyline))
            PolylineLayer(
              polylines: zones.where((z) => z.type == MapZoneType.polyline).map(
                (zone) {
                  final strokeColor =
                      _parseColor(
                        zone.style?.strokeColorHex,
                        zone.style?.strokeOpacity,
                      ) ??
                      Colors.blue;
                  return Polyline(
                    points: zone.points
                        .map((p) => ll.LatLng(p.lat, p.lng))
                        .toList(),
                    color: strokeColor,
                    strokeWidth: (zone.style?.strokeWidth ?? 2).toDouble(),
                  );
                },
              ).toList(),
            ),
          MarkerLayer(
            markers: markers.map((m) {
              // The rider marker carries a heading arrow, so it needs a larger
              // box than a job pin — the arrow must not clip when rotated.
              final isRider = m.kind == MapMarkerKind.rider;
              return Marker(
                point: ll.LatLng(m.position.lat, m.position.lng),
                width: isRider ? 54 : 36,
                height: isRider ? 54 : 36,
                rotate: true, // Keep upright as the map itself rotates.
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onMarkerTap != null ? () => onMarkerTap(m) : null,
                  child: _buildMarkerIcon(m),
                ),
              );
            }).toList(),
          ),
        ],
        );
      },
    );
  }

  // ignore: unused_element
  String _buildTooltipMessage(MapMarkerModel marker) {
    final parts = <String>[];
    if (marker.title != null && marker.title!.isNotEmpty) {
      parts.add(marker.title!);
    }
    if (marker.subtitle != null && marker.subtitle!.isNotEmpty) {
      parts.add(marker.subtitle!);
    }
    return parts.join('\n');
  }

  Widget _buildMarkerIcon(MapMarkerModel marker) {
    if (marker.iconUrl != null && marker.iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          marker.iconUrl!,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.location_pin, color: Colors.red, size: 24),
        ),
      );
    }
    if (marker.kind == MapMarkerKind.rider) {
      return _buildRiderMarker(marker.rotation);
    }
    return _buildJobMarker(marker.label);
  }

  /// A job stop marker: an amber/orange disc carrying the stop number, so the
  /// running order is readable straight off the map.
  Widget _buildJobMarker(String? label) {
    return Center(
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label ?? '',
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w800,
            fontSize: 13,
            height: 1,
          ),
        ),
      ),
    );
  }

  /// The rider's own marker: a Google-Maps-style blue location dot. When a
  /// heading is known it also fans a translucent "view cone" in that
  /// direction; with no heading yet it stays a plain dot.
  Widget _buildRiderMarker(double? heading) {
    return Transform.rotate(
      // Heading is degrees clockwise from north; the cone is painted pointing
      // up, so rotating by the heading orients it. Rotating the dot too is
      // harmless — it is radially symmetric.
      angle: (heading ?? 0) * (3.14159265359 / 180.0),
      child: CustomPaint(
        size: const Size(54, 54),
        painter: _RiderMarkerPainter(showCone: heading != null),
      ),
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
    final color = Color(value);
    if (opacity != null) {
      return color.withValues(alpha: opacity.clamp(0, 1));
    }
    return color;
  }
}

/// Paints the rider's location marker — a blue dot, plus a translucent
/// direction cone fanning "up" from it when [showCone] is set. The marker is
/// rotated by its parent [Transform.rotate] to orient the cone.
class _RiderMarkerPainter extends CustomPainter {
  const _RiderMarkerPainter({required this.showCone});

  final bool showCone;

  static const Color _blue = Color(0xFF1976D2);
  static const double _deg2rad = 3.14159265359 / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    if (showCone) {
      final radius = size.width / 2;
      const halfSpread = 32 * _deg2rad; // 32° to each side of "up"
      const up = -90 * _deg2rad; // straight up in canvas coords
      final cone = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          up - halfSpread,
          halfSpread * 2,
          false,
        )
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _blue.withValues(alpha: 0.50),
              _blue.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Drop shadow, white ring, blue core — the plain location dot.
    canvas.drawCircle(
      center.translate(0, 1),
      8.5,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawCircle(center, 8, Paint()..color = Colors.white);
    canvas.drawCircle(center, 6, Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(_RiderMarkerPainter old) => old.showCone != showCone;
}
