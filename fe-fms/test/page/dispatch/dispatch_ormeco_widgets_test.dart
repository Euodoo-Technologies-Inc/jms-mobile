import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/dispatch/dispatch_constants.dart';
import 'package:fms/core/theme/theme_controller.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/data/dispatch/models/dispatch_rider_model.dart';
import 'package:fms/page/dispatch/controller/dispatch_auth_controller.dart';
import 'package:fms/page/dispatch/presentation/dispatch_job_history_page.dart';
import 'package:fms/page/dispatch/presentation/dispatch_jobs_page.dart';
import 'package:fms/page/dispatch/presentation/dispatch_profile_page.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An ORMECO job as `/jobs/{id}` returns it: the account, meter and action
/// fields live in `external_details`, `notes` is null. "Action taken" spans
/// two lines, as MCS remarks can.
Map<String, dynamic> _ormecoJobJson() => {
      'id': 908192,
      'job_name': 'New Connection',
      'status': 2,
      'address': 'Brgy. Lalud, Calapan City',
      'customer': 'JUAN DELA CRUZ',
      'service_type': 'New Connection',
      'notes': null,
      'external_details': [
        {
          'heading': 'Detail',
          'fields': [
            {'label': 'Account no', 'value': '012026940280'},
            {'label': 'Meter serial', 'value': '261003640'},
          ],
        },
        {'heading': 'Changes', 'fields': []},
        {
          'heading': 'Action',
          'fields': [
            {'label': 'Action taken', 'value': 'Installed meter\nSealed box'},
            {'label': 'Action at', 'value': '2026-10-28 15:59:47'},
          ],
        },
      ],
    };

/// One of our own jobs: no `external_details`, free-text notes.
Map<String, dynamic> _ownJobJson() => {
      'id': 1,
      'job_name': 'Delivery',
      'status': 2,
      'notes': 'Gate code 1234',
    };

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  group('DispatchJobDetailSectionTile (job panel)', () {
    Future<void> pumpSections(WidgetTester tester, DispatchJob job) =>
        tester.pumpWidget(_app(Scaffold(
          body: ListView(children: [
            for (final s in job.externalDetails)
              DispatchJobDetailSectionTile(section: s),
          ]),
        )));

    testWidgets('shows each section collapsed, its fields once expanded',
        (tester) async {
      await pumpSections(tester, DispatchJob.fromJson(_ormecoJobJson()));

      expect(find.text('Detail'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Changes'), findsNothing); // empty section dropped
      expect(find.text('Account no'), findsNothing); // collapsed

      await tester.tap(find.text('Detail'));
      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      expect(find.text('Account no'), findsOneWidget);
      expect(find.text('012026940280'), findsOneWidget);
      expect(find.text('Meter serial'), findsOneWidget);
      expect(find.text('261003640'), findsOneWidget);
      expect(find.text('Action taken'), findsOneWidget);
      expect(find.text('Installed meter\nSealed box'), findsOneWidget);
      expect(find.text('2026-10-28 15:59:47'), findsOneWidget);
    });

    testWidgets('own job renders no sections', (tester) async {
      await pumpSections(tester, DispatchJob.fromJson(_ownJobJson()));
      expect(find.byType(DispatchJobDetailSectionTile), findsNothing);
    });
  });

  group('DispatchJobHistoryDetailPage', () {
    late Map<String, dynamic> served;

    setUp(() {
      SharedPreferences.setMockInitialValues(
          {DispatchConstants.prefToken: 'test-token'});
    });

    // The page builds its own datasource, so serve /jobs/{id} through the
    // http package's zone client instead of the network.
    Future<void> pumpDetail(WidgetTester tester, Map<String, dynamic> job) async {
      served = job;
      // A tall surface so the lazy ListView builds every card.
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await http.runWithClient(
        () => tester.pumpWidget(
            _app(DispatchJobHistoryDetailPage(jobId: job['id'] as int))),
        () => MockClient((req) async {
          expect(req.url.toString(),
              DispatchConstants.jobDetailEndpoint(served['id'] as int));
          return http.Response(jsonEncode({'data': served}), 200);
        }),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows a card per ORMECO section with its fields',
        (tester) async {
      await pumpDetail(tester, _ormecoJobJson());

      expect(find.text('DETAIL'), findsOneWidget);
      expect(find.text('ACTION'), findsOneWidget);
      expect(find.text('CHANGES'), findsNothing);
      expect(find.text('Account no'), findsOneWidget);
      expect(find.text('012026940280'), findsOneWidget);
      expect(find.text('Meter serial'), findsOneWidget);
      expect(find.text('261003640'), findsOneWidget);
      expect(find.text('Installed meter\nSealed box'), findsOneWidget);
      expect(find.text('2026-10-28 15:59:47'), findsOneWidget);
      expect(find.text('Notes'), findsNothing);
    });

    testWidgets('own job: notes row, no ORMECO cards', (tester) async {
      await pumpDetail(tester, _ownJobJson());

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Gate code 1234'), findsOneWidget);
      expect(find.text('DETAIL'), findsNothing);
      expect(find.text('TIMELINE'), findsOneWidget);
    });
  });

  group('DispatchProfilePage vehicle row', () {
    late DispatchAuthController auth;

    setUp(() {
      // No token, so the controller's session check stops before any request.
      SharedPreferences.setMockInitialValues({});
      Get.put(ThemeController());
      auth = Get.put(DispatchAuthController());
    });

    tearDown(Get.reset);

    testWidgets('shows the crew vehicle from /me', (tester) async {
      auth.rider.value = DispatchRider.fromJson({
        'user_id': 70,
        'phone': '+639171234567',
        'fullname': 'D1 CREW',
        'rider_id': 7272,
        'vehicle': {'traxroot_id': 880001, 'vehicle_name': 'ORM-4W-01'},
        'external_source': 'ormeco_mcs',
      });
      await tester.pumpWidget(_app(const DispatchProfilePage()));

      expect(find.text('VEHICLE'), findsOneWidget);
      expect(find.text('ORM-4W-01'), findsOneWidget);
      expect(find.text('No vehicle assigned'), findsNothing);
    });

    testWidgets('no vehicle', (tester) async {
      auth.rider.value =
          DispatchRider.fromJson({'user_id': 70, 'vehicle': null});
      await tester.pumpWidget(_app(const DispatchProfilePage()));

      expect(find.text('VEHICLE'), findsOneWidget);
      expect(find.text('No vehicle assigned'), findsOneWidget);
    });
  });
}
