import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_format.dart';
import '../../../core/theme/dispatch_palette.dart';
import '../../../data/dispatch/datasource/dispatch_jobs_datasource.dart';
import '../../../data/dispatch/models/dispatch_job_model.dart';
import '../widget/dispatch_external_status_pill.dart';

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
          'Completed jobs',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
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
              style: TextStyle(color: palette.subtle, fontSize: 15),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
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

/// A completed-job row — flat and divider-separated, mirroring the overview
/// page's `_OverviewJobRow`. Every history entry is a finished job, so the
/// accent bar is always the brand green.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final address = job.address;
    return InkWell(
      onTap: () => Get.to(() => DispatchJobHistoryDetailPage(jobId: job.id)),
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
                      const Text(
                        'COMPLETED',
                        style: TextStyle(
                          color: DispatchColors.brand,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      if (job.finishWhen != null)
                        Text(
                          formatDispatchTimestamp(job.finishWhen),
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
          'Job detail',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
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
        _DetailHeader(job: job),
        const SizedBox(height: 22),
        const _SectionLabel('Details'),
        _DetailCard(
          child: Column(
            children: [
              _KvRow(label: 'Customer', value: job.customer),
              _KvRow(label: 'Service type', value: job.serviceType),
              _KvRow(label: 'Address', value: job.address),
              _KvRow(
                label: 'Scheduled',
                value: formatDispatchTimestamp(
                    job.scheduledArrival, fallback: ''),
              ),
              _KvRow(
                label: 'Actual arrival',
                value: formatDispatchTimestamp(
                    job.actualArrival, fallback: ''),
              ),
              _KvRow(
                label: 'Finished at',
                value:
                    formatDispatchTimestamp(job.finishWhen, fallback: ''),
              ),
              if (job.meterNumber != null && job.meterNumber!.isNotEmpty)
                _KvRow(label: 'Meter no.', value: job.meterNumber),
              if (job.notes != null && job.notes!.isNotEmpty)
                _KvRow(label: 'Notes', value: job.notes),
            ],
          ),
        ),
        for (final section in job.externalDetails) ...[
          const SizedBox(height: 22),
          _SectionLabel(section.heading),
          _DetailCard(
            child: Column(
              children: [
                for (final f in section.fields)
                  _KvRow(label: f.label, value: f.value),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        const _SectionLabel('Timeline'),
        _DetailCard(child: _Timeline(job: job)),
        if (job.photos != null && job.photos!.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionLabel('Proof of delivery (${job.photos!.length})'),
          _DetailCard(child: _Photos(photos: job.photos!)),
        ],
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            job.jobName,
            style: TextStyle(
              color: palette.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusPill(job: job),
            if (job.externalStatusLabel != null) ...[
              const SizedBox(height: 6),
              DispatchExternalStatusPill(job: job),
            ],
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = job.isFinished
        ? ('Finished', DispatchColors.brand)
        : job.isOnTheWay
            ? ('On the way', const Color(0xFFb45309))
            : job.isReschedulePending
                ? ('Reschedule', const Color(0xFFb45309))
                : ('Assigned', context.dispatch.subtle);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Small all-caps section heading.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.dispatch.subtle,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A bordered, theme-aware content card.
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.cardBorder),
      ),
      child: child,
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final shown = (value == null || value!.isEmpty) ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(color: palette.subtle, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              shown,
              style: TextStyle(color: palette.ink, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.job});
  final DispatchJob job;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final entries = <(String, String?)>[
      ('Created', job.createdAt),
      ('Arrived', job.actualArrival),
      ('Finished', job.finishWhen),
    ].where((e) => e.$2 != null && e.$2!.isNotEmpty).toList();
    if (entries.isEmpty) {
      return Text(
        'No timeline data available.',
        style: TextStyle(color: palette.subtle, fontSize: 13),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding:
                EdgeInsets.only(bottom: i == entries.length - 1 ? 0 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: DispatchColors.brand,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entries[i].$1,
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatDispatchTimestamp(entries[i].$2),
                        style: TextStyle(
                          color: palette.subtle,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                    _placeholder(palette, photo.filename),
              )
            : _placeholder(palette, photo.filename),
      ),
    );
  }

  Widget _placeholder(DispatchPalette palette, String filename) {
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
            style: TextStyle(fontSize: 12, color: palette.subtle),
          ),
        ],
      ),
    );
  }
}
