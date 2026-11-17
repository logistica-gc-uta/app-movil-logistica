import 'dart:math' as math;

import 'package:app_movil_logistica/core/network/request_id.dart';
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

class _MyRoutePageState extends State<MyRoutePage> with WidgetsBindingObserver {
  final String _date = todayInGuayaquil();

  bool _isLoading = true;
  String? _errorMessage;
  List<DriverRoute> _routes = const [];

  /// Pedido que se está actualizando, para mostrar su botón en espera.
  String? _updatingOrderId;
  String? _startingRouteId;
  bool _startNeedsRefresh = false;
  bool _ordersNeedRefresh = false;
  int _loadSequence = 0;

  /// Ruta cuyas paradas se están viendo; null muestra las rutas del día.
  String? _openRouteId;

  /// Ruta cuya última parada se acaba de entregar desde la app. La
  /// confirmación se muestra cuando el camión llega a su destino.
  String? _finishedRouteId;

  /// Visita cuyo intento fallido se está enviando.
  String? _failingStopId;

  /// Ruta que se está cerrando o cuyo regreso se está confirmando.
  String? _closingRouteId;
  String? _returningRouteId;
  bool _closeNeedsRefresh = false;

  /// Último intento fallido sin confirmar. Si el chofer lo reenvía sin
  /// cambios se usa el mismo `requestId`, que el servidor trata como
  /// repetición; con otros datos se genera uno nuevo.
  _FailureDraft? _failureDraft;

  /// Disponibilidad informada por el servidor tras confirmar el regreso o al
  /// consultarla. Nunca se deduce del estado de la ruta.
  DriverAvailability? _availability;
  bool _checkingAvailability = false;

  bool get _isMutating =>
      _updatingOrderId != null ||
      _startingRouteId != null ||
      _failingStopId != null ||
      _closingRouteId != null ||
      _returningRouteId != null;

