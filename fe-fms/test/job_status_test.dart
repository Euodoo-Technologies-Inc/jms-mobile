import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/theme/app_theme.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/page/jobs/widget/job_status.dart';
import 'package:fms/page/jobs/widget/job_summary_card.dart';

/// Pumps a jobs-list card and a detail-page header for [status] side by side.
Future<void> _pump(WidgetTester tester, ThemeData theme, JobStatus status) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ListView(
            children: [
              KeyedSubtree(
                key: const Key('list'),
                child: JobSummaryCard(
                  title: 'Job',
                  badges: [status.badge(context)],
                ),
              ),
              KeyedSubtree(
                key: const Key('detail'),
                child: status.pill(context),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Text _label(WidgetTester tester, String key, String label) =>
    tester.widget<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.text(label)),
    );

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    for (final status in JobStatus.values) {
      testWidgets('$name: ${status.name} reads the same on list and detail', (
        tester,
      ) async {
        await _pump(tester, theme, status);
        final list = _label(tester, 'list', status.label);
        final detail = _label(tester, 'detail', status.label);
        expect(list.style!.color, detail.style!.color);
        if (status == JobStatus.inProgress) {
          // Was blue "In Progress" on the list, amber "Ongoing" on detail.
          expect(detail.data, 'In progress');
          expect(detail.style!.color, DispatchColors.warning);
        }
        expect(
          find.descendant(
            of: find.byKey(const Key('detail')),
            matching: find.byIcon(status.icon),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('scheme is seeded from the brand, not the old blue', (
    tester,
  ) async {
    final light = AppTheme.light();
    expect(light.colorScheme.primary, DispatchColors.brand);
    expect(light.colorScheme.error, DispatchColors.danger);
    expect(light.scaffoldBackgroundColor, DispatchPalette.light.pageSurface);
    expect(
      AppTheme.dark().scaffoldBackgroundColor,
      DispatchPalette.dark.pageSurface,
    );
    expect(
      AppTheme.dark().appBarTheme.backgroundColor,
      DispatchPalette.dark.pageSurface,
    );
  });

  test('white on brand meets WCAG AA for small text', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) /
          (la > lb ? lb + 0.05 : la + 0.05);
    }

    expect(
      contrast(DispatchColors.onBrand, DispatchColors.brand),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(Colors.white, DispatchColors.warning),
      greaterThanOrEqualTo(4.5),
    );
    // The 2W status green on dark surfaces uses the seeded, lighter primary.
    expect(
      contrast(AppTheme.dark().colorScheme.primary, DispatchPalette.dark.card),
      greaterThanOrEqualTo(4.5),
    );
  });
}
