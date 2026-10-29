import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/widget/dispatch_external_status_pill.dart';

void main() {
  const base = {'id': 7, 'job_name': 'Disconnection'};

  Future<void> pumpPill(WidgetTester tester, Map<String, dynamic> json) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: DispatchExternalStatusPill(job: DispatchJob.fromJson(json)),
          ),
        ),
      ));

  testWidgets('flagged job shows the label with the warning icon',
      (tester) async {
    await pumpPill(tester, {
      ...base,
      'external_status': 'has_problem',
      'external_status_label': 'Has problem',
    });

    expect(find.text('Has problem'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byTooltip('ORMECO status: Has problem'), findsOneWidget);
  });

  testWidgets('unflagged, own or older-backend job renders nothing',
      (tester) async {
    for (final json in <Map<String, dynamic>>[
      {...base, 'external_status': 'pending', 'external_status_label': null},
      {...base, 'external_status': 'pending', 'external_status_label': ''},
      {...base, 'external_status': null, 'external_status_label': null},
      base,
    ]) {
      await pumpPill(tester, json);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing,
          reason: '$json');
      expect(find.byType(Tooltip), findsNothing, reason: '$json');
    }
  });
}
