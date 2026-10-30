import 'package:flutter/material.dart';

import '../../../core/theme/dispatch_palette.dart';
import '../../../core/widgets/detail_widgets.dart';
import 'job_summary_card.dart';

/// The one 2W job status vocabulary: the jobs list badges and the detail-page
/// pills both read their label, icon and colour from here.
enum JobStatus {
  open('Open', Icons.outlined_flag),
  inProgress('In progress', Icons.timelapse),
  rescheduled('Rescheduled', Icons.event_repeat),
  completed('Completed', Icons.verified_outlined);

  const JobStatus(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Green comes from the scheme and amber from the palette, so both lighten
  /// to stay legible on dark surfaces.
  Color color(BuildContext context) => switch (this) {
    open || completed => Theme.of(context).colorScheme.primary,
    inProgress || rescheduled => context.dispatch.warning,
  };

  /// The status badge on a jobs-list card. [label] overrides the text, e.g.
  /// to append the rescheduled date.
  JobCardBadge badge(BuildContext context, {String? label}) {
    final c = color(context);
    return JobCardBadge(
      label: label ?? this.label,
      icon: icon,
      backgroundColor: c.withValues(alpha: 0.14),
      foregroundColor: c,
      borderColor: c.withValues(alpha: 0.28),
    );
  }

  /// The status pill on the job detail pages.
  DetailStatusPill pill(BuildContext context) =>
      DetailStatusPill(label: label, color: color(context), icon: icon);
}
