import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/theme/app_theme.dart';
import 'package:fms/page/jobs/controller/jobs_controller.dart';
import 'package:fms/page/jobs/widget/history_filter_bar.dart';
import 'package:get/get.dart';

/// Only the history-filter state; skips the network fetches in onInit.
class _FilterOnlyJobsController extends JobsController {
  @override
  // ignore: must_call_super
  void onInit() => initHistoryFilter();
}

void main() {
  testWidgets('2W Jobs filter bar: labelled controls, 48dp targets',
      (tester) async {
    final semantics = tester.ensureSemantics();
    Get.put<JobsController>(_FilterOnlyJobsController());
    addTearDown(Get.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: HistoryFilterBar(filteredCount: 3)),
    ));
    // Open the collapsible body so the search field and chips are checked too.
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('7 days'), findsOneWidget);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
}
