import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:app_movil_logistica/features/routes/data/routes_service.dart';
import 'package:flutter/material.dart';

/// «Mi Ruta del Día»: rutas y paradas del chofer para hoy.
class MyRoutePage extends StatefulWidget {
  const MyRoutePage({
    super.key,
    required this.user,
    required this.routesService,
    required this.onLogout,
  });

  final AuthUser user;
  final RoutesService routesService;
  final VoidCallback onLogout;

  @override
  State<MyRoutePage> createState() => _MyRoutePageState();
}

class _MyRoutePageState extends State<MyRoutePage> {
  final String _date = todayInGuayaquil();

  bool _isLoading = true;
  String? _errorMessage;
  List<DriverRoute> _routes = const [];

  /// Pedido que se está actualizando, para mostrar su botón en espera.
  String? _updatingOrderId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _load() async {
    try {
      final routes = await widget.routesService.fetchMyRoutes(_date);
      if (!mounted) {
        return false;
      }
      setState(() {
        _routes = routes;
        _errorMessage = null;
        _isLoading = false;
      });
      return true;
    } on RoutesException catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
      return false;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await _load();
  }

  Future<void> _advance(DeliveryStop stop) async {
    if (_updatingOrderId != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _updatingOrderId = stop.orderId;
    });
    String message;
    try {
      if (stop.status == 'ASSIGNED') {
        await widget.routesService.markInTransit(stop.orderId);
      } else {
        await widget.routesService.markDelivered(stop.orderId);
      }
      // Solo se informa el cambio después de confirmarlo con el servidor.
      final refreshed = await _load();
      message = refreshed
          ? 'Pedido actualizado.'
          : 'El servidor confirmó el cambio, pero no se pudo actualizar la lista. '
                'Desliza hacia abajo para consultar el estado actual.';
    } on RoutesException catch (error) {
      message = error.message;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _updatingOrderId = null;
    });
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Ruta del Día'),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final errorMessage = _errorMessage;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null && _routes.isEmpty) {
      return _MessageView(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar tus rutas',
        message: errorMessage,
        actionLabel: 'Reintentar',
        onAction: _retry,
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _load();
      },
      child: ListView(
        // Permite deslizar para actualizar aunque la lista sea corta.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Greeting(name: widget.user.name, date: _date),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            _Hint(errorMessage),
          ],
          const SizedBox(height: 20),
          if (_routes.isEmpty)
            const _MessageView(
              icon: Icons.event_available_outlined,
              title: 'No tienes rutas para hoy',
              message:
                  'Cuando te asignen una ruta aparecerá aquí. '
                  'Desliza hacia abajo para actualizar.',
            ),
          for (final route in _routes) ...[
            _RouteCard(
              route: route,
              updatingOrderId: _updatingOrderId,
              onAdvance: _advance,
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.date});

  final String name;
  final String date;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hola, $name', style: textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          formatLongDate(date),
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.route,
    required this.updatingOrderId,
    required this.onAdvance,
  });

  final DriverRoute route;
  final String? updatingOrderId;
  final ValueChanged<DeliveryStop> onAdvance;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hint = switch (route.status) {
      'ASSIGNED' => 'Inicia la ruta para poder actualizar las entregas.',
      'COMPLETED' => 'Ruta completada.',
      _ => null,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.button,
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${route.zoneName} · ${route.zoneCode}',
                    style: textTheme.titleMedium,
                  ),
                ),
                _Badge.forRoute(route.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _progressText(route),
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            if (hint != null) ...[const SizedBox(height: 12), _Hint(hint)],
            const SizedBox(height: 8),
            for (final stop in route.stops)
              _StopTile(
                stop: stop,
                canAdvance: route.isInProgress,
                isUpdating: updatingOrderId == stop.orderId,
                isLocked: updatingOrderId != null,
                onAdvance: () => onAdvance(stop),
              ),
          ],
        ),
      ),
    );
  }

  /// Cuenta solo entregas reales: un intento fallido no suma como entregado.
  String _progressText(DriverRoute route) {
    final total = route.stops.length;
    final failed = route.failedCount;
    final delivered = '${route.deliveredCount} de $total entregados';
    return failed == 0 ? delivered : '$delivered · $failed con intento fallido';
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.canAdvance,
    required this.isUpdating,
    required this.isLocked,
    required this.onAdvance,
  });

  final DeliveryStop stop;
  final bool canAdvance;
  final bool isUpdating;
  final bool isLocked;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primary = Theme.of(context).colorScheme.primary;
    final action = switch (stop.status) {
      'ASSIGNED' when !stop.isFailed && !stop.isDelivered => 'En camino',
      'IN_TRANSIT' when !stop.isFailed && !stop.isDelivered => 'Entregado',
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              stop.stopOrder?.toString() ?? '–',
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stop.address, style: textTheme.bodyLarge),
                const SizedBox(height: 6),
                _Badge.forStop(stop),
                if (canAdvance && action != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: FilledButton(
                      onPressed: isLocked ? null : onAdvance,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(132, 40),
                        textStyle: textTheme.titleMedium,
                      ),
                      child: isUpdating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : Text(action),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta de estado con colores según su significado.
class _Badge extends StatelessWidget {
  const _Badge(this.label, this.foreground, this.background);

  factory _Badge.forRoute(String status) {
    return switch (status) {
      'IN_PROGRESS' => const _Badge('En curso', _blue, _blueSoft),
      'COMPLETED' => const _Badge('Completada', _green, _greenSoft),
      'ASSIGNED' => const _Badge('Asignada', AppColors.text, _grey),
      'DRAFT' => const _Badge('Borrador', AppColors.textMuted, _grey),
      _ => const _Badge('Sin verificar', AppColors.textMuted, _grey),
    };
  }

  factory _Badge.forStop(DeliveryStop stop) {
    if (stop.isFailed) {
      return const _Badge('Intento fallido', AppColors.error, _redSoft);
    }
    if (stop.isDelivered) {
      return const _Badge('Entregado', _green, _greenSoft);
    }
    if (stop.hasPersistedVisit && stop.status == 'DELIVERED') {
      return const _Badge('Visita sin confirmar', AppColors.textMuted, _grey);
    }
    return switch (stop.status) {
      'IN_TRANSIT' => const _Badge('En camino', _blue, _blueSoft),
      'DELIVERED' => const _Badge('Entregado', _green, _greenSoft),
      'CANCELLED' => const _Badge('Cancelado', AppColors.textMuted, _grey),
      'PENDING' => const _Badge('Pendiente', AppColors.textMuted, _grey),
      _ => const _Badge('Por entregar', AppColors.text, _grey),
    };
  }

  static const _blue = Color(0xFF1F5FBF);
  static const _blueSoft = Color(0xFFE8F0FC);
  static const _green = Color(0xFF2E7D32);
  static const _greenSoft = Color(0xFFE8F5E9);
  static const _redSoft = AppColors.errorSurface;
  static const _grey = Color(0xFFF1F1F1);

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            title,
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }
}

const _weekdays = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Convierte `2026-10-18` en «Domingo 18 de octubre».
String formatLongDate(String isoDate) {
  final parts = isoDate.split('-').map(int.parse).toList();
  final day = DateTime.utc(parts[0], parts[1], parts[2]);
  final weekday = _weekdays[day.weekday - 1];
  final capitalized = weekday[0].toUpperCase() + weekday.substring(1);
  return '$capitalized ${day.day} de ${_months[day.month - 1]}';
}
