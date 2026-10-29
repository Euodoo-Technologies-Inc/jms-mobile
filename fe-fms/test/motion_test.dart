import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/theme/app_theme.dart';
import 'package:fms/core/theme/motion.dart';
import 'package:fms/core/widgets/skeleton_loading.dart';
import 'package:fms/page/dispatch/service/dispatch_notice_service.dart';
import 'package:get/get.dart';

/// Wraps [child] in an app whose MediaQuery reports [reduce] as the OS
/// "Remove animations" setting.
Widget _app(Widget child, {required bool reduce}) => MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: child,
        ),
      ),
    );

void main() {
  tearDown(Get.reset);

  group('route transitions', () {
    Future<void> pumpApp(WidgetTester tester, {required bool reduce}) {
      return tester.pumpWidget(GetMaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: Builder(builder: (context) {
            Motion.applyRouteDefaults(context);
            return child!;
          }),
        ),
        home: const Text('home'),
      ));
    }

    testWidgets('use the Motion tokens', (tester) async {
      await pumpApp(tester, reduce: false);
      expect(Get.defaultTransitionDuration, Motion.medium);
      expect(Get.defaultTransitionCurve, Motion.emphasized);
    });

    testWidgets('are instant under reduce motion', (tester) async {
      await pumpApp(tester, reduce: true);
      expect(Get.defaultTransitionDuration, Duration.zero);

      Get.to(() => const Text('next'));
      await tester.pump();
      await tester.pump();
      expect(find.text('next'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('notice banner', () {
    Future<DispatchNoticeController> pumpHost(WidgetTester tester,
        {required bool reduce}) async {
      final ctrl = Get.put(DispatchNoticeController());
      await tester.pumpWidget(_app(
        const DispatchNoticeHost(child: SizedBox.expand()),
        reduce: reduce,
      ));
      return ctrl;
    }

    testWidgets('slides in normally', (tester) async {
      final ctrl = await pumpHost(tester, reduce: false);
      ctrl.success('Saved');
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      ctrl.dismiss();
      await tester.pumpAndSettle();
    });

    testWidgets('settles in one frame under reduce motion', (tester) async {
      final ctrl = await pumpHost(tester, reduce: true);
      ctrl.success('Saved');
      await tester.pump();
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);

      ctrl.dismiss();
      await tester.pump();
      expect(find.text('Saved'), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  for (final reduce in [false, true]) {
    testWidgets(
        'MotionSize ${reduce ? 'resizes instantly under reduce motion' : 'animates'}',
        (tester) async {
      late StateSetter setState;
      var tall = false;
      await tester.pumpWidget(_app(
        Align(
          child: StatefulBuilder(builder: (context, set) {
            setState = set;
            return MotionSize(child: SizedBox(width: 10, height: tall ? 100 : 0));
          }),
        ),
        reduce: reduce,
      ));
      setState(() => tall = true);
      await tester.pump();
      expect(tester.getSize(find.byType(MotionSize)).height,
          reduce ? 100 : lessThan(100));
    });
  }

  testWidgets('shimmer holds still under reduce motion', (tester) async {
    await tester.pumpWidget(_app(
      const ShimmerProvider(child: ShimmerBox()),
      reduce: true,
    ));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_app(
      const ShimmerProvider(child: ShimmerBox()),
      reduce: false,
    ));
    expect(tester.hasRunningAnimations, isTrue);
  });
}
