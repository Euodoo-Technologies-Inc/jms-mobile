import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/data/datasource/traxroot_datasource.dart';
import 'package:fms/data/models/traxroot_icon_model.dart';
import 'package:fms/data/models/traxroot_object_model.dart';
import 'package:fms/data/models/traxroot_object_status_model.dart';
import 'package:fms/core/constants/variables.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fms/page/home/controller/home_controller.dart';
import 'package:fms/core/theme/dispatch_palette.dart';

/// Controller for managing vehicle data and tracking operations.
///
/// This controller handles fetching vehicle lists, filtering by group or query,
/// managing vehicle icons, and performing real-time tracking updates.
class VehiclesController extends GetxController {
  final _objectsDatasource = TraxrootObjectsDatasource(
    TraxrootAuthDatasource(),
  );

  final RxBool isLoading = false.obs;
  final RxList<TraxrootObjectModel> objects = <TraxrootObjectModel>[].obs;
  final RxMap<int, TraxrootIconModel> iconsById =
      <int, TraxrootIconModel>{}.obs;
  final RxnInt loadingObjectId = RxnInt();
  final RxString query = ''.obs;
  final RxnString selectedGroup = RxnString();
  final RxList<String> availableGroups = <String>[].obs;
  final RxMap<String, int> groupCounts = <String, int>{}.obs;

  // Dynamic mapping of group IDs to group names from API
  final RxMap<int, String> groupIdToName = <int, String>{}.obs;

  List<TraxrootObjectModel> get filteredObjects {
    final q = query.value.trim().toLowerCase();
    return objects.where((v) {
      // Check if vehicle belongs to selected group
      bool matchGroup =
          selectedGroup.value == null || selectedGroup.value!.isEmpty;

      if (!matchGroup && selectedGroup.value != null) {
        // Check if any of the vehicle's groups matches the selected group
        for (final group in v.groups) {
          // Group is an integer ID, convert to name
          int? groupId;
          if (group is int) {
            groupId = group;
          } else if (group is String) {
            groupId = int.tryParse(group);
          }

          if (groupId != null) {
            final groupName = groupIdToName[groupId];
            if (groupName == selectedGroup.value) {
              matchGroup = true;
              break;
            }
          }
        }
      }

      final name = (v.name ?? '').toLowerCase();
      final comment = (v.main?.comment ?? '').toLowerCase();
      final matchText = q.isEmpty || name.contains(q) || comment.contains(q);
      return matchGroup && matchText;
    }).toList();
  }

  int get totalVehicleCount => objects.length;

  @override
  void onInit() {
    super.onInit();
    loadData();
  }

