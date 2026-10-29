import 'dart:convert';
import 'dart:developer';

import 'package:fms/core/constants/variables.dart';
import 'package:fms/core/network/http_error_handler.dart';
import 'package:fms/data/models/response/auth_response_model.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/secure_storage.dart';

/// Remote datasource for authentication-related operations.
///
/// Note: Auth endpoints use http directly, not ApiClient,
/// because company validation is not needed for login/logout.
class AuthRemoteDataSource {
  /// Logs in the user with email and password.
  ///
  /// Returns [AuthResponseModel] if successful.
Future<AuthResponseModel> login({
  required String email,
  required String password,
  String? firebaseToken,
}) async {
  final uri = Uri.parse(Variables.loginEndpoint);

  final body = <String, dynamic>{'email': email, 'password': password};
  if (firebaseToken != null && firebaseToken.isNotEmpty) {
    body['firebasetoken'] = firebaseToken;
  }

  final response = await http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: jsonEncode(body),
  );

  log(
    response.statusCode.toString(),
    name: 'AuthRemoteDataSource',
    level: 800,
  );

  if (response.statusCode >= 200 && response.statusCode < 300) {
    final model = AuthResponseModel.fromJson(response.body);

    // Try to extract role and CompanyLogo from response Data and persist
    try {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      final data = decoded['Data'] as Map<String, dynamic>?;

      if (data != null) {
        final prefs = await SharedPreferences.getInstance();

        // --- Persist user role ---
        String? role;
        if (data['role'] != null) role = data['role'].toString();
        else if (data['Role'] != null) role = data['Role'].toString();
        else if (data['UserRole'] != null) role = data['UserRole'].toString();
        else if (data['userRole'] != null) role = data['userRole'].toString();
        else if (data['user_role'] != null) role = data['user_role'].toString();
        else if (data['role_name'] != null) role = data['role_name'].toString();
        else if (data['RoleName'] != null) role = data['RoleName'].toString();

        if (role != null && role.trim().isNotEmpty) {
          final normalized = role.trim().toLowerCase();
          await prefs.setString(Variables.prefUserRole, normalized);
          log('Persisted user role: $normalized',
              name: 'AuthRemoteDataSource', level: 800);
        }

        // --- Log HasTraxroot ---
        log('Login Data keys: ${data.keys.toList()}',
            name: 'AuthRemoteDataSource', level: 800);
        log('HasTraxroot raw value: ${data['HasTraxroot']} (type: ${data['HasTraxroot']?.runtimeType})',
            name: 'AuthRemoteDataSource', level: 800);

        // --- Persist CompanyLogo ---

        String? companyLogo;
        if (data['CompanyLogo'] != null) companyLogo = data['CompanyLogo'].toString();
        else if (data['companyLogo'] != null) companyLogo = data['companyLogo'].toString();
        else if (data['company_logo'] != null) companyLogo = data['company_logo'].toString();
        else if (data['Logo'] != null) companyLogo = data['Logo'].toString();
        else if (data['logo'] != null) companyLogo = data['logo'].toString();

        if (companyLogo != null && companyLogo.isNotEmpty) {
          // If the logo is a relative path, prepend the server origin
          if (!companyLogo.startsWith('http')) {
            final baseUri = Uri.parse(Variables.baseUrl);
            final origin = '${baseUri.scheme}://${baseUri.host}';
            companyLogo = '$origin$companyLogo';
          }
          await prefs.setString(Variables.companyLogo, companyLogo);
          log('Persisted company logo: $companyLogo',
              name: 'AuthRemoteDataSource', level: 800);
        } else {
          log('CompanyLogo not found in login Data',
              name: 'AuthRemoteDataSource', level: 800);
        }

        // You can also persist other fields if needed:
        // await prefs.setString(Variables.prefApiKey, data['ApiKey']);
        // await prefs.setInt(Variables.prefUserID, data['UserID']);
        // await prefs.setString(Variables.prefCompany, data['Company']);
        // await prefs.setInt(Variables.prefCompanyID, data['CompanyID']);
        // await prefs.setString(Variables.prefCompanyLabel, data['CompanyLabel']);
      }
    } catch (e) {
      log('Error parsing login data: $e', name: 'AuthRemoteDataSource', level: 1200);
    }

    if (model.success == true && model.data?.apiKey != null) {
      return model;
    } else {
      throw Exception('Login failed: invalid response');
    }
  } else if (response.statusCode == 429) {
    final retryAfter = response.headers['retry-after'];
    final seconds = int.tryParse(retryAfter ?? '') ?? 60;
    throw Exception(
      'Too many login attempts. Please try again in $seconds seconds.',
    );
  } else {
    // NOTE: deliberately do NOT route through HttpErrorHandler here. A 401 on
    // the login request just means wrong credentials — there's no session to
    // expire. Running the global 401 handler would call logout() and
    // Get.offAll(LoginPage), wiping the page and the user's typed inputs. We
    // simply surface the message so the login page can show it inline.
    log(response.body, name: 'AuthRemoteDataSource', level: 1200);
    throw Exception(_extractErrorMessage(
      response.body,
      'Login failed, please try again later',
    ));
  }
}


  /// Sends a forgot password request.
  Future<String> forgotPassword({required String email}) async {
    final uri = Uri.parse(Variables.forgotPasswordEndpoint);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{'email': email}),
    );

    log(
      response.statusCode.toString(),
      name: 'AuthRemoteDataSource.forgotPassword',
      level: 800,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final message = decoded['message'] ?? decoded['Message'];
        if (message != null && message.toString().isNotEmpty) {
          return message.toString();
        }
      } catch (_) {}
      return 'Reset password email sent.';
    } else if (response.statusCode == 429) {
      final retryAfter = response.headers['retry-after'];
      final seconds = int.tryParse(retryAfter ?? '') ?? 60;
      throw Exception(
        'Too many attempts. Please try again in $seconds seconds.',
      );
    } else {
      log(
        response.body,
        name: 'AuthRemoteDataSource.forgotPassword',
        level: 1200,
      );
      throw Exception(_extractErrorMessage(
        response.body,
        'Failed to send reset password (${response.statusCode})',
      ));
    }
  }

  /// Changes the user's password.
  ///
  /// Returns a success message string on success, throws Exception on failure.
  Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(Variables.prefApiKey);

    if (apiKey == null) {
      throw Exception('API Key not found. Please log in again.');
    }

    final uri = Uri.parse(Variables.changePasswordEndpoint);
    final response = await http.post(
      uri,
      headers: {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'current_password': currentPassword,
        'new_password': newPassword,
        'new_password_confirmation': confirmPassword,
      }),
    );

    log(
      response.statusCode.toString(),
      name: 'AuthRemoteDataSource.changePassword',
      level: 800,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final message = decoded['message'] ?? decoded['Message'];
        if (message != null && message.toString().isNotEmpty) {
          return message.toString();
        }
      } catch (_) {}
      return 'Password changed successfully';
    } else if (response.statusCode == 429) {
      final retryAfter = response.headers['retry-after'];
      final seconds = int.tryParse(retryAfter ?? '') ?? 60;
      throw Exception(
        'Too many attempts. Please try again in $seconds seconds.',
      );
    } else {
      log(
        response.body,
        name: 'AuthRemoteDataSource.changePassword',
        level: 1200,
      );
      throw Exception(_extractErrorMessage(
        response.body,
        'Failed to change password',
      ));
    }
  }

  /// Logs out the user: calls the server logout endpoint, then clears local data.
  ///
  /// Always clears local data even if the API call fails.
  Future<String> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(Variables.prefApiKey);
    final userId = prefs.getString(Variables.prefUserID);

    // Attempt server-side logout (fire-and-forget)
    if (apiKey != null && userId != null) {
      try {
        await http.post(
          Uri.parse(Variables.logoutEndpoint),
          headers: {
            'X-API-Key': apiKey,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'user_id': int.tryParse(userId) ?? userId}),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        log(
          'Server logout failed (non-blocking): $e',
          name: 'AuthRemoteDataSource',
          level: 900,
        );
      }
    }

    // Always clear local data (two-wheels only; the dispatch session stays)
    await SecureStorage.clearTwoWheelsPrefs(prefs);
    log(
      'Two-wheels shared preferences cleared',
      name: 'AuthRemoteDataSource',
      level: 800,
    );
    return 'Logout successful';
  }

  /// Updates the FCM token for push notifications.
  Future<void> updateFcmToken(String fcmToken) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(Variables.prefApiKey);

    if (apiKey == null) {
      throw Exception('API Key not found');
    }
    final url = Uri.parse(Variables.updateFcmTokenEndpoint);
    final response = await http.post(
      url,
      headers: {
        'X-API-Key': apiKey,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fcm_token': fcmToken}),
    );
    log(
      response.statusCode.toString(),
      name: 'AuthRemoteDataSource.updateFcmToken',
      level: 800,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    } else {
      HttpErrorHandler.handleResponse(response.statusCode, response.body);
      log(response.body, name: 'GetJobDatasource', level: 1200);
      String errorMessage = 'Failed to load data';
      try {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        if (decoded['Message'] != null) {
          errorMessage = decoded['Message'].toString();
        } else if (decoded['message'] != null) {
          errorMessage = decoded['message'].toString();
        }
      } catch (_) {
        errorMessage = 'Failed to cancel job';
      }
      if (errorMessage.toLowerCase().contains(
        'company subscription mismatch',
      )) {
        ApiClient.resetLogoutFlag();
      }

      return;
    }
  }
}

/// Extracts a user-friendly error message from a backend response.
///
/// Checks for field-level validation errors in `Errors`/`errors` (422),
/// then falls back to `Message`/`message` string.
String _extractErrorMessage(String responseBody, String fallback) {
  try {
    final decoded = json.decode(responseBody) as Map<String, dynamic>;

    // Check for field-level validation errors (422)
    final errors = decoded['Errors'] ?? decoded['errors'];
    if (errors is Map<String, dynamic> && errors.isNotEmpty) {
      final messages = <String>[];
      for (final fieldErrors in errors.values) {
        if (fieldErrors is List) {
          for (final msg in fieldErrors) {
            messages.add(msg.toString());
          }
        } else if (fieldErrors is String) {
          messages.add(fieldErrors);
        }
      }
      if (messages.isNotEmpty) return messages.join('\n');
    }

    // Fall back to top-level message
    if (decoded['Message'] != null) return decoded['Message'].toString();
    if (decoded['message'] != null) return decoded['message'].toString();
  } catch (_) {}

  return fallback;
}
