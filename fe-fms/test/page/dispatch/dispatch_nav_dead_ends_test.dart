import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/theme/theme_controller.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/controller/dispatch_jobs_controller.dart';
import 'package:fms/page/dispatch/presentation/dispatch_finish_job_page.dart';
import 'package:fms/page/dispatch/presentation/dispatch_jobs_page.dart';
import 'package:fms/page/dispatch/service/dispatch_notice_service.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Jobs controller with no polling, GPS or network — the tests set its Rx
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

  Future<void> pumpMap(WidgetTester tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: DispatchJobsPage()));
    await tester.pump();
  }

  group('DispatchJobsPage (4W map)', () {
    testWidgets('Back with a job panel open closes the panel', (tester) async {
      jobs.jobs.assignAll([
        DispatchJob(id: 1, jobName: 'Meter check', status: 0, lat: 13.4, lng: 121.2),
      ]);
      jobs.lastFetchedAt.value = DateTime.now();
      jobs.selectedJobId.value = 1;
      await pumpMap(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(jobs.selectedJobId.value, isNull);
      expect(find.text('Exit App'), findsNothing);
    });

    testWidgets('Back with nothing open asks before exiting', (tester) async {
      jobs.lastFetchedAt.value = DateTime.now();
      await pumpMap(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Exit App'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(DispatchJobsPage), findsOneWidget);
    });

    testWidgets('load error keeps the top bar and offers Retry',
        (tester) async {
      jobs.error.value = 'No internet connection.';
      await pumpMap(tester);

      expect(find.text('No internet connection.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byTooltip('Job list'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('spinner on first load only, not on a zero-job poll',
        (tester) async {
      jobs.isLoading.value = true;
      await pumpMap(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      jobs.lastFetchedAt.value = DateTime.now();
      await tester.pumpAndSettle(); // the spinner fades out
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No pending jobs'), findsOneWidget);
    });
  });

  group('DispatchFinishJobPage Back', () {
    Future<void> pumpFinish(WidgetTester tester) async {
      await tester.pumpWidget(GetMaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const DispatchFinishJobPage(jobId: 1))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('an empty form closes straight away', (tester) async {
      await pumpFinish(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DispatchFinishJobPage), findsNothing);
    });

    testWidgets('a filled form asks before discarding', (tester) async {
      await pumpFinish(tester);
      await tester.enterText(find.byType(TextField).first, 'MTR-001');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard this finish?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(DispatchFinishJobPage), findsOneWidget);
      expect(find.text('MTR-001'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(DispatchFinishJobPage), findsNothing);
    });
  });
}
