import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/widgets/snackbar_utils.dart';
import 'package:fms/data/datasource/auth_remote_datasource.dart';
import 'package:fms/data/datasource/profile_remote_datasource.dart';
import 'package:fms/data/datasource/traxroot_datasource.dart';
import 'package:fms/data/models/response/profile_response_model.dart';
import 'package:fms/page/auth/presentation/login_page.dart';
import 'package:fms/page/home/controller/home_controller.dart';
import 'package:fms/page/jobs/controller/jobs_controller.dart';
import 'package:fms/page/vehicles/controller/vehicles_controller.dart';

/// Controller for managing user profile data and authentication state.
class ProfileController extends GetxController {
  final ProfileRemoteDataSource _profileDs = ProfileRemoteDataSource();

  final AuthRemoteDataSource _authDs = AuthRemoteDataSource();

  final Rx<ProfileResponseModel?> profile = Rx<ProfileResponseModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool isChangingPassword = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchProfile();
  }

  /// Fetches the user's profile information.
  Future<void> fetchProfile() async {
    try {
      final res = await _profileDs.getProfile();
      profile.value = res;
    } catch (_) {
      // Keep silent, same behaviour as previous implementation which only toggled loading flag.
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
  Future<void> logout({
    required BuildContext context,
    required bool mounted,
  }) async {
    try {
      // Clear all auth data
      await _authDs.logout();

      // Clear Traxroot token cache
      await TraxrootAuthDatasource().clearCachedToken();

      // Clear controller caches
      try {
        if (Get.isRegistered<HomeController>()) {
          Get.delete<HomeController>();
        }
      } catch (_) {}

      try {
        if (Get.isRegistered<VehiclesController>()) {
          Get.delete<VehiclesController>();
        }
      } catch (_) {}

      try {
        if (Get.isRegistered<JobsController>()) {
          Get.delete<JobsController>();
        }
      } catch (_) {}

      if (mounted) {
        SnackbarUtils(
          text: 'Logout successful',
          backgroundColor: Colors.green,
          icon: Icons.logout,
        ).showSuccessSnackBar(context);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      } else {
        SnackbarUtils(
          text: 'Logout failed',
          backgroundColor: Colors.red,
          icon: Icons.logout,
        ).showErrorSnackBar(context);
      }
    } catch (_) {
      if (mounted) {
        SnackbarUtils(
          text: 'Logout failed',
          backgroundColor: Colors.red,
          icon: Icons.logout,
        ).showErrorSnackBar(context);
      }
    }
  }
}
