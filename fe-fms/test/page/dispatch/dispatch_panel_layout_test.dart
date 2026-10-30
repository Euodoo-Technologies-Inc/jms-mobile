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

/// Every label the MCS mapper can send in the Detail section, in its order.
const _detailLabels = [
  'Service code', 'Record id', 'Account no', 'Account code', 'Rate code',
  'District office', 'District code', 'Town code', 'Barangay code',
  'Pole number', 'Meter serial', 'Meter brand', 'Meter seal',
  'Transformer serial', 'Transformer brand', 'Basic multiplier',
  'Transformer multiplier', 'Approved load', 'Last reading (kWh)',
  'Job type', 'Inspection code', 'Inspection nature', 'Request id',
  'Request group', 'Request nature', 'Additional info', 'Nearest account',
  'Requestor', 'Receiver', 'Remarks', 'Encoder',
];

DispatchJob _ormecoJob({String? flag, String customer = 'JUAN DELA CRUZ'}) =>
    DispatchJob.fromJson({
      'id': 908192,
      'job_name': 'New Connection',
      'customer': customer,
      'address': 'Brgy. Lalud, Calapan City',
      'lat': 13.41,
      'lng': 121.18,
      'scheduled_arrival': '2026-10-29T09:30:00',
      'external_status': flag == null ? null : 'has_problem',
      'external_status_label': flag,
      'external_details': [
        {
          'heading': 'Detail',
          'fields': [
            for (final l in _detailLabels)
              {
                'label': l,
                'value': l == 'Remarks'
                    ? 'Customer requests a morning visit.\nCall first.'
                    : '012026940280',
              },
          ],
        },
      ],
    });

Future<void> _pumpPanel(WidgetTester tester, [DispatchJob? job]) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Fresh tree each time, so a second pump doesn't inherit expanded tiles.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: debugFocusedJobPanel(job ?? _ormecoJob()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('detail labels stay on one line at 1.0x on a 360dp phone',
      (tester) async {
    await _pumpPanel(tester);
    await tester.ensureVisible(find.text('Detail'));
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final oneLine = tester.getSize(find.text('Record id')).height;
    for (final label in _detailLabels) {
      expect(tester.getSize(find.text(label)).height, oneLine,
          reason: '"$label" wrapped');
    }
    // The schedule caption too (it wrapped as "Schedule/d" at 1.3x).
    expect(tester.getSize(find.text('SCHEDULED')).height,
        lessThanOrEqualTo(oneLine));
  });

  testWidgets('section header is clipped round; its chevron turns',
      (tester) async {
    await _pumpPanel(tester);
    final header = find.ancestor(
        of: find.byType(ListTile), matching: find.byType(Material));
    final material = tester.widget<Material>(header.first);
    expect(material.clipBehavior, isNot(Clip.none));
    final shape = material.shape;
    expect(shape, isA<RoundedRectangleBorder>());
    expect((shape! as RoundedRectangleBorder).borderRadius,
        isNot(BorderRadius.zero));

    double turns() =>
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns;
    expect(turns(), 0);
    await tester.ensureVisible(find.text('Detail'));
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();
    expect(turns(), 0.5);
  });

  testWidgets('account button is a circle centred in the island\'s round end',
      (tester) async {
    final ctrl = _IdleJobsController();
    addTearDown(Get.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SafeArea(child: debugMapTopBar(ctrl))),
    ));

    final materials = find.ancestor(
        of: find.byTooltip('Profile'), matching: find.byType(Material));
    final button = materials.at(0);
    final island = materials.at(1);
    expect(tester.widget<Material>(button).shape, isA<CircleBorder>());
    final b = tester.getRect(button);
    final i = tester.getRect(island);
    expect(b.width, b.height, reason: 'a circle, not an oval');
    expect(b.width, greaterThanOrEqualTo(48));
    final inset = b.top - i.top;
    expect(i.bottom - b.bottom, inset, reason: 'vertically centred');
    expect(i.right - b.right, inset, reason: 'same gap on the right');
    // The island's end is a semicircle, so the gap is even all round.
    final radius =
        (tester.widget<Material>(island).borderRadius! as BorderRadius)
            .topRight;
    expect(radius.x, i.height / 2);
  });

  testWidgets('close button sits on the name row, centred on it',
      (tester) async {
    await _pumpPanel(tester);
    final name = find.text('JUAN DELA CRUZ');
    final close = find.byTooltip('Back to list');
    expect(tester.getCenter(close).dy, closeTo(tester.getCenter(name).dy, 1));
    // The stop disc shares that centre too.
    final disc = find
        .ancestor(of: find.text('1'), matching: find.byType(Container))
        .first;
    expect(tester.getCenter(disc).dy, closeTo(tester.getCenter(close).dy, 1));
    expect(tester.getTopLeft(disc).dx, 18, reason: 'same left edge');
    expect(tester.getTopLeft(name).dx, 18 + 24 + 10);
    final oneLine = tester.getSize(name).height;

    // A long name wraps before the ✕ and never runs under it.
    await _pumpPanel(
        tester,
        _ormecoJob(
            customer: 'JUAN DELA CRUZ Y SANTOS ELECTRICAL SUPPLY AND '
                'HARDWARE TRADING'));
    final long = find.textContaining('JUAN DELA CRUZ Y SANTOS');
    expect(tester.getSize(long).height, greaterThan(oneLine));
    expect(tester.getRect(long).right,
        lessThanOrEqualTo(tester.getRect(close).left));
    expect(tester.getCenter(close).dy, closeTo(tester.getCenter(long).dy, 1));
    // With a wrapped name the disc moves down with it, level with the ✕
    // (user feedback 2026-10-30: it sat on the first line, above the ✕).
    expect(tester.getCenter(disc).dy, closeTo(tester.getCenter(close).dy, 1));
  });

  testWidgets('a flagged job shows its notes once, up top, not in Detail',
      (tester) async {
    await _pumpPanel(tester, _ormecoJob(flag: 'Has problem'));
    expect(find.text('REMARKS'), findsOneWidget);
    expect(find.text('Customer requests a morning visit.\nCall first.'),
        findsOneWidget);
    expect(find.text('ADDITIONAL INFO'), findsOneWidget);
    await tester.ensureVisible(find.text('Detail'));
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();
    expect(find.text('Remarks'), findsNothing);
    expect(find.text('Additional info'), findsNothing);
    expect(find.text('Customer requests a morning visit.\nCall first.'),
        findsOneWidget);
    expect(find.text('Encoder'), findsOneWidget); // the rest of Detail stays

    // Unflagged: nothing up top, notes stay in Detail.
    await _pumpPanel(tester);
    expect(find.text('REMARKS'), findsNothing);
    await tester.ensureVisible(find.text('Detail'));
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();
    expect(find.text('Remarks'), findsOneWidget);
  });
}
