import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/constants/variables.dart';
import 'package:fms/core/network/api_client.dart';
import 'package:fms/core/services/subscription.dart';
import 'package:fms/core/services/sync_service.dart';
import 'package:fms/core/storage/secure_storage.dart';
import 'package:fms/core/widgets/snackbar_utils.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fms/data/datasource/auth_remote_datasource.dart';
import 'package:fms/data/datasource/firebase_messanging_remote_datasource.dart';
import 'package:fms/data/datasource/traxroot_datasource.dart';
import 'package:fms/data/repository/job_cache_repository.dart';
import 'package:fms/data/repository/offline_queue_repository.dart';
import 'package:fms/data/models/traxroot_driver_model.dart';
import 'package:fms/data/models/traxroot_geozone_model.dart';
import 'package:fms/data/models/traxroot_icon_model.dart';
import 'package:fms/data/models/traxroot_object_group_model.dart';
import 'package:fms/data/models/traxroot_object_model.dart';
import 'package:fms/data/models/traxroot_object_status_model.dart';
import 'package:fms/nav_bar.dart';
import 'package:fms/page/auth/presentation/login_page.dart';
import 'package:fms/page/home/controller/home_controller.dart';
import 'package:fms/page/jobs/controller/jobs_controller.dart';
import 'package:fms/page/vehicles/controller/vehicles_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controller for handling authentication logic.
///
/// Manages user session, login, logout, and preloading of essential data.
class AuthController extends GetxController {
  final RxBool isLoading = false.obs;
  final RxBool isAuthenticated = false.obs;
  final RxString apiKey = ''.obs;
  final RxnString userRole = RxnString();
  final _storage = SecureStorage();

  @override
  void onInit() {
    super.onInit();
    checkSession();
  }

