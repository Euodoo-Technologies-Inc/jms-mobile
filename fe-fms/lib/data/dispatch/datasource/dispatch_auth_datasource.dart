import 'dart:io' show Platform;

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';
import '../models/dispatch_rider_model.dart';

class DispatchAuthResult {
  DispatchAuthResult({required this.token, required this.rider});
  final String token;
  final DispatchRider rider;
}

class DispatchMeResult {
  DispatchMeResult({required this.rider, this.company});
  final DispatchRider rider;
  final DispatchCompany? company;
}

class DispatchAuthDatasource {
  DispatchAuthDatasource({DispatchApiClient? client})
      : _client = client ?? DispatchApiClient();

  final DispatchApiClient _client;

  Future<DispatchAuthResult> activate({
    required String phone,
    required String code,
    required String newPassword,
    required String deviceName,
    String? fcmToken,
  }) async {
    final body = await _client.postJson(
      DispatchConstants.activateEndpoint,
      requireAuth: false,
      body: {
        'phone': phone,
        'code': code,
        'new_password': newPassword,
        'device_name': deviceName,
        if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
        'platform': _platform(),
      },
    );
    return _parseAuth(body);
  }

  Future<DispatchAuthResult> login({
    required String phone,
    required String password,
    required String deviceName,
    String? fcmToken,
  }) async {
    final body = await _client.postJson(
      DispatchConstants.loginEndpoint,
      requireAuth: false,
      body: {
        'phone': phone,
        'password': password,
        'device_name': deviceName,
        if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
        'platform': _platform(),
      },
    );
    return _parseAuth(body);
  }

  /// Revokes the current device's token. Local cleanup is the caller's job;
  /// network errors here are ignored by callers per the contract.
  Future<void> logout() async {
    await _client.postJson(DispatchConstants.logoutEndpoint);
  }

  Future<DispatchMeResult> me() async {
    final body = await _client.getJson(DispatchConstants.meEndpoint);
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rider = DispatchRider.fromJson(
      (data['rider'] as Map).cast<String, dynamic>(),
    );
    final companyJson = data['company'];
    return DispatchMeResult(
      rider: rider,
      company: companyJson is Map
          ? DispatchCompany.fromJson(companyJson.cast<String, dynamic>())
          : null,
    );
  }

  Future<void> refreshFcmToken(String fcmToken) async {
    await _client.postJson(
      DispatchConstants.refreshFcmEndpoint,
      body: {'fcm_token': fcmToken},
    );
  }

  DispatchAuthResult _parseAuth(Map<String, dynamic> body) {
    final data = (body['data'] as Map).cast<String, dynamic>();
    return DispatchAuthResult(
      token: data['token']?.toString() ?? '',
      rider: DispatchRider.fromJson(
        (data['rider'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  String _platform() {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'android';
  }
}
