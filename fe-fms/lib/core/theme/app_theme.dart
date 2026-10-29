import 'package:flutter/material.dart';

import 'dispatch_palette.dart';

/// Defines the application's theme configuration. Every colour comes from
/// [DispatchColors] / [DispatchPalette], so Material defaults (spinners,
/// refresh indicators, focus rings, buttons, chips) render in the brand green.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(
    DispatchPalette.light,
    Brightness.light,
    Typography.blackMountainView,
  );

  static ThemeData dark() => _build(
    DispatchPalette.dark,
    Brightness.dark,
    Typography.whiteMountainView,
  );

  static ThemeData _build(
    DispatchPalette palette,
    Brightness brightness,
    TextTheme typography,
  ) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: DispatchColors.brand,
      // Light mode uses the brand green itself; dark mode keeps the seeded,
      // lighter green so it stays legible as text on dark surfaces.
      primary: brightness == Brightness.light ? DispatchColors.brand : null,
      error: DispatchColors.danger,
      surface: palette.pageSurface,
      brightness: brightness,
    );

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: palette.cardBorder),
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.pageSurface,
      // Matches the hand-styled app bars (AppBarWidget, DetailScaffold).
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: palette.pageSurface,
        surfaceTintColor: palette.pageSurface,
        foregroundColor: palette.ink,
        centerTitle: true,
        shape: Border(bottom: BorderSide(color: palette.cardBorder)),
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.card,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
        ),
      ),
      // The type scale. Call sites use these roles (with `copyWith` for a
      // one-off weight or colour), never raw font sizes.
      textTheme: typography.copyWith(
        // Screen headline: sign-in screens, dashboard figures.
        headlineMedium: TextStyle(
          color: palette.ink,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        // Hero title at the top of a page or sheet.
        headlineSmall: TextStyle(
          color: palette.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        // App bar, dialog and card titles.
        titleLarge: TextStyle(
          color: palette.ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        // Section titles.
        titleMedium: TextStyle(
          color: palette.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        // List-item and row titles.
        titleSmall: TextStyle(
          color: palette.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: palette.ink, fontSize: 16, height: 1.3),
        bodyMedium: TextStyle(
          color: palette.subtle,
          fontSize: 14,
          height: 1.25,
        ),
        // Secondary lines: meta, captions, row labels.
        bodySmall: TextStyle(color: palette.subtle, fontSize: 12),
        // Overlines, pills, badges.
        labelSmall: TextStyle(
          color: palette.subtle,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[palette],
      useMaterial3: true,
    );
  }
}
