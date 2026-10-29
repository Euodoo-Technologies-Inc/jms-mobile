import 'package:flutter/material.dart';

import '../theme/dispatch_palette.dart';

/// ===========================================================================
/// Shared detail-screen building blocks for the legacy jobs surface.
///
/// These mirror the dispatch "Job detail" page (see
/// `dispatch_job_history_page.dart`) so the legacy job-detail, history-detail,
/// and report pages read from the same flat, theme-aware design language.
/// Everything draws its colours from [DispatchPalette] (`context.dispatch`) and
/// the green [DispatchColors.brand] accent, which means dark mode is handled
/// automatically — no hardcoded white surfaces.
/// ===========================================================================

/// A theme-aware [Scaffold] + [AppBar] matching the dispatch detail pages:
/// flat page surface, hairline bottom border, ink-coloured title.
class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottomNavigationBar,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Scaffold(
      backgroundColor: palette.pageSurface,
      appBar: AppBar(
        backgroundColor: palette.pageSurface,
        surfaceTintColor: palette.pageSurface,
        foregroundColor: palette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: palette.cardBorder)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: actions,
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// Large job-name heading with a trailing [DetailStatusPill].
class DetailHeader extends StatelessWidget {
  const DetailHeader({super.key, required this.title, this.pill});

  final String title;
  final Widget? pill;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: palette.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
        if (pill != null) ...[const SizedBox(width: 12), pill!],
      ],
    );
  }
}

/// Small all-caps section heading (e.g. "DETAILS", "TIMELINE").
class DetailSectionLabel extends StatelessWidget {
  const DetailSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.dispatch.subtle,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A bordered, theme-aware content card.
class DetailCard extends StatelessWidget {
  const DetailCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.cardBorder),
      ),
      child: child,
    );
  }
}

/// A label/value row inside a [DetailCard]. Renders an em dash for empty values.
class DetailKvRow extends StatelessWidget {
  const DetailKvRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
    this.trailingIcon,
  });

  final String label;
  final String? value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final shown = (value == null || value!.isEmpty) ? '—' : value!;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(color: palette.subtle, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              shown,
              style: TextStyle(
                color: valueColor ?? palette.ink,
                fontSize: 13.5,
                fontWeight:
                    onTap != null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (trailingIcon != null)
            Icon(trailingIcon, size: 18, color: valueColor ?? palette.subtle),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

/// A rounded status pill — coloured background/border with matching text.
class DetailStatusPill extends StatelessWidget {
  const DetailStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical timeline of (label, timestamp) entries with brand-green dots.
/// Pass already-formatted timestamp strings; empty entries are skipped.
class DetailTimeline extends StatelessWidget {
  const DetailTimeline({super.key, required this.entries});

  /// (label, formattedValue) pairs. Null/empty values are filtered out.
  final List<(String, String?)> entries;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final shown =
        entries.where((e) => e.$2 != null && e.$2!.isNotEmpty).toList();
    if (shown.isEmpty) {
      return Text(
        'No timeline data available.',
        style: TextStyle(color: palette.subtle, fontSize: 13),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == shown.length - 1 ? 0 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: DispatchColors.brand,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shown[i].$1,
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shown[i].$2!,
                        style: TextStyle(color: palette.subtle, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// An inline notice card (info / warning) used for reschedule states. Tinted
/// by [color] but theme-aware in its text via the palette.
class DetailNoticeCard extends StatelessWidget {
  const DetailNoticeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
    this.footnote,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: palette.ink, fontSize: 13, height: 1.45),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 6),
            Text(
              footnote!,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
