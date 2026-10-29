import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fms/core/utils/user_message.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';
import '../../../core/theme/dispatch_palette.dart';
import '../controller/dispatch_jobs_controller.dart';
import '../service/dispatch_notice_service.dart';

/// Photos (≤ 5, ≤ 4 MB each, image only) + optional notes, then submit.
///
/// Palette-driven layout matching the profile / history / overview pages —
/// hairline app bar, section labels, bordered card blocks.
class DispatchFinishJobPage extends StatefulWidget {
  const DispatchFinishJobPage({super.key, required this.jobId});

  final int jobId;

  @override
  State<DispatchFinishJobPage> createState() => _DispatchFinishJobPageState();
}

class _DispatchFinishJobPageState extends State<DispatchFinishJobPage> {
  final _picker = ImagePicker();
  final _notesCtrl = TextEditingController();
  final _meterCtrl = TextEditingController();
  final List<File> _photos = [];
  bool _submitting = false;

  DispatchNoticeController get _notices =>
      Get.find<DispatchNoticeController>();

  bool get _hasEnoughPhotos => _photos.length >= DispatchConstants.minPhotos;
  bool get _hasMeter => _meterCtrl.text.trim().isNotEmpty;
  bool get _canSubmit => _hasEnoughPhotos && _hasMeter && !_submitting;
  bool get _hasInput =>
      _photos.isNotEmpty || _hasMeter || _notesCtrl.text.trim().isNotEmpty;

  /// Back with a half-filled form asks first instead of silently dropping
  /// the photos, meter number and notes. Blocked outright mid-submit.
  Future<void> _onBack(bool didPop, Object? _) async {
    if (didPop || _submitting) return;
    if (!_hasInput) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this finish?'),
        content: const Text(
          'Your photos, meter number and notes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    // Submit button reacts to meter input live (notes don't gate submit).
    _meterCtrl.addListener(_onMeterChanged);
  }

