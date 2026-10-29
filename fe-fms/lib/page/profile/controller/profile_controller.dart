import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/widgets/snackbar_utils.dart';
import 'package:fms/data/datasource/auth_remote_datasource.dart';
import 'package:fms/data/datasource/profile_remote_datasource.dart';
import 'package:fms/data/models/response/profile_response_model.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';

/// Controller for managing user profile data and authentication state.
class ProfileController extends GetxController {
  final ProfileRemoteDataSource _profileDs = ProfileRemoteDataSource();

  final AuthRemoteDataSource _authDs = AuthRemoteDataSource();

  final Rx<ProfileResponseModel?> profile = Rx<ProfileResponseModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool isChangingPassword = false.obs;
  final RxnString error = RxnString();

  // Note: the profile page renders from the cached identity on
  // [AuthController] (persisted at login), so this controller no longer
  // fetches on init — it exists for change-password and logout. [fetchProfile]
  // remains available for an explicit refresh if ever needed.

  /// Fetches the user's profile information.
  Future<void> fetchProfile() async {
    isLoading.value = true;
    error.value = null;
    try {
      final res = await _profileDs.getProfile();
      profile.value = res;
    } catch (e) {
      log('Failed to fetch profile: $e', name: 'ProfileController', level: 1000);
      error.value = 'Failed to load profile';
    } finally {
      isLoading.value = false;
    }
  }

  /// Changes the user's password via the API.
  ///
  /// Returns success message on success, throws on failure.
  Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    isChangingPassword.value = true;
    try {
      final message = await _authDs.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      );
      return message;
    } finally {
      isChangingPassword.value = false;
    }
  }

  /// Logs out the user, clearing all local data and navigating to login.
  ///
  /// Delegates to [AuthController.logout] — the one path that also clears
  /// secure storage (the release-build API key), the FCM token and the
  /// offline queue/cache, and lands on the chooser.
  Future<void> logout({
    required BuildContext context,
    required bool mounted,
  }) async {
    try {
      await Get.find<AuthController>().logout();
      // The profile page is gone now; show the toast on the root navigator.
      final ctx = Get.context;
      if (ctx != null && ctx.mounted) {
        SnackbarUtils(
          text: 'Logout successful',
          backgroundColor: Colors.green,
          icon: Icons.logout,
        ).showSuccessSnackBar(ctx);
      }
    } catch (_) {
      if (mounted && context.mounted) {
        SnackbarUtils(
          text: 'Logout failed',
          backgroundColor: Colors.red,
          icon: Icons.logout,
        ).showErrorSnackBar(context);
      }
    }
  }
}
