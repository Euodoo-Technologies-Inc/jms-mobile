import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_navigation.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../controller/dispatch_jobs_controller.dart';
import 'dispatch_finish_job_page.dart';

// DispatchQueuedException lives in dispatch_jobs_controller.dart

/// Single job view. Refreshes on open so Start/Finish act on current state.
class DispatchJobDetailPage extends StatefulWidget {
  const DispatchJobDetailPage({super.key, required this.jobId});

  final int jobId;

  @override
  State<DispatchJobDetailPage> createState() => _DispatchJobDetailPageState();
}

class _DispatchJobDetailPageState extends State<DispatchJobDetailPage> {
  bool _loadingDetail = false;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loadingDetail = true;
      _error = null;
    });
    try {
      await Get.find<DispatchJobsController>().fetchDetail(widget.jobId);
    } on DispatchApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _startJob() async {
    setState(() => _starting = true);
    final ctrl = Get.find<DispatchJobsController>();
    try {
      await ctrl.startJob(widget.jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job started.')),
      );
    } on DispatchQueuedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved offline. Will sync when online.'),
          backgroundColor: Colors.orange,
        ),
      );
    } on DispatchApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: e.isConflict ? Colors.orange : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _openFinish(DispatchJob job) {
    Get.to(() => DispatchFinishJobPage(jobId: job.id));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DispatchJobsController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Job details')),
      body: SafeArea(
        child: Obx(() {
          final job =
              ctrl.jobs.firstWhereOrNull((j) => j.id == widget.jobId);
          if (job == null && _loadingDetail) {
            return const Center(child: CircularProgressIndicator());
          }
          if (job == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 8),
                    Text(_error ?? 'Job not found'),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  job.jobName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                _StatusBanner(job: job),
                const SizedBox(height: 16),
                if (job.address != null && job.address!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.place_outlined,
                    label: 'Address',
                    value: job.address!,
                  ),
                if (job.scheduledArrival != null)
                  _InfoRow(
                    icon: Icons.schedule,
                    label: 'Scheduled',
                    value: job.scheduledArrival!,
                  ),
                if (job.actualArrival != null)
                  _InfoRow(
                    icon: Icons.flag_outlined,
                    label: 'Started',
                    value: job.actualArrival!,
                  ),
                if (job.finishWhen != null)
                  _InfoRow(
                    icon: Icons.verified_outlined,
                    label: 'Finished',
                    value: job.finishWhen!,
                  ),
                if (job.meterNumber != null && job.meterNumber!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.speed,
                    label: 'Meter no.',
                    value: job.meterNumber!,
                  ),
                if (job.notes != null && job.notes!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.notes,
                    label: 'Notes',
                    value: job.notes!,
                  ),
                if (job.photos != null && job.photos!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PhotosSection(filenames: job.photos!.map((p) => p.filename).toList()),
                ],
                const SizedBox(height: 24),
                _Actions(
                  job: job,
                  starting: _starting,
                  onStart: _startJob,
                  onFinish: () => _openFinish(job),
                  onNavigate: () => launchMapsDirections(
                    context,
                    lat: job.lat!,
                    lng: job.lng!,
                    label: job.jobName,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _badge(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  (String, Color, IconData) _badge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (job.isFinished) {
      return ('Finished', Colors.green, Icons.verified_outlined);
    }
    if (job.isOnTheWay) {
      return ('On the way', scheme.primary, Icons.timelapse);
    }
    if (job.isReschedulePending) {
      return (
        'Reschedule pending — awaiting dispatcher',
        Colors.orange,
        Icons.event_repeat,
      );
    }
    return ('Assigned', scheme.primary, Icons.outlined_flag);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({required this.filenames});
  final List<String> filenames;

  @override
  Widget build(BuildContext context) {
    // Backend doesn't expose a rider-side image-serving endpoint yet (per
    // dispatch contract §9). Render filenames as a placeholder so the rider
    // can see how many proofs were uploaded; swap to network thumbnails
    // once the signed-URL endpoint lands.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library, size: 18),
            const SizedBox(width: 6),
            Text(
              'Photos (${filenames.length})',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: filenames
              .map(
                (f) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(f, style: const TextStyle(fontSize: 12)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.job,
    required this.starting,
    required this.onStart,
    required this.onFinish,
    required this.onNavigate,
  });

  final DispatchJob job;
  final bool starting;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    if (job.isFinished || job.isReschedulePending) {
      return const SizedBox.shrink();
    }

    final hasCoords = job.lat != null && job.lng != null;
    final primary = job.isOnTheWay
        ? SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.flag),
              label: const Text('Finish job'),
            ),
          )
        : SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: starting ? null : onStart,
              icon: starting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Start job'),
            ),
          );

    return Column(
      children: [
        primary,
        if (hasCoords) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onNavigate,
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Navigate'),
            ),
          ),
        ],
      ],
    );
  }
}
