import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fms/core/utils/user_message.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_format.dart';
import '../../../core/dispatch/dispatch_navigation.dart';
import '../../../core/models/geo.dart';
import '../../../core/theme/dispatch_palette.dart';
import '../../../core/theme/motion.dart';
import '../../../core/widgets/flutter_map_widget.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../controller/dispatch_jobs_controller.dart';
import '../service/dispatch_notice_service.dart';
import '../service/dispatch_sync_service.dart';
import '../widget/dispatch_external_status_pill.dart';
import '../widget/dispatch_job_status.dart';
import 'dispatch_finish_job_page.dart';
import 'dispatch_jobs_overview_page.dart';
import 'dispatch_profile_page.dart';

const GeoPoint _kFallbackCenter = GeoPoint(14.5995, 120.9842); // Manila

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
/// wrapping to three lines still fits the card without overflowing, at the
/// type-scale role sizes (titleLarge name, labelSmall captions).
const double _kCarouselHeight = 245;

/// The part of [_kCarouselHeight] that doesn't grow with text size: the
/// card's outer and inner padding, the divider and the fixed gaps.
const double _kCarouselChrome = 64;

/// [_kCarouselHeight] at the device's font size. Only the text share grows,
/// so a 3-line name and 2-line address still fit at 1.3× and 2×.
double _carouselHeight(BuildContext context) =>
    _kCarouselChrome +
    MediaQuery.textScalerOf(context)
        .scale(_kCarouselHeight - _kCarouselChrome);

/// Gap (logical px) between the status bar and the floating top island, and
/// the island's own fixed height.
const double _kTopBarTop = 8;
const double _kTopBarHeight = 56;

/// Fully round ends (a stadium), so the circular profile button sits inside
/// the right end with the same gap all round.
const double _kTopBarRadius = _kTopBarHeight / 2;

/// The profile button's inset from the island edge: a 48 dp circle, centred,
/// with the same gap on the right as top and bottom.
const double _kTopBarInset = (_kTopBarHeight - 48) / 2;

