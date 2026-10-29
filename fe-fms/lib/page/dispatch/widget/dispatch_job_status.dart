import 'package:flutter/material.dart';

import '../../../core/theme/dispatch_palette.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';

/// The one 4W job status vocabulary: the map cards, the job list and the
/// history detail all read their pill's label and colour from here.
enum DispatchJobStatus {
  notStarted('Not started'),
  onTheWay('On the way'),
  reschedule('Reschedule'),
  finished('Finished');

  const DispatchJobStatus(this.label);

  final String label;

  static DispatchJobStatus of(DispatchJob job) => job.isFinished
      ? finished
      : job.isOnTheWay
      ? onTheWay
      : job.isReschedulePending
      ? reschedule
      : notStarted;

  /// Palette tokens with their dark-mode variants: the scheme's green
  /// lightens on dark surfaces, and so does the palette's amber.
  Color color(BuildContext context) => switch (this) {
    finished => Theme.of(context).colorScheme.primary,
    onTheWay || reschedule => context.dispatch.warning,
    notStarted => context.dispatch.subtle,
  };

  DetailStatusPill pill(BuildContext context) =>
      DetailStatusPill(label: label, color: color(context));
}
