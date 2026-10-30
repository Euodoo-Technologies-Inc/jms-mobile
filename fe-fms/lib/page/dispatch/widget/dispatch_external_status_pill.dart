import 'package:flutter/material.dart';
import '../../../core/theme/dispatch_palette.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';

/// ORMECO's flag on a job ("Has problem", "On hold", "Transferred"): the same
/// rounded [DetailStatusPill] as our own status beside it, in the palette's
/// warning amber with a warning triangle, so it reads as a second status
/// rather than a different kind of badge. Renders nothing for our own jobs /
/// older backends.
class DispatchExternalStatusPill extends StatelessWidget {
  const DispatchExternalStatusPill({super.key, required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    final label = job.externalStatusLabel;
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      // The label may be cut short on the card; the tooltip has all of it.
      message: 'ORMECO status: $label',
      child: DetailStatusPill(
        label: label,
        color: context.dispatch.warning,
        icon: Icons.warning_amber_rounded,
      ),
    );
  }
}
