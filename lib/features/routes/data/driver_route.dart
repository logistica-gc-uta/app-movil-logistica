/// Una parada de la ruta: el pedido a entregar y el resultado de su visita.
class DeliveryStop {
  const DeliveryStop({
    required this.orderId,
    required this.address,
    required this.status,
    required this.stopOrder,
    this.outcome,
    this.hasPersistedVisit = false,
  });

  final String orderId;
  final String address;

  /// Estado comercial del pedido: PENDING, ASSIGNED, IN_TRANSIT, DELIVERED
  /// o CANCELLED.
  final String status;

  /// Posición en la ruta; puede faltar en rutas antiguas.
  final int? stopOrder;

  /// Resultado de la visita: SUCCESSFUL, FAILED, PENDING o null (legado).
  final String? outcome;
  final bool hasPersistedVisit;

  bool get isFailed => outcome == 'FAILED';
  // El estado comercial puede cambiar por una entrega en otra ruta.
  // Solo las rutas antiguas sin RouteStop usan el estado como respaldo.
  bool get isDelivered =>
      outcome == 'SUCCESSFUL' ||
      (!hasPersistedVisit && outcome == null && status == 'DELIVERED');
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
    this.startedAt,
    this.returnedAt,
  });

  factory DriverRoute.fromJson(Map<String, dynamic> json) {
    final zone = json['zone'] as Map<String, dynamic>;

    // El resultado de cada visita viene en `stops`; lo cruzamos por pedido.
    final outcomes = <String, String?>{
      for (final stop
          in (json['stops'] as List? ?? const []).cast<Map<String, dynamic>>())
        stop['orderId'] as String: stop['outcome'] as String?,
    };

    final stops =
        (json['orders'] as List)
            .cast<Map<String, dynamic>>()
            .map(
              (order) => DeliveryStop(
                orderId: order['id'] as String,
                address: order['deliveryAddress'] as String,
                status: order['status'] as String,
                stopOrder: order['stopOrder'] as int?,
                outcome: outcomes[order['id']],
                hasPersistedVisit: outcomes.containsKey(order['id']),
              ),
            )
            .toList()
          ..sort(_byStopOrder);

    return DriverRoute(
      id: json['id'] as String,
      status: json['status'] as String,
      zoneName: zone['name'] as String,
      zoneCode: zone['code'] as String,
      stops: stops,
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      returnedAt: DateTime.tryParse(json['returnedAt'] as String? ?? ''),
    );
  }

  final String id;

  /// Estado de la ruta: UNVERIFIED, DRAFT, ASSIGNED, IN_PROGRESS o COMPLETED.
  final String status;
  final String zoneName;
  final String zoneCode;
  final List<DeliveryStop> stops;
  final DateTime? startedAt;
  final DateTime? returnedAt;

  /// Aplica únicamente la confirmación del endpoint de inicio, sin alterar
  /// composición, orden ni resultados de las paradas ya consultadas.
  DriverRoute withConfirmedStart(DateTime time) => DriverRoute(
    id: id,
    status: 'IN_PROGRESS',
    zoneName: zoneName,
    zoneCode: zoneCode,
    stops: stops,
    startedAt: time,
    returnedAt: returnedAt,
  );

  /// Solo con la ruta iniciada el backend acepta "En camino" y "Entregado".
  bool get isInProgress => status == 'IN_PROGRESS';

  int get deliveredCount => stops.where((stop) => stop.isDelivered).length;

  int get failedCount => stops.where((stop) => stop.isFailed).length;
}

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
