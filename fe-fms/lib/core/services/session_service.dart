import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fms/page/auth/presentation/login_page.dart';
import 'package:fms/core/storage/secure_storage.dart';
import 'package:fms/core/widgets/app_feedback.dart';

/// Service for managing user sessions and handling unauthorized responses.
class SessionService {
  SessionService._();

  static bool _isRedirecting = false;
  static final _storage = SecureStorage();

  /// Checks if a response is unauthorized and handles redirection if necessary.
  ///
  /// Returns `true` if the response was unauthorized and handled.
  static Future<bool> handleUnauthorizedResponse(
    SharedPreferences prefs,
    http.Response response,
  ) async {
    if (!_isUnauthorized(response)) return false;
    await _clearSessionAndRedirect();
    return true;
  }

  static bool _isUnauthorized(http.Response response) {
    if (response.statusCode == 401) {
      return true;
    }

    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final status = decoded['Status'] ?? decoded['status'];
        final message = decoded['Message'] ?? decoded['message'];
        if (status == 401) {
          if (message is String) {
            return message.toLowerCase().contains('unauthorized');
          }
          return true;
        }
      }
    } catch (_) {
      // ignore parsing errors and treat as not unauthorized
    }
    return false;
  }

  static Future<void> _clearSessionAndRedirect() async {
    if (_isRedirecting) return;
    _isRedirecting = true;

    try {
      // Clear all data from SecureStorage
      await _storage.deleteAll();

      AppFeedback.error('Session expired. Please login again.');

      // Redirect to login page using GetX
      Get.offAll(() => const LoginPage());
    } finally {
      _isRedirecting = false;
    }
  }
}