  /// Loads initial data including vehicles, icons, and groups.
  ///
  /// Fetches data from the [TraxrootObjectsDatasource] and populates the
  /// observable variables. It also builds the group mapping and precaches icons.
  Future<void> loadData() async {
    isLoading.value = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final hasTraxroot =
          prefs.getBool(Variables.prefHasTraxroot) ?? false;
      if (!hasTraxroot) {
        objects.clear();
        iconsById.clear();
        availableGroups.clear();
        groupCounts.clear();
        selectedGroup.value = null;
        return;
      }

      final objectsData = await _objectsDatasource.getObjects();
      final icons = await _objectsDatasource.getObjectIcons();
      final objectGroups = await _objectsDatasource.getObjectGroups();

      final iconMap = <int, TraxrootIconModel>{};
      for (final icon in icons) {
        final id = icon.id;
        if (id != null) {
          iconMap[id] = icon;
        }
      }

      objects.value = objectsData;
      iconsById.value = iconMap;

      // Build group ID to name mapping from API
      final groupMapping = <int, String>{};
      for (final group in objectGroups) {
        if (group.groupId > 0 && group.name != null && group.name!.isNotEmpty) {
          groupMapping[group.groupId] = group.name!;
        }
      }
      groupIdToName.value = groupMapping;

      // log('Object groups count: ${objectGroups.length}', name: 'VehiclesController.loadData');
      // log('Group mapping: $groupMapping', name: 'VehiclesController.loadData');

      // Build group list with counts from groups field
      final groupCountMap = <String, int>{};

      // Log sample vehicle groups for debugging
      if (objectsData.isNotEmpty) {
        final sampleVehicles = objectsData.take(3).toList();
        for (var v in sampleVehicles) {
          log(
            'Vehicle ${v.name}: groups = ${v.groups}',
            name: 'VehiclesController.loadData',
          );
        }
      }

      for (final obj in objectsData) {
        // Extract group IDs from groups array and convert to names
        if (obj.groups.isNotEmpty) {
          for (final group in obj.groups) {
            // Groups are integer IDs
            int? groupId;
            if (group is int) {
              groupId = group;
            } else if (group is String) {
              groupId = int.tryParse(group);
            }

            if (groupId != null) {
              final groupName = groupIdToName[groupId];
              if (groupName != null && groupName.isNotEmpty) {
                groupCountMap[groupName] = (groupCountMap[groupName] ?? 0) + 1;
              }
            }
          }
        }
      }

      final groups = groupCountMap.keys.toList()..sort();

      // log('Group count map: $groupCountMap', name: 'VehiclesController.loadData');
      // log('Available groups: $groups', name: 'VehiclesController.loadData');

      availableGroups.value = groups;
      groupCounts.value = groupCountMap;

      if (selectedGroup.value != null &&
          !availableGroups.contains(selectedGroup.value)) {
        selectedGroup.value = null;
      }

      _precacheIcons(iconMap);
    } catch (e) {
      Get.snackbar(
        colorText: Colors.white,
        backgroundColor: DispatchColors.danger,
        icon: const Icon(Icons.error, color: Colors.white),
        'Error',
        'Failed to load vehicles. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  void _precacheIcons(Map<int, TraxrootIconModel> iconMap) {
    if (iconMap.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = Get.context;
        if (context != null) {
          for (final icon in iconMap.values) {
            final url = icon.url;
            if (url != null && url.isNotEmpty) {
              precacheImage(NetworkImage(url), context);
            }
          }
        }
      });
    }
  }

  /// Fetches the current status of a specific vehicle.
  ///
  /// Tries to get the object with sensor data first, falling back to the latest point
  /// or basic object details if that fails.
  Future<TraxrootObjectStatusModel?> fetchObjectStatus(
    TraxrootObjectModel vehicle,
  ) async {
    final objectId = vehicle.id;

    if (objectId == null) {
      Get.snackbar(
        colorText: Colors.white,
        backgroundColor: DispatchColors.danger,
        icon: const Icon(Icons.error, color: Colors.white),
        'Error',
        'Vehicle ID is unavailable.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return null;
    }

    TraxrootObjectStatusModel? status;
    try {
      // Fetch object with sensors for complete information
      status = await _objectsDatasource.getObjectWithSensors(
        objectId: objectId,
      );
      // Fallback to regular status if sensor fetch fails
      status ??= await _objectsDatasource.getLatestPoint(objectId: objectId);
    } catch (e) {
      Get.snackbar(
        colorText: Colors.white,
        backgroundColor: DispatchColors.danger,
        icon: const Icon(Icons.error, color: Colors.white),
        'Error',
        'Failed to load vehicle details.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }

    if (status != null) {
      // Ensure id is always set, even if the API response doesn't include it
      if (status.id == null) {
        status = status.copyWith(id: objectId);
      }
      return status;
    }

    return TraxrootObjectStatusModel(
      id: vehicle.id,
      name: vehicle.name,
      latitude: vehicle.latitude,
      longitude: vehicle.longitude,
      address: vehicle.address,
    );
  }

  /// Refreshes the tracking status of a vehicle.
  ///
  /// Primary source: `/ObjectsStatus/{id}` via [getLatestPoint] for live
  /// position + angle. Falls back to `getObjectWithSensors` and
  /// `getObjectStatus` if needed.
  Future<TraxrootObjectStatusModel?> refreshTrackingStatus(
    TraxrootObjectStatusModel vehicle,
  ) async {
    final objectId = vehicle.id;
    if (objectId == null) {
      log(
        'Vehicle Tracking - Cannot refresh: vehicle has no objectId',
        name: 'VehiclesController.refreshTrackingStatus',
        level: 900,
      );
      return null;
    }

    log(
      'Vehicle Tracking - Refresh started for objectId=$objectId',
      name: 'VehiclesController.refreshTrackingStatus',
      level: 800,
    );

    try {
      // 0) Try to reuse the latest status from HomeController to keep
      // VehicleTrackingPage perfectly in sync with the homepage map.
      try {
        final home = Get.find<HomeController>();
        TraxrootObjectStatusModel? homeStatus;
        for (final status in home.objects) {
          if (status.id == objectId) {
            homeStatus = status;
            break;
          }
        }
        if (homeStatus != null) {
          log(
            'Vehicle Tracking - Using HomeController status for objectId=$objectId',
            name: 'VehiclesController.refreshTrackingStatus',
            level: 800,
          );
          return homeStatus;
        }
      } catch (_) {
        // HomeController not available; fall back to direct API calls below.
      }

      // 1) If HomeController is not available, use getAllObjectsStatus (same source
      // as HomeController.refreshStatuses) to get real-time data for this vehicle.
      log(
        'Vehicle Tracking - HomeController not available, fetching from /ObjectsStatus',
        name: 'VehiclesController.refreshTrackingStatus',
        level: 800,
      );

      final allStatuses = await _objectsDatasource.getAllObjectsStatus();
      if (allStatuses.isNotEmpty) {
        // Find status by matching trackerId (same logic as HomeController)
        final vehicleTrackerId =
            vehicle.trackerId?.trim() ?? objectId.toString();
        TraxrootObjectStatusModel? matchedStatus;

        for (final status in allStatuses) {
          final statusTrackerId = status.trackerId?.trim();
          if (statusTrackerId != null && statusTrackerId == vehicleTrackerId) {
            matchedStatus = status;
            break;
          }
        }

        if (matchedStatus != null &&
            matchedStatus.latitude != null &&
            matchedStatus.longitude != null) {
          log(
            'Vehicle Tracking - Found in /ObjectsStatus: '
            'lat=${matchedStatus.latitude}, lng=${matchedStatus.longitude}, '
            'ang=${matchedStatus.course}, speed=${matchedStatus.speed}',
            name: 'VehiclesController.refreshTrackingStatus',
            level: 800,
          );

          // Merge with vehicle data to preserve name, iconId, etc.
          return vehicle.copyWith(
            latitude: matchedStatus.latitude,
            longitude: matchedStatus.longitude,
            speed: matchedStatus.speed,
            course: matchedStatus.course,
            altitude: matchedStatus.altitude,
            status: matchedStatus.status,
            address: matchedStatus.address,
            updatedAt: matchedStatus.updatedAt,
            satellites: matchedStatus.satellites,
            accuracy: matchedStatus.accuracy,
          );
        }
      }

      // 2) Fallback: Try per-vehicle /ObjectsStatus/{id}
      final latestPoint = await _objectsDatasource.getLatestPoint(
        objectId: objectId,
      );
      if (latestPoint != null &&
          latestPoint.latitude != null &&
          latestPoint.longitude != null) {
        log(
          'Vehicle Tracking - Live point from /ObjectsStatus/{id}: '
          'lat=${latestPoint.latitude}, lng=${latestPoint.longitude}, ang=${latestPoint.course}',
          name: 'VehiclesController.refreshTrackingStatus',
          level: 800,
        );

        final posChanged =
            vehicle.latitude != latestPoint.latitude ||
            vehicle.longitude != latestPoint.longitude;
        final angChanged = vehicle.course != latestPoint.course;

        if (posChanged || angChanged) {
          log(
            'Vehicle Tracking - Position/Angle updated: '
            'lat: ${vehicle.latitude} → ${latestPoint.latitude}, '
            'lng: ${vehicle.longitude} → ${latestPoint.longitude}, '
            'ang: ${vehicle.course} → ${latestPoint.course}',
            name: 'VehiclesController.refreshTrackingStatus',
            level: 800,
          );
        }

        return vehicle.copyWith(
          latitude: latestPoint.latitude,
          longitude: latestPoint.longitude,
          speed: latestPoint.speed,
          course: latestPoint.course,
          altitude: latestPoint.altitude,
          status: latestPoint.status,
          address: latestPoint.address,
          updatedAt: latestPoint.updatedAt,
          satellites: latestPoint.satellites,
          accuracy: latestPoint.accuracy,
        );
      }

      // 3) Final fallback to sensor data if latest point isn't usable
      log(
        'Vehicle Tracking - Falling back to sensor/object status for objectId=$objectId',
        name: 'VehiclesController.refreshTrackingStatus',
        level: 800,
      );

      final withSensors = await _objectsDatasource.getObjectWithSensors(
        objectId: objectId,
      );
      if (withSensors != null) {
        log(
          'Vehicle Tracking - Retrieved sensor data for objectId=$objectId',
          name: 'VehiclesController.refreshTrackingStatus',
          level: 800,
        );
        return withSensors;
      }

      return await _objectsDatasource.getObjectStatus(objectId: objectId);
    } catch (e, st) {
      log(
        'Vehicle Tracking - Error refreshing status for objectId=$objectId: $e',
        name: 'VehiclesController.refreshTrackingStatus',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Updates the search query for filtering vehicles.
  void updateQuery(String value) {
    query.value = value;
  }

  /// Updates the selected group for filtering vehicles.
  void updateSelectedGroup(String? value) {
    selectedGroup.value = (value == null || value.isEmpty) ? null : value;
  }

  /// Resets the controller state, clearing all data.
  void reset() {
    isLoading.value = false;
    objects.clear();
    iconsById.clear();
    loadingObjectId.value = null;
    query.value = '';
    selectedGroup.value = null;
    availableGroups.clear();
    groupCounts.clear();
    groupIdToName.clear();
  }
}
