import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/dispatch_auth_controller.dart';

/// Dead-end screen shown after a 403 "account disabled" response. The user
/// cannot proceed until they tap dismiss — prevents an immediate retry loop.
class DispatchDisabledPage extends StatelessWidget {
  const DispatchDisabledPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<DispatchAuthController>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.block, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Obx(
                () => Text(
                  auth.disabledMessage.value.isEmpty
                      ? 'Account disabled. Contact your dispatcher.'
                      : auth.disabledMessage.value,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: auth.dismissDisabled,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
