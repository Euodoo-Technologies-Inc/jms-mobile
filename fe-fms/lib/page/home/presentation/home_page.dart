import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/widgets/adaptive_map.dart';
import 'package:fms/core/widgets/object_status_bottom_sheet.dart';
import 'package:fms/page/home/controller/home_controller.dart';
import 'package:fms/page/vehicles/presentation/vehicle_tracking_page.dart';
import 'package:fms/core/services/subscription.dart';
import 'package:fms/data/models/traxroot_object_status_model.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import 'package:fms/core/widgets/skeleton_loading.dart';

import '../../../core/models/geo.dart';

/// The main home tab widget displaying the dashboard and map.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

/// A full-screen map view page.
class FullMapPage extends StatelessWidget {
  const FullMapPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<HomeController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: Obx(
        () => controller.isLoading.value
            ? const Center(child: CircularProgressIndicator())
            : AdaptiveMap(
                center: controller.mapCenter,
                zoom: 12.5,
                markers: controller.markers,
                zones: controller.zones,
                onMarkerTap: (marker) =>
                    _onFullMapMarkerTap(context, controller, marker),
              ),
      ),
    );
  }

  void _onFullMapMarkerTap(
    BuildContext context,
    HomeController controller,
    MapMarkerModel marker,
  ) {
    final status = controller.findStatusForMarker(marker);
    if (status == null) {
      return;
    }

    final iconUrl =
        marker.iconUrl ?? (status.id != null ? controller.iconUrlByObjectId[status.id!] : null);

    Get.to(() => VehicleTrackingPage(vehicle: status, iconUrl: iconUrl));
  }
}

class _MovingVehicleBanner extends StatelessWidget {
  const _MovingVehicleBanner({
    required this.status,
    required this.iconUrl,
    required this.message,
    required this.isMove,
  });

  final TraxrootObjectStatusModel status;
  final String? iconUrl;
  final String message;
  final bool isMove;

  @override
  Widget build(BuildContext context) {
    final name = status.name ?? status.trackerId ?? 'Vehicle';
    final theme = Theme.of(context);
    final bgColor = isMove ? theme.colorScheme.primaryContainer : theme.colorScheme.secondaryContainer;

    return Card(
      color: bgColor,
      child: ListTile(
        leading: const Icon(Icons.directions_car),
        title: Text('$name $message'),
        onTap: () {
          Get.to(() => VehicleTrackingPage(vehicle: status, iconUrl: iconUrl));
        },
      ),
    );
  }
}

class _HomeTabState extends State<HomeTab> {
  bool _isMarkerLoading = false;
  Timer? _autoTimer;
  late final String? _userRole;

  @override
  void initState() {
    super.initState();
    // Read role synchronously from AuthController (set during checkSession)
    _userRole = Get.find<AuthController>().userRole.value?.toLowerCase().trim();

    final controller = Get.put(HomeController());

    // Only start vehicle position polling for roles that display the map
    if (_userRole != 'field') {
      _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        if (!controller.isLoading.value) {
          controller.refreshStatuses();
        }
      });
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleMarkerTap(
    BuildContext context,
    HomeController controller,
    MapMarkerModel marker,
  ) async {
    if (_isMarkerLoading) return;

    final status = controller.findStatusForMarker(marker);
    if (status == null) return;

    if (mounted) {
      setState(() => _isMarkerLoading = true);
    }

    // Fetch sensor data if object ID is available
    var statusWithSensors = status;
    if (status.id != null) {
      try {
        final withSensors = await controller.getObjectWithSensors(status.id!);
        if (withSensors != null) {
          statusWithSensors = withSensors;
        }
      } catch (e) {
        print('Failed to fetch sensors: $e');
        // Continue with status without sensors
      }
    }

    if (!mounted) return;

    final enrichedStatus =
        statusWithSensors.name != null && statusWithSensors.name!.isNotEmpty
            ? statusWithSensors
            : statusWithSensors.copyWith(name: marker.title);

    final resolvedIconUrl =
        marker.iconUrl ?? (enrichedStatus.id != null ? controller.iconUrlByObjectId[enrichedStatus.id!] : null);

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ObjectStatusBottomSheet(
        status: enrichedStatus,
        iconUrl: resolvedIconUrl,
        onTrack: enrichedStatus.id != null
            ? () {
                Get.back();
                Get.to(() => VehicleTrackingPage(vehicle: enrichedStatus, iconUrl: resolvedIconUrl));
              }
            : null,
      ),
    );

