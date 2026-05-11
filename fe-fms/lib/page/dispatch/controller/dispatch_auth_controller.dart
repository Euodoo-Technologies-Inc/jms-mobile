import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';
import '../../../core/dispatch/dispatch_idempotency.dart';
import '../../../data/dispatch/datasource/dispatch_auth_datasource.dart';
import '../../../data/dispatch/models/dispatch_rider_model.dart';
import '../service/dispatch_sync_service.dart';
import 'dispatch_jobs_controller.dart';

/// Owns the dispatch session: bearer token, rider/company profile, and the
/// terminal 401 / 403-disabled state. Independent of the legacy AuthController.
class DispatchAuthController extends GetxController {
  final DispatchAuthDatasource _auth = DispatchAuthDatasource();

  final RxBool isLoading = false.obs;
  final RxBool isAuthenticated = false.obs;
  final Rxn<DispatchRider> rider = Rxn<DispatchRider>();
  final Rxn<DispatchCompany> company = Rxn<DispatchCompany>();

  /// Latched when the server returns 403 "disabled". UI shows a dead-end
  /// screen until the user dismisses it (per docs §6.5).
  final RxString disabledMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    checkSession();
  }

  /// Cold start: if we have a cached token, hit /me to validate + refresh.
  Future<void> checkSession() async {
    isLoading.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(DispatchConstants.prefToken);
      if (token == null || token.isEmpty) {
        isAuthenticated.value = false;
        return;
      }

      // Hydrate from cache first so the UI can render immediately.
      final riderRaw = prefs.getString(DispatchConstants.prefRider);
      if (riderRaw != null) {
        try {
          rider.value =
              DispatchRider.fromJson(jsonDecode(riderRaw) as Map<String, dynamic>);
        } catch (_) {}
      }
      final companyRaw = prefs.getString(DispatchConstants.prefCompany);
      if (companyRaw != null) {
        try {
          company.value = DispatchCompany.fromJson(
              jsonDecode(companyRaw) as Map<String, dynamic>);
        } catch (_) {}
      }
      isAuthenticated.value = true;

      // Validate against /me in the background.
      try {
        final me = await _auth.me();
        rider.value = me.rider;
        company.value = me.company;
        await prefs.setString(
            DispatchConstants.prefRider, jsonEncode(me.rider.toJson()));
        if (me.company != null) {
          await prefs.setString(DispatchConstants.prefCompany,
              jsonEncode(me.company!.toJson()));
        } else {
          await prefs.remove(DispatchConstants.prefCompany);
        }
      } on DispatchApiException catch (e) {
        if (e.isUnauthorized) {
          await _wipe();
        } else if (e.isAccountDisabled) {
          disabledMessage.value = e.message;
          await _wipe();
        }
        // Other errors leave cached state intact — user can retry.
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> login({
    required String phone,
    required String password,
    required String deviceName,
  }) async {
    isLoading.value = true;
    try {
      final fcmToken = await _readFcmToken();
      final result = await _auth.login(
        phone: phone,
        password: password,
        deviceName: deviceName,
        fcmToken: fcmToken,
      );
      await _persistAuth(result.token, result.rider, null);
      // Refresh /me to pull company info; non-fatal if it fails.
      try {
        final me = await _auth.me();
        rider.value = me.rider;
        company.value = me.company;
        final prefs = await SharedPreferences.getInstance();
        if (me.company != null) {
          await prefs.setString(DispatchConstants.prefCompany,
              jsonEncode(me.company!.toJson()));
        }
      } catch (_) {}
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> activate({
    required String phone,
    required String code,
    required String newPassword,
    required String deviceName,
  }) async {
    isLoading.value = true;
    try {
      final fcmToken = await _readFcmToken();
      final result = await _auth.activate(
        phone: phone,
        code: code,
        newPassword: newPassword,
        deviceName: deviceName,
        fcmToken: fcmToken,
      );
      await _persistAuth(result.token, result.rider, null);
      try {
        final me = await _auth.me();
        rider.value = me.rider;
        company.value = me.company;
        final prefs = await SharedPreferences.getInstance();
        if (me.company != null) {
          await prefs.setString(DispatchConstants.prefCompany,
              jsonEncode(me.company!.toJson()));
        }
      } catch (_) {}
    } finally {
      isLoading.value = false;
    }
  }

  /// Logout: best-effort revoke server-side, then wipe local state regardless.
  Future<void> logout() async {
    try {
      await _auth.logout();
    } catch (_) {
      // ignore network/4xx — wiping locally is what matters
    }
    await _wipe();
  }

  /// Called by any authenticated controller that catches a terminal 401.
  /// Wipes state and (callers should) routes to login.
  Future<void> handleUnauthorized() => _wipe();

  /// Called by any authenticated controller that catches a 403-disabled.
  /// Surfaces a non-dismissable message + wipes state.
  Future<void> handleDisabled(String message) async {
    disabledMessage.value =
        message.isNotEmpty ? message : 'Account disabled. Contact your dispatcher.';
    await _wipe();
  }

  /// Clears the latched disabled message so the login screen can be shown again.
  void dismissDisabled() => disabledMessage.value = '';

  Future<void> _persistAuth(
    String token,
    DispatchRider riderValue,
    DispatchCompany? companyValue,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DispatchConstants.prefToken, token);
    await prefs.setString(
        DispatchConstants.prefRider, jsonEncode(riderValue.toJson()));
    if (companyValue != null) {
      await prefs.setString(DispatchConstants.prefCompany,
          jsonEncode(companyValue.toJson()));
    } else {
      await prefs.remove(DispatchConstants.prefCompany);
    }
    rider.value = riderValue;
    company.value = companyValue;
    isAuthenticated.value = true;
  }

  Future<void> _wipe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(DispatchConstants.prefToken);
    await prefs.remove(DispatchConstants.prefRider);
    await prefs.remove(DispatchConstants.prefCompany);
    await DispatchIdempotencyStore.wipe();
    if (Get.isRegistered<DispatchSyncService>()) {
      await Get.find<DispatchSyncService>().wipe();
    }
    rider.value = null;
    company.value = null;
    isAuthenticated.value = false;
    // Drop the jobs controller so the next session starts clean.
    if (Get.isRegistered<DispatchJobsController>()) {
      Get.delete<DispatchJobsController>();
    }
  }

  Future<String?> _readFcmToken() async {
    // Bound the FCM lookup. On emulators / devices without Google Play
    // Services, getToken() can hang forever, which would block login.
    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 4));
      if (token != null && token.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(DispatchConstants.prefFcmToken, token);
        return token;
      }
    } catch (_) {
      // Timeout / no-services / misconfigured project — proceed without a
      // push token. FcmService.onTokenRefresh will hand it to the server
      // later if/when one is issued.
    }
    return null;
  }

  /// Best-effort device-name string for the auth payload.
  static Future<String> defaultDeviceName(String? riderLabel) async {
    String base;
    try {
      if (Platform.isAndroid) {
        base = 'Android';
      } else if (Platform.isIOS) {
        base = 'iOS';
      } else {
        base = 'Mobile';
      }
    } catch (_) {
      base = 'Mobile';
    }
    if (riderLabel != null && riderLabel.isNotEmpty) {
      final trimmed = '$base — $riderLabel';
      return trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed;
    }
    return base;
  }
}
