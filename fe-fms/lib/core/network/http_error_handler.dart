import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';

/// Helper class for handling HTTP errors globally.
class HttpErrorHandler {
  /// Shown over the chooser whenever a 2W request comes back 401.
  static const sessionExpiredNotice = 'Session expired. Please sign in again.';

  /// Handles the HTTP response based on the status code.
  ///
  /// [statusCode] - The HTTP status code.
  /// [responseBody] - The body of the response.
  static void handleResponse(int statusCode, String responseBody) {
    switch (statusCode) {
      case 401:
        _handleUnauthorized();
        break;
      case 403:
        debugPrint('HttpErrorHandler: 403 Forbidden');
        break;
      case 429:
        debugPrint('HttpErrorHandler: 429 Rate Limited');
        break;
      case 500:
      case 502:
      case 503:
        debugPrint('HttpErrorHandler: Server error $statusCode');
        break;
      default:
        if (statusCode >= 400) {
          debugPrint('HttpErrorHandler: HTTP error $statusCode');
        }
    }
  }

  static void _handleUnauthorized() {
    try {
      // Clear all data and redirect to the chooser.
      Get.find<AuthController>().logout(notice: sessionExpiredNotice);
    } catch (e) {
      // If AuthController not found, just log the error
      debugPrint('Error handling unauthorized: $e');
    }
  }

  /// Creates an exception from an HTTP error.
  ///
  /// [statusCode] - The HTTP status code.
  /// [responseBody] - The body of the response.
  static Exception createException(int statusCode, String responseBody) {
    handleResponse(statusCode, responseBody);
    return Exception('HTTP $statusCode: $responseBody');
  }
}
