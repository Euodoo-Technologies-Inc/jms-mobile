import 'dart:io';
import 'dart:developer';

import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_idempotency.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../data/dispatch/datasource/dispatch_auth_datasource.dart';
import '../../../data/dispatch/datasource/dispatch_jobs_datasource.dart';
import '../../../data/dispatch/offline/dispatch_queue_repository.dart';
import '../controller/dispatch_auth_controller.dart';
import '../controller/dispatch_jobs_controller.dart';

/// Drains [DispatchQueueRepository] when the device reconnects and a
/// dispatch session is active. Per docs §8.3:
///   - 2xx, 409, 422 → terminal, remove from queue
///   - 401 → stop draining, route to login
///   - 5xx / network → stop, retry later (no removal)
class DispatchSyncService extends GetxService {
  final DispatchQueueRepository _queue = DispatchQueueRepository();
  final DispatchJobsDatasource _jobs = DispatchJobsDatasource();
  final DispatchAuthDatasource _auth = DispatchAuthDatasource();

  Worker? _connWorker;
  Worker? _authWorker;
  bool _draining = false;

  /// Observable count of queued operations (for UI badges).
  final RxInt pendingCount = 0.obs;

  Future<DispatchSyncService> init() async {
    _connWorker = ever<bool>(
      Get.find<ConnectivityService>().isConnected,
      (online) {
        if (online) _maybeDrain();
      },
    );
    if (Get.isRegistered<DispatchAuthController>()) {
      _authWorker = ever<bool>(
        Get.find<DispatchAuthController>().isAuthenticated,
        (authed) {
          if (authed) _maybeDrain();
        },
      );
    }
    await _refreshCount();
    return this;
  }

  Future<void> _refreshCount() async {
    pendingCount.value = (await _queue.readAll()).length;
  }

  /// Returns true if the action was queued; false if it should bubble up.
  Future<bool> enqueueStart(int jobId) async {
    await _queue.enqueueStart(jobId);
    await _refreshCount();
    return true;
  }

  Future<bool> enqueueFinish(
    int jobId, {
    String? notes,
    String? meterNumber,
    List<File> photos = const [],
  }) async {
    await _queue.enqueueFinish(
      jobId,
      notes: notes,
      meterNumber: meterNumber,
      photos: photos,
    );
    await _refreshCount();
    return true;
  }

  Future<bool> enqueueFcm(String fcmToken) async {
    await _queue.enqueueFcmRefresh(fcmToken);
    await _refreshCount();
    return true;
  }

  Future<void> wipe() async {
    await _queue.wipe();
    pendingCount.value = 0;
  }

  Future<void> _maybeDrain() async {
    if (_draining) return;
    if (!Get.isRegistered<DispatchAuthController>()) return;
    final auth = Get.find<DispatchAuthController>();
    if (!auth.isAuthenticated.value) return;
    if (!Get.find<ConnectivityService>().isConnected.value) return;

    _draining = true;
    try {
      var entries = await _queue.readAll();
      while (entries.isNotEmpty) {
        final entry = entries.first;
        final ok = await _drainOne(entry);
        if (!ok) break; // network/5xx — stop, retry later
        await _queue.remove(entry.id);
        await _refreshCount();
        entries = await _queue.readAll();
      }
    } finally {
      _draining = false;
    }
  }

  /// Returns true if [entry] reached a terminal response (remove from queue),
  /// false if it was a transient failure (keep + stop).
  Future<bool> _drainOne(DispatchQueueEntry entry) async {
    try {
      switch (entry.type) {
        case DispatchQueueOpType.start:
          final jobId = entry.jobId;
          if (jobId == null) return true; // malformed; drop
          final key = await DispatchIdempotencyStore.getOrCreate(
            action: 'start',
            jobId: jobId,
          );
          final updated =
              await _jobs.startJob(jobId, idempotencyKey: key);
          await DispatchIdempotencyStore.clear(action: 'start', jobId: jobId);
          _patchJobsController(updated);
          return true;

        case DispatchQueueOpType.finish:
          final jobId = entry.jobId;
          if (jobId == null) return true;
          final files = <File>[];
          for (final path in entry.photoPaths) {
            final f = File(path);
            if (await f.exists()) {
              files.add(f);
            } else {
              log(
                'DispatchSync: photo missing for job $jobId: $path',
                name: 'DispatchSyncService',
                level: 900,
              );
            }
          }
          final key = await DispatchIdempotencyStore.getOrCreate(
            action: 'finish',
            jobId: jobId,
          );
          final updated = await _jobs.finishJob(
            jobId,
            idempotencyKey: key,
            notes: entry.notes,
            meterNumber: entry.meterNumber,
            photos: files,
          );
          await DispatchIdempotencyStore.clear(action: 'finish', jobId: jobId);
          _patchJobsController(updated);
          return true;

        case DispatchQueueOpType.fcm:
          final token = entry.fcmToken;
          if (token == null || token.isEmpty) return true;
          await _auth.refreshFcmToken(token);
          return true;
      }
    } on DispatchApiException catch (e) {
      if (e.isNetwork) return false; // retry later
      if (e.statusCode >= 500) return false;
      if (e.isUnauthorized) {
        await Get.find<DispatchAuthController>().handleUnauthorized();
        return false; // stop; we're logged out now
      }
      if (e.isAccountDisabled) {
        await Get.find<DispatchAuthController>().handleDisabled(e.message);
        return false;
      }
      // Terminal 4xx (404 reassigned, 409 already done, 422 validation) —
      // remove from queue and clear the idempotency key so the user gets a
      // fresh action next time.
      if (entry.jobId != null) {
        if (entry.type == DispatchQueueOpType.start) {
          await DispatchIdempotencyStore.clear(
              action: 'start', jobId: entry.jobId!);
        } else if (entry.type == DispatchQueueOpType.finish) {
          await DispatchIdempotencyStore.clear(
              action: 'finish', jobId: entry.jobId!);
        }
        // Refresh the job so the UI shows the true state.
        if (Get.isRegistered<DispatchJobsController>()) {
          try {
            await Get.find<DispatchJobsController>()
                .fetchDetail(entry.jobId!);
          } catch (_) {}
        }
      }
      return true;
    } catch (e) {
      log(
        'DispatchSync: unexpected error draining ${entry.type.name}: $e',
        name: 'DispatchSyncService',
        level: 1000,
      );
      return false;
    }
  }

  void _patchJobsController(dynamic updated) {
    if (!Get.isRegistered<DispatchJobsController>()) return;
    final ctrl = Get.find<DispatchJobsController>();
    // Trigger a list refresh so the UI mirrors server state precisely.
    ctrl.refreshToday();
    // (We could patch in place, but a fresh fetch keeps order consistent
    // with /jobs/today's server-side sort.)
  }

  @override
  void onClose() {
    _connWorker?.dispose();
    _authWorker?.dispose();
    super.onClose();
  }
}
