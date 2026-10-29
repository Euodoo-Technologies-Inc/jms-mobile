import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fms/core/services/connectivity_service.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/core/widgets/app_dialog.dart';
import 'package:fms/core/widgets/detail_widgets.dart';
import 'package:fms/core/widgets/snackbar_utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:fms/core/utils/timezone_util.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:get/get.dart';

import '../controller/jobs_controller.dart';

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
      ..writeln('Status: ${widget.isOngoing ? 'Ongoing' : 'Open'}')
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
      subject: job.jobName ?? 'Job Details',
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
          job.jobName ?? 'Job Details',
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
                  pill: DetailStatusPill(
                    label: isOngoing
                        ? (isRescheduledStatus ? 'Rescheduled' : 'Ongoing')
                        : 'Open',
                    color: isOngoing
                        ? const Color(0xFFB45309)
                        : DispatchColors.brand,
                    icon: isOngoing
                        ? (isRescheduledStatus
                            ? Icons.event_repeat
                            : Icons.timelapse)
                        : Icons.event_available,
                  ),
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
                        color: DispatchColors.brand,
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
                    color: Color(0xFFB45309),
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
                          valueColor: DispatchColors.brand,
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
                            foregroundColor: DispatchColors.brand,
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
                    title: 'Reschedule Rejected',
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
                    title: 'Reschedule Pending',
                    message:
                        'Your reschedule request is awaiting admin approval.',
                    color: Color(0xFFB45309),
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
                      side: const BorderSide(color: DispatchColors.brand),
                      foregroundColor: DispatchColors.brand,
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
                          side: const BorderSide(color: Color(0xFFFF9800)),
                          foregroundColor: const Color(0xFFFF9800),
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
                          ? 'Pending Upload'
                          : (isOngoing ? 'Finish Job' : 'Start Job')),
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
        backgroundColor: Colors.red,
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
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Tampilkan loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await _jobsController.startJob(jobId);

      if (context.mounted) {
        Navigator.of(context).pop(); // close loading
        final isSuccess = response.success == true;
        final message =
            response.message ??
            (isSuccess ? 'Success Driver Get The Job' : 'Failed to start job');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: isSuccess ? Colors.green : Colors.red,
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
        Navigator.of(context).pop(); // close loading

        // Extract error message from exception
        String errorMessage = 'Failed to start job';
        final exceptionMessage = e.toString();
        if (exceptionMessage.startsWith('Exception: ')) {
          errorMessage = exceptionMessage.substring('Exception: '.length);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage, style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
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
  if (!granted || !mounted) return;

  final source = await _showImageSourceSheet(context);
  if (!mounted || source == null) return;

  // --- Image Picking ---
  final picker = ImagePicker();
  final images = await _pickImages(context, picker, source);

  if (images.isEmpty || images.length < 2) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Select minimum 2 photos'))
    );
    return;
  }

  // --- Preview ---
  final approved = await _showImagePreview(context, images);
  if (!approved) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Upload canceled'))
    );
    return;
  }

  // --- Notes Input ---
  final notesResult = await _askForNotes(context);
  if (!mounted) return;
  
  if (notesResult == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Finish job canceled'))
    );
    return;
  }

  final trimmedNotes = notesResult.trim();

  // Dismiss keyboard explicitly
  FocusScope.of(context).unfocus();
  
  // Wait for keyboard dismissal animation
  await Future.delayed(const Duration(milliseconds: 400));
  if (!mounted) return;

  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => WillPopScope(
      onWillPop: () async => false,
      child: const Center(child: CircularProgressIndicator()),
    ),
  );

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
      Navigator.of(context, rootNavigator: true).pop();

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
          backgroundColor: Colors.orange,
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

    Navigator.of(context, rootNavigator: true).pop();

    if (response.success != true) {
      throw Exception(response.message ?? 'Server returned failure status');
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response.message ?? 'Success Finish The Job',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green,
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
        Navigator.of(context, rootNavigator: true).pop();

        if (offlineResponse.success == true) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                offlineResponse.message ?? 'Job saved locally. Will sync when online.',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
            ),
          );

          Navigator.pop(context, true);
          return;
        }
      } catch (_) {
        // Fallback failed, show original error below
      }
    }

    // Close loading dialog
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    String errorMessage = 'Failed to finish job';

    if (e is Exception) {
      final exceptionStr = e.toString();
      if (exceptionStr.startsWith('Exception: ')) {
        errorMessage = exceptionStr.substring('Exception: '.length);
      } else {
        errorMessage = exceptionStr;
      }
    } else {
      errorMessage = e.toString();
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
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

  Future<String?> _askForNotes(BuildContext context) async {
  final controller = TextEditingController();
  
  try {
    final result = await showDialog<String>(
      context: context,
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
            label: 'Submit',
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
                        setState(() => selectedIndex = val ? i : -1);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Type additional details (optional)',
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
              label: 'Submit',
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
          backgroundColor: Colors.red,
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

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) {
          const amber = Color(0xFFFF9800);
          return AppDialog(
            icon: Icons.event_repeat,
            accent: amber,
            title: 'Reschedule Job',
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
                      hintText: 'Leave notes here (Required)',
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please provide notes for rescheduling',
                          style: TextStyle(color: Colors.white),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Time cannot be in the past',
                          style: TextStyle(color: Colors.white),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await _jobsController.rescheduleJob(
        jobId: jobId,
        newDate: scheduledDate,
        notes: notes,
      );

      if (!mounted) return null;

      Navigator.of(context).pop(); // Close loading

      final success = response.success == true;
      final isOfflineSave = response.message?.contains('locally') ?? false;
      final message =
          response.message ??
          (success ? 'Job rescheduled successfully' : response.message);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.toString(),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: success
              ? (isOfflineSave ? Colors.orange : Colors.green)
              : Colors.red,
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
      Navigator.of(context).pop(); // Close loading

      // Extract error message
      String errorMessage = 'Failed to reschedule job';
      final exceptionMessage = e.toString();
      if (exceptionMessage.startsWith('Exception: ')) {
        errorMessage = exceptionMessage.substring('Exception: '.length);
      }

      SnackbarUtils(
        text: errorMessage,
        backgroundColor: Colors.red,
      ).showErrorSnackBar(context);
      return false;
    }
  }

  /// Cancels the job with a required reason.
  Future<void> _cancelJob(BuildContext context) async {
    final jobId = widget.job.jobId as int?;

    if (jobId == null) {
      SnackbarUtils(
        text: 'Job ID not found',
        backgroundColor: Colors.red,
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
        text: 'Please provide a reason',
        backgroundColor: Colors.red,
      ).showErrorSnackBar(context);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await _jobsController.cancelJob(
        jobId: jobId,
        reason: reason.trim(),
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      final success = response.success == true;
      final isOfflineSave = response.message?.contains('locally') ?? false;
      final message =
          response.message ??
          (success ? 'Success Cancel Job' : 'Failed to cancel job');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: success
              ? (isOfflineSave ? Colors.orange : Colors.green)
              : Colors.red,
        ),
      );

      if (success) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      log('Failed to cancel job: ${e.toString()}');
      Navigator.of(context).pop();
      SnackbarUtils(
        text: 'Failed to cancel job',
        backgroundColor: Colors.red,
      ).showErrorSnackBar(context);
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

    await _fallbackNavigateUsingDatasource(context);
  }

  Future<void> _fallbackNavigateUsingDatasource(BuildContext context) async {
    final objectId = _extractJobId();
    if (objectId == null) {
      if (!mounted) return;
      SnackbarUtils(
        text: 'Job ID not found',
        backgroundColor: Colors.red,
      ).showErrorSnackBar(context);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final status = await _jobsController.getObjectStatusForJob(objectId);
      final entry = _extractCoordinateEntry(status);

      if (entry == null) {
        throw Exception('Destination coordinate not found');
      }

      final coordinate = _parseCoordinateEntry(entry);

      if (coordinate == null) {
        throw Exception('Invalid coordinate format');
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      if (widget.isOngoing) {
        final launched = await _launchExternalNavigation(context, coordinate);
        if (!launched && mounted) {
          await _openInternalMap(context, coordinate);
        }
      } else {
        await _openInternalMap(context, coordinate);
      }
    } catch (e) {
      if (!mounted) return;
      log('Failed to open navigation: ${e.toString()}');
      Navigator.of(context).pop();
      SnackbarUtils(
        text: 'Failed to open navigation',
        backgroundColor: Colors.red,
      ).showErrorSnackBar(context);
    }
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
        jobName: widget.job.jobName ?? 'Job Destination',
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
            content: Text('Unable to open Google Maps: ${e.toString()}'),
          ),
        );
      }
      return false;
    }
  }

  GeoPoint? _extractJobCoordinates(dynamic job) {
    final latitude = _parseCoordinate(job?.latitude ?? job?.lat);
    final longitude = _parseCoordinate(job?.longitude ?? job?.lng ?? job?.lon);
    if (latitude == null || longitude == null) {
      return null;
    }
    return GeoPoint(latitude, longitude);
  }

  int? _extractJobId() {
    final id = widget.job.jobId;
    if (id is int) return id;
    if (id is String) return int.tryParse(id);
    return null;
  }

  GeoPoint? _parseCoordinateEntry(Map<String, dynamic> entry) {
    final latitude = _parseCoordinate(
      entry['Latitude'] ?? entry['latitude'] ?? entry['Lat'] ?? entry['lat'],
    );
    final longitude = _parseCoordinate(
      entry['Longitude'] ??
          entry['longitude'] ??
          entry['Lon'] ??
          entry['lon'] ??
          entry['Lng'] ??
          entry['lng'],
    );
    if (latitude == null || longitude == null) {
      return null;
    }
    return GeoPoint(latitude, longitude);
  }

  Map<String, dynamic>? _extractCoordinateEntry(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      if (_hasCoordinateKeys(payload)) {
        return payload;
      }

      final data = payload['Data'] ?? payload['data'];
      if (data is List) {
        for (final item in data) {
          final extracted = _extractCoordinateEntry(item);
          if (extracted != null) {
            return extracted;
          }
        }
      }

      final result = payload['Result'] ?? payload['result'];
      if (result is List) {
        for (final item in result) {
          final extracted = _extractCoordinateEntry(item);
          if (extracted != null) {
            return extracted;
          }
        }
      }
    } else if (payload is List) {
      for (final item in payload) {
        final extracted = _extractCoordinateEntry(item);
        if (extracted != null) {
          return extracted;
        }
      }
    }

    return null;
  }

  bool _hasCoordinateKeys(Map<String, dynamic> payload) {
    final lowerKeys = payload.keys.map((k) => k.toLowerCase()).toSet();
    return lowerKeys.contains('latitude') || lowerKeys.contains('lat');
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

