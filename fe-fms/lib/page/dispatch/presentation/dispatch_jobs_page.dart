import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_format.dart';
import '../../../core/dispatch/dispatch_navigation.dart';
import '../../../core/models/geo.dart';
import '../../../core/widgets/adaptive_map.dart';
import '../../../core/widgets/snackbar_utils.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../controller/dispatch_jobs_controller.dart';
import '../service/dispatch_sync_service.dart';
import 'dispatch_finish_job_page.dart';
import 'dispatch_profile_page.dart';

const GeoPoint _kFallbackCenter = GeoPoint(14.5995, 120.9842); // Manila
const Duration _kPanelAnim = Duration(milliseconds: 320);

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
  late final DispatchJobsController _jobsCtrl;

  @override
  void initState() {
    super.initState();
    // Reuse the existing instance if the dispatch session already
    // initialised it — preserves rider/route/ETA state across page rebuilds.
    _jobsCtrl = Get.isRegistered<DispatchJobsController>()
        ? Get.find<DispatchJobsController>()
        : Get.put(DispatchJobsController());
  }

  void _select(DispatchJob job) {
    final ok = _jobsCtrl.selectJob(job);
    if (!ok) {
      SnackbarUtils(
        text: 'This job has no coordinates yet.',
        backgroundColor: Colors.grey.shade700,
        icon: Icons.location_off,
      ).showErrorSnackBar(context);
    }
  }

  Future<void> _startJob(int jobId) async {
    _starting.value = true;
    try {
      await _jobsCtrl.startJob(jobId);
      if (!mounted) return;
      SnackbarUtils(
        text: 'Job accepted.',
        backgroundColor: Colors.green,
      ).showSuccessSnackBar(context);
    } on DispatchQueuedException {
      if (!mounted) return;
      SnackbarUtils(
        text: 'Saved offline. Will sync when online.',
        backgroundColor: Colors.orange,
        icon: Icons.cloud_off,
      ).showErrorSnackBar(context);
    } on DispatchApiException catch (e) {
      if (!mounted) return;
      SnackbarUtils(
        text: e.message,
        backgroundColor: e.isConflict ? Colors.orange : Colors.red,
      ).showErrorSnackBar(context);
    } catch (e) {
      if (!mounted) return;
      SnackbarUtils(
        text: e.toString(),
        backgroundColor: Colors.red,
      ).showErrorSnackBar(context);
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
              // change the map's parent size.
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

  /// Scoped Obx around the map.
  Widget _buildMapArea() {
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
            final isFocused = selected != null &&
                selected.lat != null &&
                selected.lng != null;
            final rider = _jobsCtrl.riderPos.value;
            final route = _jobsCtrl.routePoints.value;
            final reveal = _jobsCtrl.routeRevealCount.value;
            final followRider = _jobsCtrl.followRider.value;

            var mapData = isFocused
                ? _focusedMapData(selected, rider, route, reveal)
                : _overviewMapData(jobs, rider, route, reveal);
            if (followRider && rider != null) {
              mapData = _MapData(
                center: rider,
                zoom: 17,
                markers: mapData.markers,
                zones: mapData.zones,
              );
            }

            return AdaptiveMap(
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
            onPressed: _jobsCtrl.recenterOnRider,
            child: Obx(() => _jobsCtrl.locating.value
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
      final jobs =
          _jobsCtrl.jobs.where((j) => !j.isFinished).toList();
      final selectedId = _jobsCtrl.selectedJobId.value;
      final selected = selectedId == null
          ? null
          : jobs.firstWhereOrNull((j) => j.id == selectedId);
      final isFocused = selected != null;

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
                );
              }()
            : SizedBox(
                key: const ValueKey('carousel'),
                height: 132,
                child: _JobCarousel(
                  jobs: jobs,
                  etaMeters: _jobsCtrl.etaMeters.value,
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
    if (jobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SizedBox(width: 280, child: const _EmptyJobCard()),
      );
    }
    final nextId = jobs
        .firstWhereOrNull((j) => !j.isOnTheWay && !j.isReschedulePending)
        ?.id;
    final etaTargetId = jobs.firstWhereOrNull((j) => j.isOnTheWay)?.id ??
        nextId;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: jobs.length,
      separatorBuilder: (_, _) => const _CarouselConnector(),
      itemBuilder: (context, i) {
        final job = jobs[i];
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
                        _JobStatusPill(job: job),
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
  final double? etaMeters;
  final RxBool starting;
  final bool hasOtherActive;
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
