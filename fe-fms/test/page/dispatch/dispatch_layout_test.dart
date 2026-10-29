import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/presentation/dispatch_jobs_page.dart';

/// A job whose name wraps past three lines and address past two, so the card
/// is at its tallest.
DispatchJob _longJob() => DispatchJob.fromJson({
      'id': 1,
      'job_name': 'New Connection',
      'customer': 'JUAN DELA CRUZ Y SANTOS ELECTRICAL SUPPLY AND HARDWARE '
          'TRADING CORPORATION',
      'address': 'Purok 3, Brgy. Lalud, Calapan City, Oriental Mindoro, '
          'Philippines 5200, beside the barangay hall',
      'lat': 13.41,
      'lng': 121.18,
      'scheduled_arrival': '2026-10-29T09:30:00',
    });

/// Pumps [child] on a 360×780 dp phone at [scale]. A RenderFlex overflow
/// anywhere fails the test.
Future<void> _pumpPhone(WidgetTester tester, double scale, Widget child) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 780),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  ));
}

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('carousel card fits at ${scale}x text', (tester) async {
      await _pumpPhone(
          tester, scale, debugJobCarousel([_longJob()], etaMeters: 8500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('DESTINATION'), findsOneWidget);
      expect(find.text('8.5 km'), findsOneWidget);
    });
  }

  testWidgets('focused panel status row fits at 2x text', (tester) async {
    await _pumpPhone(
        tester, 2.0, debugFocusedJobPanel(_longJob(), etaMeters: 8500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('away'), findsOneWidget);
  });
}
