import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/dispatch_palette.dart';

/// Severity of a [DispatchNotice].
enum DispatchNoticeKind { success, error, info }

/// A transient message shown in the app-wide top banner.
class DispatchNotice {
  const DispatchNotice({
    required this.id,
    required this.message,
    required this.kind,
  });

  /// Monotonic id — keys the banner so each new notice re-animates.
  final int id;
  final String message;
  final DispatchNoticeKind kind;
}

/// App-wide transient-notice controller.
///
/// Any dispatch screen calls [show] / [success] / [error] / [info];
/// [DispatchNoticeHost] (mounted once via `GetMaterialApp.builder`) renders
/// the banner over whatever screen is showing. Legacy screens simply never
/// call it, so the banner never appears there.
class DispatchNoticeController extends GetxController {
  /// The notice currently on screen, or `null`.
  final Rxn<DispatchNotice> current = Rxn<DispatchNotice>();

  /// Extra top padding (logical px) the banner should clear, in addition to
  /// the system status bar handled by [SafeArea]. A screen that has its own
  /// floating top bar (e.g. the dispatch jobs page) sets this to the bar's
  /// height + gap so the banner floats *under* it rather than on top. Other
  /// screens leave it at 0.
  final RxDouble topInsetExtra = 0.0.obs;

  Timer? _timer;
  int _seq = 0;

  /// Shows [message]; auto-dismisses after a few seconds. A newer notice
  /// replaces the current one and restarts the timer.
  void show(String message, DispatchNoticeKind kind) {
    _timer?.cancel();
    final id = ++_seq;
    current.value = DispatchNotice(id: id, message: message, kind: kind);
    _timer = Timer(const Duration(seconds: 4), () {
      if (current.value?.id == id) current.value = null;
    });
  }

  void success(String message) => show(message, DispatchNoticeKind.success);
  void error(String message) => show(message, DispatchNoticeKind.error);
  void info(String message) => show(message, DispatchNoticeKind.info);

  void dismiss() {
    _timer?.cancel();
    current.value = null;
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}

/// Wraps the whole app (via `GetMaterialApp.builder`) and floats the notice
/// banner at the top of whatever screen is showing.
class DispatchNoticeHost extends StatelessWidget {
  const DispatchNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DispatchNoticeController>();
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Obx(() {
              final extraTop = ctrl.topInsetExtra.value;
              final notice = ctrl.current.value;
              return Padding(
                padding: EdgeInsets.fromLTRB(12, 8 + extraTop, 12, 0),
                child: _animatedBanner(notice, ctrl.dismiss),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _animatedBanner(DispatchNotice? notice, VoidCallback onDismiss) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 220),
      // Soft, slightly springy entrance — the card eases down + scales up,
      // a gentler motion than the prior slide-and-clip.
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final slide = Tween<Offset>(
          begin: const Offset(0, -0.35),
          end: Offset.zero,
        ).animate(anim);
        final scale = Tween<double>(begin: 0.96, end: 1.0).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: notice == null
          ? const SizedBox.shrink()
          : _NoticeBanner(
              key: ValueKey(notice.id),
              notice: notice,
              onDismiss: onDismiss,
            ),
    );
  }
}

/// The notice banner — a themed card with a kind-coloured icon. Swipe up or
/// tap the close icon to dismiss; the host animates it out upward.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    super.key,
    required this.notice,
    required this.onDismiss,
  });

  final DispatchNotice notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final (IconData icon, Color accent) = switch (notice.kind) {
      DispatchNoticeKind.success => (
          Icons.check_circle,
          DispatchColors.brand,
        ),
      DispatchNoticeKind.error => (
          Icons.error_outline,
          const Color(0xFFdc2626),
        ),
      DispatchNoticeKind.info => (
          Icons.info_outline,
          const Color(0xFFf59e0b),
        ),
    };
    // Material ancestor: the banner is mounted in GetMaterialApp.builder,
    // outside any Scaffold/Material, so without this its Text inherits
    // Flutter's fallback style (serif font + yellow underline). Material
    // supplies the theme's DefaultTextStyle so the banner font matches the
    // rest of the app. Transparency keeps the rounded card decoration ours.
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Swipe up to dismiss.
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < 0) onDismiss();
      },
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.cardBorder),
          // Rounded soft shadow — drawn by the container so it follows the
          // banner's rounded shape (Material(elevation:) was painting a
          // rectangular shadow that showed as grey at the corners).
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  notice.message,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Material/InkResponse for a proper ripple on the close icon —
              // the parent container has no ink surface of its own.
              Material(
                color: Colors.transparent,
                child: InkResponse(
                  onTap: onDismiss,
                  radius: 18,
                  child:
                      Icon(Icons.close, size: 18, color: palette.subtle),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
