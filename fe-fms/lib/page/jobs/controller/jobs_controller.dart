import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fms/core/services/connectivity_service.dart';
import 'package:fms/core/services/image_storage_service.dart';
import 'package:fms/data/datasource/cancel_job_datasource.dart';
import 'package:fms/data/datasource/driver_get_job_datasource.dart';
import 'package:fms/data/datasource/finish_job_datasource.dart';
import 'package:fms/data/datasource/get_job_datasource.dart';
import 'package:fms/data/datasource/get_job_history_datasource.dart';
import 'package:fms/data/datasource/get_job_ongoing_datasource.dart';
import 'package:fms/data/datasource/reschedule_job_datasource.dart';
import 'package:fms/data/datasource/reschedule_status_datasource.dart';
import 'package:fms/data/datasource/traxroot_datasource.dart';
import 'package:fms/data/models/offline_queue_item.dart';
import 'package:fms/data/models/response/cancel_job_response_model.dart';
import 'package:fms/data/models/response/driver_get_job_response_model.dart';
import 'package:fms/data/models/response/finish_job_response_model.dart';
import 'package:fms/data/models/response/get_job_response_model.dart';
import 'package:fms/data/models/response/get_job_ongoing_response_model.dart'
    as ongoing;
import 'package:fms/data/models/response/get_job_history__response_model.dart'
    as history;
import 'package:fms/data/models/response/reschedule_job_response_model.dart';
import 'package:fms/data/models/response/reschedule_status_response_model.dart';
import 'package:fms/data/models/traxroot_object_status_model.dart';
import 'package:fms/data/repository/job_cache_repository.dart';
import 'package:fms/data/repository/offline_queue_repository.dart';
import 'package:fms/page/home/controller/home_controller.dart';
import 'package:fms/page/jobs/controller/history_filter_mixin.dart';

