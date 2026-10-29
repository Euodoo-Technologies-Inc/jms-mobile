import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';

/// Helper class for handling HTTP errors globally.
class HttpErrorHandler {
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
    // Get AuthController
    try {
      final authController = Get.find<AuthController>();

      // Clear all data and redirect to login
      authController.logout();
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
