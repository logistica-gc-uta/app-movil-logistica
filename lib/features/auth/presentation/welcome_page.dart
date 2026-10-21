import 'dart:math' as math;

import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/core/widgets/brand_wordmark.dart';
import 'package:app_movil_logistica/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';

/// Alto del bloque de marca en la bienvenida.
double welcomeBlockHeight(Size screen) => math.max(300.0, screen.height * 0.56);

/// Distancia desde arriba a la que está "SPEED RUN" en la bienvenida: abajo
/// a la izquierda del bloque de marca.
double welcomeWordmarkTop(BuildContext context) {
  return welcomeBlockHeight(MediaQuery.sizeOf(context)) -
      AppSpacing.page -
      BrandWordmark.heightOf(context);
}

/// Distancia desde arriba a la que empieza el texto de bienvenida.
double welcomeCopyTop(Size screen) => welcomeBlockHeight(screen) + 24;

/// Pantalla que se muestra solo la primera vez que se abre la app
/// (o siempre, con la opción `ALWAYS_SHOW_WELCOME`).
///
/// Al pulsar «Continuar» se pasa al inicio de sesión, que parte de este mismo
/// aspecto y hace subir el fondo hasta cubrir el bloque de marca.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final screen = MediaQuery.sizeOf(context);

    return AnnotatedRegion(
      value: statusBarFor(brand.block),
      child: Scaffold(
        backgroundColor: brand.base,
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: welcomeBlockHeight(screen),
              child: ColoredBox(color: brand.block),
            ),
            Positioned(
              left: AppSpacing.page,
              right: AppSpacing.page,
              top: welcomeWordmarkTop(context),
              child: BrandWordmark(color: brand.onBlock),
            ),
            Positioned(
              left: AppSpacing.page,
              right: AppSpacing.page,
              top: welcomeCopyTop(screen),
              child: const WelcomeCopy(),
            ),
            Positioned(
              left: AppSpacing.page,
              right: AppSpacing.page,
              bottom: 12 + MediaQuery.paddingOf(context).bottom,
              child: PrimaryButton(label: 'Continuar', onPressed: onContinue),
            ),
          ],
        ),
      ),
    );
  }
}

/// Título y texto de la bienvenida, en el color de los textos del fondo.
class WelcomeCopy extends StatelessWidget {
  const WelcomeCopy({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final onBase = BrandColors.of(context).onBase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bienvenido',
          style: textTheme.headlineMedium?.copyWith(color: onBase),
        ),
        const SizedBox(height: 12),
        Text(
          'Consulta tu ruta del día y registra tus entregas desde un solo '
          'lugar.',
          style: textTheme.bodyLarge?.copyWith(
            color: onBase.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
