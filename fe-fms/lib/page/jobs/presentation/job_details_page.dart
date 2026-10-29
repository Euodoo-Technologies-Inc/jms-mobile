import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fms/core/services/connectivity_service.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/core/widgets/app_dialog.dart';
import 'package:fms/core/widgets/detail_widgets.dart';
import 'package:fms/core/widgets/snackbar_utils.dart';
import 'package:fms/core/utils/user_message.dart';
import 'package:fms/page/dispatch/widget/dispatch_auth_widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:fms/core/utils/timezone_util.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:get/get.dart';

import '../controller/jobs_controller.dart';
import '../widget/job_status.dart';

import '../../../core/permissions/permission_helper.dart';
import '../../../core/models/geo.dart';

import 'job_navigation_page.dart';

/// A page displaying detailed information about a specific job.
/// Allows the driver to start, finish, reschedule, or cancel the job.
class JobDetailsPage extends StatefulWidget {
  final dynamic job;
  final bool isOngoing;
  //is ongoing = false
  const JobDetailsPage({super.key, required this.job, this.isOngoing = false});
  @override
  State<JobDetailsPage> createState() => _JobDetailsPageState();
}

class _JobDetailsPageState extends State<JobDetailsPage> {
  final TextEditingController _cancelReasonController = TextEditingController();
  final TextEditingController _rescheduleNotesController =
      TextEditingController();
  late final JobsController _jobsController;

  @override
  void initState() {
    super.initState();
    _jobsController = Get.find<JobsController>();
  }

  /// Photos and notes from a Finish that didn't go through, so the retry
  /// starts at the review step instead of the camera.
  List<XFile> _unsentPhotos = [];
  String? _unsentNotes;

  /// Shows a spinner that Back can't dismiss and returns its closer, which
  /// pops the spinner exactly once however many paths call it — a second pop
  /// would close this page (and the rider's photos) instead.
  VoidCallback _showBlockingProgress(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    var open = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    return () {
      if (!open) return;
      open = false;
      navigator.pop();
    };
  }

  @override
  void dispose() {
    _cancelReasonController.dispose();
    _rescheduleNotesController.dispose();
    super.dispose();
  }

