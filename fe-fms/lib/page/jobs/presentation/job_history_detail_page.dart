import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:fms/core/utils/timezone_util.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/core/widgets/detail_widgets.dart';
import 'package:fms/data/models/response/get_job_history__response_model.dart';

import 'job_navigation_page.dart';
import 'job_report_page.dart';

/// A page displaying details of a completed job from history.
///
/// Mirrors the dispatch "Job detail" design (flat page surface, neutral cards,
/// brand-green accents) so it reads consistently with the newer side of the
/// app and renders correctly in dark mode.
class JobHistoryDetailPage extends StatelessWidget {
  final Data job;
  const JobHistoryDetailPage({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final latitude = job.latitude;
    final longitude = job.longitude;
    final photos =
        job.details?.where((d) => d.photoUrl != null).toList() ?? const [];

    return DetailScaffold(
      title: job.jobName ?? 'Job History Details',
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

          const DetailSectionLabel('Details'),
          DetailCard(
            child: Column(
              children: [
                DetailKvRow(label: 'Customer', value: job.customerName),
                if (job.phoneNumber != null && job.phoneNumber!.isNotEmpty)
                  DetailKvRow(label: 'Phone', value: job.phoneNumber),
                DetailKvRow(
                  label: 'Service type',
                  value: _getJobTypeString(job.typeJob),
                ),
                DetailKvRow(label: 'Address', value: job.address),
                if (job.jobDate != null)
                  DetailKvRow(label: 'Completed', value: _formatDate(job.jobDate)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _MapButton(
            enabled: latitude != null && longitude != null,
            onOpen: () {
              Get.to(
                () => JobNavigationPage(
                  latitude: latitude!,
                  longitude: longitude!,
                  jobName: job.jobName ?? 'Job Destination',
                  address: job.address,
                ),
              );
            },
          ),

          const SizedBox(height: 22),
          const DetailSectionLabel('Job Information'),
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
                if (job.createdAt != null)
                  DetailKvRow(label: 'Created at', value: _formatDate(job.createdAt)),
                if (job.assignWhen != null)
                  DetailKvRow(label: 'Assigned at', value: _formatDate(job.assignWhen)),
              ],
            ),
          ),

          const SizedBox(height: 22),
          const DetailSectionLabel('Timeline'),
          DetailCard(
            child: DetailTimeline(
              entries: [
                ('Created', _formatDateTime(job.createdAt)),
                ('Assigned', _formatDateTime(job.assignWhen)),
                ('Completed', _formatDateTime(job.jobDate)),
              ],
            ),
          ),

          if (photos.isNotEmpty) ...[
            const SizedBox(height: 22),
            DetailSectionLabel('Photos (${photos.length})'),
            DetailCard(
              // Full-width 16:10 tiles stacked vertically — mirrors the
              // dispatch history detail's proof-of-delivery display.
              child: Column(
                children: [
                  for (var i = 0; i < photos.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 16 / 10,
                        child: Image.network(
                          photos[i].photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: palette.cardBorder,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 36,
                              color: palette.subtle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Get.to(() => JobReportPage(job: job));
              },
              icon: const Icon(Icons.description_outlined),
              label: const Text('View Report'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: const BorderSide(color: DispatchColors.brand),
                foregroundColor: DispatchColors.brand,
                overlayColor: DispatchColors.brand.withValues(alpha: 0.08),
              ),
            ),
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

  /// Date + time for the timeline rows; returns null on missing/invalid input
  /// so [DetailTimeline] can skip the entry.
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

/// "Open in Map" button styled to match the dispatch surface. Disabled state
/// shows a snackbar explaining coordinates are unavailable.
class _MapButton extends StatelessWidget {
  const _MapButton({required this.enabled, required this.onOpen});

  final bool enabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: enabled
            ? onOpen
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coordinates not available')),
                );
              },
        icon: const Icon(Icons.map_outlined),
        label: const Text('Open in Map'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: context.dispatch.cardBorder),
          foregroundColor: enabled
              ? DispatchColors.brand
              : context.dispatch.subtle,
        ),
      ),
    );
  }
}