  bool get _needsRefresh =>
      _ordersNeedRefresh || _startNeedsRefresh || _closeNeedsRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app se consulta el estado real, sin reenviar mutaciones.
    // Si hay una operación pendiente, su propia recuperación hará el GET.
    if (state == AppLifecycleState.resumed && !_isMutating) _load();
  }

  Future<bool> _load() async {
    final sequence = ++_loadSequence;
    try {
      final routes = await widget.routesService.fetchMyRoutes(_date);
      if (!mounted || sequence != _loadSequence) {
        return false;
      }
      setState(() {
        _routes = routes;
        _errorMessage = null;
        _isLoading = false;
        _startNeedsRefresh = false;
        _ordersNeedRefresh = false;
        _closeNeedsRefresh = false;
        // Un intento ya resuelto en el servidor no se vuelve a ofrecer.
        final draft = _failureDraft;
        if (draft != null &&
            !routes.any(
              (route) => route.stops.any(
                (stop) => stop.stopId == draft.stopId && !stop.isFailed,
              ),
            )) {
          _failureDraft = null;
        }
      });
      return true;
    } on RoutesException catch (error) {
      if (!mounted || sequence != _loadSequence) {
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
    if (_isMutating || _ordersNeedRefresh) return;
    // Las paradas se atienden en orden: solo avanza la parada actual.
    if (_routes.every(
      (route) =>
          !route.isInProgress || route.currentStop?.orderId != stop.orderId,
    )) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    bool hasStop(DriverRoute route) =>
        route.stops.any((s) => s.orderId == stop.orderId);
    final wasFinished = _routes.where(hasStop).firstOrNull?.allStopsResolved;
    // Un GET iniciado antes del PATCH no puede sobrescribir su resultado.
    ++_loadSequence;
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
      if (!mounted) return;
      _ordersNeedRefresh = !refreshed;
      final route = _routes.where(hasStop).firstOrNull;
      if (refreshed && wasFinished == false && route != null) {
        if (route.allStopsResolved) _finishedRouteId = route.id;
      }
      message = refreshed
          ? 'Pedido actualizado.'
          : 'El servidor confirmó el cambio, pero no se pudo actualizar la lista. '
                'Desliza hacia abajo para consultar el estado actual.';
    } on RoutesException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401 &&
          widget.routesService.apiClient.onUnauthorized != null) {
        return;
      }
      // Un timeout puede ocurrir después de persistir. Consultar antes de
      // permitir otro intento; nunca confirmar éxito por una respuesta perdida.
      if (error.statusCode != 401 && error.statusCode != 403) {
        final refreshed = await _load();
        if (!mounted) return;
        _ordersNeedRefresh = !refreshed;
      }
      message = error.message;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _updatingOrderId = null;
    });
    _notify(messenger, message);
  }

  Future<void> _start(DriverRoute route) async {
    if (_isMutating ||
        _startNeedsRefresh ||
        _ordersNeedRefresh ||
        !widget.user.isDriver ||
        route.status != 'ASSIGNED') {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    // Invalida cualquier GET anterior que pudiera devolver ASSIGNED tarde.
    ++_loadSequence;
    setState(() {
      _startingRouteId = route.id;
    });
    String message;
    try {
      final startedAt = await widget.routesService.startRoute(route.id);
      if (!mounted) return;
      setState(() {
        _routes = [
          for (final current in _routes)
            if (current.id == route.id)
              current.withConfirmedStart(startedAt)
            else
              current,
        ];
        // Con el inicio confirmado se entra a las paradas de la ruta.
        _openRouteId = route.id;
      });
      final refreshed = await _load();
      message = refreshed
          ? 'Ruta iniciada.'
          : 'El servidor confirmó el inicio. No se pudo actualizar la lista; desliza para reintentar.';
    } on RoutesException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401 &&
          widget.routesService.apiClient.onUnauthorized != null) {
        // La raíz elimina la sesión y muestra el aviso en el login.
        return;
      }
      // Si la respuesta se pierde, GET puede confirmar que el servidor sí
      // inició la ruta. Recuperar estado nunca vuelve a enviar POST.
      if (error.statusCode != 401 && error.statusCode != 403) {
        final refreshed = await _load();
        if (!mounted) return;
        if (!refreshed) {
          setState(() {
            _startNeedsRefresh = true;
          });
        }
      }
      message = error.message;
    }
    if (!mounted) return;
    setState(() {
      _startingRouteId = null;
    });
    _notify(messenger, message);
  }

  /// Pide motivo y descripción y registra el intento fallido de la parada en
  /// turno. Solo se confirma con la respuesta persistida del servidor.
  Future<void> _reportFailure(DriverRoute route, DeliveryStop stop) async {
    final stopId = stop.stopId;
    if (_isMutating ||
        _needsRefresh ||
        stopId == null ||
        !route.isInProgress ||
        route.currentStop?.orderId != stop.orderId ||
        !stop.canRecordFailure) {
      return;
    }
    final previous = _failureDraft?.stopId == stopId ? _failureDraft : null;
    final input = await showModalBottomSheet<(FailedVisitReason, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _Tone.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FailedVisitSheet(
        address: stop.address,
        initialReason: previous?.reason,
        initialContext: previous?.context,
      ),
    );
    if (input == null || !mounted || _isMutating) return;
    final (reason, description) = input;
    // Mismos datos que un envío sin confirmar: misma identidad de solicitud.
    final draft =
        previous != null &&
            previous.reason == reason &&
            previous.context == description
        ? previous
        : _FailureDraft(
            stopId: stopId,
            reason: reason,
            context: description,
            requestId: newRequestId(),
          );
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    ++_loadSequence;
    setState(() {
      _failureDraft = draft;
      _failingStopId = stopId;
    });
    String message;
    try {
      await widget.routesService.recordFailedVisit(
        routeId: route.id,
        stopId: stopId,
        reason: draft.reason,
        context: draft.context,
        requestId: draft.requestId,
      );
      final refreshed = await _load();
      if (!mounted) return;
      _failureDraft = null;
      _ordersNeedRefresh = !refreshed;
      message = refreshed
          ? 'Intento fallido registrado.'
          : 'El servidor registró el intento fallido, pero no se pudo actualizar '
                'la lista. Desliza hacia abajo para consultar el estado actual.';
    } on RoutesException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401 &&
          widget.routesService.apiClient.onUnauthorized != null) {
        return;
      }
      message = error.message;
      // La respuesta pudo perderse después de persistir: se consulta GET
      // antes de permitir otro envío, y nunca se reenvía automáticamente.
      if (error.statusCode != 400 &&
          error.statusCode != 401 &&
          error.statusCode != 403) {
        final refreshed = await _load();
        if (!mounted) return;
        _ordersNeedRefresh = !refreshed;
        final persisted = _routes.any(
          (r) => r.stops.any((s) => s.stopId == stopId && s.isFailed),
        );
        if (refreshed && persisted) {
          message = 'El servidor ya había registrado el intento fallido.';
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _failingStopId = null;
    });
    _notify(messenger, message);
    final current = _routes.where((r) => r.id == route.id).firstOrNull;
    if (current != null &&
        current.allStopsResolved &&
        !route.allStopsResolved) {
      _finishedRouteId = current.id;
      await _celebrateIfFinished();
    }
  }

  /// Cierra la ruta cuando todas sus visitas están resueltas. El chofer sigue
  /// ocupado hasta confirmar su llegada al depósito.
  Future<void> _complete(DriverRoute route) async {
    if (_isMutating || _needsRefresh || !route.awaitsCompletion) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        icon: Icons.flag_outlined,
        title: '¿Cerrar la ruta?',
        message:
            '${_finishedDetail(route)}. Después de cerrarla no podrás cambiar '
            'las visitas. Seguirás ocupado hasta confirmar tu llegada al '
            'depósito.',
        confirmLabel: 'Cerrar ruta',
      ),
    );
    if (confirmed != true || !mounted || _isMutating) return;
    await _mutateRoute(
      route,
      onStart: () => _closingRouteId = route.id,
      onEnd: () => _closingRouteId = null,
      request: () async {
        final completedAt = await widget.routesService.completeRoute(route.id);
        return (DriverRoute current) =>
            current.withConfirmedCompletion(completedAt);
      },
      success: 'Ruta cerrada. Regresa al depósito y confirma tu llegada.',
      partial:
          'El servidor cerró la ruta. No se pudo actualizar la lista; '
          'desliza para reintentar.',
    );
  }

  /// Confirma la llegada física al depósito. La disponibilidad que se
  /// muestra después es la que devuelve el servidor.
  Future<void> _confirmReturn(DriverRoute route) async {
    if (_isMutating || _needsRefresh || !route.awaitsReturn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        icon: Icons.home_work_outlined,
        title: '¿Ya estás en el depósito?',
        message:
            'Confirma solo cuando hayas llegado. La app no verifica tu '
            'ubicación: tu confirmación queda registrada en el servidor.',
        confirmLabel: 'Confirmar llegada',
      ),
    );
    if (confirmed != true || !mounted || _isMutating) return;
    await _mutateRoute(
      route,
      onStart: () => _returningRouteId = route.id,
      onEnd: () => _returningRouteId = null,
      request: () async {
        final result = await widget.routesService.confirmReturn(route.id);
        _availability = result.availability;
        return (DriverRoute current) =>
            current.withConfirmedReturn(result.routeStatus, result.returnedAt);
      },
      success: 'Llegada al depósito confirmada.',
      partial:
          'El servidor confirmó tu llegada. No se pudo actualizar la lista; '
          'desliza para reintentar.',
    );
  }

  /// Envía una mutación de la ruta y aplica solo lo que el servidor confirma.
  /// Si la respuesta se pierde, consulta GET; nunca reenvía la mutación.
  Future<void> _mutateRoute(
    DriverRoute route, {
    required VoidCallback onStart,
    required VoidCallback onEnd,
    required Future<DriverRoute Function(DriverRoute)> Function() request,
    required String success,
    required String partial,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    ++_loadSequence;
    setState(onStart);
    String message;
    try {
      final apply = await request();
      if (!mounted) return;
      setState(() {
        _routes = [
          for (final current in _routes)
            if (current.id == route.id) apply(current) else current,
        ];
      });
      final refreshed = await _load();
      message = refreshed ? success : partial;
    } on RoutesException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401 &&
          widget.routesService.apiClient.onUnauthorized != null) {
        return;
      }
      if (error.statusCode != 401 && error.statusCode != 403) {
        final refreshed = await _load();
        if (!mounted) return;
        if (!refreshed) {
          setState(() {
            _closeNeedsRefresh = true;
          });
        }
      }
      message = error.message;
    }
    if (!mounted) return;
    setState(onEnd);
    _notify(messenger, message);
  }

  /// Consulta la disponibilidad efectiva que informa el servidor.
  Future<void> _checkAvailability() async {
    if (_checkingAvailability) return;
    setState(() {
      _checkingAvailability = true;
    });
    String? message;
    try {
      final availability = await widget.routesService.fetchMyAvailability();
      if (!mounted) return;
      _availability = availability;
    } on RoutesException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401 &&
          widget.routesService.apiClient.onUnauthorized != null) {
        return;
      }
      message = error.message;
    }
    if (!mounted) return;
    setState(() {
      _checkingAvailability = false;
    });
    if (message != null) {
      _notify(ScaffoldMessenger.of(context), message);
    }
  }

  /// Muestra solo el resultado más reciente: descarta avisos anteriores que
  /// sigan en cola para que no tapen el de la última acción.
  void _notify(ScaffoldMessengerState messenger, String message) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _enterRoute(DriverRoute route) {
    setState(() {
      _openRouteId = route.id;
    });
  }

  /// Tras la llegada del camión, confirma la ruta si era su última parada.
  Future<void> _celebrateIfFinished() async {
    final route = _routes
        .where((route) => route.id == _finishedRouteId)
        .firstOrNull;
    _finishedRouteId = null;
    if (route == null || !route.allStopsResolved) return;
    final back = await showDialog<bool>(
      context: context,
      builder: (_) => _FinishedDialog(route),
    );
    if (back == true && mounted) _closeRoute();
  }

  void _closeRoute() {
    setState(() {
      _openRouteId = null;
    });
  }

  /// Ruta abierta en la vista de paradas; null muestra las rutas del día.
  DriverRoute? get _openRoute =>
      _routes.where((route) => route.id == _openRouteId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final open = _openRoute;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      // El botón atrás de Android regresa a las rutas del día.
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeRoute();
      },
      child: Scaffold(
        backgroundColor: _Tone.page,
        appBar: AppBar(
          backgroundColor: _Tone.page,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 64,
          titleSpacing: 20,
          automaticallyImplyLeading: false,
          title: open == null
              ? Text(
                  'SPEEDRUN',
                  style: _weight(
                    textTheme.headlineMedium,
                    FontWeight.w800,
                    size: 20,
                    color: AppColors.ink,
                  ),
                )
              : TextButton(
                  onPressed: _closeRoute,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    shape: const RoundedRectangleBorder(),
                    textStyle: _weight(
                      textTheme.bodyLarge,
                      FontWeight.w700,
                      size: 17,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 22),
                      SizedBox(width: 8),
                      Text('Regresar'),
                    ],
                  ),
                ),
          actions: [
            if (_errorMessage != null && _routes.isNotEmpty)
              IconButton(
                onPressed: _isMutating ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Actualizar estado',
              ),
            if (open == null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout, size: 20),
                  tooltip: 'Cerrar sesión',
                  style: IconButton.styleFrom(
                    backgroundColor: _Tone.card,
                    foregroundColor: AppColors.ink,
                    fixedSize: const Size(44, 44),
                    shape: const RoundedRectangleBorder(),
                  ),
                ),
              ),
          ],
        ),
        body: _buildBody(open),
      ),
    );
  }

  Widget _buildBody(DriverRoute? open) {
    final errorMessage = _errorMessage;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null && _routes.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _MessageView(
            icon: Icons.cloud_off_rounded,
            title: 'No se pudieron cargar tus rutas',
            message: errorMessage,
            actionLabel: 'Reintentar',
            onAction: _retry,
          ),
        ),
      );
    }

    // Ambas vistas comparten la misma lista para que deslizar y actualizar
    // no se interrumpa al entrar o salir de una ruta.
    return RefreshIndicator(
      onRefresh: () async {
        if (!_isMutating) await _load();
      },
      child: ListView(
        // Permite deslizar para actualizar aunque la lista sea corta.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (open == null) _Greeting(name: widget.user.name, date: _date),
          if (errorMessage != null || _needsRefresh) ...[
            const SizedBox(height: 16),
            _Notice(
              errorMessage ?? 'El estado de la ruta necesita actualizarse.',
              detail: _ordersNeedRefresh
                  ? 'Actualiza el estado antes de volver a cambiar una entrega.'
                  : _startNeedsRefresh
                  ? 'Actualiza la lista antes de volver a intentar iniciar una ruta.'
                  : _closeNeedsRefresh
                  ? 'Actualiza la lista antes de volver a cerrar la ruta o '
                        'confirmar tu llegada.'
                  : null,
              onRetry: () => _load(),
              retryEnabled: !_isMutating,
            ),
          ],
          if (open != null) ...[
            const SizedBox(height: 8),
            _RouteStops(
              route: open,
              updatingOrderId: _updatingOrderId,
              failingStopId: _failingStopId,
              isLocked: _isMutating || _needsRefresh,
              onAdvance: _advance,
              onFail: (stop) => _reportFailure(open, stop),
              onArrived: _celebrateIfFinished,
              nextStep: _RouteNextStep(
                isBusy:
                    _closingRouteId == open.id || _returningRouteId == open.id,
                isLocked: _isMutating || _needsRefresh,
                onComplete: () => _complete(open),
                onReturn: () => _confirmReturn(open),
              ),
              availability: _availability,
              checkingAvailability: _checkingAvailability,
              onCheckAvailability: _checkAvailability,
            ),
          ] else ...[
            const SizedBox(height: 24),
            if (_routes.isEmpty)
              const _MessageView(
                icon: Icons.event_available_rounded,
                title: 'No tienes rutas para hoy',
                message:
                    'Cuando te asignen una ruta aparecerá aquí. '
                    'Desliza hacia abajo para actualizar.',
              ),
            for (final route in _routes) ...[
              _RouteHero(
                key: ValueKey('route-${route.id}'),
                route: route,
                canStart: widget.user.isDriver && !_needsRefresh,
                isStarting: _startingRouteId == route.id,
                isLocked: _isMutating,
                onStart: () => _start(route),
                onOpen: () => _enterRoute(route),
                nextStep: _RouteNextStep(
                  isBusy:
                      _closingRouteId == route.id ||
                      _returningRouteId == route.id,
                  isLocked: _isMutating || _needsRefresh,
                  onComplete: () => _complete(route),
                  onReturn: () => _confirmReturn(route),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ],
      ),
    );
  }
}

/// Colores de la pantalla: superficies planas y rectas, sin bordes, sombras
/// ni esquinas redondeadas. Tonos sobrios, poco saturados.
class _Tone {
  static const page = Color(0xFFF4F5F7);
  static const card = Colors.white;
  static const blue = Color(0xFF3D5A7A);
  static const green = Color(0xFF3F6B52);
  static const greenSoft = Color(0xFFEDF1EE);
  static const red = Color(0xFFA14A42);
  static const redSoft = Color(0xFFF6EEED);
  static const amber = Color(0xFFB08A4E);
  static const amberSoft = Color(0xFFF7F2EA);
  static const grey = Color(0xFFEDEEF1);
  static const rail = Color(0xFFDADDE3);
  static const fresh = Color(0xFFEDF5F1);
  static const accent = Color(0xFF286B56);

  // Variantes claras para el bloque oscuro de la ruta.
  static const blueOnDark = Color(0xFF9DB2C9);
  static const greenOnDark = Color(0xFF9DBFA9);
  static const redOnDark = Color(0xFFD0968F);
  static const amberOnDark = Color(0xFFD6BC8C);
}

/// Inter es variable: el grosor también se indica como variación.
TextStyle? _weight(
  TextStyle? style,
  FontWeight weight, {
  double? size,
  Color? color,
}) {
  return style?.copyWith(
    fontSize: size,
    color: color,
    fontWeight: weight,
    fontVariations: [FontVariation.weight(weight.value.toDouble())],
  );
}

/// Texto pequeño en mayúsculas que encabeza un bloque.
TextStyle? _overline(BuildContext context, Color color) {
  return _weight(
    Theme.of(context).textTheme.bodySmall,
    FontWeight.w600,
    color: color,
  )?.copyWith(letterSpacing: 1.2);
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.date});
  final String name;
  final String date;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatLongDate(date),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Text(
          'Hola, $name',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontSize: 26),
        ),
      ],
    ),
  );
}

