/// Motivos tipificados de una visita fallida, tal como los acepta el backend
/// en `POST /routes/:id/stops/:stopId/failure`.
enum FailedVisitReason {
  recipientAbsent('RECIPIENT_ABSENT', 'Destinatario ausente'),
  recipientRefused('RECIPIENT_REFUSED', 'Rechazó el pedido');

  const FailedVisitReason(this.code, this.label);

  final String code;
  final String label;

  static FailedVisitReason? fromCode(String? code) =>
      values.where((reason) => reason.code == code).firstOrNull;
}

/// Una parada de la ruta: el pedido a entregar y el resultado de su visita.
class DeliveryStop {
  const DeliveryStop({
    required this.orderId,
    required this.address,
    required this.status,
    required this.stopOrder,
    this.deliveryLat,
    this.deliveryLng,
    this.stopId,
    this.isLegacy = false,
    this.outcome,
    this.hasPersistedVisit = false,
    this.failureReason,
    this.failureContext,
  });

  final String orderId;
  final String address;

  /// Estado comercial del pedido: PENDING, ASSIGNED, IN_TRANSIT, DELIVERED
  /// o CANCELLED.
  final String status;

  /// Posición en la ruta; puede faltar en rutas antiguas.
  final int? stopOrder;

  /// Coordenadas de entrega enviadas por el backend; pueden faltar en pedidos antiguos.
  final double? deliveryLat;
  final double? deliveryLng;

  bool get hasCoordinates => deliveryLat != null && deliveryLng != null;

  /// Id de la visita (`RouteStop`). Solo las visitas verificadas lo tienen y
  /// solo con él se puede registrar un intento fallido.
  final String? stopId;
  final bool isLegacy;

  /// Resultado de la visita: SUCCESSFUL, FAILED, PENDING o null (legado).
  final String? outcome;
  final bool hasPersistedVisit;

  /// Motivo y descripción del intento fallido persistido, si existe.
  final FailedVisitReason? failureReason;
  final String? failureContext;

  bool get isFailed => outcome == 'FAILED';
  // El estado comercial puede cambiar por una entrega en otra ruta.
  // Solo las rutas antiguas sin RouteStop usan el estado como respaldo.
  bool get isDelivered =>
      outcome == 'SUCCESSFUL' ||
      (!hasPersistedVisit && outcome == null && status == 'DELIVERED');

  /// El backend solo acepta un intento fallido sobre una visita verificada
  /// y pendiente cuyo pedido sigue en reparto.
  bool get canRecordFailure =>
      stopId != null &&
      !isLegacy &&
      outcome == 'PENDING' &&
      (status == 'ASSIGNED' || status == 'IN_TRANSIT');
}

/// Una ruta asignada al chofer, tal como la devuelve
/// `GET /drivers/me/routes`.
class DriverRoute {
  const DriverRoute({
    required this.id,
    required this.status,
    required this.zoneName,
    required this.zoneCode,
    required this.stops,
    this.depotLat,
    this.depotLng,
    this.startedAt,
    this.completedAt,
    this.returnedAt,
    this.interruptionReason,
  });

  factory DriverRoute.fromJson(Map<String, dynamic> json) {
    // Las rutas de la era de cobertura de tienda pueden no tener zona.
    final zone = json['zone'] as Map<String, dynamic>?;
    final depot = json['depot'] as Map<String, dynamic>?;

    // El resultado de cada visita viene en `stops`; lo cruzamos por pedido.
    final visits = <String, Map<String, dynamic>>{
      for (final stop
          in (json['stops'] as List? ?? const []).cast<Map<String, dynamic>>())
        stop['orderId'] as String: stop,
    };

    final stops = (json['orders'] as List).cast<Map<String, dynamic>>().map((
      order,
    ) {
      final visit = visits[order['id']];
      final failure = _failedAttempt(visit);
      return DeliveryStop(
        orderId: order['id'] as String,
        address: order['deliveryAddress'] as String,
        status: order['status'] as String,
        stopOrder: order['stopOrder'] as int?,
        deliveryLat: (order['deliveryLat'] as num?)?.toDouble(),
        deliveryLng: (order['deliveryLng'] as num?)?.toDouble(),
        stopId: visit?['id'] as String?,
        isLegacy: visit?['isLegacy'] as bool? ?? false,
        outcome: visit?['outcome'] as String?,
        hasPersistedVisit: visit != null,
        failureReason: FailedVisitReason.fromCode(
          failure?['failureReason'] as String?,
        ),
        failureContext: failure?['context'] as String?,
      );
    }).toList()..sort(_byStopOrder);

    final emergency = json['emergency'] as Map<String, dynamic>?;
    return DriverRoute(
      id: json['id'] as String,
      status: json['status'] as String,
      zoneName: zone?['name'] as String? ?? 'Ruta sin zona',
      zoneCode: zone?['code'] as String?,
      stops: stops,
      depotLat: (depot?['lat'] as num?)?.toDouble(),
      depotLng: (depot?['lng'] as num?)?.toDouble(),
      startedAt: _instant(json['startedAt']),
      completedAt: _instant(json['completedAt']),
      returnedAt: _instant(json['returnedAt']),
      interruptionReason: emergency?['reason'] as String?,
    );
  }

  final String id;

