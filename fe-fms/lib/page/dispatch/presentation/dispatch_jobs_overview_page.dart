import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/dispatch_palette.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../controller/dispatch_jobs_controller.dart';

/// A plain, flat list of today's jobs — a quick read-through of the day.
/// Tapping a job focuses it on the map and returns.
class DispatchJobsOverviewPage extends StatelessWidget {
  const DispatchJobsOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DispatchJobsController>();
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
        title: const Text(
          'Overview',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: Obx(() {
        if (ctrl.isLoading.value && ctrl.jobs.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: DispatchColors.brand),
          );
        }
        // Route order first, then anything unordered.
        final jobs = ctrl.jobs.toList()
          ..sort((a, b) => (a.routeOrder ?? 1 << 30)
              .compareTo(b.routeOrder ?? 1 << 30));
        if (jobs.isEmpty) {
          return Center(
            child: Text(
              'No jobs for today.',
              style: TextStyle(color: palette.subtle, fontSize: 15),
            ),
          );
        }
        return RefreshIndicator(
          color: DispatchColors.brand,
          onRefresh: ctrl.refreshToday,
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: jobs.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              thickness: 1,
              color: palette.divider,
              indent: 20,
              endIndent: 20,
            ),
            itemBuilder: (context, i) {
              final job = jobs[i];
              return _OverviewJobRow(
                job: job,
                stopNumber: job.routeOrder ?? (i + 1),
                onTap: () {
                  ctrl.selectJob(job);
                  Get.back();
                },
              );
            },
          ),
        );
      }),
    );
  }
}

/// Per-status accent-bar colour + label. The label text itself stays neutral
/// (theme `subtle`) — the coloured bar carries the status, so it reads on
/// both light and dark surfaces.
({Color accent, String label}) _statusOf(DispatchJob job) {
  if (job.isFinished) {
    return (accent: DispatchColors.brand, label: 'Finished');
  }
  if (job.isOnTheWay) {
    return (accent: DispatchColors.accent, label: 'On the way');
  }
  if (job.isReschedulePending) {
    return (accent: DispatchColors.warning, label: 'Reschedule');
  }
  return (accent: const Color(0xFF9aa4b2), label: 'Not started');
}

class _OverviewJobRow extends StatelessWidget {
  const _OverviewJobRow({
    required this.job,
    required this.stopNumber,
    required this.onTap,
  });

  final DispatchJob job;
  final int stopNumber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final status = _statusOf(job);
    final address = job.address;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            // Slim status accent down the left edge of the row.
            Container(
              width: 4,
              height: 42,
              decoration: BoxDecoration(
                color: status.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'STOP $stopNumber',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        status.label,
                        style: TextStyle(
                          color: palette.subtle,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.customer ?? job.jobName,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  if (address != null && address.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      address,
                      style: TextStyle(
                        color: palette.subtle,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
