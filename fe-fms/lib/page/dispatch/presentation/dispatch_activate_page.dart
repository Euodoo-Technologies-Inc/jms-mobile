import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../main.dart' show RootGate;
import '../controller/dispatch_auth_controller.dart';

/// First-time activation: phone + 6-digit code from admin + chosen password.
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
      // Replace the navigator stack with a fresh RootGate so the post-auth
      // state is read cleanly (instead of relying on the under-the-hood
      // Obx swap of the original RootGate to settle in time).
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
    return Scaffold(
      appBar: AppBar(title: const Text('Activate account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter the 8-character code your dispatcher provided, '
                  'along with your phone number, to set a password '
                  'and finish activation.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    hintText: '09XX… or +639XX…',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.visiblePassword,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [
                    // Backend alphabet excludes 0/1/I/O to avoid lookalikes.
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[A-HJ-NP-Za-hj-np-z2-9]'),
                    ),
                    _UpperCaseTextFormatter(),
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: const InputDecoration(
                    labelText: '8-character code',
                    hintText: 'e.g. K7M2QXR4',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().length != 8)
                      ? 'Enter the 8-character code'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'At least 8 characters'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v != _passwordCtrl.text
                      ? 'Passwords do not match'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Activate'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'If activation keeps failing, contact your dispatcher.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
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
