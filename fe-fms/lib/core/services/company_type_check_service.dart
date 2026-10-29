import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fms/core/constants/variables.dart';
import 'package:fms/data/datasource/auth_remote_datasource.dart';
import 'package:get/get.dart';
import 'package:fms/core/widgets/app_feedback.dart';
import 'package:fms/page/auth/presentation/login_page.dart';

/// Service for verifying if the user's company subscription type matches the local data.
class CompanyTypeCheckService {
  CompanyTypeCheckService._();

  static bool _isChecking = false;

  /// Check if company type matches the subscription from API
  /// If mismatch, logout the user
  static Future<void> checkCompanyTypeMatch() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getInt(Variables.prefCompanyID);
      final localCompanyType = prefs.getInt(Variables.prefCompanyType);
      final apiKey = prefs.getString(Variables.prefApiKey);

      if (companyId == null || localCompanyType == null || apiKey == null) {
        log(
          'Missing company data in preferences',
          name: 'CompanyTypeCheckService',
          level: 900,
        );
        return;
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
        'Company type check response: ${response.statusCode}',
        name: 'CompanyTypeCheckService',
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
              name: 'CompanyTypeCheckService',
              level: 1000,
            );
            await _logoutDueToMismatch();
          } else {
            log(
              'Company type match verified',
              name: 'CompanyTypeCheckService',
              level: 800,
            );
          }
        }
      } else {
        log(
          'Failed to check company type: ${response.statusCode}',
          name: 'CompanyTypeCheckService',
          level: 900,
        );
      }
    } catch (e) {
      log(
        'Error checking company type: $e',
        name: 'CompanyTypeCheckService',
        level: 1000,
      );
    } finally {
      _isChecking = false;
    }
  }

  static Future<void> _logoutDueToMismatch() async {
    try {
      // Clear all data
      await AuthRemoteDataSource().logout();

      AppFeedback.error('Your subscription type has changed. Please login again.');

      // Redirect to login page
      Get.offAll(() => const LoginPage());
    } catch (e) {
      log(
        'Error during logout: $e',
        name: 'CompanyTypeCheckService',
        level: 1000,
      );
    }
  }
}
