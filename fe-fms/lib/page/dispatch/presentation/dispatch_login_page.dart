import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/dispatch/dispatch_api_client.dart';
import '../../../main.dart' show RootGate;
import '../controller/dispatch_auth_controller.dart';
import 'dispatch_activate_page.dart';

/// Phone + password sign-in for dispatch riders.
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
      // Replace the navigator stack with a fresh RootGate. This forces a
      // clean rebuild that reads the post-login auth state, instead of
      // relying on the under-the-hood Obx of the original RootGate to
      // settle in time.
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
      appBar: AppBar(title: const Text('Rider sign-in')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
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
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Get.to(() => const DispatchActivatePage()),
                  child: const Text('First time? Activate account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