/// Aviso de cada estado de ruta, con su icono.
(IconData, String)? _routeHint(DriverRoute route) {
  return switch (route.status) {
    'IN_PROGRESS' when route.allStopsResolved => (
      Icons.flag_outlined,
      'Todas las visitas están resueltas. Cierra la ruta para registrar su fin.',
    ),
    'INTERRUPTED' when route.returnedAt == null => (
      Icons.report_outlined,
      'La administración interrumpió esta ruta. No atiendas más paradas: '
          'regresa al depósito y confirma tu llegada.',
    ),
    'INTERRUPTED' => (
      Icons.verified_outlined,
      'Ruta interrumpida. Regreso al depósito confirmado; la administración '
          'gestiona los pedidos pendientes.',
    ),
    'COMPLETED' when route.returnedAt == null => (
      Icons.home_work_outlined,
      'Visitas finalizadas. Sigues ocupado: regresa al depósito y confirma tu llegada.',
    ),
    'COMPLETED' => (
      Icons.verified_outlined,
      'Visitas finalizadas. Regreso al depósito confirmado.',
    ),
    _ => null,
  };
}

/// Cuenta solo entregas reales: un intento fallido no suma como entregado.
String _progressText(DriverRoute route) {
  final total = route.stops.length;
  final failed = route.failedCount;
  final delivered = '${route.deliveredCount} de $total entregados';
  return failed == 0 ? delivered : '$delivered · $failed con intento fallido';
}

