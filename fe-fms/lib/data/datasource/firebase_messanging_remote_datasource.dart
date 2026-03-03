import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fms/core/constants/variables.dart';
import 'package:fms/core/navigation/navigation_controller.dart';
import 'package:fms/data/datasource/auth_remote_datasource.dart';
import 'package:fms/page/jobs/controller/jobs_controller.dart';

/// Top-level function required by Firebase for background isolate invocation.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final ds = FirebaseMessangingRemoteDatasource();
  await ds.ensureLocalNotificationsReady();
  await ds.showNotification(
    title: message.notification?.title,
    body: message.notification?.body,
    jobId: message.data['job_id'],
  );
}

/// Datasource for handling Firebase Cloud Messaging (Push Notifications).
class FirebaseMessangingRemoteDatasource {
  // Singleton so background handler reuses the same instance.
  static final _instance = FirebaseMessangingRemoteDatasource._internal();
  factory FirebaseMessangingRemoteDatasource() => _instance;
  FirebaseMessangingRemoteDatasource._internal();

  static const _channelId = 'efms_job_notifications';
  static const _channelName = 'Job Notifications';
  static const _channelDesc = 'Notifications for new and updated jobs';

  final _firebaseMessaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _localReady = false;

  /// Lightweight init for background handler (no permissions, no listeners).
  Future<void> ensureLocalNotificationsReady() async {
    if (_localReady) return;
    _localReady = true;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_notif');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(initSettings);

    // Create notification channel (required on Android 8+).
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// Full init — called after login or session restore.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Request notification permission via permission_handler.
    await Permission.notification.request();

    // 2. Request FCM permission.
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. Ensure local notifications plugin and channel are ready.
    await ensureLocalNotificationsReady();

    // 4. Re-initialize with tap callback.
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_notif');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 5. Get FCM token and send to backend.
    final token = await _firebaseMessaging.getToken();
    if (kDebugMode) {
      debugPrint('FCM Token: $token');
    }
    if (token != null) {
      await _sendTokenToBackend(token);
    }

    // 6. Listen to token refresh.
    _firebaseMessaging.onTokenRefresh.listen(_sendTokenToBackend);

    // 7. Handle cold-start tap (app was killed, user tapped notification).
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _navigateToJobs();
    }

    // 8. Foreground messages — show local notification + refresh jobs.
    FirebaseMessaging.onMessage.listen((msg) {
      final notification = msg.notification;
      if (notification == null) return;
      showNotification(
        title: notification.title,
        body: notification.body,
        jobId: msg.data['job_id'],
      );
      if (Get.isRegistered<JobsController>()) {
        Get.find<JobsController>().refresh();
      }
    });

    // 9. Background tap — user tapped notification while app was in background.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _navigateToJobs());
  }

  /// Shows a local notification.
  Future<void> showNotification({
    String? title,
    String? body,
    String? jobId,
  }) async {
    final id = int.tryParse(jobId ?? '') ??
        (DateTime.now().millisecondsSinceEpoch ~/ 1000);

    await _localNotifications.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          icon: '@mipmap/ic_notif',
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  void _navigateToJobs() {
    if (Get.isRegistered<NavigationController>()) {
      final nav = Get.find<NavigationController>();
      final idx = nav.titles.indexOf('Jobs');
      if (idx >= 0) nav.changeTab(idx);
    }
    if (Get.isRegistered<JobsController>()) {
      Get.find<JobsController>().refresh();
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    _navigateToJobs();
  }

  Future<void> _sendTokenToBackend(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final lastToken = prefs.getString(Variables.prefFcmToken);
    if (lastToken == token) return; // Skip if already sent.

    final apiKey = prefs.getString(Variables.prefApiKey);
    if (apiKey == null || apiKey.isEmpty) return;

    try {
      await AuthRemoteDataSource().updateFcmToken(token);
      await prefs.setString(Variables.prefFcmToken, token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to update FCM token: $e');
      }
    }
  }

  /// Resets state so FCM can be re-initialized on next login.
  void reset() {
    _initialized = false;
    _localReady = false;
  }
}
