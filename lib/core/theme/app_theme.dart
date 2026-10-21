import 'package:flutter/material.dart';

class AppColors {
  static const background = Colors.white;
  static const primary = Color(0xFF141310);
  static const onPrimary = Colors.white;
  static const text = Color(0xFF404040);
  static const ink = Color(0xFF201E1D);
  static const field = Color(0xFFF3F3F3);
  static const fieldBorder = Color(0xFF999898);
  static const textMuted = Color(0xFF8E8E8E);
  static const hint = Color(0xFFA6A6A6);
  static const line = Color(0xFFDEDEDE);
  static const error = Color(0xFFD93F3F);
  static const errorSurface = Color(0xFFFFF1F1);
}

/// Colores de la bienvenida y del inicio de sesión. La bienvenida tiene un
/// bloque de marca ([block], con la marca en [onBlock]) sobre un fondo
/// ([base], con los textos en [onBase]); en el inicio de sesión el fondo
/// sube y lo cubre todo. Invertir intercambia ambos pares.
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.block,
    required this.onBlock,
    required this.base,
    required this.onBase,
  });

  static const normal = BrandColors(
    block: AppColors.primary,
    onBlock: Color(0xFFF4F4F4),
    base: Colors.white,
    onBase: AppColors.ink,
  );

  static const inverted = BrandColors(
    block: Colors.white,
    onBlock: AppColors.ink,
    base: AppColors.primary,
    onBase: Color(0xFFF4F4F4),
  );

  final Color block;
  final Color onBlock;
  final Color base;
  final Color onBase;

  static BrandColors of(BuildContext context) {
    return Theme.of(context).extension<BrandColors>() ?? normal;
  }

  @override
  BrandColors copyWith({
    Color? block,
    Color? onBlock,
    Color? base,
    Color? onBase,
  }) {
    return BrandColors(
      block: block ?? this.block,
      onBlock: onBlock ?? this.onBlock,
      base: base ?? this.base,
      onBase: onBase ?? this.onBase,
    );
  }

  @override
  BrandColors lerp(BrandColors? other, double t) {
    if (other == null) {
      return this;
    }
    return BrandColors(
      block: Color.lerp(block, other.block, t)!,
      onBlock: Color.lerp(onBlock, other.onBlock, t)!,
      base: Color.lerp(base, other.base, t)!,
      onBase: Color.lerp(onBase, other.onBase, t)!,
    );
  }
}

class AppFonts {
  static const body = 'Inter';
}

/// Margen lateral común: marca, títulos, campos y botón se alinean a él.
class AppSpacing {
  static const page = 28.0;
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
    // Sin el espaciado extra que Material añade por defecto a algunos estilos.
    letterSpacing: letterSpacing ?? 0,
  );
}

/// Con [invertBrand], la bienvenida y el inicio de sesión intercambian el
/// blanco y el negro.
ThemeData buildAppTheme({bool invertBrand = false}) {
  const primary = AppColors.primary;
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
    // Títulos de pantalla: la misma letra que "SPEEDRUN", en tamaño menor.
    headlineMedium: _style(
      28,
      FontWeight.w800,
      height: 31,
      letterSpacing: -0.8,
    ),
    titleLarge: _style(18, FontWeight.w700, height: 24),
    titleMedium: _style(17, FontWeight.w500, height: 22),
    labelLarge: _style(18, FontWeight.w500, height: 22),
    labelSmall: _style(13, FontWeight.w400, height: 18),
    bodyLarge: _style(16, FontWeight.w400, height: 22),
    bodyMedium: _style(14, FontWeight.w400, height: 20),
    bodySmall: _style(12, FontWeight.w400, height: 16),
  ).apply(bodyColor: AppColors.text, displayColor: AppColors.ink);

  OutlineInputBorder box(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.zero,
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
      filled: true,
      fillColor: AppColors.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: textTheme.bodyLarge?.copyWith(
        color: AppColors.hint,
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation.weight(400)],
      ),
      errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.error),
      suffixIconColor: AppColors.ink,
      border: box(AppColors.fieldBorder, 1),
      enabledBorder: box(AppColors.fieldBorder, 1),
      focusedBorder: box(primary, 1.5),
      errorBorder: box(AppColors.error, 1),
      focusedErrorBorder: box(AppColors.error, 1.5),
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
    extensions: [invertBrand ? BrandColors.inverted : BrandColors.normal],
  );
}
