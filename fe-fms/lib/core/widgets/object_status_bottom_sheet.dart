import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fms/core/utils/timezone_util.dart';
import 'package:fms/data/models/traxroot_object_status_model.dart';
import 'package:fms/data/models/traxroot_sensor_model.dart';

/// Bottom sheet widget that displays real-time status and sensor data
/// for a tracked vehicle or object.
///
/// This sheet is typically opened from the map when a marker is tapped.
class ObjectStatusBottomSheet extends StatefulWidget {
  final TraxrootObjectStatusModel status;
  final VoidCallback? onTrack;
  final VoidCallback? onNavigate;
  final String? iconUrl;
  const ObjectStatusBottomSheet({
    super.key,
    required this.status,
    this.onTrack,
    this.onNavigate,
    this.iconUrl,
  });

  @override
  State<ObjectStatusBottomSheet> createState() =>
      _ObjectStatusBottomSheetState();
}

/// Internal state for [ObjectStatusBottomSheet] that builds the layout
/// and handles toggling between priority sensors and the full sensor list.
class _ObjectStatusBottomSheetState extends State<ObjectStatusBottomSheet> {
  /// Controls whether all sensors are shown, or only the priority subset.
  bool _showAllSensors = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = widget.status;
    final subtitle = <String>[
      if (status.status != null && status.status!.isNotEmpty) status.status!,
      if (status.speed != null)
        'Speed: ${status.speed!.toStringAsFixed(1)} km/h',
      if (status.course != null)
        'Heading: ${status.course!.toStringAsFixed(0)}°',
    ].join(' • ');

    final updatedLabel = status.updatedAt != null
        ? _formatDateTime(status.updatedAt!)
        : 'Unknown';

    final coordinatesLabel = status.geoPoint != null
        ? '${status.geoPoint!.lat.toStringAsFixed(5)}, ${status.geoPoint!.lng.toStringAsFixed(5)}'
        : 'Not available';

    // Get priority sensors to display
    final sensors = status.sensors ?? [];
    final prioritySensors = _getPrioritySensors(sensors);
    final hasMoreSensors = sensors.length > prioritySensors.length;

    // Debug: Print sensor count
    log(
      'ObjectStatusBottomSheet - Total sensors: ${sensors.length}, Priority: ${prioritySensors.length}',
    );

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusAvatar(iconUrl: widget.iconUrl),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status.name ?? status.trackerId ?? 'Vehicle',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  subtitle,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Last update: $updatedLabel',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DetailRow(
                    label: 'Tracker ID',
                    value: status.trackerId ?? '-',
                  ),
                  _DetailRow(label: 'Coordinates', value: coordinatesLabel),
                  _DetailRow(
                    label: 'Speed',
                    value: status.speed != null
                        ? '${status.speed!.toStringAsFixed(1)} km/h'
                        : '-',
                  ),
                  _DetailRow(
                    label: 'Altitude',
                    value: status.altitude != null
                        ? '${status.altitude!.toStringAsFixed(1)} m'
                        : '-',
                  ),
                  _DetailRow(
                    label: 'Satellites',
                    value: status.satellites?.toString() ?? '-',
                  ),
                  _DetailRow(
                    label: 'Accuracy',
                    value: status.accuracy != null
                        ? '${status.accuracy!.toStringAsFixed(1)} m'
                        : '-',
                  ),
                  // Display priority sensors
                  if (prioritySensors.isNotEmpty)
                    ..._buildSensorRows(prioritySensors),
                  // Show more/less button
                  if (hasMoreSensors)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showAllSensors = !_showAllSensors;
                        });
                      },
                      child: Text(
                        _showAllSensors ? 'Show less' : 'Show more sensors',
                      ),
                    ),
                  // Display all sensors when expanded
                  if (_showAllSensors)
                    ..._buildSensorRows(
                      sensors.skip(prioritySensors.length).toList(),
                    ),
                  if (status.address != null && status.address!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Address',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(status.address!, style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 16),
                  if (widget.onTrack != null || widget.onNavigate != null)
                    Row(
                      children: [
                        if (widget.onTrack != null)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: widget.onTrack,
                              icon: const Icon(Icons.near_me_outlined),
                              label: const Text('Track vehicle'),
                            ),
                          ),
                        if (widget.onTrack != null && widget.onNavigate != null)
                          const SizedBox(width: 12),
                        if (widget.onNavigate != null)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: widget.onNavigate,
                              icon: const Icon(Icons.navigation_outlined),
                              label: const Text('Navigate'),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final local = ManilaTimezone.convert(value);
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  /// Get priority sensors to display first
  /// Only returns sensors that have actual data from the API (from trends field)
  List<TraxrootSensorModel> _getPrioritySensors(
    List<TraxrootSensorModel> sensors,
  ) {
    // Filter only sensors that have a valid name
    final namedSensors = sensors
        .where((sensor) => sensor.name != null && sensor.name!.isNotEmpty)
        .toList();

    // Sort alphabetically by name
    namedSensors.sort(
      (a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()),
    );

    return namedSensors;
  }

  /// Check if sensor has meaningful data to display
  /// A sensor is meaningful if it has metadata (name, units) from the API trends
  bool _hasMeaningfulData(TraxrootSensorModel sensor) {
    // Must have a name (from trends)
    if (sensor.name == null || sensor.name!.isEmpty) {
      return false;
    }

    // If it has units defined in trends, it's a real sensor even without current value
    if (sensor.units != null && sensor.units!.isNotEmpty) {
      return true;
    }

    // If it has a value, show it
    if (sensor.value != null && sensor.value!.isNotEmpty) {
      return true;
    }

    // Otherwise, it's likely a placeholder
    return false;
  }

  /// Build sensor rows
  List<Widget> _buildSensorRows(List<TraxrootSensorModel> sensors) {
    final meaningful = sensors.where(_hasMeaningfulData).toList();
    return meaningful.map((sensor) {
      final name = sensor.name ?? 'Unknown';
      final value = _formatSensorValue(sensor);
      return _DetailRow(label: name, value: value);
    }).toList();
  }

  /// Format sensor value based on type
  String _formatSensorValue(TraxrootSensorModel sensor) {
    final units = sensor.units;

    if (units != null && units.isNotEmpty) {
      return '- $units';
    }

    return '-';
  }
}

class _StatusAvatar extends StatelessWidget {
  const _StatusAvatar({this.iconUrl});

  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.directions_bus_filled);

    if (iconUrl == null || iconUrl!.isEmpty) {
      return const CircleAvatar(child: fallback);
    }

    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: CachedNetworkImage(
          imageUrl: iconUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.contain,
          placeholder: (_, __) => const Center(child: fallback),
          errorWidget: (_, __, ___) => const Center(child: fallback),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
