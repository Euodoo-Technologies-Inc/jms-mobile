import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/services/subscription.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fms/core/constants/variables.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/core/widgets/profile_widgets.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import '../controller/profile_controller.dart';
import '../widget/change_password_dialog.dart';

const String _kAppName = 'JMS';
const String _kAppVersion = '2.0';
const String _kAppBuild = '36';

/// User profile for the two-wheels (legacy E-FMS) surface.
///
/// Mirrors the four-wheels [DispatchProfilePage]: it renders entirely from the
/// identity cached on [AuthController] at login (name, email) plus the company
/// and plan persisted in prefs/subscription — so there is **no network fetch
/// and no loading state** when opening the page. The green brand header and
/// theme-aware sections (including the light/dark theme picker) match the
/// four-wheels design, while keeping the two-wheels features: PRO/BASIC plan,
/// subscription, support, change-password, and logout.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileController _controller;
  final AuthController _auth = Get.find<AuthController>();
  String? _company;

  @override
  void initState() {
    super.initState();
    // Kept alive for change-password (the dialog does Get.find) and logout.
    // It no longer fetches the profile — identity comes from [AuthController].
    _controller = Get.isRegistered<ProfileController>()
        ? Get.find<ProfileController>()
        : Get.put(ProfileController());

    // Company name was persisted at login.
    SharedPreferences.getInstance().then((prefs) {
      final company = prefs.getString(Variables.prefCompany);
      if (mounted) setState(() => _company = company);
    });
  }

  Future<void> _confirmLogout() async {
    final ok = await showProfileLogoutDialog(
      context,
      message: 'Are you sure you want to log out?',
    );
    if (!ok || !mounted) return;
    await _controller.logout(context: context, mounted: mounted);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final isPro = subscriptionService.currentPlan == Plan.pro;

    return Scaffold(
      backgroundColor: palette.pageSurface,
      body: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Identity is cached on AuthController, so it shows immediately.
            Obx(() {
              final name = _auth.fullName.value?.trim();
              final email = _auth.userEmail.value?.trim();
              return ProfileBrandHeader(
                name: (name == null || name.isEmpty) ? 'Unknown' : name,
                subtitle:
                    (email == null || email.isEmpty) ? 'No email on file' : email,
                chipLabel: isPro ? 'Pro' : 'Basic',
              );
            }),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProfileSectionLabel('Company'),
                  ProfileInfoRow(
                    icon: Icons.business_outlined,
                    title: _company ?? 'Unknown company',
                  ),
                  const SizedBox(height: 22),
                  const ProfileSectionLabel('Subscription'),
                  ProfileInfoRow(
                    icon: Icons.workspace_premium_outlined,
                    title: isPro ? 'Pro plan' : 'Basic plan',
                    trailing: _PlanBadge(isPro: isPro),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '${_company ?? "The company"} is subscribed to the '
                      '${isPro ? "Pro" : "Basic"} plan.',
                      style: TextStyle(color: palette.subtle, fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const ProfileSectionLabel('Appearance'),
                  const ProfileThemeModeTile(),
                  const SizedBox(height: 22),
                  const ProfileSectionLabel('Account'),
                  ProfileActionRow(
                    icon: Icons.lock_outline,
                    title: 'Change password',
                    onTap: () => showChangePasswordDialog(context),
                  ),
                  const SizedBox(height: 12),
                  const ProfileInfoRow(
                    icon: Icons.help_outline,
                    title: 'Support',
                    subtitle: 'help@efms.app',
                  ),
                  const SizedBox(height: 12),
                  ProfileActionRow(
                    icon: Icons.logout,
                    title: 'Log out',
                    danger: true,
                    onTap: _confirmLogout,
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
      ),
    );
  }
}

/// A small plan badge shown on the subscription row.
class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.isPro});
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    final color = isPro ? DispatchColors.brand : context.dispatch.subtle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isPro ? 'PRO' : 'BASIC',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
