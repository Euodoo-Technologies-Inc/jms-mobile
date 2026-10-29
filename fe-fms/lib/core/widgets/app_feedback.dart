import 'package:get/get.dart';

import '../../page/dispatch/service/dispatch_notice_service.dart';

/// The app's one transient-feedback channel, 2W and 4W alike.
///
/// Every success / error / info message goes through here and shows as the
/// app-wide top banner ([DispatchNoticeHost]) — never a SnackBar or
/// `Get.snackbar`. It needs no [BuildContext], so controllers and services
/// call it directly, and the banner floats above open dialogs and sheets.
abstract final class AppFeedback {
  static void success(String message) => _notices?.success(message);
  static void error(String message) => _notices?.error(message);
  static void info(String message) => _notices?.info(message);

  // Registered permanently in main(); absent only in isolated widget tests.
  static DispatchNoticeController? get _notices =>
      Get.isRegistered<DispatchNoticeController>()
          ? Get.find<DispatchNoticeController>()
          : null;
}
