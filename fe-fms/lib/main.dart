import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:fms/core/database/offline_database.dart';
import 'package:fms/core/services/connectivity_service.dart';
import 'package:fms/core/services/sync_service.dart';
import 'package:fms/core/theme/app_theme.dart';
import 'package:fms/core/theme/motion.dart';
import 'package:fms/core/theme/theme_controller.dart';
import 'package:fms/page/auth/presentation/login_chooser_page.dart';
import 'package:fms/nav_bar.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import 'package:fms/page/dispatch/controller/dispatch_auth_controller.dart';
import 'package:fms/page/dispatch/presentation/dispatch_disabled_page.dart';
import 'package:fms/page/dispatch/presentation/dispatch_jobs_page.dart';
import 'package:fms/page/dispatch/service/dispatch_fcm_service.dart';
import 'package:fms/page/dispatch/service/dispatch_notice_service.dart';
import 'package:fms/page/dispatch/service/dispatch_position_service.dart';
import 'package:fms/page/dispatch/service/dispatch_sync_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fms/data/datasource/firebase_messanging_remote_datasource.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App-level safety net: log uncaught framework and async errors instead of
  // letting them vanish, and in release show a calm message in place of a
  // widget that failed to build (debug keeps the red screen for diagnosis).
  // debugPrint, not dart:developer's log(): log() only reaches an attached
  // debugger, so in a release build these errors never reached logcat.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (_) => const Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Something went wrong on this screen. Please go back and try again.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Before the auth controllers: restoring either session reads the FCM
  // token, which needs Firebase up.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize controllers
  Get.put(AuthController());
  Get.put(DispatchAuthController(), permanent: true);

  // Theme — restore the persisted (or system-default) mode before the first
  // frame so the app never flashes the wrong theme on launch.
  final themeController = ThemeController();
  await themeController.load();
  Get.put<ThemeController>(themeController, permanent: true);

  // App-wide transient-notice banner controller (dispatch surface).
  Get.put<DispatchNoticeController>(DispatchNoticeController(), permanent: true);

  runApp(const MyApp());

  // Only now the rest: the first frame (the spinner, then the login or map
  // screen) no longer waits on the database, the connectivity probe or the
  // background services (#62).
  await _initServices();
}

/// The offline database, connectivity, sync queues, push and GPS pings —
/// nothing the first frame needs. Order matters: SyncService listens to
/// ConnectivityService + auth state, PositionService listens to auth + jobs.
Future<void> _initServices() async {
  // Initialize SQLite database
  await OfflineDatabase.instance.database;

  // Initialize ConnectivityService (permanent GetxService)
  await Get.putAsync<ConnectivityService>(
    () => ConnectivityService().init(),
    permanent: true,
  );

  // Initialize SyncService (permanent GetxService, depends on ConnectivityService)
  await Get.putAsync<SyncService>(
    () => SyncService().init(),
    permanent: true,
  );

  // Dispatch services (FCM token refresh, offline queue drain, GPS pings).
  // Order matters: SyncService listens to ConnectivityService + auth state,
  // PositionService listens to auth + jobs.
  await Get.putAsync<DispatchSyncService>(
    () => DispatchSyncService().init(),
    permanent: true,
  );
  await Get.putAsync<DispatchFcmService>(
    () => DispatchFcmService().init(),
    permanent: true,
  );
  await Get.putAsync<DispatchPositionService>(
    () => DispatchPositionService().init(),
    permanent: true,
  );

  // Both sessions kick a sync when restored; one restored before its sync
  // service came up found nothing to kick, so kick it here.
  if (Get.find<AuthController>().isAuthenticated.value) {
    Get.find<SyncService>().syncAll();
  }
}

// Built once and reused — avoids reallocating ThemeData on every theme swap.
final ThemeData _lightTheme = AppTheme.light();
final ThemeData _darkTheme = AppTheme.dark();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'E-FMS',
      debugShowCheckedModeBanner: false,
      // Every route slides in from the right (the same card-swipe used by the
      // profile page) so navigation feels seamless and consistent app-wide.
      // Its curve and duration come from [Motion] in [builder].
      defaultTransition: Transition.rightToLeft,
      // MaterialApp's theme is pinned so its built-in AnimatedTheme never
      // animates (the 200ms cross-fade janks on heavy screens). The real,
      // user-selected theme is applied instantly in [builder] via a plain
      // Theme widget driven by ThemeController — a single-frame swap.
      theme: _lightTheme,
      themeMode: ThemeMode.light,
      builder: (context, child) {
        Motion.applyRouteDefaults(context);
        final content =
            DispatchNoticeHost(child: child ?? const SizedBox.shrink());
        return Obx(() {
          final mode = Get.find<ThemeController>().themeMode.value;
          final isDark = mode == ThemeMode.dark ||
              (mode == ThemeMode.system &&
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark);
          return Theme(
            data: isDark ? _darkTheme : _lightTheme,
            child: content,
          );
        });
      },
      home: const RootGate(),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = Get.find<AuthController>();
    final dispatchAuth = Get.find<DispatchAuthController>();

    return Obx(() {
      if (authController.isLoading.value || dispatchAuth.isLoading.value) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      // A 403-disabled dispatch session blocks the UI until dismissed.
      if (dispatchAuth.disabledMessage.value.isNotEmpty) {
        return const DispatchDisabledPage();
      }
      // Dispatch session takes precedence when both happen to be authed.
      if (dispatchAuth.isAuthenticated.value) {
        return const DispatchJobsPage();
      }
      return authController.isAuthenticated.value
          ? const NavBar()
          : const LoginChooserPage();
    });
  }
}
