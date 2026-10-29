// End-to-end: a start and a finish made offline reach the board once
// signal returns (#21).
//
// The crew's calls fail at the HTTP client (as with no signal) and go into
// the app's real offline queue; flipping the connectivity flag back on lets
// the real DispatchSyncService drain it against a running laravel-jms. The
// dispatcher's board is then read to check what landed. Skips unless a
// dispatcher login is given:
//
//   E2E_ADMIN_EMAIL=… E2E_ADMIN_PASSWORD=… flutter test test/e2e \
//     --dart-define=DISPATCH_BASE_URL=http://localhost:8081/api/dispatch
//
// Each run links one more unlinked ORMECO crew (there is no unlink), so it
// is for a local/dev database only.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/dispatch/dispatch_api_client.dart';
import 'package:fms/core/dispatch/dispatch_constants.dart';
import 'package:fms/core/dispatch/dispatch_idempotency.dart';
import 'package:fms/core/services/connectivity_service.dart';
import 'package:fms/data/dispatch/datasource/dispatch_auth_datasource.dart';
import 'package:fms/data/dispatch/datasource/dispatch_jobs_datasource.dart';
import 'package:fms/page/dispatch/controller/dispatch_auth_controller.dart';
import 'package:fms/page/dispatch/service/dispatch_sync_service.dart';
import 'package:get/get.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _env = Platform.environment;
final _adminEmail = _env['E2E_ADMIN_EMAIL'] ?? '';
final _adminPassword = _env['E2E_ADMIN_PASSWORD'] ?? '';
final _webUrl = DispatchConstants.baseUrl.replaceFirst('/api/dispatch', '');

// A 1x1 GIF: passes the server's `image` rule without an image library.
final _photoBytes = base64Decode(
    'R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==');

