import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fms/core/utils/timezone_util.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/core/widgets/detail_widgets.dart';
import 'package:fms/data/models/response/get_job_history__response_model.dart';
import 'package:fms/page/jobs/widget/job_status.dart';

/// A page displaying a summary report of a completed job.
///
/// Shares the dispatch detail design language (flat surface, neutral cards,
/// brand-green accents) so it matches the newer side of the app and respects
/// dark mode.
class JobReportPage extends StatelessWidget {
  final Data job;
  const JobReportPage({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final notes = job.notes?.trim() ?? '';

    void shareReport() {
      final buffer = StringBuffer()
        ..writeln('Job report')
        ..writeln('Job: ${job.jobName ?? '—'}')
        ..writeln('Status: Completed')
        ..writeln('Type: ${_getJobTypeString(job.typeJob)}')
        ..writeln('Customer: ${job.customerName ?? '—'}')
        ..writeln('Phone: ${job.phoneNumber ?? '—'}')
        ..writeln('Address: ${job.address ?? '—'}');

      if (job.createdAt != null) {
        buffer.writeln('Created: ${_formatDate(job.createdAt)}');
      }
      if (job.assignWhen != null) {
        buffer.writeln('Assigned: ${_formatDate(job.assignWhen)}');
      }
      if (job.finishWhen != null) {
        buffer.writeln('Completed: ${_formatDateTime(job.finishWhen)}');
      }
      if (notes.isNotEmpty) {
        buffer.writeln('Notes: $notes');
      }

      Share.share(
        buffer.toString().trim(),
        subject: job.jobName ?? 'Job report',
      );
    }

    return DetailScaffold(
      title: 'Job report',
      actions: [
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.share_outlined),
          onPressed: shareReport,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          DetailHeader(
            title: job.jobName ?? 'Job',
            pill: JobStatus.completed.pill(context),
          ),
          const SizedBox(height: 22),

          const DetailSectionLabel('Overview'),
          DetailCard(
            child: Column(
              children: [
                DetailKvRow(
                  label: 'Job type',
                  value: _getJobTypeString(job.typeJob),
                ),
                DetailKvRow(
                  label: 'Created by',
                  value: job.createdBy?.toString(),
                ),
                DetailKvRow(label: 'Created at', value: _formatDate(job.createdAt)),
                DetailKvRow(label: 'Assigned at', value: _formatDate(job.assignWhen)),
                DetailKvRow(
                  label: 'Completed at',
                  value: _formatDateTime(job.finishWhen),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),
          const DetailSectionLabel('Customer & contact'),
          DetailCard(
            child: Column(
              children: [
                DetailKvRow(label: 'Customer', value: job.customerName),
                DetailKvRow(label: 'Phone', value: job.phoneNumber),
                DetailKvRow(label: 'Address', value: job.address),
              ],
            ),
          ),

          // The crew's own notes from Finish; no section when they left none.
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 22),
            const DetailSectionLabel('Completion notes'),
            DetailCard(
              child: Text(
                notes,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: palette.cardBorder),
                    foregroundColor: palette.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: shareReport,
                  icon: const Icon(Icons.share),
                  label: const Text('Share report'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    backgroundColor: DispatchColors.brand,
                    foregroundColor: DispatchColors.onBrand,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getJobTypeString(int? type) {
    switch (type) {
      case 1:
        return 'Line interruption';
      case 2:
        return 'Reconnection';
      case 3:
        return 'Short circuit';
      case 4:
        return 'Disconnection';
      default:
        return 'Other';
    }
  }

  String? _formatDate(dynamic value) {
    final dateTime = _parseDate(value);
    if (dateTime == null) return null;
    return DateFormat('EEE, dd MMM yyyy').format(ManilaTimezone.convert(dateTime));
  }

  String? _formatDateTime(dynamic value) {
    final dateTime = _parseDate(value);
    if (dateTime == null) return null;
    return DateFormat('dd MMM yyyy · h:mm a')
        .format(ManilaTimezone.convert(dateTime));
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }
}
