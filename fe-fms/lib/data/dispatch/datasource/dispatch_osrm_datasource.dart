import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';
import '../../../core/models/geo.dart';

/// Result of an OSRM `/route/v1/driving` call. `points` is the road-following
/// polyline; `durationSeconds` is OSRM's estimate of the drive time.
class DispatchRoute {
  const DispatchRoute({
    required this.points,
    required this.durationSeconds,
    required this.distanceMeters,
  });

  final List<GeoPoint> points;
  final int durationSeconds;
  final double distanceMeters;
}

/// Backend-proxied OSRM routing. The server caches 60s and chooses the
/// upstream driver (public demo / self-hosted), so the client just asks for
/// "the road polyline between these waypoints".
class DispatchOsrmDatasource {
  DispatchOsrmDatasource({DispatchApiClient? client})
      : _client = client ?? DispatchApiClient();

  final DispatchApiClient _client;

  /// Returns the road-following polyline + duration, or `null` if the upstream
  /// rejected the request or returned an unexpected shape. Network errors
  /// propagate as [DispatchApiException].
  Future<DispatchRoute?> route(List<GeoPoint> waypoints) async {
    if (waypoints.length < 2) return null;
    final coords = waypoints
        .map((p) => '${p.lng.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}')
        .join(';');
    final url = '${DispatchConstants.osrmRouteEndpoint}'
        '?coordinates=${Uri.encodeQueryComponent(coords)}';

    final body = await _client.getJson(url);
    final data = body['data'];
    if (data is! Map) return null;
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final first = routes.first;
    if (first is! Map) return null;
    final geometry = first['geometry'];
    if (geometry is! Map) return null;
    final coordsList = geometry['coordinates'];
    if (coordsList is! List) return null;

    final points = <GeoPoint>[];
    for (final pair in coordsList) {
      if (pair is! List || pair.length < 2) continue;
      final lng = (pair[0] as num?)?.toDouble();
      final lat = (pair[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add(GeoPoint(lat, lng));
    }
    if (points.length < 2) return null;
    final durationSeconds = ((first['duration'] as num?) ?? 0).round();
    final distanceMeters = ((first['distance'] as num?) ?? 0).toDouble();
    return DispatchRoute(
      points: points,
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
    );
  }
}
