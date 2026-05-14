import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../main.dart' show RootGate;
import '../../auth/presentation/login_chooser_page.dart';
import '../../auth/widget/auth_button.dart';
import '../../auth/widget/auth_text_field.dart';
import '../controller/dispatch_auth_controller.dart';
import 'dispatch_activate_page.dart';

/// Phone + password sign-in for dispatch (four-wheels) riders. Visual
/// structure mirrors the legacy two-wheels [LoginPage] so the two surfaces
/// feel like one app — only the header icon differs (car instead of logo)
/// to make the four-wheels surface immediately distinguishable.
class DispatchLoginPage extends StatefulWidget {
  const DispatchLoginPage({super.key});

  @override
  State<DispatchLoginPage> createState() => _DispatchLoginPageState();
}

class _DispatchLoginPageState extends State<DispatchLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() => _obscure = !_obscure);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final auth = Get.find<DispatchAuthController>();
      final deviceName = await DispatchAuthController.defaultDeviceName(
        _phoneCtrl.text.trim(),
      );
      await auth.login(
        phone: _phoneCtrl.text.trim(),
        password: _passwordCtrl.text,
        deviceName: deviceName,
      );
      // Replace the navigator stack with a fresh RootGate so the post-login
      // auth state is re-evaluated cleanly.
      if (mounted) {
        Get.offAll(() => const RootGate());
      }
    } on DispatchApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.colorScheme.onSurface,
        // Always show a back-to-chooser arrow regardless of nav stack state.
        // On a logout-triggered `Get.offAll(DispatchLoginPage)` this page is
        // the root, so the default automatically-implied back button is
        // hidden — that's why we route explicitly via Get.offAll.
        leading: IconButton(
          tooltip: 'Back to sign-in chooser',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.offAll(() => const LoginChooserPage()),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 85,
                          height: 80,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.directions_car_filled_outlined,
                            size: 44,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Welcome',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in as a driver',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  AuthTextField(
                    label: 'Phone',
                    hint: '09XX… or +639XX…',
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    prefixIcon: Icon(
                      Icons.phone_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Phone is required' : null,
                  ),

                  const SizedBox(height: 24),

                  AuthTextField(
                    label: 'Password',
                    hint: 'Fill your password',
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: theme.colorScheme.primary,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: _togglePasswordVisibility,
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Password is required' : null,
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],

                  const SizedBox(height: 24),

                  AuthButton(
                    text: 'Login',
                    onPressed: _submit,
                    isLoading: _submitting,
                    isOutlined: true,
                  ),

                  const SizedBox(height: 12),

                  // Activate-account entry point — kept as a soft TextButton
                  // analogous to "Forgot Password" on the legacy login.
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Get.to(() => const DispatchActivatePage()),
                      child: Text(
                        'First time? Activate account',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
