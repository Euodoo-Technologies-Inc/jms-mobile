import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../theme/dispatch_palette.dart';
import '../theme/theme_controller.dart';
import 'app_dialog.dart';

/// Shared, theme-aware building blocks for the profile screens (two-wheels and
/// four-wheels). A single source of truth so both surfaces stay visually
/// identical — branded green header, section labels, info/action rows, the
/// theme-mode picker, and a palette-styled log-out confirmation.

/// Branded green profile header — avatar, name, a subtitle line, and an
/// optional status chip, with a back button + "Profile" title.
class ProfileBrandHeader extends StatelessWidget {
  const ProfileBrandHeader({
    super.key,
    required this.name,
    required this.subtitle,
    this.chipLabel,
    this.onBack,
  });

  final String name;
  final String subtitle;
  final String? chipLabel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final topInset = MediaQuery.of(context).padding.top;
    // Light status-bar icons over the green, whatever the page below set.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        color: DispatchColors.brand,
        padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 48dp back target; the row shifts left so the glyph stays on the
            // 20px edge, and the gaps shrink to absorb the target's padding.
            Transform.translate(
              offset: const Offset(-12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack ?? () => Get.back(),
                    icon: const Icon(Icons.arrow_back,
                        color: DispatchColors.onBrand),
                    tooltip: 'Back',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 48, height: 48),
                  ),
                  Text(
                    'Profile',
                    style: textTheme.titleMedium?.copyWith(
                      color: DispatchColors.onBrand,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
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
                        style: textTheme.headlineSmall?.copyWith(
                          color: DispatchColors.onBrand,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      if (chipLabel != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            // A deeper green, not a lighter one, keeps the 11 pt
                            // white label at 6.7:1.
                            color: Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            chipLabel!.toUpperCase(),
                            style: textTheme.labelSmall?.copyWith(
                              color: DispatchColors.onBrand,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small all-caps section heading.
class ProfileSectionLabel extends StatelessWidget {
  const ProfileSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(letterSpacing: 0.6),
      ),
    );
  }
}

/// A non-interactive labelled value row (e.g. company name). An optional
/// [subtitle] shows under the title, and an optional [trailing] widget shows on
/// the right (e.g. a plan badge).
class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: textTheme.bodySmall),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A tappable settings row.
class ProfileActionRow extends StatelessWidget {
  const ProfileActionRow({
    super.key,
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
    final textTheme = Theme.of(context).textTheme;
    final palette = context.dispatch;
    final tint = danger ? DispatchColors.danger : DispatchColors.brand;
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
                      style: textTheme.titleSmall?.copyWith(
                        color: danger ? tint : palette.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (!danger) Icon(Icons.chevron_right, color: palette.subtle),
            ],
          ),
        ),
      ),
    );
  }
}

/// Theme-mode picker — System (follow the OS), Light, or Dark. Persists the
/// choice via [ThemeController].
class ProfileThemeModeTile extends StatelessWidget {
  const ProfileThemeModeTile({super.key});

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
              Text('Theme', style: Theme.of(context).textTheme.titleSmall),
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
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
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

/// Shows a palette-driven log-out confirmation modal. Returns `true` when the
/// user confirms.
Future<bool> showProfileLogoutDialog(
  BuildContext context, {
  String message = 'You will need to sign in again to continue.',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      icon: Icons.logout,
      accent: DispatchColors.danger,
      title: 'Log out?',
      message: message,
      actions: [
        AppDialogButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        AppDialogButton(
          label: 'Log out',
          filled: true,
          color: DispatchColors.danger,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return ok == true;
}
