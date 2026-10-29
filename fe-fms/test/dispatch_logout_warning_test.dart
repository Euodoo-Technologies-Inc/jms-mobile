import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/theme/theme_controller.dart';
import 'package:fms/page/dispatch/controller/dispatch_auth_controller.dart';
import 'package:fms/page/dispatch/presentation/dispatch_profile_page.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends DispatchAuthController {
  @override
  Future<void> checkSession() async => isAuthenticated.value = true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(Get.reset);

  Future<void> openLogout(WidgetTester tester) async {
    Get.put<DispatchAuthController>(_SignedIn());
    Get.put(ThemeController());
    await tester.pumpWidget(const GetMaterialApp(home: DispatchProfilePage()));
    await tester.scrollUntilVisible(find.text('Log out'), 200);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
  }

  testWidgets('4W logout warns when job updates are not synced', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'dispatch.queue.entries':
          '[{"id":"1-1","type":"start","enqueuedAt":"2026-10-29T13:05:07.000","jobId":7},'
          '{"id":"1-2","type":"fcm","enqueuedAt":"2026-10-29T13:05:08.000","fcmToken":"t"}]',
    });
    await openLogout(tester);
    expect(find.textContaining('1 job update not synced yet'), findsOneWidget);
  });

  testWidgets('4W logout keeps the plain message with an empty queue', (
    tester,
  ) async {
    await openLogout(tester);
    expect(
      find.text('You will need to sign in again to receive jobs.'),
      findsOneWidget,
    );
  });
}
