// Route line "draw-on" reveal: vsync-driven, eased, instant under the OS
// "Remove animations" setting (#34).
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/models/geo.dart';
import 'package:fms/core/theme/motion.dart';
import 'package:fms/data/dispatch/datasource/dispatch_osrm_datasource.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/controller/dispatch_jobs_controller.dart';
import 'package:get/get.dart';

const _points = 50;

/// OSRM that answers every request with a [_points]-point line.
class _FakeOsrm extends DispatchOsrmDatasource {
  @override
  Future<DispatchRoute?> route(List<GeoPoint> waypoints) async => DispatchRoute(
        points: [
          for (var i = 0; i < _points; i++) GeoPoint(13.4 + i * 0.001, 121.2),
        ],
        durationSeconds: 600,
        distanceMeters: 5000,
      );
}

/// Jobs controller with no polling, GPS or network.
class _Controller extends DispatchJobsController {
  _Controller() : super(osrm: _FakeOsrm());

  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  tearDown(Get.reset);

  Future<DispatchJobsController> previewOn(WidgetTester tester,
      {required bool reduce}) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduce);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final ctrl = Get.put<DispatchJobsController>(_Controller());
    ctrl.jobs.assignAll([
      DispatchJob(id: 1, jobName: 'A', status: 0, lat: 13.4, lng: 121.2),
      DispatchJob(id: 2, jobName: 'B', status: 0, lat: 13.5, lng: 121.3),
    ]);
    await ctrl.toggleRoutePreview();
    return ctrl;
  }

  testWidgets('the preview line draws on, eased, frame by frame',
      (tester) async {
    final ctrl = await previewOn(tester, reduce: false);
    expect(ctrl.previewRevealCount.value, 2);

    await tester.pump();
    await tester.pump(Motion.long);
    expect(ctrl.previewRevealCount.value, inExclusiveRange(2, _points));

    await tester.pumpAndSettle();
    expect(ctrl.previewRevealCount.value, _points);
  });

  testWidgets('the preview line shows whole at once under reduce motion',
      (tester) async {
    final ctrl = await previewOn(tester, reduce: true);
    expect(ctrl.previewRevealCount.value, _points);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
