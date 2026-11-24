import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_formatters.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_parts.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_style.dart';
import 'package:flutter/material.dart';

/// Paso pendiente de una ruta con las visitas resueltas: cerrarla y, después,
/// confirmar el regreso al depósito.
class RouteNextStep {
  const RouteNextStep({
    required this.isBusy,
    required this.isLocked,
    required this.onComplete,
    required this.onReturn,
  });

  final bool isBusy;
  final bool isLocked;
  final VoidCallback onComplete;
  final VoidCallback onReturn;

  /// Acción, etiqueta, icono y clave del paso, o null si la ruta no tiene.
  (VoidCallback, String, IconData, Key)? of(DriverRoute route) {
    if (route.awaitsCompletion) {
      return (
        onComplete,
        isBusy ? 'Cerrando…' : 'Cerrar ruta',
        Icons.flag_outlined,
        ValueKey('complete-route-${route.id}'),
      );
    }
    if (route.awaitsReturn) {
      return (
        onReturn,
        isBusy ? 'Confirmando…' : 'Confirmar llegada al depósito',
        Icons.home_work_outlined,
        ValueKey('return-route-${route.id}'),
      );
    }
    return null;
  }
}

/// Tarjeta de una ruta del día: cuántas paradas tiene, cómo va y la acción
/// que toca ahora.
class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.route,
    required this.canStart,
    required this.isStarting,
    required this.isLocked,
    required this.onStart,
    required this.onOpen,
    required this.nextStep,
  });

  final DriverRoute route;
  final bool canStart;
  final bool isStarting;
  final bool isLocked;
  final VoidCallback onStart;
  final VoidCallback onOpen;
  final RouteNextStep nextStep;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hint = routeHint(route);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: const BoxDecoration(
        color: RouteTone.surface,
        borderRadius: RouteRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 12),
                decoration: const BoxDecoration(
                  color: RouteTone.ink,
                  borderRadius: RouteRadius.chip,
                ),
                child: const Icon(
                  Icons.route_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: Text(
                  route.allStopsResolved
                      ? (route.failedCount == 0
                            ? 'PARADAS COMPLETADAS'
                            : 'PARADAS FINALIZADAS')
                      : 'RUTA DEL DÍA',
                  style: overline(context),
                ),
              ),
              RouteStatusLabel(route.status),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            stopsCount(route.stops.length),
            style: display(context, size: 26),
          ),
          const SizedBox(height: 20),
          RouteProgressBar(stops: route.stops),
          const SizedBox(height: 14),
          Text(
            progressText(route),
            style: weighted(
              textTheme.bodyLarge,
              FontWeight.w600,
              size: 14,
              color: RouteTone.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            resolvedText(route),
            style: textTheme.bodySmall?.copyWith(color: RouteTone.muted),
          ),
          if (hint != null) ...[
            const SizedBox(height: 14),
            Text(
              hint,
              style: textTheme.bodySmall?.copyWith(color: RouteTone.body),
            ),
          ],
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    if (nextStep.of(route) case (
      final onPressed,
      final label,
      final icon,
      final key,
    )) {
      return [
        const SizedBox(height: 20),
        RouteActionButton(
          key: key,
          label: label,
          icon: icon,
          busy: nextStep.isBusy,
          onPressed: nextStep.isLocked ? null : onPressed,
        ),
        const SizedBox(height: 4),
        TextButton(
          key: ValueKey('open-route-${route.id}'),
          onPressed: isLocked ? null : onOpen,
          style: TextButton.styleFrom(
            foregroundColor: RouteTone.ink,
            minimumSize: const Size.fromHeight(44),
          ),
          child: const Text('Ver resumen'),
        ),
      ];
    }
    final starting = route.status == 'ASSIGNED';
    final (key, label, icon) = switch (route.status) {
      'ASSIGNED' when canStart => (
        ValueKey('start-route-${route.id}'),
        isStarting ? 'Iniciando…' : 'Iniciar ruta',
        Icons.play_arrow_rounded,
      ),
      'IN_PROGRESS' when !route.allStopsResolved => (
        ValueKey('open-route-${route.id}'),
        'Continuar ruta',
        Icons.arrow_forward_rounded,
      ),
      'IN_PROGRESS' || 'COMPLETED' || 'INTERRUPTED' => (
        ValueKey('open-route-${route.id}'),
        'Ver resumen',
        Icons.format_list_bulleted_rounded,
      ),
      _ => (null, null, null),
    };
    if (label == null) return const [];
    return [
      const SizedBox(height: 20),
      RouteActionButton(
        key: key,
        label: label,
        icon: icon!,
        busy: starting && isStarting,
        onPressed: isLocked ? null : (starting ? onStart : onOpen),
      ),
      // Antes de iniciar se pueden revisar las paradas, sin acciones.
      if (starting) ...[
        const SizedBox(height: 4),
        TextButton(
          key: ValueKey('open-route-${route.id}'),
          onPressed: isLocked ? null : onOpen,
          style: TextButton.styleFrom(
            foregroundColor: RouteTone.ink,
            minimumSize: const Size.fromHeight(44),
          ),
          child: const Text('Ver paradas'),
        ),
      ],
    ];
  }
}
