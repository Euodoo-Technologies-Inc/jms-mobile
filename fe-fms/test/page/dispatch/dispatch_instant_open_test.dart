// #62: the job list, history and job detail open on the data the app already
// holds, with no spinner, while the refresh runs behind them.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/dispatch/dispatch_constants.dart';
import 'package:fms/core/theme/theme_controller.dart';
import 'package:fms/data/dispatch/datasource/dispatch_jobs_datasource.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/controller/dispatch_jobs_controller.dart';
import 'package:fms/page/dispatch/presentation/dispatch_job_history_page.dart';
import 'package:fms/page/dispatch/presentation/dispatch_jobs_overview_page.dart';
import 'package:fms/page/dispatch/service/dispatch_notice_service.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A history fetch that is still in flight for the whole test.
class _SlowDatasource extends DispatchJobsDatasource {
  @override
  Future<List<DispatchJob>> jobsHistory({int limit = 50}) =>
      Completer<List<DispatchJob>>().future;
}

class _FakeJobsController extends DispatchJobsController {
  _FakeJobsController() : super(datasource: _SlowDatasource());

  @override
  // ignore: must_call_super
  void onInit() {}
}

final _done = DispatchJob(
  id: 7,
  jobName: 'Meter change',
  status: 2,
  address: 'Brgy. Lalud',
  finishWhen: '2026-10-29 15:00:00',
);

void main() {
  late _FakeJobsController jobs;

  setUp(() {
    SharedPreferences.setMockInitialValues(
        {DispatchConstants.prefToken: 'test-token'});
    Get.put(ThemeController());
    Get.put(DispatchNoticeController());
    jobs = Get.put<DispatchJobsController>(_FakeJobsController())
        as _FakeJobsController;
  });

  tearDown(Get.reset);

  testWidgets('job list shows loaded jobs on the first frame, no spinner',
      (tester) async {
    jobs.jobs.assignAll([
      DispatchJob(id: 1, jobName: 'Meter check', status: 0, lat: 13.4, lng: 121.2),
    ]);
    jobs.isLoading.value = true; // a refresh is in flight
    await tester.pumpWidget(
        const GetMaterialApp(home: DispatchJobsOverviewPage()));

    expect(find.text('Meter check'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('history shows the last list on the first frame, no spinner',
      (tester) async {
    jobs.history = [_done];
    await tester.pumpWidget(
        const GetMaterialApp(home: DispatchJobHistoryPage()));

    expect(find.text('Meter change'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('job detail shows the list\'s copy on the first frame, no spinner',
      (tester) async {
    await http.runWithClient(
      () => tester.pumpWidget(GetMaterialApp(
          home: DispatchJobHistoryDetailPage(jobId: 7, initial: _done))),
      () => MockClient((_) async => http.Response(
          jsonEncode({'data': {'id': 7, 'job_name': 'Meter change', 'status': 2}}),
          200)),
    );

    expect(find.text('Meter change'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
  });
}