String _resolvedText(DriverRoute route) =>
    '${(route.deliveredFraction * 100).round()} % entregado · '
    '${route.resolvedCount}/${route.stops.length} visitas resueltas';

/// Tarjeta oscura de una ruta del día. El icono de la esquina la gira para
/// ver por detrás el resumen de sus paradas.
class _RouteHero extends StatefulWidget {
  const _RouteHero({
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
  final _RouteNextStep nextStep;

  @override
  State<_RouteHero> createState() => _RouteHeroState();
}

/// Paso pendiente de una ruta con las visitas resueltas: cerrarla y, después,
/// confirmar el regreso al depósito.
class _RouteNextStep {
  const _RouteNextStep({
    required this.isBusy,
    required this.isLocked,
    required this.onComplete,
    required this.onReturn,
  });

  final bool isBusy;
  final bool isLocked;
  final VoidCallback onComplete;
  final VoidCallback onReturn;

  /// Acción, etiqueta e icono del paso, o null si la ruta no tiene ninguno.
  (VoidCallback, String, IconData, Key)? of(DriverRoute route) {
    if (route.awaitsCompletion) {
      return (
        onComplete,
        isBusy ? 'Cerrando…' : 'Cerrar ruta',
        Icons.flag_rounded,
        ValueKey('complete-route-${route.id}'),
      );
    }
    if (route.awaitsReturn) {
      return (
        onReturn,
        isBusy ? 'Confirmando…' : 'Confirmar llegada al depósito',
        Icons.home_work_rounded,
        ValueKey('return-route-${route.id}'),
      );
    }
    return null;
  }
}

class _RouteHeroState extends State<_RouteHero> {
  bool _showStops = false;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _showStops ? math.pi : 0),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeInOutCubic,
      builder: (context, angle, _) {
        final back = angle > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          // La cara trasera se voltea de nuevo para que no se lea al revés.
          child: back
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(math.pi),
                  child: _card(context, _back(context)),
                )
              : _card(context, _front(context)),
        );
      },
    );
  }

  Widget _card(BuildContext context, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          if (_action(context) case final action?) ...[
            const SizedBox(height: 20),
            action,
          ],
        ],
      ),
    );
  }

  Widget _flipButton() {
    return IconButton(
      key: ValueKey('flip-route-${widget.route.id}'),
      onPressed: () => setState(() => _showStops = !_showStops),
      tooltip: _showStops ? 'Ver la ruta' : 'Ver las paradas',
      icon: Icon(
        _showStops ? Icons.close : Icons.format_list_bulleted,
        size: 20,
      ),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        foregroundColor: Colors.white,
        fixedSize: const Size(44, 44),
        shape: const RoundedRectangleBorder(),
      ),
    );
  }

  List<Widget> _front(BuildContext context) {
    final route = widget.route;
    final textTheme = Theme.of(context).textTheme;
    final hint = _routeHint(route);
    return [
      Row(
        children: [
          Expanded(
            child: route.allStopsResolved
                ? _FinishedBanner(route)
                : Text(
                    'RUTA DEL DÍA',
                    style: _overline(context, Colors.white60),
                  ),
          ),
          _RouteStatusChip(route.status, onDark: true),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: Text(
              route.zoneName,
              style: textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontSize: 32,
              ),
            ),
          ),
          _flipButton(),
        ],
      ),
      const SizedBox(height: 22),
      _RouteProgress(stops: route.stops, onDark: true),
      const SizedBox(height: 14),
      Text(
        _progressText(route),
        style: textTheme.bodyLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        _resolvedText(route),
        style: textTheme.bodySmall?.copyWith(color: Colors.white60),
      ),
      if (hint case (final icon, final text)) ...[
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _back(BuildContext context) {
    final route = widget.route;
    final textTheme = Theme.of(context).textTheme;

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PARADAS · ${route.stops.length}',
                  style: _overline(context, Colors.white60),
                ),
                const SizedBox(height: 6),
                Text(
                  route.zoneName,
                  style: textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _flipButton(),
        ],
      ),
      const SizedBox(height: 20),
      for (final stop in route.stops) ...[
        _CompactStop(stop),
        if (stop != route.stops.last)
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
      ],
    ];
  }

  /// Iniciar si está asignada; si ya empezó, entrar a sus paradas. Si falta
  /// cerrarla o confirmar el regreso, ese paso es la acción principal.
  Widget? _action(BuildContext context) {
    final route = widget.route;
    if (widget.nextStep.of(route) case (
      final onPressed,
      final label,
      final icon,
      final key,
    )) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heroButton(
            context,
            key: key,
            label: label,
            icon: icon,
            busy: widget.nextStep.isBusy,
            onPressed: widget.nextStep.isLocked ? null : onPressed,
          ),
          const SizedBox(height: 6),
          TextButton(
            key: ValueKey('open-route-${route.id}'),
            onPressed: widget.isLocked ? null : widget.onOpen,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('Ver resumen'),
          ),
        ],
      );
    }
    final (key, label, icon) = switch (route.status) {
      'ASSIGNED' when widget.canStart => (
        ValueKey('start-route-${route.id}'),
        widget.isStarting ? 'Iniciando…' : 'Iniciar ruta',
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
    if (label == null) return null;
    final starting = route.status == 'ASSIGNED';
    return _heroButton(
      context,
      key: key!,
      label: label,
      icon: icon!,
      busy: starting && widget.isStarting,
      onPressed: widget.isLocked
          ? null
          : starting
          ? widget.onStart
          : widget.onOpen,
    );
  }

  Widget _heroButton(
    BuildContext context, {
    required Key key,
    required String label,
    required IconData icon,
    required bool busy,
    required VoidCallback? onPressed,
  }) {
    return FilledButton(
      key: key,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.6),
        disabledForegroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: _weight(
          Theme.of(context).textTheme.labelLarge,
          FontWeight.w600,
          size: 15,
        )?.copyWith(letterSpacing: -0.3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.ink,
              ),
            )
          else
            Icon(icon, size: 24),
          const SizedBox(width: 10),
          // Con letra grande la etiqueta pasa a dos líneas en vez de cortarse.
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

/// Fila resumida de una parada en el reverso de la tarjeta.
class _CompactStop extends StatelessWidget {
  const _CompactStop(this.stop);

  final DeliveryStop stop;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (icon, color) = switch (stop) {
      _ when stop.isDelivered => (Icons.check_rounded, _Tone.greenOnDark),
      _ when stop.isFailed => (Icons.close_rounded, _Tone.redOnDark),
      _ when stop.status == 'IN_TRANSIT' => (
        Icons.local_shipping_rounded,
        _Tone.blueOnDark,
      ),
      _ => (Icons.radio_button_unchecked_rounded, Colors.white38),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            color: Colors.white.withValues(alpha: 0.1),
            child: Text(
              stop.stopOrder?.toString() ?? '–',
              style: _weight(
                textTheme.bodyMedium,
                FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              stop.address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _weight(
                textTheme.bodyLarge,
                FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, size: 20, color: color),
        ],
      ),
    );
  }
}

