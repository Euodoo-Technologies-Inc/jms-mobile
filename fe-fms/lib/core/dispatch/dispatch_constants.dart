/// Endpoints, SharedPreferences keys, and tunables for the dispatch surface.
///
/// Kept fully separate from [Variables] (legacy `/myapi/*`) — the dispatch
/// API uses a different base path, auth scheme, and envelope shape.
class DispatchConstants {
  /// Base URL for the dispatch API. Override with
  /// `--dart-define=DISPATCH_BASE_URL=…`. Default targets the Android
  /// emulator host alias against the local Laravel server on port 8000
  /// (same host as the legacy `/myapi/*` routes).
  static const String baseUrl = String.fromEnvironment(
    'DISPATCH_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/dispatch',
  );

  // Auth
  static const String activateEndpoint = '$baseUrl/auth/activate';
  static const String loginEndpoint = '$baseUrl/auth/login';
  static const String logoutEndpoint = '$baseUrl/auth/logout';
  static const String meEndpoint = '$baseUrl/me';

  // Devices
  static const String refreshFcmEndpoint = '$baseUrl/devices/refresh-fcm';

  // Position (optional GPS reporting)
  static const String positionEndpoint = '$baseUrl/position';

  // Routing proxy → OSRM (server-side cached, see OsrmController)
  static const String osrmRouteEndpoint = '$baseUrl/osrm/route';

  // Jobs
  static const String jobsTodayEndpoint = '$baseUrl/jobs/today';
  static const String jobsHistoryEndpoint = '$baseUrl/jobs/history';
  static String jobDetailEndpoint(int id) => '$baseUrl/jobs/$id';
  static String jobStartEndpoint(int id) => '$baseUrl/jobs/$id/start';
  static String jobFinishEndpoint(int id) => '$baseUrl/jobs/$id/finish';

  // SharedPreferences keys
  static const String prefToken = 'dispatch.auth.token';
  static const String prefRider = 'dispatch.auth.rider';
  static const String prefCompany = 'dispatch.auth.company';
  static const String prefFcmToken = 'dispatch.fcm.token';
  static const String prefIdempotencyKeys = 'dispatch.idempotency';
  static const String prefJobsTodayCache = 'dispatch.cache.jobs_today';
  static const String prefJobsTodayCachedAt = 'dispatch.cache.jobs_today_at';

  // Job status (per dispatch contract §2)
  static const int statusOnTheWay = 1;
  static const int statusFinished = 2;
  static const int statusReschedulePending = 3;

  // Limits (per contract §4.8)
  static const int maxPhotos = 5;
  static const int maxPhotoBytes = 4 * 1024 * 1024;
  static const int maxNotesLength = 2000;
}
