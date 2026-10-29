import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/controller/dispatch_jobs_controller.dart';
import 'package:fms/page/dispatch/presentation/dispatch_jobs_page.dart';
import 'package:get/get.dart';

/// Jobs state only; skips the polling, GPS and fetches started in onInit.
class _IdleJobsController extends DispatchJobsController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  // ignore: must_call_super
  void onClose() {}
}

DispatchJob _job() => DispatchJob.fromJson({
      'id': 1,
      'job_name': 'New Connection',
      'customer': 'Juan Dela Cruz',
      'address': 'Calapan City',
      'lat': 13.41,
      'lng': 121.18,
    });

void main() {
  testWidgets('4W map top bar: labelled controls, 48dp targets',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final ctrl = _IdleJobsController()..jobs.add(_job());
    addTearDown(Get.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SafeArea(child: debugMapTopBar(ctrl))),
    ));
    expect(find.byTooltip('Job list'), findsOneWidget);
    expect(find.byTooltip('Profile'), findsOneWidget);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('4W panel drag handle is a labelled 48dp target',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: debugFocusedJobPanel(_job()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final handle = find.bySemanticsLabel('Resize job panel');
    expect(handle, findsOneWidget);
    expect(tester.getSize(handle).height, greaterThanOrEqualTo(48));
    semantics.dispose();
  });
}
