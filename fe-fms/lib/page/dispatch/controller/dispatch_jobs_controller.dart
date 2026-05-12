import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';
import '../../../core/dispatch/dispatch_idempotency.dart';
import '../../../data/dispatch/datasource/dispatch_jobs_datasource.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../service/dispatch_sync_service.dart';
import 'dispatch_auth_controller.dart';

/// Thrown when an action was successfully queued for later sync (offline /
/// 5xx). Distinct from a failed action — UI should show a "saved offline"
/// state, not a red error.
class DispatchQueuedException implements Exception {
  DispatchQueuedException(this.action, this.jobId);
  final String action;
  final int jobId;
  @override
  String toString() => 'Queued $action for job $jobId';
}

/// Owns the list of today's jobs and orchestrates start/finish with
/// persistent idempotency. Per docs §6.6: one logical action = one
/// Idempotency-Key, persisted across retries, cleared on terminal response.
class DispatchJobsController extends GetxController with WidgetsBindingObserver {
  final DispatchJobsDatasource _ds = DispatchJobsDatasource();

  final RxBool isLoading = false.obs;
  final RxnString error = RxnString();
  final RxList<DispatchJob> jobs = <DispatchJob>[].obs;
  final RxBool isStale = false.obs;
  final Rxn<DateTime> lastFetchedAt = Rxn<DateTime>();

  static const String _startAction = 'start';
  static const String _finishAction = 'finish';

