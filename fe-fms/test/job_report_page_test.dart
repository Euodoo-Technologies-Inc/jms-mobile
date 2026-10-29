import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/data/models/response/get_job_history__response_model.dart';
import 'package:fms/page/jobs/presentation/job_report_page.dart';

void main() {
  Future<void> pump(WidgetTester tester, Data job) async {
    // Tall enough that the lazy ListView builds every section.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: JobReportPage(job: job)));
  }

  testWidgets('shows the crew notes from Finish', (tester) async {
    await pump(tester, Data.fromMap({
      'JobName': 'Line check',
      'Notes': 'Replaced the fuse at the pole.',
      'FinishWhen': '2026-10-29 14:05:00',
    }));
    expect(find.text('COMPLETION NOTES'), findsOneWidget);
    expect(find.text('Replaced the fuse at the pole.'), findsOneWidget);
    expect(find.textContaining('follow-up'), findsNothing);
  });

  testWidgets('no notes means no notes section', (tester) async {
    await pump(tester, Data.fromMap({'JobName': 'Line check'}));
    expect(find.text('COMPLETION NOTES'), findsNothing);
    expect(find.textContaining('electrical connections'), findsNothing);
  });
}
