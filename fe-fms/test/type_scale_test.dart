import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/theme/app_theme.dart';

/// role → (size in sp, weight). Call sites use these instead of raw sizes.
final _scale = <String, (TextStyle? Function(TextTheme), double, FontWeight)>{
  'headlineMedium': ((t) => t.headlineMedium, 24, FontWeight.w700),
  'headlineSmall': ((t) => t.headlineSmall, 20, FontWeight.w700),
  'titleLarge': ((t) => t.titleLarge, 18, FontWeight.w700),
  'titleMedium': ((t) => t.titleMedium, 16, FontWeight.w600),
  'titleSmall': ((t) => t.titleSmall, 14, FontWeight.w600),
  'bodyLarge': ((t) => t.bodyLarge, 16, FontWeight.w400),
  'bodyMedium': ((t) => t.bodyMedium, 14, FontWeight.w400),
  'bodySmall': ((t) => t.bodySmall, 12, FontWeight.w400),
  'labelSmall': ((t) => t.labelSmall, 11, FontWeight.w700),
};

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    testWidgets('$name theme exposes the type scale', (tester) async {
      late TextTheme text;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (context) {
          text = Theme.of(context).textTheme;
          return const SizedBox();
        }),
      ));

      _scale.forEach((role, spec) {
        final (pick, size, weight) = spec;
        final style = pick(text)!;
        expect(style.fontSize, size, reason: role);
        expect(style.fontWeight, weight, reason: role);
        expect(style.color, isNotNull, reason: role);
      });
    });

    testWidgets('$name app bar titles default to titleLarge', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(appBar: AppBar(title: const Text('Jobs'))),
      ));

      final style =
          tester.renderObject<RenderParagraph>(find.text('Jobs')).text.style!;
      expect(style.fontSize, 18);
      expect(style.fontWeight, FontWeight.w700);
    });
  }
}