  /// Foreground polling cadence — picks up new admin assignments without
  /// relying on FCM push delivery. Short enough to feel "live", long
  /// enough that 24h of idle polling costs ~2.8k requests/device.
  static const Duration _pollInterval = Duration(seconds: 30);
  Timer? _pollTimer;
  bool _isForeground = true;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _loadCache().then((_) => refreshToday());
    _startPolling();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isForeground;
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      // Fire immediately on resume + restart the cadence so the next tick
      // is a full interval away rather than a stale "midway" deadline.
      if (!wasForeground) refreshToday();
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!_isForeground) return;
      refreshToday();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Hydrate from SharedPreferences so the user sees something on the first
  /// frame, even when the network call hasn't completed yet (or fails).
  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(DispatchConstants.prefJobsTodayCache);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final cached = decoded
          .whereType<Map<String, dynamic>>()
          .map(DispatchJob.fromJson)
          .toList(growable: false);
      jobs.assignAll(cached);
      final stamp = prefs.getString(DispatchConstants.prefJobsTodayCachedAt);
      if (stamp != null) lastFetchedAt.value = DateTime.tryParse(stamp);
      isStale.value = true; // mark stale until next successful refresh
    } catch (e) {
      log(
        'DispatchJobsController: failed to load cache: $e',
        name: 'DispatchJobsController',
        level: 900,
      );
    }
  }

  Future<void> _writeCache(List<DispatchJob> fresh) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Serialize via the parts the model already understands.
      final payload = fresh.map((j) => {
            'id': j.id,
            'job_name': j.jobName,
            'status': j.status,
            'job_date': j.jobDate,
            'address': j.address,
            'lat': j.lat,
            'lng': j.lng,
            'route_id': j.routeId,
            'route_order': j.routeOrder,
            'scheduled_arrival': j.scheduledArrival,
            'actual_arrival': j.actualArrival,
            'finish_when': j.finishWhen,
            'notes': j.notes,
            'photos': j.photos
                ?.map((p) => {'id': p.id, 'photo': p.filename})
                .toList(),
          }).toList();
      await prefs.setString(
        DispatchConstants.prefJobsTodayCache,
        jsonEncode(payload),
      );
      await prefs.setString(
        DispatchConstants.prefJobsTodayCachedAt,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      log(
        'DispatchJobsController: failed to write cache: $e',
        name: 'DispatchJobsController',
        level: 900,
      );
    }
  }

  Future<void> refreshToday() async {
    isLoading.value = true;
    error.value = null;
    try {
      final result = await _ds.jobsToday();
      jobs.assignAll(result);
      isStale.value = false;
      lastFetchedAt.value = DateTime.now();
      await _writeCache(result);
    } on DispatchApiException catch (e) {
      if (await _handleTerminalAuth(e)) return;
      // Keep any cached jobs visible; surface a friendly error.
      error.value = e.message;
      if (jobs.isNotEmpty) isStale.value = true;
    } catch (e) {
      error.value = e.toString();
      if (jobs.isNotEmpty) isStale.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  /// Fetches the latest snapshot for one job and patches it into [jobs].
  /// Returns the fresh copy, or null on failure (caller may surface error).
  Future<DispatchJob?> fetchDetail(int id) async {
    try {
      final fresh = await _ds.jobDetail(id);
      _patch(fresh);
      return fresh;
    } on DispatchApiException catch (e) {
      if (await _handleTerminalAuth(e)) return null;
      rethrow;
    }
  }

  /// Starts a job. Returns the updated job on success.
  /// Throws [DispatchQueuedException] if the call failed transiently and was
  /// queued for later sync. On 401/403 wipes auth and rethrows.
  Future<DispatchJob> startJob(int jobId) async {
    final key = await DispatchIdempotencyStore.getOrCreate(
      action: _startAction,
      jobId: jobId,
    );
    try {
      final updated = await _ds.startJob(jobId, idempotencyKey: key);
      _patch(updated);
      await DispatchIdempotencyStore.clear(action: _startAction, jobId: jobId);
      return updated;
    } on DispatchApiException catch (e) {
      if (e.isUnauthorized || e.isAccountDisabled) {
        await _handleTerminalAuth(e);
        rethrow;
      }
      // Transient: queue for later. Keeps the idempotency key in place so
      // the sync service replays the same key.
      if ((e.isNetwork || e.statusCode >= 500) &&
          Get.isRegistered<DispatchSyncService>()) {
        await Get.find<DispatchSyncService>().enqueueStart(jobId);
        throw DispatchQueuedException(_startAction, jobId);
      }
      if (e.statusCode >= 400 && e.statusCode < 500 && e.statusCode != 409) {
        await DispatchIdempotencyStore.clear(
            action: _startAction, jobId: jobId);
      }
      if (e.isConflict) {
        await fetchDetail(jobId);
        await DispatchIdempotencyStore.clear(
            action: _startAction, jobId: jobId);
      }
      rethrow;
    }
  }

  /// Finishes a job with optional notes and photos.
  /// Throws [DispatchQueuedException] if queued for later sync.
  Future<DispatchJob> finishJob(
    int jobId, {
    String? notes,
    List<File> photos = const [],
  }) async {
    final key = await DispatchIdempotencyStore.getOrCreate(
      action: _finishAction,
      jobId: jobId,
    );
    try {
      final updated = await _ds.finishJob(
        jobId,
        idempotencyKey: key,
        notes: notes,
        photos: photos,
      );
      _patch(updated);
      await DispatchIdempotencyStore.clear(
          action: _finishAction, jobId: jobId);
      return updated;
    } on DispatchApiException catch (e) {
      if (e.isUnauthorized || e.isAccountDisabled) {
        await _handleTerminalAuth(e);
        rethrow;
      }
      if ((e.isNetwork || e.statusCode >= 500) &&
          Get.isRegistered<DispatchSyncService>()) {
        await Get.find<DispatchSyncService>().enqueueFinish(
          jobId,
          notes: notes,
          photos: photos,
        );
        throw DispatchQueuedException(_finishAction, jobId);
      }
      if (e.statusCode >= 400 && e.statusCode < 500 && e.statusCode != 409) {
        await DispatchIdempotencyStore.clear(
            action: _finishAction, jobId: jobId);
      }
      if (e.isConflict) {
        await fetchDetail(jobId);
        await DispatchIdempotencyStore.clear(
            action: _finishAction, jobId: jobId);
      }
      rethrow;
    }
  }

  void _patch(DispatchJob fresh) {
    final idx = jobs.indexWhere((j) => j.id == fresh.id);
    if (idx >= 0) {
      jobs[idx] = fresh;
    } else {
      jobs.add(fresh);
    }
  }

  /// Returns true if [e] was a terminal auth failure and the caller should
  /// stop. The dispatch auth controller is responsible for routing to login.
  Future<bool> _handleTerminalAuth(DispatchApiException e) async {
    if (!Get.isRegistered<DispatchAuthController>()) return false;
    final auth = Get.find<DispatchAuthController>();
    if (e.isUnauthorized) {
      await auth.handleUnauthorized();
      return true;
    }
    if (e.isAccountDisabled) {
      await auth.handleDisabled(e.message);
      return true;
    }
    return false;
  }
}