void main() {
  // The sync service needs a binding (lifecycle listener, path_provider), but
  // the binding stubs every HttpClient to answer 400; this test wants the
  // real server.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final skip = _adminEmail.isEmpty || _adminPassword.isEmpty
      ? 'set E2E_ADMIN_EMAIL / E2E_ADMIN_PASSWORD to run'
      : null;

  final web = _Board(_webUrl);
  final auth = DispatchAuthDatasource();
  final jobs = DispatchJobsDatasource();
  // No signal: every request dies the way a dropped connection does.
  final noSignal = DispatchJobsDatasource(
    client: DispatchApiClient(
      httpClient: MockClient((_) => throw const SocketException('no signal')),
    ),
  );

  late int jobId;
  late List<File> photos;
  late DispatchSyncService sync;
  late ConnectivityService connectivity;
  late DateTime crewStartedAt;
  late DateTime crewFinishedAt;
  late DateTime syncedAt;
  late String? keysWhileOffline;

  group('offline start/finish → board', skip: skip, () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final docs = await Directory.systemTemp.createTemp('e2e_docs');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => docs.path,
      );
      photos = [
        for (var i = 0; i < DispatchConstants.minPhotos; i++)
          await File('${docs.path}/p$i.gif').writeAsBytes(_photoBytes),
      ];

      // An ORMECO crew nobody has given app access yet, with work today.
      await web.login(_adminEmail, _adminPassword);
      final day = await web.json('/admin/dispatch/rider-jobs?date=${_today()}');
      final pick = (day['data'] as List).cast<Map<String, dynamic>>().firstWhere(
            (r) =>
                r['rider']['external_source'] == 'ormeco_mcs' &&
                (r['rider']['user_id'] as num) < 0 &&
                (r['summary']['assigned'] as num) > 0,
            orElse: () => throw StateError(
                'No unlinked ORMECO crew with assigned work today — run mcs:sync'),
          );
      jobId = (pick['jobs'] as List).firstWhere(
        (j) => j['v2_status'] == 'assigned' && j['actual_arrival'] == null,
      )['job_id'] as int;

      final rnd = Random();
      final phone = '+639${100000000 + rnd.nextInt(899999999)}';
      final res = await auth.activate(
        phone: phone,
        code: await web.grantAccess(pick['rider']['rider_id'] as int, phone),
        newPassword: 'e2e-pass-${rnd.nextInt(1 << 30)}',
        deviceName: 'e2e offline ${DateTime.now().millisecondsSinceEpoch}',
        fcmToken: 'e2e-fcm-offline',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DispatchConstants.prefToken, res.token);

      connectivity = Get.put(ConnectivityService()); // starts offline
      Get.put<DispatchAuthController>(_SignedIn());
      sync = await Get.putAsync(() => DispatchSyncService().init());
    });

    tearDownAll(() async {
      await auth.logout();
      Get.reset();
    });

    test('start and finish made offline are queued, not sent', () async {
      // What DispatchJobsController does: key first, try, queue on failure.
      crewStartedAt = DateTime.now();
      await expectLater(
        noSignal.startJob(jobId,
            idempotencyKey: await _key('start', jobId),
            startedAt: crewStartedAt),
        throwsA(isA<DispatchApiException>().having((e) => e.isNetwork, 'isNetwork', true)),
      );
      await sync.enqueueStart(jobId, startedAt: crewStartedAt);

      // Time passes offline, so a sync-time stamp can't pass for the crew's.
      await Future<void>.delayed(const Duration(seconds: 3));

      crewFinishedAt = DateTime.now();
      await expectLater(
        noSignal.finishJob(
          jobId,
          idempotencyKey: await _key('finish', jobId),
          notes: 'e2e offline: meter replaced',
          meterNumber: 'E2E-OFF-1',
          photos: photos,
          finishedAt: crewFinishedAt,
        ),
        throwsA(isA<DispatchApiException>().having((e) => e.isNetwork, 'isNetwork', true)),
      );
      await sync.enqueueFinish(
        jobId,
        notes: 'e2e offline: meter replaced',
        meterNumber: 'E2E-OFF-1',
        photos: photos,
        finishedAt: crewFinishedAt,
      );
      keysWhileOffline = (await SharedPreferences.getInstance())
          .getString(DispatchConstants.prefIdempotencyKeys);
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(sync.pendingCount.value, 2);
      final job = await web.job(jobId);
      expect(job['actual_arrival'], isNull);
      expect(job['finished_at'], isNull);
    });

    test('signal returns: board shows it started then finished, with photos',
        () async {
      syncedAt = DateTime.now();
      connectivity.isConnected.value = true;
      await _drained(sync);

      final job = await web.job(jobId);
      final started = DateTime.parse(job['actual_arrival'] as String);
      final finished = DateTime.parse(job['finished_at'] as String);
      expect(finished.isBefore(started), isFalse);
      final boardPhotos = await web.json('/admin/dispatch/jobs/$jobId/photos');
      expect(boardPhotos['data'], hasLength(photos.length));

      final mine = await jobs.jobDetail(jobId);
      expect(mine.status, DispatchConstants.statusFinished);
      expect(mine.notes, 'e2e offline: meter replaced');
      expect(mine.meterNumber, 'E2E-OFF-1');
    });

    test("board keeps the crew's own times, not the sync time", () async {
      final job = await web.job(jobId);
      final started = DateTime.parse(job['actual_arrival'] as String);
      final finished = DateTime.parse(job['finished_at'] as String);
      // The crew started 6+ s before the sync, so a start stamped at the
      // sync is a backend without laravel-jms #47, not an app regression.
      if (started.difference(syncedAt).inSeconds.abs() < 2) {
        markTestSkipped('Backend ignores started_at / finished_at '
            '(needs laravel-jms #47); it stamped the sync time.');
        return;
      }
      expect(started.difference(crewStartedAt).inSeconds.abs(), lessThan(2));
      expect(finished.difference(crewFinishedAt).inSeconds.abs(), lessThan(2));
    });

    test('replaying the finish does not record a second one', () async {
      final before = await web.job(jobId);

      // The app died after the server took the finish but before the entry
      // left the queue: the same finish, with the same key, is sent again.
      connectivity.isConnected.value = false;
      await sync.enqueueFinish(
        jobId,
        notes: 'e2e offline: meter replaced',
        meterNumber: 'E2E-OFF-1',
        photos: photos,
        finishedAt: crewFinishedAt,
      );
      await (await SharedPreferences.getInstance())
          .setString(DispatchConstants.prefIdempotencyKeys, keysWhileOffline!);
      connectivity.isConnected.value = true;
      await _drained(sync);

      final job = await web.job(jobId);
      expect(job['finished_at'], before['finished_at']);
      final boardPhotos = await web.json('/admin/dispatch/jobs/$jobId/photos');
      expect(boardPhotos['data'], hasLength(photos.length));
    });
  });
}

