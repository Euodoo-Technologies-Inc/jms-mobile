// End-to-end: the 4W app and the web board stay in sync (#8).
//
// Drives the app's real dispatch data layer against a running laravel-jms,
// and after each crew action reads the dispatcher's board to check it shows
// the same thing. Skips unless a dispatcher login is given:
//
//   E2E_ADMIN_EMAIL=… E2E_ADMIN_PASSWORD=… flutter test test/e2e \
//     --dart-define=DISPATCH_BASE_URL=http://localhost:8081/api/dispatch
//
// Each run links one more unlinked ORMECO crew (there is no unlink), so it
// is for a local/dev database only.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fms/core/dispatch/dispatch_constants.dart';
import 'package:fms/core/dispatch/dispatch_uuid.dart';
import 'package:fms/data/dispatch/datasource/dispatch_auth_datasource.dart';
import 'package:fms/data/dispatch/datasource/dispatch_jobs_datasource.dart';
import 'package:fms/data/dispatch/datasource/dispatch_position_datasource.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _env = Platform.environment;
final _adminEmail = _env['E2E_ADMIN_EMAIL'] ?? '';
final _adminPassword = _env['E2E_ADMIN_PASSWORD'] ?? '';
final _webUrl = DispatchConstants.baseUrl.replaceFirst('/api/dispatch', '');

// A 1x1 GIF: passes the server's `image` rule without an image library.
final _photoBytes = base64Decode(
    'R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==');

void main() {
  final skip = _adminEmail.isEmpty || _adminPassword.isEmpty
      ? 'set E2E_ADMIN_EMAIL / E2E_ADMIN_PASSWORD to run'
      : null;

  final web = _Board(_webUrl);
  final auth = DispatchAuthDatasource();
  final jobs = DispatchJobsDatasource();
  final position = DispatchPositionDatasource();

  final rnd = Random();
  final phone = '+639${100000000 + rnd.nextInt(899999999)}';
  final deviceName = 'e2e ${DateTime.now().millisecondsSinceEpoch}';
  late Map<String, dynamic> crew; // board roster row
  late List<int> boardJobIds;
  late int userId;
  late int jobId;
  late String code;

  group('app ↔ board', skip: skip, () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await web.login(_adminEmail, _adminPassword);

      // An ORMECO crew nobody has given app access yet, with work today.
      final day = await web.json('/admin/dispatch/rider-jobs?date=${_today()}');
      final pick = (day['data'] as List).cast<Map<String, dynamic>>().firstWhere(
            (r) =>
                r['rider']['external_source'] == 'ormeco_mcs' &&
                (r['rider']['user_id'] as num) < 0 &&
                (r['summary']['assigned'] as num) > 0,
            orElse: () => throw StateError(
                'No unlinked ORMECO crew with assigned work today — run mcs:sync'),
          );
      crew = pick['rider'] as Map<String, dynamic>;
      boardJobIds = (pick['jobs'] as List)
          .where((j) => j['v2_status'] != 'cancelled')
          .map((j) => (j['job_id'] as num).toInt())
          .toList();
      jobId = (pick['jobs'] as List).firstWhere(
        (j) => j['v2_status'] == 'assigned' && j['actual_arrival'] == null,
      )['job_id'] as int;
    });

    test('dispatcher gives the crew app access and gets a code', () async {
      code = await web.grantAccess(crew['rider_id'] as int, phone);
      expect(code, matches(RegExp(r'^[A-Z2-9]{8}$')));
    });

    test('app activates; board shows the crew linked with this handset',
        () async {
      final res = await auth.activate(
        phone: phone,
        code: code,
        newPassword: 'e2e-pass-${rnd.nextInt(1 << 30)}',
        deviceName: deviceName,
        fcmToken: 'e2e-fcm-$deviceName',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DispatchConstants.prefToken, res.token);
      userId = res.rider.userId;

      final row = await web.rosterRow(crew['rider_id'] as int);
      expect(row['user_id'], userId);
      final devices = await web.json('/user-list/rider/$userId/devices');
      expect(jsonEncode(devices['data']), contains(deviceName));
    });

    test('/me is the same crew', () async {
      final me = await auth.me();
      expect(me.rider.userId, userId);
      expect(me.rider.fullname, crew['name']);
    });

    test("today's jobs match the board's Riders view", () async {
      final mine = (await jobs.jobsTodayJson()).map(DispatchJob.fromJson);
      expect(mine.map((j) => j.id), containsAll(boardJobIds));
      // The app also keeps earlier days' unfinished jobs (carry-over); the
      // board's Riders view shows the selected day only.
      for (final j in mine.where((j) => !boardJobIds.contains(j.id))) {
        expect(j.jobDate!.compareTo(_today()), lessThan(0), reason: 'job ${j.id}');
        expect(j.status, isNot(DispatchConstants.statusFinished));
      }
      expect(mine.firstWhere((j) => j.id == jobId).status, isNull,
          reason: 'an assigned job reads as not started in the app');
    });

    test('app starts the job; board shows it started', () async {
      final started = await jobs.startJob(jobId, idempotencyKey: _key());
      expect(started.status, DispatchConstants.statusOnTheWay);

      final job = await web.job(jobId);
      expect(job['actual_arrival'], isNotNull);
      expect(job['finished_at'], isNull);
    });

    test('app GPS shows the crew as seen on the board', () async {
      await position.postPosition(lat: 13.4117, lng: 121.1803);
      final row = await web.rosterRow(crew['rider_id'] as int);
      expect(row['last_seen_at'], isNotNull);
    });

    test('app finishes with photos; board shows it finished with them',
        () async {
      final dir = await Directory.systemTemp.createTemp('e2e_photos');
      final photos = [
        for (var i = 0; i < DispatchConstants.minPhotos; i++)
          await File('${dir.path}/p$i.gif').writeAsBytes(_photoBytes),
      ];
      final DispatchJob done = await jobs.finishJob(
        jobId,
        idempotencyKey: _key(),
        notes: 'e2e: meter replaced',
        meterNumber: 'E2E-123',
        photos: photos,
      );
      expect(done.status, DispatchConstants.statusFinished);
      expect(done.notes, 'e2e: meter replaced');
      expect(done.meterNumber, 'E2E-123');

      final job = await web.job(jobId);
      expect(job['finished_at'], isNotNull);
      final boardPhotos = await web.json('/admin/dispatch/jobs/$jobId/photos');
      expect(boardPhotos['data'], hasLength(photos.length));
    });

    test('finished job is in the app history', () async {
      final history = await jobs.jobsHistory();
      final job = history.firstWhere((j) => j.id == jobId);
      expect(job.status, DispatchConstants.statusFinished);
    });

    test('logout removes the handset from the board', () async {
      await auth.logout();
      final devices = await web.json('/user-list/rider/$userId/devices');
      expect(devices['data'], isEmpty);
    });
  });
}

String _today() {
  // The board's day is Asia/Manila (UTC+8, no DST).
  final d = DateTime.now().toUtc().add(const Duration(hours: 8));
  return d.toIso8601String().substring(0, 10);
}

String _key() => generateUuidV4();

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

  Future<Map<String, dynamic>> rosterRow(int riderId) async {
    final roster = await json('/admin/dispatch/riders?type=vehicle');
    return (roster['data'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((r) => r['rider_id'] == riderId);
  }

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
