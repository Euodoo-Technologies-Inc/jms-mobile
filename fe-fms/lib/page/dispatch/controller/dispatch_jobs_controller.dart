import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';
import '../../../core/dispatch/dispatch_idempotency.dart';
import '../../../core/models/geo.dart';
import '../../../data/dispatch/datasource/dispatch_jobs_datasource.dart';
import '../../../data/dispatch/datasource/dispatch_osrm_datasource.dart';
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

/// Owns the list of today's jobs and the rider's live map state (position,
/// selected job, OSRM polyline, ETA). Survives page rebuilds so the route the
/// rider is following is *already there* the moment the map remounts — no
/// blank-then-snap on revisit.
///
/// Also orchestrates start/finish with persistent idempotency. Per docs §6.6:
/// one logical action = one Idempotency-Key, persisted across retries,
/// cleared on terminal response.
class DispatchJobsController extends GetxController with WidgetsBindingObserver {
  final DispatchJobsDatasource _ds = DispatchJobsDatasource();
  final DispatchOsrmDatasource _osrm = DispatchOsrmDatasource();

  // ---- Jobs list state ------------------------------------------------------

  final RxBool isLoading = false.obs;
  final RxnString error = RxnString();
  final RxList<DispatchJob> jobs = <DispatchJob>[].obs;
  final RxBool isStale = false.obs;
  final Rxn<DateTime> lastFetchedAt = Rxn<DateTime>();

  // ---- Map state (lives across page rebuilds) ------------------------------

  final RxnInt selectedJobId = RxnInt();
  final Rxn<GeoPoint> riderPos = Rxn<GeoPoint>();
  final RxBool locating = false.obs;

  /// When true, the map center continuously tracks the live [riderPos] (the
  /// "center on me" follow mode). Cleared on selection changes.
  final RxBool followRider = false.obs;

  /// Road-following polyline from rider → navigation target. `null` means no
  /// route yet / fetch failed — the polyline is hidden entirely.
  final Rxn<List<GeoPoint>> routePoints = Rxn<List<GeoPoint>>();

  /// Drive distance (meters) from rider to the current target. Drives the
  /// "12 min away" label on the active card.
  final RxnDouble etaMeters = RxnDouble();

  /// Number of polyline points currently revealed, used to animate the line
  /// "drawing" from rider towards the job once OSRM data arrives.
  final RxInt routeRevealCount = 0.obs;

  static const String _startAction = 'start';
  static const String _finishAction = 'finish';

  /// Foreground polling cadence — picks up new admin assignments without
  /// relying on FCM push delivery. Short enough to feel "live", long
  /// enough that 24h of idle polling costs ~2.8k requests/device.
  static const Duration _pollInterval = Duration(seconds: 30);

  /// Silent GPS poll cadence — keeps [riderPos] and the OSRM origin in sync
  /// with real movement. OSRM + ETA fetches are memoised at 4-dp (~11m) so
  /// this rate doesn't translate into network traffic 1:1.
  static const Duration _riderTrackInterval = Duration(seconds: 10);

  /// Total duration of the polyline "draw-on" reveal animation.
  static const Duration _routeAnimDuration = Duration(milliseconds: 800);
  static const Duration _routeAnimTick = Duration(milliseconds: 16);

  Timer? _pollTimer;
  Timer? _riderTrackTimer;
  Timer? _routeAnimTimer;
  Stopwatch? _routeAnimClock;
  bool _isForeground = true;

  int _routeRequestSeq = 0;
  int _etaRequestSeq = 0;
  String? _lastRouteKey;
  int? _lastRouteTargetId;
  String? _lastEtaKey;

  Worker? _jobsWorker;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _loadCache().then((_) => refreshToday());
    _startPolling();
    _startRiderTracking();

    // Recompute ETA + route whenever the jobs list changes (refresh, accept,
    // finish, sync). Both are cheap if memoised by (rider, target).
    _jobsWorker = ever<List<DispatchJob>>(jobs, _onJobsChanged);

