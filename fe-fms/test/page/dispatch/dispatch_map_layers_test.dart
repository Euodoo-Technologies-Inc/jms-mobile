// 4W map, scoped rebuilds (#62): a GPS fix redraws the rider dot and pans the
// camera, but must not rebuild the tile layer or the job pins.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/models/geo.dart';
import 'package:fms/core/theme/theme_controller.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/controller/dispatch_jobs_controller.dart';
import 'package:fms/page/dispatch/presentation/dispatch_jobs_page.dart';
import 'package:fms/page/dispatch/service/dispatch_notice_service.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Jobs controller with no polling, GPS or network — the test sets its Rx
/// state directly.
class _FakeJobsController extends DispatchJobsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  late _FakeJobsController jobs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.put(ThemeController());
    Get.put(DispatchNoticeController());
    jobs = Get.put<DispatchJobsController>(_FakeJobsController())
        as _FakeJobsController;
  });

  tearDown(Get.reset);

  /// Unmounts the map and lets its in-flight tile requests finish, so
  /// flutter_test doesn't report their timers as pending.
  Future<void> unmountMap(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// The marker layer carrying the job pins — the one with a stop number.
  Finder jobPins() => find
      .ancestor(of: find.text('1'), matching: find.byType(MarkerLayer))
      .first;

  testWidgets('a rider fix rebuilds the rider dot only', (tester) async {
    jobs.jobs.assignAll([
      DispatchJob(id: 1, jobName: 'Meter check', status: 0, lat: 13.4, lng: 121.2),
    ]);
    jobs.lastFetchedAt.value = DateTime.now();
    jobs.riderPos.value = const GeoPoint(13.41, 121.21);
    await tester.pumpWidget(const GetMaterialApp(home: DispatchJobsPage()));
    await tester.pump();

    final tiles = tester.widgetList<TileLayer>(find.byType(TileLayer)).toList();
    expect(tiles, hasLength(2)); // preview + sharp
    final pins = tester.widget<MarkerLayer>(jobPins());
    expect(find.byType(MarkerLayer), findsNWidgets(2)); // pins + rider

    jobs.riderPos.value = const GeoPoint(13.42, 121.22);
    await tester.pump();

    // Same widget instances: Flutter skipped them, nothing rebuilt.
    expect(
      tester.widgetList<TileLayer>(find.byType(TileLayer)),
      orderedEquals(tiles),
    );
    expect(tester.widget<MarkerLayer>(jobPins()), same(pins));
    // ...while the rider's own layer did pick up the new fix.
    final rider = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .firstWhere((l) => !identical(l, pins));
    expect(rider.markers.single.point.latitude, closeTo(13.42, 1e-9));

    await unmountMap(tester);
  });
}
