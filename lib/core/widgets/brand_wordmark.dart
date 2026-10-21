import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "SPEED RUN" en grande, en dos líneas y en blanco: la marca del bloque de
/// color de la bienvenida y del inicio de sesión. Con [showLines] lleva tres
/// líneas de velocidad junto a "RUN". Ocupa todo el ancho disponible.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, required this.color, this.showLines = false});

  /// Color de las letras y de las líneas de velocidad.
  final Color color;

  /// Si es true, muestra las líneas de velocidad, que se dibujan
  /// deslizándose al aparecer.
  final bool showLines;

  static TextStyle? _style(BuildContext context, [Color? color]) {
    final width = MediaQuery.sizeOf(context).width;
    return Theme.of(context).textTheme.headlineLarge?.copyWith(
      color: color,
      fontSize: width * 0.2,
      height: 0.95,
      fontWeight: FontWeight.w800,
      fontVariations: const [FontVariation.weight(800)],
      letterSpacing: -width * 0.006,
    );
  }

  /// Alto que ocupa la marca, para poder ubicarla con precisión.
  static double heightOf(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'SPEED\nRUN', style: _style(context)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.height;
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context, color);
    final fontSize = style?.fontSize ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('SPEED', style: style),
        Row(
          children: [
            Text('RUN', style: style),
            if (showLines) ...[
              SizedBox(width: fontSize * 0.2),
              Expanded(
                child: _SpeedLines(height: fontSize * 0.42, color: color),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Tres líneas horizontales de distinto largo y opacidad, alineadas a la
/// derecha, que se dibujan deslizándose al aparecer.
class _SpeedLines extends StatelessWidget {
  const _SpeedLines({required this.height, required this.color});

  final double height;
  final Color color;

  static const _lines = [(1.0, 0.95), (0.68, 0.6), (0.36, 0.35)];

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (length, opacity) in _lines)
                FractionallySizedBox(
                  widthFactor: length * progress,
                  alignment: Alignment.centerRight,
                  child: Container(
                    height: 4,
                    color: color.withValues(alpha: opacity),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Iconos de la barra de estado legibles sobre un bloque de [color].
SystemUiOverlayStyle statusBarFor(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark;
}
