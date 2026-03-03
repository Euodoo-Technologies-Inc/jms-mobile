import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../page/profile/presentation/profile_page.dart';
import '../../core/constants/variables.dart';

class AppBarWidget extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  const AppBarWidget({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

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
    return AppBar(
      title: Text(widget.title),
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FutureBuilder<String?>(
            future: _logoFuture,
            builder: (context, snapshot) {
              final logoUrl = snapshot.data;

              if (logoUrl != null && logoUrl.isNotEmpty) {
                log('Loading company logo: $logoUrl',
                    name: 'AppBarWidget', level: 800);
                return Image.network(
                  logoUrl,
                  width: 25,
                  height: 25,
                  fit: BoxFit.cover,
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
          icon: const Icon(Icons.person),
          onPressed: () {
            Get.to(() => const ProfilePage());
          },
        ),
      ],
    );
  }

  Widget _defaultLogo() {
    return Image.asset(
      'assets/images/logo.png',
      width: 25,
      height: 25,
      fit: BoxFit.cover,
    );
  }
}
