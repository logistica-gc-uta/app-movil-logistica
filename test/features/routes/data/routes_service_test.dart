import 'dart:async';
import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/features/routes/data/routes_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('todayInGuayaquil usa la hora de Ecuador (UTC-5)', () {
    // 03:00 UTC del 19 todavía es día 18 en Ecuador.
    expect(todayInGuayaquil(DateTime.utc(2026, 10, 19, 3)), '2026-10-18');
    expect(todayInGuayaquil(DateTime.utc(2026, 10, 19, 6)), '2026-10-19');
  });

  test('fetchMyRoutes pide las rutas del día indicado', () async {
    late Uri requested;
    final service = RoutesService(
      ApiClient(
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response('[]', 200);
        }),
      ),
    );

    final routes = await service.fetchMyRoutes('2026-10-18');

    expect(routes, isEmpty);
    expect(requested.path, endsWith('/drivers/me/routes'));
    expect(requested.queryParameters['date'], '2026-10-18');
  });

  test('markDelivered envía PATCH con el nuevo estado', () async {
    late http.Request sent;
    final service = RoutesService(
      ApiClient(
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      ),
    );

    await service.markDelivered('o1');

    expect(sent.method, 'PATCH');
    expect(sent.url.path, endsWith('/orders/o1/status'));
    expect(sent.body, '{"status":"DELIVERED"}');
  });

  test('un 403 se informa como acción no permitida, no como éxito', () async {
    final service = RoutesService(
      ApiClient(
        httpClient: MockClient((request) async => http.Response('{}', 403)),
      ),
    );

    await expectLater(
      service.markInTransit('o1'),
      throwsA(
        isA<RoutesException>().having(
          (error) => error.message,
          'message',
          contains('Verifica que la ruta esté iniciada'),
        ),
      ),
    );
  });

  test('la consulta y las mutaciones envían el Bearer de la sesión', () async {
    final requests = <http.Request>[];
    final api = ApiClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(request.method == 'GET' ? '[]' : '{}', 200);
      }),
    )..token = 'fixture-token';
    final service = RoutesService(api);
    await service.fetchMyRoutes('2026-10-21');
    await service.markInTransit('o1');
    expect(requests, hasLength(2));
    expect(
      requests.every(
        (r) => r.headers['Authorization'] == 'Bearer fixture-token',
      ),
      isTrue,
    );
    expect(requests.first.url.queryParameters.containsKey('driverId'), isFalse);
  });

  for (final status in [401, 409, 500]) {
    test('un $status rechaza la mutación', () async {
      final service = RoutesService(
        ApiClient(
          httpClient: MockClient((_) async => http.Response('{}', status)),
        ),
      );
      await expectLater(
        service.markDelivered('o1'),
        throwsA(isA<RoutesException>()),
      );
    });
  }

  test('un timeout no reintenta automáticamente la mutación', () async {
    var calls = 0;
    final service = RoutesService(
      ApiClient(
        httpClient: MockClient((_) async {
          calls++;
          throw TimeoutException('fixture');
        }),
      ),
    );
    await expectLater(
      service.markDelivered('o1'),
      throwsA(isA<RoutesException>()),
    );
    expect(calls, 1);
  });
}
