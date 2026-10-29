import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/dispatch_palette.dart';
import '../../../core/widgets/profile_widgets.dart';
import '../../auth/presentation/login_chooser_page.dart';
import '../controller/dispatch_auth_controller.dart';
import 'dispatch_job_history_page.dart';

const String _kAppName = 'JMS';
const String _kAppVersion = '2.0';
const String _kAppBuild = '36';

/// Rider-side profile. A branded green header over theme-aware setting
/// sections — company, job history, appearance (theme picker), sign out.
class DispatchProfilePage extends StatelessWidget {
  const DispatchProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<DispatchAuthController>();
    final palette = context.dispatch;
    return Scaffold(
      backgroundColor: palette.pageSurface,
      body: Obx(() {
        final rider = auth.rider.value;
        final company = auth.company.value;
        final name = rider?.fullname.isNotEmpty == true
            ? rider!.fullname
            : 'Driver';
        final phone = rider?.phone ?? '';
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileBrandHeader(
                name: name,
                subtitle: phone.isEmpty ? 'No phone on file' : phone,
                chipLabel: 'Driver',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (company != null) ...[
                      const ProfileSectionLabel('Company'),
                      ProfileInfoRow(
                        icon: Icons.business_outlined,
                        title: company.name,
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (rider != null) ...[
                      const ProfileSectionLabel('Vehicle'),
                      ProfileInfoRow(
                        icon: Icons.local_shipping_outlined,
                        title: rider.vehicleName ?? 'No vehicle assigned',
                      ),
                      const SizedBox(height: 22),
                    ],
                    const ProfileSectionLabel('Activity'),
                    ProfileActionRow(
                      icon: Icons.history,
                      title: 'Job history',
                      subtitle: 'Review your completed jobs',
                      onTap: () => Get.to(() => const DispatchJobHistoryPage()),
                    ),
                    const SizedBox(height: 22),
                    const ProfileSectionLabel('Appearance'),
                    const ProfileThemeModeTile(),
                    const SizedBox(height: 22),
                    const ProfileSectionLabel('Account'),
                    ProfileActionRow(
                      icon: Icons.logout,
                      title: 'Log out',
                      danger: true,
                      onTap: () => _confirmLogout(context, auth),
                    ),
                    const SizedBox(height: 26),
                    Center(
                      child: Text(
                        '$_kAppName  •  v$_kAppVersion ($_kAppBuild)',
                        style: TextStyle(color: palette.subtle, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _confirmLogout(
    BuildContext context,
    DispatchAuthController auth,
  ) async {
    final ok = await showProfileLogoutDialog(
      context,
      message: 'You will need to sign in again to receive jobs.',
    );
    if (!ok) return;
    await auth.logout();
    // The Profile page sits on top of a Get.to() push, so the chooser is
    // hidden beneath it — replace the whole stack explicitly.
    Get.offAll(() => const LoginChooserPage());
  }
}
