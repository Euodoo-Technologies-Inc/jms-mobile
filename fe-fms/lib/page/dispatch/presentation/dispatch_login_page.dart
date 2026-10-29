import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/theme/dispatch_palette.dart';
import '../../../main.dart' show RootGate;
import '../controller/dispatch_auth_controller.dart';
import '../widget/dispatch_auth_widgets.dart';
import 'dispatch_activate_page.dart';

/// Phone + password sign-in for dispatch (four-wheels) riders.
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
    final palette = context.dispatch;
    return Scaffold(
      backgroundColor: palette.pageSurface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DispatchBrandHeader(
              icon: Icons.directions_car_filled_outlined,
              title: 'Welcome',
              subtitle: 'Sign in as a driver',
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
                      controller: _phoneCtrl,
                      label: 'Phone',
                      hint: '09XX… or +639XX…',
                      keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Phone is required'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    DispatchTextField(
                      controller: _passwordCtrl,
                      label: 'Password',
                      hint: 'Enter your password',
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
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Password is required'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      DispatchErrorText(_error!),
                    ],
                    const SizedBox(height: 24),
                    DispatchPrimaryButton(
                      label: 'Log in',
                      loading: _submitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _submitting
                            ? null
                            : () =>
                                Get.to(() => const DispatchActivatePage()),
                        child: const Text(
                          'First time? Activate account',
                          style: TextStyle(
                            color: DispatchColors.brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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
