import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the app-wide theme mode (system / light / dark).
///
/// The initial value follows the OS setting; once the user picks a mode
/// explicitly in the profile page it is persisted and restored on next launch.
class ThemeController extends GetxController {
  static const String _prefKey = 'app.theme_mode';

  /// Current theme mode. Stays on [ThemeMode.system] until [load] restores a
  /// saved choice or the user changes it.
  final Rx<ThemeMode> themeMode = ThemeMode.system.obs;

  /// Restores the persisted choice. Call once before the app builds so the
  /// very first frame already uses the right theme.
  Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode.value = _decode(prefs.getString(_prefKey));
    return this;
  }

  /// Applies a new theme mode immediately and persists it.
  ///
  /// The app applies the resolved [ThemeData] via a plain [Theme] in the
  /// `GetMaterialApp.builder` (driven by [themeMode]) rather than through
  /// `MaterialApp.themeMode`. That swaps the theme in a single frame instead of
  /// running MaterialApp's 200ms `AnimatedTheme` cross-fade, which janks badly
  /// on heavy screens (e.g. the legacy map). So we deliberately do NOT call
  /// `Get.changeThemeMode` here.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == themeMode.value) return;
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.name);
  }

  static ThemeMode _decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
