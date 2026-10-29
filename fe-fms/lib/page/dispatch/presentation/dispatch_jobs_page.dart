import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_format.dart';
import '../../../core/dispatch/dispatch_navigation.dart';
import '../../../core/models/geo.dart';
import '../../../core/theme/dispatch_palette.dart';
import '../../../core/widgets/adaptive_map.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../controller/dispatch_jobs_controller.dart';
import '../service/dispatch_notice_service.dart';
import '../service/dispatch_sync_service.dart';
import 'dispatch_finish_job_page.dart';
import 'dispatch_jobs_overview_page.dart';
import 'dispatch_profile_page.dart';

const GeoPoint _kFallbackCenter = GeoPoint(14.5995, 120.9842); // Manila
const Duration _kPanelAnim = Duration(milliseconds: 320);

/// Route polyline colours — sourced from the central palette so a re-skin
/// only touches [DispatchColors].
const String _kRouteHex = DispatchColors.routeHex;
const String _kPreviewRouteHex = DispatchColors.routePreviewHex;

/// Stop number shown on a job's map marker and card — its backend route order
/// when assigned, otherwise its 1-based position in [list].
int _stopNumberOf(DispatchJob job, List<DispatchJob> list) =>
    job.routeOrder ?? (list.indexWhere((j) => j.id == job.id) + 1);

/// Default height of the focused job panel, as a fraction of screen height.
/// Shared between the panel's own mid anchor and the map's initial inset so
/// the route frames correctly on the very first focused frame.
const double _kPanelMidFrac = 0.4;

/// Height (logical px) of the bottom job carousel. The map insets its camera
/// by this much so framed content clears the carousel, and the recenter /
/// route-preview FABs are stacked above it. Tall enough that a job name
/// wrapping to three lines still fits the card without overflowing.
const double _kCarouselHeight = 240;

/// Gap (logical px) between the status bar and the floating top island, and
/// the island's own fixed height.
const double _kTopBarTop = 8;
const double _kTopBarHeight = 56;

/// Compact "HH:mm" for the carousel card's scheduled metric. Today's jobs
/// carry a same-day time, so the date portion would just be noise. Falls back
/// to an em dash when the timestamp is missing or unparseable.
String _compactTime(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final local = dt.isUtc ? dt.toLocal() : dt;
  return DateFormat('HH:mm').format(local);
}

/// Map of today's jobs with a horizontal carousel at the bottom. All the
/// live state (rider position, selected job, OSRM polyline, ETA) lives in
/// [DispatchJobsController] so the route survives page rebuilds — opening
/// and closing the focused panel never blanks the polyline.
class DispatchJobsPage extends StatefulWidget {
  const DispatchJobsPage({super.key});

  @override
  State<DispatchJobsPage> createState() => _DispatchJobsPageState();
}

class _DispatchJobsPageState extends State<DispatchJobsPage> {
  final RxBool _starting = false.obs;

  /// Current height of the focused job panel as a fraction of screen height.
  /// The panel pushes a new value here every time it settles at a drag anchor;
  /// the map reads it to keep the route framed in the space above the panel.
  final RxDouble _panelFrac = RxDouble(_kPanelMidFrac);

  /// Live panel height fraction — updated continuously *during* the drag, not
  /// just on settle like [_panelFrac]. Drives the recenter button so it
  /// sticks to the panel's moving top edge; kept separate so the map camera
  /// (which reads [_panelFrac]) doesn't re-frame on every drag frame.
  final RxDouble _panelFracLive = RxDouble(_kPanelMidFrac);

  /// True while the user is actively dragging the focus panel. The recenter
  /// button reads this to skip its position easing during a drag (so it
  /// tracks the panel edge frame-for-frame) and ease only on settle.
  final RxBool _panelDragging = false.obs;

  late final DispatchJobsController _jobsCtrl;

  /// App-wide transient-notice banner.
  DispatchNoticeController get _notices =>
      Get.find<DispatchNoticeController>();

  /// How far below the SafeArea top the global notice banner should sit on
  /// this page — the island's height plus a top + bottom gap, so the banner
  /// floats beneath the island with a small breathing space.
  static const double _noticeTopOffset =
      _kTopBarTop + _kTopBarHeight + 8;

  @override
  void initState() {
    super.initState();
    // Reuse the existing instance if the dispatch session already
    // initialised it — preserves rider/route/ETA state across page rebuilds.
    _jobsCtrl = Get.isRegistered<DispatchJobsController>()
        ? Get.find<DispatchJobsController>()
        : Get.put(DispatchJobsController());
    _applyNoticeTopOffset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-apply on hot-reload / dependency changes — initState doesn't re-run
    // on a hot-reload, so without this the banner would stay at its old
    // position if the offset was changed in code and reloaded.
    _applyNoticeTopOffset();
  }

