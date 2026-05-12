import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_format.dart';
import '../../../core/dispatch/dispatch_navigation.dart';
import '../../../core/models/geo.dart';
import '../../../core/widgets/adaptive_map.dart';
import '../../../data/dispatch/datasource/dispatch_osrm_datasource.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../controller/dispatch_jobs_controller.dart';
import '../service/dispatch_sync_service.dart';
import 'dispatch_finish_job_page.dart';
import 'dispatch_profile_page.dart';

const GeoPoint _kFallbackCenter = GeoPoint(14.5995, 120.9842); // Manila
const Duration _kPanelAnim = Duration(milliseconds: 320);

/// Map of today's jobs with a horizontal carousel at the bottom. Tapping a
/// card promotes that job into a focused detail panel covering the bottom
/// half, while the map switches to "rider position → job" with a route line.
class DispatchJobsPage extends StatefulWidget {
  const DispatchJobsPage({super.key});

  @override
  State<DispatchJobsPage> createState() => _DispatchJobsPageState();
}

class _DispatchJobsPageState extends State<DispatchJobsPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Cadence for the silent foreground GPS poll that keeps the rider pin
  /// and route source point in sync as the driver moves. The OSRM + ETA
  /// fetches are memoised at 4-dp (~11m) so this rate doesn't translate
  /// into network traffic 1:1.
  static const Duration _riderTrackInterval = Duration(seconds: 10);
  Timer? _riderTrackTimer;
  bool _isForeground = true;
  final RxnInt _selectedId = RxnInt();
  final Rxn<GeoPoint> _riderPos = Rxn<GeoPoint>();
  final RxBool _locating = false.obs;
  final RxBool _starting = false.obs;

  /// When true, the map center continuously tracks the live `_riderPos`
  /// instead of using the focus/overview natural framing. Toggled on by the
  /// "center on me" FAB so the camera follows the rider as they move,
  /// rather than freezing at a snapshot. Cleared on selection changes so
  /// natural framing returns.
  final RxBool _followRider = false.obs;

  /// Road-following polyline from rider → focused job, fetched via the
  /// backend OSRM proxy. `null` means "no route yet / fetch failed" — the
  /// polyline is then hidden entirely (we don't draw a misleading straight
  /// line).
  final Rxn<List<GeoPoint>> _routePoints = Rxn<List<GeoPoint>>();

  /// Drive-time (seconds) from the rider to whichever job the carousel marks
  /// as the next/active stop. Drives the "12 min away" label on that card.
  final RxnDouble _etaMeters = RxnDouble();
  int _etaRequestSeq = 0;
  String? _lastEtaKey;
  Worker? _jobsListenWorker;

  /// Number of polyline points currently revealed, used to animate the line
  /// "drawing" from rider towards the job once OSRM data arrives.
  final RxInt _routeRevealCount = 0.obs;
  late final AnimationController _routeAnim;

  final DispatchOsrmDatasource _osrm = DispatchOsrmDatasource();
  int _routeRequestSeq = 0;
  String? _lastRouteKey;

  late final DispatchJobsController _jobsCtrl;

  @override
  void initState() {
    super.initState();
    _jobsCtrl = Get.put(DispatchJobsController());

    _routeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(_onRouteTick);

    WidgetsBinding.instance.addObserver(this);
    _startRiderTracking();

    // Recompute the carousel ETA and the active-job route whenever the
    // jobs list changes (refresh, accept, finish, etc). Both are cheap if
    // memoised by (rider, target).
    _jobsListenWorker = ever<List<DispatchJob>>(
      _jobsCtrl.jobs,
      (jobs) {
        // Drop selection if the previously-selected job has been finished
        // (status=2). Without this, _maybeFetchRoute would keep using the
        // finished job as a target and the polyline would linger on the
        // map even though there's no active work.
        final sid = _selectedId.value;
        if (sid != null &&
            !jobs.any((j) => j.id == sid && !j.isFinished)) {
          _selectedId.value = null;
        }
        _maybeFetchEta();
        _maybeFetchRoute();
      },
    );

    // Kick off a one-shot rider fix so the initial overview centers on the
    // user instead of the first job / Manila fallback.
    _refreshRiderPosition();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRiderTracking();
    _jobsListenWorker?.dispose();
    _routeAnim
      ..removeListener(_onRouteTick)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isForeground;
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground && !wasForeground) {
      _startRiderTracking();
    } else if (!_isForeground && wasForeground) {
      _stopRiderTracking();
    }
  }

  /// Begins a low-frequency, silent GPS poll so the rider marker + route
  /// origin track real movement. Each tick passes `force: true, silent: true`
  /// — `force` defeats the "already have a fix" short-circuit, `silent`
  /// keeps the recenter FAB from flashing its spinner every interval.
  void _startRiderTracking() {
    _riderTrackTimer?.cancel();
    _riderTrackTimer = Timer.periodic(_riderTrackInterval, (_) {
      if (!_isForeground || !mounted) return;
      _refreshRiderPosition(force: true, silent: true);
    });
  }

  void _stopRiderTracking() {
    _riderTrackTimer?.cancel();
    _riderTrackTimer = null;
  }

  /// Drives the "draw-the-line" reveal — maps the animation's 0..1 value to a
  /// growing prefix of the OSRM polyline and pushes that count into the Rx so
  /// the map's Obx rebuilds with one more segment at a time.
  void _onRouteTick() {
    final pts = _routePoints.value;
    if (pts == null || pts.length < 2) return;
    final target =
        (pts.length * _routeAnim.value).round().clamp(2, pts.length);
    if (target != _routeRevealCount.value) {
      _routeRevealCount.value = target;
    }
  }

  /// One-shot rider fix. We deliberately do NOT subscribe to the position
  /// stream here — every emission would invalidate the map's ValueKey and
  /// tear down the native GoogleMap view, which crashes on lower-end devices.
  /// The user can hit the recenter FAB to refresh.
  Future<void> _refreshRiderPosition({
    bool force = false,
    bool silent = false,
  }) async {
    if (_locating.value && !silent) return;
    if (!force && _riderPos.value != null) return;
    if (!silent) _locating.value = true;
    try {
      if (_riderPos.value == null) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _riderPos.value = GeoPoint(last.latitude, last.longitude);
        }
      }
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      _riderPos.value = GeoPoint(fresh.latitude, fresh.longitude);
    } catch (_) {
      // Permission / timeout — leave whatever we already had. Panel will just
      // skip the route line.
    } finally {
      if (!silent) _locating.value = false;
    }
    // Route + ETA both depend on rider position. Always try both — the
    // route fetch is a no-op when there is no target.
    unawaited(_maybeFetchRoute());
    if (_selectedId.value == null) {
      unawaited(_maybeFetchEta());
    }
  }

  void _select(DispatchJob job) {
    if (job.lat == null || job.lng == null) {
      Get.snackbar(
        'No location',
        'This job has no coordinates yet.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    _selectedId.value = job.id;
    _routePoints.value = null;
    _routeRevealCount.value = 0;
    _routeAnim.stop();
    _lastRouteKey = null;
    _lastEtaKey = null;
    _etaMeters.value = null;
    _followRider.value = false;
    _refreshRiderPosition().then((_) => _maybeFetchRoute());
    _jobsCtrl.fetchDetail(job.id);
  }

  void _clearSelection() {
    _selectedId.value = null;
    _lastRouteKey = null;
    _lastEtaKey = null;
    _etaMeters.value = null;
    _followRider.value = false;
    // Returning to overview — recompute the carousel ETA, and re-fetch the
    // route in case the previously-focused job wasn't the active one (so
    // the polyline can switch to the on-the-way target). The existing
    // polyline stays visible until the new one lands.
    unawaited(_maybeFetchEta());
    unawaited(_maybeFetchRoute());
  }

  /// Pins the camera onto the rider and *keeps* it there as the silent GPS
  /// poller updates `_riderPos`. The previous implementation stashed a
  /// one-shot snapshot, so the camera stopped following after the first
  /// tap — switching to a follow-mode flag means subsequent ticks pan the
  /// camera with the rider until the rider picks a job again.
  Future<void> _recenterOnRider() async {
    _followRider.value = true;
    await _refreshRiderPosition(force: true);
  }

  /// Fetches a road-following polyline from rider → the navigation target
  /// (selected job, or the active on-the-way job when no card is focused)
  /// via the backend OSRM proxy. Memoised per (rider 4-dp, job id) so
  /// position pings don't refetch on every meter of drift. Silently leaves
  /// the existing polyline in place on any error.
  Future<void> _maybeFetchRoute() async {
    final rider = _riderPos.value;
    if (rider == null) return;
    // Target = focused job → otherwise the active job so the route stays
    // drawn whenever the rider has work in progress, even if the detail
    // panel is closed. Finished jobs (status=2) are never valid targets —
    // their polyline must clear the moment the job completes.
    final selectedId = _selectedId.value;
    DispatchJob? job;
    if (selectedId != null) {
      job = _jobsCtrl.jobs.firstWhereOrNull(
        (j) => j.id == selectedId && !j.isFinished,
      );
    }
    job ??= _jobsCtrl.jobs.firstWhereOrNull((j) => j.isOnTheWay);
    if (job == null || job.lat == null || job.lng == null) {
      // No target — make sure stale polylines don't linger after the rider
      // finishes the active job.
      if (_selectedId.value == null) {
        _routePoints.value = null;
        _routeRevealCount.value = 0;
        _routeAnim.stop();
        _lastRouteKey = null;
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
      // Discard if a newer fetch raced ahead or the user switched target.
      if (!mounted) return;
      if (seq != _routeRequestSeq) return;
      // Validate the target is still current (still selected, or still the
      // active job in overview).
      final stillCurrent = _selectedId.value != null
          ? _selectedId.value == targetId
          : (_jobsCtrl.jobs.firstWhereOrNull((j) => j.isOnTheWay)?.id ==
              targetId);
      if (!stillCurrent) return;
      final pts = result?.points;
      // Only animate the "drawing out" effect on the *initial* appearance
      // of a route. While the rider is moving the polyline gets refetched
      // every ~11m crossing — replaying the reveal animation each time
      // makes the line look like it keeps redrawing itself, which a real
      // navigation app never does. Subsequent refreshes snap the reveal
      // count to full so the polyline just updates in place.
      final hadRoute = _routePoints.value != null;
      _routePoints.value = pts;
      // The OSRM round-trip also gives us the road distance — reuse it for
      // the carousel "850 m / 1.5 km away" label.
      if (result != null) _etaMeters.value = result.distanceMeters;
      if (pts != null && pts.length >= 2) {
        if (hadRoute) {
          _routeAnim.stop();
          _routeRevealCount.value = pts.length;
        } else {
          _routeRevealCount.value = 2;
          _routeAnim
            ..stop()
            ..forward(from: 0);
        }
      }
    } catch (_) {
      if (!mounted) return;
      if (seq != _routeRequestSeq) return;
      // Leave _routePoints null → polyline hidden.
    }
  }

  /// Computes the ETA from the rider to whichever stop is currently the
  /// "next/active" one. Runs in overview mode only (in focused mode the
  /// route fetch already supplies the same duration). Memoised by
  /// (rider 4-dp, target id) so position pings don't refetch.
  Future<void> _maybeFetchEta() async {
    if (!mounted) return;
    if (_selectedId.value != null) return; // covered by _maybeFetchRoute
    final rider = _riderPos.value;
    if (rider == null) return;
    final target = _etaTarget();
    if (target == null || target.lat == null || target.lng == null) {
      _etaMeters.value = null;
      _lastEtaKey = null;
      return;
    }
    final key = '${rider.lat.toStringAsFixed(4)},'
        '${rider.lng.toStringAsFixed(4)}->${target.id}';
    if (key == _lastEtaKey && _etaMeters.value != null) return;
    _lastEtaKey = key;

    final seq = ++_etaRequestSeq;
    try {
      final result = await _osrm.route(
        [rider, GeoPoint(target.lat!, target.lng!)],
      );
      if (!mounted) return;
      if (seq != _etaRequestSeq) return;
      if (_selectedId.value != null) return;
      if (_etaTarget()?.id != target.id) return;
      _etaMeters.value = result?.distanceMeters;
    } catch (_) {
      if (!mounted) return;
      if (seq != _etaRequestSeq) return;
      // Leave previous value in place.
    }
  }

  /// The stop the rider is currently heading to: an on-the-way job if there
  /// is one (since accepts are sequential, at most one), else the first
  /// assigned non-reschedule job.
  DispatchJob? _etaTarget() {
    final list = _jobsCtrl.jobs.where((j) => !j.isFinished).toList();
    return list.firstWhereOrNull((j) => j.isOnTheWay) ??
        list.firstWhereOrNull((j) => !j.isReschedulePending);
  }

  Future<void> _startJob(int jobId) async {
    _starting.value = true;
    final ctrl = _jobsCtrl;
    try {
      await ctrl.startJob(jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job accepted.')),
      );
    } on DispatchQueuedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved offline. Will sync when online.'),
          backgroundColor: Colors.orange,
        ),
      );
    } on DispatchApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: e.isConflict ? Colors.orange : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      _starting.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's jobs"),
        actions: [
          if (Get.isRegistered<DispatchSyncService>())
            Obx(() {
              final count = Get.find<DispatchSyncService>().pendingCount.value;
              if (count == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  child: Tooltip(
                    message: '$count action(s) pending sync',
                    child: Chip(
                      avatar: const Icon(Icons.sync, size: 14),
                      label: Text('$count'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              );
            }),
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Get.to(() => const DispatchProfilePage()),
          ),
        ],
      ),
      body: SafeArea(
        child: Obx(() {
          // Top-level Obx: only top-of-tree state (loading / error / empty /
          // stale). Map + panel have their own scoped Obx so they don't
          // rebuild on unrelated state changes.
          if (_jobsCtrl.isLoading.value && _jobsCtrl.jobs.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_jobsCtrl.error.value != null && _jobsCtrl.jobs.isEmpty) {
            return _ErrorState(
              message: _jobsCtrl.error.value ?? 'Failed to load',
              onRetry: _jobsCtrl.refreshToday,
            );
          }
          // Note: we deliberately don't bail to an _EmptyState when there
          // are no active jobs — the rider still wants to see the map with
          // their own location. The carousel itself renders a single
          // "No jobs available" placeholder card instead.

          return Column(
            children: [
              if (_jobsCtrl.isStale.value)
                _StaleBanner(
                  message:
                      _jobsCtrl.error.value ?? 'Showing cached jobs.',
                  onRetry: _jobsCtrl.refreshToday,
                ),
              // Map fills the remaining space; the bottom panel floats over
              // it via a Stack so panel resizes (Accept → Finish, etc.) never
              // change the map's parent size. GoogleMap's native view goes
              // blank-until-interaction when its size changes; this avoids
              // the issue entirely.
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildMapArea()),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildBottomArea(),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }


  /// Scoped Obx around the map. Rebuilds only when selection, jobs list, or
  /// rider position changes — and even then GoogleMap survives because the
  /// ValueKey is stable per "selection mode" (all-jobs vs focused-job-id).
  Widget _buildMapArea() {
    return Stack(
      children: [
        Positioned.fill(
          child: Obx(() {
            // Hide finished jobs from the home view — they live in History.
            // Backend already excludes Status=2, but filtering client-side
            // too prevents a flicker between "user finishes" and "next
            // refresh lands".
            final jobs = _jobsCtrl.jobs.where((j) => !j.isFinished).toList();
            final selectedId = _selectedId.value;
            final selected = selectedId == null
                ? null
                : jobs.firstWhereOrNull((j) => j.id == selectedId);
            final isFocused =
                selected != null && selected.lat != null && selected.lng != null;
            final rider = _riderPos.value;
            final route = _routePoints.value;
            final reveal = _routeRevealCount.value;
            final followRider = _followRider.value;

            var mapData = isFocused
                ? _focusedMapData(selected, rider, route, reveal)
                : _overviewMapData(jobs, rider, route, reveal);
            // Follow mode forces the camera onto the live rider position
            // every rebuild — so the silent GPS poll's Rxn updates pan the
            // map automatically instead of being shadowed by a static
            // override snapshot.
            if (followRider && rider != null) {
              mapData = _MapData(
                center: rider,
                zoom: 17,
                markers: mapData.markers,
                zones: mapData.zones,
              );
            }

            return AdaptiveMap(
              // Stable key across selection changes: the underlying map
              // instance survives, and animates the camera via didUpdateWidget
              // instead of teleporting.
              key: const ValueKey('dispatchmap'),
              center: mapData.center,
              zoom: mapData.zoom,
              markers: mapData.markers,
              zones: mapData.zones,
              onMarkerTap: (m) {
                final id = m.data;
                if (id is int) {
                  final j = jobs.firstWhereOrNull((x) => x.id == id);
                  if (j != null) _select(j);
                }
              },
            );
          }),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: FloatingActionButton.small(
            heroTag: 'recenter',
            tooltip: 'Center on my location',
            onPressed: _recenterOnRider,
            child: Obx(() => _locating.value
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location)),
          ),
        ),
      ],
    );
  }

  /// Scoped Obx around the bottom area only.
  Widget _buildBottomArea() {
    return Obx(() {
      final jobs = _jobsCtrl.jobs.where((j) => !j.isFinished).toList();
      final selectedId = _selectedId.value;
      final selected = selectedId == null
          ? null
          : jobs.firstWhereOrNull((j) => j.id == selectedId);
      final isFocused = selected != null;

      // No AnimatedSize wrapper: the focused panel manages its own height for
      // drag-to-resize, and an animating parent would lag every drag frame.
      // The AnimatedSwitcher fade+slide still covers the carousel↔panel swap.
      return AnimatedSwitcher(
        duration: _kPanelAnim,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: isFocused
            ? () {
                // Strict route order: the only acceptable next job is the
                // first non-on-the-way, non-reschedule entry in the (already
                // RouteOrder-sorted) active queue. Same rule the carousel
                // uses for the "Next stop" highlight.
                final nextInQueueId = jobs
                    .firstWhereOrNull(
                        (j) => !j.isOnTheWay && !j.isReschedulePending)
                    ?.id;
                return _FocusedJobPanel(
                  key: ValueKey('panel_${selected.id}'),
                  job: selected,
                  // Same numbering rule as the carousel cards — route order if
                  // the server set it, otherwise the queue position. Keeps the
                  // panel header consistent with the card the user just tapped.
                  stopNumber: selected.routeOrder ??
                      (jobs.indexWhere((j) => j.id == selected.id) + 1),
                  // OSRM road distance — same value the card pill on this
                  // job shows, so the overview and the panel never disagree.
                  etaMeters: _etaMeters.value,
                  starting: _starting,
                  hasOtherActive: jobs.any(
                      (j) => j.isOnTheWay && j.id != selected.id),
                  isNextInQueue: selected.id == nextInQueueId,
                  onClose: _clearSelection,
                  onStart: () => _startJob(selected.id),
                  onFinish: () => Get.to(
                      () => DispatchFinishJobPage(jobId: selected.id)),
                );
              }()
            : SizedBox(
                key: const ValueKey('carousel'),
                height: 132,
                child: _JobCarousel(
                  jobs: jobs,
                  etaMeters: _etaMeters.value,
                  onSelect: _select,
                ),
              ),
      );
    });
  }

  _MapData _focusedMapData(
    DispatchJob selected,
    GeoPoint? rider,
    List<GeoPoint>? route,
    int revealCount,
  ) {
    final job = GeoPoint(selected.lat!, selected.lng!);
    final markers = <MapMarkerModel>[
      MapMarkerModel(
        id: 'job_${selected.id}',
        position: job,
        title: selected.jobName,
        subtitle: selected.address,
      ),
      if (rider != null)
        MapMarkerModel(
        id: 'rider',
        position: rider,
        title: 'You',
        kind: MapMarkerKind.rider,
      ),
    ];
    if (rider == null) {
      return _MapData(center: job, zoom: 16, markers: markers);
    }
    // Focused view always frames rider + job around their midpoint with a
    // distance-aware zoom, so the full route is visible regardless of
    // on-the-way state. The "follow the rider" behaviour for active jobs
    // lives in the overview map (panel closed), which keeps the polyline
    // drawn while centring on the rider.
    final center = GeoPoint(
      (job.lat + rider.lat) / 2,
      (job.lng + rider.lng) / 2,
    );
    final meters = Geolocator.distanceBetween(
        rider.lat, rider.lng, job.lat, job.lng);
    final zoom = _zoomForMeters(meters);
    // Draw only the revealed prefix of the OSRM polyline. revealCount grows
    // from 2 → route.length while the route-draw AnimationController runs,
    // so the line appears to extend from rider towards the job rather than
    // popping in fully formed. Nothing is drawn until OSRM returns (no
    // misleading crow-flies fallback).
    final hasRoute = route != null && route.length >= 2 && revealCount >= 2;
    final revealed = hasRoute
        ? route.sublist(0, revealCount.clamp(2, route.length))
        : const <GeoPoint>[];
    return _MapData(
      center: center,
      zoom: zoom,
      markers: markers,
      zones: hasRoute
          ? [
              MapZoneModel(
                id: 'route',
                type: MapZoneType.polyline,
                points: revealed,
                style: const MapZoneStyle(
                  strokeColorHex: '#1976D2',
                  strokeWidth: 4,
                  strokeOpacity: 0.85,
                ),
              ),
            ]
          : const [],
    );
  }

  _MapData _overviewMapData(
    List<DispatchJob> jobs,
    GeoPoint? rider,
    List<GeoPoint>? route,
    int revealCount,
  ) {
    final geoJobs =
        jobs.where((j) => j.lat != null && j.lng != null).toList();
    final markers = <MapMarkerModel>[
      ...geoJobs.map((j) => MapMarkerModel(
            id: 'job_${j.id}',
            position: GeoPoint(j.lat!, j.lng!),
            title: j.jobName,
            subtitle: j.address,
            data: j.id,
          )),
      if (rider != null)
        MapMarkerModel(
          id: 'rider',
          position: rider,
          title: 'You',
          kind: MapMarkerKind.rider,
        ),
    ];
    // Prefer rider position; otherwise fall back to first job, then Manila.
    final center = rider ??
        (geoJobs.isNotEmpty
            ? GeoPoint(geoJobs.first.lat!, geoJobs.first.lng!)
            : _kFallbackCenter);
    // While there's an active (on-the-way) job, _maybeFetchRoute keeps
    // _routePoints populated from rider → that job. Render the same
    // animated polyline in overview so the driver still sees their path
    // even with the detail panel closed.
    final hasRoute = route != null && route.length >= 2 && revealCount >= 2;
    final revealed = hasRoute
        ? route.sublist(0, revealCount.clamp(2, route.length))
        : const <GeoPoint>[];
    return _MapData(
      center: center,
      zoom: 14,
      markers: markers,
      zones: hasRoute
          ? [
              MapZoneModel(
                id: 'route',
                type: MapZoneType.polyline,
                points: revealed,
                style: const MapZoneStyle(
                  strokeColorHex: '#1976D2',
                  strokeWidth: 4,
                  strokeOpacity: 0.85,
                ),
              ),
            ]
          : const [],
    );
  }

  // Crude zoom heuristic to fit rider+job in view without a real bounds API.
  double _zoomForMeters(double m) {
    if (m < 250) return 17;
    if (m < 600) return 16;
    if (m < 1500) return 15;
    if (m < 3500) return 14;
    if (m < 8000) return 13;
    if (m < 18000) return 12;
    if (m < 40000) return 11;
    return 10;
  }
}

/// Plain value bag — keeps the build method readable.
class _MapData {
  const _MapData({
    required this.center,
    required this.zoom,
    required this.markers,
    this.zones = const [],
  });
  final GeoPoint center;
  final double zoom;
  final List<MapMarkerModel> markers;
  final List<MapZoneModel> zones;
}

class _JobCarousel extends StatelessWidget {
  const _JobCarousel({
    required this.jobs,
    required this.etaMeters,
    required this.onSelect,
  });

  final List<DispatchJob> jobs;

  /// Road distance (meters) to whichever stop the rider is heading to —
  /// shown as "850 m / 1.5 km away" on that card only. Null while OSRM
  /// hasn't responded.
  final double? etaMeters;
  final ValueChanged<DispatchJob> onSelect;

  @override
  Widget build(BuildContext context) {
    // Empty queue → render a single placeholder card. We deliberately keep
    // the map underneath visible so the rider still sees their location;
    // the carousel area just communicates "nothing assigned right now".
    if (jobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SizedBox(width: 280, child: const _EmptyJobCard()),
      );
    }
    // Jobs come back from /jobs/today already sorted by RouteOrder. The
    // "next stop" is the first assigned (not-yet-accepted) job in that
    // sequence. If a job is already on-the-way it stays the active one and
    // the *following* assigned job is the next stop.
    final nextId = jobs
        .firstWhereOrNull((j) => !j.isOnTheWay && !j.isReschedulePending)
        ?.id;
    // The ETA target is whichever stop the rider is *currently* heading
    // toward (on-the-way job if any, else the next assigned). Same logic
    // as `_etaTarget()` on the page state.
    final etaTargetId = jobs.firstWhereOrNull((j) => j.isOnTheWay)?.id ??
        nextId;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: jobs.length,
      separatorBuilder: (_, _) => const _CarouselConnector(),
      itemBuilder: (context, i) {
        final job = jobs[i];
        // Use the route order from the server when present so completed
        // stops keep their numbering (jobs 1+2 done → remaining cards
        // start at 3). Fall back to the carousel position otherwise.
        final stopNumber = job.routeOrder ?? (i + 1);
        return SizedBox(
          width: 280,
          child: _DispatchJobCard(
            job: job,
            stopNumber: stopNumber,
            selected: false,
            isNext: job.id == nextId,
            etaMeters: job.id == etaTargetId ? etaMeters : null,
            onTap: () => onSelect(job),
          ),
        );
      },
    );
  }
}

class _DispatchJobCard extends StatelessWidget {
  const _DispatchJobCard({
    required this.job,
    required this.stopNumber,
    required this.selected,
    required this.onTap,
    this.isNext = false,
    this.etaMeters,
  });

  final DispatchJob job;
  final int stopNumber;
  final bool selected;
  final bool isNext;
  /// Road distance from the rider to this stop, in meters. Non-null only on
  /// the card the rider is currently heading toward.
  final double? etaMeters;
  final VoidCallback onTap;

  // Web palette parity (assets/dispatch/dispatch.css).
  static const _kNumberBg = Color(0xFF1f2937);
  static const _kBorder = Color(0xFFe5e7eb);
  static const _kCardBg = Color(0xFFf9fafb);
  static const _kCustomer = Color(0xFF111827);
  static const _kAddress = Color(0xFF6b7280);
  static const _kMeta = Color(0xFF4b5563);
  static const _kNextBorder = Color(0xFF06b6d4);

  @override
  Widget build(BuildContext context) {
    final highlight = isNext && !job.isOnTheWay;
    final hasGeo = job.lat != null && job.lng != null;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : (highlight ? _kNextBorder : _kBorder),
              width: selected ? 2 : (highlight ? 1.5 : 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StopNumber(number: stopNumber),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            job.customer ?? job.jobName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kCustomer,
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (highlight) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward,
                              size: 14, color: _kNextBorder),
                        ],
                        if (!hasGeo) ...[
                          const SizedBox(width: 6),
                          const Tooltip(
                            message: 'No coordinates',
                            child: Icon(Icons.location_off,
                                size: 14, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                    if (job.address != null && job.address!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        job.address!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kAddress,
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _statusPill(job),
                        if (etaMeters != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '${formatTravelDistance(etaMeters!)} away',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kMeta,
                                fontSize: 11.5,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(DispatchJob job) => _JobStatusPill(job: job);
}

/// Web-palette status pill shared by the carousel cards and the focused-job
/// panel so both surfaces stay visually consistent. Colors match
/// `.dispatch-queue-status-*` from `assets/dispatch/dispatch.css`.
class _JobStatusPill extends StatelessWidget {
  const _JobStatusPill({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    if (job.isFinished) {
      bg = const Color(0xFFd1fae5);
      fg = const Color(0xFF065f46);
      label = 'Finished';
    } else if (job.isOnTheWay) {
      bg = const Color(0xFFfef3c7);
      fg = const Color(0xFF92400e);
      label = 'On the way';
    } else if (job.isReschedulePending) {
      bg = const Color(0xFFfed7aa);
      fg = const Color(0xFF9a3412);
      label = 'Reschedule';
    } else {
      bg = const Color(0xFFe5e7eb);
      fg = const Color(0xFF374151);
      label = 'Not started';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Placeholder card rendered in the carousel slot when the rider has no
/// jobs in their queue. Same visual chrome as a real `_DispatchJobCard`
/// (web palette border + radius) so the empty state feels like part of
/// the same list rather than a separate empty screen.
class _EmptyJobCard extends StatelessWidget {
  const _EmptyJobCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _DispatchJobCard._kCardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _DispatchJobCard._kBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 28,
            color: Colors.grey.shade500,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'No jobs available',
                  style: TextStyle(
                    color: _DispatchJobCard._kCustomer,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  "You're all caught up.",
                  style: TextStyle(
                    color: _DispatchJobCard._kAddress,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Solid grey line between adjacent carousel cards — expresses the
/// "stop N → stop N+1" sequence assigned by the admin. Sits horizontally
/// between two card slots, vertically centred in the carousel.
class _CarouselConnector extends StatelessWidget {
  const _CarouselConnector();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 3,
          child: DecoratedBox(
            // Darker than the previous #9ca3af so the "stop N → stop N+1"
            // bridge reads clearly even on light card backgrounds.
            decoration: BoxDecoration(
              color: Color(0xFF374151),
              borderRadius: BorderRadius.all(Radius.circular(1.5)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Numbered circle that mirrors `.dispatch-queue-number` from the web
/// dispatch dashboard (dark gray bg, white tabular figure).
class _StopNumber extends StatelessWidget {
  const _StopNumber({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _DispatchJobCard._kNumberBg,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          height: 1.0,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Detail panel promoted when a job is selected. The grab handle at the top
/// can be dragged vertically to switch between three snap heights — collapsed
/// (handle + title only), half-screen (default), and near-fullscreen — or
/// tapped to cycle. The rest of the page rebuilds around it.
class _FocusedJobPanel extends StatefulWidget {
  const _FocusedJobPanel({
    super.key,
    required this.job,
    required this.stopNumber,
    required this.etaMeters,
    required this.starting,
    required this.hasOtherActive,
    required this.isNextInQueue,
    required this.onClose,
    required this.onStart,
    required this.onFinish,
  });

  final DispatchJob job;
  final int stopNumber;

  /// Road distance from rider to this job in meters (OSRM). Shared with the
  /// carousel card so the two surfaces never disagree on the same number.
  final double? etaMeters;
  final RxBool starting;

  /// True if a *different* job is already on-the-way. The rider can only run
  /// one job at a time, so Accept on this panel is disabled in that case.
  final bool hasOtherActive;

  /// True when this job is the next-in-queue per route order. Accept is
  /// disabled on any other assigned job to enforce sequential acceptance.
  final bool isNextInQueue;
  final VoidCallback onClose;
  final VoidCallback onStart;
  final VoidCallback onFinish;

  @override
  State<_FocusedJobPanel> createState() => _FocusedJobPanelState();
}

class _FocusedJobPanelState extends State<_FocusedJobPanel> {
  static const double _minFrac = 0.12;
  static const double _midFrac = 0.4;
  static const double _maxFrac = 0.88;
  static const List<double> _anchors = [_minFrac, _midFrac, _maxFrac];
  static const Duration _snap = Duration(milliseconds: 220);

  double _frac = _midFrac;
  bool _dragging = false;

  void _onDragStart(DragStartDetails _) =>
      setState(() => _dragging = true);

  void _onDragUpdate(DragUpdateDetails d, double screenH) {
    if (screenH <= 0) return;
    setState(() {
      _frac = (_frac - d.delta.dy / screenH).clamp(_minFrac, _maxFrac);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    double target;
    if (v.abs() > 700) {
      // Fling — bias to the next anchor in the fling direction.
      if (v > 0) {
        target = _anchors.lastWhere(
          (a) => a < _frac - 0.01,
          orElse: () => _minFrac,
        );
      } else {
        target = _anchors.firstWhere(
          (a) => a > _frac + 0.01,
          orElse: () => _maxFrac,
        );
      }
    } else {
      target = _anchors.reduce(
        (a, b) => (a - _frac).abs() < (b - _frac).abs() ? a : b,
      );
    }
    setState(() {
      _frac = target;
      _dragging = false;
    });
  }

  void _onHandleTap() {
    setState(() {
      if (_frac <= _minFrac + 0.01) {
        _frac = _midFrac;
      } else if (_frac >= _maxFrac - 0.01) {
        _frac = _midFrac;
      } else {
        _frac = _maxFrac;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final height = screenH * _frac;
    final scheme = Theme.of(context).colorScheme;
    final job = widget.job;

    return Material(
      color: scheme.surface,
      elevation: 8,
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : _snap,
        curve: Curves.easeOutCubic,
        height: height,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onHandleTap,
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: (d) => _onDragUpdate(d, screenH),
                onVerticalDragEnd: _onDragEnd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _StopNumber(number: widget.stopNumber),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Customer first (or job name fallback) — same
                          // information hierarchy as the carousel card.
                          Text(
                            job.customer ?? job.jobName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _DispatchJobCard._kCustomer,
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                              height: 1.25,
                            ),
                          ),
                          if (job.address != null &&
                              job.address!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              job.address!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _DispatchJobCard._kAddress,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Back to list',
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _JobStatusPill(job: job),
                          const SizedBox(width: 8),
                          if (widget.etaMeters != null)
                            Text(
                              '${formatTravelDistance(widget.etaMeters!)} away',
                              style: const TextStyle(
                                color: _DispatchJobCard._kMeta,
                                fontSize: 12,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (job.scheduledArrival != null)
                        _InfoRow(
                          icon: Icons.schedule,
                          label: 'Scheduled',
                          value: formatDispatchTimestamp(job.scheduledArrival),
                        ),
                      if (job.actualArrival != null)
                        _InfoRow(
                          icon: Icons.flag_outlined,
                          label: 'Started',
                          value: formatDispatchTimestamp(job.actualArrival),
                        ),
                      if (job.finishWhen != null)
                        _InfoRow(
                          icon: Icons.verified_outlined,
                          label: 'Finished',
                          value: formatDispatchTimestamp(job.finishWhen),
                        ),
                      if (job.notes != null && job.notes!.isNotEmpty)
                        _InfoRow(
                          icon: Icons.notes,
                          label: 'Notes',
                          value: job.notes!,
                        ),
                      const SizedBox(height: 10),
                      _PanelActions(
                        job: job,
                        starting: widget.starting,
                        hasOtherActive: widget.hasOtherActive,
                        isNextInQueue: widget.isNextInQueue,
                        onStart: widget.onStart,
                        onFinish: widget.onFinish,
                        onNavigate: () => launchMapsDirections(
                          context,
                          lat: job.lat!,
                          lng: job.lng!,
                          label: job.jobName,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _PanelActions extends StatelessWidget {
  const _PanelActions({
    required this.job,
    required this.starting,
    required this.hasOtherActive,
    required this.isNextInQueue,
    required this.onStart,
    required this.onFinish,
    required this.onNavigate,
  });

  final DispatchJob job;
  final RxBool starting;

  /// True if another job is already on-the-way. Disables Accept on this
  /// panel so the rider can't run two jobs in parallel.
  final bool hasOtherActive;

  /// True when this job is the next-up entry per route order. Riders may
  /// only accept stops in sequence — Accept is disabled on out-of-order
  /// cards with an explanatory notice.
  final bool isNextInQueue;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    if (job.isFinished || job.isReschedulePending) {
      return const SizedBox.shrink();
    }

    final hasCoords = job.lat != null && job.lng != null;
    final acceptBlocked =
        !job.isOnTheWay && (hasOtherActive || !isNextInQueue);
    final blockedNotice = hasOtherActive
        ? 'Please complete your current job first.'
        : 'Please complete previous job first.';
    final primary = job.isOnTheWay
        ? SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.flag),
              label: const Text('Finish job'),
            ),
          )
        : SizedBox(
            width: double.infinity,
            child: Obx(() => FilledButton.icon(
                  onPressed:
                      (starting.value || acceptBlocked) ? null : onStart,
                  icon: starting.value
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Accept job'),
                )),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (acceptBlocked) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    blockedNotice,
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        primary,
        if (hasCoords) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onNavigate,
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Navigate'),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(label,
                style: TextStyle(color: Colors.grey.shade700)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.amber.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 18, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
        const SizedBox(height: 12),
        Center(child: Text(message)),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}


