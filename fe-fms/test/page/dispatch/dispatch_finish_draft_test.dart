import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/dispatch/dispatch_finish_draft.dart';
import 'package:fms/core/theme/theme_controller.dart';
import 'package:fms/page/dispatch/controller/dispatch_jobs_controller.dart';
import 'package:fms/page/dispatch/presentation/dispatch_finish_job_page.dart';
import 'package:fms/page/dispatch/presentation/dispatch_jobs_page.dart';
import 'package:fms/page/dispatch/service/dispatch_notice_service.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No camera, no platform channel: hands back canned results.
class _FakePicker extends ImagePicker {
  _FakePicker({this.lost, this.picked});
  final LostDataResponse? lost;
  final XFile? picked;

  @override
  Future<LostDataResponse> retrieveLostData() async =>
      lost ?? LostDataResponse.empty();

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      picked;
}

class _FakeJobsController extends DispatchJobsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Issue #78: Android killed the app while the Finish page's camera was up,
/// and the crew came back to the map with photos, meter and notes gone.
void main() {
  late Directory dir;
  late File photo1;
  late File photo2;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.put(ThemeController());
    Get.put(DispatchNoticeController());
    dir = Directory.systemTemp.createTempSync('finish78');
    // A real 1×1 PNG, so Image.file has something to open.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    );
    photo1 = File('${dir.path}/one.png')..writeAsBytesSync(png);
    photo2 = File('${dir.path}/two.png')..writeAsBytesSync(png);
  });

  tearDown(() {
    Get.reset();
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpFinish(WidgetTester tester, ImagePicker picker) async {
    await tester.pumpWidget(GetMaterialApp(
      home: DispatchFinishJobPage(jobId: 7, picker: picker),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a saved draft plus the lost capture restore the whole form',
      (tester) async {
    await DispatchFinishDraft(
      jobId: 7,
      photoPaths: [photo1.path],
      meter: 'MTR-001',
      notes: 'Pole replaced',
    ).save();

    await pumpFinish(
      tester,
      _FakePicker(lost: LostDataResponse(files: [XFile(photo2.path)])),
    );

    expect(find.text('2/5 photos'), findsOneWidget);
    expect(find.text('MTR-001'), findsOneWidget);
    expect(find.text('Pole replaced'), findsOneWidget);
    expect(Get.find<DispatchNoticeController>().current.value?.message,
        'Your photos and notes were restored.');
    await tester.pump(const Duration(seconds: 5)); // the notice auto-dismisses
  });

  testWidgets('Camera saves the draft first; leaving the page clears it',
      (tester) async {
    await pumpFinish(tester, _FakePicker(picked: XFile(photo1.path)));
    await tester.enterText(find.byType(TextField).first, 'MTR-002');
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    final draft = await DispatchFinishDraft.load();
    expect(draft?.jobId, 7);
    expect(draft?.meter, 'MTR-002');
    expect(draft?.photoPaths, [photo1.path]);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await DispatchFinishDraft.load(), isNull);
  });

  testWidgets('the map reopens the Finish page when a draft is waiting',
      (tester) async {
    final jobs = Get.put<DispatchJobsController>(_FakeJobsController());
    jobs.lastFetchedAt.value = DateTime.now();
    await DispatchFinishDraft(jobId: 7, photoPaths: [photo1.path]).save();

    await tester.pumpWidget(const GetMaterialApp(home: DispatchJobsPage()));
    await tester.pumpAndSettle();

    final page = tester.widget<DispatchFinishJobPage>(
        find.byType(DispatchFinishJobPage));
    expect(page.jobId, 7);
    expect(find.text('1/5 photos'), findsOneWidget);

    // Unmount the map so its tile timers don't count as pending.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
