import 'package:flutter/material.dart';

/// ===========================================================================
/// THE dispatch colour palette — the single source of truth.
///
/// To re-skin the dispatch surface, edit ONLY this file:
///   • brand colours (mode-independent) → [DispatchColors]
///   • theme-dependent neutrals → [DispatchPalette.light] / [DispatchPalette.dark]
/// Every dispatch screen reads its colours from here.
/// ===========================================================================

/// Brand colours — identical in light and dark mode.
class DispatchColors {
  DispatchColors._();

  /// Primary brand green — job cards, focus panel, headers, accents.
  static const Color brand = Color(0xFF2d9353);

  /// Content (text / icons) shown on top of [brand].
  static const Color onBrand = Color(0xFFFFFFFF);

  /// Highlight accent — the in-progress job, etc.
  static const Color accent = Color(0xFFe8e241);

  /// Destructive red — cancel buttons, log out, and other irreversible
  /// actions. A strong, consistent red across light and dark (the muted
  /// [ColorScheme.error] reads as pink on dark surfaces).
  static const Color danger = Color(0xFFdc2626);

  /// Active rider route polyline (hex form — `MapZoneStyle` wants a string).
  static const String routeHex = '#1976D2';

  /// All-jobs preview route polyline.
  static const String routePreviewHex = '#F59E0B';
}

/// Theme-dependent neutral colours for the dispatch surface. Registered as a
/// [ThemeExtension] on both the light and dark [ThemeData]; read it concisely
/// with `context.dispatch`.
@immutable
class DispatchPalette extends ThemeExtension<DispatchPalette> {
  const DispatchPalette({
    required this.pageSurface,
    required this.card,
    required this.cardBorder,
    required this.control,
    required this.ink,
    required this.subtle,
    required this.divider,
  });

  /// Page / scaffold background.
  final Color pageSurface;

  /// Neutral card / sheet surface (distinct from the green brand cards).
  final Color card;

  /// Border around neutral cards.
  final Color cardBorder;

  /// Floating controls layered over the map — the top island, recenter button.
  final Color control;

  /// Primary text colour.
  final Color ink;

  /// Secondary / muted text colour.
  final Color subtle;

  /// Hairline divider colour.
  final Color divider;

  /// Light-mode neutrals.
  static const DispatchPalette light = DispatchPalette(
    pageSurface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFe5e7eb),
    control: Color(0xFFFFFFFF),
    ink: Color(0xFF111827),
    subtle: Color(0xFF6b7280),
    divider: Color(0xFFe5e7eb),
  );

  /// Dark-mode neutrals.
  static const DispatchPalette dark = DispatchPalette(
    pageSurface: Color(0xFF0F141A),
    card: Color(0xFF1A222C),
    cardBorder: Color(0xFF2A3441),
    control: Color(0xFF222C38),
    ink: Color(0xFFE8EBF0),
    subtle: Color(0xFF94A3B8),
    divider: Color(0xFF2A3441),
  );

  @override
  DispatchPalette copyWith({
    Color? pageSurface,
    Color? card,
    Color? cardBorder,
    Color? control,
    Color? ink,
    Color? subtle,
    Color? divider,
  }) {
    return DispatchPalette(
      pageSurface: pageSurface ?? this.pageSurface,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      control: control ?? this.control,
      ink: ink ?? this.ink,
      subtle: subtle ?? this.subtle,
      divider: divider ?? this.divider,
    );
  }

  @override
  DispatchPalette lerp(DispatchPalette? other, double t) {
    if (other == null) return this;
    return DispatchPalette(
      pageSurface: Color.lerp(pageSurface, other.pageSurface, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      control: Color.lerp(control, other.control, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

/// Concise palette access: `context.dispatch.card`, `context.dispatch.ink`, …
extension DispatchPaletteX on BuildContext {
  DispatchPalette get dispatch =>
      Theme.of(this).extension<DispatchPalette>() ?? DispatchPalette.light;
}
