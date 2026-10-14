import 'package:flutter/material.dart';

class AppColors {
  static const background = Colors.white;
  static const primary = Color(0xFFFF8383);
  static const onPrimary = Colors.white;
  static const text = Color(0xFF404040);
  static const textMuted = Color(0xFF8E8E8E);
  static const hint = Color(0xFFA6A6A6);
  static const line = Color(0xFFDEDEDE);
  static const error = Color(0xFFD93F3F);
  static const errorSurface = Color(0xFFFFF1F1);
}

/// Paletas de colores que el repartidor puede elegir.
enum AppPalette {
  coral('Coral', Color(0xFFFF8383)),
  naranja('Naranja', Color(0xFFFF6940)),
  negro('Negro', Color(0xFF141310));

  const AppPalette(this.label, this.color);

  final String label;
  final Color color;
}

class AppFonts {
  static const body = 'Rubik';
}

class AppRadius {
  static const button = BorderRadius.all(Radius.circular(10));
}

TextStyle _style(
  double size,
  FontWeight weight, {
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: AppFonts.body,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation.weight(weight.value.toDouble())],
    height: height == null ? null : height / size,
    letterSpacing: letterSpacing,
  );
}

ThemeData buildAppTheme({Color primary = AppColors.primary}) {
  final scheme = ColorScheme.light(
    primary: primary,
    onPrimary: AppColors.onPrimary,
    surface: AppColors.background,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.line,
    error: AppColors.error,
  );

  final textTheme = TextTheme(
    headlineLarge: _style(36, FontWeight.w700, height: 44),
    titleLarge: _style(18, FontWeight.w700, height: 24),
    titleMedium: _style(17, FontWeight.w500, height: 22),
    labelLarge: _style(18, FontWeight.w500, height: 22),
    labelSmall: _style(13, FontWeight.w400, height: 18),
    bodyLarge: _style(16, FontWeight.w400, height: 22),
    bodyMedium: _style(14, FontWeight.w400, height: 20),
    bodySmall: _style(12, FontWeight.w400, height: 16),
  ).apply(bodyColor: AppColors.text, displayColor: AppColors.text);

  UnderlineInputBorder underline(Color color, double width) {
    return UnderlineInputBorder(
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: AppFonts.body,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge,
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: primary),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      hintStyle: textTheme.bodyLarge?.copyWith(
        color: AppColors.hint,
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation.weight(400)],
      ),
      errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.error),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
      border: underline(AppColors.line, 1),
      enabledBorder: underline(AppColors.line, 1),
      focusedBorder: underline(primary, 2),
      errorBorder: underline(AppColors.error, 1),
      focusedErrorBorder: underline(AppColors.error, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: primary.withValues(alpha: 0.6),
        disabledForegroundColor: AppColors.onPrimary,
        minimumSize: const Size.fromHeight(52),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        textStyle: textTheme.labelLarge,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
  );
}
