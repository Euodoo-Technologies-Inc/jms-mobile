import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:fms/core/utils/timezone_util.dart';
import 'package:fms/page/jobs/controller/jobs_controller.dart';
import 'package:fms/page/jobs/presentation/job_details_page.dart';
import 'package:fms/data/models/response/get_job_history__response_model.dart'
    as history;
import 'package:fms/core/widgets/skeleton_loading.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import '../widget/job_summary_card.dart';
import '../widget/history_filter_bar.dart';
import 'job_history_detail_page.dart';

/// Displays a tabbed list of jobs for the driver, including all, ongoing,
/// and history jobs. Each tab uses reactive data from [JobsController].
class JobsPage extends StatelessWidget {
  const JobsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(JobsController());
    final palette = context.dispatch;

    return Scaffold(
      backgroundColor: palette.pageSurface,
      appBar: AppBar(
        backgroundColor: palette.pageSurface,
        surfaceTintColor: palette.pageSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        // No title here — the outer app bar carries it. Collapse the toolbar so
        // the tabs sit directly under the main top bar instead of leaving a gap.
        toolbarHeight: 0,
        bottom: TabBar(
          controller: controller.tabController,
          labelColor: palette.ink,
          unselectedLabelColor: palette.subtle,
          indicatorColor: DispatchColors.brand,
          indicatorWeight: 3,
          dividerColor: palette.cardBorder,
          // Drop the blue ripple/splash flash when a tab is tapped.
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: const [
            Tab(text: 'All Job'),
            Tab(text: 'Ongoing'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: controller.tabController,
        children: [
          _getAllJob(controller, context),
          _getOngoingJob(controller, context),
          _getHistoryJob(controller, context),
        ],
      ),
    );
  }

  /// Shows a centered text message inside a [RefreshIndicator] so that
  /// users can pull to refresh when a list is empty or an error occurs.
  Widget _buildRefreshableMessage(JobsController controller, String message) {
    return RefreshIndicator(
      onRefresh: controller.refresh,
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: Center(child: Text(message)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Builds the list of all available jobs.
  ///
  /// Only jobs with a job date that is today or earlier are shown.
  Widget _getAllJob(JobsController controller, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    return Obx(() {
      if (controller.isLoadingAllJobs.value) {
        return ShimmerProvider(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: const [
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
            ],
          ),
        );
      }
      if (controller.errorAllJobs.value != null) {
        return _buildRefreshableMessage(
          controller,
          'Error: ${controller.errorAllJobs.value}',
        );
      }
      if (controller.allJobsResponse.value?.data == null ||
          controller.allJobsResponse.value!.data!.isEmpty) {
        return _buildRefreshableMessage(controller, 'No jobs found');
      }

      final allJobs = controller.allJobsResponse.value!.data!;
      final now = ManilaTimezone.now();
      final today = DateTime(now.year, now.month, now.day);

      final visibleJobs = allJobs.where((job) {
        final jobDate = job.jobDate;
        if (jobDate == null) return true;
        final jobOnlyDate = DateTime(jobDate.year, jobDate.month, jobDate.day);
        return !jobOnlyDate.isAfter(today);
      }).toList();

      if (visibleJobs.isEmpty) {
        return _buildRefreshableMessage(controller, 'No jobs found');
      }

      return RefreshIndicator(
        onRefresh: controller.refresh,
        triggerMode: RefreshIndicatorTriggerMode.anywhere,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: visibleJobs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final job = visibleJobs[index];
            return JobSummaryCard(
              title: job.jobName ?? 'Untitled Job',
              customerName: job.customerName,
              address: job.address,
              dateLabel: job.jobDate != null ? _formatDate(job.jobDate) : null,
              badges: [
                _buildJobTypeBadge(context, job.typeJob),
                _buildStatusBadge(
                  label: 'Open',
                  color: accent,
                  icon: Icons.outlined_flag,
                ),
              ],
              accentColor: accent,
              onTap: () => _openJobDetails(job),
              onDetails: () => _openJobDetails(job),
              detailsLabel: 'Details',
            );
          },
        ),
      );
    });
  }

  /// Builds the list of ongoing jobs that are currently being processed
  /// by the driver, including rescheduled jobs.
  Widget _getOngoingJob(JobsController controller, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    return Obx(() {
      if (controller.isLoadingOngoingJobs.value) {
        return ShimmerProvider(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: const [
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
            ],
          ),
        );
      }
      if (controller.errorOngoingJobs.value != null) {
        return _buildRefreshableMessage(
          controller,
          'Error: ${controller.errorOngoingJobs.value}',
        );
      }
      if (controller.ongoingJobsResponse.value?.data == null ||
          controller.ongoingJobsResponse.value!.data!.isEmpty) {
        return _buildRefreshableMessage(controller, 'No ongoing jobs found');
      }

      return RefreshIndicator(
        onRefresh: controller.refresh,
        triggerMode: RefreshIndicatorTriggerMode.anywhere,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: controller.ongoingJobsResponse.value!.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final job = controller.ongoingJobsResponse.value!.data![index];
            final jobId = job.jobId;
            final status = job.status;
            final isRescheduledStatus = status == 3;
            final rescheduledDate = jobId != null
                ? controller.rescheduledJobs[jobId]
                : null;
            final hasRescheduled =
                rescheduledDate != null || isRescheduledStatus;
            return JobSummaryCard(
              title: job.jobName ?? 'Untitled Job',
              customerName: job.customerName,
              address: job.address,
              dateLabel: job.jobDate != null ? _formatDate(job.jobDate) : null,
              badges: [
                _buildJobTypeBadge(context, job.typeJob),
                _buildStatusBadge(
                  label: isRescheduledStatus ? 'Rescheduled' : 'In Progress',
                  color: isRescheduledStatus ? Colors.orange : accent,
                  icon: isRescheduledStatus
                      ? Icons.event_repeat
                      : Icons.timelapse,
                ),
                if (rescheduledDate != null)
                  _buildStatusBadge(
                    label:
                        'Rescheduled · ${DateFormat('dd MMM, HH:mm').format(ManilaTimezone.convert(rescheduledDate))}',
                    color: Colors.orange,
                    icon: Icons.event_repeat,
                  ),
              ],
              accentColor: accent,
              onTap: () => _openJobDetails(job, isOngoing: true),
              onDetails: () => _openJobDetails(job, isOngoing: true),
              detailsLabel: hasRescheduled ? 'Details' : 'Resume',
            );
          },
        ),
      );
    });
  }

  /// Builds the list of completed jobs (history tab) with search, filter,
  /// and sort capabilities via [HistoryFilterMixin].
  Widget _getHistoryJob(JobsController controller, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    return Obx(() {
      if (controller.isLoadingHistoryJobs.value) {
        return ShimmerProvider(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: const [
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
              SizedBox(height: 10),
              SkeletonJobCard(),
            ],
          ),
        );
      }
      if (controller.errorHistoryJobs.value != null) {
        return _buildRefreshableMessage(
          controller,
          'Error: ${controller.errorHistoryJobs.value}',
        );
      }
      if (controller.historyJobsResponse.value?.data == null ||
          controller.historyJobsResponse.value!.data!.isEmpty) {
        return _buildRefreshableMessage(controller, 'No history jobs found');
      }

      // Read reactive filter values so Obx rebuilds on changes
      controller.historySearchQuery.value;
      controller.historyDateRange.value;
      controller.historyTypeFilter.value;
      controller.historySortOrder.value;
      controller.isHistoryFilterVisible.value;

      final filteredJobs = controller.getFilteredHistoryJobs(
        controller.historyJobsResponse.value!.data,
      );

      return Column(
        children: [
          HistoryFilterBar(filteredCount: filteredJobs.length),
          Expanded(
            child: filteredJobs.isEmpty
                ? _buildFilteredEmptyState(controller)
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    triggerMode: RefreshIndicatorTriggerMode.anywhere,
                    child: ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: filteredJobs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final job = filteredJobs[index];
                        return JobSummaryCard(
                          title: job.jobName ?? 'Untitled Job',
                          customerName: job.customerName,
                          address: job.address,
                          dateLabel: job.jobDate != null
                              ? _formatDate(job.jobDate)
                              : null,
                          badges: [
                            _buildJobTypeBadge(context, job.typeJob),
                            _buildStatusBadge(
                              label: 'Completed',
                              color: Colors.green,
                              icon: Icons.verified_outlined,
                            ),
                          ],
                          accentColor: accent,
                          onTap: () => _openHistoryDetails(job),
                          onDetails: () => _openHistoryDetails(job),
                          detailsLabel: 'Report',
                        );
                      },
                    ),
                  ),
          ),
        ],
      );
    });
  }

  /// Empty state shown when filters match no jobs.
  Widget _buildFilteredEmptyState(JobsController controller) {
    return RefreshIndicator(
      onRefresh: controller.refresh,
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      const Text('No jobs match your filters'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: controller.clearHistoryFilters,
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Maps the numeric job type from the backend into a readable label.
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

  /// Creates a badge widget that visually represents the job type.
  JobCardBadge _buildJobTypeBadge(BuildContext context, int? type) {
    final typeString = _getJobTypeString(type);
    final accent = Theme.of(context).colorScheme.primary;
    return JobCardBadge(
      label: typeString,
      icon: Icons.work_outline,
      backgroundColor: accent.withValues(alpha: 0.22),
      foregroundColor: accent,
      borderColor: accent.withValues(alpha: 0.4),
    );
  }

  /// Creates a badge widget that visually represents the job status.
  JobCardBadge _buildStatusBadge({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return JobCardBadge(
      label: label,
      icon: icon,
      backgroundColor: color.withValues(alpha: 0.14),
      foregroundColor: color,
      borderColor: color.withValues(alpha: 0.28),
    );
  }

  /// Navigates to the job details page.
  ///
  /// When the details page returns with a `refresh` flag, the job lists
  /// are refreshed and the tab is optionally switched to the ongoing tab.
  void _openJobDetails(dynamic job, {bool isOngoing = false}) async {
    final result = await Get.to(
      () => JobDetailsPage(job: job, isOngoing: isOngoing),
    );
    if (result is Map && result['refresh'] == true) {
      final controller = Get.find<JobsController>();
      await controller.refresh();

      // Navigate to ongoing tab if job was just accepted
      if (result['navigateToOngoing'] == true) {
        controller.tabController.animateTo(1); // Index 1 is Ongoing tab
      }
    } else if (result == true) {
      Get.find<JobsController>().refresh();
    }
  }

  /// Navigates to the job history detail page for the given completed job.
  void _openHistoryDetails(history.Data job) {
    Get.to(() => JobHistoryDetailPage(job: job));
  }

  /// Formats a dynamic date value from the API into a short readable label.
  String _formatDate(dynamic value) {
    final dateTime = _parseDate(value);
    if (dateTime == null) return 'N/A';
    return DateFormat('EEE, dd MMM yyyy').format(ManilaTimezone.convert(dateTime));
  }

  /// Parses different possible date representations (DateTime, String, int)
  /// returned by the backend into a [DateTime] instance when possible.
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
