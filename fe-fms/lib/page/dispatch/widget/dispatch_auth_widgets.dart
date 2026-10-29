import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dispatch_palette.dart';

/// Branded green header for the dispatch auth screens — an icon, title and
/// subtitle on the brand colour, with an optional back action.
class DispatchBrandHeader extends StatelessWidget {
  const DispatchBrandHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      color: DispatchColors.brand,
      padding: EdgeInsets.fromLTRB(20, topInset + 10, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back,
                  color: DispatchColors.onBrand),
              tooltip: 'Back',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(height: 18),
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, size: 32, color: DispatchColors.onBrand),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: DispatchColors.onBrand,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// A palette-styled text field for the dispatch auth forms — green focus
/// ring, theme-aware fill/borders.
class DispatchTextField extends StatelessWidget {
  const DispatchTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.enableSuggestions = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      style: TextStyle(color: palette.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: palette.card,
        labelStyle: TextStyle(color: palette.subtle),
        hintStyle: TextStyle(color: palette.subtle),
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: DispatchColors.brand),
        suffixIcon: suffixIcon,
        border: border(palette.cardBorder),
        enabledBorder: border(palette.cardBorder),
        focusedBorder: border(DispatchColors.brand, 1.6),
      ),
    );
  }
}

/// An inline form error — a soft red box. For transient action feedback use
/// the notice banner instead; this is for in-form validation/submit errors.
class DispatchErrorText extends StatelessWidget {
  const DispatchErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    const red = DispatchColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: red.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: red, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared primary action button for dispatch auth forms — green fill.
class DispatchPrimaryButton extends StatelessWidget {
  const DispatchPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: DispatchColors.brand,
        foregroundColor: DispatchColors.onBrand,
        disabledBackgroundColor: DispatchColors.brand.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }
}
