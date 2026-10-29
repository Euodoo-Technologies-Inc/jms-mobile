import 'package:flutter_test/flutter_test.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';

void main() {
  const base = {'id': 7, 'job_name': 'Disconnection'};

  test('reads ORMECO status and label when present', () {
    final job = DispatchJob.fromJson({
      ...base,
      'external_status': 'has_problem',
      'external_status_label': 'Has problem',
    });
    expect(job.externalStatus, 'has_problem');
    expect(job.externalStatusLabel, 'Has problem');
  });

  test('null for our own jobs', () {
    final job = DispatchJob.fromJson({
      ...base,
      'external_status': null,
      'external_status_label': null,
    });
    expect(job.externalStatus, isNull);
    expect(job.externalStatusLabel, isNull);
  });

  test('null when an older backend omits the keys', () {
    final job = DispatchJob.fromJson(base);
    expect(job.externalStatus, isNull);
    expect(job.externalStatusLabel, isNull);
  });
}
