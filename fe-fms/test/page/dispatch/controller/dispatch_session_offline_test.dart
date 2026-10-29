// 4W session expiry, offline pending state and the raw-JSON job cache (#29).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/dispatch/dispatch_api_client.dart';
import 'package:fms/core/dispatch/dispatch_constants.dart';
import 'package:fms/data/dispatch/datasource/dispatch_jobs_datasource.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/data/dispatch/offline/dispatch_queue_repository.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import 'package:fms/page/auth/presentation/login_chooser_page.dart';
import 'package:fms/page/dispatch/controller/dispatch_auth_controller.dart';
import 'package:fms/page/dispatch/controller/dispatch_jobs_controller.dart';
import 'package:fms/page/dispatch/service/dispatch_notice_service.dart';
import 'package:fms/page/dispatch/service/dispatch_sync_service.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _job = {
  'id': 7,
  'job_name': 'Disconnect',
  'status': 1,
  'customer': 'Juan Dela Cruz',
  'external_status': 'IP',
  'external_details': [
    {
      'heading': 'Detail',
      'fields': [
        {'label': 'Account', 'value': '0012'},
      ],
    },
  ],
};

/// Serves today's jobs on GET; answers everything else with [onAction].
DispatchJobsController _controller(
  Future<http.Response> Function(http.BaseRequest) onAction,
) {
  final server = MockClient((req) async {
    if (req.method == 'GET') {
      return http.Response(
        jsonEncode({
          'data': {
            'jobs': [_job],
          },
        }),
        200,
      );
    }
    return onAction(req);
  });
  return DispatchJobsController(
    datasource: DispatchJobsDatasource(
      client: DispatchApiClient(httpClient: server),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({DispatchConstants.prefToken: 't'});
    final docs = await Directory.systemTemp.createTemp('queue_docs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => docs.path,
        );
  });

  tearDown(Get.reset);

  test('the cache keeps the raw job, ORMECO fields included', () async {
    final ctrl = _controller((_) async => http.Response('', 500));
    await ctrl.refreshToday();

    final prefs = await SharedPreferences.getInstance();
    final cached = (jsonDecode(
      prefs.getString(DispatchConstants.prefJobsTodayCache)!,
    ) as List).single as Map<String, dynamic>;
    expect(cached['external_details'], _job['external_details']);
    expect(cached['external_status'], 'IP');
    expect(DispatchJob.fromJson(cached).customer, 'Juan Dela Cruz');
  });

  test('an offline Finish shows the job finished; a second tap queues nothing',
      () async {
    Get.put(DispatchSyncService());
    final ctrl = _controller(
      (_) async => throw const SocketException('no signal'),
    );
    await ctrl.refreshToday();

    await expectLater(
      ctrl.finishJob(7, meterNumber: '1'),
      throwsA(isA<DispatchQueuedException>()),
    );
    expect(ctrl.jobs.single.isFinished, isTrue);
    expect(Get.find<DispatchSyncService>().pendingCount.value, 1);

    await expectLater(
      ctrl.finishJob(7, meterNumber: '1'),
      throwsA(isA<DispatchQueuedException>()),
    );
    expect(await DispatchQueueRepository().readAll(), hasLength(1));
  });

  testWidgets('a 401 during Finish lands on sign-in with a notice', (
    tester,
  ) async {
    final notice = Get.put(DispatchNoticeController());
    Get.put(AuthController());
    Get.put<DispatchAuthController>(_SignedIn());
    final ctrl = _controller(
      (_) async => http.Response('{"message":"Unauthenticated."}', 401),
    );

    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    Get.to(() => const Scaffold(body: Text('Finish job')));
    await tester.pumpAndSettle();

    Object? thrown;
    await tester.runAsync(() async {
      try {
        await ctrl.finishJob(7, meterNumber: '1');
      } catch (e) {
        thrown = e;
      }
    });
    // What the Finish page does with it: show the error.
    notice.error((thrown as DispatchApiException).message);
    await tester.pumpAndSettle();

    final chooser = find.byType(LoginChooserPage);
    expect(chooser, findsOneWidget);
    expect(Navigator.of(tester.element(chooser)).canPop(), isFalse);
    expect(notice.current.value?.message,
        'Session expired. Please sign in again.');
    expect(tester.takeException(), isNull);

    notice.dismiss();
  });
}

class _SignedIn extends DispatchAuthController {
  @override
  Future<void> checkSession() async => isAuthenticated.value = true;
}