  /// Checks if the user is currently authenticated.
  ///
  /// Verifies if an API key exists in secure storage. If found, it updates the
  /// authentication state and loads the user's subscription plan.
  Future<void> checkSession() async {
    isLoading.value = true;
    try {
      final token = await _storage.read(Variables.prefApiKey);
      if (token != null && token.isNotEmpty) {
        apiKey.value = token;
        isAuthenticated.value = true;

        // Load CompanyType from SharedPreferences and update subscription service
        final prefs = await SharedPreferences.getInstance();
        final companyType = prefs.getInt(Variables.prefCompanyType);
        if (companyType != null) {
          subscriptionService.currentPlan = companyType == 2
              ? Plan.pro
              : Plan.basic;
        }

        final role = prefs.getString(Variables.prefUserRole);
        userRole.value = role;

        _initializeFcm();

        // Trigger pending sync if any queued items exist
        Future.microtask(() {
          try {
            if (Get.isRegistered<SyncService>()) {
              Get.find<SyncService>().syncAll();
            }
          } catch (_) {}
        });
      } else {
        isAuthenticated.value = false;
      }
    } catch (e) {
      isAuthenticated.value = false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Logs in the user with a token.
  ///
  /// Stores the provided token and updates the authentication state.
  Future<void> login(String token) async {
    await _storage.write(Variables.prefApiKey, token);
    apiKey.value = token;
    isAuthenticated.value = true;
  }

  /// Logs in the user with email and password.
  ///
  /// Authenticates with the remote server, stores user credentials and preferences,
  /// preloads Traxroot data, and navigates to the main application.
  Future<void> loginWithCredentials({
    required String email,
    required String password,
    required BuildContext context,
  }) async {
    final dataSource = AuthRemoteDataSource();

    try {
      final res = await dataSource.login(
        email: email.trim(),
        password: password,
      );

      final prefs = await SharedPreferences.getInstance();
      final apiKeyResult = res.data?.apiKey;
      final userID = res.data?.userId;
      final company = res.data?.company;
      final companyId = res.data?.companyId;
      final companyType = res.data?.companyType;
      final companyLabel = res.data?.companyLabel;
      final hasTraxroot = res.data?.hasTraxroot ?? false;

      log(
        'HasTraxroot: $hasTraxroot',
        name: 'Login',
        level: 800,
      );

      if (apiKeyResult == null || apiKeyResult.isEmpty) {
        throw Exception('Error fetch data');
      }

      await prefs.setString(Variables.prefApiKey, apiKeyResult);
      await _storage.write(Variables.prefApiKey, apiKeyResult);
      apiKey.value = apiKeyResult;

      log(userID.toString(), name: 'Login', level: 800);

      if (userID != null && userID.toString().isNotEmpty) {
        await prefs.setString(Variables.prefUserID, userID.toString());
      }

      if (company != null) {
        await prefs.setString(Variables.prefCompany, company);
      }

      if (companyId != null) {
        await prefs.setInt(Variables.prefCompanyID, companyId);
      }

      if (companyType != null) {
        await prefs.setInt(Variables.prefCompanyType, companyType);
        subscriptionService.currentPlan = companyType == 2
            ? Plan.pro
            : Plan.basic;
        log(
          'Company type: $companyType, Plan: ${subscriptionService.currentPlan}',
          name: 'Login',
          level: 800,
        );
      }

      if (companyLabel != null) {
        await prefs.setString(Variables.prefCompanyLabel, companyLabel);
      }

      await prefs.setBool(Variables.prefHasTraxroot, hasTraxroot);

      final savedRole = prefs.getString(Variables.prefUserRole);
      userRole.value = savedRole;

      // Set isAuthenticated AFTER all state (role, subscription, hasTraxroot)
      // is ready, so RootGate renders NavBar with the correct role.
      isAuthenticated.value = true;

      _initializeFcm();

      ApiClient.resetLogoutFlag();

      if (!context.mounted) return;

      _preloadTraxrootData();

      SnackbarUtils(
        text: 'Login Success',
        backgroundColor: Colors.green,
      ).showSuccessSnackBar(context);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NavBar()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      String errorMessage = 'Login Failed';
      final exceptionMessage = e.toString();
      log(exceptionMessage, name: 'Login', level: 900);
      if (exceptionMessage.startsWith('Exception: ')) {
        errorMessage = exceptionMessage.substring('Exception: '.length);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    }
  }

  /// Logs out the user and clears all data.
  ///
  /// Removes stored credentials, clears cached data in controllers, and
  /// redirects the user to the login page.
  Future<void> logout() async {
    // Clear FCM token so device stops receiving notifications
    try {
      await FirebaseMessaging.instance.deleteToken();
      FirebaseMessangingRemoteDatasource().reset();
    } catch (_) {}

    // Call server-side logout + clear SharedPreferences
    try {
      await AuthRemoteDataSource().logout();
    } catch (_) {}

    // Clear secure storage
    await _storage.deleteAll();
    apiKey.value = '';
    isAuthenticated.value = false;
    userRole.value = null;

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

    // Clear offline data to prevent data leaking between users
    try {
      await OfflineQueueRepository().deleteAll();
      await JobCacheRepository().clearAll();
    } catch (_) {}

    // Redirect to login page
    Get.offAll(() => const LoginPage());
  }

  void _initializeFcm() {
    Future.microtask(() async {
      try {
        await FirebaseMessangingRemoteDatasource().initialize();
      } catch (e) {
        log('FCM initialization failed: $e', name: 'AuthController', level: 900);
      }
    });
  }

  void _preloadTraxrootData() {
    final authDatasource = TraxrootAuthDatasource();
    final objectsDatasource = TraxrootObjectsDatasource(authDatasource);
    final internalDatasource = TraxrootInternalDatasource();

    Future.wait([
          objectsDatasource.getObjects().catchError((e) {
            log('Preload getObjects failed: $e', name: 'LoginPage', level: 900);
            return <TraxrootObjectModel>[];
          }),
          objectsDatasource.getObjectIcons().catchError((e) {
            log(
              'Preload getObjectIcons failed: $e',
              name: 'LoginPage',
              level: 900,
            );
            return <TraxrootIconModel>[];
          }),
          objectsDatasource.getObjectGroups().catchError((e) {
            log(
              'Preload getObjectGroups failed: $e',
              name: 'LoginPage',
              level: 900,
            );
            return <TraxrootObjectGroupModel>[];
          }),
          objectsDatasource.getAllObjectsStatus().catchError((e) {
            log(
              'Preload getAllObjectsStatus failed: $e',
              name: 'LoginPage',
              level: 900,
            );
            return <TraxrootObjectStatusModel>[];
          }),
          objectsDatasource.getDrivers().catchError((e) {
            log('Preload getDrivers failed: $e', name: 'LoginPage', level: 900);
            return <TraxrootDriverModel>[];
          }),
          internalDatasource.getGeozones().catchError((e) {
            log(
              'Preload getGeozones failed: $e',
              name: 'LoginPage',
              level: 900,
            );
            return <TraxrootGeozoneModel>[];
          }),
          internalDatasource.getGeozoneIcons().catchError((e) {
            log(
              'Preload getGeozoneIcons failed: $e',
              name: 'LoginPage',
              level: 900,
            );
            return <TraxrootIconModel>[];
          }),
        ])
        .then((_) {
          log(
            'Traxroot data preloading completed',
            name: 'LoginPage',
            level: 800,
          );
        })
        .catchError((e) {
          log(
            'Traxroot data preloading error: $e',
            name: 'LoginPage',
            level: 1000,
          );
        });
  }
}
