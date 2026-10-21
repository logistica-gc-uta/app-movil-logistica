import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Botón principal de la app: negro con borde blanco, de esquinas rectas y
/// de lado a lado, con el texto a la izquierda y una flecha a la derecha.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback onPressed;

  /// Mientras es true, el botón se desactiva y la flecha se cambia por un
  /// indicador de carga.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    // Siempre negro, también con los colores invertidos.
    const background = AppColors.ink;
    const foreground = AppColors.onPrimary;

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: background.withValues(alpha: 0.7),
        disabledForegroundColor: foreground,
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        // Borde blanco fino: se ve cuando el botón está sobre el bloque de
        // color; sobre fondo blanco no se nota.
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.white, width: 1.5),
        ),
        // La misma letra que "SPEEDRUN".
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation.weight(800)],
          letterSpacing: -0.3,
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: foreground,
              ),
            )
          else
            const Icon(Icons.arrow_forward, size: 22),
        ],
      ),
    );
  }
}
