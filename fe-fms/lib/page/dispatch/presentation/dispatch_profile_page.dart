import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/presentation/login_chooser_page.dart';
import '../controller/dispatch_auth_controller.dart';
import 'dispatch_job_history_page.dart';

/// Rider-side profile. Mirrors the legacy ProfilePage layout (Card-stacked
/// list, top avatar header, red logout at the bottom) so the two surfaces
/// feel like one app. Hosts the entry points the dispatch jobs screen used
/// to put in its AppBar — Completed jobs (history) and Sign out.
class DispatchProfilePage extends StatelessWidget {
  const DispatchProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<DispatchAuthController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Obx(() {
            final rider = auth.rider.value;
            final company = auth.company.value;
            final name = rider?.fullname.isNotEmpty == true
                ? rider!.fullname
                : 'Driver';
            final phone = rider?.phone ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      radius: 26,
                      child: Icon(Icons.person),
                    ),
                    title: Text(name),
                    subtitle: Text(phone.isEmpty ? 'No phone on file' : phone),
                    trailing: company == null
                        ? null
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'DRIVER',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                  ),
                ),
                if (company != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Company',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            company.name,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Job history'),
                    subtitle: const Text('Review your completed jobs'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Get.to(() => const DispatchJobHistoryPage()),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text(
                      'Log out',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () => _confirmLogout(context, auth),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'JMS v2.0',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(
    BuildContext context,
    DispatchAuthController auth,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await auth.logout();
    // RootGate would settle back to the chooser once the Obx rebuilds, but
    // this Profile page sits on top of the navigator from a Get.to() push —
    // so the chooser is hidden beneath it. Replace the whole stack with the
    // chooser explicitly so the user lands there.
    Get.offAll(() => const LoginChooserPage());
  }
}
