import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/network/api_client.dart';
import 'package:fms/core/services/connectivity_service.dart';
import 'package:fms/core/services/image_storage_service.dart';
import 'package:fms/data/datasource/cancel_job_datasource.dart';
import 'package:fms/data/datasource/finish_job_datasource.dart';
import 'package:fms/data/datasource/reschedule_job_datasource.dart';
import 'package:fms/data/models/offline_queue_item.dart';
import 'package:fms/data/repository/offline_queue_repository.dart';
import 'package:fms/page/jobs/controller/jobs_controller.dart';
import 'package:fms/core/theme/dispatch_palette.dart';

class SyncService extends GetxService {
  final OfflineQueueRepository _queueRepo = OfflineQueueRepository();
  final FinishJobDatasource _finishDatasource = FinishJobDatasource();
  final CancelJobDatasource _cancelDatasource = CancelJobDatasource();
  final RescheduleJobDatasource _rescheduleDatasource = RescheduleJobDatasource();

  bool _isSyncing = false;

  Future<SyncService> init() async {
    // Reset any stale 'syncing' items back to 'pending' (app-kill recovery)
    await _queueRepo.resetSyncingToPending();

    // Listen to connectivity changes
    final connectivity = Get.find<ConnectivityService>();
    ever(connectivity.isConnected, (bool connected) {
      if (connected) {
        // Wait for connection to stabilize before syncing
        Future.delayed(const Duration(seconds: 3), () {
          if (connectivity.isConnected.value) {
            syncAll();
          }
        });
      }
    });

    return this;
  }

  Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;

    // Skip company type validation during sync to reduce failure points
    ApiClient.skipValidation = true;

    try {
      final items = await _queueRepo.getPendingItems();
      if (items.isEmpty) return;

      log('Syncing ${items.length} queued action(s)...', name: 'SyncService');
      Get.snackbar(
        'Syncing',
        'Syncing ${items.length} queued action(s)...',
        backgroundColor: DispatchColors.brand.withValues(alpha: 0.9),
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );

      final connectivity = Get.find<ConnectivityService>();

      for (final item in items) {
        // Check connectivity before each item
        if (!connectivity.isConnected.value) {
          log('Lost connectivity mid-sync, stopping.', name: 'SyncService');
          break;
        }

        await _syncItem(item);
      }

      // Refresh jobs controller if registered
      try {
        if (Get.isRegistered<JobsController>()) {
          Get.find<JobsController>().refresh();
        }
      } catch (_) {}
    } catch (e) {
      log('Sync error: $e', name: 'SyncService', level: 1000);
    } finally {
      ApiClient.skipValidation = false;
      _isSyncing = false;
    }
  }

  Future<void> _syncItem(OfflineQueueItem item) async {
    final itemId = item.id;
    if (itemId == null) return;

    try {
      await _queueRepo.markSyncing(itemId);

      switch (item.actionType) {
        case OfflineActionType.finish:
          await _syncFinish(item);
        case OfflineActionType.cancel:
          await _syncCancel(item);
        case OfflineActionType.reschedule:
          await _syncReschedule(item);
      }

      // Success: clean up
      await _queueRepo.delete(itemId);
      if (item.imagePaths != null && item.imagePaths!.isNotEmpty) {
        await ImageStorageService.deleteImages(item.imagePaths!);
      }

      log('Job #${item.jobId} synced successfully', name: 'SyncService');
      Get.snackbar(
        'Synced',
        'Job #${item.jobId} synced successfully',
        backgroundColor: DispatchColors.brand.withValues(alpha: 0.9),
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      log('Failed to sync job #${item.jobId}: $e', name: 'SyncService', level: 1000);

      final newRetryCount = item.retryCount + 1;
      if (newRetryCount >= 3) {
        // Max retries exhausted — discard
        await _queueRepo.delete(itemId);
        if (item.imagePaths != null && item.imagePaths!.isNotEmpty) {
          await ImageStorageService.deleteImages(item.imagePaths!);
        }

        Get.snackbar(
          'Sync Failed',
          'Job #${item.jobId} failed after 3 attempts. Discarded.',
          backgroundColor: DispatchColors.danger.withValues(alpha: 0.9),
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 4),
        );
      } else {
        // Reset to pending for retry on next sync cycle
        await _queueRepo.resetToPendingWithRetry(itemId, newRetryCount);

        Get.snackbar(
          'Sync Retry',
          'Job #${item.jobId} will retry ($newRetryCount/3)',
          backgroundColor: DispatchColors.warning.withValues(alpha: 0.9),
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _syncFinish(OfflineQueueItem item) async {
    List<String> imagesBase64 = [];
    if (item.imagePaths != null && item.imagePaths!.isNotEmpty) {
      imagesBase64 = await ImageStorageService.loadImagesAsBase64(item.imagePaths!);
    }

    final response = await _finishDatasource.finishJob(
      jobId: item.jobId,
      imagesBase64: imagesBase64,
      notes: item.payload['notes'] as String?,
    ).timeout(const Duration(seconds: 60));

    if (response.success != true) {
      throw Exception(response.message ?? 'Server rejected finish request');
    }
  }

  Future<void> _syncCancel(OfflineQueueItem item) async {
    final response = await _cancelDatasource.cancelJob(
      jobId: item.jobId,
      reason: item.payload['reason'] as String? ?? '',
    );

    if (response.success != true) {
      throw Exception(response.message ?? 'Server rejected cancel request');
    }
  }

  Future<void> _syncReschedule(OfflineQueueItem item) async {
    final newDateStr = item.payload['new_date'] as String?;
    if (newDateStr == null) {
      throw Exception('Missing reschedule date');
    }

    final response = await _rescheduleDatasource.rescheduleJob(
      jobId: item.jobId,
      newDate: DateTime.parse(newDateStr),
      notes: item.payload['notes'] as String?,
    );

    if (response.success != true) {
      throw Exception(response.message ?? 'Server rejected reschedule request');
    }
  }
}