    // Kick off a one-shot rider fix so the initial overview centres on the
    // user instead of falling back to Manila.
    refreshRiderPosition();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _stopRiderTracking();
    _stopRouteAnim();
    _jobsWorker?.dispose();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isForeground;
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      if (!wasForeground) refreshToday();
      _startPolling();
      _startRiderTracking();
    } else {
      _stopPolling();
      _stopRiderTracking();
    }
  }

  // ---- Selection ------------------------------------------------------------

  /// Called when the user taps a job card. Returns false if the job has no
  /// coordinates (caller should surface a notice).
  bool selectJob(DispatchJob job) {
    if (job.lat == null || job.lng == null) return false;
    selectedJobId.value = job.id;
    // Don't blank the polyline — keep the old one visible until the new fetch
    // lands so the user never sees a flash of routeless map. The animate-vs-
    // snap decision in [_maybeFetchRoute] uses target-id, not nullness.
    _lastEtaKey = null;
    etaMeters.value = null;
    followRider.value = false;
    fetchDetail(job.id);
    refreshRiderPosition().then((_) => _maybeFetchRoute());
    return true;
  }

  void clearSelection() {
    selectedJobId.value = null;
    _lastEtaKey = null;
    etaMeters.value = null;
    followRider.value = false;
    // Returning to overview — recompute ETA + route. The existing polyline
    // stays visible until the new one lands; _maybeFetchRoute will animate
    // only if the *target* changes (not on rider drift).
    unawaited(_maybeFetchEta());
    unawaited(_maybeFetchRoute());
  }

  /// Pins the camera onto the rider and keeps it there as the silent GPS poll
  /// updates [riderPos]. Cleared next time the user picks a job.
  Future<void> recenterOnRider() async {
    followRider.value = true;
    await refreshRiderPosition(force: true);
  }

  // ---- Rider tracking -------------------------------------------------------

  void _startRiderTracking() {
    _riderTrackTimer?.cancel();
    _riderTrackTimer = Timer.periodic(_riderTrackInterval, (_) {
      if (!_isForeground) return;
      refreshRiderPosition(force: true, silent: true);
    });
  }

  void _stopRiderTracking() {
    _riderTrackTimer?.cancel();
    _riderTrackTimer = null;
  }

  /// One-shot rider fix. Deliberately *not* a position-stream subscription —
  /// every emission would invalidate the map widget's ValueKey and tear down
  /// the native view, which crashes on lower-end devices.
  Future<void> refreshRiderPosition({
    bool force = false,
    bool silent = false,
  }) async {
    if (locating.value && !silent) return;
    if (!force && riderPos.value != null) return;
    if (!silent) locating.value = true;
    try {
      if (riderPos.value == null) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          riderPos.value = GeoPoint(last.latitude, last.longitude);
        }
      }
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      riderPos.value = GeoPoint(fresh.latitude, fresh.longitude);
    } catch (_) {
      // Permission / timeout — leave whatever we already had.
    } finally {
      if (!silent) locating.value = false;
    }
    unawaited(_maybeFetchRoute());
    if (selectedJobId.value == null) {
      unawaited(_maybeFetchEta());
    }
  }

  // ---- OSRM ----------------------------------------------------------------

  void _onJobsChanged(List<DispatchJob> list) {
    // Drop selection if the previously-selected job has been finished.
    final sid = selectedJobId.value;
    if (sid != null && !list.any((j) => j.id == sid && !j.isFinished)) {
      selectedJobId.value = null;
    }
    _maybeFetchEta();
    _maybeFetchRoute();
  }

  /// The stop the rider is currently heading to: on-the-way job if any
  /// (accepts are sequential, so at most one), else the first non-reschedule
  /// assigned job.
  DispatchJob? _etaTarget() {
    final list = jobs.where((j) => !j.isFinished).toList();
    return list.firstWhereOrNull((j) => j.isOnTheWay) ??
        list.firstWhereOrNull((j) => !j.isReschedulePending);
  }

  Future<void> _maybeFetchRoute() async {
    final rider = riderPos.value;
    if (rider == null) return;
    // Target = focused job if selected and active, else the on-the-way job so
    // the route stays drawn whenever there's work in progress even with the
    // panel closed.
    final sid = selectedJobId.value;
    DispatchJob? job;
    if (sid != null) {
      job = jobs.firstWhereOrNull((j) => j.id == sid && !j.isFinished);
    }
    job ??= jobs.firstWhereOrNull((j) => j.isOnTheWay);
    if (job == null || job.lat == null || job.lng == null) {
      // No target — clear any stale polyline only in overview (focused mode
      // is awaiting the new target's route and will overwrite shortly).
      if (selectedJobId.value == null) {
        routePoints.value = null;
        routeRevealCount.value = 0;
        _stopRouteAnim();
        _lastRouteKey = null;
        _lastRouteTargetId = null;
      }
      return;
    }
    final targetId = job.id;
    final key = '${rider.lat.toStringAsFixed(4)},'
        '${rider.lng.toStringAsFixed(4)}->$targetId';
    if (key == _lastRouteKey) return;
    _lastRouteKey = key;

    final seq = ++_routeRequestSeq;
    try {
      final result =
          await _osrm.route([rider, GeoPoint(job.lat!, job.lng!)]);
      if (seq != _routeRequestSeq) return;
      final stillCurrent = selectedJobId.value != null
          ? selectedJobId.value == targetId
          : (jobs.firstWhereOrNull((j) => j.isOnTheWay)?.id == targetId);
      if (!stillCurrent) return;
      final pts = result?.points;
      // Animate-vs-snap rule: animate on *target change* (different job, or
      // first appearance). Snap on rider-drift refetches against the same
      // target, otherwise the line looks like it keeps redrawing itself.
      final targetChanged = _lastRouteTargetId != targetId;
      _lastRouteTargetId = targetId;
      routePoints.value = pts;
      if (result != null) etaMeters.value = result.distanceMeters;
      if (pts != null && pts.length >= 2) {
        if (targetChanged) {
          routeRevealCount.value = 2;
          _startRouteAnim(pts.length);
        } else {
          _stopRouteAnim();
          routeRevealCount.value = pts.length;
        }
      }
    } catch (_) {
      if (seq != _routeRequestSeq) return;
      // Leave routePoints as-is so the user keeps seeing the last good route.
    }
  }

  Future<void> _maybeFetchEta() async {
    if (selectedJobId.value != null) return; // covered by _maybeFetchRoute
    final rider = riderPos.value;
    if (rider == null) return;
    final target = _etaTarget();
    if (target == null || target.lat == null || target.lng == null) {
      etaMeters.value = null;
      _lastEtaKey = null;
      return;
    }
    final key = '${rider.lat.toStringAsFixed(4)},'
        '${rider.lng.toStringAsFixed(4)}->${target.id}';
    if (key == _lastEtaKey && etaMeters.value != null) return;
    _lastEtaKey = key;

    final seq = ++_etaRequestSeq;
    try {
      final result = await _osrm.route(
        [rider, GeoPoint(target.lat!, target.lng!)],
      );
      if (seq != _etaRequestSeq) return;
      if (selectedJobId.value != null) return;
      if (_etaTarget()?.id != target.id) return;
      etaMeters.value = result?.distanceMeters;
    } catch (_) {
      // Leave previous value in place.
    }
  }

  // ---- Route reveal animation ----------------------------------------------

  void _startRouteAnim(int totalPoints) {
    _stopRouteAnim();
    _routeAnimClock = Stopwatch()..start();
    _routeAnimTimer = Timer.periodic(_routeAnimTick, (_) {
      final elapsed = _routeAnimClock?.elapsedMilliseconds ?? 0;
      final t = (elapsed / _routeAnimDuration.inMilliseconds).clamp(0.0, 1.0);
      final target = (totalPoints * t).round().clamp(2, totalPoints);
      if (target != routeRevealCount.value) {
        routeRevealCount.value = target;
      }
      if (t >= 1.0) _stopRouteAnim();
    });
  }

  void _stopRouteAnim() {
    _routeAnimTimer?.cancel();
    _routeAnimTimer = null;
    _routeAnimClock?.stop();
    _routeAnimClock = null;
  }

  // ---- Polling --------------------------------------------------------------

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
            'meter_number': j.meterNumber,
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
    String? meterNumber,
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
        meterNumber: meterNumber,
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
          meterNumber: meterNumber,
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
