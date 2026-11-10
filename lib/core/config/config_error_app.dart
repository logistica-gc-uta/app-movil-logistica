import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// App mínima que se muestra en lugar de la real cuando la build trae una
/// URL de API inválida o insegura. Así no se llega a pedir la contraseña ni
/// a enviarla por un canal sin cifrar.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.message, this.buildLabel});

  final String message;
  final String? buildLabel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speedrun',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(invertBrand: false),
      home: Builder(
        builder: (context) {
          final textTheme = Theme.of(context).textTheme;
          final label = buildLabel;
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.gpp_maybe_outlined,
                      color: AppColors.error,
                      size: 40,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Esta versión de la app no está bien configurada',
                      style: textTheme.titleLarge?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: textTheme.bodyLarge?.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pide al equipo una versión compilada para tu entorno.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    if (label != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        label,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
