import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_card.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_formatters.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_parts.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_style.dart';
import 'package:app_movil_logistica/features/routes/presentation/stop_tile.dart';
import 'package:flutter/material.dart';

/// Vista de una ruta: su avance, el paso pendiente y las paradas en orden.
class RouteDetail extends StatelessWidget {
  const RouteDetail({
    super.key,
    required this.route,
    required this.updatingOrderId,
    required this.failingStopId,
    required this.isLocked,
    required this.onAdvance,
    required this.onFail,
    required this.nextStep,
    required this.availability,
    required this.checkingAvailability,
    required this.onCheckAvailability,
  });

  final DriverRoute route;
  final String? updatingOrderId;
  final String? failingStopId;
  final bool isLocked;
  final ValueChanged<DeliveryStop> onAdvance;
  final ValueChanged<DeliveryStop> onFail;
  final RouteNextStep nextStep;
  final DriverAvailability? availability;
  final bool checkingAvailability;
  final VoidCallback onCheckAvailability;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hint = routeHint(route);
    final turn = route.isInProgress ? route.currentStop : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('RUTA DEL DÍA', style: overline(context))),
            RouteStatusLabel(route.status),
          ],
        ),
        const SizedBox(height: 12),
        Text(stopsCount(route.stops.length), style: display(context, size: 38)),
        const SizedBox(height: 22),
        RouteProgressBar(stops: route.stops),
        const SizedBox(height: 14),
        Text(
          progressText(route),
          style: weighted(
            textTheme.bodyLarge,
            FontWeight.w600,
            color: RouteTone.ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          resolvedText(route),
          style: textTheme.bodySmall?.copyWith(color: RouteTone.muted),
        ),
        if (route.startedAt case final startedAt?) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 16,
                color: RouteTone.muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  formatRouteStart(startedAt),
                  style: textTheme.bodyMedium?.copyWith(color: RouteTone.muted),
                ),
              ),
            ],
          ),
        ],
        if (hint != null) ...[const SizedBox(height: 22), RouteNotice(hint)],
        if (nextStep.of(route) case (
          final onPressed,
          final label,
          final icon,
          final key,
        )) ...[
          const SizedBox(height: 16),
          RouteActionButton(
            key: key,
            label: label,
            icon: icon,
            busy: nextStep.isBusy,
            onPressed: nextStep.isLocked ? null : onPressed,
          ),
        ],
        if (route.status == 'COMPLETED' || route.isInterrupted) ...[
          const SizedBox(height: 16),
          LifecycleSummary(
            route: route,
            availability: availability,
            checkingAvailability: checkingAvailability,
            onCheckAvailability: onCheckAvailability,
          ),
        ],
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('Paradas', style: display(context, size: 22))),
            Text(
              '${route.stops.length} en tu ruta',
              style: textTheme.bodySmall?.copyWith(color: RouteTone.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < route.stops.length; i++) ...[
          if (i > 0 && !_isTurn(turn, i - 1) && !_isTurn(turn, i))
            const Divider(height: 1, color: RouteTone.line),
          if (_isTurn(turn, i)) const SizedBox(height: 8),
          StopTile(
            key: ValueKey('stop-${route.stops[i].orderId}'),
            stop: route.stops[i],
            isTurn: _isTurn(turn, i),
            isUpdating: updatingOrderId == route.stops[i].orderId,
            isFailing:
                failingStopId != null && failingStopId == route.stops[i].stopId,
            isLocked: isLocked,
            onAdvance: () => onAdvance(route.stops[i]),
            onFail: () => onFail(route.stops[i]),
          ),
          if (_isTurn(turn, i)) const SizedBox(height: 8),
        ],
      ],
    );
  }

  bool _isTurn(DeliveryStop? turn, int index) =>
      turn != null && route.stops[index].orderId == turn.orderId;
}

/// Distingue los pasos del cierre: visitas resueltas, ruta cerrada, regreso
/// confirmado y disponibilidad informada por el servidor.
class LifecycleSummary extends StatelessWidget {
  const LifecycleSummary({
    super.key,
    required this.route,
    required this.availability,
    required this.checkingAvailability,
    required this.onCheckAvailability,
  });

  final DriverRoute route;
  final DriverAvailability? availability;
  final bool checkingAvailability;
  final VoidCallback onCheckAvailability;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final returned = route.returnedAt;
    final completed = route.completedAt;
    final availability = this.availability;
    return Container(
      key: const ValueKey('route-lifecycle'),
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: const BoxDecoration(
        color: RouteTone.surface,
        borderRadius: RouteRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LifecycleRow(
            done: route.allStopsResolved,
            title: 'Visitas',
            detail:
                '${route.resolvedCount}/${route.stops.length} resueltas · '
                '${finishedDetail(route)}',
          ),
          _LifecycleRow(
            done: true,
            title: route.isInterrupted ? 'Ruta interrumpida' : 'Ruta cerrada',
            detail: route.isInterrupted
                ? (route.interruptionReason?.trim().isNotEmpty ?? false)
                      ? 'Por la administración: ${route.interruptionReason!.trim()}'
                      : 'Por la administración'
                : completed != null
                ? 'Cerrada a las ${formatEcuadorTime(completed)} (Ecuador)'
                : 'Cerrada en el servidor',
          ),
          _LifecycleRow(
            done: returned != null,
            title: 'Regreso al depósito',
            detail: returned != null
                ? 'Confirmado a las ${formatEcuadorTime(returned)} (Ecuador)'
                : 'Pendiente: sigues ocupado hasta confirmarlo',
          ),
          if (returned != null)
            _LifecycleRow(
              done: availability?.isAvailable ?? false,
              title: 'Disponibilidad',
              detail: availability == null
                  ? 'Consulta al servidor si puedes recibir una nueva ruta.'
                  : availability.isAvailable
                  ? 'El servidor te marca disponible para una nueva ruta.'
                  : 'El servidor aún no te habilita para otra ruta. '
                        'Consulta con la administración.',
              trailing: TextButton(
                key: const ValueKey('check-availability'),
                onPressed: checkingAvailability ? null : onCheckAvailability,
                style: TextButton.styleFrom(foregroundColor: RouteTone.ink),
                child: Text(
                  checkingAvailability ? 'Consultando…' : 'Consultar',
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LifecycleRow extends StatelessWidget {
  const _LifecycleRow({
    required this.done,
    required this.title,
    required this.detail,
    this.trailing,
  });

  final bool done;
  final String title;
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: done ? RouteTone.ink : RouteTone.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: weighted(
                    textTheme.bodyMedium,
                    FontWeight.w700,
                    color: RouteTone.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: textTheme.bodySmall?.copyWith(color: RouteTone.body),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