/// Vista de una ruta iniciada: encabezado compacto y las paradas en orden.
class _RouteStops extends StatelessWidget {
  const _RouteStops({
    required this.route,
    required this.updatingOrderId,
    required this.failingStopId,
    required this.isLocked,
    required this.onAdvance,
    required this.onFail,
    required this.onArrived,
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
  final VoidCallback onArrived;
  final _RouteNextStep nextStep;
  final DriverAvailability? availability;
  final bool checkingAvailability;
  final VoidCallback onCheckAvailability;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hint = _routeHint(route);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _Tone.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      route.zoneName,
                      style: textTheme.headlineMedium?.copyWith(fontSize: 26),
                    ),
                  ),
                  _RouteStatusChip(route.status, onDark: false),
                ],
              ),
              const SizedBox(height: 18),
              _RouteProgress(stops: route.stops, onDark: false),
              const SizedBox(height: 12),
              Text(
                _progressText(route),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _resolvedText(route),
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              if (route.startedAt case final startedAt?) ...[
                const SizedBox(height: 6),
                _StartTime(startedAt, color: AppColors.textMuted),
              ],
            ],
          ),
        ),
        if (hint case (_, final text)) ...[
          const SizedBox(height: 14),
          _Notice(text),
        ],
        if (nextStep.of(route) case (
          final onPressed,
          final label,
          final icon,
          final key,
        )) ...[
          const SizedBox(height: 14),
          FilledButton(
            key: key,
            onPressed: nextStep.isLocked ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withValues(
                alpha: 0.45,
              ),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: _weight(
                textTheme.labelLarge,
                FontWeight.w700,
                size: 16,
              ),
            ),
            child: nextStep.isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20),
                      const SizedBox(width: 10),
                      Flexible(child: Text(label)),
                    ],
                  ),
          ),
        ],
        if (route.status == 'COMPLETED' || route.isInterrupted) ...[
          const SizedBox(height: 14),
          _LifecycleSummary(
            route: route,
            availability: availability,
            checkingAvailability: checkingAvailability,
            onCheckAvailability: onCheckAvailability,
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(child: Text('Paradas', style: textTheme.titleLarge)),
            Text(
              '${route.stops.length} en tu ruta',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < route.stops.length; i++)
          _StopItem(
            key: ValueKey('stop-${route.stops[i].orderId}'),
            stop: route.stops[i],
            isLast: i == route.stops.length - 1,
            currentStop: route.isInProgress ? route.currentStop : null,
            isUpdating: updatingOrderId == route.stops[i].orderId,
            isFailing:
                failingStopId != null && failingStopId == route.stops[i].stopId,
            isLocked: isLocked,
            onAdvance: () => onAdvance(route.stops[i]),
            onFail: () => onFail(route.stops[i]),
            onArrived: onArrived,
          ),
      ],
    );
  }
}

