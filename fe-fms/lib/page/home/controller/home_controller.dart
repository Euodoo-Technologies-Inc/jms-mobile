import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/models/geo.dart';
import 'package:fms/data/datasource/get_job_datasource.dart';
import 'package:fms/data/datasource/get_job_ongoing_datasource.dart';
import 'package:fms/data/datasource/get_job_history_datasource.dart';
import 'package:fms/data/datasource/traxroot_datasource.dart';
import 'package:fms/data/models/response/get_job_response_model.dart';
import 'package:fms/data/models/response/get_job_ongoing_response_model.dart'
    as ongoing;
import 'package:fms/data/models/traxroot_icon_model.dart';
import 'package:fms/data/models/traxroot_object_model.dart';
import 'package:fms/data/models/traxroot_object_status_model.dart';
import 'package:fms/data/models/traxroot_geozone_model.dart';
import 'package:fms/data/models/response/get_job_history__response_model.dart'
    as history;
import 'dart:developer';
import 'package:fms/core/services/home_widget_service.dart';
import 'package:home_widget/home_widget.dart';
import 'package:fms/core/constants/variables.dart';
import 'package:fms/core/navigation/navigation_controller.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controller for the home screen, managing map data, jobs, and vehicle tracking.
class HomeController extends GetxController {
  final _objectsDatasource = TraxrootObjectsDatasource(
    TraxrootAuthDatasource(),
  );
  final _internalDatasource = TraxrootInternalDatasource();

  final RxBool isLoading = false.obs;
  /// Job-overview stats load independently of the (slower) Traxroot map
  /// pipeline, so the dashboard overview no longer waits for vehicle data.
  final RxBool isOverviewLoading = false.obs;
  final RxString error = ''.obs;
  final RxList<MapMarkerModel> markers = <MapMarkerModel>[].obs;
  final RxList<MapZoneModel> zones = <MapZoneModel>[].obs;
  final RxList<TraxrootObjectStatusModel> objects =
      <TraxrootObjectStatusModel>[].obs;
  final RxList<TraxrootObjectStatusModel> movingObjects =
      <TraxrootObjectStatusModel>[].obs;
  final Map<int, DateTime> _lastMovementTimeByObjectId = {};
  final Map<int, String> _lastMovementEventIdByObjectId = {};
  final Map<int, String> lastMovementTextByObjectId = {};
  final Map<int, String> lastMovementTypeByObjectId = {};
  final RxMap<int, String> iconUrlByObjectId = <int, String>{}.obs;
  final Rx<GetJobResponseModel?> allJobsResponse = Rx<GetJobResponseModel?>(
    null,
  );
  final Rx<ongoing.GetJobOngoingResponseModel?> ongoingJobsResponse =
      Rx<ongoing.GetJobOngoingResponseModel?>(null);
  final Rx<history.GetJobHistoryResponseModel?> completedJobsResponse =
      Rx<history.GetJobHistoryResponseModel?>(null);

  static const GeoPoint defaultCenter = GeoPoint(
    14.5995,
    120.9842,
  ); // Manila fallback

  GeoPoint get mapCenter => defaultCenter;

  int get openJobsCount => allJobsResponse.value?.data?.length ?? 0;
  int get ongoingJobsCount => ongoingJobsResponse.value?.data?.length ?? 0;
  int get completedJobsCount => completedJobsResponse.value?.data?.length ?? 0;

  /// Fetches an object with its sensor data.
  Future<TraxrootObjectStatusModel?> getObjectWithSensors(int objectId) {
    return _objectsDatasource.getObjectWithSensors(objectId: objectId);
  }

  @override
  void onInit() {
    super.onInit();
    loadData();
  }

