import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/dispatch_palette.dart';
import '../../dispatch/presentation/dispatch_login_page.dart';
import 'login_page.dart';

/// First screen for unauthenticated users — choose which surface to sign in:
///   - Two-wheels → legacy LoginPage
///   - Four-wheels → DispatchLoginPage
class LoginChooserPage extends StatelessWidget {
  const LoginChooserPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return Scaffold(
      backgroundColor: palette.pageSurface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 28),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: DispatchColors.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.asset(
                        // The original purple/blue logo — matches the app
                        // launcher icon. (logo.png was later recolored yellow.)
                        'assets/images/logo_original.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Welcome',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'How are you signing in today?',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.subtle, fontSize: 14),
              ),
              const SizedBox(height: 40),
              _ChoiceCard(
                icon: Icons.two_wheeler,
                title: 'Two-wheels',
                subtitle: 'Motorcycle / bike sign-in',
                onTap: () => Get.to(() => const LoginPage()),
              ),
              const SizedBox(height: 14),
              _ChoiceCard(
                icon: Icons.directions_car_filled_outlined,
                title: 'Four-wheels',
                subtitle: 'Dispatch rider sign-in',
                onTap: () => Get.to(() => const DispatchLoginPage()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    // Plain tap target — no ink ripple/splash, just the card.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DispatchColors.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 28, color: DispatchColors.brand),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: palette.subtle,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: palette.subtle),
          ],
        ),
      ),
    );
  }
}
