# Plan: Real-time Job Notifications with Sound

## Context

E-FMS is a Flutter mobile app for fleet/job management (`com.querta.fms`). It uses **GetX** for state management, **Firebase** for backend services, and a **CodeIgniter 3 (PHP 8.2)** backend API. The Firebase project is `jms-app-80f22` with Cloud Messaging enabled.

**Problem:** The deployed app has no push notifications when new jobs are assigned. Users must manually open the app and pull-to-refresh to see new jobs.

**Goal:** Real-time push notifications with default system sound that work in foreground, background, and when the app is killed.

**Root cause:** The app already has a file `lib/data/datasource/firebase_messanging_remote_datasource.dart` with FCM setup code, but `initialize()` is **never called anywhere**, and the file has 10 bugs that prevent it from working even if it were called.

---

## Project Architecture Reference

- **State management:** GetX (`GetxController`, `Obx()`, `Get.put()`, `Get.find()`)
- **Auth flow:** `main.dart` → `RootGate` observes `AuthController.isAuthenticated` → routes to `LoginPage` or `NavBar`
- **Navigation:** `NavigationController` manages bottom nav tabs. Tab titles include `'Jobs'`. Use `changeTab(index)` to switch.
- **Jobs:** `JobsController` has `refresh()` method that re-fetches all job lists.
- **API auth:** All API calls use header `X-API-Key` with key stored in SharedPreferences under `Variables.prefApiKey`.
- **FCM token endpoint:** `POST /update-fcm-token` with body `{"fcm_token": "..."}` and `X-API-Key` header. Already implemented in `AuthRemoteDataSource.updateFcmToken()`.
- **Existing dependencies (pubspec.yaml):** `firebase_core: ^4.2.1`, `firebase_messaging: ^16.0.4`, `flutter_local_notifications: ^19.5.0`, `permission_handler: ^12.0.1`, `get: ^4.7.2`
- **Android resources:** `@mipmap/ic_notif` exists in all density buckets (hdpi through xxxhdpi). No `ic_permission` drawable exists.
- **Android permissions:** `POST_NOTIFICATIONS` already declared in AndroidManifest.xml.

---

## Files to Modify (5 files)

| # | File | Action |
|---|------|--------|
| 1 | `lib/core/constants/variables.dart` | Add 1 constant |
| 2 | `lib/data/datasource/firebase_messanging_remote_datasource.dart` | Full rewrite (fix 10 bugs) |
| 3 | `lib/main.dart` | Add 2 lines (import + background handler registration) |
| 4 | `lib/page/auth/controller/auth_controller.dart` | Add FCM init calls (login, session restore, logout) |
| 5 | `android/app/src/main/AndroidManifest.xml` | Add 2 meta-data tags |

---

## Step 1: `lib/core/constants/variables.dart`

**What:** Add a SharedPreferences key for caching the FCM token to avoid redundant API calls.

**Where:** After line 76 (`static const String companyLogo = 'CompanyLogo';`), add:

```dart
static const String prefFcmToken = 'FcmToken';
```

---

## Step 2: `lib/data/datasource/firebase_messanging_remote_datasource.dart` — FULL REWRITE

**This is the largest change.** The current file has these 10 bugs:

1. `_firebaseMessagingBackgroundHandler` is an instance method (line 112) — Firebase requires a **top-level function** for background isolate invocation
2. `AndroidInitializationSettings('ic_permission')` (line 39) — `ic_permission` drawable doesn't exist. Must be `'@mipmap/ic_notif'`
3. Two duplicate `onMessage.listen()` calls (lines 79-82 and line 84) — creates double listeners
4. `message.notification!.title` (line 122) — force-unwrap crashes on data-only FCM messages
5. `onMessageOpenedApp` (line 86) calls `firebaseBackgroundHandler` which shows a **duplicate** notification when user taps — should navigate to Jobs tab instead
6. `getInitialMessage()` result (line 78) is discarded — cold-start notification taps are lost
7. No `AndroidNotificationChannel` created — Android 8+ requires explicit channel creation for notifications to show
8. No `onTokenRefresh` listener — if FCM rotates the token, the backend never learns
9. `showNotification()` uses `id: 0` (line 92) — every notification replaces the previous one
10. `onDidReceiveNotificationResponse` is empty (line 54) — tapping a notification does nothing

**Current file content (to be replaced entirely):**

