import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_navigation.dart';
import '../../../core/models/geo.dart';
import '../../../core/widgets/adaptive_map.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../controller/dispatch_auth_controller.dart';
import '../controller/dispatch_jobs_controller.dart';
import '../service/dispatch_sync_service.dart';
import 'dispatch_finish_job_page.dart';
import 'dispatch_job_history_page.dart';

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

class _DispatchJobsPageState extends State<DispatchJobsPage> {
  final RxnInt _selectedId = RxnInt();
  final Rxn<GeoPoint> _riderPos = Rxn<GeoPoint>();
  final RxBool _locating = false.obs;
  final RxBool _starting = false.obs;

  late final DispatchJobsController _jobsCtrl;
  late final DispatchAuthController _authCtrl;

  @override
  void initState() {
    super.initState();
    _jobsCtrl = Get.put(DispatchJobsController());
    _authCtrl = Get.find<DispatchAuthController>();
  }

  /// One-shot rider fix. We deliberately do NOT subscribe to the position
  /// stream here — every emission would invalidate the map's ValueKey and
  /// tear down the native GoogleMap view, which crashes on lower-end devices.
  /// The user can hit the recenter FAB to refresh.
  Future<void> _refreshRiderPosition({bool force = false}) async {
    if (_locating.value) return;
    if (!force && _riderPos.value != null) return;
    _locating.value = true;
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
      _locating.value = false;
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
    _refreshRiderPosition();
    _jobsCtrl.fetchDetail(job.id);
  }

  void _clearSelection() {
    _selectedId.value = null;
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
            tooltip: 'Completed jobs',
            icon: const Icon(Icons.history),
            onPressed: () => Get.to(() => const DispatchJobHistoryPage()),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmSignOut,
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
          final activeJobs =
              _jobsCtrl.jobs.where((j) => !j.isFinished).toList();
          if (activeJobs.isEmpty) {
            return _EmptyState(
              rider: _authCtrl.rider.value?.fullname,
              allFinished: _jobsCtrl.jobs.isNotEmpty,
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

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _authCtrl.logout();
    }
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

            final mapData = isFocused
                ? _focusedMapData(selected, rider)
                : _overviewMapData(jobs);

            return AdaptiveMap(
              // Stable key: only changes when we switch between overview and
              // a different focused job. Marker / rider updates do NOT
              // rebuild the native map view.
              key: ValueKey(isFocused
                  ? 'dispatchmap_focus_${selected.id}'
                  : 'dispatchmap_overview'),
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
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'refresh',
                onPressed: _jobsCtrl.refreshToday,
                child: const Icon(Icons.refresh),
              ),
              const SizedBox(height: 8),
              Obx(() {
                if (_selectedId.value == null) return const SizedBox.shrink();
                return FloatingActionButton.small(
                  heroTag: 'recenter',
                  tooltip: 'Recenter on me',
                  onPressed: () => _refreshRiderPosition(force: true),
                  child: Obx(() => _locating.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location)),
                );
              }),
            ],
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

