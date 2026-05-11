import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../data/dispatch/datasource/dispatch_position_datasource.dart';
import '../controller/dispatch_auth_controller.dart';
import '../controller/dispatch_jobs_controller.dart';

/// Posts a GPS sample every [pollInterval] while:
///   * the app is foregrounded, AND
///   * a dispatch session is active, AND
///   * at least one job is in status=1 (on-the-way).
///
/// Per docs §5.4: do not poll while idle, do not queue stale GPS offline.
/// A single 404 ("no vehicle linked") suppresses further pings for the session.
class DispatchPositionService extends GetxService with WidgetsBindingObserver {
  DispatchPositionService({
    this.pollInterval = const Duration(seconds: 45),
  });

  final Duration pollInterval;
  final DispatchPositionDatasource _ds = DispatchPositionDatasource();

  Timer? _timer;
  bool _foreground = true;
  bool _vehicleMissing = false;
  Worker? _authWorker;
  Worker? _jobsWorker;

  Future<DispatchPositionService> init() async {
    WidgetsBinding.instance.addObserver(this);

    // React to auth changes — start/stop as the dispatch session toggles.
    if (Get.isRegistered<DispatchAuthController>()) {
      final auth = Get.find<DispatchAuthController>();
      _authWorker = ever<bool>(auth.isAuthenticated, (_) => _reevaluate());
    }
    _reevaluate();
    return this;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _reevaluate();
  }

  /// Recomputes whether the timer should be running.
  void _reevaluate() {
    final shouldRun = _foreground && _vehicleMissing == false && _hasActiveJob();
    if (shouldRun) {
      _ensureRunning();
      _ensureJobsWatcher();
    } else {
      _stop();
    }
  }

  void _ensureJobsWatcher() {
    if (_jobsWorker != null) return;
    if (!Get.isRegistered<DispatchJobsController>()) return;
    final jobs = Get.find<DispatchJobsController>();
    _jobsWorker = ever(jobs.jobs, (_) => _reevaluate());
  }

  bool _hasActiveJob() {
    if (!Get.isRegistered<DispatchJobsController>()) return false;
    final jobs = Get.find<DispatchJobsController>();
    return jobs.jobs.any((j) => j.isOnTheWay);
  }

  void _ensureRunning() {
    if (_timer != null && _timer!.isActive) return;
    _tick(); // fire one immediately
    _timer = Timer.periodic(pollInterval, (_) => _tick());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_vehicleMissing) return;

    try {
      final permission = await _ensurePermission();
      if (permission == null) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await _ds.postPosition(
        lat: position.latitude,
        lng: position.longitude,
        recordedAt: position.timestamp,
      );
    } on DispatchApiException catch (e) {
      if (e.statusCode == 404) {
        // No MasterVehicle linked — stop polling for the session.
        _vehicleMissing = true;
        _stop();
        log(
          'DispatchPositionService: vehicle missing (404); suppressing further pings',
          name: 'DispatchPositionService',
          level: 900,
        );
      } else if (e.isUnauthorized || e.isAccountDisabled) {
        // Auth controller will wipe; we'll be re-evaluated when it does.
      } else {
        log(
          'DispatchPositionService: ${e.message}',
          name: 'DispatchPositionService',
          level: 900,
        );
      }
    } catch (e) {
      log(
        'DispatchPositionService: $e',
        name: 'DispatchPositionService',
        level: 900,
      );
    }
  }

  Future<LocationPermission?> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return permission;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _authWorker?.dispose();
    _jobsWorker?.dispose();
    _stop();
    super.onClose();
  }
}
