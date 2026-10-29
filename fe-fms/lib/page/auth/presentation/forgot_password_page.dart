import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/dispatch_palette.dart';
import '../../dispatch/widget/dispatch_auth_widgets.dart';
import '../../../data/datasource/auth_remote_datasource.dart';

/// Page for requesting a password reset.
///
/// Mirrors the two-wheels [LoginPage] layout — the green brand header plus the
/// shared dispatch form widgets — so the auth surface reads consistently.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _resetSent = false;
  String? _error;
  final _dataSource = AuthRemoteDataSource();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final email = _emailController.text.trim();

    try {
      await _dataSource.forgotPassword(email: email);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _resetSent = true;
      });
    } catch (e) {
      if (!mounted) return;
      final error = e.toString();
      var message = error.startsWith('Exception: ')
          ? error.substring('Exception: '.length)
          : error;
      if (message.trim().isEmpty) {
        message = 'Failed to send reset password';
      }
      setState(() {
        _isLoading = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Scaffold(
      backgroundColor: palette.pageSurface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DispatchBrandHeader(
              icon: Icons.lock_reset,
              title: 'Forgot Password',
              subtitle: 'We\'ll email you a reset link',
              // Pop back to the login page, reversing the slide transition.
              onBack: () => Get.back(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: _resetSent ? _buildSuccessView(palette) : _buildFormView(palette),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormView(DispatchPalette palette) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter the email linked to your account and we\'ll send you a '
            'link to reset your password.',
            style: TextStyle(color: palette.subtle, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 24),
          DispatchTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'Enter your email',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
            autocorrect: false,
            enableSuggestions: false,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Email is required';
              }
              if (!RegExp(
                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
              ).hasMatch(value)) {
                return 'Invalid email address';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            DispatchErrorText(_error!),
          ],
          const SizedBox(height: 24),
          DispatchPrimaryButton(
            label: 'Send Reset Link',
            loading: _isLoading,
            onPressed: _handleResetPassword,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : () => Get.back(),
              child: const Text(
                'Back to login',
                style: TextStyle(
                  color: DispatchColors.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(DispatchPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: DispatchColors.brand.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              size: 42,
              color: DispatchColors.brand,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'If an account exists for ${_emailController.text.trim()}, a reset '
          'link is on its way. Check your inbox — and your spam folder.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.subtle, fontSize: 13.5, height: 1.45),
        ),
        const SizedBox(height: 28),
        DispatchPrimaryButton(
          label: 'Back to login',
          loading: false,
          onPressed: () => Get.back(),
        ),
      ],
    );
  }
}
