import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/theme/motion.dart';
import 'package:fms/core/theme/theme_controller.dart';
import 'package:fms/page/dispatch/controller/dispatch_jobs_controller.dart';
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

  /// Pumps the 4W map with the OS "Remove animations" setting at [reduce].
  Future<void> pumpMap(WidgetTester tester, {required bool reduce}) async {
    await tester.pumpWidget(GetMaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: const DispatchJobsPage(),
    ));
    await tester.pump();
  }

  /// Two frames with no time passing: one for the Obx rebuild, one for the
  /// switcher to drop its outgoing child. Only zero-length motion is done.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// Unmounts the map and lets its in-flight tile requests (Dio, zero-length
  /// timers) finish, so flutter_test doesn't report them as pending.
  Future<void> unmountMap(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Whether the offline banner area has reached its content's full height.
  bool bannerSettled(WidgetTester tester) {
    final area = find.ancestor(
      of: find.text('No internet connection.'),
      matching: find.byType(MotionSize),
    );
    final content = find.descendant(of: area, matching: find.byType(Column));
    return tester.getSize(area).height == tester.getSize(content.first).height;
  }

  for (final reduce in [false, true]) {
    final mode = reduce ? 'under reduce motion' : 'normally';

    testWidgets('offline banner ${reduce ? 'is instant' : 'grows in'} '
        '$mode', (tester) async {
      jobs.lastFetchedAt.value = DateTime.now();
      await pumpMap(tester, reduce: reduce);

      jobs.error.value = 'No internet connection.';
      await settle(tester);
      expect(bannerSettled(tester), reduce);
      await unmountMap(tester);
    });

    testWidgets('first-load spinner ${reduce ? 'goes instantly' : 'fades'} '
        '$mode', (tester) async {
      jobs.isLoading.value = true;
      await pumpMap(tester, reduce: reduce);

      jobs.lastFetchedAt.value = DateTime.now();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator),
          reduce ? findsNothing : findsOneWidget);
      await unmountMap(tester);
    });
  }
}
