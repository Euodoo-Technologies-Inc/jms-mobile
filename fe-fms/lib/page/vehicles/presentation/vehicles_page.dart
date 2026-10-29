import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fms/core/widgets/object_status_bottom_sheet.dart';
import 'package:fms/page/vehicles/controller/vehicles_controller.dart';
import 'package:fms/core/widgets/skeleton_loading.dart';
import 'package:fms/core/theme/motion.dart';
import 'package:fms/page/vehicles/presentation/vehicle_tracking_page.dart';
import 'package:fms/core/widgets/detail_widgets.dart';
import 'package:fms/core/theme/dispatch_palette.dart';

/// A page that displays a list of vehicles with filtering and search capabilities.
///
/// Allows users to view all vehicles, filter by group, search by name,
/// and navigate to vehicle tracking or details.
class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  final Map<int, String> _loadingActions = {};

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(VehiclesController());
    final palette = context.dispatch;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DetailCard(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  onChanged: controller.updateQuery,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search vehicles',
                    hintText: 'Type name or note',
                  ),
                ),
                const SizedBox(height: 8),
                Obx(
                  () => DropdownButtonFormField<String>(
                    value: controller.selectedGroup.value,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.group_outlined),
                      labelText: 'Select a group',
                    ),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem(
                        value: '',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('All'),
                            Text(
                              '${controller.totalVehicleCount}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...controller.availableGroups.map((g) {
                        final count = controller.groupCounts[g] ?? 0;
                        return DropdownMenuItem(
                          value: g,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  g,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$count',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                    onChanged: controller.updateSelectedGroup,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.loadData,
            // Cross-fade skeleton → list; instant under reduce motion.
            child: Obx(() => AnimatedSwitcher(
                duration: Motion.of(context, Motion.short),
                child: () {
              if (controller.isLoading.value && controller.objects.isEmpty) {
                return ShimmerProvider(
                  key: const ValueKey('skeleton'),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: const [
                      SkeletonVehicleCard(),
                      SizedBox(height: 12),
                      SkeletonVehicleCard(),
                      SizedBox(height: 12),
                      SkeletonVehicleCard(),
                      SizedBox(height: 12),
                      SkeletonVehicleCard(),
                      SizedBox(height: 12),
                      SkeletonVehicleCard(),
                    ],
                  ),
                );
              }

              final filtered = controller.filteredObjects;
              if (filtered.isEmpty) {
                final failed = controller.loadFailed.value;
                return _VehiclesMessage(
                  icon: failed ? Icons.cloud_off : Icons.search_off,
                  message: failed
                      ? "Couldn't load vehicles."
                      : controller.objects.isEmpty
                          ? 'No vehicles yet.'
                          : 'No vehicles match your search.',
                  onRetry: failed ? controller.loadData : null,
                );
              }

              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final vehicle = filtered[index];
                  final iconId = vehicle.iconId;
                  final iconUrl = iconId != null
                      ? controller.iconsById[iconId]?.url
                      : null;
                  final subtitle = vehicle.main?.comment;
                  final vehicleId = vehicle.id;
                  final isLoadingTrack =
                      vehicleId != null &&
                      _loadingActions[vehicleId] == 'track';
                  final isLoadingDetail =
                      vehicleId != null &&
                      _loadingActions[vehicleId] == 'detail';

                  return Material(
                    color: palette.card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: palette.cardBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      iconColor: palette.subtle,
                      leading: _VehicleIcon(url: iconUrl),
                      title: Text(
                        vehicle.name ?? 'Object ${vehicle.id ?? index + 1}',
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: subtitle != null && subtitle.isNotEmpty
                          ? Text(
                              subtitle,
                              style: TextStyle(
                                color: palette.subtle,
                                fontSize: 13,
                              ),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Track',
                            onPressed:
                                vehicle.id == null ||
                                    isLoadingTrack ||
                                    isLoadingDetail
                                ? null
                                : () => _openVehicleTracking(
                                    controller,
                                    vehicle,
                                    iconUrl,
                                  ),
                            icon: isLoadingTrack
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.near_me_outlined),
                          ),

                          IconButton(
                            tooltip: 'Detail',
                            onPressed:
                                vehicle.id == null ||
                                    isLoadingTrack ||
                                    isLoadingDetail
                                ? null
                                : () => _showVehicleSummary(
                                    context,
                                    controller,
                                    vehicle,
                                    iconUrl,
                                  ),
                            icon: isLoadingDetail
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.info_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }())),
          ),
        ),
      ],
    );
  }

  Future<void> _showVehicleSummary(
    BuildContext context,
    VehiclesController controller,
    vehicle,
    String? iconUrl,
  ) async {
    final vehicleId = vehicle.id;
    if (vehicleId == null) return;

    setState(() {
      _loadingActions[vehicleId] = 'detail';
    });

    try {
      final status = await controller.fetchObjectStatus(vehicle);
      if (status == null) return;

      final enrichedStatus = status.name != null && status.name!.isNotEmpty
          ? status
          : status.copyWith(name: vehicle.name);

      final resolvedIconUrl =
          iconUrl ??
          (vehicle.iconId != null
              ? controller.iconsById[vehicle.iconId!]?.url
              : null);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (_) => ObjectStatusBottomSheet(
          status: enrichedStatus,
          iconUrl: resolvedIconUrl,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingActions.remove(vehicleId);
        });
      }
    }
  }

  Future<void> _openVehicleTracking(
    VehiclesController controller,
    vehicle,
    String? iconUrl,
  ) async {
    final vehicleId = vehicle.id;
    if (vehicleId == null) return;

    setState(() {
      _loadingActions[vehicleId] = 'track';
    });

    try {
      final status = await controller.fetchObjectStatus(vehicle);
      if (status == null) return;

      final enrichedStatus = status.name != null && status.name!.isNotEmpty
          ? status
          : status.copyWith(name: vehicle.name);

      if (!mounted) return;

      final resolvedIconUrl =
          iconUrl ??
          (vehicle.iconId != null
              ? controller.iconsById[vehicle.iconId!]?.url
              : null);

      Get.to(
        () => VehicleTrackingPage(
          vehicle: enrichedStatus,
          iconUrl: resolvedIconUrl,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingActions.remove(vehicleId);
        });
      }
    }
  }
}

/// A widget that displays a vehicle's icon in the list.
class _VehicleIcon extends StatelessWidget {
  const _VehicleIcon({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outline.withValues(alpha: 0.2);
    final radius = BorderRadius.circular(8);

    Widget fallbackIcon() => const Icon(Icons.directions_car, size: 18);

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: radius,
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: (url == null || url!.isEmpty)
            ? Center(child: fallbackIcon())
            : CachedNetworkImage(
                imageUrl: url!,
                width: 36,
                height: 36,
                fit: BoxFit.contain,
                placeholder: (_, __) => Center(child: fallbackIcon()),
                errorWidget: (_, __, ___) => Center(child: fallbackIcon()),
              ),
      ),
    );
  }
}

/// Empty / error state for the vehicle list. Scrollable so pull-to-refresh
/// still works.
class _VehiclesMessage extends StatelessWidget {
  const _VehiclesMessage({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(icon, size: 56, color: palette.subtle),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.subtle, fontSize: 15),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ),
        ],
      ],
    );
  }
}
