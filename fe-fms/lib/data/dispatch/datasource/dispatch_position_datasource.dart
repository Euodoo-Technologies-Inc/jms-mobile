import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';

class DispatchPositionDatasource {
  DispatchPositionDatasource({DispatchApiClient? client})
      : _client = client ?? DispatchApiClient();

  final DispatchApiClient _client;

  /// Posts a GPS sample for the signed-in rider. `recordedAt` is ISO 8601;
  /// the server defaults to its own clock if omitted.
  Future<void> postPosition({
    required double lat,
    required double lng,
    DateTime? recordedAt,
  }) async {
    await _client.postJson(
      DispatchConstants.positionEndpoint,
      body: {
        'lat': lat,
        'lng': lng,
        if (recordedAt != null) 'recorded_at': recordedAt.toUtc().toIso8601String(),
      },
    );
  }
}
