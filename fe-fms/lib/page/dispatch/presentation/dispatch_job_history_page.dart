import 'package:flutter/material.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
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
                    'Finished: ${job.finishWhen!}',
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
    );
  }
}
