import 'package:app_movil_logistica/core/network/request_id.dart';
import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:app_movil_logistica/features/routes/data/external_navigation.dart';
import 'package:app_movil_logistica/features/routes/data/routes_service.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_card.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_detail.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_dialogs.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_formatters.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_parts.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_style.dart';
import 'package:flutter/material.dart';

export 'package:app_movil_logistica/features/routes/presentation/route_formatters.dart'
    show formatEcuadorTime, formatLongDate, formatRouteStart;

/// «Mi Ruta del Día»: rutas y paradas del chofer para hoy.
class MyRoutePage extends StatefulWidget {
  const MyRoutePage({
    super.key,
    required this.user,
    required this.routesService,
    required this.onLogout,
    this.externalNavigator = const ExternalNavigator(),
  });

  final AuthUser user;
  final RoutesService routesService;
  final VoidCallback onLogout;
  final ExternalNavigator externalNavigator;

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
  FailureDraft? _failureDraft;

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
    await _celebrateIfFinished();
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => FailedVisitSheet(
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
        : FailureDraft(
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
      builder: (_) => ConfirmDialog(
        icon: Icons.flag_outlined,
        title: '¿Cerrar la ruta?',
        message:
            '${finishedDetail(route)}. Después de cerrarla no podrás cambiar '
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
      builder: (_) => const ConfirmDialog(
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
      builder: (_) => FinishedDialog(route),
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

    return PopScope(
      // El botón atrás de Android regresa a las rutas del día.
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeRoute();
      },
      child: Scaffold(
        backgroundColor: RouteTone.page,
        appBar: RouteTopBar(
          onBack: open == null ? null : _closeRoute,
          onRefresh: _errorMessage != null && _routes.isNotEmpty && !_isMutating
              ? _load
              : null,
        ),
        body: Column(
          children: [
            Expanded(child: _buildBody(open)),
            if (open == null && !_isLoading)
              _LogoutBar(name: widget.user.name, onLogout: widget.onLogout),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToStop(DeliveryStop stop) async {
    final app = await _pickMapApp(
      title: 'Navegar a parada ${stop.stopOrder ?? '–'}',
      subtitle: stop.address,
    );
    if (app == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final launched = await widget.externalNavigator.openStop(stop, app);
    if (!mounted) return;
    if (!launched) {
      _notify(messenger, 'No se pudo abrir ${app.label} en este dispositivo.');
    }
  }

  Future<void> _navigateToDepot(DriverRoute route) async {
    if (!route.hasDepotCoordinates) return;
    final app = await _pickMapApp(
      title: 'Navegar al depósito',
      subtitle: 'Regreso al punto de partida de la ruta',
    );
    if (app == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final launched = await widget.externalNavigator.openDepot(
      lat: route.depotLat!,
      lng: route.depotLng!,
      app: app,
    );
    if (!mounted) return;
    if (!launched) {
      _notify(messenger, 'No se pudo abrir ${app.label} en este dispositivo.');
    }
  }

  Future<void> _openFullRouteInMaps(DriverRoute route) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.externalNavigator.openFullRoute(route);
    if (!mounted) return;
    if (!result.launched) {
      _notify(
        messenger,
        'No se pudo abrir Google Maps en este dispositivo.',
      );
      return;
    }
    if (result.omittedCount > 0) {
      _notify(
        messenger,
        'Se abrieron las primeras ${ExternalNavigator.maxGoogleMapsStops} '
        'paradas pendientes en Google Maps.',
      );
    }
  }

  Future<ExternalMapApp?> _pickMapApp({
    required String title,
    required String subtitle,
  }) => showModalBottomSheet<ExternalMapApp>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (_) => _NavigationAppSheet(title: title, subtitle: subtitle),
  );

  Widget _buildBody(DriverRoute? open) {
    final errorMessage = _errorMessage;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null && _routes.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: pagePadding),
          child: RouteMessage(
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
      color: RouteTone.ink,
      onRefresh: () async {
        if (!_isMutating) await _load();
      },
      child: ListView(
        // Permite deslizar para actualizar aunque la lista sea corta.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(pagePadding, 4, pagePadding, 48),
        children: [
          if (open == null) _Greeting(name: widget.user.name, date: _date),
          if (errorMessage != null || _needsRefresh) ...[
            const SizedBox(height: 16),
            RouteNotice(
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
            const SizedBox(height: 12),
            RouteDetail(
              route: open,
              updatingOrderId: _updatingOrderId,
              failingStopId: _failingStopId,
              isLocked: _isMutating || _needsRefresh,
              onAdvance: _advance,
              onFail: (stop) => _reportFailure(open, stop),
              onNavigateFullRoute: () => _openFullRouteInMaps(open),
              onNavigateDepot: () => _navigateToDepot(open),
              onNavigateStop: _navigateToStop,
              nextStep: _nextStep(open),
              availability: _availability,
              checkingAvailability: _checkingAvailability,
              onCheckAvailability: _checkAvailability,
            ),
          ] else ...[
            const SizedBox(height: 28),
            if (_routes.isEmpty)
              const RouteMessage(
                icon: Icons.event_available_outlined,
                title: 'No tienes rutas para hoy',
                message:
                    'Cuando te asignen una ruta aparecerá aquí. '
                    'Desliza hacia abajo para actualizar.',
              ),
            for (final route in _routes) ...[
              RouteCard(
                key: ValueKey('route-${route.id}'),
                route: route,
                canStart: widget.user.isDriver && !_needsRefresh,
                isStarting: _startingRouteId == route.id,
                isLocked: _isMutating,
                onStart: () => _start(route),
                onOpen: () => _enterRoute(route),
                nextStep: _nextStep(route),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ],
      ),
    );
  }

  RouteNextStep _nextStep(DriverRoute route) => RouteNextStep(
    isBusy: _closingRouteId == route.id || _returningRouteId == route.id,
    isLocked: _isMutating || _needsRefresh,
    onComplete: () => _complete(route),
    onReturn: () => _confirmReturn(route),
  );
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.date});

  final String name;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatLongDate(date).toUpperCase(),
                  style: overline(context),
                ),
                const SizedBox(height: 10),
                Text('Hola, $name', style: display(context, size: 26)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: RouteTone.ink,
              borderRadius: RouteRadius.tile,
            ),
            child: Text(
              _initials(name),
              style: display(context, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Iniciales de las dos primeras palabras del nombre.
String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}

/// Pie de la pantalla de rutas: quién tiene la sesión y cómo cerrarla.
class _LogoutBar extends StatelessWidget {
  const _LogoutBar({required this.name, required this.onLogout});

  final String name;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: RouteTone.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(pagePadding, 12, pagePadding, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sesión iniciada',
                      style: textTheme.bodySmall?.copyWith(
                        color: RouteTone.muted,
                      ),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: weighted(
                        textTheme.bodyMedium,
                        FontWeight.w700,
                        color: RouteTone.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const ValueKey('logout'),
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Cerrar sesión'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RouteTone.ink,
                  side: const BorderSide(color: RouteTone.track),
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.button,
                  ),
                  textStyle: weighted(
                    textTheme.labelLarge,
                    FontWeight.w600,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationAppSheet extends StatelessWidget {
  const _NavigationAppSheet({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: display(context, size: 18)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: RouteTone.muted),
            ),
            const SizedBox(height: 16),
            ListTile(
              key: const ValueKey('nav-app-google-maps'),
              leading: const Icon(Icons.map_outlined, color: RouteTone.ink),
              title: const Text('Google Maps'),
              subtitle: const Text('Abrir ruta guiada en Google Maps'),
              shape: const RoundedRectangleBorder(
                borderRadius: RouteRadius.tile,
              ),
              tileColor: RouteTone.surface,
              onTap: () => Navigator.of(context).pop(ExternalMapApp.googleMaps),
            ),
            const SizedBox(height: 10),
            ListTile(
              key: const ValueKey('nav-app-waze'),
              leading: const Icon(
                Icons.navigation_rounded,
                color: RouteTone.ink,
              ),
              title: const Text('Waze'),
              subtitle: const Text('Abrir navegación en Waze'),
              shape: const RoundedRectangleBorder(
                borderRadius: RouteRadius.tile,
              ),
              tileColor: RouteTone.surface,
              onTap: () => Navigator.of(context).pop(ExternalMapApp.waze),
            ),
          ],
        ),
      ),
    );
  }
}