/// Compact "h:mm a" for the carousel card's scheduled metric. Today's jobs
/// carry a same-day time, so the date portion would just be noise. Falls back
/// to an em dash when the timestamp is missing or unparseable.
String _compactTime(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final local = dt.isUtc ? dt.toLocal() : dt;
  return DateFormat('h:mm a').format(local);
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

class _DispatchJobsPageState extends State<DispatchJobsPage>
    with TickerProviderStateMixin {
  final RxBool _starting = false.obs;

  /// How far each bottom layer is up: 0 is below the screen's bottom edge,
  /// 1 is in place. Opening a job runs the cards down to 0 and then the
  /// panel up to 1; closing is the same in the other order. Only one moves
  /// at a time, so the recenter button and the banners sit on whichever is
  /// taller ([_bottomEdge]).
  late final AnimationController _cards;
  late final AnimationController _panel;
  late final Animation<Offset> _cardsSlide = _slide(_cards);
  late final Animation<Offset> _panelSlide = _slide(_panel);

  /// Which layer is wanted; the swap is in flight until both have settled.
  bool _panelShown = false;
  final RxBool _swapping = false.obs;

  /// The job the panel shows. Kept after the selection clears so the panel
  /// has something to draw while it slides out.
  DispatchJob? _panelJob;

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

  /// Why the rider's position can't be read (GPS off / permission denied),
  /// or null when location works. Drives the "Enable" banner.
  final RxnString _locationOff = RxnString();

  /// Re-checks location when the user comes back from system settings.
  late final AppLifecycleListener _lifecycle;

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
        : Get.put(DispatchJobsController(), permanent: true);
    _panelShown = _jobsCtrl.selectedJobId.value != null;
    _cards = AnimationController(vsync: this, value: _panelShown ? 0 : 1);
    _panel = AnimationController(vsync: this, value: _panelShown ? 1 : 0);
    _applyNoticeTopOffset();
    _checkLocation(request: true);
    // No prompt on resume: the permission dialog itself pauses/resumes the
    // app, so requesting here would re-prompt in a loop after a denial.
    _lifecycle = AppLifecycleListener(onResume: _checkLocation);
  }

  /// Asks for location once when the map opens and keeps [_locationOff] in
  /// step with the OS, so a missing rider dot / "—" distances are explained.
  Future<void> _checkLocation({bool request = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _locationOff.value = 'Location is off — your position and '
            'distances to jobs can\'t show.';
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (request && permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _locationOff.value = 'Location access is off — your position and '
            'distances to jobs can\'t show.';
        return;
      }
      if (!mounted) return;
      final wasOff = _locationOff.value != null;
      _locationOff.value = null;
      if (wasOff || request) {
        unawaited(_jobsCtrl.refreshRiderPosition(force: true));
      }
    } catch (_) {
      // No location plugin (tests / unsupported platform) — nothing to show.
    }
  }

  /// Banner "Enable": GPS settings when the service is off, app settings when
  /// the permission is permanently denied, otherwise the system prompt again.
  Future<void> _enableLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      } else if (await Geolocator.checkPermission() ==
          LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      } else {
        await _checkLocation(request: true);
      }
    } catch (_) {}
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

  static Animation<Offset> _slide(Animation<double> up) =>
      Tween(begin: const Offset(0, 1), end: Offset.zero).animate(up);

  /// Swaps the bottom layers in sequence, as on the eFMS tracking page: the
  /// one on screen drops out (short, snappy), then the other rises (medium,
  /// calmer). Instant under reduce motion. A swap the other way mid-flight
  /// just turns the moving layer around.
  void _swapTo(bool panel) {
    if (_panelShown == panel) return;
    _panelShown = panel;
    _swapping.value = true;
    final out = panel ? _cards : _panel;
    final inn = panel ? _panel : _cards;
    out
        .animateBack(0,
            duration: Motion.of(context, Motion.short), curve: Motion.standard)
        .whenCompleteOrCancel(() {
      if (!mounted || _panelShown != panel) return;
      inn
          .animateTo(1,
              duration: Motion.of(context, Motion.medium),
              curve: Motion.emphasized)
          .whenCompleteOrCancel(() {
        if (mounted && _panelShown == panel && !inn.isAnimating) {
          _swapping.value = false;
        }
      });
    });
  }

  /// How far the bottom layer currently on screen reaches above the bottom
  /// edge: the carousel (with its safe-area inset) or the panel, scaled by
  /// how far up each one is. Read inside a builder on [_cards] and [_panel]
  /// so it tracks the swap frame for frame.
  double _bottomEdge(BuildContext context, {required bool hasCarousel}) {
    final mq = MediaQuery.of(context);
    final carousel =
        (hasCarousel ? _carouselHeight(context) : 0) + mq.padding.bottom;
    final panel = mq.size.height * _panelFracLive.value;
    return math.max(carousel * _cards.value, panel * _panel.value);
  }

  @override
  void dispose() {
    _cards.dispose();
    _panel.dispose();
    _lifecycle.dispose();
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
        _notices.info(userMessage(e));
      } else {
        _notices.error(userMessage(e));
      }
    } catch (e) {
      if (!mounted) return;
      _notices.error(userMessage(e));
    } finally {
      _starting.value = false;
    }
  }

  /// Back peels the map's layers one at a time — the focused panel, then the
  /// route preview — and only then asks before leaving the app, matching the
  /// 2W exit confirm in `nav_bar.dart`.
  Future<void> _onBack(bool didPop, Object? _) async {
    if (didPop) return;
    if (_jobsCtrl.selectedJobId.value != null) {
      _jobsCtrl.clearSelection();
      return;
    }
    if (_jobsCtrl.routePreview.value) {
      _jobsCtrl.toggleRoutePreview();
      return;
    }
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App'),
        content: const Text('Do you want to exit the application?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (shouldExit == true) SystemNavigator.pop();
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
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: _onBack,
        child: Scaffold(
          // No AppBar — the map runs full-bleed to the top edge of the
          // screen. The profile entry point is a floating button overlaid on
          // the map. Loading and load errors render *over* the map so the
          // top bar (job list, profile, log out) is always reachable.
          body: Stack(
            children: [
              Positioned.fill(child: _buildMapArea()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomArea(),
              ),
              // First load only — later polls refresh in place, so a day
              // with zero jobs never blanks the map every 30 s.
              // Positioned.fill: a non-positioned child would size this
              // Stack (the body gets loose constraints), and the idle
              // SizedBox.shrink() collapsed the whole page to 0×0.
              Positioned.fill(
                child: Obx(() => AnimatedSwitcher(
                      duration: Motion.of(context, Motion.short),
                      child: _jobsCtrl.isLoading.value &&
                              _jobsCtrl.jobs.isEmpty &&
                              _jobsCtrl.lastFetchedAt.value == null
                          ? const Center(
                              key: ValueKey('spinner'),
                              child: CircularProgressIndicator())
                          : const SizedBox.shrink(),
                    )),
              ),
              // Location-off and offline / load-error banners: bottom-
              // anchored, floating above the carousel/panel rather than
              // pushing the top bar down.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Obx(() {
                  final error = _jobsCtrl.error.value;
                  final showError = _jobsCtrl.isStale.value ||
                      (error != null && _jobsCtrl.jobs.isEmpty);
                  final locationOff = _locationOff.value;
                  final hasCarousel =
                      _jobsCtrl.jobs.any((j) => !j.isFinished);
                  _panelFracLive.value; // subscribe: the panel edge moves
                  return AnimatedBuilder(
                    animation: Listenable.merge([_cards, _panel]),
                    builder: (context, child) => Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12,
                          _bottomEdge(context, hasCarousel: hasCarousel) + 12),
                      child: child,
                    ),
                    // Banners grow in and out from the bottom edge instead
                    // of popping; instant under reduce motion.
                    child: MotionSize(
                      alignment: Alignment.bottomCenter,
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (locationOff != null)
                          _StaleBanner(
                            icon: Icons.location_off,
                            message: locationOff,
                            actionLabel: 'Enable',
                            onAction: _enableLocation,
                          ),
                        if (locationOff != null && showError)
                          const SizedBox(height: 8),
                        if (showError)
                          _StaleBanner(
                            message: error ?? 'Showing cached jobs.',
                            onAction: _jobsCtrl.refreshToday,
                          ),
                      ],
                    ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Today's unfinished jobs — what every map layer draws from.
  List<DispatchJob> get _activeJobs =>
      _jobsCtrl.jobs.where((j) => !j.isFinished).toList();

  /// The focused job: selected, geocoded and not hidden by the route
  /// preview. Null means overview (or preview) mode.
  DispatchJob? _focusedJob(List<DispatchJob> jobs) {
    if (_jobsCtrl.routePreview.value) return null;
    final id = _jobsCtrl.selectedJobId.value;
    final job = id == null ? null : jobs.firstWhereOrNull((j) => j.id == id);
    return job != null && job.lat != null && job.lng != null ? job : null;
  }

  /// Job pins. Focused: the one job, not tappable. Overview: every geocoded
  /// job. Preview: the same, in route order. Rebuilds on jobs / selection /
  /// preview changes only — never on a GPS fix or a route-reveal frame.
  late final Widget _jobPinsLayer = Obx(() {
    final jobs = _activeJobs;
    final focused = _focusedJob(jobs);
    final List<DispatchJob> shown;
    if (focused != null) {
      shown = [focused];
    } else {
      shown = jobs.where((j) => j.lat != null && j.lng != null).toList();
      if (_jobsCtrl.routePreview.value) {
        shown.sort((a, b) =>
            (a.routeOrder ?? 1 << 30).compareTo(b.routeOrder ?? 1 << 30));
      }
    }
    return FlutterMapWidget.markerLayer(
      [
        for (final j in shown)
          MapMarkerModel(
            id: 'job_${j.id}',
            position: GeoPoint(j.lat!, j.lng!),
            title: j.jobName,
            subtitle: j.address,
            data: focused == null ? j.id : null,
            label: _stopNumberOf(j, jobs).toString(),
          ),
      ],
      onMarkerTap: (m) {
        final id = m.data;
        if (id is int) {
          final j = jobs.firstWhereOrNull((x) => x.id == id);
          if (j != null) _select(j);
        }
      },
    );
  });

  /// The rider's dot and heading cone. Rebuilds on GPS fixes only. Hidden in
  /// the route preview, which is about the job route.
  late final Widget _riderLayer = Obx(() {
    final rider = _jobsCtrl.riderPos.value;
    if (rider == null || _jobsCtrl.routePreview.value) {
      return const SizedBox.shrink();
    }
    return FlutterMapWidget.markerLayer([
      MapMarkerModel(
        id: 'rider',
        position: rider,
        title: 'You',
        kind: MapMarkerKind.rider,
        rotation: _jobsCtrl.riderHeading.value,
      ),
    ]);
  });

  /// The route line — rider → target, or the all-jobs preview line — revealed
  /// point by point. Rebuilds once per reveal frame, and only itself.
  late final Widget _routeLayer = Obx(() {
    final preview = _jobsCtrl.routePreview.value;
    final points = preview
        ? _jobsCtrl.previewRoutePoints.value
        : _jobsCtrl.routePoints.value;
    final reveal = preview
        ? _jobsCtrl.previewRevealCount.value
        : _jobsCtrl.routeRevealCount.value;
    if (points == null || points.length < 2 || reveal < 2) {
      return const SizedBox.shrink();
    }
    return FlutterMapWidget.polylineLayer([
      MapZoneModel(
        id: preview ? 'preview_route' : 'route',
        type: MapZoneType.polyline,
        points: points.sublist(0, reveal.clamp(2, points.length)),
        style: preview
            ? const MapZoneStyle(
                strokeColorHex: _kPreviewRouteHex,
                strokeWidth: 4,
                strokeOpacity: 0.9,
              )
            : const MapZoneStyle(
                strokeColorHex: _kRouteHex,
                strokeWidth: 4,
                strokeOpacity: 0.85,
              ),
      ),
    ]);
  });

  /// The map. Its reactive state is split so each part rebuilds alone: this
  /// Obx reads only what moves the camera and rebuilds [FlutterMapWidget]
  /// (whose tile layer is built once); the pins, the rider dot and the route
  /// line are the long-lived Obx layers above, inside the map.
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
            final jobs = _activeJobs;
            final focused = _focusedJob(jobs);
            final rider = _jobsCtrl.riderPos.value;
            final followRider = _jobsCtrl.followRider.value;
            final recenterTick = _jobsCtrl.recenterTick.value;

            var camera = _jobsCtrl.routePreview.value
                ? _previewCamera(jobs)
                : focused != null
                    ? _focusedCamera(focused, rider)
                    : _overviewCamera(jobs, rider);
            if (followRider && rider != null) {
              // Follow mode pins the rider — no bounds, so the map uses the
              // center/zoom path.
              camera = _Camera(center: rider, zoom: 17);
            }

            // How much of the map's bottom edge the panel currently covers.
            // The map insets its camera by this much so the framed route never
            // hides behind the panel; carousel mode uses its fixed 132px.
            final screenH = mq.size.height;
            final bottomInset = focused != null
                ? screenH * _panelFrac.value
                : (jobs.isEmpty ? 0.0 : _carouselHeight(context)) + bottomSafe;

            // flutter_map directly rather than AdaptiveMap: the 4W map is
            // OpenStreetMap by decision, and the scoped layers are its own.
            return FlutterMapWidget(
              key: const ValueKey('dispatchmap'),
              center: camera.center,
              zoom: camera.zoom,
              recenterTick: recenterTick,
              fitBounds: camera.bounds,
              bottomInset: bottomInset,
              topInset: mapTopInset,
              layers: [_routeLayer, _jobPinsLayer, _riderLayer],
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
          child: _MapTopBar(jobsCtrl: _jobsCtrl),
        ),
        // Pending-sync indicator — sits just below the floating top island.
        if (Get.isRegistered<DispatchSyncService>())
          Positioned(
            top: statusBar + _kTopBarTop + _kTopBarHeight + 4,
            left: 12,
            child: Obx(() {
              final count =
                  Get.find<DispatchSyncService>().pendingCount.value;
              // Fades in and out instead of popping.
              return AnimatedSwitcher(
                duration: Motion.of(context, Motion.short),
                child: count == 0
                    ? const SizedBox.shrink()
                    : Material(
                        key: const ValueKey('pending'),
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
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: palette.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              );
            }),
          ),
        // Recenter button — anchored just above whatever occupies the bottom:
        // the top edge of the focus panel when one is open, otherwise the
        // carousel. Glued to the panel as it is dragged, rides the layers
        // down and up through a swap, and fades out once the panel (nearly)
        // fills the screen.
        Positioned.fill(
          child: Obx(() {
            final focused = _jobsCtrl.selectedJobId.value != null;
            final hasCarousel = _jobsCtrl.jobs.any((j) => !j.isFinished);
            final frac = _panelFracLive.value;
            final dragging = _panelDragging.value || _swapping.value;
            // No usable map left to recenter once the panel is dragged up to
            // (nearly) fill the screen — fade the button away.
            final hidden = focused && frac > 0.8;
            return Align(
              alignment: Alignment.bottomRight,
              child: AnimatedBuilder(
                animation: Listenable.merge([_cards, _panel]),
                builder: (context, child) => AnimatedPadding(
                  // Snap instantly while the panel is being dragged (or the
                  // layers are swapping) so the button tracks the edge with
                  // no lag; ease only on settle.
                  duration: dragging
                      ? Duration.zero
                      : Motion.of(context, Motion.medium),
                  curve: Motion.standard,
                  padding: EdgeInsets.only(
                      right: 8,
                      bottom:
                          _bottomEdge(context, hasCarousel: hasCarousel) + 12),
                  child: child,
                ),
                child: AnimatedOpacity(
                  duration: Motion.of(context, Motion.short),
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
                      // Centring on the rider needs a fix — explain and
                      // offer to turn location on instead of doing nothing.
                      onPressed: !focused && _locationOff.value != null
                          ? _enableLocation
                          : _jobsCtrl.recenterOnRider,
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

      if (selected != null) _panelJob = selected;
      // In flight, or about to start on this frame's post-frame callback.
      final swapping = _swapping.value || isFocused != _panelShown;
      if (isFocused != _panelShown) {
        // After the frame: the swap moves the recenter button and banners
        // too, and they can't be marked dirty from inside this build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _swapTo(isFocused);
        });
      }
      final panelJob = _panelJob;

      // Both layers are bottom-aligned, and the one that is off is only
      // mounted while it slides out.
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          if (jobs.isNotEmpty && (!isFocused || swapping))
            SlideTransition(
              key: const ValueKey('cards-layer'),
              position: _cardsSlide,
              child: SafeArea(
                key: const ValueKey('carousel'),
                top: false,
                child: SizedBox(
                  height: _carouselHeight(context),
                  child: _JobCarousel(
                    jobs: jobs,
                    etaMeters: _jobsCtrl.etaMeters.value,
                    onSelect: _select,
                  ),
                ),
              ),
            ),
          if (panelJob != null && (isFocused || swapping))
            SlideTransition(
              key: const ValueKey('panel-layer'),
              position: _panelSlide,
              child: _FocusedJobPanel(
                key: ValueKey('panel_${panelJob.id}'),
                job: panelJob,
                stopNumber: panelJob.routeOrder ??
                    (jobs.indexWhere((j) => j.id == panelJob.id) + 1),
                etaMeters: _jobsCtrl.etaMeters.value,
                starting: _starting,
                hasOtherActive:
                    jobs.any((j) => j.isOnTheWay && j.id != panelJob.id),
                isNextInQueue: panelJob.id ==
                    jobs
                        .firstWhereOrNull(
                            (j) => !j.isOnTheWay && !j.isReschedulePending)
                        ?.id,
                onClose: _jobsCtrl.clearSelection,
                onStart: () => _startJob(panelJob.id),
                onFinish: () =>
                    Get.to(() => DispatchFinishJobPage(jobId: panelJob.id)),
                onFracChanged: (f) => _panelFrac.value = f,
                onFracLive: (f) => _panelFracLive.value = f,
                panelDragging: _panelDragging,
              ),
            ),
        ],
      );
    });
  }

  _Camera _focusedCamera(DispatchJob selected, GeoPoint? rider) {
    final job = GeoPoint(selected.lat!, selected.lng!);
    if (rider == null) return _Camera(center: job, zoom: 16);
    final center = GeoPoint(
      (job.lat + rider.lat) / 2,
      (job.lng + rider.lng) / 2,
    );
    final meters = Geolocator.distanceBetween(
        rider.lat, rider.lng, job.lat, job.lng);
    // Frame the rider→job span so the route is fully visible above the panel.
    // Endpoints (not the revealing polyline) keep the box stable while the
    // line "draws on". A degenerate box — rider sitting on the job — falls
    // back to the center/zoom pair computed above.
    final span = GeoBounds.fromPoints([job, rider]);
    return _Camera(
      center: center,
      zoom: _zoomForMeters(meters),
      bounds: span.isPoint ? null : span,
    );
  }

  _Camera _overviewCamera(List<DispatchJob> jobs, GeoPoint? rider) {
    final first = jobs.firstWhereOrNull((j) => j.lat != null && j.lng != null);
    final center = rider ??
        (first != null ? GeoPoint(first.lat!, first.lng!) : _kFallbackCenter);
    return _Camera(center: center, zoom: 14);
  }

  /// Frames every unfinished geocoded job together so the whole day is in
  /// view, starting from the first stop in route order.
  _Camera _previewCamera(List<DispatchJob> jobs) {
    final stops = jobs.where((j) => j.lat != null && j.lng != null).toList()
      ..sort((a, b) =>
          (a.routeOrder ?? 1 << 30).compareTo(b.routeOrder ?? 1 << 30));
    final points = [for (final j in stops) GeoPoint(j.lat!, j.lng!)];
    final bounds = points.length >= 2 ? GeoBounds.fromPoints(points) : null;
    return _Camera(
      center: points.isNotEmpty ? points.first : _kFallbackCenter,
      zoom: 12,
      bounds: bounds != null && !bounds.isPoint ? bounds : null,
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

/// Where the map looks: [bounds] when set, else [center]/[zoom], which also
/// stay the initial camera.
class _Camera {
  const _Camera({required this.center, required this.zoom, this.bounds});
  final GeoPoint center;
  final double zoom;
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
            showDistance: job.id == etaTargetId,
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
    this.showDistance = true,
  });

  final DispatchJob job;
  final int stopNumber;
  final double? etaMeters;

  /// Only the carousel's eta target has a live distance; the other cards
  /// drop the DISTANCE field instead of showing "—".
  final bool showDistance;
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Capped so a long ORMECO flag or large text wraps the
                  // pills instead of squeezing the name off the card.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        DispatchJobStatus.of(job).pill(context),
                        if (job.externalStatusLabel != null) ...[
                          const SizedBox(height: 4),
                          DispatchExternalStatusPill(job: job),
                        ],
                      ],
                    ),
                  ),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
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
                  if (showDistance)
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

  static TextStyle? styleOf(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Colors.white.withValues(alpha: 0.9),
        letterSpacing: 0.8,
      );

  @override
  Widget build(BuildContext context) => Text(text, style: styleOf(context));
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foregroundColor ?? Colors.white,
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
  /// Hard floor for the peek size, used until the summary is measured.
  static const double _minFrac = 0.12;
  static const double _maxFrac = 0.88;

  /// Vertical extent of the drag handle (22 + 4 + 22) — added to the measured
  /// content when sizing the panel.
  static const double _handleHeight = 48;

  /// Key on the scrollable content column — its laid-out height is what the
  /// panel sizes itself to, so everything is visible without scrolling.
  final GlobalKey _contentKey = GlobalKey();

  /// Key on the pill/distance row — the last row of the summary block. Its
  /// bottom edge (relative to the content column) is the peek height.
  final GlobalKey _pillRowKey = GlobalKey();

  final ScrollController _scroll = ScrollController();

  double _frac = _kPanelMidFrac;
  bool _dragging = false;
  bool _entered = false;

  /// False until the content has been measured once. That first fit is
  /// instant, so the panel rises in at its full size rather than growing on
  /// the way up; later fits (sections, Accept) animate.
  bool _fitted = false;

  /// Height fraction at which the panel exactly fits its content with no
  /// scrolling — measured from the laid-out content on the first frame, and
  /// the panel's resting "open" anchor. Falls back to the mid default until
  /// measured.
  double _fitFrac = _kPanelMidFrac;

  /// Smallest height fraction: exactly the summary block (handle, stop/name/✕
  /// row, DESTINATION, divider, pills + distance) — measured, so a 3-line
  /// name or 1.3× text gets a taller peek. The content can't scroll here.
  double _peekFrac = _minFrac;

  bool get _atPeek => _frac <= _peekFrac + 0.005;

  /// Drag/tap snap anchors: collapsed peek, content-fit, near-full.
  List<double> get _anchors => [_peekFrac, _fitFrac, _maxFrac];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Rest at [target]: the peek shows the summary from its top, so scroll
  /// back up there before the physics lock it.
  void _settle(double target) {
    setState(() {
      _frac = target;
      _dragging = false;
    });
    if (_atPeek && _scroll.hasClients) _scroll.jumpTo(0);
    widget.onFracChanged(target);
    widget.onFracLive(target);
  }

  void _onDragStart(DragStartDetails _) {
    widget.panelDragging.value = true;
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails d, double screenH) {
    if (screenH <= 0) return;
    // Resize the panel live, but don't re-frame the map mid-drag — that's done
    // once on settle (_onDragEnd / _onHandleTap) so the camera doesn't thrash.
    setState(() {
      _frac = (_frac - d.delta.dy / screenH).clamp(_peekFrac, _maxFrac);
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
          orElse: () => _peekFrac,
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
    widget.panelDragging.value = false;
    _settle(target);
  }

  void _onHandleTap() {
    final double next;
    if (_frac <= _peekFrac + 0.02) {
      next = _fitFrac; // peek → open to full content
    } else if (_frac >= _maxFrac - 0.02) {
      next = _fitFrac; // near-full → back to content
    } else {
      next = _maxFrac; // content → near-full
    }
    _settle(next);
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
    double frac(double contentH) =>
        (_handleHeight + contentH + mq.padding.bottom) / screenH;
    final content = _contentKey.currentContext?.findRenderObject();
    final pillRow = _pillRowKey.currentContext?.findRenderObject();
    if (screenH > 0 && content is RenderBox && pillRow is RenderBox) {
      // Peek: down to the pill row's bottom edge plus the 16 gap under it —
      // the next caption starts exactly at the panel's edge, so no slack.
      final summaryH = pillRow
          .localToGlobal(Offset(0, pillRow.size.height), ancestor: content)
          .dy;
      _peekFrac = frac(summaryH + 16).clamp(_minFrac, _maxFrac);
      target = frac(content.size.height + 6).clamp(_peekFrac, _maxFrac);
    }
    // Capture whether the rider was sitting at the previous fit anchor
    // *before* we overwrite [_fitFrac] — otherwise the check below compares
    // against the new fit and always trips when the content grows, which is
    // exactly the case we want to follow (Accept → taller content).
    final wasAtPreviousFit = (_frac - _fitFrac).abs() < 0.02;
    if (!_fitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitted = true);
    }
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

  /// An ORMECO section expanded or collapsed: once its animation is done,
  /// re-fit the panel to the new content height.
  void _refitAfterSectionToggle(bool _) {
    Future.delayed(Motion.of(context, Motion.short), () {
      if (!mounted) return;
      WidgetsBinding.instance
        ..addPostFrameCallback(
            (_) => _openToFitContent(keepFracIfDragged: true))
        ..scheduleFrame();
    });
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
      // First build: lay out at roughly the carousel card's height, then —
      // once the content has laid out — snap to exactly fit it next frame,
      // still below the screen edge; the panel then rises at its full size.
      _entered = true;
      _frac = (_carouselHeight(context) / screenH).clamp(_peekFrac, _maxFrac);
      WidgetsBinding.instance.addPostFrameCallback((_) => _openToFitContent());
    }

    final height = screenH * _frac;
    final job = widget.job;
    const green = _DispatchJobCard._kCardGreen;
    // ORMECO sends no reason for a flag; its own notes (Remarks, Action
    // taken…) are the closest, so a flagged job shows them up here, under the
    // flag, and not again inside Detail / Action. Unflagged jobs keep them in
    // the sections only.
    final List<({String label, String value})> flaggedNotes =
        job.externalStatusLabel != null ? job.externalNotes : const [];
    final sections = [
      for (final section in job.externalDetails)
        if (flaggedNotes.isEmpty)
          section
        else if (section.fields.any((f) => !flaggedNotes.contains(f)))
          DispatchJobDetailSection(
            heading: section.heading,
            fields: [
              for (final f in section.fields)
                if (!flaggedNotes.contains(f)) f,
            ],
          ),
    ];
    final timeline = [
      for (final note in flaggedNotes)
        (label: note.label.toUpperCase(), value: note.value),
      if (job.scheduledArrival != null)
        (
          label: 'SCHEDULED',
          value: formatDispatchTimestamp(job.scheduledArrival),
        ),
      if (job.actualArrival != null)
        (label: 'STARTED', value: formatDispatchTimestamp(job.actualArrival)),
      if (job.finishWhen != null)
        (label: 'FINISHED', value: formatDispatchTimestamp(job.finishWhen)),
      if (job.notes != null && job.notes!.isNotEmpty)
        (label: 'NOTES', value: job.notes!),
    ];

    return Material(
      color: green,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: _dragging || !_fitted
            ? Duration.zero
            : Motion.of(context, Motion.medium),
        curve: Motion.standard,
        height: height,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle — a 48dp-tall labelled target (M3 sheet handle)
              // around the 4px grip; tap toggles the panel height.
              Semantics(
                button: true,
                label: 'Resize job panel',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onHandleTap,
                  onVerticalDragStart: _onDragStart,
                  onVerticalDragUpdate: (d) => _onDragUpdate(d, screenH),
                  onVerticalDragEnd: _onDragEnd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
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
              ),
              // Content — header + detail. The panel measures this column
              // (via [_contentKey]) and opens exactly tall enough to show all
              // of it; it scrolls only when dragged shorter than its content
              // — and not at all at the peek, which shows exactly the summary.
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  physics: _atPeek ? const NeverScrollableScrollPhysics() : null,
                  child: Column(
                    key: _contentKey,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header — mirrors the carousel card's header so the
                      // card visually "becomes" the panel. The close button
                      // sits on this row, centred on it; a long name wraps
                      // before it. Right padding 10 so the ✕ glyph's edge
                      // (8 in from its 40dp box) lands on the 18dp edge.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 10, 0),
                        child: Row(
                          children: [
                            Expanded(
                              // Centred: the disc, the name block and the ✕
                              // share one vertical centre, also when a long
                              // name wraps onto two or three lines.
                              child: Row(
                                children: [
                                  _StopNumber(
                                    number: widget.stopNumber,
                                    backgroundColor: Colors.white,
                                    foregroundColor: green,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      job.customer ?? job.jobName,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                        color: Colors.white,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Back to list',
                              // 40dp box; the padded tap target is still 48.
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close,
                                  color: Colors.white),
                              onPressed: widget.onClose,
                            ),
                          ],
                        ),
                      ),
                      // Detail: one 18dp edge, 4dp from caption to value,
                      // 16dp between groups.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                            const SizedBox(height: 16),
                            // Pills left, distance right; each drops to its
                            // own line when a long flag or large text won't
                            // fit them side by side.
                            SizedBox(
                              key: _pillRowKey,
                              // Full width, or spaceBetween has no room.
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      DispatchJobStatus.of(job).pill(context),
                                      if (job.externalStatusLabel != null)
                                        DispatchExternalStatusPill(job: job),
                                    ],
                                  ),
                                  if (widget.etaMeters != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.near_me_outlined,
                                            size: 15, color: Colors.white),
                                        const SizedBox(width: 4),
                                        Text(
                                          formatTravelDistance(
                                              widget.etaMeters!),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'away',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                            color: Colors.white
                                                .withValues(alpha: 0.75),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            if (timeline.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _FieldGrid(timeline, caps: true),
                            ],
                          ],
                        ),
                      ),
                      // ORMECO sections, inset 6 so each header's rounded
                      // highlight has room around it; the tile's 12dp padding
                      // keeps titles and fields on the 18dp edge.
                      if (sections.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                          child: Column(
                            children: [
                              for (final section in sections)
                                DispatchJobDetailSectionTile(
                                  section: section,
                                  onExpansionChanged: _refitAfterSectionToggle,
                                ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                        child: _PanelActions(
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
                          ),
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
      textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
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
              borderRadius: BorderRadius.circular(12),
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
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                        ),
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
                minimumSize: const Size.fromHeight(50),
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

/// The bottom carousel at its live height, and the focused job panel, for
/// widget tests that pump them without the map page around them.
/// The floating top island on the map: job list + route toggle on the left,
/// the job-progress summary in the middle, profile on the right.
class _MapTopBar extends StatelessWidget {
  const _MapTopBar({required this.jobsCtrl});

  final DispatchJobsController jobsCtrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Material(
      color: palette.control,
      elevation: 4,
      borderRadius: BorderRadius.circular(_kTopBarRadius),
      child: SizedBox(
        height: _kTopBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kTopBarInset),
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
                  final remaining = jobsCtrl.jobs
                      .where((j) => !j.isFinished)
                      .length;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE, MMM d')
                            .format(DateTime.now()),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                    final on = jobsCtrl.routePreview.value;
                    // Nothing to route with no jobs — grey it out.
                    final hasJobs =
                        jobsCtrl.jobs.any((j) => !j.isFinished);
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
                          ? jobsCtrl.toggleRoutePreview
                          : null,
                    );
                  }),
                  const Spacer(),
                  // Profile — a circle concentric with the island's round
                  // end, so its edge follows the curve with an even gap.
                  Material(
                    color: _DispatchJobCard._kCardGreen,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: Tooltip(
                      message: 'Profile',
                      child: InkWell(
                        onTap: () =>
                            Get.to(() => const DispatchProfilePage()),
                        // 48dp (13 + 22 + 13) for the tap-target minimum.
                        child: const Padding(
                          padding: EdgeInsets.all(13),
                          child: Icon(Icons.person,
                              color: Colors.white, size: 22),
                        ),
                      ),
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

@visibleForTesting
Widget debugMapTopBar(DispatchJobsController jobsCtrl) =>
    _MapTopBar(jobsCtrl: jobsCtrl);

@visibleForTesting
Widget debugJobCarousel(List<DispatchJob> jobs, {double? etaMeters}) =>
    Builder(
      builder: (context) => SizedBox(
        height: _carouselHeight(context),
        child: _JobCarousel(
            jobs: jobs, etaMeters: etaMeters, onSelect: (_) {}),
      ),
    );

@visibleForTesting
Widget debugFocusedJobPanel(DispatchJob job, {double? etaMeters}) =>
    _FocusedJobPanel(
      job: job,
      stopNumber: 1,
      etaMeters: etaMeters,
      starting: false.obs,
      hasOtherActive: false,
      isNextInQueue: true,
      onClose: () {},
      onStart: () {},
      onFinish: () {},
      onFracChanged: (_) {},
      onFracLive: (_) {},
      panelDragging: false.obs,
    );

/// One ORMECO details section, collapsed so the panel stays map-sized. Public
/// only so a widget test can pump it without the map page around it.
@visibleForTesting
class DispatchJobDetailSectionTile extends StatefulWidget {
  const DispatchJobDetailSectionTile({
    super.key,
    required this.section,
    this.onExpansionChanged,
  });
  final DispatchJobDetailSection section;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<DispatchJobDetailSectionTile> createState() =>
      _DispatchJobDetailSectionTileState();
}

class _DispatchJobDetailSectionTileState
    extends State<DispatchJobDetailSectionTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    // A shape clips the header's ink to rounded corners (and replaces the
    // theme dividers ExpansionTile draws above and below).
    const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)));
    return ExpansionTile(
      expansionAnimationStyle: AnimationStyle(
        duration: Motion.of(context, Motion.short),
        curve: Motion.standard,
      ),
      onExpansionChanged: (open) {
        setState(() => _open = open);
        widget.onExpansionChanged?.call(open);
      },
      shape: shape,
      collapsedShape: shape,
      clipBehavior: Clip.antiAlias,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      trailing: AnimatedRotation(
        turns: _open ? 0.5 : 0,
        duration: Motion.of(context, Motion.short),
        curve: Motion.standard,
        child: const Icon(Icons.keyboard_arrow_down_rounded,
            color: Colors.white),
      ),
      title: Text(
        widget.section.heading,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      children: [_FieldGrid(widget.section.fields)],
    );
  }
}

/// Label-above-value fields, two to a row where label and value each fit on
/// one line in half the width, so labels never wrap. Fields keep their order;
/// only one that doesn't fit takes a row alone, so a short field is never
/// left beside a gap.
class _FieldGrid extends StatelessWidget {
  const _FieldGrid(this.fields, {this.caps = false});
  final List<({String label, String value})> fields;

  /// Panel captions (SCHEDULED) instead of record labels (Account no).
  final bool caps;

  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    // Record labels: bold and a step smaller than the value, so a row reads
    // as "label, then value" at a glance. Tone can't carry the difference —
    // white at 0.9 on the green is already at the AA floor (4.5:1).
    final labelStyle = caps
        ? _CardLabel.styleOf(context)
        : Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
            );
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.white,
          height: 1.3,
        );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    Widget field(({String label, String value}) f) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label, style: labelStyle),
            const SizedBox(height: 2),
            Text(f.value, style: valueStyle),
          ],
        );

    return LayoutBuilder(builder: (context, constraints) {
      final half = (constraints.maxWidth - _gap) / 2;
      bool fitsHalf(String text, TextStyle? style) {
        if (text.contains('\n')) return false;
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textScaler: scaler,
          textDirection: direction,
          maxLines: 1,
        )..layout(maxWidth: half);
        final fits = !painter.didExceedMaxLines;
        painter.dispose();
        return fits;
      }

      final halves = [
        for (final f in fields)
          fitsHalf(f.label, labelStyle) && fitsHalf(f.value, valueStyle),
      ];
      final rows = <Widget>[];
      for (var i = 0; i < fields.length; i++) {
        final next = i + 1;
        if (next < fields.length && halves[i] && halves[next]) {
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: field(fields[i])),
              const SizedBox(width: _gap),
              Expanded(child: field(fields[next])),
            ],
          ));
          i++;
        } else {
          rows.add(field(fields[i]));
        }
      }
      // Record rows sit on hairlines, like a table; the panel captions keep
      // their plain gap.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: caps ? 10 : 8,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0 && !caps)
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            rows[i],
          ],
        ],
      );
    });
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({
    required this.message,
    required this.onAction,
    this.icon = Icons.cloud_off,
    this.actionLabel = 'Retry',
  });
  final String message;
  final VoidCallback onAction;
  final IconData icon;
  final String actionLabel;

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
            Icon(icon, size: 18, color: _amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.ink,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: DispatchColors.brand,
                textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                minimumSize: const Size(56, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// The job card, for widget tests that pump it without the map page around it.
@visibleForTesting
Widget debugJobCard(DispatchJob job, {double? etaMeters}) => _DispatchJobCard(
      job: job,
      stopNumber: 1,
      etaMeters: etaMeters,
      onTap: () {},
    );
