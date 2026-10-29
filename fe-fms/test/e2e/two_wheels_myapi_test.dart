// End-to-end: the 2W app against the legacy /myapi (#22).
//
// Drives the app's real two-wheels datasources against a running laravel-jms:
// log in, take a job from today's pool, finish it with a photo, and load the
// history photo through its signed link. Skips unless a rider login is given:
//
//   E2E_2W_EMAIL=… E2E_2W_PASSWORD=… flutter test test/e2e \
//     --dart-define=BASE_URL=http://localhost:8081/myapi
//
// The rider needs unassigned jobs dated today or earlier in their company,
// and each run finishes one, so it is for a local/dev database only.
import 'dart:io';

import 'package:fms/core/constants/variables.dart';
import 'package:fms/data/datasource/auth_remote_datasource.dart';
import 'package:fms/data/datasource/driver_get_job_datasource.dart';
import 'package:fms/data/datasource/finish_job_datasource.dart';
import 'package:fms/data/datasource/get_job_datasource.dart';
import 'package:fms/data/datasource/get_job_history_datasource.dart';
import 'package:fms/data/datasource/get_job_ongoing_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

final _env = Platform.environment;
final _email = _env['E2E_2W_EMAIL'] ?? '';
final _password = _env['E2E_2W_PASSWORD'] ?? '';

// A 1x1 PNG: finished-job only takes JPEG/PNG and re-encodes it with GD.
const _photoBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  final skip = _email.isEmpty || _password.isEmpty
      ? 'set E2E_2W_EMAIL / E2E_2W_PASSWORD to run'
      : null;

  final auth = AuthRemoteDataSource();
  late int jobId;
  late Uri photo;

  group('2W app ↔ /myapi', skip: skip, () {
    setUpAll(() => SharedPreferences.setMockInitialValues({}));

    test('login returns the rider name and email', () async {
      final res = await auth.login(email: _email, password: _password);

      // What AuthController persists for the datasources below.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(Variables.prefApiKey, res.data!.apiKey!);
      await prefs.setString(Variables.prefUserID, '${res.data!.userId}');
      await prefs.setInt(Variables.prefCompanyID, res.data!.companyId!);
      await prefs.setInt(Variables.prefCompanyType, res.data!.companyType!);

      expect(res.data!.email, _email.trim().toLowerCase());
      expect(res.data!.fullname, isNotEmpty);
    });

    test("rider takes one of today's jobs", () async {
      // A run that died after taking a job left it ongoing; finish that one,
      // since the server allows one ongoing job per rider.
      final ongoing = await GetJobOngoingDatasource().getOngoingJobs();
      final held = ongoing.data!.where((j) => j.status == 1);
      if (held.isNotEmpty) {
        jobId = held.first.jobId!;
        return;
      }

      final pool = (await GetJobDatasource().getJob()).data!;
      expect(
        pool,
        isNotEmpty,
        reason: 'no unassigned job today for this rider — seed one',
      );
      final today = DateTime.now();
      for (final j in pool) {
        expect(j.jobDate!.isAfter(today), isFalse, reason: 'job ${j.jobId}');
      }
      jobId = pool.first.jobId!;

      final took = await DriverGetJobDatasource().driverGetJob(jobId: jobId);
      expect(took.success, isTrue, reason: took.message);
      final mine = (await GetJobOngoingDatasource().getOngoingJobs()).data!;
      expect(mine.map((j) => j.jobId), contains(jobId));
    });

    test('rider finishes it with a photo', () async {
      final done = await FinishJobDatasource().finishJob(
        jobId: jobId,
        imagesBase64: [_photoBase64],
        notes: 'e2e: two-wheels finish',
      );
      expect(done.success, isTrue, reason: done.message);
    });

    test('history has the job with a signed photo link', () async {
      final history = (await GetJobHistoryDatasource().getJobHistory()).data!;
      final job = history.firstWhere((j) => j.jobId == jobId);
      expect(job.details, hasLength(1));

      // A bare storage path here is the pre-laravel-jms#11 bug: the app
      // can't load it.
      final raw = job.details!.single.photo!;
      photo = Uri.parse(raw);
      expect(photo.isAbsolute, isTrue, reason: raw);
      expect(photo.path, contains('/myapi/finished-job-photo/'));
      expect(photo.queryParameters, contains('signature'));

      final expires = DateTime.fromMillisecondsSinceEpoch(
        int.parse(photo.queryParameters['expires']!) * 1000,
      );
      final ttl = expires.difference(DateTime.now());
      expect(ttl, greaterThan(const Duration(minutes: 55)));
      expect(ttl, lessThanOrEqualTo(const Duration(minutes: 60)));
    });

    test('signed photo link loads without the API key', () async {
      final res = await http.get(photo);
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], startsWith('image/'));
      expect(res.bodyBytes, isNotEmpty);
    });

    test('unsigned, tampered or re-dated photo links are refused', () async {
      final q = photo.queryParameters;
      final sig = q['signature']!;
      final pastExpiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
      for (final bad in [
        photo.replace(query: ''),
        photo.replace(
          queryParameters: {
            ...q,
            'signature':
                '${sig.substring(0, sig.length - 1)}'
                '${sig.endsWith('0') ? '1' : '0'}',
          },
        ),
        // Expired: the signature covers `expires`, so it can't be moved.
        photo.replace(queryParameters: {...q, 'expires': '$pastExpiry'}),
      ]) {
        final res = await http.get(bad);
        expect(res.statusCode, 403, reason: '$bad');
      }
    });

    test('logout drops the API key', () async {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString(Variables.prefApiKey)!;
      await auth.logout();
      final res = await http.get(
        Uri.parse(Variables.getJobEndpoint),
        headers: {'X-API-Key': key, 'Accept': 'application/json'},
      );
      expect(res.statusCode, 401, reason: res.body);
    });
  });
}
