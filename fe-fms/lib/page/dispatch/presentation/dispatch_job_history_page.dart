import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_format.dart';
import '../../../data/dispatch/datasource/dispatch_jobs_datasource.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';

/// Read-only list of the rider's recently completed jobs (server-capped at
/// 50). Pulled on open + pull-to-refresh; no caching since it's not a
/// hot-path screen.
class DispatchJobHistoryPage extends StatefulWidget {
  const DispatchJobHistoryPage({super.key});

  @override
  State<DispatchJobHistoryPage> createState() => _DispatchJobHistoryPageState();
}

class _DispatchJobHistoryPageState extends State<DispatchJobHistoryPage> {
  final DispatchJobsDatasource _ds = DispatchJobsDatasource();
  bool _loading = false;
  String? _error;
  List<DispatchJob> _jobs = const [];

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
      final jobs = await _ds.jobsHistory();
      if (!mounted) return;
      setState(() => _jobs = jobs);
    } on DispatchApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Completed jobs')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _jobs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _jobs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Center(child: Text(_error!)),
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
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.history_toggle_off,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Center(child: Text('No completed jobs yet.')),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _jobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _HistoryCard(job: _jobs[i]),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.to(() => DispatchJobHistoryDetailPage(jobId: job.id)),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_outlined,
                    size: 18, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    job.jobName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (job.address != null && job.address!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      job.address!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            if (job.finishWhen != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.event_available,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Finished: ${formatDispatchTimestamp(job.finishWhen)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ],
            if (job.notes != null && job.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                job.notes!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

/// Read-only detail view for a completed job. Mirrors the web "Job Detail"
/// page minus the driver name. Fetches `/jobs/{id}` on open.
class DispatchJobHistoryDetailPage extends StatefulWidget {
  const DispatchJobHistoryDetailPage({super.key, required this.jobId});
  final int jobId;

  @override
  State<DispatchJobHistoryDetailPage> createState() =>
      _DispatchJobHistoryDetailPageState();
}

class _DispatchJobHistoryDetailPageState
    extends State<DispatchJobHistoryDetailPage> {
  final DispatchJobsDatasource _ds = DispatchJobsDatasource();
  bool _loading = false;
  String? _error;
  DispatchJob? _job;

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
    } on DispatchApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Job detail')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _job == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _job == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Center(child: Text(_error!)),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _HeaderCard(job: job),
        const SizedBox(height: 12),
        _StatusTimelineCard(job: job),
        if (job.photos != null && job.photos!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PhotosCard(photos: job.photos!),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    job.jobName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(job: job, scheme: scheme),
              ],
            ),
            const Divider(height: 24),
            _KvRow(label: 'Customer', value: job.customer),
            _KvRow(label: 'Service type', value: job.serviceType),
            _KvRow(label: 'Address', value: job.address),
            _KvRow(
              label: 'Scheduled',
              value: formatDispatchTimestamp(job.scheduledArrival,
                  fallback: ''),
            ),
            _KvRow(
              label: 'Actual arrival',
              value: formatDispatchTimestamp(job.actualArrival,
                  fallback: ''),
            ),
            _KvRow(
              label: 'Finished at',
              value:
                  formatDispatchTimestamp(job.finishWhen, fallback: ''),
            ),
            if (job.notes != null && job.notes!.isNotEmpty)
              _KvRow(label: 'Notes', value: job.notes),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.job, required this.scheme});
  final DispatchJob job;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  (String, Color) _resolve(ColorScheme scheme) {
    if (job.isFinished) return ('Finished', Colors.green);
    if (job.isOnTheWay) return ('On the way', scheme.primary);
    if (job.isReschedulePending) {
      return ('Reschedule pending', Colors.orange);
    }
    return ('Assigned', scheme.primary);
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final shown = (value == null || value!.isEmpty) ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          Expanded(child: Text(shown)),
        ],
      ),
    );
  }
}

class _StatusTimelineCard extends StatelessWidget {
  const _StatusTimelineCard({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String?)>[
      ('Created', job.createdAt),
      ('Arrived', job.actualArrival),
      ('Finished', job.finishWhen),
    ].where((e) => e.$2 != null && e.$2!.isNotEmpty).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status timeline',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Text('No timeline data available.',
                  style: TextStyle(color: Colors.grey))
            else
              for (final (label, ts) in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.cyan,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            Text(formatDispatchTimestamp(ts),
                                style:
                                    const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _PhotosCard extends StatelessWidget {
  const _PhotosCard({required this.photos});
  final List<DispatchJobPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Proof of delivery photos (${photos.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (var i = 0; i < photos.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _PhotoTile(photo: photos[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});
  final DispatchJobPhoto photo;

  @override
  Widget build(BuildContext context) {
    final url = photo.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _photoPlaceholder(photo.filename),
              )
            : _photoPlaceholder(photo.filename),
      ),
    );
  }

  Widget _photoPlaceholder(String filename) {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_outlined, size: 36, color: Colors.grey),
          const SizedBox(height: 6),
          Text(
            filename.isEmpty ? '(no filename)' : filename,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
