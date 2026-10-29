import 'package:flutter/material.dart';

import '../theme/dispatch_palette.dart';

/// ===========================================================================
/// Theme-aware modal building blocks for the legacy jobs surface.
///
/// These mirror the flat, palette-driven language of the detail pages (see
/// `detail_widgets.dart`): a neutral [DispatchPalette.card] surface, a tinted
/// circular icon badge whose [accent] colour signals intent, an ink title with
/// a subtle supporting line, and a row of consistent action buttons. Dark mode
/// is handled automatically because every colour is read from the palette.
///
/// Intent is communicated through [accent]:
///   • red   ([ColorScheme.error]) → destructive (cancel a job)
///   • amber ([DispatchColors.warning]) → reschedule
///   • green ([DispatchColors.brand]) → proceed / finish
/// ===========================================================================
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    this.message,
    this.content,
    required this.actions,
  });

  /// Glyph shown in the tinted badge — reinforces the dialog's purpose.
  final IconData icon;

  /// Intent colour for the badge, used at low alpha for the badge fill.
  final Color accent;

  /// Bold, centred heading.
  final String title;

  /// Optional supporting line under the title.
  final String? message;

  /// Optional body (text fields, chips, image grids…) between the message and
  /// the action row.
  final Widget? content;

  /// Action buttons, laid out as an even row. Use [AppDialogButton].
  final List<Widget> actions;

  /// Blocking progress overlay for a request in flight. Not dismissible by tap
  /// or back; close it with `Navigator.of(context, rootNavigator: true).pop()`.
  static void showLoading(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Dialog(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 26),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(height: 1.3),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: 20),
                content!,
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single [AppDialog] action button.
///
/// [filled] draws a solid [color] background (default brand green); otherwise it
/// renders as an outline whose border and label take [color] (default a neutral
/// palette border with ink text). Both share the dialog's 14px corner radius.
class AppDialogButton extends StatelessWidget {
  const AppDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.filled = false,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool filled;
  final IconData? icon;

  /// Shows a spinner in place of the label (pair with `onPressed: null`).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const padding = EdgeInsets.symmetric(vertical: 14);
    // Buttons recolour textStyle with their foreground colour.
    final textStyle = Theme.of(context).textTheme.titleMedium;
    final Widget text = busy
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled ? Colors.white : palette.ink,
              semanticsLabel: label,
            ),
          )
        : Text(label);

    if (filled) {
      final bg = color ?? DispatchColors.brand;
      final style = FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        // Busy keeps the fill so the white spinner stays visible.
        disabledBackgroundColor: busy ? bg : null,
        padding: padding,
        shape: shape,
        textStyle: textStyle,
        elevation: 0,
      );
      return icon == null
          ? FilledButton(onPressed: onPressed, style: style, child: text)
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 18),
              label: text,
            );
    }

    final fg = color ?? palette.ink;
    final style = OutlinedButton.styleFrom(
      foregroundColor: fg,
      side: BorderSide(
        color: color?.withValues(alpha: 0.5) ?? palette.cardBorder,
      ),
      padding: padding,
      shape: shape,
      textStyle: textStyle,
      overlayColor: fg.withValues(alpha: 0.08),
    );
    return icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: text)
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: text,
          );
  }
}
