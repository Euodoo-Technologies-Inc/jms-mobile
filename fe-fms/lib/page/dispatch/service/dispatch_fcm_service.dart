import 'dart:async';
import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';
import '../../../data/dispatch/datasource/dispatch_auth_datasource.dart';
import '../controller/dispatch_auth_controller.dart';
import '../controller/dispatch_jobs_controller.dart';
import 'dispatch_notice_service.dart';
import 'dispatch_sync_service.dart';

/// Subscribes to FCM token rotations and forwards them to
/// `POST /devices/refresh-fcm` whenever a dispatch session is active.
/// While unauthenticated, the token is cached so the next login/activate
/// picks it up via `DispatchConstants.prefFcmToken`.
class DispatchFcmService extends GetxService {
  final DispatchAuthDatasource _auth = DispatchAuthDatasource();
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _msgSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  Future<DispatchFcmService> init() async {
    _tokenSub =
        FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
    // Foreground push (data payload triggers refresh per docs §9).
    _msgSub = FirebaseMessaging.onMessage.listen(_onMessage);
    // Push tapped from background.
    _openedSub = FirebaseMessaging.onMessageOpenedApp
        .listen((m) => _onMessage(m, opened: true));
    // Cold start: app launched by tapping a notification.
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _onMessage(initial, opened: true);
    } catch (_) {}
    return this;
  }

  /// Refreshes the jobs list whenever an FCM message carries a `job_id` data
  /// field — covers admin-assigns, reassigns, and reschedule notifications.
  /// Legacy pushes that don't carry `job_id` are ignored here (the legacy
  /// FCM handler still processes them). A *tapped* notification ([opened])
  /// also opens that job on the map once the refresh lands.
  void _onMessage(RemoteMessage message, {bool opened = false}) {
    final data = message.data;
    if (data.isEmpty) return;
    final jobId = data['job_id']?.toString();
    if (jobId == null || jobId.isEmpty) return;

    if (!Get.isRegistered<DispatchAuthController>()) return;
    final auth = Get.find<DispatchAuthController>();
    if (!auth.isAuthenticated.value) {
      // Cold start: the session is still restoring — retry the tap once it
      // is up instead of dropping it.
      if (opened) {
        once(auth.isAuthenticated, (bool ok) {
          if (ok) _onMessage(message, opened: true);
        });
      }
      return;
    }

    if (Get.isRegistered<DispatchJobsController>()) {
      final ctrl = Get.find<DispatchJobsController>();
      final refresh = ctrl.refreshToday();
      final parsed = int.tryParse(jobId);
      if (parsed != null) {
        // Best-effort detail refresh; ignore failures.
        ctrl.fetchDetail(parsed).catchError((_) => null);
        if (opened) refresh.then((_) => _openJob(ctrl, parsed));
      }
    }
  }

  /// Brings the map to the front and focuses [jobId], or says why it can't.
  void _openJob(DispatchJobsController ctrl, int jobId) {
    final job = ctrl.jobs.firstWhereOrNull((j) => j.id == jobId);
    final notices = Get.find<DispatchNoticeController>();
    if (job == null || job.isFinished) {
      notices.info('That job is no longer on your list for today.');
      return;
    }
    // The map is the dispatch session's root route.
    Get.until((route) => route.isFirst);
    if (!ctrl.selectJob(job)) {
      notices.info('This job has no coordinates yet.');
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    if (token.isEmpty) return;

    // Always cache so the next login/activate sends it.
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(DispatchConstants.prefFcmToken);
      if (last == token) return; // no-op rotation
      await prefs.setString(DispatchConstants.prefFcmToken, token);
    } catch (_) {}

    // If a dispatch session is active, push the token now.
    if (!Get.isRegistered<DispatchAuthController>()) return;
    final authCtrl = Get.find<DispatchAuthController>();
    if (!authCtrl.isAuthenticated.value) return;

    try {
      await _auth.refreshFcmToken(token);
    } on DispatchApiException catch (e) {
      if (e.isUnauthorized) {
        await authCtrl.handleUnauthorized();
      } else if (e.isAccountDisabled) {
        await authCtrl.handleDisabled(e.message);
      } else if (e.isNetwork || e.statusCode >= 500) {
        // Queue for later sync (coalesces to latest token per repo logic).
        if (Get.isRegistered<DispatchSyncService>()) {
          await Get.find<DispatchSyncService>().enqueueFcm(token);
        }
      } else {
        log(
          'DispatchFcmService: refresh-fcm failed: ${e.message}',
          name: 'DispatchFcmService',
          level: 900,
        );
      }
    } catch (e) {
      log(
        'DispatchFcmService: refresh-fcm failed: $e',
        name: 'DispatchFcmService',
        level: 900,
      );
    }
  }

  @override
  void onClose() {
    _tokenSub?.cancel();
    _msgSub?.cancel();
    _openedSub?.cancel();
    super.onClose();
  }
}
