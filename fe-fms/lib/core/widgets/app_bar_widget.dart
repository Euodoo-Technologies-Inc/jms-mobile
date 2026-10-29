import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../page/profile/presentation/profile_page.dart';
import '../../core/constants/variables.dart';
import '../theme/dispatch_palette.dart';

class AppBarWidget extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  const AppBarWidget({super.key, required this.title});

  /// Standard toolbar height — matches the detail pages' app bars so the main
  /// screens and the pages they push to share one consistent bar size.
  static const double _height = kToolbarHeight;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  State<AppBarWidget> createState() => _AppBarWidgetState();
}

class _AppBarWidgetState extends State<AppBarWidget> {
  late final Future<String?> _logoFuture;

  @override
  void initState() {
    super.initState();
    _logoFuture = _getCompanyLogo();
  }

  Future<String?> _getCompanyLogo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(Variables.companyLogo);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return AppBar(
      toolbarHeight: AppBarWidget._height,
      backgroundColor: palette.pageSurface,
      surfaceTintColor: palette.pageSurface,
      foregroundColor: palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      shape: Border(bottom: BorderSide(color: palette.cardBorder)),
      title: Text(
        widget.title,
        style: TextStyle(
          color: palette.ink,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      leadingWidth: 52,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: FutureBuilder<String?>(
            future: _logoFuture,
            builder: (context, snapshot) {
              final logoUrl = snapshot.data;

              if (logoUrl != null && logoUrl.isNotEmpty) {
                log('Loading company logo: $logoUrl',
                    name: 'AppBarWidget', level: 800);
                return Image.network(
                  logoUrl,
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (_, error, _) {
                    log('Company logo failed to load: $error (url: $logoUrl)',
                        name: 'AppBarWidget', level: 900);
                    return _defaultLogo();
                  },
                );
              }

              if (snapshot.connectionState == ConnectionState.done) {
                log('No company logo URL stored in SharedPreferences',
                    name: 'AppBarWidget', level: 900);
              }
              return _defaultLogo();
            },
          ),
        ),
      ),
      actions: [
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 22,
          icon: const Icon(Icons.person_outline),
          onPressed: () {
            Get.to(
              () => const ProfilePage(),
              transition: Transition.rightToLeft,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _defaultLogo() {
    return Image.asset(
      'assets/images/logo.png',
      width: 32,
      height: 32,
      fit: BoxFit.contain,
    );
  }
}
