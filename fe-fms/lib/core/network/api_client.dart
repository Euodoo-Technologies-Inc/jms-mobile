import 'dart:convert';
import 'dart:developer';
import 'package:fms/core/services/connectivity_service.dart';
import 'package:fms/core/widgets/app_feedback.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fms/core/constants/variables.dart';
import 'package:fms/data/datasource/auth_remote_datasource.dart';
import 'package:get/get.dart';
import 'package:fms/page/auth/presentation/login_page.dart';

/// Custom HTTP client that validates company type before every API call
class ApiClient {
  static bool _isValidating = false;
  static bool _hasLoggedOut = false;
  static bool skipValidation = false;

  /// Validate company type before making API request
  static Future<bool> _validateCompanyType() async {
    // Skip validation during offline sync to reduce failure points
    if (skipValidation) return true;

    // Prevent multiple simultaneous validations
    if (_isValidating || _hasLoggedOut) return !_hasLoggedOut;
    _isValidating = true;

    // Skip validation if offline — no point making a network call
    try {
      final connectivity = Get.find<ConnectivityService>();
      if (!connectivity.isConnected.value) return true;
    } catch (_) {} // Service not yet initialized, proceed normally

    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getInt(Variables.prefCompanyID);
      final localCompanyType = prefs.getInt(Variables.prefCompanyType);
      final apiKey = prefs.getString(Variables.prefApiKey);

      // Skip validation if no company data (e.g., not logged in)
      if (companyId == null || localCompanyType == null || apiKey == null) {
        return true;
      }

      final uri = Uri.parse(Variables.getCheckTypeCompanyEndpoint(companyId));
      final response = await http.get(
        uri,
        headers: {
          'X-API-Key': apiKey,
          'Accept': 'application/json',
        },
      );

      log(
        'Company type validation: ${response.statusCode}',
        name: 'ApiClient',
        level: 800,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final success = decoded['Success'] as bool?;
        final companySubscribe = decoded['CompanySubscribe'] as int?;

        if (success == true && companySubscribe != null) {
          // Check if company type matches
          if (localCompanyType != companySubscribe) {
            log(
              'Company type mismatch! Local: $localCompanyType, Remote: $companySubscribe',
              name: 'ApiClient',
              level: 1000,
            );
            await _logoutDueToMismatch();
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      log('Error validating company type: $e', name: 'ApiClient', level: 1000);
      // Don't block the request if validation fails
      return true;
    } finally {
      _isValidating = false;
    }
  }

  static Future<void> _logoutDueToMismatch() async {
    if (_hasLoggedOut) return;
    _hasLoggedOut = true;

    try {
      // Clear all data
      await AuthRemoteDataSource().logout();

      AppFeedback.error('Subscription Mismatch');

      // Redirect to login page
      Get.offAll(() => const LoginPage());
    } catch (e) {
      log('Error during logout: $e', name: 'ApiClient', level: 1000);
    }
  }

  /// GET request with company type validation.
  ///
  /// [uri] - The URI to send the request to.
  /// [headers] - Optional headers to include in the request.
  static Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    // Validate company type before making request
    final isValid = await _validateCompanyType();
    if (!isValid) {
      return _unauthorizedResponse();
    }

    return http.get(uri, headers: headers);
  }

  /// POST request with company type validation.
  ///
  /// [uri] - The URI to send the request to.
  /// [headers] - Optional headers.
  /// [body] - The body of the request.
  /// [encoding] - The encoding to use.
  static Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    // Validate company type before making request
    final isValid = await _validateCompanyType();
    if (!isValid) {
      return _unauthorizedResponse();
    }

    return http.post(uri, headers: headers, body: body, encoding: encoding);
  }

  /// PUT request with company type validation.
  ///
  /// [uri] - The URI to send the request to.
  /// [headers] - Optional headers.
  /// [body] - The body of the request.
  /// [encoding] - The encoding to use.
  static Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    // Validate company type before making request
    final isValid = await _validateCompanyType();
    if (!isValid) {
      return _unauthorizedResponse();
    }

    return http.put(uri, headers: headers, body: body, encoding: encoding);
  }

  /// DELETE request with company type validation.
  ///
  /// [uri] - The URI to send the request to.
  /// [headers] - Optional headers.
  /// [body] - The body of the request.
  /// [encoding] - The encoding to use.
  static Future<http.Response> delete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    // Validate company type before making request
    final isValid = await _validateCompanyType();
    if (!isValid) {
      return _unauthorizedResponse();
    }

    return http.delete(uri, headers: headers, body: body, encoding: encoding);
  }

  /// PATCH request with company type validation.
  ///
  /// [uri] - The URI to send the request to.
  /// [headers] - Optional headers.
  /// [body] - The body of the request.
  /// [encoding] - The encoding to use.
  static Future<http.Response> patch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    // Validate company type before making request
    final isValid = await _validateCompanyType();
    if (!isValid) {
      return _unauthorizedResponse();
    }

    return http.patch(uri, headers: headers, body: body, encoding: encoding);
  }

  /// Reset logout flag (useful for testing or re-login)
  static void resetLogoutFlag() {
    _hasLoggedOut = false;
  }

  static http.Response _unauthorizedResponse() {
    return http.Response(
      jsonEncode({'message': 'Company subscription mismatch'}),
      401,
      headers: {'Content-Type': 'application/json'},
    );
  }
}
