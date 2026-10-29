import 'package:flutter/material.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';

/// ORMECO's flag on a job ("Has problem", "On hold"), styled like the board's
/// `.ui-flag`: amber outline + warning triangle. White fill (the board has
/// none) so it reads on the green job cards and apart from our amber-filled
/// "On the way". Renders nothing for our own jobs / older backends.
class DispatchExternalStatusPill extends StatelessWidget {
  const DispatchExternalStatusPill({super.key, required this.job});
  final DispatchJob job;

  static const _border = Color(0xFFf59e0b);
  static const _fg = Color(0xFF92400e);

  @override
  Widget build(BuildContext context) {
    final label = job.externalStatusLabel;
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      // The label may be cut short on the card; the tooltip has all of it.
      message: 'ORMECO status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 13, color: _fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _fg,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