/// Signed in, without the session side effects (jobs controller, GPS, FCM)
/// the real controller starts.
class _SignedIn extends DispatchAuthController {
  @override
  Future<void> checkSession() async => isAuthenticated.value = true;
}

Future<String> _key(String action, int jobId) =>
    DispatchIdempotencyStore.getOrCreate(action: action, jobId: jobId);

Future<void> _drained(DispatchSyncService sync) async {
  for (var i = 0; i < 120 && sync.pendingCount.value > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  expect(sync.pendingCount.value, 0, reason: 'queue did not drain');
}

String _today() {
  // The board's day is Asia/Manila (UTC+8, no DST).
  final d = DateTime.now().toUtc().add(const Duration(hours: 8));
  return d.toIso8601String().substring(0, 10);
}

/// The dispatcher's side: a cookie session on the web app, the same way the
/// browser holds one. dart:io rather than package:http for the cookie jar.
class _Board {
  _Board(this.base);

  final String base;
  final _client = HttpClient();
  final _cookies = <String, Cookie>{};

  Future<void> login(String email, String password) async {
    final res = await _send('POST', '/auth/login', form: {
      '_token': await _csrf('/auth'),
      'email': email,
      'password': password,
    });
    await res.drain<void>();
    if (res.statusCode != 302 ||
        res.headers.value('location')?.contains('/auth') == true) {
      throw StateError('Web login failed (${res.statusCode}).');
    }
  }

  /// "Give app access" on /user-list; the code is on the page it lands on.
  Future<String> grantAccess(int riderId, String phone) async {
    final res = await _send('POST', '/user-list/crew/$riderId/grant-access',
        form: {'_token': await _csrf('/user-list?type=vehicle'), 'phone': phone});
    await res.drain<void>();
    expect(res.statusCode, 302);
    final page = await _body(await _send('GET', '/user-list?type=vehicle'));
    final code = RegExp(r'id="activationCodeValue"[^>]*>\s*([A-Z0-9]+)\s*<')
        .firstMatch(page)
        ?.group(1);
    if (code == null) throw StateError('No activation code on /user-list.');
    return code;
  }

  Future<Map<String, dynamic>> job(int id) async =>
      (await json('/admin/dispatch/jobs/$id'))['data'] as Map<String, dynamic>;

  Future<Map<String, dynamic>> json(String path) async {
    final res = await _send('GET', path, accept: 'application/json');
    final body = await _body(res);
    if (res.statusCode != 200) {
      throw StateError('GET $path → ${res.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<String> _csrf(String page) async {
    final html = await _body(await _send('GET', page));
    final token = RegExp(r'name="_token" value="([^"]+)"').firstMatch(html);
    if (token == null) throw StateError('No CSRF token on $page.');
    return token.group(1)!;
  }

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Map<String, String>? form,
    String accept = 'text/html',
  }) async {
    final req = await _client.openUrl(method, Uri.parse('$base$path'));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptHeader, accept);
    req.cookies.addAll(_cookies.values);
    if (form != null) {
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      req.write(Uri(queryParameters: form).query);
    }
    final res = await req.close();
    for (final c in res.cookies) {
      _cookies[c.name] = Cookie(c.name, c.value);
    }
    return res;
  }

  Future<String> _body(HttpClientResponse res) =>
      res.transform(utf8.decoder).join();
}
