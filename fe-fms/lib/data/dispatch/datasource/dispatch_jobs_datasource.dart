import 'dart:io';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';
import '../models/dispatch_job_model.dart';

class DispatchJobsDatasource {
  DispatchJobsDatasource({DispatchApiClient? client})
      : _client = client ?? DispatchApiClient();

  final DispatchApiClient _client;

  Future<List<DispatchJob>> jobsToday() async {
    final body = await _client.getJson(DispatchConstants.jobsTodayEndpoint);
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final jobs = data['jobs'];
    if (jobs is! List) return const [];
    return jobs
        .whereType<Map<String, dynamic>>()
        .map(DispatchJob.fromJson)
        .toList(growable: false);
  }

  Future<List<DispatchJob>> jobsHistory({int limit = 50}) async {
    final body = await _client.getJson(
      '${DispatchConstants.jobsHistoryEndpoint}?limit=$limit',
    );
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final jobs = data['jobs'];
    if (jobs is! List) return const [];
    return jobs
        .whereType<Map<String, dynamic>>()
        .map(DispatchJob.fromJson)
        .toList(growable: false);
  }

  Future<DispatchJob> jobDetail(int id) async {
    final body = await _client.getJson(DispatchConstants.jobDetailEndpoint(id));
    final data = (body['data'] as Map).cast<String, dynamic>();
    return DispatchJob.fromJson(data);
  }

  /// Idempotent. Caller persists [idempotencyKey] across retries.
  Future<DispatchJob> startJob(int id, {required String idempotencyKey}) async {
    final body = await _client.postJson(
      DispatchConstants.jobStartEndpoint(id),
      idempotencyKey: idempotencyKey,
    );
    final data = (body['data'] as Map).cast<String, dynamic>();
    return DispatchJob.fromJson(data);
  }

  /// Idempotent multipart upload. [photos] up to 5 files, ≤ 4 MB each.
  Future<DispatchJob> finishJob(
    int id, {
    required String idempotencyKey,
    String? notes,
    String? meterNumber,
    List<File> photos = const [],
  }) async {
    final body = await _client.postMultipart(
      DispatchConstants.jobFinishEndpoint(id),
      idempotencyKey: idempotencyKey,
      fields: {
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (meterNumber != null && meterNumber.isNotEmpty)
          'meter_number': meterNumber,
      },
      fileFields:
          photos.map((f) => MapEntry('photos[]', f)).toList(growable: false),
    );
    final data = (body['data'] as Map).cast<String, dynamic>();
    return DispatchJob.fromJson(data);
  }
}
