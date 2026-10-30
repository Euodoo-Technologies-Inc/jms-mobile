// Route refetch rule (#61): GPS fixes on the drawn line cost no request; an
// off-route fix or a new job costs exactly one; a revisited job redraws its
// last line at once.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/models/geo.dart';
import 'package:fms/data/dispatch/datasource/dispatch_osrm_datasource.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/controller/dispatch_jobs_controller.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OSRM that answers with a straight 20-point line from origin to job and
/// counts its calls.
class _FakeOsrm extends DispatchOsrmDatasource {
  int calls = 0;

  @override
  Future<DispatchRoute?> route(List<GeoPoint> waypoints) async {
    calls++;
    final a = waypoints.first, b = waypoints.last;
    return DispatchRoute(
      points: [
        for (var i = 0; i < 20; i++)
          GeoPoint(a.lat + (b.lat - a.lat) * i / 19,
              a.lng + (b.lng - a.lng) * i / 19),
      ],
      durationSeconds: 600,
      distanceMeters: 5000,
    );
  }
}

/// Jobs controller with no polling or network.
class _Controller extends DispatchJobsController {
  _Controller(_FakeOsrm osrm) : super(osrm: osrm);

  @override
  // ignore: must_call_super
  void onInit() {}
}

// Job 1 is ~5.5 km due north of the rider's start; job 2 is east of it.
final _job1 = DispatchJob(id: 1, jobName: 'A', status: 0, lat: 13.45, lng: 121.2);
final _job2 = DispatchJob(id: 2, jobName: 'B', status: 0, lat: 13.40, lng: 121.25);

void main() {
  late GeoPoint fix;
  late _FakeOsrm osrm;
  late DispatchJobsController ctrl;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fix = const GeoPoint(13.40, 121.2);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => {'latitude': fix.lat, 'longitude': fix.lng},
    );
  });
  tearDown(Get.reset);

  Future<void> start(WidgetTester tester) async {
    osrm = _FakeOsrm();
    ctrl = Get.put<DispatchJobsController>(_Controller(osrm));
    ctrl.riderPos.value = fix;
    ctrl.jobs.assignAll([_job1, _job2]);
    ctrl.selectJob(_job1);
    await tester.pumpAndSettle();
    expect(osrm.calls, 1);
  }

  Future<void> gps(WidgetTester tester, GeoPoint p) async {
    fix = p;
    await ctrl.refreshRiderPosition(force: true, silent: true);
    await tester.pumpAndSettle();
  }

  testWidgets('GPS fixes along the drawn route make no request',
      (tester) async {
    await start(tester);

    await gps(tester, const GeoPoint(13.41, 121.2));
    await gps(tester, const GeoPoint(13.42, 121.2002)); // ~20 m off the line
    await gps(tester, const GeoPoint(13.43, 121.2));

    expect(osrm.calls, 1);
    // 60% of the way up the line: the distance left is read off it.
    expect(ctrl.etaMeters.value, closeTo(2000, 50));
  });

  testWidgets('an off-route fix makes exactly one request', (tester) async {
    await start(tester);

    await gps(tester, const GeoPoint(13.42, 121.21)); // ~1 km east
    expect(osrm.calls, 2);
    // The new line starts there, so the next fix is back on route.
    await gps(tester, const GeoPoint(13.4205, 121.21));
    expect(osrm.calls, 2);
  });

  testWidgets('a new job makes exactly one request', (tester) async {
    await start(tester);

    ctrl.selectJob(_job2);
    await tester.pumpAndSettle();
    expect(osrm.calls, 2);
    expect(ctrl.routePoints.value!.last.lng, 121.25);
  });

  testWidgets('going back to a job redraws its last route without a request',
      (tester) async {
    await start(tester);
    final job1Line = ctrl.routePoints.value;
    ctrl.selectJob(_job2);
    await tester.pumpAndSettle();
    expect(osrm.calls, 2);

    ctrl.selectJob(_job1);
    await tester.pumpAndSettle();
    expect(ctrl.routePoints.value, same(job1Line));
    expect(osrm.calls, 2);
  });
}
