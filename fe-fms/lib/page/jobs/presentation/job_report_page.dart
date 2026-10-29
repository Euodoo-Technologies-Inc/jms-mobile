import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fms/core/utils/timezone_util.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/core/widgets/detail_widgets.dart';
import 'package:fms/data/models/response/get_job_history__response_model.dart';

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

    void shareReport() {
      final buffer = StringBuffer()
        ..writeln('Job Report')
        ..writeln('Job: ${job.jobName ?? 'N/A'}')
        ..writeln('Status: Completed')
        ..writeln('Type: ${_getJobTypeString(job.typeJob)}')
        ..writeln('Customer: ${job.customerName ?? 'N/A'}')
        ..writeln('Phone: ${job.phoneNumber ?? 'N/A'}')
        ..writeln('Address: ${job.address ?? 'N/A'}');

      if (job.createdAt != null) {
        buffer.writeln('Created: ${_formatDate(job.createdAt)}');
      }
      if (job.assignWhen != null) {
        buffer.writeln('Assigned: ${_formatDate(job.assignWhen)}');
      }
      if (job.jobDate != null) {
        buffer.writeln('Completed: ${_formatDate(job.jobDate)}');
      }

      Share.share(
        buffer.toString().trim(),
        subject: job.jobName ?? 'Job Report',
      );
    }

    return DetailScaffold(
      title: 'Job Report',
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
            pill: const DetailStatusPill(
              label: 'Completed',
              color: DispatchColors.brand,
              icon: Icons.verified_outlined,
            ),
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
                DetailKvRow(label: 'Completed at', value: _formatDate(job.jobDate)),
              ],
            ),
          ),

          const SizedBox(height: 22),
          const DetailSectionLabel('Customer & Contact'),
          DetailCard(
            child: Column(
              children: [
                DetailKvRow(label: 'Customer', value: job.customerName),
                DetailKvRow(label: 'Phone', value: job.phoneNumber),
                DetailKvRow(label: 'Address', value: job.address),
              ],
            ),
          ),

          const SizedBox(height: 22),
          const DetailSectionLabel('Completion Notes'),
          DetailCard(
            child: Text(
              'Job completed successfully. All electrical connections have been '
              'restored and tested. Ensure follow-up inspection is scheduled '
              'within 7 days.',
              style: TextStyle(
                color: palette.ink,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
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
                  label: const Text('Share Report'),
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
        return 'Line Interruption';
      case 2:
        return 'Reconnection';
      case 3:
        return 'Short Circuit';
      case 4:
        return 'Disconnection';
      default:
        return 'Other';
    }
  }

  String _formatDate(dynamic value) {
    final dateTime = _parseDate(value);
    if (dateTime == null) return 'N/A';
    return DateFormat('EEE, dd MMM yyyy').format(ManilaTimezone.convert(dateTime));
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