  /// Loads all initial data for the home screen.
  ///
  /// Skips Traxroot/GPS fetching for field users (they only see job stats).
  /// Skips job fetching for monitor users (they only see the map).
  Future<void> loadData() async {
    isLoading.value = true;
    isOverviewLoading.value = true;
    error.value = '';

    try {
      final prefs = await SharedPreferences.getInstance();
      final hasTraxroot =
          prefs.getBool(Variables.prefHasTraxroot) ?? false;

      // Read role from AuthController (already set during checkSession)
      final role = Get.find<AuthController>().userRole.value?.toLowerCase().trim();
      final isField = role == 'field';
      final isMonitor = role == 'monitor';

      // Check for widget launch
      final widgetUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (widgetUri != null) {
        _handleWidgetNavigation(widgetUri);
      }

      // Listen for widget clicks while app is running
      HomeWidget.widgetClicked.listen(_handleWidgetNavigation);

      // Kick off the overview (job) fetches and the Traxroot map fetches
      // concurrently. The overview is released as soon as the job calls
      // return — it no longer waits behind the slower Traxroot pipeline.
      Future<GetJobResponseModel?>? allJobsFuture;
      Future<ongoing.GetJobOngoingResponseModel?>? ongoingJobsFuture;
      Future<history.GetJobHistoryResponseModel?>? completedJobsFuture;
      if (!isMonitor) {
        allJobsFuture = GetJobDatasource().getJob();
        ongoingJobsFuture = GetJobOngoingDatasource().getOngoingJobs();
        completedJobsFuture = GetJobHistoryDatasource().getJobHistory();
      }

      // Map/vehicle data — skipped for field users; needs Traxroot configured.
      final bool loadMap = !isField && hasTraxroot;
      Future<List<TraxrootObjectModel>>? objectsFuture;
      Future<List<TraxrootIconModel>>? iconsFuture;
      Future<List<TraxrootGeozoneModel>>? geozonesFuture;
      Future<List<TraxrootObjectStatusModel>>? statusesFuture;
      if (loadMap) {
        objectsFuture = _objectsDatasource.getObjects();
        iconsFuture = _objectsDatasource.getObjectIcons();
        geozonesFuture = _internalDatasource.getGeozones();
        // A single bulk /ObjectsStatus call replaces the previous one-request-
        // per-vehicle getLatestPoint fan-out.
        statusesFuture = _objectsDatasource.getAllObjectsStatus();
      } else if (!isField && !hasTraxroot) {
        error.value =
            'Unable to load map: GPS tracking is not configured for this company. Please contact your administrator.';
      }

      // ---- Overview (jobs): resolve and reveal independently of the map ----
      if (allJobsFuture != null) {
        try {
          final allJobs = await allJobsFuture;
          final ongoingJobs = await ongoingJobsFuture;
          final completedJobs = await completedJobsFuture;
          allJobsResponse.value = allJobs;
          ongoingJobsResponse.value = ongoingJobs;
          completedJobsResponse.value = completedJobs;
        } catch (e) {
          log('Overview job load failed: $e',
              name: 'HomeController.loadData', level: 1000);
        }
      }
      isOverviewLoading.value = false;

      // Nothing more to load when there's no map (field, or no Traxroot).
      if (!loadMap) {
        markers.clear();
        zones.clear();
        objects.clear();
        isLoading.value = false;
        _updateWidgets();
        return;
      }

      // ---- Map / Traxroot pipeline (no longer blocks the overview) ----
      final objectsData = await objectsFuture!;
      final icons = await iconsFuture!;
      final geozones = await geozonesFuture!;
      final bulkStatuses = await statusesFuture!;

      // Index the bulk status payload by trackerId — the same key
      // refreshStatuses() matches on.
      final statusByTrackerId = <String, TraxrootObjectStatusModel>{};
      for (final s in bulkStatuses) {
        final t = s.trackerId?.trim();
        if (t != null && t.isNotEmpty) {
          statusByTrackerId[t] = s;
        }
      }

      final iconsById = <int, TraxrootIconModel>{
        for (final icon in icons)
          if (icon.id != null) icon.id!: icon,
      };

      final iconUrlMap = <int, String>{};
      final iconUrlByObjectName = <String, String>{};
      final iconUrlByTrackerId = <String, String>{};
      final trackersByObject = <int, Set<String>>{};

      void collectTrackers(int objectId, dynamic node, String? iconUrl) {
        if (node is Map) {
          for (final entry in node.entries) {
            final key = '${entry.key}'.toLowerCase();
            final value = entry.value;
            if (key.contains('tracker') || key.contains('imei')) {
              final text = value?.toString().trim();
              if (text != null && text.isNotEmpty) {
                trackersByObject
                    .putIfAbsent(objectId, () => <String>{})
                    .add(text);
                if (iconUrl != null && iconUrl.isNotEmpty) {
                  iconUrlByTrackerId.putIfAbsent(text, () => iconUrl);
                }
              }
            }
            collectTrackers(objectId, value, iconUrl);
          }
        } else if (node is List) {
          for (final v in node) {
            collectTrackers(objectId, v, iconUrl);
          }
        }
      }

      for (final object in objectsData) {
        final objectId = object.id;
        if (objectId == null) continue;

        final iconId = object.iconId;
        final iconUrl = iconId != null ? iconsById[iconId]?.url : null;
        if (iconUrl != null && iconUrl.isNotEmpty) {
          iconUrlMap[objectId] = iconUrl;
          final name = object.name;
          if (name != null && name.isNotEmpty) {
            iconUrlByObjectName[name] = iconUrl;
          }
        }

        // Collect trackers for every object (not just icon-bearing ones) so
        // each can be matched to the bulk status payload.
        collectTrackers(objectId, object.raw, iconUrl);
      }

      // Resolve each object's latest status from the bulk payload via its
      // tracker id (falling back to the object-id string). Any object the bulk
      // call doesn't cover gets a targeted per-object fetch, so a marker is
      // never silently dropped.
      final statusByObjectId = <int, TraxrootObjectStatusModel>{};
      final unmatched = <int>[];
      for (final object in objectsData) {
        final objectId = object.id;
        if (objectId == null) continue;

        TraxrootObjectStatusModel? statusPoint;
        final candidates = <String>{
          ...?trackersByObject[objectId],
          objectId.toString(),
        };
        for (final key in candidates) {
          final hit = statusByTrackerId[key.trim()];
          if (hit != null) {
            statusPoint = hit;
            break;
          }
        }
        if (statusPoint != null) {
          statusByObjectId[objectId] = statusPoint;
        } else {
          unmatched.add(objectId);
        }
      }

      if (unmatched.isNotEmpty) {
        log(
          'Bulk /ObjectsStatus missed ${unmatched.length}/${objectsData.length} '
          'objects — falling back to per-object fetch for those',
          name: 'HomeController.loadData',
          level: 900,
        );
        final fallback = await Future.wait(
          unmatched.map(
            (id) => _objectsDatasource
                .getLatestPoint(objectId: id)
                .catchError((_) => null),
          ),
        );
        for (var i = 0; i < unmatched.length; i++) {
          final s = fallback[i];
          if (s != null) {
            statusByObjectId[unmatched[i]] = s;
          }
        }
      }

      // Build markers from /Objects (name, id, iconId) + extracted statuses (lat, lng)
      final markersList = <MapMarkerModel>[];
      final usedIconUrls = <String>{};
      final statusList = <TraxrootObjectStatusModel>[];

      for (final object in objectsData) {
        final objectId = object.id;
        if (objectId == null) continue;

        final objectName = object.name;
        final objectIconId = object.iconId;
        final iconUrl = objectIconId != null
            ? iconsById[objectIconId]?.url
            : null;

        if (iconUrl != null && iconUrl.isNotEmpty) {
          usedIconUrls.add(iconUrl);
        }

        // Get status from the map we built earlier
        final statusPoint = statusByObjectId[objectId];
        if (statusPoint == null) continue;

        final lat = statusPoint.latitude;
        final lon = statusPoint.longitude;
        if (lat == null || lon == null || (lat == 0.0 && lon == 0.0)) {
          continue;
        }

        // Compose status model with data from both endpoints
        // IMPORTANT: trackerId should match the trackerid field from /ObjectsStatus
        // Usually this is the object's ID as a string
        final trackerId = statusPoint.trackerId ?? objectId.toString();

        // log(
        //   'Initial Load - Object id=$objectId, name=$objectName, trackerId from API=${statusPoint.trackerId}, using trackerId=$trackerId',
        //   name: 'HomeController.loadData',
        //   level: 800,
        // );

        final composed = TraxrootObjectStatusModel(
          id: objectId,
          name: objectName,
          trackerId: trackerId,
          latitude: lat,
          longitude: lon,
          address: statusPoint.address,
          speed: statusPoint.speed,
          course: statusPoint.course,
          altitude: statusPoint.altitude,
          status: statusPoint.status,
          updatedAt: statusPoint.updatedAt,
          satellites: statusPoint.satellites,
          accuracy: statusPoint.accuracy,
          iconId: objectIconId,
        );

        statusList.add(composed);
        final marker = composed.toMarker(icon: iconUrl);
        if (marker != null) {
          markersList.add(marker);
        }
      }

      final zonesList = <MapZoneModel>[];
      for (final geozone in geozones) {
        final zoneModel = geozone.toZoneModel();
        if (zoneModel != null) {
          zonesList.add(zoneModel);
        }
      }

      markers.value = markersList;
      zones.value = zonesList;
      objects.value = statusList;
      iconUrlByObjectId.value = iconUrlMap;
      await _detectMovement(statusList);
      isLoading.value = false;

      _precacheIcons(usedIconUrls);
      _updateWidgets();
      if (error.value.isEmpty) {
        final authError = TraxrootAuthDatasource.lastErrorMessage;
        if (authError != null &&
            authError.toLowerCase().contains('invalid username or password')) {
          error.value =
              'Unable to load map: GPS tracking authentication failed. Please contact your administrator.';
        }
      }
    } catch (e) {
      // On any Traxroot failure, keep job data but clear map-related state
      markers.clear();
      zones.clear();
      objects.clear();
      iconUrlByObjectId.clear();

      isLoading.value = false;
      isOverviewLoading.value = false;

      final msg = e.toString();
      if (msg.toLowerCase().contains('invalid username or password')) {
        error.value =
            'Unable to load map: GPS tracking authentication failed. Please contact your administrator.';
      } else {
        final authError = TraxrootAuthDatasource.lastErrorMessage;
        if (authError != null &&
            authError.toLowerCase().contains('invalid username or password')) {
          error.value =
              'Unable to load map: GPS tracking authentication failed. Please contact your administrator.';
        } else {
          error.value = 'Failed to load map data. Please try again later.';
        }
      }
      // No Get.snackbar here to avoid Overlay-related errors; HomeTab already
      // displays error text under the map using controller.error.
    }
  }

