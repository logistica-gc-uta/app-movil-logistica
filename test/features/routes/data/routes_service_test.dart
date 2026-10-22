import 'dart:async';
import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/features/routes/data/routes_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'iniciar envía POST vacío y Bearer; repetición conserva la hora original',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"id":"r1","status":"IN_PROGRESS","startedAt":"2026-10-22T14:30:00Z"}',
            200,
          );
        }),
      )..token = 'fixture-token';
      final service = RoutesService(api);
      final first = await service.startRoute('r1');
      expect(await service.startRoute('r1'), first);
      expect(first, DateTime.utc(2026, 10, 22, 14, 30));
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(request.url.path, endsWith('/routes/r1/start'));
        expect(request.body, '{}');
        expect(request.headers['Authorization'], 'Bearer fixture-token');
        expect(request.headers['Content-Type'], 'application/json');
      }
    },
  );

  for (final code in [400, 401, 403, 404, 409, 500]) {
    test(
      'inicio rechazado con $code conserva el código y no da éxito',
      () async {
        var expired = false;
        final api =
            ApiClient(
                httpClient: MockClient((_) async => http.Response('{}', code)),
              )
              ..token = 'fixture-token'
              ..onUnauthorized = () {
                expired = true;
              };
        await expectLater(
          RoutesService(api).startRoute('r1'),
          throwsA(
            isA<RoutesException>().having(
              (e) => e.statusCode,
              'statusCode',
              code,
            ),
          ),
        );
        expect(expired, code == 401);
      },
    );
  }

  for (final body in [
    '{}',
    'null',
    '[]',
    '{"id":"other","status":"IN_PROGRESS","startedAt":"2026-10-22T14:30:00Z"}',
    '{"id":"r1","status":"ASSIGNED","startedAt":"2026-10-22T14:30:00Z"}',
    '{"id":"r1","status":"IN_PROGRESS","startedAt":"invalid"}',
    '{"id":"r1","status":"IN_PROGRESS","startedAt":"2026-10-22T14:30:00"}',
  ]) {
    test(
      'no confirma un inicio con respuesta incompleta o de otra ruta: $body',
      () async {
        final service = RoutesService(
          ApiClient(
            httpClient: MockClient((_) async => http.Response(body, 200)),
          ),
        );
        await expectLater(
          service.startRoute('r1'),
          throwsA(isA<RoutesException>()),
        );
      },
    );
  }

  test('timeout de inicio no reenvía POST', () async {
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
      service.startRoute('r1'),
      throwsA(isA<RoutesException>()),
    );
    expect(calls, 1);
  });
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
