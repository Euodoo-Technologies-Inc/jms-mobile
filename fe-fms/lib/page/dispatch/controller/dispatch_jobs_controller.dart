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

  /// Live compass heading of the rider in degrees clockwise from north, used
  /// to orient the driver marker on the map. `null` until a usable GPS bearing
  /// arrives. GPS bearing is only meaningful while moving, so this is held
  /// across stationary fixes rather than snapped back to an arbitrary value.
  final RxnDouble riderHeading = RxnDouble();

  /// When true, the map center continuously tracks the live [riderPos] (the
  /// "center on me" follow mode). Cleared on selection changes.
  final RxBool followRider = false.obs;

  /// Bumped every time the user taps "center on me". The map widget treats a
  /// change in this value as an explicit re-snap request — needed because
  /// neither [followRider] nor [riderPos] necessarily change between taps
  /// (e.g. the user pinched to zoom out without us knowing), so the widget's
  /// center/zoom props would otherwise look identical and skip the animation.
  final RxInt recenterTick = 0.obs;

  /// Road-following polyline from rider → navigation target. `null` means no
  /// route yet / fetch failed — the polyline is hidden entirely.
  final Rxn<List<GeoPoint>> routePoints = Rxn<List<GeoPoint>>();

  /// Drive distance (meters) from rider to the current target. Drives the
  /// "12 min away" label on the active card.
  final RxnDouble etaMeters = RxnDouble();

  /// Number of polyline points currently revealed, used to animate the line
  /// "drawing" from rider towards the job once OSRM data arrives.
  final RxInt routeRevealCount = 0.obs;

  /// When true, the map shows every unfinished job pin framed together with a
  /// single multi-stop polyline threading them in route order — a quick
  /// "here's the whole day" preview. A plain UI toggle, not persisted.
  final RxBool routePreview = false.obs;

  /// Multi-stop polyline for [routePreview], threading all job stops in route
  /// order. `null` while the preview is off or its fetch hasn't landed.
  final Rxn<List<GeoPoint>> previewRoutePoints = Rxn<List<GeoPoint>>();

  /// Number of [previewRoutePoints] currently revealed — animates the preview
  /// line "drawing" from the first stop through to the last.
  final RxInt previewRevealCount = 0.obs;

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

  /// Longer reveal for the all-jobs preview — it spans the whole day's route,
  /// so it draws stop-by-stop over a more deliberate beat.
  static const Duration _previewAnimDuration = Duration(milliseconds: 1700);

  Timer? _pollTimer;
  Timer? _riderTrackTimer;
  Timer? _routeAnimTimer;
  Stopwatch? _routeAnimClock;
  Timer? _previewAnimTimer;
  Stopwatch? _previewAnimClock;
  bool _isForeground = true;

  int _routeRequestSeq = 0;
  int _etaRequestSeq = 0;
  int _previewRequestSeq = 0;
  String? _lastRouteKey;
  int? _lastRouteTargetId;
  String? _lastEtaKey;

  /// Signature of the stops currently used by the all-jobs preview line. Re-
  /// fetching OSRM is skipped when the new jobs list produces the same
  /// signature — only a job added / removed / finished / re-ordered should
  /// redraw the preview (per user feedback). Without this, every periodic
  /// `/jobs/today` refresh re-fetched and re-assigned the polyline, briefly
  /// blanking the line on screen.
  String? _lastPreviewKey;

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
    _stopPreviewAnim();
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
    // Focusing a single job exits the all-jobs route preview.
    if (routePreview.value) {
      routePreview.value = false;
      _clearPreview();
    }
    selectedJobId.value = job.id;
    debugPrint('[sel] selectJob(${job.id})');
    // Don't blank the polyline — keep the old one visible until the new fetch
    // lands so the user never sees a flash of routeless map. Likewise keep the
    // last ETA distance on the card; nulling it here is what made the distance
    // flicker. _maybeFetchRoute overwrites it with the new target's distance.
    _lastEtaKey = null;
    followRider.value = false;
    fetchDetail(job.id);
    refreshRiderPosition().then((_) => _maybeFetchRoute());
    return true;
  }

  void clearSelection() {
    debugPrint('[sel] clearSelection() called');
    selectedJobId.value = null;
    _lastEtaKey = null;
    followRider.value = false;
    // Returning to overview — recompute ETA + route. The existing polyline
    // stays visible until the new one lands; _maybeFetchRoute will animate
    // only if the *target* changes (not on rider drift).
    unawaited(_maybeFetchEta());
    unawaited(_maybeFetchRoute());
  }

  /// Recenters the map. With a job focused this re-frames the rider→job route
  /// (the user may have panned the map away); in the overview it pins the
  /// camera onto the rider and follows it as the silent GPS poll updates
  /// [riderPos].
  Future<void> recenterOnRider() async {
    // Recenter exits route preview either way.
    if (routePreview.value) {
      routePreview.value = false;
      _clearPreview();
    }
    // Follow-the-rider only in the overview. With a job focused, leaving
    // [followRider] false keeps the focused map data's route bounds — and the
    // bumped [recenterTick] makes the map re-fit them.
    followRider.value = selectedJobId.value == null;
    recenterTick.value++;
    await refreshRiderPosition(force: true);
  }

  /// Flips the all-jobs route preview. Turning it on drops any focused
  /// selection (the preview frames every stop) and fetches the multi-stop
  /// polyline; turning it off clears that polyline.
  Future<void> toggleRoutePreview() async {
    routePreview.value = !routePreview.value;
    debugPrint('[sel] toggleRoutePreview -> ${routePreview.value}');
    if (routePreview.value) {
      selectedJobId.value = null;
      followRider.value = false;
      await _fetchPreviewRoute(animate: true);
    } else {
      _clearPreview();
    }
  }

  /// Fetches a single OSRM route threading every unfinished, geocoded job in
  /// route order. Leaves [previewRoutePoints] null when there are fewer than
  /// two routable stops (nothing to connect).
  Future<void> _fetchPreviewRoute({bool animate = false}) async {
    final stops = jobs
        .where((j) => !j.isFinished && j.lat != null && j.lng != null)
        .toList()
      ..sort((a, b) => (a.routeOrder ?? 1 << 30)
          .compareTo(b.routeOrder ?? 1 << 30));
    if (stops.length < 2) {
      // A transient "no stops" — typically a refresh tick where coordinates
      // haven't landed yet — must NOT blank an already-drawn preview line.
      // Only the explicit toggle-off path (`_clearPreview` called directly
      // from `toggleRoutePreview`) is allowed to wipe the polyline.
      debugPrint(
          '[preview] skip: only ${stops.length} routable stop(s) (keep current)');
      if (animate && previewRoutePoints.value == null) _clearPreview();
      return;
    }
    // Skip the fetch when the stop set hasn't actually changed — a periodic
    // `/jobs/today` refresh produces a new list object every tick, but unless
    // a job was added / finished / re-ordered, the preview line is identical
    // and reassigning it would visibly flicker the polyline. `animate: true`
    // overrides this so an explicit user toggle always plays the reveal.
    final key = stops
        .map((j) =>
            '${j.id}:${j.routeOrder ?? -1}:${j.lat}:${j.lng}:${j.status ?? -1}')
        .join('|');
    if (!animate && key == _lastPreviewKey && previewRoutePoints.value != null) {
      debugPrint('[preview] skip: stop set unchanged');
      return;
    }
    _lastPreviewKey = key;
    final waypoints =
        stops.map((j) => GeoPoint(j.lat!, j.lng!)).toList();
    final seq = ++_previewRequestSeq;
    debugPrint('[preview] fetching OSRM for ${waypoints.length} stops');
    try {
      final result = await _osrm.route(waypoints);
      if (seq != _previewRequestSeq || !routePreview.value) {
        debugPrint('[preview] stale/cancelled response ignored');
        return;
      }
      final pts = result?.points;
      if (pts == null || pts.length < 2) {
        debugPrint('[preview] OSRM returned no usable polyline');
        _clearPreview();
        return;
      }
      debugPrint('[preview] OK: ${pts.length} pts');
      previewRoutePoints.value = pts;
      if (animate) {
        // Draw the line on — stop by stop, in route order.
        previewRevealCount.value = 2;
        _startPreviewAnim(pts.length);
      } else {
        // A silent refetch (jobs changed) — snap to the full line.
        _stopPreviewAnim();
        previewRevealCount.value = pts.length;
      }
    } catch (e) {
      // Leave the preview line absent — the job pins still frame together.
      debugPrint('[preview] OSRM fetch FAILED: $e');
    }
  }

  /// Clears the all-jobs preview line and its reveal animation.
  void _clearPreview() {
    _stopPreviewAnim();
    previewRevealCount.value = 0;
    previewRoutePoints.value = null;
    // Forget the stop signature so the next toggle-on always refetches.
    _lastPreviewKey = null;
  }

  /// Reveals [previewRoutePoints] progressively — the line draws itself from
  /// the first stop through to the last.
  void _startPreviewAnim(int totalPoints) {
    _stopPreviewAnim();
    _previewAnimClock = Stopwatch()..start();
    _previewAnimTimer = Timer.periodic(_routeAnimTick, (_) {
      final elapsed = _previewAnimClock?.elapsedMilliseconds ?? 0;
      final t =
          (elapsed / _previewAnimDuration.inMilliseconds).clamp(0.0, 1.0);
      final target = (totalPoints * t).round().clamp(2, totalPoints);
      if (target != previewRevealCount.value) {
        previewRevealCount.value = target;
      }
      if (t >= 1.0) _stopPreviewAnim();
    });
  }

  void _stopPreviewAnim() {
    _previewAnimTimer?.cancel();
    _previewAnimTimer = null;
    _previewAnimClock?.stop();
    _previewAnimClock = null;
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
  ///
  /// Fires the OSRM + ETA fetches as soon as a *last-known* position is
  /// available, without waiting for the (up to 6s) fresh-fix call. Last-known
  /// is the rider's real coordinates from the most recent GPS sample the OS
  /// recorded — not stale in the misleading sense, just slightly older. The
  /// 4-dp memo key (~11m grid) means the fresh-fix refetch is usually a no-op.
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
          _updateHeading(last);
          // Don't wait for the fresh-fix — kick OSRM + ETA off the last-known
          // position so the polyline can render in ~one network round trip
          // instead of (GPS_timeout + network).
          unawaited(_maybeFetchRoute());
          if (selectedJobId.value == null) {
            unawaited(_maybeFetchEta());
          }
        }
      }
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      riderPos.value = GeoPoint(fresh.latitude, fresh.longitude);
      _updateHeading(fresh);
    } catch (_) {
      // Permission / timeout — leave whatever we already had.
    } finally {
      if (!silent) locating.value = false;
    }
    // Second pass with the fresh fix. If the rider hasn't moved more than
    // ~11m the memo key matches and these are cheap no-ops; otherwise the
    // polyline updates in place (no reveal-animation replay).
    unawaited(_maybeFetchRoute());
    if (selectedJobId.value == null) {
      unawaited(_maybeFetchEta());
    }
  }

  /// Updates [riderHeading] from a GPS fix. A GPS bearing is only reliable
  /// while the device is actually moving — below a walking-pace threshold the
  /// reported bearing is noise, so we keep the last good heading instead of
  /// letting the marker spin in place.
  void _updateHeading(Position p) {
    if (p.speed >= 0.7 && p.heading >= 0 && p.heading <= 360) {
      riderHeading.value = p.heading;
    }
  }

  // ---- OSRM ----------------------------------------------------------------

  void _onJobsChanged(List<DispatchJob> list) {
    // Drop the selection only when the previously-selected job is *present and
    // finished*. A job momentarily missing from a refreshed list (a transient
    // API hiccup) must not collapse the focused panel on its own.
    final sid = selectedJobId.value;
    if (sid != null) {
      final sel = list.firstWhereOrNull((j) => j.id == sid);
      if (sel != null && sel.isFinished) {
        debugPrint('[sel] cleared: job $sid is finished');
        selectedJobId.value = null;
      }
    }
    _maybeFetchEta();
    _maybeFetchRoute();
    // Keep the all-jobs preview line in sync as jobs are added / finished.
    if (routePreview.value) _fetchPreviewRoute();
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
    if (rider == null) {
      debugPrint('[route] skip: rider position is null');
      return;
    }
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
      debugPrint('[route] skip: no target job (selected=$sid)');
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
    if (key == _lastRouteKey) {
      debugPrint('[route] skip: memo hit ($key)');
      return;
    }
    _lastRouteKey = key;
    debugPrint('[route] fetching OSRM for job $targetId ($key)');

    final seq = ++_routeRequestSeq;
    try {
      final result =
          await _osrm.route([rider, GeoPoint(job.lat!, job.lng!)]);
      if (seq != _routeRequestSeq) {
        debugPrint('[route] stale response ignored');
        return;
      }
      final stillCurrent = selectedJobId.value != null
          ? selectedJobId.value == targetId
          : (jobs.firstWhereOrNull((j) => j.isOnTheWay)?.id == targetId);
      if (!stillCurrent) {
        debugPrint('[route] target changed mid-flight, ignoring');
        return;
      }
      final pts = result?.points;
      if (pts == null || pts.length < 2) {
        // Upstream gave us nothing usable. Clear the memo so the next poll
        // retries instead of leaving the route blank forever for a rider who
        // hasn't moved — and keep the last good polyline on screen.
        _lastRouteKey = null;
        debugPrint('[route] OSRM returned no usable polyline '
            '(result=${result == null ? 'null' : '${result.points.length} pts'})');
        return;
      }
      // Animate-vs-snap rule: animate on *target change* (different job, or
      // first appearance). Snap on rider-drift refetches against the same
      // target, otherwise the line looks like it keeps redrawing itself.
      final targetChanged = _lastRouteTargetId != targetId;
      _lastRouteTargetId = targetId;
      routePoints.value = pts;
      etaMeters.value = result!.distanceMeters;
      if (targetChanged) {
        routeRevealCount.value = 2;
        _startRouteAnim(pts.length);
      } else {
        _stopRouteAnim();
        routeRevealCount.value = pts.length;
      }
      debugPrint('[route] OK: ${pts.length} pts, routePoints set, '
          'revealCount=${routeRevealCount.value}');
    } catch (e) {
      if (seq != _routeRequestSeq) return;
      // Transient failure (network / rate-limited demo OSRM). Clear the memo
      // so the next tick retries — otherwise a stationary rider never sees the
      // route come back. Keep any existing polyline visible meanwhile.
      _lastRouteKey = null;
      debugPrint('[route] OSRM fetch FAILED for job $targetId: $e');
    }
  }

  Future<void> _maybeFetchEta() async {
    if (selectedJobId.value != null) return; // covered by _maybeFetchRoute
    final rider = riderPos.value;
    if (rider == null) return;
    final target = _etaTarget();
    if (target == null || target.lat == null || target.lng == null) {
      // Keep the last distance on the card — a momentarily un-geocoded target
      // (a backend geocoding race) must not blank a perfectly good estimate.
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
      final meters = result?.distanceMeters;
      if (meters != null) {
        etaMeters.value = meters;
      } else {
        // OSRM returned nothing usable (rate-limited demo server / no route).
        // Keep the last good distance on the card and clear the memo so the
        // next poll retries, rather than blanking the estimate.
        _lastEtaKey = null;
      }
    } catch (_) {
      // Transient failure — leave the previous value in place and retry.
      _lastEtaKey = null;
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
    final startedAt = DateTime.now();
    final key = await DispatchIdempotencyStore.getOrCreate(
      action: _startAction,
      jobId: jobId,
    );
    try {
      final updated = await _ds.startJob(
        jobId,
        idempotencyKey: key,
        startedAt: startedAt,
      );
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
        await Get.find<DispatchSyncService>()
            .enqueueStart(jobId, startedAt: startedAt);
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
    final finishedAt = DateTime.now();
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
        finishedAt: finishedAt,
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
          finishedAt: finishedAt,
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
