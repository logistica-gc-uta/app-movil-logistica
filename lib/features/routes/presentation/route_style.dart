import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Paleta de la zona privada: la misma base monocroma del inicio de sesión
/// (blanco, negro y grises) con color solo para comunicar un estado.
class RouteTone {
  static const page = Colors.white;

  /// Superficie suave de las tarjetas, sin bordes ni sombras.
  static const surface = Color(0xFFF5F5F4);
  static const ink = AppColors.ink;
  static const body = AppColors.text;
  static const muted = AppColors.textMuted;
  static const line = AppColors.line;
  static const track = Color(0xFFE4E4E2);

  static const success = Color(0xFF2E6B4F);
  static const successSoft = Color(0xFFE9F1EC);
  static const danger = Color(0xFFB3412F);
  static const dangerSoft = Color(0xFFF8EDEA);
  static const warning = Color(0xFF9A6B1F);
  static const warningSoft = Color(0xFFF7F0E3);

  /// Variantes legibles sobre el bloque negro de la parada en turno.
  static const onDarkMuted = Color(0xFFB9B9B6);
}

class RouteRadius {
  static const card = BorderRadius.all(Radius.circular(8));
  static const tile = BorderRadius.all(Radius.circular(6));
  static const chip = BorderRadius.all(Radius.circular(4));
}

/// Inter es variable: el grosor también se indica como variación.
TextStyle? weighted(
  TextStyle? style,
  FontWeight weight, {
  double? size,
  Color? color,
  double? letterSpacing,
}) {
  return style?.copyWith(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    fontVariations: [FontVariation.weight(weight.value.toDouble())],
  );
}

/// Texto pequeño en mayúsculas que encabeza un bloque.
TextStyle? overline(BuildContext context, {Color color = RouteTone.muted}) {
  return weighted(
    Theme.of(context).textTheme.bodySmall,
    FontWeight.w600,
    color: color,
    letterSpacing: 1.1,
  );
}

/// Título grande y pesado, como «SPEEDRUN» y «INICIAR SESIÓN».
TextStyle? display(BuildContext context, {double size = 30, Color? color}) {
  return weighted(
    Theme.of(context).textTheme.headlineMedium,
    FontWeight.w800,
    size: size,
    color: color ?? RouteTone.ink,
    letterSpacing: -size * 0.03,
  )?.copyWith(height: 1.08);
}

/// Margen lateral de la zona privada.
const pagePadding = 24.0;