  /// Estado de la ruta: UNVERIFIED, DRAFT, ASSIGNED, IN_PROGRESS, COMPLETED
  /// o INTERRUPTED.
  final String status;
  final String zoneName;
  final String? zoneCode;
  final List<DeliveryStop> stops;
  final double? depotLat;
  final double? depotLng;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? returnedAt;

  /// Motivo que dio la administración al interrumpir la ruta.
  final String? interruptionReason;

  bool get hasDepotCoordinates => depotLat != null && depotLng != null;

  List<DeliveryStop> get pendingStops =>
      stops.where((stop) => !stop.isDelivered && !stop.isFailed).toList();

  DriverRoute _copy({
    String? status,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? returnedAt,
  }) => DriverRoute(
    id: id,
    status: status ?? this.status,
    zoneName: zoneName,
    zoneCode: zoneCode,
    stops: stops,
    depotLat: depotLat,
    depotLng: depotLng,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    returnedAt: returnedAt ?? this.returnedAt,
    interruptionReason: interruptionReason,
  );

  /// Aplica únicamente la confirmación del endpoint de inicio, sin alterar
  /// composición, orden ni resultados de las paradas ya consultadas.
  DriverRoute withConfirmedStart(DateTime time) =>
      _copy(status: 'IN_PROGRESS', startedAt: time);

  /// Aplica el cierre confirmado por `POST /routes/:id/complete`.
  DriverRoute withConfirmedCompletion(DateTime time) =>
      _copy(status: 'COMPLETED', completedAt: time);

  /// Aplica el regreso confirmado por `POST /routes/:id/return`.
  DriverRoute withConfirmedReturn(String status, DateTime time) =>
      _copy(status: status, returnedAt: time);

  /// Solo con la ruta iniciada el backend acepta "En camino" y "Entregado".
  bool get isInProgress => status == 'IN_PROGRESS';

  /// La administración detuvo la ruta por una emergencia.
  bool get isInterrupted => status == 'INTERRUPTED';

  /// Ruta en curso con todas sus visitas resueltas: falta cerrarla.
  bool get awaitsCompletion => isInProgress && allStopsResolved;

  /// Ruta cerrada o interrumpida cuyo regreso al depósito aún no se confirmó.
  /// Hasta entonces el chofer sigue ocupado.
  bool get awaitsReturn =>
      (status == 'COMPLETED' || isInterrupted) && returnedAt == null;

  /// Parada que el chofer atiende ahora; las demás esperan su turno. Es la
  /// que ya va en camino o, si no hay, la primera por entregar según el
  /// orden. Un intento fallido también cuenta como parada terminada.
  DeliveryStop? get currentStop {
    final open = stops.where((stop) => !stop.isDelivered && !stop.isFailed);
    return open.where((stop) => stop.status == 'IN_TRANSIT').firstOrNull ??
        open.where((stop) => stop.status == 'ASSIGNED').firstOrNull;
  }

  /// Todas las paradas tienen resultado: entregadas o con intento fallido.
  bool get allStopsResolved =>
      stops.isNotEmpty &&
      stops.every((stop) => stop.isDelivered || stop.isFailed);

  int get deliveredCount => stops.where((stop) => stop.isDelivered).length;

  int get failedCount => stops.where((stop) => stop.isFailed).length;

  int get resolvedCount => deliveredCount + failedCount;

  double get deliveredFraction =>
      stops.isEmpty ? 0 : deliveredCount / stops.length;
}

/// Disponibilidad efectiva del chofer según el servidor. La app nunca la
/// deduce del estado de una ruta.
class DriverAvailability {
  const DriverAvailability({
    required this.isAvailable,
    required this.hasPersistedHolds,
    required this.blockingRouteIds,
  });

  factory DriverAvailability.fromJson(Map<String, dynamic> json) =>
      DriverAvailability(
        isAvailable: json['isAvailable'] as bool,
        hasPersistedHolds: json['hasPersistedHolds'] as bool,
        blockingRouteIds: (json['blockingRouteIds'] as List)
            .cast<String>()
            .toList(),
      );

  final bool isAvailable;
  final bool hasPersistedHolds;
  final List<String> blockingRouteIds;
}

/// Respuesta persistida de `POST /routes/:id/return`.
class DepotReturn {
  const DepotReturn({
    required this.routeStatus,
    required this.returnedAt,
    required this.availability,
  });

  final String routeStatus;
  final DateTime returnedAt;
  final DriverAvailability availability;
}

/// Último intento fallido persistido de la visita, si lo hay.
Map<String, dynamic>? _failedAttempt(Map<String, dynamic>? visit) {
  final attempts = (visit?['attempts'] as List? ?? const [])
      .cast<Map<String, dynamic>>()
      .where((attempt) => attempt['outcome'] == 'FAILED');
  return attempts.lastOrNull;
}

DateTime? _instant(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Ordena por `stopOrder` ascendente, las paradas sin posición al final y,
/// en empate, por id (el mismo criterio que usa el backend).
int _byStopOrder(DeliveryStop a, DeliveryStop b) {
  final first = a.stopOrder;
  final second = b.stopOrder;
  if (first != second) {
    if (first == null) {
      return 1;
    }
    if (second == null) {
      return -1;
    }
    return first.compareTo(second);
  }
  return a.orderId.compareTo(b.orderId);
}
