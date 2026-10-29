import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/constants/variables.dart';
import 'package:fms/core/network/http_error_handler.dart';
import 'package:fms/core/services/session_service.dart';
import 'package:fms/core/storage/secure_storage.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import 'package:fms/page/auth/presentation/login_chooser_page.dart';
import 'package:fms/page/dispatch/service/dispatch_notice_service.dart';
import 'package:fms/page/profile/controller/profile_controller.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Records logout calls instead of clearing anything.
class _FakeAuth extends AuthController {
  final notices = <String?>[];

  @override
  Future<void> checkSession() async {}

  @override
  Future<void> logout({String? notice}) async => notices.add(notice);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(Get.reset);

  testWidgets('2W logout drops the API key and lands on the chooser alone', (
    tester,
  ) async {
    await SecureStorage().write(Variables.prefApiKey, 'old-key');
    final notice = Get.put(DispatchNoticeController());
    final auth = Get.put(AuthController());

    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    Get.to(() => const Scaffold(body: Text('profile')));
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => auth.logout(notice: HttpErrorHandler.sessionExpiredNotice),
    );
    await tester.pumpAndSettle();

    final chooser = find.byType(LoginChooserPage);
    expect(chooser, findsOneWidget);
    expect(Navigator.of(tester.element(chooser)).canPop(), isFalse);
    expect(notice.current.value?.message, HttpErrorHandler.sessionExpiredNotice);

    // "Kill + reopen": a fresh session check finds no key.
    expect(await SecureStorage().read(Variables.prefApiKey), isNull);
    final reopened = AuthController();
    await reopened.checkSession();
    expect(reopened.isAuthenticated.value, isFalse);

    notice.dismiss();
  });

  testWidgets('Profile logout goes through AuthController.logout', (
    tester,
  ) async {
    final auth = Get.put<AuthController>(_FakeAuth()) as _FakeAuth;
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));

    await ProfileController().logout(context: context, mounted: true);

    expect(auth.notices, [null]);
  });

  test('401 and session-expired responses log out with a notice', () async {
    final auth = Get.put<AuthController>(_FakeAuth()) as _FakeAuth;

    HttpErrorHandler.handleResponse(401, '');
    final prefs = await SharedPreferences.getInstance();
    final handled = await SessionService.handleUnauthorizedResponse(
      prefs,
      http.Response('{"Status":401,"Message":"Unauthorized"}', 200),
    );

    expect(handled, isTrue);
    expect(auth.notices, [
      HttpErrorHandler.sessionExpiredNotice,
      HttpErrorHandler.sessionExpiredNotice,
    ]);
  });
}
