import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/dispatch/dispatch_constants.dart';
import '../controller/dispatch_jobs_controller.dart';

/// Photos (≤ 5, ≤ 4 MB each, image only) + optional notes, then submit.
class DispatchFinishJobPage extends StatefulWidget {
  const DispatchFinishJobPage({super.key, required this.jobId});

  final int jobId;

  @override
  State<DispatchFinishJobPage> createState() => _DispatchFinishJobPageState();
}

class _DispatchFinishJobPageState extends State<DispatchFinishJobPage> {
  final _picker = ImagePicker();
  final _notesCtrl = TextEditingController();
  final List<File> _photos = [];
  bool _submitting = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_photos.length >= DispatchConstants.maxPhotos) {
      _toast('Maximum ${DispatchConstants.maxPhotos} photos.');
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
      _toast('Image picker failed: $e');
    }
  }

  Future<void> _maybeAdd(File file) async {
    final size = await file.length();
    if (size > DispatchConstants.maxPhotoBytes) {
      _toast(
        '${file.uri.pathSegments.last} is over '
        '${(DispatchConstants.maxPhotoBytes / 1024 / 1024).toStringAsFixed(0)} MB.',
      );
      return;
    }
    _photos.add(file);
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await Get.find<DispatchJobsController>().finishJob(
        widget.jobId,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        photos: _photos,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job finished.')),
      );
      Navigator.of(context).pop(true);
    } on DispatchQueuedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved offline. Will sync when online.'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.of(context).pop(true);
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finish job')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Proof of work'),
              const SizedBox(height: 8),
              _PhotoGrid(
                photos: _photos,
                onRemove: (f) => setState(() => _photos.remove(f)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_photos.length}/${DispatchConstants.maxPhotos} photos',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _notesCtrl,
                maxLines: 4,
                maxLength: DispatchConstants.maxNotesLength,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(
                    DispatchConstants.maxNotesLength,
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: const Text('Submit'),
              ),
            ],
          ),
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
    if (photos.isEmpty) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        alignment: Alignment.center,
        child: const Text(
          'No photos yet',
          style: TextStyle(color: Colors.grey),
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
              borderRadius: BorderRadius.circular(8),
              child: Image.file(f, fit: BoxFit.cover),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: InkWell(
                onTap: () => onRemove(f),
                child: const CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
