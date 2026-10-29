import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:fms/core/utils/timezone_util.dart';

import '../../../core/theme/dispatch_palette.dart';
import '../../../core/widgets/adaptive_map.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../core/widgets/object_status_bottom_sheet.dart';
import '../../../data/models/traxroot_object_status_model.dart';
import '../controller/vehicles_controller.dart';

/// A page that displays real-time tracking for a specific vehicle.
///
/// This page shows the vehicle on a map, updates its position periodically,
/// and displays detailed status information in a card.
class VehicleTrackingPage extends StatefulWidget {
  final TraxrootObjectStatusModel vehicle;
  final String? iconUrl;
  const VehicleTrackingPage({super.key, required this.vehicle, this.iconUrl});

  @override
  State<VehicleTrackingPage> createState() => _VehicleTrackingPageState();
}

class _VehicleTrackingPageState extends State<VehicleTrackingPage> {
  late final VehiclesController _vehiclesController;
  TraxrootObjectStatusModel? _vehicle;
  bool _loading = false;
  String? _error;
  bool _autoRefresh = false;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    log(
      'VehicleTrackingPage - initState: widget.vehicle=${widget.vehicle.id}, '
      'widget.vehicle.name=${widget.vehicle.name}',
      name: 'VehicleTrackingPage.initState',
      level: 800,
    );
    _vehicle = widget.vehicle;
    log(
      'VehicleTrackingPage - initState: _vehicle set to ${_vehicle?.id}',
      name: 'VehicleTrackingPage.initState',
      level: 800,
    );
    try {
      _vehiclesController = Get.find<VehiclesController>();
    } catch (_) {
      _vehiclesController = Get.put(VehiclesController());
    }
    _refreshLatestStatus();
    _autoRefresh = true;
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLatestStatus() async {
    log(
      'VehicleTrackingPage - _refreshLatestStatus called, _vehicle=${_vehicle?.id}',
      name: 'VehicleTrackingPage._refreshLatestStatus',
      level: 800,
    );

    final current = _vehicle;
    if (current == null || current.id == null) {
      log(
        'VehicleTrackingPage - Skipping refresh: vehicle or ID is null',
        name: 'VehicleTrackingPage._refreshLatestStatus',
        level: 900,
      );
      return;
    }

    log(
      'VehicleTrackingPage - Refresh requested for objectId=${current.id}, '
      'lat=${current.latitude}, lng=${current.longitude}, ang=${current.course}',
      name: 'VehicleTrackingPage._refreshLatestStatus',
      level: 800,
    );

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final latest = await _vehiclesController
          .refreshTrackingStatus(current)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              log(
                'VehicleTrackingPage - Refresh timeout after 5 seconds',
                name: 'VehicleTrackingPage._refreshLatestStatus',
                level: 1000,
              );
              return null;
            },
          );
      if (!mounted) return;
      final before = current;
      final after = latest ?? current;

      log(
        'VehicleTrackingPage - Refresh result for objectId=${before.id}: '
        'lat ${before.latitude} → ${after.latitude}, '
        'lng ${before.longitude} → ${after.longitude}, '
        'ang ${before.course} → ${after.course}',
        name: 'VehicleTrackingPage._refreshLatestStatus',
        level: 800,
      );

      setState(() {
        _vehicle = after;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update vehicle: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = _vehicle;
    final marker = vehicle?.toMarker(icon: widget.iconUrl);
    final hasLocation = marker != null;
    final palette = context.dispatch;

    // DetailScaffold's SafeArea keeps the bottom card above the nav bar.
    return DetailScaffold(
      title: vehicle?.name ?? 'Vehicle Tracking',
      actions: [
        IconButton(
          tooltip: _autoRefresh ? 'Auto refresh: ON' : 'Auto refresh: OFF',
          onPressed: _toggleAutoRefresh,
          icon: Icon(
            Icons.autorenew,
            color: _autoRefresh ? DispatchColors.brand : null,
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _refreshLatestStatus,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: hasLocation
                  ? AdaptiveMap(
                      center: marker.position,
                      zoom: 15,
                      markers: [marker],
                      onMarkerTap: (_) => _showVehicleDetail(vehicle!),
                    )
                  : Center(
                      child: Text(
                        'Vehicle location is unavailable',
                        style: TextStyle(color: palette.subtle, fontSize: 14),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            //card display
            DetailCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _VehicleAvatar(iconUrl: widget.iconUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: palette.subtle, fontSize: 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            vehicle?.name ?? 'Vehicle',
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (vehicle?.status != null)
                            Text('Status: ${vehicle!.status}'),
                          if (vehicle?.speed != null)
                            Text(
                                'Speed: ${vehicle!.speed!.toStringAsFixed(1)} km/h'),
                          if (vehicle?.address != null &&
                              vehicle!.address!.isNotEmpty)
                            Text(vehicle.address!),
                          if (vehicle?.updatedAt != null)
                            Text(
                              'Updated: ${ManilaTimezone.convert(vehicle!.updatedAt!)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (_error != null)
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: DispatchColors.danger,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVehicleDetail(TraxrootObjectStatusModel vehicle) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ObjectStatusBottomSheet(status: vehicle),
    );
  }

  void _toggleAutoRefresh() {
    setState(() {
      _autoRefresh = !_autoRefresh;
    });
    if (_autoRefresh) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
  }

  void _startAutoRefresh() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      log(
        'VehicleTrackingPage - Auto-refresh timer tick: mounted=$mounted, loading=$_loading',
        name: 'VehicleTrackingPage._startAutoRefresh',
        level: 800,
      );
      if (!mounted) return;
      if (!_loading) {
        _refreshLatestStatus();
      } else {
        log(
          'VehicleTrackingPage - Skipping refresh because _loading is true',
          name: 'VehicleTrackingPage._startAutoRefresh',
          level: 900,
        );
      }
    });
  }

  void _stopAutoRefresh() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }
}

/// A widget that displays a vehicle's icon or a fallback avatar.
class _VehicleAvatar extends StatelessWidget {
  const _VehicleAvatar({required this.iconUrl});

  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(8);
    final borderColor = theme.colorScheme.outline.withValues(alpha: 0.2);

    Widget fallbackIcon() => const Icon(Icons.directions_car, size: 18);

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: radius,
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: (iconUrl == null || iconUrl!.isEmpty)
            ? Center(child: fallbackIcon())
            : CachedNetworkImage(
                imageUrl: iconUrl!,
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                placeholder: (_, __) => Center(child: fallbackIcon()),
                errorWidget: (_, __, ___) => Center(child: fallbackIcon()),
              ),
      ),
    );
  }
}
