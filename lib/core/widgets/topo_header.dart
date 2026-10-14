import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Cabecera coral con líneas topográficas, borde ondulado y la marca.
///
/// [child] se dibuja encima; debe ser un [Positioned] para ubicarse
/// dentro de la cabecera (por ejemplo, el título de la pantalla).
class TopoHeader extends StatelessWidget {
  const TopoHeader({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final child = this.child;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _TopoWavePainter(Theme.of(context).colorScheme.primary),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: Text(
              'SPEEDRUN',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}

class _TopoWavePainter extends CustomPainter {
  const _TopoWavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final shape = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.80)
      ..cubicTo(w * 0.93, h * 0.94, w * 0.82, h * 0.97, w * 0.71, h * 0.92)
      ..cubicTo(w * 0.60, h * 0.87, w * 0.55, h * 0.66, w * 0.34, h * 0.62)
      ..cubicTo(w * 0.20, h * 0.59, w * 0.08, h * 0.62, 0, h * 0.66)
      ..close();

    canvas.drawPath(shape, Paint()..color = color);

    canvas.save();
    canvas.clipPath(shape);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.30);

    const centers = [
      (0.18, 0.22, 0.0),
      (0.78, 0.14, 1.7),
      (0.58, 0.58, 3.1),
      (0.05, 0.68, 4.4),
      (0.98, 0.62, 2.3),
    ];
    final unit = math.max(w, h);
    for (final (cx, cy, phase) in centers) {
      for (var ring = 1; ring <= 6; ring++) {
        final radius = unit * 0.055 * ring;
        final ringPath = Path();
        for (var i = 0; i <= 72; i++) {
          final t = i / 72 * 2 * math.pi;
          final wobble =
              1 +
              0.20 * math.sin(3 * t + phase + ring * 0.25) +
              0.08 * math.sin(5 * t - phase * 1.3);
          final x = cx * w + radius * wobble * math.cos(t);
          final y = cy * h + radius * wobble * 0.85 * math.sin(t);
          if (i == 0) {
            ringPath.moveTo(x, y);
          } else {
            ringPath.lineTo(x, y);
          }
        }
        canvas.drawPath(ringPath, line);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TopoWavePainter oldDelegate) =>
      oldDelegate.color != color;
}
