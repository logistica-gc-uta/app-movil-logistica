import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> order(String id, int? stopOrder, String status) {
  return {
    'id': id,
    'deliveryAddress': 'Calle $id',
    'status': status,
    'scheduledDeliveryDate': null,
    'stopOrder': stopOrder,
  };
}

Map<String, dynamic> routeJson({
  required List<Map<String, dynamic>> orders,
  List<Map<String, dynamic>> stops = const [],
}) {
  return {
    'id': 'r1',
    'date': '2026-10-18T05:00:00Z',
    'zone': {'id': 'z1', 'name': 'Centro', 'code': 'CEN-01'},
    'status': 'IN_PROGRESS',
    'orders': orders,
    'startedAt': '2026-10-18T13:00:00Z',
    'stops': stops,
    'events': <Map<String, dynamic>>[],
  };
}

void main() {
  test('lee la zona, el estado y las paradas de la respuesta', () {
    final route = DriverRoute.fromJson(
      routeJson(orders: [order('o1', 1, 'ASSIGNED')]),
    );

    expect(route.zoneName, 'Centro');
    expect(route.zoneCode, 'CEN-01');
    expect(route.isInProgress, true);
    expect(route.stops.single.address, 'Calle o1');
  });

  test('ordena por stopOrder y deja las paradas sin posición al final', () {
    final route = DriverRoute.fromJson(
      routeJson(
        orders: [
          order('o3', null, 'ASSIGNED'),
          order('o2', 2, 'ASSIGNED'),
          order('o1', 1, 'ASSIGNED'),
        ],
      ),
    );

    expect(route.stops.map((stop) => stop.orderId), ['o1', 'o2', 'o3']);
  });

  test('un intento fallido no cuenta como entregado', () {
    final route = DriverRoute.fromJson(
      routeJson(
        orders: [
          order('o1', 1, 'DELIVERED'),
          order('o2', 2, 'DELIVERED'),
          order('o3', 3, 'DELIVERED'),
          order('o4', 4, 'ASSIGNED'),
        ],
        stops: [
          {'orderId': 'o1', 'outcome': 'SUCCESSFUL'},
          {'orderId': 'o2', 'outcome': 'SUCCESSFUL'},
          {'orderId': 'o3', 'outcome': 'SUCCESSFUL'},
          {'orderId': 'o4', 'outcome': 'FAILED'},
        ],
      ),
    );

    expect(route.deliveredCount, 3);
    expect(route.failedCount, 1);
    expect(route.stops.last.isFailed, true);
  });

  test('una entrega posterior no cambia el resultado histórico fallido', () {
    final route = DriverRoute.fromJson(
      routeJson(
        orders: [order('o1', 1, 'DELIVERED')],
        stops: [
          {'orderId': 'o1', 'outcome': 'FAILED'},
        ],
      ),
    );
    expect(route.deliveredCount, 0);
    expect(route.failedCount, 1);
  });

  test('una visita persistida sin resultado no cuenta como entregada', () {
    final route = DriverRoute.fromJson(
      routeJson(
        orders: [order('o1', 1, 'DELIVERED')],
        stops: [
          {'orderId': 'o1', 'outcome': null},
        ],
      ),
    );
    expect(route.deliveredCount, 0);
  });

  test('conserva éxito histórico aunque cambie el estado comercial', () {
    final route = DriverRoute.fromJson(
      routeJson(
        orders: [order('o1', 1, 'ASSIGNED')],
        stops: [
          {'orderId': 'o1', 'outcome': 'SUCCESSFUL'},
        ],
      ),
    );
    expect(route.deliveredCount, 1);
  });

  test('rutas antiguas sin visitas conservan el respaldo comercial', () {
    final route = DriverRoute.fromJson(
      routeJson(orders: [order('o1', 1, 'DELIVERED')]),
    );
    expect(route.deliveredCount, 1);
  });
}
