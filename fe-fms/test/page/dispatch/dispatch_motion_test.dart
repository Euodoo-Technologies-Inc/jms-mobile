import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/theme/motion.dart';
import 'package:fms/core/theme/theme_controller.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
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

  final carousel = find.byKey(const ValueKey('carousel'));
  final panel = find.byKey(const ValueKey('panel_1'));

  /// Whether [layer] sits entirely below the screen's bottom edge.
  bool offScreen(WidgetTester tester, Finder layer) =>
      tester.getRect(layer).top >= tester.getSize(find.byType(Scaffold)).height;

  /// Whether [layer] rests on the bottom edge, fully on screen.
  bool inPlace(WidgetTester tester, Finder layer) =>
      tester.getRect(layer).bottom ==
      tester.getSize(find.byType(Scaffold)).height;

  Future<void> pumpMapWithJob(WidgetTester tester, {required bool reduce}) {
    jobs.lastFetchedAt.value = DateTime.now();
    jobs.jobs.assignAll([
      DispatchJob(id: 1, jobName: 'Meter check', status: 0, lat: 13.4, lng: 121.2),
    ]);
    return pumpMap(tester, reduce: reduce);
  }

  /// A zero-length frame: a slide that was just started takes its first
  /// tick, so the clock of the next timed pump starts from here.
  Future<void> firstTick(WidgetTester tester) => tester.pump();

  testWidgets('opening a job: the cards slide out, then the panel rises',
      (tester) async {
    await pumpMapWithJob(tester, reduce: false);
    expect(inPlace(tester, carousel), isTrue);

    jobs.selectedJobId.value = 1;
    await tester.pump(); // the panel mounts below the edge; the swap starts
    await firstTick(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(inPlace(tester, carousel), isFalse); // on its way down
    expect(offScreen(tester, carousel), isFalse);
    expect(offScreen(tester, panel), isTrue); // not yet moving

    await tester.pump(const Duration(milliseconds: 100));
    expect(offScreen(tester, carousel), isTrue); // gone before the panel moves
    expect(offScreen(tester, panel), isTrue);

    await tester.pump(const Duration(milliseconds: 1)); // hand-off
    await firstTick(tester);
    await tester.pump(const Duration(milliseconds: 150));
    expect(offScreen(tester, panel), isFalse); // rising
    expect(inPlace(tester, panel), isFalse);

    await tester.pump(const Duration(milliseconds: 151));
    await settle(tester);
    expect(inPlace(tester, panel), isTrue);
    expect(carousel, findsNothing);
    await unmountMap(tester);
  });

  testWidgets('closing: the panel slides out, then the cards rise',
      (tester) async {
    await pumpMapWithJob(tester, reduce: false);
    jobs.selectedJobId.value = 1;
    await tester.pumpAndSettle();
    expect(inPlace(tester, panel), isTrue);
    expect(carousel, findsNothing);

    jobs.selectedJobId.value = null;
    await tester.pump();
    await firstTick(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(inPlace(tester, panel), isFalse);
    expect(offScreen(tester, panel), isFalse);
    expect(offScreen(tester, carousel), isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    expect(offScreen(tester, panel), isTrue);
    expect(offScreen(tester, carousel), isTrue);

    await tester.pump(const Duration(milliseconds: 1));
    await firstTick(tester);
    await tester.pump(const Duration(milliseconds: 150));
    expect(offScreen(tester, carousel), isFalse);
    expect(inPlace(tester, carousel), isFalse);

    await tester.pump(const Duration(milliseconds: 151));
    await settle(tester);
    expect(inPlace(tester, carousel), isTrue);
    expect(panel, findsNothing);
    await unmountMap(tester);
  });

  testWidgets('under reduce motion the swap takes no animation time',
      (tester) async {
    await pumpMapWithJob(tester, reduce: true);

    jobs.selectedJobId.value = 1;
    await settle(tester);
    expect(inPlace(tester, panel), isTrue);
    expect(carousel, findsNothing);

    jobs.selectedJobId.value = null;
    await settle(tester);
    expect(inPlace(tester, carousel), isTrue);
    expect(panel, findsNothing);
    await unmountMap(tester);
  });

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
