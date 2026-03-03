import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:fms/core/database/offline_database.dart';
import 'package:fms/core/services/connectivity_service.dart';
import 'package:fms/core/services/sync_service.dart';
import 'package:fms/core/theme/app_theme.dart';
import 'package:fms/page/auth/presentation/login_page.dart';
import 'package:fms/nav_bar.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fms/data/datasource/firebase_messanging_remote_datasource.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

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

  // Initialize controllers
  Get.put(AuthController());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'E-FMS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const RootGate(),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = Get.find<AuthController>();

    return Obx(() {
      if (authController.isLoading.value) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return authController.isAuthenticated.value
          ? const NavBar()
          : const LoginPage();
    });
  }
}
