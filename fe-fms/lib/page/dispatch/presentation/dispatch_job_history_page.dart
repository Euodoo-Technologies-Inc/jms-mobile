import 'package:flutter/material.dart';
import 'package:fms/core/utils/user_message.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_format.dart';
import '../../../core/theme/dispatch_palette.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../data/dispatch/datasource/dispatch_jobs_datasource.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../controller/dispatch_jobs_controller.dart';
import '../widget/dispatch_external_status_pill.dart';
import '../widget/dispatch_job_status.dart';

/// Read-only list of the rider's recently completed jobs (server-capped at
/// 50). Opens on the list from the last visit (held by the jobs controller)
/// and refreshes behind it; pull-to-refresh too.
class DispatchJobHistoryPage extends StatefulWidget {
  const DispatchJobHistoryPage({super.key});

  @override
  State<DispatchJobHistoryPage> createState() => _DispatchJobHistoryPageState();
}

class _DispatchJobHistoryPageState extends State<DispatchJobHistoryPage> {
  final DispatchJobsController _ctrl = Get.find<DispatchJobsController>();
  bool _loading = false;
  String? _error;
  List<DispatchJob> get _jobs => _ctrl.history;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _ctrl.refreshHistory();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: 'Job history',
      body: RefreshIndicator(
        color: DispatchColors.brand,
        onRefresh: _load,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final palette = context.dispatch;
    if (_loading && _jobs.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: DispatchColors.brand),
      );
    }
    if (_error != null && _jobs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.cloud_off, size: 56, color: palette.subtle),
          const SizedBox(height: 12),
          Center(
            child: Text(_error!, style: TextStyle(color: palette.subtle)),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonal(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    if (_jobs.isEmpty) {
      // A ListView so pull-to-refresh still works on an empty list.
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.history_toggle_off, size: 64, color: palette.subtle),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'No completed jobs yet.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: palette.subtle,
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: _jobs.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        color: palette.divider,
        indent: 20,
        endIndent: 20,
      ),
      itemBuilder: (context, i) => _HistoryRow(job: _jobs[i]),
    );
  }
}

/// A completed-job row — flat and divider-separated, like the overview
/// page's `_OverviewJobRow`. Every history entry is a finished job, so the
/// accent bar is always the brand green.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    final address = job.address;
    return InkWell(
      onTap: () => Get.to(
          () => DispatchJobHistoryDetailPage(jobId: job.id, initial: job)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 42,
              decoration: BoxDecoration(
                color: DispatchColors.brand,
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
                        'COMPLETED',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: DispatchColors.brand,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      if (job.finishWhen != null)
                        Text(
                          formatDispatchTimestamp(job.finishWhen),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
          ],
        ),
      ),
    );
  }
}

/// Read-only detail view for a completed job. Mirrors the web "Job Detail"
/// page minus the driver name. Shows [initial] at once and fetches
/// `/jobs/{id}` on open for the full record (photos, ORMECO sections).
class DispatchJobHistoryDetailPage extends StatefulWidget {
  const DispatchJobHistoryDetailPage({
    super.key,
    required this.jobId,
    this.initial,
  });
  final int jobId;

  /// The job as the history list already had it, if it did.
  final DispatchJob? initial;

  @override
  State<DispatchJobHistoryDetailPage> createState() =>
      _DispatchJobHistoryDetailPageState();
}

class _DispatchJobHistoryDetailPageState
    extends State<DispatchJobHistoryDetailPage> {
  final DispatchJobsDatasource _ds = DispatchJobsDatasource();
  bool _loading = false;
  String? _error;
  late DispatchJob? _job = widget.initial;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final job = await _ds.jobDetail(widget.jobId);
      if (!mounted) return;
      setState(() => _job = job);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: 'Job detail',
      body: RefreshIndicator(
        color: DispatchColors.brand,
        onRefresh: _load,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final palette = context.dispatch;
    if (_loading && _job == null) {
      return const Center(
        child: CircularProgressIndicator(color: DispatchColors.brand),
      );
    }
    if (_error != null && _job == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.cloud_off, size: 56, color: palette.subtle),
          const SizedBox(height: 12),
          Center(
            child: Text(_error!, style: TextStyle(color: palette.subtle)),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonal(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    final job = _job;
    if (job == null) {
      return ListView(children: const [SizedBox(height: 80)]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        DetailHeader(
          title: job.customer ?? job.jobName,
          // Capped so a long ORMECO flag wraps instead of squeezing the title.
          pill: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                DispatchJobStatus.of(job).pill(context),
                if (job.externalStatusLabel != null) ...[
                  const SizedBox(height: 6),
                  DispatchExternalStatusPill(job: job),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const DetailSectionLabel('Details'),
        DetailCard(
          child: Column(
            children: [
              DetailKvRow(label: 'Customer', value: job.customer),
              DetailKvRow(label: 'Service type', value: job.serviceType),
              DetailKvRow(label: 'Address', value: job.address),
              DetailKvRow(
                label: 'Scheduled',
                value: formatDispatchTimestamp(
                    job.scheduledArrival, fallback: ''),
              ),
              DetailKvRow(
                label: 'Started',
                value: formatDispatchTimestamp(
                    job.actualArrival, fallback: ''),
              ),
              DetailKvRow(
                label: 'Finished at',
                value:
                    formatDispatchTimestamp(job.finishWhen, fallback: ''),
              ),
              if (job.meterNumber != null && job.meterNumber!.isNotEmpty)
                DetailKvRow(label: 'Meter no.', value: job.meterNumber),
              if (job.notes != null && job.notes!.isNotEmpty)
                DetailKvRow(label: 'Notes', value: job.notes),
            ],
          ),
        ),
        for (final section in job.externalDetails) ...[
          const SizedBox(height: 22),
          DetailSectionLabel(section.heading),
          DetailCard(
            child: Column(
              children: [
                for (final f in section.fields)
                  DetailKvRow(label: f.label, value: f.value),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        const DetailSectionLabel('Timeline'),
        DetailCard(
          child: DetailTimeline(
            entries: [
              for (final (label, raw) in [
                ('Created', job.createdAt),
                ('Started', job.actualArrival),
                ('Finished', job.finishWhen),
              ])
                (label, formatDispatchTimestamp(raw, fallback: '')),
            ],
          ),
        ),
        if (job.photos != null && job.photos!.isNotEmpty) ...[
          const SizedBox(height: 22),
          DetailSectionLabel('Proof of work (${job.photos!.length})'),
          DetailCard(child: _Photos(photos: job.photos!)),
        ],
      ],
    );
  }
}

class _Photos extends StatelessWidget {
  const _Photos({required this.photos});
  final List<DispatchJobPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < photos.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _PhotoTile(photo: photos[i]),
        ],
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});
  final DispatchJobPhoto photo;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final url = photo.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _placeholder(context, palette, photo.filename),
              )
            : _placeholder(context, palette, photo.filename),
      ),
    );
  }

  Widget _placeholder(
    BuildContext context,
    DispatchPalette palette,
    String filename,
  ) {
    return Container(
      color: palette.cardBorder,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 36, color: palette.subtle),
          const SizedBox(height: 6),
          Text(
            filename.isEmpty ? '(no filename)' : filename,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