/// Distingue los pasos del cierre: visitas resueltas, ruta cerrada, regreso
/// confirmado y disponibilidad informada por el servidor.
class _LifecycleSummary extends StatelessWidget {
  const _LifecycleSummary({
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _Tone.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LifecycleRow(
            done: route.allStopsResolved,
            title: 'Visitas',
            detail:
                '${route.resolvedCount}/${route.stops.length} resueltas · '
                '${_finishedDetail(route)}',
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
                child: Text(
                  checkingAvailability ? 'Consultando…' : 'Consultar',
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 20,
            color: done ? _Tone.green : _Tone.amber,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _weight(
                    textTheme.bodyMedium,
                    FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.text),
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

class _StartTime extends StatelessWidget {
  const _StartTime(this.startedAt, {required this.color});

  final DateTime startedAt;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.schedule_rounded, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            formatRouteStart(startedAt),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Hora confirmada por el servidor, independiente de la zona del teléfono.
String formatRouteStart(DateTime time) =>
    'Inicio: ${formatEcuadorTime(time)} (Ecuador)';

/// `HH:mm` en hora de Ecuador (UTC-5), sin depender de la zona del teléfono.
String formatEcuadorTime(DateTime time) {
  final local = time.toUtc().subtract(const Duration(hours: 5));
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _RouteStatusChip extends StatelessWidget {
  const _RouteStatusChip(this.status, {required this.onDark});

  final String status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final muted = onDark ? Colors.white54 : AppColors.textMuted;
    final (label, dot) = switch (status) {
      'IN_PROGRESS' => ('En curso', onDark ? _Tone.blueOnDark : _Tone.blue),
      'COMPLETED' => ('Completada', onDark ? _Tone.greenOnDark : _Tone.green),
      'INTERRUPTED' => ('Interrumpida', onDark ? _Tone.redOnDark : _Tone.red),
      'ASSIGNED' => ('Asignada', onDark ? _Tone.amberOnDark : _Tone.amber),
      'DRAFT' => ('Borrador', muted),
      _ => ('Sin verificar', muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.12) : _Tone.fresh,
        borderRadius: BorderRadius.circular(onDark ? 0 : 6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.rectangle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: _weight(
              Theme.of(context).textTheme.labelSmall,
              FontWeight.w600,
              color: onDark ? Colors.white : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un segmento por visita: el color distingue éxito, fallo y pendiente.
class _RouteProgress extends StatelessWidget {
  const _RouteProgress({required this.stops, required this.onDark});
  final List<DeliveryStop> stops;
  final bool onDark;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < stops.length; i++) ...[
        if (i > 0) const SizedBox(width: 5),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            height: 4,
            decoration: BoxDecoration(
              color: stops[i].isDelivered
                  ? (onDark ? _Tone.greenOnDark : _Tone.green)
                  : stops[i].isFailed
                  ? (onDark ? _Tone.redOnDark : _Tone.red)
                  : stops[i].status == 'IN_TRANSIT'
                  ? (onDark ? _Tone.blueOnDark : _Tone.blue)
                  : (onDark ? Colors.white24 : _Tone.rail),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    ],
  );
}

/// Una parada compacta; la parada actual muestra su acción y recorrido.
/// Al confirmarse la entrega, el camión termina su recorrido antes de mostrar
/// el resultado.
class _StopItem extends StatefulWidget {
  const _StopItem({
    super.key,
    required this.stop,
    required this.isLast,
    required this.currentStop,
    required this.isUpdating,
    required this.isFailing,
    required this.isLocked,
    required this.onAdvance,
    required this.onFail,
    required this.onArrived,
  });

  final DeliveryStop stop;
  final bool isLast;

  /// Parada en turno de una ruta en curso; null si no se puede avanzar.
  final DeliveryStop? currentStop;
  final bool isUpdating;
  final bool isFailing;
  final bool isLocked;
  final VoidCallback onAdvance;
  final VoidCallback onFail;

  /// Se llama cuando el camión llega al destino tras confirmar la entrega.
  final VoidCallback onArrived;

  @override
  State<_StopItem> createState() => _StopItemState();
}

class _StopItemState extends State<_StopItem> {
  /// La entrega ya está confirmada, pero el camión aún va llegando.
  bool _arriving = false;

  @override
  void didUpdateWidget(_StopItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.stop;
    if (before.status == 'IN_TRANSIT' &&
        !before.isDelivered &&
        !before.isFailed &&
        widget.stop.isDelivered) {
      _arriving = true;
    }
  }

  void _arrived() {
    if (!mounted || !_arriving) return;
    setState(() {
      _arriving = false;
    });
    widget.onArrived();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: widget.isLast ? 0 : 8),
    child: _StopCard(
      stop: widget.stop,
      arriving: _arriving,
      onArrived: _arrived,
      currentStop: widget.currentStop,
      isUpdating: widget.isUpdating,
      isFailing: widget.isFailing,
      isLocked: widget.isLocked,
      onAdvance: widget.onAdvance,
      onFail: widget.onFail,
    ),
  );
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.stop,
    required this.arriving,
    required this.onArrived,
    required this.currentStop,
    required this.isUpdating,
    required this.isFailing,
    required this.isLocked,
    required this.onAdvance,
    required this.onFail,
  });

  final DeliveryStop stop;
  final bool arriving;
  final VoidCallback onArrived;
  final DeliveryStop? currentStop;
  final bool isUpdating;
  final bool isFailing;
  final bool isLocked;
  final VoidCallback onAdvance;
  final VoidCallback onFail;

  /// Estado visible de la parada. Mientras el camión llega se mantiene el
  /// trayecto, con la misma clave, para que su animación continúe.
  Widget _status() {
    if (!arriving && stop.status == 'ASSIGNED') {
      return const SizedBox.shrink();
    }
    if (stop.isDelivered && !arriving) {
      return const _ResultPanel(
        key: ValueKey('delivered'),
        icon: Icons.check_rounded,
        label: 'Entregado con éxito',
        color: _Tone.green,
        background: _Tone.greenSoft,
      );
    }
    if (stop.isFailed) {
      return _ResultPanel(
        key: const ValueKey('failed'),
        icon: Icons.close_rounded,
        label: _failedLabel(stop),
        color: _Tone.red,
        background: _Tone.redSoft,
      );
    }
    return Column(
      key: const ValueKey('open'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (arriving || stop.status == 'IN_TRANSIT') ...[
          _TransitTrack(arrived: arriving, onArrived: onArrived),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pending = !stop.isFailed && !stop.isDelivered;
    final action = switch (stop.status) {
      'ASSIGNED' when pending => (
        'En camino',
        Icons.local_shipping_rounded,
        _Tone.accent,
      ),
      'IN_TRANSIT' when pending => (
        'Entregado',
        Icons.check_circle_rounded,
        _Tone.green,
      ),
      _ => null,
    };
    final current = currentStop;
    final isTurn = current != null && current.orderId == stop.orderId;
    if (!isTurn && !arriving) {
      final color = stop.isFailed
          ? _Tone.red
          : stop.isDelivered
          ? _Tone.green
          : AppColors.textMuted;
      return Container(
        decoration: BoxDecoration(
          color: _Tone.card,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: stop.isDelivered ? _Tone.fresh : _Tone.grey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${stop.stopOrder ?? '–'}',
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.address,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (stop.isDelivered || stop.isFailed) ...[
                    Text(
                      stop.isFailed
                          ? _failedLabel(stop)
                          : 'Entregado con éxito',
                      style: textTheme.bodySmall?.copyWith(color: color),
                    ),
                    if (stop.isFailed && stop.failureContext != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        stop.failureContext!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ] else
                    Text(
                      _stopStatusLabel(stop),
                      style: textTheme.bodySmall?.copyWith(color: color),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              stop.isFailed
                  ? Icons.close
                  : stop.isDelivered
                  ? Icons.check
                  : Icons.lock_outline,
              size: 16,
              color: color,
            ),
          ],
        ),
      );
    }

    // La dirección y el botón comparten esta columna: así se ubica la
    // acción de cada parada.
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Tone.fresh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AHORA · PARADA ${stop.stopOrder ?? '–'}',
            style: _overline(context, _Tone.accent),
          ),
          const SizedBox(height: 6),
          Text(
            stop.address,
            style: _weight(
              textTheme.titleMedium,
              FontWeight.w700,
              size: 21,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              child: _status(),
            ),
          ),
          if (action case (
            final label,
            final icon,
            final color,
          ) when isTurn) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isLocked ? null : onAdvance,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: color.withValues(alpha: 0.45),
                disabledForegroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: _weight(
                  textTheme.labelLarge,
                  FontWeight.w700,
                  size: 16,
                ),
              ),
              child: isUpdating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20),
                        const SizedBox(width: 10),
                        Text(label),
                      ],
                    ),
            ),
          ],
          // Una visita fallida no es una entrega ni una cancelación: queda
          // resuelta y la administración decide qué hacer con el pedido.
          if (isTurn && !arriving && stop.canRecordFailure) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: ValueKey('fail-stop-${stop.orderId}'),
              onPressed: isLocked ? null : onFail,
              style: OutlinedButton.styleFrom(
                foregroundColor: _Tone.red,
                disabledForegroundColor: _Tone.red.withValues(alpha: 0.45),
                side: BorderSide(color: _Tone.red.withValues(alpha: 0.5)),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: _weight(
                  textTheme.labelLarge,
                  FontWeight.w600,
                  size: 15,
                ),
              ),
              child: isFailing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: _Tone.red,
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.report_gmailerrorred_rounded, size: 20),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'No se pudo entregar',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «Intento fallido», con su motivo cuando el servidor lo informa.
String _failedLabel(DeliveryStop stop) => switch (stop.failureReason) {
  final reason? => 'Intento fallido · ${reason.label}',
  null => 'Intento fallido',
};

/// Camión con su paquete recorriendo el trayecto hacia la parada. Al
/// aparecer avanza hasta antes del destino; con [arrived] termina el
/// recorrido y avisa con [onArrived].
class _TransitTrack extends StatelessWidget {
  const _TransitTrack({required this.arrived, required this.onArrived});

  final bool arrived;
  final VoidCallback onArrived;

  static const _truck = 36.0;
  static const _pin = 24.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final travel = constraints.maxWidth - _truck - _pin;
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: arrived ? 1 : 0.65),
                duration: Duration(milliseconds: arrived ? 1000 : 1600),
                curve: Curves.easeInOutCubic,
                onEnd: () {
                  if (arrived) onArrived();
                },
                builder: (context, value, _) {
                  final x = travel * value;
                  final reached = value > 0.98;
                  return SizedBox(
                    height: 46,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: _pin / 2,
                          bottom: 6,
                          height: 3,
                          child: CustomPaint(
                            painter: _DashPainter(
                              _Tone.blue.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          bottom: 5,
                          width: x + _truck / 2,
                          height: 5,
                          child: const ColoredBox(color: _Tone.blue),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Icon(
                            reached
                                ? Icons.check_circle_rounded
                                : Icons.location_on_rounded,
                            size: _pin,
                            color: reached ? _Tone.green : _Tone.blue,
                          ),
                        ),
                        Positioned(
                          left: x,
                          bottom: 12,
                          child: const _TruckWithPackage(size: _truck),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            arrived
                ? 'Llegando al destino'
                : 'Llevando el paquete a esta parada',
            style: _weight(
              Theme.of(context).textTheme.bodyMedium,
              FontWeight.w600,
              color: _Tone.blue,
            ),
          ),
        ],
      ),
    );
  }
}

class _TruckWithPackage extends StatelessWidget {
  const _TruckWithPackage({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Icon(
              Icons.local_shipping_rounded,
              size: size,
              color: _Tone.blue,
            ),
          ),
          Positioned(
            left: size * 0.12,
            top: 0,
            child: Icon(
              Icons.inventory_2_rounded,
              size: size * 0.4,
              color: _Tone.amber,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 10) {
      final end = x + 5 < size.width ? x + 5 : size.width;
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}

/// Resultado de la visita: el icono aparece con un pequeño rebote.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: background),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: _weight(
                Theme.of(context).textTheme.bodyLarge,
                FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado comercial separado del resultado persistido de la visita.
String _stopStatusLabel(DeliveryStop stop) {
  if (stop.hasPersistedVisit && stop.status == 'DELIVERED') {
    return 'Visita sin confirmar';
  }
  return switch (stop.status) {
    'IN_TRANSIT' => 'En camino',
    'CANCELLED' => 'Cancelado',
    'PENDING' => 'Pendiente',
    _ => 'Por entregar',
  };
}

/// Resultado de una ruta con todas sus paradas resueltas, sin dar por
/// exitosa una visita fallida.
String _finishedDetail(DriverRoute route) {
  final delivered = route.deliveredCount;
  final failed = route.failedCount;
  final ok = delivered == 1
      ? '1 entrega exitosa'
      : '$delivered entregas exitosas';
  return failed == 0 ? ok : '$ok · $failed con intento fallido';
}

/// Indicador discreto dentro de la tarjeta al resolver todas las paradas.
class _FinishedBanner extends StatelessWidget {
  const _FinishedBanner(this.route);
  final DriverRoute route;
  @override
  Widget build(BuildContext context) {
    final perfect = route.failedCount == 0;
    final color = perfect ? _Tone.greenOnDark : _Tone.amberOnDark;
    return Row(
      children: [
        Icon(
          perfect ? Icons.check_circle_outline : Icons.flag_outlined,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            perfect ? 'PARADAS COMPLETADAS' : 'PARADAS FINALIZADAS',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Finalizar las visitas no implica liberar al conductor ni cerrar su jornada.
class _FinishedDialog extends StatelessWidget {
  const _FinishedDialog(this.route);
  final DriverRoute route;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final perfect = route.failedCount == 0;
    final total = route.stops.length;
    final color = perfect ? _Tone.accent : _Tone.amber;
    return Dialog(
      backgroundColor: _Tone.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Icon(
                  perfect
                      ? Icons.check_circle_outline_rounded
                      : Icons.flag_outlined,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                perfect ? 'Paradas completadas' : 'Paradas finalizadas',
                style: textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                perfect
                    ? 'Entregaste $total de $total paradas con éxito.'
                    : '${_finishedDetail(route)}.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.text),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.home_work_outlined,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      route.isInProgress
                          ? 'Cierra la ruta y, al llegar al depósito, confirma '
                                'tu llegada.'
                          : route.returnedAt == null
                          ? 'Regresa al depósito y confirma tu llegada.'
                          : 'Regreso al depósito confirmado.',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Volver a mis rutas'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.text,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: textTheme.bodyMedium,
                ),
                child: const Text('Ver paradas'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Intento fallido enviado y aún sin confirmar.
class _FailureDraft {
  const _FailureDraft({
    required this.stopId,
    required this.reason,
    required this.context,
    required this.requestId,
  });

  final String stopId;
  final FailedVisitReason reason;
  final String context;
  final String requestId;
}

/// Hoja para registrar por qué no se pudo entregar: motivo tipificado y una
/// descripción obligatoria, como exige el servidor.
class _FailedVisitSheet extends StatefulWidget {
  const _FailedVisitSheet({
    required this.address,
    this.initialReason,
    this.initialContext,
  });

  final String address;
  final FailedVisitReason? initialReason;
  final String? initialContext;

  @override
  State<_FailedVisitSheet> createState() => _FailedVisitSheetState();
}

class _FailedVisitSheetState extends State<_FailedVisitSheet> {
  static const maxLength = 500;

  late FailedVisitReason? _reason = widget.initialReason;
  late final _description = TextEditingController(text: widget.initialContext);

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  bool get _isValid => _reason != null && _description.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudo entregar', style: textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                widget.address,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Motivo',
                style: _weight(textTheme.bodyMedium, FontWeight.w600),
              ),
              RadioGroup<FailedVisitReason>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: Column(
                  children: [
                    for (final reason in FailedVisitReason.values)
                      RadioListTile<FailedVisitReason>(
                        key: ValueKey('failure-reason-${reason.code}'),
                        value: reason,
                        title: Text(reason.label),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('failure-context'),
                controller: _description,
                maxLength: maxLength,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Qué pasó',
                  hintText: 'Ej.: Nadie respondió tras tocar dos veces.',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'El pedido no se cancela: la administración decide si se '
                'reprograma.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.text),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('submit-failure'),
                onPressed: _isValid
                    ? () => Navigator.of(
                        context,
                      ).pop((_reason!, _description.text.trim()))
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _Tone.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Registrar intento fallido'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.text,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirmación antes de una acción que no se puede deshacer desde la app.
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: _Tone.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Icon(icon, color: AppColors.ink),
      title: Text(title, style: textTheme.titleLarge),
      content: Text(
        message,
        style: textTheme.bodyMedium?.copyWith(color: AppColors.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('confirm-dialog'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Aviso de la pantalla, por ejemplo cuando una recarga falla.
class _Notice extends StatelessWidget {
  const _Notice(
    this.text, {
    this.detail,
    this.onRetry,
    this.retryEnabled = true,
  });

  final String text;
  final String? detail;
  final VoidCallback? onRetry;
  final bool retryEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Tone.amberSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_rounded, size: 20, color: _Tone.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.ink),
                ),
                if (detail case final message?) ...[
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.text),
                  ),
                ],
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Reintentar',
              onPressed: retryEnabled ? onRetry : null,
              icon: const Icon(Icons.refresh_rounded),
              color: AppColors.ink,
            ),
          ],
        ],
      ),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(color: _Tone.card),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: _Tone.page,
              shape: BoxShape.rectangle,
            ),
            child: Icon(icon, size: 38, color: AppColors.ink),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: _weight(textTheme.titleLarge, FontWeight.w800, size: 20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 52),
                shape: const RoundedRectangleBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(actionLabel),
                ],
              ),
            ),
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
