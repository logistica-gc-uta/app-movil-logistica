import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_style.dart';
import 'package:flutter/material.dart';

/// Estado de la ruta como punto de color y texto, sin recuadro.
class RouteStatusLabel extends StatelessWidget {
  const RouteStatusLabel(this.status, {super.key, this.onDark = false});

  final String status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'IN_PROGRESS' => ('En curso', RouteTone.ink),
      'COMPLETED' => ('Completada', RouteTone.success),
      'INTERRUPTED' => ('Interrumpida', RouteTone.danger),
      'ASSIGNED' => ('Asignada', RouteTone.warning),
      'DRAFT' => ('Borrador', RouteTone.muted),
      _ => ('Sin verificar', RouteTone.muted),
    };
    final textColor = onDark ? Colors.white : RouteTone.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: onDark && color == RouteTone.ink ? Colors.white : color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: weighted(
            Theme.of(context).textTheme.bodyMedium,
            FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

/// Un segmento fino por visita: negro si se entregó, rojo si falló y gris
/// mientras está pendiente.
class RouteProgressBar extends StatelessWidget {
  const RouteProgressBar({super.key, required this.stops});

  final List<DeliveryStop> stops;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < stops.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                color: stops[i].isDelivered
                    ? RouteTone.ink
                    : stops[i].isFailed
                    ? RouteTone.danger
                    : stops[i].status == 'IN_TRANSIT'
                    ? RouteTone.body.withValues(alpha: 0.55)
                    : RouteTone.track,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Aviso en línea, por ejemplo cuando una recarga falla o hay un paso
/// pendiente. Sin iconos decorativos: solo una barra lateral de color.
class RouteNotice extends StatelessWidget {
  const RouteNotice(
    this.text, {
    super.key,
    this.detail,
    this.onRetry,
    this.retryEnabled = true,
    this.tone = RouteTone.warning,
    this.background = RouteTone.warningSoft,
  });

  final String text;
  final String? detail;
  final VoidCallback? onRetry;
  final bool retryEnabled;
  final Color tone;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: RouteRadius.tile,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: tone),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: textTheme.bodyMedium?.copyWith(
                        color: RouteTone.ink,
                      ),
                    ),
                    if (detail case final message?) ...[
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: textTheme.bodySmall?.copyWith(
                          color: RouteTone.body,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (onRetry != null)
              IconButton(
                tooltip: 'Reintentar',
                onPressed: retryEnabled ? onRetry : null,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                color: RouteTone.ink,
              ),
          ],
        ),
      ),
    );
  }
}

/// Mensaje centrado de un estado vacío o de error, con una acción opcional.
class RouteMessage extends StatelessWidget {
  const RouteMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final actionLabel = this.actionLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 36, color: RouteTone.ink),
          const SizedBox(height: 20),
          Text(title, style: display(context, size: 20)),
          const SizedBox(height: 10),
          Text(
            message,
            style: textTheme.bodyLarge?.copyWith(color: RouteTone.muted),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Botón principal de las tarjetas: negro, con la misma forma que el botón
/// «Ingresar al turno» del inicio de sesión.
class RouteActionButton extends StatelessWidget {
  const RouteActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.onDark = false,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  /// Sobre el bloque negro el botón se invierte: fondo blanco, texto negro.
  final bool onDark;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final background = color ?? (onDark ? Colors.white : AppColors.primary);
    final foreground = onDark && color == null ? RouteTone.ink : Colors.white;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: background.withValues(alpha: 0.5),
        disabledForegroundColor: foreground,
        minimumSize: const Size.fromHeight(54),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        textStyle: weighted(
          Theme.of(context).textTheme.labelLarge,
          FontWeight.w700,
          size: 15,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: foreground,
              ),
            )
          else
            Icon(icon, size: 20),
          const SizedBox(width: 10),
          // Con letra grande la etiqueta pasa a dos líneas.
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

/// Acción secundaria: solo contorno.
class RouteOutlineButton extends StatelessWidget {
  const RouteOutlineButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.color = RouteTone.ink,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: color.withValues(alpha: 0.45),
        side: BorderSide(
          color: color.withValues(alpha: onPressed == null ? 0.25 : 0.5),
        ),
        minimumSize: const Size.fromHeight(50),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        textStyle: weighted(
          Theme.of(context).textTheme.labelLarge,
          FontWeight.w600,
          size: 14,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
            )
          else
            Icon(icon, size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}