```dart
import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fms/core/constants/variables.dart';
import 'package:fms/data/datasource/auth_remote_datasource.dart';

/// Datasource for handling Firebase Cloud Messaging (Push Notifications).
class FirebaseMessangingRemoteDatasource {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    final permissionStatus = await Permission.notification.status;
    if (!permissionStatus.isGranted) {
      await Permission.notification.request();
    }

    final notificationSettings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (kDebugMode) {
      debugPrint(
        'FirebaseMessaging permissions: '
        '${notificationSettings.authorizationStatus}',
      );
    }

    const initializationSettingsAndroid = AndroidInitializationSettings(
      'ic_permission',
    );
    final initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse notificationResponse) async {},
    );

    final fcmToken = await _firebaseMessaging.getToken();

    if (kDebugMode) {
      debugPrint('FCM Token: $fcmToken');
    }

    if (fcmToken != null) {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString(Variables.prefApiKey);

      if (apiKey != null && apiKey.isNotEmpty) {
        try {
          await AuthRemoteDataSource().updateFcmToken(fcmToken);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Failed to update FCM token: $e');
          }
        }
      }
    }

    FirebaseMessaging.instance.getInitialMessage();
    FirebaseMessaging.onMessage.listen((message) {
      log(message.notification?.body ?? '');
      log(message.notification?.title ?? '');
    });

    FirebaseMessaging.onMessage.listen(firebaseBackgroundHandler);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(firebaseBackgroundHandler);
  }

  Future showNotification({
    int id = 0,
    String? title,
    String? body,
    String? payLoad,
  }) async {
    return flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'com.querta.fms',
          'app',
          importance: Importance.max,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  @pragma('vm:entry-point')
  Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    await Firebase.initializeApp();
    FirebaseMessangingRemoteDatasource().firebaseBackgroundHandler(message);
  }

  Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
    showNotification(
      title: message.notification!.title,
      body: message.notification!.body,
    );
  }
}
```

**Rewrite the entire file with this structure:**

```dart
// TOP-LEVEL FUNCTION (outside any class) — required by Firebase for background isolate
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

class FirebaseMessangingRemoteDatasource {
  // SINGLETON — so background handler reuses the same instance
  static final _instance = FirebaseMessangingRemoteDatasource._internal();
  factory FirebaseMessangingRemoteDatasource() => _instance;
  FirebaseMessangingRemoteDatasource._internal();

  // CONSTANTS — channel ID must match AndroidManifest metadata and backend payload
  static const _channelId = 'efms_job_notifications';
  static const _channelName = 'Job Notifications';
  static const _channelDesc = 'Notifications for new and updated jobs';

  final _firebaseMessaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _localReady = false;

  // Lightweight init for background handler (no permissions, no listeners)
  Future<void> ensureLocalNotificationsReady() async { ... }
    // - Guard: if (_localReady) return; then set _localReady = true
    // - Initialize FlutterLocalNotificationsPlugin with AndroidInitializationSettings('@mipmap/ic_notif')
    //   and DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)
    // - Create AndroidNotificationChannel(_channelId, _channelName, description: _channelDesc,
    //     importance: Importance.high, playSound: true, enableVibration: true)
    // - Register channel via _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel()

  // Full init — called after login or session restore
  Future<void> initialize() async { ... }
    // Guard: if (_initialized) return; then set _initialized = true
    // 1. Request notification permission via permission_handler: Permission.notification.request()
    // 2. Request FCM permission: _firebaseMessaging.requestPermission(alert: true, badge: true, sound: true)
    // 3. Call ensureLocalNotificationsReady()
    // 4. Re-initialize local notifications WITH tap callback:
    //    _localNotifications.initialize(
    //      InitializationSettings(
    //        android: AndroidInitializationSettings('@mipmap/ic_notif'),
    //        iOS: DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true),
    //      ),
    //      onDidReceiveNotificationResponse: _onNotificationTapped,
    //    )
    // 5. Get FCM token: final token = await _firebaseMessaging.getToken()
    //    if (token != null) await _sendTokenToBackend(token)
    // 6. Listen to token refresh: _firebaseMessaging.onTokenRefresh.listen(_sendTokenToBackend)
    // 7. Handle cold-start tap: final initial = await FirebaseMessaging.instance.getInitialMessage()
    //    if (initial != null) _navigateToJobs()
    // 8. Foreground messages: FirebaseMessaging.onMessage.listen((msg) {
    //      final notification = msg.notification;
    //      if (notification == null) return;
    //      showNotification(title: notification.title, body: notification.body, jobId: msg.data['job_id']);
    //      // Also refresh jobs if controller exists:
    //      if (Get.isRegistered<JobsController>()) Get.find<JobsController>().refresh();
    //    })
    // 9. Background tap: FirebaseMessaging.onMessageOpenedApp.listen((_) => _navigateToJobs())

  Future<void> showNotification({String? title, String? body, String? jobId}) async { ... }
    // - Generate unique ID: int.tryParse(jobId ?? '') ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000)
    // - _localNotifications.show(id, title, body, NotificationDetails(
    //     android: AndroidNotificationDetails(_channelId, _channelName,
    //       channelDescription: _channelDesc, importance: Importance.high, priority: Priority.high,
    //       playSound: true, icon: '@mipmap/ic_notif', enableVibration: true),
    //     iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
    //   ))

  void _navigateToJobs([dynamic _]) { ... }
    // - if (Get.isRegistered<NavigationController>()) {
    //     final nav = Get.find<NavigationController>();
    //     final idx = nav.titles.indexOf('Jobs');
    //     if (idx >= 0) nav.changeTab(idx);
    //   }
    // - if (Get.isRegistered<JobsController>()) Get.find<JobsController>().refresh();

  void _onNotificationTapped(NotificationResponse response) { ... }
    // - Call _navigateToJobs()

  Future<void> _sendTokenToBackend(String token) async { ... }
    // - final prefs = await SharedPreferences.getInstance()
    // - final lastToken = prefs.getString(Variables.prefFcmToken)
    // - if (lastToken == token) return  // Skip if already sent
    // - final apiKey = prefs.getString(Variables.prefApiKey)
    // - if (apiKey == null || apiKey.isEmpty) return
    // - try { await AuthRemoteDataSource().updateFcmToken(token); await prefs.setString(Variables.prefFcmToken, token); }
    // - catch (e) { debugPrint in kDebugMode only }

  void reset() { ... }
    // - _initialized = false
    // - _localReady = false
}
```

