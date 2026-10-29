import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/dispatch_palette.dart';
import '../widgets/app_dialog.dart';

/// Helper class for managing application permissions.
class AppPermission {
  /// Ensures that the application has permission to access photos/storage.
  ///
  /// Returns `true` if permission is granted, `false` otherwise.
  static Future<bool> ensurePhotosPermission(BuildContext context) async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) {
        final goToSettings = await _showSettingsDialog(
          context,
          'Application requires access to Storage/Photo to upload proof of work. Open Settings to grant permission.',
        );
        if (goToSettings) {
          await openAppSettings();
        }
      }
      return false;
    } else {
      // Android 13+: request dedicated photos permission. Older versions still rely on storage permission.
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isGranted || photosStatus.isLimited) {
        return true;
      }

      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) {
        return true;
      }

      if (photosStatus.isPermanentlyDenied ||
          storageStatus.isPermanentlyDenied) {
        final goToSettings = await _showSettingsDialog(
          context,
          'Application requires access to Storage/Photo to upload proof of work. Open Settings to grant permission.',
        );
        if (goToSettings) {
          await openAppSettings();
        }
      }
      return false;
    }
  }

  static Future<bool> _showSettingsDialog(
    BuildContext context,
    String message,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AppDialog(
            icon: Icons.photo_library_outlined,
            accent: DispatchColors.brand,
            title: 'Permission Required',
            message: message,
            actions: [
              AppDialogButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              AppDialogButton(
                label: 'Open Settings',
                filled: true,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ) ??
        false;
  }
}
