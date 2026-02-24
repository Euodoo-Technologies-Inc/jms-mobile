import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/widgets/snackbar_utils.dart';
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

  @override
  void dispose() {
    widget.currentPasswordCtrl.dispose();
    widget.newPasswordCtrl.dispose();
    widget.confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final message = await widget.controller.changePassword(
        currentPassword: widget.currentPasswordCtrl.text.trim(),
        newPassword: widget.newPasswordCtrl.text.trim(),
        confirmPassword: widget.confirmPasswordCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);

      SnackbarUtils(
        text: message,
        backgroundColor: Colors.green,
        icon: Icons.check_circle,
      ).showSuccessSnackBar(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      SnackbarUtils(
        text: errorMsg,
        backgroundColor: Colors.red,
        icon: Icons.error,
      ).showErrorSnackBar(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: SingleChildScrollView(
        child: Form(
          key: widget.formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: widget.currentPasswordCtrl,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureCurrent
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Current password is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.newPasswordCtrl,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
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
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.confirmPasswordCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please confirm your new password';
                  }
                  if (value.trim() != widget.newPasswordCtrl.text.trim()) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Change Password'),
        ),
      ],
    );
  }
}