  void _applyNoticeTopOffset() {
    if (!Get.isRegistered<DispatchNoticeController>()) return;
    final ctrl = Get.find<DispatchNoticeController>();
    if (ctrl.topInsetExtra.value == _noticeTopOffset) return;
    // Writing the Rx triggers the host's Obx — defer to after the current
    // frame to avoid "setState() called during build" when initState /
    // didChangeDependencies fire mid-build (e.g. during route push).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!Get.isRegistered<DispatchNoticeController>()) return;
      Get.find<DispatchNoticeController>().topInsetExtra.value =
          _noticeTopOffset;
    });
  }

  @override
  void dispose() {
    // dispose runs during the unmount phase — also defer the Rx write so it
    // can't mark the host's Obx dirty while the frame is still being built.
    if (Get.isRegistered<DispatchNoticeController>()) {
      final ctrl = Get.find<DispatchNoticeController>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.isRegistered<DispatchNoticeController>()) {
          ctrl.topInsetExtra.value = 0;
        }
      });
    }
    super.dispose();
  }

  void _select(DispatchJob job) {
    final ok = _jobsCtrl.selectJob(job);
    if (!ok) {
      _notices.info('This job has no coordinates yet.');
      return;
    }
    // A freshly-opened panel always starts at the mid anchor — keep the map's
    // inset and the recenter button in sync so the route frames correctly on
    // the first focused frame, before the new panel reports its own height.
    _panelFrac.value = _kPanelMidFrac;
    _panelFracLive.value = _kPanelMidFrac;
  }

  Future<void> _startJob(int jobId) async {
    _starting.value = true;
    try {
      await _jobsCtrl.startJob(jobId);
      if (!mounted) return;
      _notices.success('Job accepted — you are on the way.');
    } on DispatchQueuedException {
      if (!mounted) return;
      _notices.info('Saved offline. Will sync when online.');
    } on DispatchApiException catch (e) {
      if (!mounted) return;
      if (e.isConflict) {
        _notices.info(e.message);
      } else {
        _notices.error(e.message);
      }
    } catch (e) {
      if (!mounted) return;
      _notices.error(e.toString());
    } finally {
      _starting.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The map runs full-bleed under the status bar — keep that bar fully
      // transparent (no grey scrim) with dark icons for the light map tiles.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        // No AppBar — the map runs full-bleed to the top edge of the screen.
        // The profile entry point is a floating button overlaid on the map.
        body: Obx(() {
        // Top-level Obx: only top-of-tree state (loading / error / empty /
        // stale). Map + panel have their own scoped Obx so they don't
        // rebuild on unrelated state changes.
        if (_jobsCtrl.isLoading.value && _jobsCtrl.jobs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_jobsCtrl.error.value != null && _jobsCtrl.jobs.isEmpty) {
          return SafeArea(
            child: _ErrorState(
              message: _jobsCtrl.error.value ?? 'Failed to load',
              onRetry: _jobsCtrl.refreshToday,
            ),
          );
        }

        // Map fills the screen; the bottom panel + the offline / stale
        // banner float over it via a Stack so neither one pushes the map
        // around when it appears or resizes.
        return Stack(
          children: [
            Positioned.fill(child: _buildMapArea()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomArea(),
            ),
            // Offline / stale-cache banner: bottom-anchored, floating above
            // the carousel/panel rather than pushing the top bar down.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Obx(() {
                if (!_jobsCtrl.isStale.value) return const SizedBox.shrink();
                final panelH = _panelFracLive.value *
                    MediaQuery.of(context).size.height;
                final hasFocus = _jobsCtrl.selectedJobId.value != null &&
                    !_jobsCtrl.routePreview.value;
                final bottomGap = (hasFocus ? panelH : _kCarouselHeight) + 12;
                return Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, bottomGap),
                  child: _StaleBanner(
                    message:
                        _jobsCtrl.error.value ?? 'Showing cached jobs.',
                    onRetry: _jobsCtrl.refreshToday,
                  ),
                );
              }),
            ),
          ],
        );
        }),
      ),
    );
  }

  /// Scoped Obx around the map.
  Widget _buildMapArea() {
    final mq = MediaQuery.of(context);
    final palette = context.dispatch;
    final statusBar = mq.padding.top;
    final bottomSafe = mq.padding.bottom;
    // Inset handed to the map so framed routes clear the status bar *and* the
    // floating island — without it the top of a route hides behind the bar.
    final mapTopInset = statusBar + _kTopBarTop + _kTopBarHeight + 8;
    return Stack(
      children: [
        Positioned.fill(
          child: Obx(() {
            final jobs =
                _jobsCtrl.jobs.where((j) => !j.isFinished).toList();
            final selectedId = _jobsCtrl.selectedJobId.value;
            final selected = selectedId == null
                ? null
                : jobs.firstWhereOrNull((j) => j.id == selectedId);
            final routePreview = _jobsCtrl.routePreview.value;
            final isFocused = !routePreview &&
                selected != null &&
                selected.lat != null &&
                selected.lng != null;
            final rider = _jobsCtrl.riderPos.value;
            final heading = _jobsCtrl.riderHeading.value;
            final route = _jobsCtrl.routePoints.value;
            final reveal = _jobsCtrl.routeRevealCount.value;
            final previewReveal = _jobsCtrl.previewRevealCount.value;
            final followRider = _jobsCtrl.followRider.value;
            final recenterTick = _jobsCtrl.recenterTick.value;

            var mapData = routePreview
                ? _routePreviewMapData(
                    jobs, _jobsCtrl.previewRoutePoints.value, previewReveal)
                : isFocused
                    ? _focusedMapData(
                        selected, jobs, rider, heading, route, reveal)
                    : _overviewMapData(jobs, rider, heading, route, reveal);
            if (followRider && rider != null) {
              // Follow mode pins the rider — no bounds, so the map uses the
              // center/zoom path.
              mapData = _MapData(
                center: rider,
                zoom: 17,
                markers: mapData.markers,
                zones: mapData.zones,
              );
            }

            // Diagnostic: confirms how many polyline zones reach the map on
            // each rebuild. Debug-only — tree-shaken from release builds.
            assert(() {
              final mode = routePreview
                  ? 'preview'
                  : isFocused
                      ? 'focused'
                      : 'overview';
              final lineCount = mapData.zones
                  .where((z) => z.type == MapZoneType.polyline)
                  .length;
              debugPrint('[map] mode=$mode markers=${mapData.markers.length} '
                  'polylineZones=$lineCount');
              return true;
            }());

            // How much of the map's bottom edge the panel currently covers.
            // The map insets its camera by this much so the framed route never
            // hides behind the panel; carousel mode uses its fixed 132px.
            final screenH = mq.size.height;
            final bottomInset = isFocused
                ? screenH * _panelFrac.value
                : (jobs.isEmpty ? 0.0 : _kCarouselHeight) + bottomSafe;

            return AdaptiveMap(
              key: const ValueKey('dispatchmap'),
              center: mapData.center,
              zoom: mapData.zoom,
              markers: mapData.markers,
              zones: mapData.zones,
              recenterTick: recenterTick,
              fitBounds: mapData.bounds,
              bottomInset: bottomInset,
              topInset: mapTopInset,
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
        // Floating top island — job list + route toggle on the left, a
        // tap-through job-progress summary filling the middle, profile on
        // the right.
        Positioned(
          top: statusBar + _kTopBarTop,
          left: 12,
          right: 12,
          child: Material(
            color: palette.control,
            elevation: 4,
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: _kTopBarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Centre: today's date over the job-progress count. Truly
                    // centred over the whole bar (a Stack, so the uneven edge
                    // controls don't shift it) and display-only.
                    IgnorePointer(
                      child: Obx(() {
                        // Jobs still to do. Finished jobs leave the list, so
                        // a "done / total" count would only ever shrink —
                        // a plain remaining-count is the honest signal.
                        final remaining = _jobsCtrl.jobs
                            .where((j) => !j.isFinished)
                            .length;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('EEE, MMM d')
                                  .format(DateTime.now()),
                              style: TextStyle(
                                color: palette.subtle,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              remaining == 0
                                  ? 'No pending jobs'
                                  : remaining == 1
                                      ? '1 job remaining'
                                      : '$remaining jobs remaining',
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                    // Edge controls overlaid on top.
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Job list',
                          icon: Icon(Icons.list_alt_outlined,
                              color: palette.ink),
                          onPressed: () => Get.to(
                              () => const DispatchJobsOverviewPage()),
                        ),
                        Obx(() {
                          final on = _jobsCtrl.routePreview.value;
                          // Nothing to route with no jobs — grey it out.
                          final hasJobs =
                              _jobsCtrl.jobs.any((j) => !j.isFinished);
                          return IconButton(
                            tooltip: !hasJobs
                                ? 'No jobs to route'
                                : on
                                    ? 'Hide job route'
                                    : 'Show job route',
                            icon: Icon(
                              Icons.route_outlined,
                              color: !hasJobs
                                  ? palette.subtle.withValues(alpha: 0.4)
                                  : on
                                      ? DispatchColors.brand
                                      : palette.ink,
                            ),
                            onPressed: hasJobs
                                ? _jobsCtrl.toggleRoutePreview
                                : null,
                          );
                        }),
                        const Spacer(),
                        // Profile — a rounded square to match the bar.
                        Material(
                          color: _DispatchJobCard._kCardGreen,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () =>
                                Get.to(() => const DispatchProfilePage()),
                            child: const Padding(
                              padding: EdgeInsets.all(9),
                              child: Icon(Icons.person,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Pending-sync indicator — sits just below the floating top island.
        if (Get.isRegistered<DispatchSyncService>())
          Positioned(
            top: statusBar + _kTopBarTop + _kTopBarHeight + 4,
            left: 12,
            child: Obx(() {
              final count =
                  Get.find<DispatchSyncService>().pendingCount.value;
              if (count == 0) return const SizedBox.shrink();
              return Material(
                color: palette.control,
                elevation: 3,
                borderRadius: BorderRadius.circular(999),
                child: Tooltip(
                  message: '$count action(s) pending sync',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync, size: 14, color: palette.ink),
                        const SizedBox(width: 4),
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        // Recenter button — anchored just above whatever occupies the bottom:
        // the top edge of the focus panel when one is open, otherwise the
        // carousel. Glued to the panel as it is dragged, and fades out once
        // the panel (nearly) fills the screen.
        Positioned.fill(
          child: Obx(() {
            final focused = _jobsCtrl.selectedJobId.value != null;
            final hasCarousel = _jobsCtrl.jobs.any((j) => !j.isFinished);
            final screenH = mq.size.height;
            final frac = _panelFracLive.value;
            final dragging = _panelDragging.value;
            final bottomOffset = focused
                ? screenH * frac + 12
                : (hasCarousel ? _kCarouselHeight : 0) + bottomSafe + 12;
            // No usable map left to recenter once the panel is dragged up to
            // (nearly) fill the screen — fade the button away.
            final hidden = focused && frac > 0.8;
            return Align(
              alignment: Alignment.bottomRight,
              child: AnimatedPadding(
                // Snap instantly while the panel is being dragged so the
                // button tracks the finger with no lag; ease only on settle.
                duration: dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(right: 8, bottom: bottomOffset),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: hidden ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: hidden,
                    child: FloatingActionButton.small(
                      heroTag: 'recenter',
                      backgroundColor: palette.control,
                      foregroundColor: palette.ink,
                      tooltip: focused
                          ? 'Recenter on the route'
                          : 'Center on my location',
                      onPressed: _jobsCtrl.recenterOnRider,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Scoped Obx around the bottom area only.
  Widget _buildBottomArea() {
    return Obx(() {
      final jobs =
          _jobsCtrl.jobs.where((j) => !j.isFinished).toList();
      final selectedId = _jobsCtrl.selectedJobId.value;
      final selected = selectedId == null
          ? null
          : jobs.firstWhereOrNull((j) => j.id == selectedId);
      final isFocused = selected != null;

      // Diagnostic: surfaces a selection that is set but whose job dropped
      // out of the active list, which silently collapses the focused panel.
      assert(() {
        if (selectedId != null && selected == null) {
          debugPrint('[sel] panel hidden: job $selectedId '
              'is not in the active (unfinished) job list');
        }
        return true;
      }());

      return AnimatedSwitcher(
        duration: _kPanelAnim,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        // A plain cross-fade — both the carousel card and the panel are the
        // same green, and the panel animates its own height growth, so the
        // swap reads as the tapped card enlarging in place.
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        // Bottom-align the in/out children. The default centres them, which
        // makes the short carousel float to mid-screen while a tall panel is
        // still fading out — pin both to the bottom so the carousel never
        // leaves its resting position.
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.bottomCenter,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        ),
        child: isFocused
            ? () {
                final nextInQueueId = jobs
                    .firstWhereOrNull(
                        (j) => !j.isOnTheWay && !j.isReschedulePending)
                    ?.id;
                return _FocusedJobPanel(
                  key: ValueKey('panel_${selected.id}'),
                  job: selected,
                  stopNumber: selected.routeOrder ??
                      (jobs.indexWhere((j) => j.id == selected.id) + 1),
                  etaMeters: _jobsCtrl.etaMeters.value,
                  starting: _starting,
                  hasOtherActive: jobs.any(
                      (j) => j.isOnTheWay && j.id != selected.id),
                  isNextInQueue: selected.id == nextInQueueId,
                  onClose: _jobsCtrl.clearSelection,
                  onStart: () => _startJob(selected.id),
                  onFinish: () => Get.to(
                      () => DispatchFinishJobPage(jobId: selected.id)),
                  onFracChanged: (f) => _panelFrac.value = f,
                  onFracLive: (f) => _panelFracLive.value = f,
                  panelDragging: _panelDragging,
                );
              }()
            : jobs.isEmpty
                // No jobs — the top bar already says so; render nothing here
                // rather than a redundant empty card.
                ? const SizedBox.shrink(key: ValueKey('carousel'))
                : SafeArea(
                    key: const ValueKey('carousel'),
                    top: false,
                    child: SizedBox(
                      height: _kCarouselHeight,
                      child: _JobCarousel(
                        jobs: jobs,
                        etaMeters: _jobsCtrl.etaMeters.value,
                        onSelect: _select,
                      ),
                    ),
                  ),
      );
    });
  }

  _MapData _focusedMapData(
    DispatchJob selected,
    List<DispatchJob> jobs,
    GeoPoint? rider,
    double? heading,
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
        label: _stopNumberOf(selected, jobs).toString(),
      ),
      if (rider != null)
        MapMarkerModel(
          id: 'rider',
          position: rider,
          title: 'You',
          kind: MapMarkerKind.rider,
          rotation: heading,
        ),
    ];
    if (rider == null) {
      return _MapData(center: job, zoom: 16, markers: markers);
    }
    final center = GeoPoint(
      (job.lat + rider.lat) / 2,
      (job.lng + rider.lng) / 2,
    );
    final meters = Geolocator.distanceBetween(
        rider.lat, rider.lng, job.lat, job.lng);
    final zoom = _zoomForMeters(meters);
    final hasRoute = route != null && route.length >= 2 && revealCount >= 2;
    final revealed = hasRoute
        ? route.sublist(0, revealCount.clamp(2, route.length))
        : const <GeoPoint>[];
    // Frame the rider→job span so the route is fully visible above the panel.
    // Endpoints (not the revealing polyline) keep the box stable while the
    // line "draws on". A degenerate box — rider sitting on the job — falls
    // back to the center/zoom pair computed above.
    final span = GeoBounds.fromPoints([job, rider]);
    return _MapData(
      center: center,
      zoom: zoom,
      markers: markers,
      bounds: span.isPoint ? null : span,
      zones: hasRoute
          ? [
              MapZoneModel(
                id: 'route',
                type: MapZoneType.polyline,
                points: revealed,
                style: const MapZoneStyle(
                  strokeColorHex: _kRouteHex,
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
    double? heading,
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
            label: _stopNumberOf(j, jobs).toString(),
          )),
      if (rider != null)
        MapMarkerModel(
          id: 'rider',
          position: rider,
          title: 'You',
          kind: MapMarkerKind.rider,
          rotation: heading,
        ),
    ];
    final center = rider ??
        (geoJobs.isNotEmpty
            ? GeoPoint(geoJobs.first.lat!, geoJobs.first.lng!)
            : _kFallbackCenter);
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
                  strokeColorHex: _kRouteHex,
                  strokeWidth: 4,
                  strokeOpacity: 0.85,
                ),
              ),
            ]
          : const [],
    );
  }

  /// Map data for the all-jobs route preview: every unfinished geocoded job
  /// framed together, threaded by the multi-stop polyline from the controller.
  /// Deliberately omits the driver pin — this view is about the job route.
  _MapData _routePreviewMapData(
    List<DispatchJob> jobs,
    List<GeoPoint>? previewRoute,
    int revealCount,
  ) {
    final geoJobs = jobs
        .where((j) => j.lat != null && j.lng != null)
        .toList()
      ..sort((a, b) => (a.routeOrder ?? 1 << 30)
          .compareTo(b.routeOrder ?? 1 << 30));
    final markers = <MapMarkerModel>[
      ...geoJobs.map((j) => MapMarkerModel(
            id: 'job_${j.id}',
            position: GeoPoint(j.lat!, j.lng!),
            title: j.jobName,
            subtitle: j.address,
            data: j.id,
            label: _stopNumberOf(j, jobs).toString(),
          )),
    ];
    // Frame every job stop together so the whole day is in view.
    final framePoints =
        geoJobs.map((j) => GeoPoint(j.lat!, j.lng!)).toList();
    final bounds =
        framePoints.length >= 2 ? GeoBounds.fromPoints(framePoints) : null;
    final center = framePoints.isNotEmpty ? framePoints.first : _kFallbackCenter;
    final hasLine = previewRoute != null &&
        previewRoute.length >= 2 &&
        revealCount >= 2;
    // Reveal the line progressively — it draws from the first stop onward.
    final revealed = hasLine
        ? previewRoute.sublist(0, revealCount.clamp(2, previewRoute.length))
        : const <GeoPoint>[];
    return _MapData(
      center: center,
      zoom: 12,
      markers: markers,
      bounds: (bounds != null && !bounds.isPoint) ? bounds : null,
      zones: hasLine
          ? [
              MapZoneModel(
                id: 'preview_route',
                type: MapZoneType.polyline,
                points: revealed,
                style: const MapZoneStyle(
                  strokeColorHex: _kPreviewRouteHex,
                  strokeWidth: 4,
                  strokeOpacity: 0.9,
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
    this.bounds,
  });
  final GeoPoint center;
  final double zoom;
  final List<MapMarkerModel> markers;
  final List<MapZoneModel> zones;

  /// When set, the map frames this box instead of using [center]/[zoom].
  /// [center]/[zoom] remain as the fallback / initial camera position.
  final GeoBounds? bounds;
}

class _JobCarousel extends StatefulWidget {
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
  State<_JobCarousel> createState() => _JobCarouselState();
}

class _JobCarouselState extends State<_JobCarousel> {
  /// A page-snapping controller — each job card snaps to screen-centre, with
  /// the neighbouring cards peeking in at the edges. The < 1.0 viewport
  /// fraction is what visually centres the active card.
  final PageController _controller = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobs = widget.jobs;
    // The card carrying the live "DISTANCE" value: the on-the-way stop if any,
    // else the next actionable stop.
    final etaTargetId = jobs.firstWhereOrNull((j) => j.isOnTheWay)?.id ??
        jobs
            .firstWhereOrNull(
                (j) => !j.isOnTheWay && !j.isReschedulePending)
            ?.id;
    return PageView.builder(
      controller: _controller,
      itemCount: jobs.length,
      padEnds: true,
      itemBuilder: (context, i) {
        final job = jobs[i];
        final stopNumber = job.routeOrder ?? (i + 1);
        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 14),
          child: _DispatchJobCard(
            job: job,
            stopNumber: stopNumber,
            etaMeters: job.id == etaTargetId ? widget.etaMeters : null,
            onTap: () => widget.onSelect(job),
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
    required this.onTap,
    this.etaMeters,
  });

  final DispatchJob job;
  final int stopNumber;
  final double? etaMeters;
  final VoidCallback onTap;

  /// Fallback fill for the stop-number disc (overridden to white on the
  /// green card / panel, so this is just a safety default).
  static const _kNumberBg = Color(0xFF1f2937);

  /// Ride-card green — the carousel card fill. Sourced from the central
  /// palette so a re-skin only touches [DispatchColors].
  static const _kCardGreen = DispatchColors.brand;

  @override
  Widget build(BuildContext context) {
    final hasGeo = job.lat != null && job.lng != null;

    return Material(
      color: _kCardGreen,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.30),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header — stop number, customer, status.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StopNumber(
                    number: stopNumber,
                    backgroundColor: Colors.white,
                    foregroundColor: _kCardGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // Wrap the full name rather than truncating it — most fit
                    // on one or two lines; three is the safety ceiling.
                    child: Text(
                      job.customer ?? job.jobName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _JobStatusPill(job: job),
                ],
              ),
              // Destination address.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _CardLabel('DESTINATION'),
                  const SizedBox(height: 4),
                  Text(
                    (job.address != null && job.address!.isNotEmpty)
                        ? job.address!
                        : 'No address provided',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
              // Hairline divider, mirroring the reference card.
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.22),
              ),
              // Metadata row — scheduled time + travel distance.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _CardMetric(
                      label: 'SCHEDULED',
                      value: _compactTime(job.scheduledArrival),
                    ),
                  ),
                  Expanded(
                    child: _CardMetric(
                      label: 'DISTANCE',
                      value: etaMeters != null
                          ? formatTravelDistance(etaMeters!)
                          : (hasGeo ? '—' : 'No location'),
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small all-caps label used for the field captions on the green job card
/// ("DESTINATION", "SCHEDULED", "DISTANCE").
class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.9),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// A captioned value in the job card's bottom metadata row.
class _CardMetric extends StatelessWidget {
  const _CardMetric({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _CardLabel(label),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            height: 1.1,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

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

class _StopNumber extends StatelessWidget {
  const _StopNumber({
    required this.number,
    this.backgroundColor,
    this.foregroundColor,
  });

  final int number;

  /// Disc fill. Defaults to the dark web-parity colour (light surfaces); the
  /// green carousel card overrides it to white.
  final Color? backgroundColor;

  /// Numeral colour. Defaults to white; overridden to green on the card.
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? _DispatchJobCard._kNumberBg,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: foregroundColor ?? Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

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
    required this.onFracChanged,
    required this.onFracLive,
    required this.panelDragging,
  });

  final DispatchJob job;
  final int stopNumber;
  final double? etaMeters;
  final RxBool starting;
  final bool hasOtherActive;
  final bool isNextInQueue;
  final VoidCallback onClose;
  final VoidCallback onStart;
  final VoidCallback onFinish;

  /// Reports the panel's height fraction whenever it settles at a drag anchor
  /// (drag-end or handle-tap) — and once on first frame. Lets the map re-frame
  /// the route into the newly-sized visible area.
  final ValueChanged<double> onFracChanged;

  /// Reports the height fraction *continuously* during a drag, so the recenter
  /// button can stay glued to the panel's moving top edge.
  final ValueChanged<double> onFracLive;

  /// Set true while the user is actively dragging — lets the recenter button
  /// skip its position easing so it tracks the panel without lag.
  final RxBool panelDragging;

  @override
  State<_FocusedJobPanel> createState() => _FocusedJobPanelState();
}

class _FocusedJobPanelState extends State<_FocusedJobPanel> {
  static const double _minFrac = 0.12;
  static const double _maxFrac = 0.88;
  static const Duration _snap = Duration(milliseconds: 260);

  /// Vertical extent of the drag handle (10 + 4 + 10) — added to the measured
  /// content when sizing the panel.
  static const double _handleHeight = 24;

  /// Key on the scrollable content column — its laid-out height is what the
  /// panel sizes itself to, so everything is visible without scrolling.
  final GlobalKey _contentKey = GlobalKey();

  double _frac = _kPanelMidFrac;
  bool _dragging = false;
  bool _entered = false;

  /// Height fraction at which the panel exactly fits its content with no
  /// scrolling — measured from the laid-out content on the first frame, and
  /// the panel's resting "open" anchor. Falls back to the mid default until
  /// measured.
  double _fitFrac = _kPanelMidFrac;

  /// Drag/tap snap anchors: collapsed peek, content-fit, near-full.
  List<double> get _anchors => [_minFrac, _fitFrac, _maxFrac];

  void _onDragStart(DragStartDetails _) {
    widget.panelDragging.value = true;
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails d, double screenH) {
    if (screenH <= 0) return;
    // Resize the panel live, but don't re-frame the map mid-drag — that's done
    // once on settle (_onDragEnd / _onHandleTap) so the camera doesn't thrash.
    setState(() {
      _frac = (_frac - d.delta.dy / screenH).clamp(_minFrac, _maxFrac);
    });
    // The recenter button does follow the live edge.
    widget.onFracLive(_frac);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    final anchors = _anchors;
    double target;
    if (v.abs() > 700) {
      if (v > 0) {
        target = anchors.lastWhere(
          (a) => a < _frac - 0.01,
          orElse: () => _minFrac,
        );
      } else {
        target = anchors.firstWhere(
          (a) => a > _frac + 0.01,
          orElse: () => _maxFrac,
        );
      }
    } else {
      target = anchors.reduce(
        (a, b) => (a - _frac).abs() < (b - _frac).abs() ? a : b,
      );
    }
    setState(() {
      _frac = target;
      _dragging = false;
    });
    widget.panelDragging.value = false;
    widget.onFracChanged(target);
    widget.onFracLive(target);
  }

  void _onHandleTap() {
    final double next;
    if (_frac <= _minFrac + 0.02) {
      next = _fitFrac; // peek → open to full content
    } else if (_frac >= _maxFrac - 0.02) {
      next = _fitFrac; // near-full → back to content
    } else {
      next = _maxFrac; // content → near-full
    }
    setState(() => _frac = next);
    widget.onFracChanged(next);
    widget.onFracLive(next);
  }

  /// Measures the laid-out content and opens the panel at exactly the height
  /// that shows all of it — so the action buttons are visible immediately,
  /// with no scrolling needed. [keepFracIfDragged] is true when the panel was
  /// re-measured because the underlying job changed (e.g. Accept → Finish);
  /// in that case the panel snaps to the new fit height regardless of the
  /// rider's current drag position, since the previous fit is now stale.
  void _openToFitContent({bool keepFracIfDragged = false}) {
    if (!mounted) return;
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    var target = _kPanelMidFrac;
    final contentH = _contentKey.currentContext?.size?.height;
    if (contentH != null && contentH > 0 && screenH > 0) {
      final needed = _handleHeight + contentH + mq.padding.bottom + 6;
      target = (needed / screenH).clamp(_minFrac, _maxFrac);
    }
    // Capture whether the rider was sitting at the previous fit anchor
    // *before* we overwrite [_fitFrac] — otherwise the check below compares
    // against the new fit and always trips when the content grows, which is
    // exactly the case we want to follow (Accept → taller content).
    final wasAtPreviousFit = (_frac - _fitFrac).abs() < 0.02;
    setState(() {
      _fitFrac = target;
      // If the rider has dragged away from the previous fit, leave their
      // chosen size alone — only the "fit" anchor is updated.
      if (!keepFracIfDragged || wasAtPreviousFit) {
        _frac = target;
      }
    });
    widget.onFracChanged(target);
    widget.onFracLive(target);
  }

  @override
  void didUpdateWidget(covariant _FocusedJobPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the underlying job's actionable state changes — accept (assigned →
    // on the way), or new timeline rows appear — the content's height changes,
    // so the previously-measured fit anchor is wrong. Re-measure next frame.
    final oldJob = oldWidget.job;
    final newJob = widget.job;
    final actionableChanged = oldJob.isOnTheWay != newJob.isOnTheWay ||
        oldJob.actualArrival != newJob.actualArrival ||
        oldJob.finishWhen != newJob.finishWhen ||
        oldJob.isReschedulePending != newJob.isReschedulePending ||
        oldWidget.hasOtherActive != widget.hasOtherActive ||
        oldWidget.isNextInQueue != widget.isNextInQueue;
    if (actionableChanged) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openToFitContent(keepFracIfDragged: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;

    if (!_entered) {
      // First build: open at roughly the carousel card's height, then — once
      // the content has laid out — expand to exactly fit it next frame, so the
      // panel reads as the tapped card swelling open to its full detail.
      _entered = true;
      _frac = (_kCarouselHeight / screenH).clamp(_minFrac, _maxFrac);
      WidgetsBinding.instance.addPostFrameCallback((_) => _openToFitContent());
    }

    final height = screenH * _frac;
    final job = widget.job;
    const green = _DispatchJobCard._kCardGreen;

    return Material(
      color: green,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
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
              // Drag handle.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onHandleTap,
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: (d) => _onDragUpdate(d, screenH),
                onVerticalDragEnd: _onDragEnd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              // Content — header + detail. The panel measures this column
              // (via [_contentKey]) and opens exactly tall enough to show all
              // of it; it scrolls only when dragged shorter than its content.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    key: _contentKey,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header — mirrors the carousel card's header so the
                      // card visually "becomes" the panel.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _StopNumber(
                                number: widget.stopNumber,
                                backgroundColor: Colors.white,
                                foregroundColor: green,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  job.customer ?? job.jobName,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Back to list',
                              icon: const Icon(Icons.close,
                                  color: Colors.white),
                              onPressed: widget.onClose,
                            ),
                          ],
                        ),
                      ),
                      // Detail.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _CardLabel('DESTINATION'),
                            const SizedBox(height: 4),
                            Text(
                              (job.address != null &&
                                      job.address!.isNotEmpty)
                                  ? job.address!
                                  : 'No address provided',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _JobStatusPill(job: job),
                                const Spacer(),
                                if (widget.etaMeters != null) ...[
                                  const Icon(Icons.near_me_outlined,
                                      size: 15, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    formatTravelDistance(widget.etaMeters!),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'away',
                                    style: TextStyle(
                                      color: Colors.white
                                          .withValues(alpha: 0.75),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (job.scheduledArrival != null)
                              _InfoRow(
                                icon: Icons.schedule,
                                label: 'Scheduled',
                                value: formatDispatchTimestamp(
                                    job.scheduledArrival),
                              ),
                            if (job.actualArrival != null)
                              _InfoRow(
                                icon: Icons.flag_outlined,
                                label: 'Started',
                                value: formatDispatchTimestamp(
                                    job.actualArrival),
                              ),
                            if (job.finishWhen != null)
                              _InfoRow(
                                icon: Icons.verified_outlined,
                                label: 'Finished',
                                value: formatDispatchTimestamp(
                                    job.finishWhen),
                              ),
                            if (job.notes != null &&
                                job.notes!.isNotEmpty)
                              _InfoRow(
                                icon: Icons.notes,
                                label: 'Notes',
                                value: job.notes!,
                              ),
                            for (final section in job.externalDetails)
                              DispatchJobDetailSectionTile(section: section),
                            const SizedBox(height: 16),
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
  final bool hasOtherActive;
  final bool isNextInQueue;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    if (job.isFinished || job.isReschedulePending) {
      return const SizedBox.shrink();
    }

    const green = _DispatchJobCard._kCardGreen;
    final hasCoords = job.lat != null && job.lng != null;
    final acceptBlocked =
        !job.isOnTheWay && (hasOtherActive || !isNextInQueue);
    final blockedNotice = hasOtherActive
        ? 'Please complete your current job first.'
        : 'Please complete previous job first.';

    // White fill / green label — the primary action reads clearly against
    // the green panel (mirrors the reference card's Accept button).
    final whiteButtonStyle = FilledButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: green,
      disabledBackgroundColor: Colors.white.withValues(alpha: 0.45),
      disabledForegroundColor: green.withValues(alpha: 0.5),
      minimumSize: const Size.fromHeight(50),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );

    final primary = job.isOnTheWay
        ? SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: whiteButtonStyle,
              onPressed: onFinish,
              icon: const Icon(Icons.flag),
              label: const Text('Finish job'),
            ),
          )
        : SizedBox(
            width: double.infinity,
            child: Obx(() => FilledButton.icon(
                  style: whiteButtonStyle,
                  onPressed:
                      (starting.value || acceptBlocked) ? null : onStart,
                  icon: starting.value
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: green),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    blockedNotice,
                    style:
                        const TextStyle(fontSize: 12.5, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        primary,
        if (hasCoords) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                minimumSize: const Size.fromHeight(48),
              ),
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

/// One ORMECO details section, collapsed so the panel stays map-sized. Public
/// only so a widget test can pump it without the map page around it.
@visibleForTesting
class DispatchJobDetailSectionTile extends StatelessWidget {
  const DispatchJobDetailSectionTile({super.key, required this.section});
  final DispatchJobDetailSection section;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // ExpansionTile draws theme dividers above and below; the panel has none.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,
        title: Text(
          section.heading,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          for (final f in section.fields) _InfoRow(label: f.label, value: f.value),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    this.icon,
    required this.label,
    required this.value,
  });
  final IconData? icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.9);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: muted),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 86,
            child: Text(label,
                style: TextStyle(color: muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  static const Color _amber = Color(0xFFb45309);

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Material(
      color: palette.card,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 18, color: _amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12.5,
                  color: palette.ink,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: DispatchColors.brand,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                minimumSize: const Size(56, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
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

