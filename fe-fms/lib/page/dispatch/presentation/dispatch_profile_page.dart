import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/dispatch_palette.dart';
import '../../../core/theme/theme_controller.dart';
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
              _ProfileHeader(name: name, phone: phone),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (company != null) ...[
                      const _SectionLabel('Company'),
                      _InfoRow(
                        icon: Icons.business_outlined,
                        title: company.name,
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (rider != null) ...[
                      const _SectionLabel('Vehicle'),
                      _InfoRow(
                        icon: Icons.local_shipping_outlined,
                        title: rider.vehicleName ?? 'No vehicle assigned',
                      ),
                      const SizedBox(height: 22),
                    ],
                    const _SectionLabel('Activity'),
                    _ActionRow(
                      icon: Icons.history,
                      title: 'Job history',
                      subtitle: 'Review your completed jobs',
                      onTap: () =>
                          Get.to(() => const DispatchJobHistoryPage()),
                    ),
                    const SizedBox(height: 22),
                    const _SectionLabel('Appearance'),
                    const _ThemeModeTile(),
                    const SizedBox(height: 22),
                    const _SectionLabel('Account'),
                    _ActionRow(
                      icon: Icons.logout,
                      title: 'Log out',
                      danger: true,
                      onTap: () => _confirmLogout(context, auth),
                    ),
                    const SizedBox(height: 26),
                    Center(
                      child: Text(
                        '$_kAppName  •  v$_kAppVersion ($_kAppBuild)',
                        style: Theme.of(context).textTheme.bodySmall,
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
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => const _LogoutConfirmDialog(),
    );
    if (ok != true) return;
    await auth.logout();
    // The Profile page sits on top of a Get.to() push, so the chooser is
    // hidden beneath it — replace the whole stack explicitly.
    Get.offAll(() => const LoginChooserPage());
  }
}

/// Palette-driven log-out confirmation modal — replaces the default
/// `AlertDialog` so the surface, text, and buttons match the dispatch theme
/// in both light and dark mode.
class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  static const Color _danger = Color(0xFFdc2626);

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Dialog(
      backgroundColor: palette.card,
      surfaceTintColor: palette.card,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.cardBorder),
      ),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _danger.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.logout,
                      color: _danger,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Log out?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'You will need to sign in again to receive jobs.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.ink,
                          side: BorderSide(color: palette.cardBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: Theme.of(context).textTheme.titleSmall,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: _danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Log out'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Branded green header — avatar, name, phone, role chip, with a back button.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      color: DispatchColors.brand,
      padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Get.back(),
                icon: const Icon(Icons.arrow_back,
                    color: DispatchColors.onBrand),
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Text(
                'Profile',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: DispatchColors.onBrand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.person,
                    color: DispatchColors.onBrand, size: 34),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: DispatchColors.onBrand,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      phone.isEmpty ? 'No phone on file' : phone,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'DRIVER',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: DispatchColors.onBrand,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small all-caps section heading.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A non-interactive labelled value row (e.g. company name).
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: DispatchColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable settings row.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final tint = danger ? const Color(0xFFdc2626) : DispatchColors.brand;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.cardBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: danger ? tint : palette.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (!danger)
                Icon(Icons.chevron_right, color: palette.subtle),
            ],
          ),
        ),
      ),
    );
  }
}

/// Theme-mode picker — System (follow the OS), Light, or Dark.
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    final theme = Get.find<ThemeController>();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.brightness_6_outlined,
                  size: 20, color: DispatchColors.brand),
              const SizedBox(width: 12),
              Text(
                'Theme',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                // Match the hairline borders used elsewhere on the page,
                // rather than the heavier default outline.
                style: ButtonStyle(
                  side: WidgetStateProperty.all(
                    BorderSide(color: palette.cardBorder),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(
                      value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(
                      value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {theme.themeMode.value},
                onSelectionChanged: (s) => theme.setThemeMode(s.first),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
