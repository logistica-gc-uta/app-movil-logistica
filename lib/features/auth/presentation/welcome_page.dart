import 'dart:math' as math;

import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/core/widgets/topo_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pantalla que se muestra solo la primera vez que se abre la app.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final headerHeight = math.max(300.0, constraints.maxHeight * 0.55);

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: headerHeight, child: const TopoHeader()),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bienvenido', style: textTheme.headlineLarge),
                            const SizedBox(height: 12),
                            Text(
                              'Consulta tu ruta del día y registra tus '
                              'entregas desde un solo lugar.',
                              style: textTheme.bodyLarge?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          28,
                          32,
                          20,
                          24 + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _ContinueButton(onPressed: onContinue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Continuar',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(width: 14),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.onPrimary,
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
