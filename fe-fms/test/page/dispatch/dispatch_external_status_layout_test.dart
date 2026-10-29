import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/page/dispatch/presentation/dispatch_jobs_page.dart';

/// A 40-character ORMECO flag on a job with a long customer name.
const _longFlag = 'Has problem: meter seal broken, re-visit';

DispatchJob _flaggedJob() => DispatchJob.fromJson({
      'id': 1,
      'job_name': 'New Connection',
      'customer': 'JUAN DELA CRUZ Y SANTOS ELECTRICAL SUPPLY',
      'address': 'Brgy. Lalud, Calapan City',
      'lat': 13.41,
      'lng': 121.18,
      'external_status_label': _longFlag,
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
  test('the flag is 40 characters', () => expect(_longFlag.length, 40));

  for (final scale in [1.0, 2.0]) {
    testWidgets('card header fits a long ORMECO flag at ${scale}x text',
        (tester) async {
      // The carousel's card width on a 360 dp phone.
      await _pumpPhone(tester, scale,
          SizedBox(width: 312, child: debugJobCard(_flaggedJob())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(_longFlag), findsOneWidget);
    });

    testWidgets('panel status row fits a long ORMECO flag at ${scale}x text',
        (tester) async {
      await _pumpPhone(tester, scale,
          debugFocusedJobPanel(_flaggedJob(), etaMeters: 8500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(_longFlag), findsOneWidget);
      expect(find.text('away'), findsOneWidget);
    });
  }
}