  void _onMeterChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _meterCtrl.removeListener(_onMeterChanged);
    _notesCtrl.dispose();
    _meterCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_photos.length >= DispatchConstants.maxPhotos) {
      _notices.info('Maximum ${DispatchConstants.maxPhotos} photos.');
      return;
    }
    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(
          maxWidth: 2048,
          imageQuality: 85,
        );
        for (final x in picked) {
          if (_photos.length >= DispatchConstants.maxPhotos) break;
          await _maybeAdd(File(x.path));
        }
      } else {
        final x = await _picker.pickImage(
          source: source,
          maxWidth: 2048,
          imageQuality: 85,
        );
        if (x != null) await _maybeAdd(File(x.path));
      }
      if (mounted) setState(() {});
    } catch (e) {
      // Usually a denied camera or photos permission.
      _notices.error(
        "Couldn't open the camera or gallery. "
        'Allow camera and photo access in Settings and try again.',
      );
    }
  }

  Future<void> _maybeAdd(File file) async {
    final size = await file.length();
    if (size > DispatchConstants.maxPhotoBytes) {
      _notices.info(
        '${file.uri.pathSegments.last} is over '
        '${(DispatchConstants.maxPhotoBytes / 1024 / 1024).toStringAsFixed(0)} MB.',
      );
      return;
    }
    _photos.add(file);
  }

  Future<void> _submit() async {
    if (!_hasEnoughPhotos) {
      _notices.info(
        'Add at least ${DispatchConstants.minPhotos} photos.',
      );
      return;
    }
    if (!_hasMeter) {
      _notices.info('Enter the meter number.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final meter = _meterCtrl.text.trim();
      await Get.find<DispatchJobsController>().finishJob(
        widget.jobId,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        meterNumber: meter.isEmpty ? null : meter,
        photos: _photos,
      );
      if (!mounted) return;
      _notices.success('Job finished.');
      Navigator.of(context).pop(true);
    } on DispatchQueuedException {
      if (!mounted) return;
      _notices.info('Saved offline. Will sync when online.');
      Navigator.of(context).pop(true);
    } on DispatchApiException catch (e) {
      if (!mounted) return;
      if (e.isConflict) {
        _notices.info(userMessage(e));
      } else {
        _notices.error(userMessage(e));
      }
    } catch (e) {
      if (!mounted) return;
      _notices.error(userMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: Scaffold(
        backgroundColor: palette.pageSurface,
        appBar: AppBar(
          backgroundColor: palette.pageSurface,
          surfaceTintColor: palette.pageSurface,
          foregroundColor: palette.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: Border(bottom: BorderSide(color: palette.cardBorder)),
          title: const Text(
            'Finish job',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('Proof of work'),
                _PhotoGrid(
                  photos: _photos,
                  onRemove: (f) => setState(() => _photos.remove(f)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _PhotoPickButton(
                        icon: Icons.photo_camera_outlined,
                        label: 'Camera',
                        onPressed: _submitting
                            ? null
                            : () => _pick(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PhotoPickButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        onPressed: _submitting
                            ? null
                            : () => _pick(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _PhotoCounter(
                  count: _photos.length,
                  min: DispatchConstants.minPhotos,
                  max: DispatchConstants.maxPhotos,
                ),
                const SizedBox(height: 22),
                const _SectionLabel('Meter number'),
                _PaletteTextField(
                  controller: _meterCtrl,
                  hint: 'Enter meter reading',
                  maxLength: 64,
                  inputFormatters: [LengthLimitingTextInputFormatter(64)],
                ),
                const SizedBox(height: 22),
                const _SectionLabel('Notes (optional)'),
                _PaletteTextField(
                  controller: _notesCtrl,
                  hint: 'Add a note about this job',
                  maxLines: 4,
                  maxLength: DispatchConstants.maxNotesLength,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                      DispatchConstants.maxNotesLength,
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: DispatchColors.brand,
                      foregroundColor: DispatchColors.onBrand,
                      disabledBackgroundColor:
                          DispatchColors.brand.withValues(alpha: 0.4),
                      disabledForegroundColor:
                          DispatchColors.onBrand.withValues(alpha: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _canSubmit ? _submit : null,
                    icon: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: DispatchColors.onBrand,
                            ),
                          )
                        : const Icon(Icons.check, size: 20),
                    label: const Text('Finish job'),
                  ),
                ),
                if (!_hasEnoughPhotos || !_hasMeter) ...[
                  const SizedBox(height: 10),
                  _MissingRequirementsHint(
                    needsPhotos: !_hasEnoughPhotos,
                    needsMeter: !_hasMeter,
                    minPhotos: DispatchConstants.minPhotos,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small all-caps section heading — matches the profile / history pages.
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

/// Tiny "n/max photos" indicator that turns green once the rider has reached
/// the minimum, so the gating threshold is obvious.
class _PhotoCounter extends StatelessWidget {
  const _PhotoCounter({
    required this.count,
    required this.min,
    required this.max,
  });

  final int count;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final met = count >= min;
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.info_outline,
          size: 14,
          color: met ? Theme.of(context).colorScheme.primary : palette.subtle,
        ),
        const SizedBox(width: 6),
        Text(
          '$count/$max photos',
          style: TextStyle(
            color: met ? Theme.of(context).colorScheme.primary : palette.subtle,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '(min $min)',
          style: TextStyle(
            color: palette.subtle,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// Subtle reminder shown beneath the submit button explaining which
/// requirements are not yet met. Replaces the silent disabled state.
class _MissingRequirementsHint extends StatelessWidget {
  const _MissingRequirementsHint({
    required this.needsPhotos,
    required this.needsMeter,
    required this.minPhotos,
  });

  final bool needsPhotos;
  final bool needsMeter;
  final int minPhotos;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final missing = <String>[
      if (needsPhotos) 'at least $minPhotos photos',
      if (needsMeter) 'a meter number',
    ];
    if (missing.isEmpty) return const SizedBox.shrink();
    final text = 'Add ${missing.join(' and ')} to finish this job.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 14, color: palette.subtle),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: palette.subtle,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// A palette-styled outlined button used for the camera / gallery pickers.
class _PhotoPickButton extends StatelessWidget {
  const _PhotoPickButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final disabled = onPressed == null;
    final tint = disabled
        ? palette.subtle
        : DispatchColors.brand;
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: tint,
          side: BorderSide(color: palette.cardBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// A palette-styled `TextField`.
class _PaletteTextField extends StatelessWidget {
  const _PaletteTextField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      cursorColor: DispatchColors.brand,
      style: TextStyle(color: palette.ink, fontSize: 14.5),
      decoration: InputDecoration(
        counterStyle: TextStyle(color: palette.subtle, fontSize: 11),
        hintText: hint,
        hintStyle: TextStyle(color: palette.subtle, fontSize: 14),
        filled: true,
        fillColor: palette.pageSurface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DispatchColors.brand, width: 1.5),
        ),
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos, required this.onRemove});
  final List<File> photos;
  final void Function(File) onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    if (photos.isEmpty) {
      return Container(
        height: 96,
        decoration: BoxDecoration(
          color: palette.pageSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.cardBorder),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 28, color: palette.subtle),
            const SizedBox(height: 6),
            Text(
              'No photos yet',
              style: TextStyle(color: palette.subtle, fontSize: 12.5),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, i) {
        final f = photos[i];
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(f, fit: BoxFit.cover),
            ),
            // 48dp target in the corner; the 22px badge keeps its 4px inset.
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Remove photo',
                onPressed: () => onRemove(f),
                alignment: Alignment.topRight,
                padding: const EdgeInsets.all(4),
                constraints:
                    const BoxConstraints.tightFor(width: 48, height: 48),
                icon: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
