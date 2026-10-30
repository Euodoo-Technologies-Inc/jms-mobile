import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/theme/app_theme.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/core/widgets/detail_widgets.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/widget/dispatch_job_status.dart';
import 'package:fms/page/jobs/widget/job_status.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// Pumps [pill] and checks it is the shared [DetailStatusPill] showing
/// [label] in [color], legible on its own fill.
Future<void> _expectPill(
  WidgetTester tester,
  ThemeData theme,
  Widget Function(BuildContext) pill,
  String label,
  Color color,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: Builder(builder: pill))),
    ),
  );
  expect(find.byType(DetailStatusPill), findsOneWidget);
  final text = tester.widget<Text>(find.text(label));
  expect(text.style!.color, color);
  final fill = (tester
          .widget<Container>(
            find.descendant(
              of: find.byType(DetailStatusPill),
              matching: find.byType(Container),
            ),
          )
          .decoration! as BoxDecoration)
      .color!;
  // Opaque, so it reads on the green 4W job card too.
  expect(fill.a, 1.0);
  // The neutral grey is the one status allowed under 4.5:1 (4.4 in light).
  expect(_contrast(color, fill), greaterThanOrEqualTo(4.3));
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    final palette = theme.extension<DispatchPalette>()!;
    final green = theme.colorScheme.primary;

    for (final (status, dispatchStatus, label, color) in [
      (null, DispatchJobStatus.notStarted, 'Not started', palette.subtle),
      (1, DispatchJobStatus.onTheWay, 'On the way', palette.warning),
      (2, DispatchJobStatus.finished, 'Finished', green),
      (3, DispatchJobStatus.reschedule, 'Reschedule', palette.warning),
    ]) {
      testWidgets('$name: 4W status $status is a "$label" pill', (
        tester,
      ) async {
        final job = DispatchJob(id: 1, jobName: 'Job', status: status);
        expect(DispatchJobStatus.of(job), dispatchStatus);
        await _expectPill(tester, theme, dispatchStatus.pill, label, color);
      });
    }

    for (final status in JobStatus.values) {
      testWidgets('$name: 2W ${status.name} is a "${status.label}" pill', (
        tester,
      ) async {
        final color = switch (status) {
          JobStatus.open || JobStatus.completed => green,
          JobStatus.inProgress || JobStatus.rescheduled => palette.warning,
        };
        await _expectPill(tester, theme, status.pill, status.label, color);
      });
    }
  }

  test('brand and warning pills meet 4.5:1 in both modes', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final palette = theme.extension<DispatchPalette>()!;
      for (final c in [theme.colorScheme.primary, palette.warning]) {
        final fill = Color.alphaBlend(c.withValues(alpha: 0.08), palette.card);
        expect(_contrast(c, fill), greaterThanOrEqualTo(4.5));
      }
    }
  });
}