  // ignore: unused_element
  void _shareJobDetails() {
    final job = widget.job;
    final buffer = StringBuffer()
      ..writeln('Job: ${job.jobName ?? 'N/A'}')
      ..writeln(
        'Status: '
        '${(widget.isOngoing ? JobStatus.inProgress : JobStatus.open).label}',
      )
      ..writeln('Job Type: ${_getJobTypeString(job.typeJob)}');

    if (job.jobDate != null) {
      buffer.writeln('Date: ${_formatDate(job.jobDate)}');
    }

    if (job.customerName != null) {
      buffer.writeln('Customer: ${job.customerName}');
    }

    if (job.address != null) {
      buffer.writeln('Address: ${job.address}');
    }

    Share.share(
      buffer.toString().trim(),
      subject: job.jobName ?? 'Job details',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = context.dispatch;
    final job = widget.job;
    final isOngoing = widget.isOngoing;
    final int? jobIdValue = job.jobId is int ? job.jobId as int : null;
    final bool isRescheduledStatus = isOngoing && job.status == 3;
    final bool hasPendingAction =
        jobIdValue != null && _jobsController.isJobPendingUpload(jobIdValue);

    // Server-provided reschedule info (only available on ongoing job model)
    final int? rescheduleStatus = isOngoing ? job.rescheduleStatus : null;
    final bool? serverCanFinish = isOngoing ? job.canFinish : null;
    final String? rescheduledDateJob = isOngoing ? job.rescheduledDateJob : null;
    final String? reasonReject = isOngoing ? job.reasonReject : null;

    // Local fallback: rescheduledJobs map (for optimistic UI after reschedule request)
    final localRescheduledDate = jobIdValue != null
        ? _jobsController.rescheduledJobs[jobIdValue]
        : null;

    // Determine if finish is allowed.
    // serverCanFinish == null means the backend hasn't been updated yet —
    // treat as allowed (backward compatible with old API).
    final bool canFinish = (serverCanFinish ?? true) &&
        !hasPendingAction &&
        localRescheduledDate == null;
    // Determine if reschedule button is allowed (enabled for ongoing status 1,
    // or after rejection, or after approval)
    final bool canReschedule = isOngoing &&
        !hasPendingAction &&
        localRescheduledDate == null &&
        rescheduleStatus != 1; // blocked only when pending

    // A driver may only have one job in progress at a time. When viewing an
    // open (not-yet-accepted) job while another job is already ongoing, the
    // Start action is blocked.
    final bool blockStartForOngoing = !isOngoing &&
        (_jobsController.ongoingJobsResponse.value?.data?.isNotEmpty ?? false);

    const sectionSpacing = 22.0;
    return Scaffold(
      backgroundColor: palette.pageSurface,
      appBar: AppBar(
        backgroundColor: palette.pageSurface,
        surfaceTintColor: palette.pageSurface,
        foregroundColor: palette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: palette.cardBorder)),
        title: Text(
          job.jobName ?? 'Job details',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        // Profile is intentionally not reachable from the job detail page —
        // drivers shouldn't jump to their profile mid-job.
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailHeader(
                  title: job.jobName ?? 'Job',
                  pill: (isOngoing
                          ? (isRescheduledStatus
                              ? JobStatus.rescheduled
                              : JobStatus.inProgress)
                          : JobStatus.open)
                      .pill(context),
                ),
                const SizedBox(height: 6),
                Text(
                  _getJobTypeString(job.typeJob),
                  style: TextStyle(color: palette.subtle, fontSize: 13.5),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (job.jobDate != null)
                      DetailStatusPill(
                        label: _formatDate(job.jobDate),
                        color: palette.subtle,
                        icon: Icons.calendar_today_outlined,
                      ),
                    if (rescheduleStatus == 2)
                      DetailStatusPill(
                        label: serverCanFinish == true
                            ? 'Rescheduled — Ready'
                            : 'Rescheduled to ${rescheduledDateJob ?? ''}',
                        color: Theme.of(context).colorScheme.primary,
                        icon: serverCanFinish == true
                            ? Icons.check_circle_outline
                            : Icons.event_repeat,
                      ),
                  ],
                ),

                if (blockStartForOngoing) ...[
                  const SizedBox(height: sectionSpacing),
                  const DetailNoticeCard(
                    icon: Icons.info_outline,
                    title: 'Finish your ongoing job first',
                    message:
                        'You already have a job in progress. Complete or '
                        'cancel it before accepting a new one.',
                    color: DispatchColors.warning,
                  ),
                ],

                const SizedBox(height: sectionSpacing),

                const DetailSectionLabel('Customer'),
                DetailCard(
                  child: Column(
                    children: [
                      DetailKvRow(label: 'Name', value: job.customerName),
                      if (job.phoneNumber != null)
                        DetailKvRow(
                          label: 'Phone',
                          value: job.phoneNumber,
                          valueColor: Theme.of(context).colorScheme.primary,
                          trailingIcon: Icons.phone,
                          onTap: () => _callPhone(job.phoneNumber!),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: sectionSpacing),

                const DetailSectionLabel('Address'),
                DetailCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.address ?? 'N/A',
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _navigateToJob(context),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                            padding: EdgeInsets.zero,
                            overlayColor:
                                DispatchColors.brand.withValues(alpha: 0.08),
                          ),
                          label: const Text('Open in Map'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: sectionSpacing),

                const DetailSectionLabel('Job information'),
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
                        DetailKvRow(
                          label: 'Created at',
                          value: _formatDate(job.createdAt),
                        ),
                    ],
                  ),
                ),

                // Reschedule rejection info
                if (isOngoing && rescheduleStatus == 3 && reasonReject != null) ...[
                  const SizedBox(height: sectionSpacing),
                  DetailNoticeCard(
                    icon: Icons.warning_amber_rounded,
                    title: 'Reschedule rejected',
                    message: reasonReject,
                    color: colorScheme.error,
                    footnote: 'You must complete this job.',
                  ),
                ],

                // Reschedule pending info
                if (isOngoing && (rescheduleStatus == 1 || localRescheduledDate != null)) ...[
                  const SizedBox(height: sectionSpacing),
                  const DetailNoticeCard(
                    icon: Icons.hourglass_top,
                    title: 'Reschedule pending',
                    message:
                        'Your reschedule request is awaiting admin approval.',
                    color: DispatchColors.warning,
                  ),
                ],

                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOngoing)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _navigateToJob(context),
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Navigate'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      overlayColor: DispatchColors.brand.withValues(
                        alpha: 0.08,
                      ),
                    ),
                  ),
                ),
              if (isOngoing) const SizedBox(height: 12),
              Row(
                children: [
                  if (isOngoing)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isRescheduledStatus || hasPendingAction
                            ? null
                            : () {
                                _cancelJob(context);
                              },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: const BorderSide(
                            color: DispatchColors.danger,
                            width: 1.5,
                          ),
                          foregroundColor: DispatchColors.danger,
                          overlayColor: DispatchColors.danger.withValues(
                            alpha: 0.08,
                          ),
                        ),
                      ),
                    ),
                  if (isOngoing && canReschedule) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showRescheduleDialog(context),
                        icon: const Icon(Icons.event_repeat),
                        label: const Text('Reschedule'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: const BorderSide(color: DispatchColors.warning),
                          foregroundColor: DispatchColors.warning,
                          overlayColor: const Color(
                            0xFFFF9800,
                          ).withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                  ],
                  if (isOngoing) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: hasPendingAction
                          ? null
                          : isOngoing
                              ? (canFinish ? () => _finishJob(context) : null)
                              : (blockStartForOngoing
                                  ? null
                                  : () => _startJob(context)),
                      icon: Icon(
                        hasPendingAction
                            ? Icons.cloud_upload_outlined
                            : isOngoing
                                ? Icons.flag
                                : Icons.play_arrow_rounded,
                      ),
                      label: Text(hasPendingAction
                          ? 'Pending upload'
                          : (isOngoing ? 'Finish job' : 'Start job')),
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
            ],
          ),
        ),
      ),
    );
  }

  String _getJobTypeString(int? type) {
    switch (type) {
      case 1:
        return 'Line interruption';
      case 2:
        return 'Reconnection';
      case 3:
        return 'Short circuit';
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

  Future<void> _callPhone(String rawNumber) async {
    final sanitized = rawNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: sanitized);
    final launched = await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cannot open phone dialer')));
    }
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

  /// Starts the job, changing its status to ongoing.
  Future<void> _startJob(BuildContext context) async {
    // Safety net: a driver can only have one job in progress at a time.
    final hasOngoing =
        _jobsController.ongoingJobsResponse.value?.data?.isNotEmpty ?? false;
    if (hasOngoing) {
      SnackbarUtils(
        text: 'Finish your ongoing job before accepting another.',
        backgroundColor: DispatchColors.danger,
      ).showErrorSnackBar(context);
      return;
    }

    final jobId = widget.job.jobId as int?;
    if (jobId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Job ID not found',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: DispatchColors.danger,
        ),
      );
      return;
    }

    final closeProgress = _showBlockingProgress(context);

    try {
      final response = await _jobsController.startJob(jobId);

      if (context.mounted) {
        closeProgress();
        final isSuccess = response.success == true;
        final message = isSuccess
            ? 'Job started.'
            : userMessage(Exception(response.message ?? "Couldn't start the job. Try again."));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor:
                isSuccess ? DispatchColors.brand : DispatchColors.danger,
            content: Text(message, style: const TextStyle(color: Colors.white)),
          ),
        );

        if (isSuccess) {
          // Return with special flag to navigate to ongoing tab
          Navigator.pop(context, {'refresh': true, 'navigateToOngoing': true});
        }
      }
    } catch (e) {
      if (context.mounted) {
        log('Failed to start job: ${e.toString()}');
        closeProgress();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage(e), style: TextStyle(color: Colors.white)),
            backgroundColor: DispatchColors.danger,
          ),
        );
      }
    } finally {
      closeProgress();
    }
  }

  /// Finishes the job, requiring photo evidence and optional notes.
  /// /// Finishes the job with enhanced debugging
