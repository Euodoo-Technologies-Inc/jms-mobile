import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fms/core/network/http_error_handler.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';

/// Service for managing user sessions and handling unauthorized responses.
class SessionService {
  SessionService._();

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

  static Future<void> _clearSessionAndRedirect() =>
      Get.find<AuthController>().logout(
        notice: HttpErrorHandler.sessionExpiredNotice,
      );
}