    if (mounted) {
      setState(() => _isMarkerLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<HomeController>();
    final isPro = subscriptionService.currentPlan == Plan.pro;
    final showMap = (_userRole != 'field'); // hide map for 'field'
    final showOverview = isPro && (_userRole != 'monitor'); // hide overview for basic users & Pro monitors

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: RefreshIndicator(
        onRefresh: controller.loadData,
        child: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (showMap)
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: controller.isLoading.value ? null : controller.loadData,
                      icon: const Icon(Icons.refresh),
                    ),
                  if (showMap)
                    IconButton(
                      tooltip: 'Full map',
                      onPressed: () {
                        Get.to(() => const FullMapPage());
                      },
                      icon: const Icon(Icons.fullscreen),
                    ),
                ],
              ),

              // Map area or Overview when map hidden for 'field'
              Expanded(
                child: controller.isLoading.value
                    ? ShimmerProvider(
                        child: showMap && showOverview
                            ? Column(
                                children: const [
                                  Expanded(child: SkeletonMapPlaceholder()),
                                  SizedBox(height: 12),
                                  SkeletonStatCards(),
                                ],
                              )
                            : showMap
                                ? const SkeletonMapPlaceholder()
                                : showOverview
                                    ? const SingleChildScrollView(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            SizedBox(height: 8),
                                            SkeletonStatCards(),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                      )
                    : showMap
                        ? Stack(
                            children: [
                              AdaptiveMap(
                                center: controller.mapCenter,
                                zoom: 12.5,
                                markers: controller.markers,
                                zones: controller.zones,
                                onMarkerTap: (marker) => _handleMarkerTap(context, controller, marker),
                              ),
                              Obx(() {
                                final movingList = controller.movingObjects;
                                if (movingList.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                return Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 16,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (final moving in movingList)
                                          _MovingVehicleBanner(
                                            status: moving,
                                            iconUrl: moving.id != null ? controller.iconUrlByObjectId[moving.id!] : null,
                                            message: moving.id != null
                                                ? (controller.lastMovementTextByObjectId[moving.id!] ?? 'is moving')
                                                : 'is moving',
                                            isMove: moving.id != null
                                                ? ((controller.lastMovementTypeByObjectId[moving.id!] ?? '') == 'MOVE' ||
                                                    (controller.lastMovementTextByObjectId[moving.id!]?.toLowerCase().contains('moving') ?? false))
                                                : false,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              if (_isMarkerLoading)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.15),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : (showOverview
                            ? SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 8),
                                    Text('Overview', style: Theme.of(context).textTheme.titleMedium),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _StatCard(
                                            title: 'Open',
                                            value: controller.openJobsCount.toString(),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _StatCard(
                                            title: 'Ongoing',
                                            value: controller.ongoingJobsCount.toString(),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _StatCard(
                                            title: 'Complete',
                                            value: controller.completedJobsCount.toString(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            : Center(
                                child: Text(
                                  'Overview not available',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                                ),
                              ) ),
              ),

              if (showMap && controller.error.value.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  controller.error.value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
              const SizedBox(height: 16),

              // Show the detailed Overview below the map only when allowed
              if (showOverview && showMap) ...[
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overview',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Open Jobs',
                        value: controller.openJobsCount.toString(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'Ongoing',
                        value: controller.ongoingJobsCount.toString(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'Complete',
                        value: controller.completedJobsCount.toString(),
                      ),
                    ),
                  ],
                ),
              ],

              // if (!isPro) ...[
              //   const SizedBox(height: 8),
              //   Text(
              //     'Upgrade to Pro to access Job',
              //     textAlign: TextAlign.center,
              //     style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              //   ),
              // ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}