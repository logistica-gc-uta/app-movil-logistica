import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_formatters.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_parts.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_style.dart';
import 'package:flutter/material.dart';

/// Una parada de la ruta. La parada en turno es un bloque negro con sus
/// acciones; las demás son filas simples con su resultado.
class StopTile extends StatelessWidget {
  const StopTile({
    super.key,
    required this.stop,
    required this.isTurn,
    required this.isUpdating,
    required this.isFailing,
    required this.isLocked,
    required this.onAdvance,
    required this.onFail,
  });

  final DeliveryStop stop;

  /// Es la parada que se atiende ahora, en una ruta en curso.
  final bool isTurn;
  final bool isUpdating;
  final bool isFailing;
  final bool isLocked;
  final VoidCallback onAdvance;
  final VoidCallback onFail;

  @override
  Widget build(BuildContext context) =>
      isTurn ? _buildTurn(context) : _buildRow(context);

  Widget _buildRow(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (marker, markerColor, markerBackground) = switch (stop) {
      _ when stop.isDelivered => (
        const Icon(Icons.check_rounded, size: 20, color: Colors.white),
        RouteTone.ink,
        RouteTone.ink,
      ),
      _ when stop.isFailed => (
        const Icon(Icons.close_rounded, size: 20, color: RouteTone.danger),
        RouteTone.danger,
        RouteTone.dangerSoft,
      ),
      _ => (
        Text(
          '${stop.stopOrder ?? '–'}',
          style: weighted(
            textTheme.bodyMedium,
            FontWeight.w700,
            color: RouteTone.muted,
          ),
        ),
        RouteTone.muted,
        RouteTone.surface,
      ),
    };
    final detailColor = stop.isFailed
        ? RouteTone.danger
        : stop.isDelivered
        ? RouteTone.success
        : RouteTone.muted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: markerBackground,
              borderRadius: RouteRadius.chip,
            ),
            child: marker,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.address,
                  style: weighted(
                    textTheme.bodyLarge,
                    FontWeight.w600,
                    size: 15,
                    color: stop.isDelivered || stop.isFailed
                        ? RouteTone.body
                        : RouteTone.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  stop.isFailed
                      ? failedLabel(stop)
                      : stop.isDelivered
                      ? 'Entregado con éxito'
                      : stopStatusLabel(stop),
                  style: textTheme.bodySmall?.copyWith(color: detailColor),
                ),
                if (stop.isFailed && stop.failureContext != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    stop.failureContext!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: RouteTone.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!stop.isDelivered && !stop.isFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 8),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: markerColor.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTurn(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final inTransit = stop.status == 'IN_TRANSIT';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: const BoxDecoration(
        color: RouteTone.ink,
        borderRadius: RouteRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AHORA · PARADA ${stop.stopOrder ?? '–'}',
            style: overline(context, color: RouteTone.onDarkMuted),
          ),
          const SizedBox(height: 10),
          Text(
            stop.address,
            style: display(context, size: 20, color: Colors.white),
          ),
          if (inTransit) ...[
            const SizedBox(height: 20),
            const _TransitLine(),
            const SizedBox(height: 10),
            Text(
              'Llevando el paquete a esta parada',
              style: textTheme.bodyMedium?.copyWith(
                color: RouteTone.onDarkMuted,
              ),
            ),
          ],
          const SizedBox(height: 22),
          if (stop.status == 'ASSIGNED')
            RouteActionButton(
              label: 'En camino',
              icon: Icons.local_shipping_outlined,
              onDark: true,
              busy: isUpdating,
              onPressed: isLocked ? null : onAdvance,
            )
          else if (inTransit)
            RouteActionButton(
              label: 'Entregado',
              icon: Icons.check_circle_outline_rounded,
              onDark: true,
              busy: isUpdating,
              onPressed: isLocked ? null : onAdvance,
            ),
          // Una visita fallida no es una entrega ni una cancelación: queda
          // resuelta y la administración decide qué hacer con el pedido.
          if (stop.canRecordFailure) ...[
            const SizedBox(height: 10),
            RouteOutlineButton(
              key: ValueKey('fail-stop-${stop.orderId}'),
              label: 'No se pudo entregar',
              icon: Icons.report_gmailerrorred_rounded,
              color: Colors.white,
              busy: isFailing,
              onPressed: isLocked ? null : onFail,
            ),
          ],
        ],
      ),
    );
  }
}

/// Línea fina que avanza de forma progresiva hasta la mitad del trayecto
/// cuando el pedido pasa a «En camino». Se anima una sola vez y se queda
/// quieta: sin animaciones infinitas que gasten batería.
class _TransitLine extends StatelessWidget {
  const _TransitLine();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 0.5),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 3,
          color: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}