**Imports needed:**
```dart
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
```

---

## Step 3: `lib/main.dart`

**What:** Register the top-level background message handler before `runApp()`.

**Current file content:**
```dart
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
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize SQLite database
  await OfflineDatabase.instance.database;
  // ... rest of main
}
```

**Add these 2 imports at top:**
```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fms/data/datasource/firebase_messanging_remote_datasource.dart';
```

**Add this line after `Firebase.initializeApp(...)` (after line 17) and before the SQLite init:**
```dart
FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
```

---

## Step 4: `lib/page/auth/controller/auth_controller.dart`

**What:** Initialize FCM after authentication, clean up on logout.

**Current file has these key sections (line numbers for reference):**
- Line 54: `isAuthenticated.value = true;` (in `checkSession()`)
- Line 172: `isAuthenticated.value = true;` (in `loginWithCredentials()`)
- Line 207-249: `logout()` method

### 4a. Add imports at top (after existing imports):
```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fms/data/datasource/firebase_messanging_remote_datasource.dart';
```

### 4b. Add private helper method to the `AuthController` class:
```dart
void _initializeFcm() {
  Future.microtask(() async {
    try {
      await FirebaseMessangingRemoteDatasource().initialize();
    } catch (e) {
      log('FCM initialization failed: $e', name: 'AuthController', level: 900);
    }
  });
}
```
This uses `Future.microtask` (non-blocking), matching the existing pattern for `SyncService.syncAll()` on line 69.

### 4c. In `checkSession()` — after `isAuthenticated.value = true;` (line 54):
Add:
```dart
_initializeFcm();
```

### 4d. In `loginWithCredentials()` — after `isAuthenticated.value = true;` (line 172):
Add:
```dart
_initializeFcm();
```

### 4e. In `logout()` — add BEFORE the existing `AuthRemoteDataSource().logout()` call (before line 210):
```dart
// Clear FCM token so device stops receiving notifications
try {
  await FirebaseMessaging.instance.deleteToken();
  FirebaseMessangingRemoteDatasource().reset();
} catch (_) {}
```

---

## Step 5: `android/app/src/main/AndroidManifest.xml`

**What:** Tell Android which notification channel and icon to use when FCM delivers a notification while the app is killed (system-delivered, no Dart code runs).

