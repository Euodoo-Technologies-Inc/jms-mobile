import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
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
    final palette = context.dispatch;
    return Dialog(
      backgroundColor: palette.card,
      surfaceTintColor: palette.card,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.cardBorder),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Form(
              key: widget.formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header — brand badge + title + supporting line.
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: DispatchColors.brand.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_outline,
                            color: DispatchColors.brand, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Change password',
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Use at least 8 characters.',
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
                  const SizedBox(height: 22),
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
                        return 'Please confirm your new password';
                      }
                      if (value.trim() != widget.newPasswordCtrl.text.trim()) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            onPressed:
                                _isLoading ? null : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: palette.ink,
                              side: BorderSide(color: palette.cardBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: DispatchColors.brand,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Update'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
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
