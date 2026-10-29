import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';

import '../../../core/theme/dispatch_palette.dart';
import 'package:fms/core/utils/user_message.dart';
import '../../dispatch/widget/dispatch_auth_widgets.dart';
import 'forgot_password_page.dart';

/// Email + password sign-in for the two-wheels (legacy E-FMS) surface.
///
/// Mirrors the four-wheels [DispatchLoginPage] layout — the green brand
/// header plus the shared dispatch form widgets — while keeping the
/// two-wheels flow: email login, forgot-password, and [AuthController].
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final authController = Get.find<AuthController>();
      await authController.loginWithCredentials(
        email: _emailController.text,
        password: _passwordController.text,
        context: context,
      );
    } catch (e) {
      // Show the failure inline (e.g. invalid credentials) instead of
      // navigating away — consistent with the four-wheels dispatch login.
      if (mounted) {
        setState(() => _error = userMessage(e));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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
              icon: Icons.two_wheeler,
              title: 'Welcome',
              subtitle: 'Sign in to E-FMS',
              // Pop back to the chooser — reverses the slide-in transition
              // (the chooser always sits beneath this page).
              onBack: () => Get.back(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DispatchTextField(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'name@company.com',
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
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    DispatchTextField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'Your password',
                      obscureText: _obscure,
                      prefixIcon: Icons.lock_outline,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: palette.subtle,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        if (value.length < 4) {
                          return 'Password must be at least 4 characters';
                        }
                        return null;
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _submitting
                            ? null
                            : () => Get.to(() => const ForgotPasswordPage()),
                        child: Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      DispatchErrorText(_error!),
                    ],
                    const SizedBox(height: 16),
                    DispatchPrimaryButton(
                      label: 'Log in',
                      loading: _submitting,
                      onPressed: _handleLogin,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
