import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/core/utils/user_message.dart';
import 'package:fms/core/widgets/app_dialog.dart';
import 'package:fms/core/widgets/app_feedback.dart';
import 'package:fms/page/dispatch/widget/dispatch_auth_widgets.dart';
import 'package:fms/page/profile/controller/profile_controller.dart';

/// Shows a dialog that lets the user change their password.
///
/// Uses [StatefulBuilder] to manage local form state (visibility toggles,
/// loading indicator) without requiring a dedicated StatefulWidget.
Future<void> showChangePasswordDialog(BuildContext context) {
  final controller = Get.find<ProfileController>();
  final formKey = GlobalKey<FormState>();
  final currentPasswordCtrl = TextEditingController();
  final newPasswordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();

  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ChangePasswordDialogContent(
      formKey: formKey,
      currentPasswordCtrl: currentPasswordCtrl,
      newPasswordCtrl: newPasswordCtrl,
      confirmPasswordCtrl: confirmPasswordCtrl,
      controller: controller,
    ),
  );
}

class _ChangePasswordDialogContent extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController currentPasswordCtrl;
  final TextEditingController newPasswordCtrl;
  final TextEditingController confirmPasswordCtrl;
  final ProfileController controller;

  const _ChangePasswordDialogContent({
    required this.formKey,
    required this.currentPasswordCtrl,
    required this.newPasswordCtrl,
    required this.confirmPasswordCtrl,
    required this.controller,
  });

  @override
  State<_ChangePasswordDialogContent> createState() =>
      _ChangePasswordDialogContentState();
}

class _ChangePasswordDialogContentState
    extends State<_ChangePasswordDialogContent> {
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    widget.currentPasswordCtrl.dispose();
    widget.newPasswordCtrl.dispose();
    widget.confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final message = await widget.controller.changePassword(
        currentPassword: widget.currentPasswordCtrl.text.trim(),
        newPassword: widget.newPasswordCtrl.text.trim(),
        confirmPassword: widget.confirmPasswordCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);

      AppFeedback.success(message);
    } catch (e) {
      if (!mounted) return;
      // Inline, inside the dialog: a page snackbar sits under the barrier.
      setState(() {
        _isLoading = false;
        _error = userMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.lock_outline,
      accent: DispatchColors.brand,
      title: 'Change password',
      message: 'Use at least 8 characters.',
      content: Form(
        key: widget.formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _passwordField(
              controller: widget.currentPasswordCtrl,
              label: 'Current password',
              icon: Icons.lock_outline,
              obscure: _obscureCurrent,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Current password is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: widget.newPasswordCtrl,
              label: 'New password',
              icon: Icons.lock_reset_outlined,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'New password is required';
                }
                if (value.trim().length < 8) {
                  return 'Password must be at least 8 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: widget.confirmPasswordCtrl,
              label: 'Confirm new password',
              icon: Icons.lock_reset_outlined,
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Confirm your new password';
                }
                if (value.trim() != widget.newPasswordCtrl.text.trim()) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              DispatchErrorText(_error!),
            ],
          ],
        ),
      ),
      actions: [
        AppDialogButton(
          label: 'Cancel',
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        AppDialogButton(
          label: 'Update',
          filled: true,
          busy: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
      ],
    );
  }

  /// A theme-aware obscured password field with a visibility toggle, styled to
  /// match the rest of the profile surface.
  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    final palette = context.dispatch;
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: DispatchColors.brand, size: 20),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show password' : 'Hide password',
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: palette.subtle,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}