Future<void> _finishJob(BuildContext context) async {
  final jobId = widget.job.jobId as int?;

  // --- Validation Checks ---
  if (jobId == null) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Job ID not found'))
    );
    return;
  }

  // --- Permissions & Source ---
  final granted = await AppPermission.ensurePhotosPermission(context);
  if (!mounted) return;
  if (!granted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Photo access is needed to attach proof of work. '
          'Allow it, then tap Finish again.',
        ),
      ),
    );
    return;
  }

  // --- Image Picking + Preview ---
  // A failed attempt's photos go straight to review; "Retake" picks again.
  var images = _unsentPhotos;
  while (true) {
    if (images.isEmpty) {
      final source = await _showImageSourceSheet(context);
      if (!mounted || source == null) return;
      images = await _pickImages(context, ImagePicker(), source);
      if (!mounted) return;
      if (images.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select minimum 2 photos'))
        );
        return;
      }
    }
    if (await _showImagePreview(context, images)) break;
    if (!mounted) return;
    images = [];
  }
  _unsentPhotos = images;

  // --- Notes Input ---
  final notesResult = await _askForNotes(context, initial: _unsentNotes);
  if (!mounted) return;
  
  if (notesResult == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Finish job canceled'))
    );
    return;
  }

  final trimmedNotes = notesResult.trim();
  _unsentNotes = trimmedNotes;

  // Dismiss keyboard explicitly
  FocusScope.of(context).unfocus();
  
  // Wait for keyboard dismissal animation
  await Future.delayed(const Duration(milliseconds: 400));
  if (!mounted) return;

  final closeProgress = _showBlockingProgress(context);

  try {
    // Check connectivity to decide online/offline path
    final connectivity = Get.find<ConnectivityService>();
    final isOnline = connectivity.isConnected.value;

    if (!isOnline) {
      // OFFLINE: skip base64 encoding, save raw files for later sync
      log('Offline mode: saving job $jobId locally');
      final response = await _jobsController.finishJob(
        jobId: jobId,
        imagesBase64: [],
        notes: trimmedNotes.isEmpty ? null : trimmedNotes,
        originalImageFiles: images,
      );

      if (!mounted) return;
      closeProgress();

      if (response.success != true) {
        throw Exception(response.message ?? 'Failed to save job offline');
      }

      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.message ?? 'Job saved locally. Will sync when online.',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: DispatchColors.warning,
        ),
      );

      Navigator.pop(context, true);
      return;
    }

    // ONLINE: existing path
    log('========== FINISH JOB DEBUG ==========');
    log('Job ID: $jobId');
    log('Number of images: ${images.length}');
    log('Notes: ${trimmedNotes.isEmpty ? "none" : trimmedNotes}');

    final List<String> imagesBase64 = [];

    for (int i = 0; i < images.length; i++) {
      final bytes = await images[i].readAsBytes();
      final sizeInMB = bytes.length / (1024 * 1024);
      log('Image ${i + 1}/${images.length} - Size: ${sizeInMB.toStringAsFixed(2)} MB');

      if (sizeInMB > 10) {
        throw Exception('Image ${i + 1} is too large: ${sizeInMB.toStringAsFixed(1)}MB. Maximum is 10MB');
      }

      imagesBase64.add(base64Encode(bytes));
      log('Image ${i + 1} encoded successfully');
    }

    log('All images encoded. Starting API call...');

    final response = await _jobsController.finishJob(
      jobId: jobId,
      imagesBase64: imagesBase64,
      notes: trimmedNotes.isEmpty ? null : trimmedNotes,
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw Exception('Request timeout after 60 seconds - images might be too large or poor network connection');
      },
    );

    log('API Response received');
    log('Response success: ${response.success}');
    log('Response message: ${response.message}');
    log('======================================');

    if (!mounted) return;

    closeProgress();

    if (response.success != true) {
      throw Exception(response.message ?? 'Server returned failure status');
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Job finished.',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: DispatchColors.brand,
      ),
    );

    Navigator.pop(context, true);

  } catch (e, stackTrace) {
    if (!mounted) return;

    log('========== ERROR DETAILS ==========');
    log('Error: $e');
    log('Stack Trace: $stackTrace');
    log('===================================');

    // Network error fallback: save offline as safety net
    final errorStr = e.toString();
    final isNetworkError = errorStr.contains('SocketException') ||
        errorStr.contains('Failed host lookup') ||
        errorStr.contains('Network is unreachable') ||
        errorStr.contains('timeout');

    if (isNetworkError) {
      try {
        final offlineResponse = await _jobsController.finishJob(
          jobId: jobId,
          imagesBase64: [],
          notes: trimmedNotes.isEmpty ? null : trimmedNotes,
          originalImageFiles: images,
        );

        if (!mounted) return;
        closeProgress();

        if (offlineResponse.success == true) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                offlineResponse.message ?? 'Job saved locally. Will sync when online.',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: DispatchColors.warning,
            ),
          );

          Navigator.pop(context, true);
          return;
        }
      } catch (_) {
        // Fallback failed, show original error below
      }
    }

    closeProgress();

    final errorMessage = userMessage(e);

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: DispatchColors.danger,
        duration: const Duration(seconds: 5),
      ),
    );
  } finally {
    closeProgress();
  }
}
  Future<ImageSource?> _showImageSourceSheet(BuildContext context) async {
    final palette = context.dispatch;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add job photos',
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Attach at least 2 photos as proof of completion.',
                  style: TextStyle(color: palette.subtle, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _photoSourceTile(
                  context,
                  icon: Icons.photo_camera_outlined,
                  title: 'Camera',
                  subtitle: 'Take photos now',
                  onTap: () =>
                      Navigator.of(sheetContext).pop(ImageSource.camera),
                ),
                const SizedBox(height: 12),
                _photoSourceTile(
                  context,
                  icon: Icons.photo_library_outlined,
                  title: 'Gallery',
                  subtitle: 'Pick from your photos',
                  onTap: () =>
                      Navigator.of(sheetContext).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A single tappable photo-source option used in [_showImageSourceSheet].
  Widget _photoSourceTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final palette = context.dispatch;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.pageSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: DispatchColors.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: DispatchColors.brand, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: palette.subtle, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: palette.subtle, size: 20),
          ],
        ),
      ),
    );
  }

  Future<List<XFile>> _pickImages(
    BuildContext context,
    ImagePicker picker,
    ImageSource source,
  ) async {
    if (source == ImageSource.gallery) {
      return await picker.pickMultiImage(imageQuality: 85, maxWidth: 1600);
    }

    final capturedImages = <XFile>[];

    while (capturedImages.length < 2) {
      final image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (image == null) {
        break;
      }

      capturedImages.add(image);
    }

    while (capturedImages.isNotEmpty) {
      final addMore = await _askCaptureMore(context);
      if (!addMore) {
        break;
      }

      final image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (image == null) {
        break;
      }

      capturedImages.add(image);
    }

    return capturedImages;
  }

  Future<bool> _askCaptureMore(BuildContext context) async {
    if (!mounted) return false;

    final result =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AppDialog(
            icon: Icons.add_a_photo_outlined,
            accent: DispatchColors.brand,
            title: 'Add more photos?',
            message: 'Capture another shot, or finish if you have enough.',
            actions: [
              AppDialogButton(
                label: 'Done',
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              AppDialogButton(
                label: 'Add',
                filled: true,
                icon: Icons.photo_camera_outlined,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ) ??
        false;

    return result;
  }

  Future<bool> _showImagePreview(
    BuildContext context,
    List<XFile> images,
  ) async {
    if (images.isEmpty) return false;

    return (await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AppDialog(
            icon: Icons.photo_library_outlined,
            accent: DispatchColors.brand,
            title: 'Review photos',
            message:
                '${images.length} photo${images.length == 1 ? '' : 's'} '
                'selected. Upload these, or retake if something\'s off.',
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: images
                      .map(
                        (image) => ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(image.path),
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            actions: [
              AppDialogButton(
                label: 'Retake',
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              AppDialogButton(
                label: 'Upload',
                filled: true,
                icon: Icons.cloud_upload_outlined,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<String?> _askForNotes(BuildContext context, {String? initial}) async {
  final controller = TextEditingController(text: initial);
  
  try {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AppDialog(
        icon: Icons.sticky_note_2_outlined,
        accent: DispatchColors.brand,
        title: 'Job notes',
        message: 'Add an optional note before finishing — or skip it.',
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Add an optional note for this job',
          ),
        ),
        actions: [
          AppDialogButton(
            label: 'Cancel',
            color: DispatchColors.danger,
            onPressed: () => Navigator.of(dialogContext).pop(null),
          ),
          AppDialogButton(
            label: 'Skip',
            onPressed: () => Navigator.of(dialogContext).pop(''),
          ),
          AppDialogButton(
            label: 'Finish job',
            filled: true,
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          ),
        ],
      ),
    );
    
    // CRITICAL: Wait for dialog close animation before disposing
    await Future.delayed(const Duration(milliseconds: 300));
    
    return result;
  } finally {
    // Dispose in finally block to ensure it always happens
    controller.dispose();
  }
}

  Future<String?> _askCancelReason(BuildContext context) async {
    final suggestions = <String>[
      'Customer not available',
      'Wrong address',
      'Vehicle issue',
      'Weather issue',
      'Other',
    ];
    final controller = _cancelReasonController;
    controller.clear();
    int selectedIndex = -1;
    bool missingReason = false;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) => AppDialog(
          icon: Icons.edit_note,
          accent: DispatchColors.danger,
          title: 'Reason for cancelling',
          message: 'Pick a reason or add your own — this is shared with the '
              'dispatcher.',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < suggestions.length; i++)
                    ChoiceChip(
                      label: Text(suggestions[i]),
                      selected: selectedIndex == i,
                      selectedColor:
                          DispatchColors.danger.withValues(alpha: 0.14),
                      onSelected: (val) {
                        setState(() {
                          selectedIndex = val ? i : -1;
                          missingReason = false;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Type additional details (optional)',
                  errorText: missingReason
                      ? 'Pick a reason above or type one'
                      : null,
                ),
              ),
            ],
          ),
          actions: [
            AppDialogButton(
              label: 'Back',
              onPressed: () => Navigator.of(dialogContext).pop(null),
            ),
            AppDialogButton(
              label: 'Cancel job',
              filled: true,
              color: DispatchColors.danger,
              onPressed: () {
                String reason = '';
                if (selectedIndex >= 0) {
                  reason = suggestions[selectedIndex];
                }
                final note = controller.text.trim();
                if (note.isNotEmpty) {
                  reason = reason.isEmpty ? note : '$reason — $note';
                }
                if (reason.trim().isEmpty) {
                  setState(() => missingReason = true);
                  return;
                }
                Navigator.of(dialogContext).pop(reason.trim());
              },
            ),
          ],
        ),
      ),
    );
    controller.clear();
    return result;
  }

  /// Shows a dialog to reschedule the job to a future date.
  ///
  /// Returns `true` if the reschedule succeeded, `false` if the server
  /// rejected it, or `null` if the user dismissed the dialog.
  Future<bool?> _showRescheduleDialog(BuildContext context) async {
    final jobId = widget.job.jobId as int?;
    if (jobId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Job ID not found',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: DispatchColors.danger,
        ),
      );
      return null;
    }

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final palette = context.dispatch;

    DateTime selectedDate = ManilaTimezone.now().add(const Duration(days: 1));
    final _manilaTime = ManilaTimezone.now();
    TimeOfDay selectedTime = TimeOfDay(hour: _manilaTime.hour, minute: _manilaTime.minute);
    final notesController = _rescheduleNotesController;
    notesController.clear();
    String? rescheduleError;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) {
          const amber = DispatchColors.warning;
          return AppDialog(
            icon: Icons.event_repeat,
            accent: amber,
            title: 'Reschedule job',
            message: 'Pick a new date and time and tell the dispatcher why. '
                'This needs admin approval before it takes effect.',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Date Time Picker
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.cardBorder),
                  ),
                  child: Column(
                    children: [
                      // Date Selector
                      InkWell(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: selectedDate,
                            firstDate: ManilaTimezone.now(),
                            lastDate: ManilaTimezone.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null) {
                            setState(() => selectedDate = picked);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('EEE MMM d').format(selectedDate),
                                    style: textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: palette.ink,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('yyyy').format(selectedDate),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: palette.subtle,
                                    ),
                                  ),
                                ],
                              ),
                              const Icon(
                                Icons.calendar_today,
                                color: amber,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Divider(height: 1, color: palette.divider),
                      // Time Selector
                      InkWell(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(14),
                        ),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: dialogContext,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setState(() => selectedTime = picked);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                selectedTime.format(dialogContext),
                                style: textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: palette.ink,
                                ),
                              ),
                              const Icon(
                                Icons.access_time,
                                color: amber,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Notes TextField
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.cardBorder),
                  ),
                  child: TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Reason for rescheduling (required)',
                      hintStyle: textTheme.bodyMedium?.copyWith(
                        color: palette.subtle,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                if (rescheduleError != null) ...[
                  const SizedBox(height: 12),
                  DispatchErrorText(rescheduleError!),
                ],
              ],
            ),
            actions: [
              AppDialogButton(
                label: 'Cancel',
                color: DispatchColors.danger,
                onPressed: () => Navigator.of(dialogContext).pop(null),
              ),
              AppDialogButton(
                label: 'Reschedule',
                filled: true,
                color: amber,
                onPressed: () {
                  // Validate notes field is not empty
                  final notes = notesController.text.trim();
                  if (notes.isEmpty) {
                    setState(() => rescheduleError =
                        'Add a reason for rescheduling.');
                    return;
                  }

                  final scheduledDateTime = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  );

                  if (scheduledDateTime.isBefore(ManilaTimezone.now())) {
                    setState(() => rescheduleError =
                        'Pick a time that is later than now.');
                    return;
                  }

                  Navigator.of(dialogContext).pop({
                    'date': scheduledDateTime,
                    'notes': notes,
                  });
                },
              ),
            ],
          );
        },
      ),
    );

    if (result == null || !mounted) {
      return null;
    }

    // Process reschedule
    final scheduledDate = result['date'] as DateTime;
    final notes = result['notes'] as String?;

    final closeProgress = _showBlockingProgress(context);

    try {
      final response = await _jobsController.rescheduleJob(
        jobId: jobId,
        newDate: scheduledDate,
        notes: notes,
      );

      if (!mounted) return null;

      closeProgress();

      final success = response.success == true;
      final isOfflineSave = response.message?.contains('locally') ?? false;
      final message = success
          ? (isOfflineSave
              ? response.message!
              : 'Reschedule sent. It takes effect once an admin approves it.')
          : userMessage(Exception(response.message ?? "Couldn't reschedule the job. Try again."));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: success
              ? (isOfflineSave ? DispatchColors.warning : DispatchColors.brand)
              : DispatchColors.danger,
        ),
      );

      if (success) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jobsController.markJobRescheduled(jobId, scheduledDate);
          if (mounted) {
            setState(() {});
          }
        });
        return true;
      }

      return false;
    } catch (e) {
      if (!mounted) return null;
      log('Failed to reschedule job: ${e.toString()}');
      closeProgress();

      SnackbarUtils(
        text: userMessage(e),
        backgroundColor: DispatchColors.danger,
      ).showErrorSnackBar(context);
      return false;
    } finally {
      closeProgress();
    }
  }

  /// Cancels the job with a required reason.
  Future<void> _cancelJob(BuildContext context) async {
    final jobId = widget.job.jobId as int?;

    if (jobId == null) {
      SnackbarUtils(
        text: 'Job ID not found',
        backgroundColor: DispatchColors.danger,
      ).showErrorSnackBar(context);
      return;
    }

    // Ask for confirmation to cancel
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AppDialog(
            icon: Icons.cancel_outlined,
            accent: DispatchColors.danger,
            title: 'Cancel this job?',
            message:
                'This marks the job as cancelled and removes it from your '
                'ongoing list. You\'ll be asked for a reason next.',
            actions: [
              AppDialogButton(
                label: 'Keep job',
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              AppDialogButton(
                label: 'Cancel job',
                filled: true,
                color: DispatchColors.danger,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    final reason = await _askCancelReason(context);
    if (!mounted) return;
    if (reason == null || reason.trim().isEmpty) {
      SnackbarUtils(
        text: 'Add a reason to cancel the job.',
        backgroundColor: DispatchColors.danger,
      ).showErrorSnackBar(context);
      return;
    }

    final closeProgress = _showBlockingProgress(context);

    try {
      final response = await _jobsController.cancelJob(
        jobId: jobId,
        reason: reason.trim(),
      );

      if (!mounted) return;

      closeProgress();

      final success = response.success == true;
      final isOfflineSave = response.message?.contains('locally') ?? false;
      final message = success
          ? (isOfflineSave ? response.message! : 'Job cancelled.')
          : userMessage(Exception(response.message ?? "Couldn't cancel the job. Try again."));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: success
              ? (isOfflineSave ? DispatchColors.warning : DispatchColors.brand)
              : DispatchColors.danger,
        ),
      );

      if (success) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      log('Failed to cancel job: ${e.toString()}');
      closeProgress();
      SnackbarUtils(
        text: userMessage(e),
        backgroundColor: DispatchColors.danger,
      ).showErrorSnackBar(context);
    } finally {
      closeProgress();
    }
  }

  Future<void> _navigateToJob(BuildContext context) async {
    final coordinates = _extractJobCoordinates(widget.job);

    if (coordinates != null) {
      if (widget.isOngoing) {
        final launched = await _launchExternalNavigation(context, coordinates);
        if (!launched && mounted) {
          await _openInternalMap(context, coordinates);
        }
      } else {
        await _openInternalMap(context, coordinates);
      }
      return;
    }

    if (!mounted) return;
    SnackbarUtils(
      text: 'No location for this job',
      backgroundColor: DispatchColors.danger,
    ).showErrorSnackBar(context);
  }

  Future<void> _openInternalMap(
    BuildContext context,
    GeoPoint coordinate,
  ) async {
    if (!mounted) return;
    Get.to(
      () => JobNavigationPage(
        latitude: coordinate.lat,
        longitude: coordinate.lng,
        jobName: widget.job.jobName ?? 'Job destination',
        address: widget.job.address,
      ),
    );
  }

  Future<bool> _launchExternalNavigation(
    BuildContext context,
    GeoPoint coordinate,
  ) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${coordinate.lat},${coordinate.lng}',
    );

    final canLaunchUri = await canLaunchUrl(uri);
    if (!canLaunchUri) {
      return false;
    }

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't open Google Maps. Try again."),
          ),
        );
      }
      return false;
    }
  }

  /// Every 2W job model names its coordinates `latitude`/`longitude`; a model
  /// without them (NoSuchMethodError on `dynamic`) just has no location.
  GeoPoint? _extractJobCoordinates(dynamic job) {
    double? latitude, longitude;
    try {
      latitude = _parseCoordinate(job?.latitude);
      longitude = _parseCoordinate(job?.longitude);
    } on NoSuchMethodError {
      return null;
    }
    if (latitude == null || longitude == null) {
      return null;
    }
    return GeoPoint(latitude, longitude);
  }

  double? _parseCoordinate(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}

