import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:app_movil_logistica/features/routes/data/external_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryStop makeStop(
  String id,
  int stopOrder, {
  double? lat,
  double? lng,
  String status = 'ASSIGNED',
  String? outcome,
}) => DeliveryStop(
  orderId: id,
  address: 'Calle $id 123',
  status: status,
  stopOrder: stopOrder,
  deliveryLat: lat,
  deliveryLng: lng,
  outcome: outcome,
);

DriverRoute makeRoute(List<DeliveryStop> stops) => DriverRoute(
  id: 'r1',
  status: 'IN_PROGRESS',
  zoneName: 'Centro',
  zoneCode: 'CEN-01',
  stops: stops,
  depotLat: -1.24908,
  depotLng: -78.61675,
);

void main() {
  group('ExternalNavigator URL builders', () {
    test('arma deep link de parada por coordenadas para Google Maps y Waze', () {
      final stop = makeStop('o1', 1, lat: -1.241234, lng: -78.619876);

      final mapsUri = ExternalNavigator.buildStopUri(
        stop,
        ExternalMapApp.googleMaps,
      );
      expect(mapsUri.host, 'www.google.com');
      expect(mapsUri.path, '/maps/dir/');
      expect(mapsUri.queryParameters['api'], '1');
      expect(mapsUri.queryParameters['destination'], '-1.241234,-78.619876');
      expect(mapsUri.queryParameters['travelmode'], 'driving');

      final wazeUri = ExternalNavigator.buildStopUri(stop, ExternalMapApp.waze);
      expect(wazeUri.host, 'waze.com');
      expect(wazeUri.path, '/ul');
      expect(wazeUri.queryParameters['ll'], '-1.241234,-78.619876');
      expect(wazeUri.queryParameters['navigate'], 'yes');
    });

    test('usa la dirección como respaldo cuando faltan coordenadas', () {
      final stop = makeStop('o1', 1);

      final mapsUri = ExternalNavigator.buildStopUri(
        stop,
        ExternalMapApp.googleMaps,
      );
      expect(mapsUri.queryParameters['destination'], 'Calle o1 123');

      final wazeUri = ExternalNavigator.buildStopUri(stop, ExternalMapApp.waze);
      expect(wazeUri.queryParameters['q'], 'Calle o1 123');
      expect(wazeUri.queryParameters['navigate'], 'yes');
    });

    test('arma ruta completa en Google Maps solo con paradas pendientes en orden', () {
      final route = makeRoute([
        makeStop('o1', 1, lat: -1.240, lng: -78.610, status: 'DELIVERED', outcome: 'SUCCESSFUL'),
        makeStop('o2', 2, lat: -1.241, lng: -78.611),
        makeStop('o3', 3, lat: -1.242, lng: -78.612, outcome: 'FAILED'),
        makeStop('o4', 4, lat: -1.243, lng: -78.613),
        makeStop('o5', 5, lat: -1.244, lng: -78.614),
      ]);

      final built = ExternalNavigator.buildFullRouteGoogleMapsUri(route);
      expect(built, isNotNull);
      expect(built!.omittedCount, 0);
      expect(
        built.uri.queryParameters['waypoints'],
        '-1.241000,-78.611000|-1.243000,-78.613000',
      );
      expect(built.uri.queryParameters['destination'], '-1.244000,-78.614000');
    });

    test('limita la ruta completa a 10 paradas pendientes e informa las omitidas', () {
      final stops = [
        for (var i = 1; i <= 12; i++)
          makeStop('o$i', i, lat: -1.24 - i * 0.001, lng: -78.61 - i * 0.001),
      ];
      final built = ExternalNavigator.buildFullRouteGoogleMapsUri(
        makeRoute(stops),
      );
      expect(built, isNotNull);
      expect(built!.omittedCount, 2);
      final waypoints = built.uri.queryParameters['waypoints']!.split('|');
      expect(waypoints, hasLength(9));
    });

    test('devuelve null cuando no quedan paradas pendientes', () {
      final route = makeRoute([
        makeStop('o1', 1, lat: -1.24, lng: -78.61, status: 'DELIVERED', outcome: 'SUCCESSFUL'),
      ]);
      expect(ExternalNavigator.buildFullRouteGoogleMapsUri(route), isNull);
    });

    test('maneja fallos del launcher sin lanzar excepciones', () async {
      final nav = ExternalNavigator(
        launcher: (_) async => throw Exception('No app'),
      );
      final stop = makeStop('o1', 1, lat: -1.24, lng: -78.61);

      expect(await nav.openStop(stop, ExternalMapApp.waze), isFalse);
      expect(
        await nav.openDepot(
          lat: -1.24908,
          lng: -78.61675,
          app: ExternalMapApp.googleMaps,
        ),
        isFalse,
      );
    });
  });
}
