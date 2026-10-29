import 'package:flutter_test/flutter_test.dart';
import 'package:fms/data/dispatch/models/dispatch_job_model.dart';
import 'package:fms/data/dispatch/models/dispatch_rider_model.dart';

void main() {
  group('DispatchJob.externalDetails', () {
    test('reads ORMECO sections in order, dropping empty ones', () {
      final job = DispatchJob.fromJson({
        'id': 908192,
        'job_name': 'New Connection',
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
              {'label': 'Action at', 'value': '2026-10-28 15:59:47'},
            ],
          },
        ],
      });

      expect(job.externalDetails.map((s) => s.heading), ['Detail', 'Action']);
      expect(job.externalDetails.first.fields.last,
          (label: 'Meter serial', value: '261003640'));
      expect(job.notes, isNull);
    });

    test('older backend or own job: no details, notes untouched', () {
      for (final details in [null, 'garbage', <dynamic>[]]) {
        final job = DispatchJob.fromJson({
          'id': 1,
          'job_name': 'Delivery',
          'notes': 'Gate code 1234',
          'external_details': details,
        });
        expect(job.externalDetails, isEmpty);
        expect(job.notes, 'Gate code 1234');
      }
      expect(DispatchJob.fromJson({'id': 1}).externalDetails, isEmpty);
    });
  });

  group('DispatchRider vehicle', () {
    test('reads /me rider_id, vehicle and source, and survives the cache', () {
      final rider = DispatchRider.fromJson({
        'user_id': 70,
        'phone': '+639171234567',
        'fullname': 'D1 CREW',
        'rider_id': 7272,
        'vehicle': {'traxroot_id': 880001, 'vehicle_name': 'ORM-4W-01'},
        'external_source': 'ormeco_mcs',
      });
      expect(rider.riderId, 7272);
      expect(rider.vehicleName, 'ORM-4W-01');
      expect(rider.externalSource, 'ormeco_mcs');

      final cached = DispatchRider.fromJson(rider.toJson());
      expect(cached.riderId, 7272);
      expect(cached.vehicleName, 'ORM-4W-01');
      expect(cached.externalSource, 'ormeco_mcs');
    });

    test('no vehicle, or an older backend without the keys', () {
      for (final json in [
        {'user_id': 70, 'vehicle': null, 'rider_id': null},
        {'user_id': 70},
      ]) {
        final rider = DispatchRider.fromJson(json);
        expect(rider.vehicleName, isNull);
        expect(rider.riderId, isNull);
        expect(rider.externalSource, isNull);
      }
    });
  });
}
