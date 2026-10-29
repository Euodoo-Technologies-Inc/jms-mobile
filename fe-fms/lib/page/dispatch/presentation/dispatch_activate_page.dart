import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../core/theme/dispatch_palette.dart';
import '../../../main.dart' show RootGate;
import '../controller/dispatch_auth_controller.dart';
import '../widget/dispatch_auth_widgets.dart';

/// First-time activation: phone + 8-character code from the dispatcher +
/// chosen password.
class DispatchActivatePage extends StatefulWidget {
  const DispatchActivatePage({super.key});

  @override
  State<DispatchActivatePage> createState() => _DispatchActivatePageState();
}

class _DispatchActivatePageState extends State<DispatchActivatePage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
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
      await auth.activate(
        phone: _phoneCtrl.text.trim(),
        code: _codeCtrl.text.trim(),
        newPassword: _passwordCtrl.text,
        deviceName: deviceName,
      );
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
              icon: Icons.vpn_key_outlined,
              title: 'Activate account',
              subtitle: 'Set up your driver sign-in',
              onBack: () => Get.back(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Enter the 8-character code your dispatcher provided, '
                      'along with your phone number, to set a password and '
                      'finish activation.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
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
                      controller: _codeCtrl,
                      label: '8-character code',
                      hint: 'e.g. K7M2QXR4',
                      keyboardType: TextInputType.visiblePassword,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      prefixIcon: Icons.confirmation_number_outlined,
                      inputFormatters: [
                        // Backend alphabet excludes 0/1/I/O to avoid
                        // lookalikes.
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-HJ-NP-Za-hj-np-z2-9]'),
                        ),
                        _UpperCaseTextFormatter(),
                        LengthLimitingTextInputFormatter(8),
                      ],
                      validator: (v) => (v == null || v.trim().length != 8)
                          ? 'Enter the 8-character code'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    DispatchTextField(
                      controller: _passwordCtrl,
                      label: 'New password',
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
                      validator: (v) => (v == null || v.length < 8)
                          ? 'At least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    DispatchTextField(
                      controller: _confirmCtrl,
                      label: 'Confirm password',
                      obscureText: _obscure,
                      prefixIcon: Icons.lock_outline,
                      validator: (v) => v != _passwordCtrl.text
                          ? 'Passwords do not match'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      DispatchErrorText(_error!),
                    ],
                    const SizedBox(height: 24),
                    DispatchPrimaryButton(
                      label: 'Activate',
                      loading: _submitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'If activation keeps failing, contact your dispatcher.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
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

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
