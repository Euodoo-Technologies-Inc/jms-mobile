import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The app's motion tokens: Material 3 durations and easing. Transitions use
/// these (through [Motion.of]) instead of literals, so motion reads as one
/// system and the OS "Remove animations" setting is honoured everywhere.
abstract final class Motion {
  /// Small state changes: a pill or banner appearing, loading → content.
  static const Duration short = Durations.short4; // 200 ms

  /// Layout and view changes: route transitions, panels, expanding sections.
  static const Duration medium = Durations.medium2; // 300 ms

  /// Deliberate reveals: the route line drawing on.
  static const Duration long = Durations.long2; // 500 ms

  /// Elements changing in place, and exits.
  static const Curve standard = Easing.standard;

  /// Arrivals: routes, banners and panels entering. No overshoot.
  static const Curve emphasized = Easing.emphasizedDecelerate;

  /// True when the OS asks for reduced motion (Android "Remove animations").
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or [Duration.zero] under reduce motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// Sets GetX's route defaults: one curve and one duration for every push,
  /// instant under reduce motion. Called from the app builder, which reruns
  /// when the setting changes.
  static void applyRouteDefaults(BuildContext context) => Get.rootController
    ..defaultTransitionCurve = emphasized
    ..defaultTransitionDuration = of(context, medium);

  /// [reduced] for code with no [BuildContext], such as controllers.
  static bool get reducedNow => WidgetsBinding
      .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
}
