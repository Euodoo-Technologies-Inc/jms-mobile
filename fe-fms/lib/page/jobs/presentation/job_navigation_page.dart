import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/models/geo.dart';
import '../../../core/theme/dispatch_palette.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../core/widgets/adaptive_map.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/object_status_bottom_sheet.dart';
import '../../../data/models/traxroot_object_status_model.dart';
import '../../vehicles/presentation/vehicle_tracking_page.dart';
import '../controller/job_navigation_controller.dart';

/// A page for navigating to a job location using a map.
class JobNavigationPage extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String jobName;
  final String? address;
  const JobNavigationPage({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.jobName,
    this.address,
  });

  @override
  State<JobNavigationPage> createState() => _JobNavigationPageState();
}

class _JobNavigationPageState extends State<JobNavigationPage> {
  late final JobNavigationController _controller;

  GeoPoint get _jobPoint => GeoPoint(widget.latitude, widget.longitude);

  @override
  void initState() {
    super.initState();
    _controller = Get.put(JobNavigationController());
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final warnings = await _controller.loadData(
      jobPoint: _jobPoint,
      jobName: widget.jobName,
      address: widget.address,
    );
    if (warnings.isNotEmpty && mounted) {
      AppFeedback.info(warnings.join('\n'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return DetailScaffold(
      title: 'Job navigation',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _controller.isLoading.value ? null : _loadData,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Obx(() {
          final error = _controller.error.value;
          final markers = _controller.markers;
          final zones = _controller.zones;
          final loading = _controller.isLoading.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Destination header — mirrors the detail page's title block.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: DispatchColors.brand.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.place_outlined,
                      size: 20,
                      color: DispatchColors.brand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.jobName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.2),
                        ),
                        if (widget.address != null &&
                            widget.address!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            widget.address!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.3),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: DispatchColors.danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: DispatchColors.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 16,
                        color: DispatchColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DispatchColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AdaptiveMap(
                          center: _jobPoint,
                          markers: markers,
                          zones: zones,
                          onMarkerTap: _handleMarkerTap,
                        ),
                      ),
                      // Hairline border drawn over the map to match cards.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: palette.cardBorder),
                            ),
                          ),
                        ),
                      ),
                      if (loading)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Color(0x33000000),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: DispatchColors.brand,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Markers: ${markers.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Geozones: ${zones.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }

  void _handleMarkerTap(MapMarkerModel marker) {
    final status = marker.data;
    if (status is! TraxrootObjectStatusModel) {
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ObjectStatusBottomSheet(
        status: status,
        onTrack: status.id != null
            ? () {
                Navigator.of(context).pop();
                Get.to(() => VehicleTrackingPage(vehicle: status));
              }
            : null,
      ),
    );
  }
}
