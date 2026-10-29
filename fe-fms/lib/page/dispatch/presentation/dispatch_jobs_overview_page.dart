import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/dispatch_palette.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../controller/dispatch_jobs_controller.dart';
import '../service/dispatch_notice_service.dart';
import '../widget/dispatch_job_status.dart';

/// A plain, flat list of today's jobs — a quick read-through of the day.
/// Tapping a job focuses it on the map and returns.
class DispatchJobsOverviewPage extends StatelessWidget {
  const DispatchJobsOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DispatchJobsController>();
    final palette = context.dispatch;
    return DetailScaffold(
      title: 'Job list',
      body: Obx(() {
        // First load only — a poll on a zero-job day refreshes in place.
        if (ctrl.isLoading.value &&
            ctrl.jobs.isEmpty &&
            ctrl.lastFetchedAt.value == null) {
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
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: palette.subtle,
              ),
            ),
          );
        }
        return RefreshIndicator(
          color: DispatchColors.brand,
          onRefresh: ctrl.refreshToday,
          child: ListView.separated(
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
                  // The map only shows unfinished, geocoded jobs — say why
                  // instead of silently staying put.
                  final notices = Get.find<DispatchNoticeController>();
                  if (job.isFinished) {
                    notices.info('This job is already finished.');
                  } else if (!ctrl.selectJob(job)) {
                    notices.info('This job has no coordinates yet.');
                  } else {
                    Get.back();
                  }
                },
              );
            },
          ),
        );
      }),
    );
  }
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
    final address = job.address;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'STOP $stopNumber',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                DispatchJobStatus.of(job).pill(context),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              job.customer ?? job.jobName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                height: 1.25,
              ),
            ),
            if (address != null && address.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                address,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
