import 'package:flutter_test/flutter_test.dart';
import 'package:fms/data/dispatch/offline/dispatch_queue_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the first action on an empty queue (fresh install, after logout) is queued',
      () async {
    SharedPreferences.setMockInitialValues({});
    final queue = DispatchQueueRepository();

    await queue.enqueueStart(1);
    await queue.enqueueFcmRefresh('t');

    expect((await queue.readAll()).map((e) => e.type),
        [DispatchQueueOpType.start, DispatchQueueOpType.fcm]);
  });
}
