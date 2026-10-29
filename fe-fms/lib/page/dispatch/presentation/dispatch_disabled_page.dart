import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/dispatch_auth_controller.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import '../widget/dispatch_auth_widgets.dart';

/// Dead-end screen shown after a 403 "account disabled" response. The user
/// cannot proceed until they tap dismiss — prevents an immediate retry loop.
class DispatchDisabledPage extends StatelessWidget {
  const DispatchDisabledPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<DispatchAuthController>();
    return Scaffold(
      backgroundColor: context.dispatch.pageSurface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.block, size: 64, color: DispatchColors.danger),
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
              DispatchPrimaryButton(
                label: 'Dismiss',
                onPressed: auth.dismissDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
