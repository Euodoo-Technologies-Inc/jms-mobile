/// Global variables and constants used throughout the application.
///
/// This class contains API endpoints, shared preferences keys, and other constant values.
class Variables {
  /// The base URL for the main API.
  // static const String baseUrl = 'http://quetraverse.pro/efms/api/myapi';


  // Use --dart-define=BASE_URL=<url> to override at build/run time (default: production)
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://jms.euodoo.com.ph/api/myapi',
    // defaultValue: 'http://10.0.2.2:8000/myapi',
    // defaultValue: 'http://192.168.254.110:8000/myapi',
  );
  // API endpoints helper methods
  static String getProfileEndpoint(String userId) =>
      '$baseUrl/get-user/$userId';
  static String getJobHistoryEndpoint(String userId) =>
      '$baseUrl/get-job-by-user/$userId';
  static String getOngoingJobEndpoint(String userId) =>
      '$baseUrl/get-job-ongoing/$userId';
  static String getCheckTypeCompanyEndpoint(int companyId) =>
      '$baseUrl/check-type-company/$companyId';
  // API endpoints
  static const String loginEndpoint = '$baseUrl/login';
  static const String logoutEndpoint = '$baseUrl/logout';
  static const String forgotPasswordEndpoint = '$baseUrl/forgot-password';
  static const String changePasswordEndpoint = '$baseUrl/change-password';
  static const String getJobEndpoint = '$baseUrl/get-job';

  static const String driverGetJobEndpoint = '$baseUrl/driver-get-job';
  static const String finishedJobEndpoint = '$baseUrl/finished-job';
  static const String reportJobEndpoint = '$baseUrl/report-job';
  static const String postponeJobEndpoint = '$baseUrl/postpone-job';
  static const String cancelJobEndpoint = '$baseUrl/cancel-job';
  static const String rescheduleJobEndpoint = '$baseUrl/reschedule-job';
  static String getRescheduleStatusEndpoint(int jobId) =>
      '$baseUrl/reschedule-status/$jobId';
  static const String updateFcmTokenEndpoint = '$baseUrl/update-fcm-token';

  // Traxroot endpoints
  /// Base URL for direct Traxroot API (used with proxy-obtained token).
  static const String traxrootBaseUrl = 'https://connect.traxroot.com/api';
  static const String traxrootIconBaseUrl = 'https://connect.traxroot.com';
  static const String traxrootObjectsStatusEndpoint =
      '$traxrootBaseUrl/ObjectsStatus';
  static String getTraxrootObjectStatusEndpoint(int objectId) =>
      '$traxrootBaseUrl/ObjectsStatus/$objectId';
  static const String traxrootObjectIconsEndpoint =
      '$traxrootBaseUrl/Objects/Icons';
  static const String traxrootObjectsEndpoint = '$traxrootBaseUrl/Objects';
  static const String traxrootDriversEndpoint = '$traxrootBaseUrl/Drivers';
  static String getTraxrootDriverEndpoint(int driverId) =>
      '$traxrootBaseUrl/Drivers/$driverId';
  static const String traxrootGeozonesEndpoint = '$traxrootBaseUrl/Geozones';
  static const String traxrootGeozoneIconsEndpoint =
      '$traxrootBaseUrl/Geozones/Icons';
  static const String traxrootProfileEndpoint = '$traxrootBaseUrl/profile';

  // Shared Preferences keys
  /// Key for storing API Key in Shared Preferences.
  static const String prefApiKey = 'apiKey';
  static const String prefUserID = 'UserID';
  static const String prefCompany = 'Company';
  static const String prefCompanyID = 'CompanyID';
  static const String prefCompanyType = 'CompanyType';
  static const String prefCompanyLabel = 'CompanyLabel';
  static const String prefHasTraxroot = 'HasTraxroot';

  static const String prefTraxrootToken = 'TraxrootAccessToken';
  static const String prefTraxrootTokenExpiry = 'TraxrootAccessTokenExpiry';
  static const String prefUserRole = 'UserRole';


  static const String companyLogo = 'CompanyLogo';
  static const String prefFcmToken = 'FcmToken';
}