  /// Updates the dashboard overview counts (Open / Ongoing / Complete) from
  /// job data already fetched elsewhere — currently [JobsController.refresh],
  /// which runs after a job is accepted, finished, or cancelled. This keeps the
  /// overview live without a manual refresh and without re-hitting the network
  /// (the Jobs tab just fetched this data) or touching the slower map pipeline.
  ///
  /// Only non-null values are applied, so a failed/offline fetch on the Jobs
  /// side leaves the last good counts in place instead of zeroing them.
  void syncOverviewFromJobs({
    GetJobResponseModel? allJobs,
    ongoing.GetJobOngoingResponseModel? ongoingJobs,
    history.GetJobHistoryResponseModel? completedJobs,
  }) {
    if (allJobs != null) allJobsResponse.value = allJobs;
    if (ongoingJobs != null) ongoingJobsResponse.value = ongoingJobs;
    if (completedJobs != null) completedJobsResponse.value = completedJobs;
    _updateWidgets();
  }

  void _precacheIcons(Set<String> urls) {
    if (urls.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = Get.context;
        if (context != null) {
          for (final url in urls) {
            precacheImage(NetworkImage(url), context);
          }
        }
      });
    }
  }

  /// Refreshes the status of tracked objects.
  Future<void> refreshStatuses() async {
    if (objects.isEmpty) {
      return;
    }

    try {
      log(
        'Live Tracking - Refresh started for ${objects.length} tracked vehicles',
        name: 'HomeController.refreshStatuses',
        level: 800,
      );

      final allStatuses = await _objectsDatasource.getAllObjectsStatus();

      if (allStatuses.isEmpty) {
        log(
          'Live Tracking - No statuses received from /ObjectsStatus',
          name: 'HomeController.refreshStatuses',
          level: 900,
        );
        return;
      }

      log(
        'Live Tracking - Received ${allStatuses.length} statuses from /ObjectsStatus',
        name: 'HomeController.refreshStatuses',
        level: 800,
      );

      // Build map by trackerId since /ObjectsStatus returns trackerid, not object ID
      final statusByTrackerId = <String, TraxrootObjectStatusModel>{};
      for (final status in allStatuses) {
        final trackerId = status.trackerId?.trim();
        if (trackerId != null && trackerId.isNotEmpty) {
          statusByTrackerId[trackerId] = status;
        }
      }

      log(
        'Mapping trackerid - Built map with ${statusByTrackerId.length} unique trackerIds',
        name: 'HomeController.refreshStatuses',
        level: 800,
      );

      // Log first 5 trackerIds to verify format
      final sampleTrackerIds = statusByTrackerId.keys.take(5).toList();
      if (sampleTrackerIds.isNotEmpty) {
        log(
          'Mapping trackerid - Sample trackerIds from /ObjectsStatus: $sampleTrackerIds',
          name: 'HomeController.refreshStatuses',
          level: 800,
        );
      }

      final updatedStatuses = <TraxrootObjectStatusModel>[];
      final updatedMarkers = <MapMarkerModel>[];
      final usedIconUrls = <String>{};
      int matchedCount = 0;
      int unmatchedCount = 0;
      int positionChangedCount = 0;

      for (final previous in objects) {
        final objectId = previous.id;
        if (objectId == null) {
          continue;
        }

        // Try to find matching status by trackerId
        TraxrootObjectStatusModel? latest;
        final previousTrackerId = previous.trackerId?.trim();
        if (previousTrackerId != null && previousTrackerId.isNotEmpty) {
          latest = statusByTrackerId[previousTrackerId];

          if (latest != null) {
            matchedCount++;

            // Check if position changed
            final posChanged =
                previous.latitude != latest.latitude ||
                previous.longitude != latest.longitude;
            final angChanged = previous.course != latest.course;

            if (posChanged || angChanged) {
              positionChangedCount++;
              log(
                'Position Update - Vehicle objectId=$objectId, trackerId=$previousTrackerId: '
                'lat: ${previous.latitude} → ${latest.latitude}, '
                'lng: ${previous.longitude} → ${latest.longitude}, '
                'ang: ${previous.course} → ${latest.course}',
                name: 'HomeController.refreshStatuses',
                level: 800,
              );
            }
          } else {
            unmatchedCount++;
            log(
              'Mapping trackerid - No match found for objectId=$objectId, trackerId=$previousTrackerId',
              name: 'HomeController.refreshStatuses',
              level: 900,
            );
          }
        }

        final composed = latest == null
            ? previous
            : previous.copyWith(
                latitude: latest.latitude,
                longitude: latest.longitude,
                speed: latest.speed,
                course: latest.course, // This is the 'ang' field from API
                altitude: latest.altitude,
                status: latest.status,
                address: latest.address,
                updatedAt: latest.updatedAt,
                satellites: latest.satellites,
                accuracy: latest.accuracy,
              );

        updatedStatuses.add(composed);

        final iconUrl = iconUrlByObjectId[objectId];
        if (iconUrl != null && iconUrl.isNotEmpty) {
          usedIconUrls.add(iconUrl);
        }
        final marker = composed.toMarker(icon: iconUrl);
        if (marker != null) {
          updatedMarkers.add(marker);
        }
      }

      log(
        'State Update - Matched: $matchedCount, Unmatched: $unmatchedCount, Position Changed: $positionChangedCount',
        name: 'HomeController.refreshStatuses',
        level: 800,
      );

      markers.value = updatedMarkers;
      objects.value = updatedStatuses;

      log(
        'State Update - Updated ${updatedStatuses.length} vehicle objects and ${updatedMarkers.length} map markers',
        name: 'HomeController.refreshStatuses',
        level: 800,
      );

      await _detectMovement(updatedStatuses);
      _precacheIcons(usedIconUrls);
      _updateWidgets();

      log(
        'Live Tracking - Refresh completed successfully',
        name: 'HomeController.refreshStatuses',
        level: 800,
      );
    } catch (e, st) {
      log(
        'Live Tracking - Error during refresh: ${e.toString()}',
        name: 'HomeController.refreshStatuses',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      // Ignore refresh errors to keep home map stable
    }
  }

  Future<void> _detectMovement(
    List<TraxrootObjectStatusModel> newStatuses,
  ) async {
    final now = DateTime.now();

    if (newStatuses.isEmpty) {
      return;
    }

    // Map trackerId -> latest status so we can attach events to objects
    final statusByTrackerId = <String, TraxrootObjectStatusModel>{};
    for (final status in newStatuses) {
      final tracker = status.trackerId?.trim();
      if (tracker != null && tracker.isNotEmpty) {
        statusByTrackerId[tracker] = status;
      }
    }

    if (statusByTrackerId.isEmpty) {
      return;
    }

    final events = await _objectsDatasource.getAllEvents();
    if (events.isEmpty) {
      // Just apply expiry if no events are available
      final expiry = now.subtract(const Duration(seconds: 3));
      movingObjects.removeWhere((status) {
        final objectId = status.id;
        if (objectId == null) {
          return true;
        }
        final ts = _lastMovementTimeByObjectId[objectId];
        return ts == null || ts.isBefore(expiry);
      });
      return;
    }

    for (final event in events) {
      final rawTrackerId =
          event['trackerid'] ?? event['trackerId'] ?? event['TrackerId'];
      if (rawTrackerId == null) {
        continue;
      }
      final trackerId = rawTrackerId.toString().trim();
      if (trackerId.isEmpty) {
        continue;
      }

      final status = statusByTrackerId[trackerId];
      if (status == null || status.id == null) {
        continue;
      }

      final rawTypeDesc =
          event['typedesc'] ?? event['typeDesc'] ?? event['TypeDesc'];
      final rawText = event['text'] ?? event['Text'];
      final typeDesc = rawTypeDesc?.toString().toUpperCase();
      final text = rawText?.toString().trim() ?? '';

      // Parse event time so we can drop stale events and timestamp notifications
      DateTime? eventTime;
      final rawTime = event['time'];
      if (rawTime is int) {
        try {
          eventTime = DateTime.fromMillisecondsSinceEpoch(rawTime);
        } catch (_) {}
      } else if (rawTime is String) {
        final millis = int.tryParse(rawTime.trim());
        if (millis != null && millis > 0) {
          try {
            eventTime = DateTime.fromMillisecondsSinceEpoch(millis);
          } catch (_) {}
        }
      }

      // Ignore events that are too old compared to now. We keep a generous
      // window (60 seconds) so we don't miss new events between polling
      // intervals, but still avoid replaying very old events on app start.
      final cutoff = now.subtract(const Duration(seconds: 60));
      if (eventTime != null && eventTime.isBefore(cutoff)) {
        continue;
      }

      final eventId = event['id']?.toString();
      final objectId = status.id!;
      if (eventId != null) {
        final lastEventId = _lastMovementEventIdByObjectId[objectId];
        if (lastEventId == eventId) {
          // Same event as before, skip to avoid duplicate notifications
          continue;
        }
        _lastMovementEventIdByObjectId[objectId] = eventId;
      }

      // Use the time we *saw* the event (now) for expiry, so notifications
      // disappear a few seconds after being shown, regardless of server time.
      _lastMovementTimeByObjectId[objectId] = now;
      if (text.isNotEmpty) {
        lastMovementTextByObjectId[objectId] = text;
      } else {
        lastMovementTextByObjectId[objectId] = 'is moving';
      }

      if (typeDesc != null && typeDesc.isNotEmpty) {
        lastMovementTypeByObjectId[objectId] = typeDesc;
      } else {
        lastMovementTypeByObjectId.remove(objectId);
      }

      log(
        'Movement event: trackerId=$trackerId, objectId=$objectId, type=$typeDesc, text=${lastMovementTextByObjectId[objectId]}',
        name: 'HomeController._detectMovement',
        level: 800,
      );

      final index = movingObjects.indexWhere((e) => e.id == objectId);
      if (index >= 0) {
        movingObjects[index] = status;
        log(
          'Notification - Updated existing notification for vehicle objectId=$objectId',
          name: 'HomeController._detectMovement',
          level: 800,
        );
      } else {
        movingObjects.add(status);
        log(
          'Notification - Triggered new homepage notification for vehicle objectId=$objectId (${status.name ?? trackerId})',
          name: 'HomeController._detectMovement',
          level: 800,
        );
      }
    }

    // Expire notifications after 4 seconds from last detection
    final expiry = now.subtract(const Duration(seconds: 4));
    movingObjects.removeWhere((status) {
      final objectId = status.id;
      if (objectId == null) {
        return true;
      }
      final ts = _lastMovementTimeByObjectId[objectId];
      return ts == null || ts.isBefore(expiry);
    });
  }

  /// Clears the list of moving objects.
  void clearMovementNotification() {
    movingObjects.clear();
    lastMovementTextByObjectId.clear();
  }

  /// Finds the status model associated with a map marker.
  TraxrootObjectStatusModel? findStatusForMarker(MapMarkerModel marker) {
    final data = marker.data;
    if (data is TraxrootObjectStatusModel) {
      return data;
    }

    try {
      return objects.firstWhere(
        (obj) =>
            obj.geoPoint?.lat == marker.position.lat &&
            obj.geoPoint?.lng == marker.position.lng,
      );
    } catch (_) {
      return null;
    }
  }

  void _updateWidgets() {
    final widgetService = HomeWidgetService();

    // Prepare recent jobs (top 3 from all jobs)
    final recentJobs =
        allJobsResponse.value?.data
            ?.take(3)
            .map(
              (job) => {
                'title': job.jobName ?? 'Unknown Job',
                'status': job.typeJobName ?? 'Open',
                'time': job.jobDate?.toIso8601String() ?? '',
              },
            )
            .toList() ??
        [];

    // Update Job Stats
    widgetService.updateJobStats(
      open: openJobsCount,
      ongoing: ongoingJobsCount,
      complete: completedJobsCount,
      recentJobs: recentJobs,
    );

    // Update Map Stats
    widgetService.updateMapStats(
      activeVehicles: markers.length,
      markers: markers,
    );
  }

  void _handleWidgetNavigation(Uri? uri) {
    if (uri == null) return;

    try {
      final navController = Get.find<NavigationController>();

      if (uri.host == 'job') {
        // Navigate to Jobs tab (Index 2)
        navController.changeTab(2);
      } else if (uri.host == 'map') {
        // Navigate to Home/Map tab (Index 0)
        navController.changeTab(0);
      }
    } catch (e) {
      log('NavigationController not found: $e');
    }
  }

  /// Resets the controller state.
  void reset() {
    isLoading.value = false;
    isOverviewLoading.value = false;
    error.value = '';
    markers.clear();
    zones.clear();
    objects.clear();
    iconUrlByObjectId.clear();
    allJobsResponse.value = null;
    ongoingJobsResponse.value = null;
    completedJobsResponse.value = null;
  }
}