/// Controller for managing job lists (all, ongoing, history) and job actions.
class JobsController extends GetxController
    with GetSingleTickerProviderStateMixin, HistoryFilterMixin {
  final Rx<GetJobResponseModel?> allJobsResponse = Rx<GetJobResponseModel?>(
    null,
  );

  final RxnString errorAllJobs = RxnString();
  final RxnString errorHistoryJobs = RxnString();
  final RxnString errorOngoingJobs = RxnString();
  final Rx<history.GetJobHistoryResponseModel?> historyJobsResponse =
      Rx<history.GetJobHistoryResponseModel?>(null);

  final RxBool isLoadingAllJobs = true.obs;
  final RxBool isLoadingHistoryJobs = true.obs;
  final RxBool isLoadingOngoingJobs = true.obs;
  final Rx<ongoing.GetJobOngoingResponseModel?> ongoingJobsResponse =
      Rx<ongoing.GetJobOngoingResponseModel?>(null);

  final RxMap<int, DateTime> rescheduledJobs = <int, DateTime>{}.obs;
  late TabController tabController;

  final _getJobDatasource = GetJobDatasource();
  final _getJobHistoryDatasource = GetJobHistoryDatasource();
  final _getJobOngoingDatasource = GetJobOngoingDatasource();
  final _driverGetJobDatasource = DriverGetJobDatasource();
  final _finishJobDatasource = FinishJobDatasource();
  final _rescheduleJobDatasource = RescheduleJobDatasource();
  final _rescheduleStatusDatasource = RescheduleStatusDatasource();
  final _cancelJobDatasource = CancelJobDatasource();
  final _traxrootObjectsDatasource = TraxrootObjectsDatasource(
    TraxrootAuthDatasource(),
  );

  ConnectivityService get _connectivityService => Get.find<ConnectivityService>();

  final OfflineQueueRepository _offlineQueueRepo = OfflineQueueRepository();
  final JobCacheRepository _jobCacheRepo = JobCacheRepository();
  final RxList<OfflineQueueItem> pendingQueueItems = <OfflineQueueItem>[].obs;

  /// Reads the reactive connectivity state (instant, no network call).
  bool get _isOnline => _connectivityService.isConnected.value;

  /// Safely checks connectivity — prefers the reactive value but falls back
  /// to an async check. Returns false on any error instead of throwing.
  Future<bool> _checkConnectivity() async {
    // Fast path: reactive value is already known
    if (!_isOnline) return false;
    // Double-check with async call, but catch socket errors
    try {
      return await _connectivityService.hasConnection;
    } catch (_) {
      return false;
    }
  }

  String _toUserMessage(Object e) {
    final message = e.toString();
    if (message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('Network is unreachable')) {
      return 'No internet connection. Please check your connection and try again.';
    }
    return message;
  }

  @override
  void onClose() {
    disposeHistoryFilter();
    tabController.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    initHistoryFilter();
    tabController = TabController(length: 3, vsync: this);
    fetchAllJobs();
    fetchOngoingJobs();
    fetchHistoryJobs();
    _refreshPendingQueue();
  }

  /// Fetches the list of all jobs.
  Future<void> fetchAllJobs() async {
    try {
      isLoadingAllJobs.value = true;
      errorAllJobs.value = null;
      final hasConnection = await _checkConnectivity();
      if (!hasConnection) {
        errorAllJobs.value =
            'No internet connection. Please check your connection and try again.';
        allJobsResponse.value = null;
        return;
      }
      allJobsResponse.value = await _getJobDatasource.getJob();
    } catch (e) {
      errorAllJobs.value = _toUserMessage(e);
    } finally {
      isLoadingAllJobs.value = false;
    }
  }

  /// Fetches the history of completed jobs.
  Future<void> fetchHistoryJobs() async {
    try {
      isLoadingHistoryJobs.value = true;
      errorHistoryJobs.value = null;
      final hasConnection = await _checkConnectivity();
      if (!hasConnection) {
        errorHistoryJobs.value =
            'No internet connection. Please check your connection and try again.';
        historyJobsResponse.value = null;
        return;
      }
      historyJobsResponse.value = await _getJobHistoryDatasource
          .getJobHistory();
    } catch (e) {
      errorHistoryJobs.value = _toUserMessage(e);
    } finally {
      isLoadingHistoryJobs.value = false;
    }
  }

  /// Fetches the list of ongoing jobs, with offline cache fallback.
  Future<void> fetchOngoingJobs() async {
    try {
      isLoadingOngoingJobs.value = true;
      errorOngoingJobs.value = null;
      final hasConnection = await _checkConnectivity();

      if (!hasConnection) {
        // Offline: load from cache
        final cached = await _jobCacheRepo.getCachedOngoingJobs();
        if (cached.isNotEmpty) {
          ongoingJobsResponse.value = ongoing.GetJobOngoingResponseModel(
            success: true,
            data: cached,
          );
        } else {
          errorOngoingJobs.value =
              'No internet connection and no cached data.';
          ongoingJobsResponse.value = null;
        }
        await _refreshPendingQueue();
        return;
      }

      ongoingJobsResponse.value = await _getJobOngoingDatasource
          .getOngoingJobs();
      final jobs = ongoingJobsResponse.value?.data ?? [];
      final activeIds = jobs.map((job) => job.jobId).whereType<int>().toSet();
      rescheduledJobs.removeWhere((jobId, _) => !activeIds.contains(jobId));

      // Clear local optimistic state when server has a definitive answer
      // (approved=2, rejected=3, or no pending reschedule).
      for (final job in jobs) {
        final id = job.jobId;
        if (id != null && rescheduledJobs.containsKey(id)) {
          final status = job.rescheduleStatus;
          if (status == null || status == 0 || status == 2 || status == 3) {
            rescheduledJobs.remove(id);
          }
        }
      }

      // Cache for offline use
      await _jobCacheRepo.cacheOngoingJobs(jobs);
    } catch (e) {
      errorOngoingJobs.value = _toUserMessage(e);
    } finally {
      isLoadingOngoingJobs.value = false;
    }
  }

  /// Refreshes all job lists.
  Future<void> refresh() async {
    await Future.wait([fetchAllJobs(), fetchOngoingJobs(), fetchHistoryJobs()]);
    await _refreshPendingQueue();
    _syncHomeOverview();
  }

  /// Pushes the freshly-fetched job lists into the dashboard overview so its
  /// Open / Ongoing / Complete counts update the moment a job is accepted,
  /// finished, or cancelled — no manual dashboard refresh needed. Safe no-op
  /// when the home tab (and its controller) isn't registered.
  void _syncHomeOverview() {
    if (!Get.isRegistered<HomeController>()) return;
    Get.find<HomeController>().syncOverviewFromJobs(
      allJobs: allJobsResponse.value,
      ongoingJobs: ongoingJobsResponse.value,
      completedJobs: historyJobsResponse.value,
    );
  }

  /// Marks a job as rescheduled locally.
  void markJobRescheduled(int jobId, DateTime scheduledDate) {
    rescheduledJobs[jobId] = scheduledDate;
  }

  /// Clears the rescheduled status of a job locally.
  void clearJobRescheduled(int jobId) {
    rescheduledJobs.remove(jobId);
  }

  /// Fetches the latest reschedule status for a job from the server.
  Future<RescheduleStatusResponseModel> fetchRescheduleStatus(int jobId) {
    return _rescheduleStatusDatasource.getRescheduleStatus(jobId: jobId);
  }

  /// Starts a job (driver claims it).
  Future<DriverGetJobResponseModel> startJob(int jobId) {
    return _driverGetJobDatasource.driverGetJob(jobId: jobId);
  }

  /// Finishes a job with optional images and notes.
  /// When offline, saves images to disk and enqueues for later sync.
  Future<FinishJobResponseModel> finishJob({
    required int jobId,
    required List<String> imagesBase64,
    String? notes,
    List<XFile>? originalImageFiles,
  }) async {
    final isOnline = _isOnline;

    if (isOnline) {
      final response = await _finishJobDatasource.finishJob(
        jobId: jobId,
        imagesBase64: imagesBase64,
        notes: notes,
      );
      if (response.success == true) {
        await _jobCacheRepo.removeJob(jobId);
      }
      return response;
    }

    // OFFLINE: save images to disk, enqueue
    if (await _offlineQueueRepo.hasQueuedActionForJob(jobId)) {
      return FinishJobResponseModel(
        success: false,
        message: 'This job already has a pending offline action.',
      );
    }

    List<String> savedPaths = [];
    if (originalImageFiles != null && originalImageFiles.isNotEmpty) {
      savedPaths = await ImageStorageService.saveImages(
        jobId: jobId,
        images: originalImageFiles,
      );
    }

    await _offlineQueueRepo.enqueue(OfflineQueueItem(
      jobId: jobId,
      actionType: OfflineActionType.finish,
      payload: {'job_id': jobId, 'notes': notes ?? ''},
      imagePaths: savedPaths,
      status: OfflineQueueStatus.pending,
      createdAt: DateTime.now(),
    ));

    await _refreshPendingQueue();
    return FinishJobResponseModel(
      success: true,
      message: 'Job saved locally. Will sync when online.',
    );
  }

  /// Reschedules a job to a new date.
  /// When offline, enqueues for later sync.
  Future<RescheduleJobResponseModel> rescheduleJob({
    required int jobId,
    required DateTime newDate,
    String? notes,
  }) async {
    final isOnline = _isOnline;

    if (isOnline) {
      return _rescheduleJobDatasource.rescheduleJob(
        jobId: jobId,
        newDate: newDate,
        notes: notes,
      );
    }

    // OFFLINE
    if (await _offlineQueueRepo.hasQueuedActionForJob(jobId)) {
      return RescheduleJobResponseModel(
        success: false,
        message: 'This job already has a pending offline action.',
      );
    }

    await _offlineQueueRepo.enqueue(OfflineQueueItem(
      jobId: jobId,
      actionType: OfflineActionType.reschedule,
      payload: {
        'job_id': jobId,
        'new_date': newDate.toIso8601String(),
        'notes': notes ?? '',
      },
      status: OfflineQueueStatus.pending,
      createdAt: DateTime.now(),
    ));

    await _refreshPendingQueue();
    return RescheduleJobResponseModel(
      success: true,
      message: 'Reschedule saved locally. Will sync when online.',
    );
  }

  /// Cancels a job with a reason.
  /// When offline, enqueues for later sync.
  Future<CancelJobResponseModel> cancelJob({
    required int jobId,
    required String reason,
  }) async {
    final isOnline = _isOnline;

    if (isOnline) {
      return _cancelJobDatasource.cancelJob(jobId: jobId, reason: reason);
    }

    // OFFLINE
    if (await _offlineQueueRepo.hasQueuedActionForJob(jobId)) {
      return CancelJobResponseModel(
        success: false,
        message: 'This job already has a pending offline action.',
      );
    }

    await _offlineQueueRepo.enqueue(OfflineQueueItem(
      jobId: jobId,
      actionType: OfflineActionType.cancel,
      payload: {'job_id': jobId, 'reason': reason},
      status: OfflineQueueStatus.pending,
      createdAt: DateTime.now(),
    ));

    await _refreshPendingQueue();
    return CancelJobResponseModel(
      success: true,
      message: 'Cancellation saved locally. Will sync when online.',
    );
  }

  /// Gets the Traxroot status for a specific object/vehicle.
  Future<TraxrootObjectStatusModel> getObjectStatusForJob(int objectId) {
    return _traxrootObjectsDatasource.getObjectStatus(objectId: objectId);
  }

  /// Check if a job has a pending offline action.
  bool isJobPendingUpload(int jobId) =>
      pendingQueueItems.any((item) => item.jobId == jobId);

  Future<void> _refreshPendingQueue() async {
    pendingQueueItems.value = await _offlineQueueRepo.getAllItems();
  }
}