      return AnimatedSize(
        duration: _kPanelAnim,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
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
              ? _FocusedJobPanel(
                  key: ValueKey('panel_${selected.id}'),
                  job: selected,
                  riderListenable: _riderPos,
                  starting: _starting,
                  onClose: _clearSelection,
                  onStart: () => _startJob(selected.id),
                  onFinish: () =>
                      Get.to(() => DispatchFinishJobPage(jobId: selected.id)),
                )
              : SizedBox(
                  key: const ValueKey('carousel'),
                  height: 168,
                  child: _JobCarousel(
                    jobs: jobs,
                    onSelect: _select,
                  ),
                ),
        ),
      );
    });
  }

  _MapData _focusedMapData(DispatchJob selected, GeoPoint? rider) {
    final job = GeoPoint(selected.lat!, selected.lng!);
    final markers = <MapMarkerModel>[
      MapMarkerModel(
        id: 'job_${selected.id}',
        position: job,
        title: selected.jobName,
        subtitle: selected.address,
      ),
      if (rider != null)
        MapMarkerModel(id: 'rider', position: rider, title: 'You'),
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
    return _MapData(
      center: center,
      zoom: _zoomForMeters(meters),
      markers: markers,
      zones: [
        MapZoneModel(
          id: 'route',
          type: MapZoneType.polyline,
          points: [rider, job],
          style: const MapZoneStyle(
            strokeColorHex: '#1976D2',
            strokeWidth: 4,
            strokeOpacity: 0.85,
          ),
        ),
      ],
    );
  }

  _MapData _overviewMapData(List<DispatchJob> jobs) {
    final geoJobs =
        jobs.where((j) => j.lat != null && j.lng != null).toList();
    final markers = geoJobs
        .map((j) => MapMarkerModel(
              id: 'job_${j.id}',
              position: GeoPoint(j.lat!, j.lng!),
              title: j.jobName,
              subtitle: j.address,
              data: j.id,
            ))
        .toList(growable: false);
    final center = geoJobs.isNotEmpty
        ? GeoPoint(geoJobs.first.lat!, geoJobs.first.lng!)
        : _kFallbackCenter;
    return _MapData(center: center, zoom: 14, markers: markers);
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
    required this.onSelect,
  });

  final List<DispatchJob> jobs;
  final ValueChanged<DispatchJob> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: jobs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final job = jobs[i];
        return SizedBox(
          width: 280,
          child: _DispatchJobCard(
            job: job,
            selected: false,
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
    required this.selected,
    required this.onTap,
  });

  final DispatchJob job;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = _statusBadge(job, scheme);
    final hasGeo = job.lat != null && job.lng != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: selected ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.jobName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (!hasGeo)
                    const Tooltip(
                      message: 'No coordinates',
                      child: Icon(Icons.location_off,
                          size: 16, color: Colors.grey),
                    ),
                ],
              ),
              if (job.address != null && job.address!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place_outlined, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        job.address!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              if (job.scheduledArrival != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        job.scheduledArrival!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: color),
                    const SizedBox(width: 4),
                    Text(label,
                        style: TextStyle(color: color, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, Color, IconData) _statusBadge(DispatchJob job, ColorScheme scheme) {
    if (job.isFinished) {
      return ('Finished', Colors.green, Icons.verified_outlined);
    }
    if (job.isOnTheWay) {
      return ('On the way', scheme.primary, Icons.timelapse);
    }
    if (job.isReschedulePending) {
      return ('Reschedule pending', Colors.orange, Icons.event_repeat);
    }
    return ('Assigned', scheme.primary, Icons.outlined_flag);
  }
}

/// Detail panel that takes the bottom half of the screen when a job is
/// promoted. Reuses controller state so background detail refreshes
/// (notes/photos) flow in automatically.
class _FocusedJobPanel extends StatelessWidget {
  const _FocusedJobPanel({
    super.key,
    required this.job,
    required this.riderListenable,
    required this.starting,
    required this.onClose,
    required this.onStart,
    required this.onFinish,
  });

  final DispatchJob job;
  final Rxn<GeoPoint> riderListenable;
  final RxBool starting;
  final VoidCallback onClose;
  final VoidCallback onStart;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.5;
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = _badge(scheme);

    return Material(
      color: scheme.surface,
      elevation: 8,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        job.jobName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Back to list',
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 14, color: color),
                          const SizedBox(width: 4),
                          Text(label,
                              style:
                                  TextStyle(color: color, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Obx(() {
                      final text = _distanceLabel(riderListenable.value);
                      if (text == null) return const SizedBox.shrink();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.alt_route,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(text,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (job.address != null && job.address!.isNotEmpty)
                          _InfoRow(
                            icon: Icons.place_outlined,
                            label: 'Address',
                            value: job.address!,
                          ),
                        if (job.scheduledArrival != null)
                          _InfoRow(
                            icon: Icons.schedule,
                            label: 'Scheduled',
                            value: job.scheduledArrival!,
                          ),
                        if (job.actualArrival != null)
                          _InfoRow(
                            icon: Icons.flag_outlined,
                            label: 'Started',
                            value: job.actualArrival!,
                          ),
                        if (job.finishWhen != null)
                          _InfoRow(
                            icon: Icons.verified_outlined,
                            label: 'Finished',
                            value: job.finishWhen!,
                          ),
                        if (job.notes != null && job.notes!.isNotEmpty)
                          _InfoRow(
                            icon: Icons.notes,
                            label: 'Notes',
                            value: job.notes!,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _PanelActions(
                  job: job,
                  starting: starting,
                  onStart: onStart,
                  onFinish: onFinish,
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
      ),
    );
  }

  String? _distanceLabel(GeoPoint? rider) {
    if (rider == null || job.lat == null || job.lng == null) return null;
    final m = Geolocator.distanceBetween(
        rider.lat, rider.lng, job.lat!, job.lng!);
    if (m < 1000) return '${m.round()} m away';
    return '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km away';
  }

  (String, Color, IconData) _badge(ColorScheme scheme) {
    if (job.isFinished) {
      return ('Finished', Colors.green, Icons.verified_outlined);
    }
    if (job.isOnTheWay) return ('On the way', scheme.primary, Icons.timelapse);
    if (job.isReschedulePending) {
      return ('Reschedule pending', Colors.orange, Icons.event_repeat);
    }
    return ('Assigned', scheme.primary, Icons.outlined_flag);
  }
}

class _PanelActions extends StatelessWidget {
  const _PanelActions({
    required this.job,
    required this.starting,
    required this.onStart,
    required this.onFinish,
    required this.onNavigate,
  });

  final DispatchJob job;
  final RxBool starting;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    if (job.isFinished || job.isReschedulePending) {
      return const SizedBox.shrink();
    }

    final hasCoords = job.lat != null && job.lng != null;
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
                  onPressed: starting.value ? null : onStart,
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
      children: [
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.rider, this.allFinished = false});
  final String? rider;
  final bool allFinished;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(
          allFinished ? Icons.verified_outlined : Icons.task_alt,
          size: 64,
          color: allFinished ? Colors.green.shade400 : Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            allFinished
                ? 'All jobs finished. Tap History to review.'
                : 'No jobs assigned for today.',
          ),
        ),
        const SizedBox(height: 24),
        if (rider != null)
          Center(
            child: Text(
              'Signed in as $rider',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
      ],
    );
  }
}

