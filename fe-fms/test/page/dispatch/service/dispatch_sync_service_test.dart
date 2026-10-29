// The crew's start/finish time survives the offline queue and reaches the
// server (#27).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/dispatch/dispatch_api_client.dart';
import 'package:fms/core/dispatch/dispatch_constants.dart';
import 'package:fms/core/services/connectivity_service.dart';
import 'package:fms/data/dispatch/datasource/dispatch_jobs_datasource.dart';
import 'package:fms/data/dispatch/offline/dispatch_queue_repository.dart';
import 'package:fms/page/dispatch/controller/dispatch_auth_controller.dart';
import 'package:fms/page/dispatch/service/dispatch_sync_service.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pressedAt = DateTime(2026, 10, 29, 13, 5, 7);
  late List<http.Request> sent;
  late ConnectivityService connectivity;
  late DispatchSyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({DispatchConstants.prefToken: 't'});
    final docs = await Directory.systemTemp.createTemp('queue_docs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => docs.path,
        );
    sent = [];
    final server = MockClient((req) async {
      sent.add(req);
      return http.Response(
        jsonEncode({
          'data': {'id': 7},
        }),
        200,
      );
    });
    connectivity = Get.put(ConnectivityService()); // starts offline
    Get.put<DispatchAuthController>(_SignedIn());
    sync = await Get.putAsync(
      () => DispatchSyncService(
        jobs: DispatchJobsDatasource(
          client: DispatchApiClient(httpClient: server),
        ),
      ).init(),
    );
  });

  tearDown(Get.reset);

  Future<void> flush() async {
    connectivity.isConnected.value = true;
    final queue = DispatchQueueRepository();
    for (var i = 0; i < 40 && !await queue.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(await queue.isEmpty, isTrue, reason: 'queue did not drain');
  }

  test('a queued start keeps its time across save, reload and flush', () async {
    await sync.enqueueStart(7, startedAt: pressedAt);

    final reloaded = await DispatchQueueRepository().readAll();
    expect(reloaded.single.actionAt, pressedAt);

    await flush();
    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body['started_at'], isoWithOffset(pressedAt));
    expect(
      DateTime.parse(body['started_at'] as String).isAtSameMomentAs(pressedAt),
      isTrue,
    );
  });

  test('a queued finish sends finished_at', () async {
    await sync.enqueueFinish(7, notes: 'n', finishedAt: pressedAt);
    await flush();
    expect(
      sent.single.body,
      contains('name="finished_at"\r\n\r\n${isoWithOffset(pressedAt)}\r\n'),
    );
  });

  test(
    'an entry queued before the time was recorded still flushes, without one',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'dispatch.queue.entries',
        jsonEncode([
          {
            'id': '1-1',
            'type': 'start',
            'enqueuedAt': '2026-10-29T13:05:07.000',
            'jobId': 7,
          },
        ]),
      );

      await flush();
      expect(jsonDecode(sent.single.body), isEmpty);
    },
  );

  test('the time is ISO 8601 with the device offset', () {
    expect(
      isoWithOffset(pressedAt),
      matches(RegExp(r'^2026-10-29T13:05:07[+-]\d\d:\d\d$')),
    );
  });
}

class _SignedIn extends DispatchAuthController {
  @override
  Future<void> checkSession() async => isAuthenticated.value = true;
}