**Current content around the insertion point (lines 27-30):**
```xml
    <application
        android:label="E-FMS"
        ...>
        <meta-data
            android:name="firebase_analytics_collection_enabled"
            android:value="false" />
```

**Add after the `firebase_analytics_collection_enabled` meta-data (after line 29):**

```xml
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="efms_job_notifications" />
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@mipmap/ic_notif" />
```

The channel ID `efms_job_notifications` must exactly match the `_channelId` constant in the Dart code.

---

## Step 6: Backend — CI3 / PHP 8.2

The Flutter side receives and displays notifications. The backend must **send** them when a new job is created.

### What the backend already has:
- `POST /update-fcm-token` endpoint — receives `{"fcm_token": "..."}` with `X-API-Key` header and stores the user's FCM token in the database
- The Flutter app calls this endpoint on login/session restore to register the device

### What the backend needs to add:

**1. Get a Firebase service account key:**
- Firebase Console > Project Settings (gear icon) > Service Accounts tab
- Click "Generate new private key" → downloads a JSON file
- Place on server outside web root (e.g., `/path/to/firebase-service-account.json`)

**2. Install Google API Client:**
```bash
composer require google/apiclient
```

**3. Create a helper function to send FCM notifications:**
```php
function send_fcm_notification($fcm_token, $title, $body, $job_id) {
    $client = new Google_Client();
    $client->setAuthConfig('/path/to/firebase-service-account.json');
    $client->addScope('https://www.googleapis.com/auth/firebase.messaging');
    $access_token = $client->fetchAccessTokenWithAssertion()['access_token'];

    $url = 'https://fcm.googleapis.com/v1/projects/jms-app-80f22/messages:send';

    $payload = [
        'message' => [
            'token' => $fcm_token,
            'notification' => [
                'title' => $title,
                'body'  => $body,
            ],
            'data' => [
                'job_id' => (string) $job_id,
                'type'   => 'new_job',
            ],
            'android' => [
                'notification' => [
                    'channel_id' => 'efms_job_notifications',
                    'sound'      => 'default',
                ],
            ],
        ],
    ];

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Authorization: Bearer ' . $access_token,
        'Content-Type: application/json',
    ]);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    return $http_code === 200;
}
```

**4. Call it when a job is created/assigned:**
In the CI3 controller or model where jobs are created, after inserting the job into the database:
```php
// Look up the assigned user's FCM token from DB
$user = $this->db->get_where('users', ['id' => $assigned_user_id])->row();
if ($user && !empty($user->fcm_token)) {
    send_fcm_notification(
        $user->fcm_token,
        'New Job Available',
        $job_name . ' - ' . $customer_name,
        $job_id
    );
}
```

**Important:** The `channel_id` in the backend payload (`efms_job_notifications`) MUST match the channel ID in the Flutter code and AndroidManifest.xml. This is what triggers the correct notification sound on Android.

---

## Verification Checklist

| # | Test | Expected Result |
|---|------|----------------|
| 1 | Login to the app | Debug console shows `FCM Token: <token>` and token is sent to backend |
| 2 | Send test from Firebase Console (Engage > Messaging > paste token) | Notification appears with default system sound |
| 3 | Send while app is in background | Notification appears with sound |
| 4 | Send while app is force-closed | Notification appears with sound |
| 5 | Tap a notification (app in background) | App opens, navigates to Jobs tab, refreshes job data |
| 6 | Tap a notification (app was killed) | App launches, authenticates, navigates to Jobs tab |
| 7 | Receive notification while app is in foreground | Local notification shown with sound + job list auto-refreshes |
| 8 | Logout then login | Old FCM token deleted, new token generated and sent to backend |
| 9 | Deny notification permission | App does not crash, notifications silently don't appear |
| 10 | Create job on backend with FCM send | Notification arrives on device in real-time |

---

## Key Constraints

- The top-level background handler function `firebaseMessagingBackgroundHandler` MUST be outside any class — Firebase invokes it in a separate isolate
- The notification channel `efms_job_notifications` MUST be created before showing any notification on Android 8+
- The channel ID must be identical in: Dart code, AndroidManifest.xml, and backend FCM payload
- `onBackgroundMessage` must be called before `runApp()` in `main.dart`
- The singleton pattern on the datasource is required because the background handler creates a new instance in a fresh isolate
