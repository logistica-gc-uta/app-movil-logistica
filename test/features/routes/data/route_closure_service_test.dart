import 'dart:async';
import 'dart:convert';

import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:app_movil_logistica/features/routes/data/routes_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _requestId = '3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e';

final _attempt = {
  'id': 'a1',
  'stopId': 's1',
  'driverId': 'd1',
  'recordedAt': '2026-11-17T15:00:00.000Z',
  'outcome': 'FAILED',
  'failureReason': 'RECIPIENT_ABSENT',
  'context': 'Nadie respondió',
  'requestId': _requestId,
};

final _availability = {
  'isAvailable': true,
  'hasPersistedHolds': false,
  'compatibilityFlagBlocks': false,
  'blockingRouteIds': <String>[],
};

void main() {
  late List<http.Request> requests;

  RoutesService service(
    FutureOr<http.Response> Function(http.Request request) server,
  ) {
    requests = [];
    return RoutesService(
      ApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          return server(request);
        }),
      )..token = 'fixture-token',
    );
  }

  Future<void> fail(RoutesService routes) => routes.recordFailedVisit(
    routeId: 'r1',
    stopId: 's1',
    reason: FailedVisitReason.recipientAbsent,
    context: 'Nadie respondió',
    requestId: _requestId,
  );

  group('intento fallido', () {
    test('envía motivo, descripción y requestId a la visita', () async {
      final routes = service((_) => http.Response(jsonEncode(_attempt), 200));
      await fail(routes);
      final sent = requests.single;
      expect(sent.method, 'POST');
      expect(sent.url.path, endsWith('/routes/r1/stops/s1/failure'));
      expect(sent.headers['Authorization'], 'Bearer fixture-token');
      expect(jsonDecode(sent.body), {
        'reason': 'RECIPIENT_ABSENT',
        'context': 'Nadie respondió',
        'requestId': _requestId,
      });
    });

    for (final change in [
      {'stopId': 'otra'},
      {'outcome': 'SUCCESSFUL'},
      {'failureReason': 'RECIPIENT_REFUSED'},
      {'requestId': 'otro'},
    ]) {
      test('no confirma una respuesta que no corresponde: $change', () async {
        final routes = service(
          (_) => http.Response(jsonEncode({..._attempt, ...change}), 200),
        );
        await expectLater(fail(routes), throwsA(isA<RoutesException>()));
      });
    }

    for (final (code, text) in [
      (400, 'Revisa el motivo'),
      (403, 'no es tuya'),
      (404, 'ya no está disponible'),
      (409, 'ya no está pendiente'),
    ]) {
      test('rechazo $code se explica y conserva el código', () async {
        final routes = service((_) => http.Response('{}', code));
        await expectLater(
          fail(routes),
          throwsA(
            isA<RoutesException>()
                .having((e) => e.statusCode, 'statusCode', code)
                .having((e) => e.message, 'message', contains(text)),
          ),
        );
      });
    }

    test('timeout no reenvía el intento', () async {
      final routes = service((_) => throw TimeoutException('fixture'));
      await expectLater(fail(routes), throwsA(isA<RoutesException>()));
      expect(requests, hasLength(1));
    });
  });

  group('cerrar ruta', () {
    test('envía {} y devuelve la hora confirmada', () async {
      final routes = service(
        (_) => http.Response(
          jsonEncode({
            'id': 'r1',
            'status': 'COMPLETED',
            'completedAt': '2026-11-17T17:00:00.000Z',
          }),
          200,
        ),
      );
      expect(await routes.completeRoute('r1'), DateTime.utc(2026, 11, 17, 17));
      expect(requests.single.url.path, endsWith('/routes/r1/complete'));
      expect(requests.single.body, '{}');
    });

    for (final body in [
      '{}',
      '{"id":"r1","status":"IN_PROGRESS","completedAt":"2026-11-17T17:00:00Z"}',
      '{"id":"otra","status":"COMPLETED","completedAt":"2026-11-17T17:00:00Z"}',
      '{"id":"r1","status":"COMPLETED","completedAt":"2026-11-17T17:00:00"}',
    ]) {
      test('no confirma un cierre inválido: $body', () async {
        final routes = service((_) => http.Response(body, 200));
        await expectLater(
          routes.completeRoute('r1'),
          throwsA(isA<RoutesException>()),
        );
      });
    }

    test('409 explica que faltan visitas por resolver', () async {
      final routes = service((_) => http.Response('{}', 409));
      await expectLater(
        routes.completeRoute('r1'),
        throwsA(
          isA<RoutesException>().having(
            (e) => e.message,
            'message',
            contains('visitas estén resueltas'),
          ),
        ),
      );
    });
  });

  group('regreso al depósito', () {
    for (final status in ['COMPLETED', 'INTERRUPTED']) {
      test('confirma el regreso de una ruta $status', () async {
        final routes = service(
          (_) => http.Response(
            jsonEncode({
              'id': 'r1',
              'status': status,
              'returnedAt': '2026-11-17T18:00:00.000Z',
              'availability': _availability,
            }),
            200,
          ),
        );
        final result = await routes.confirmReturn('r1');
        expect(result.routeStatus, status);
        expect(result.returnedAt, DateTime.utc(2026, 11, 17, 18));
        expect(result.availability.isAvailable, isTrue);
        expect(requests.single.url.path, endsWith('/routes/r1/return'));
        expect(requests.single.body, '{}');
      });
    }

    for (final change in <Map<String, Object?>>[
      {'status': 'IN_PROGRESS'},
      {'id': 'otra'},
      {'returnedAt': null},
      {'availability': null},
      {
        'availability': {'isAvailable': 'sí'},
      },
    ]) {
      test('no confirma un regreso inválido: $change', () async {
        final routes = service(
          (_) => http.Response(
            jsonEncode({
              'id': 'r1',
              'status': 'COMPLETED',
              'returnedAt': '2026-11-17T18:00:00.000Z',
              'availability': _availability,
              ...change,
            }),
            200,
          ),
        );
        await expectLater(
          routes.confirmReturn('r1'),
          throwsA(isA<RoutesException>()),
        );
      });
    }

    test('409 no se presenta como éxito', () async {
      final routes = service((_) => http.Response('{}', 409));
      await expectLater(
        routes.confirmReturn('r1'),
        throwsA(
          isA<RoutesException>().having(
            (e) => e.message,
            'message',
            contains('aún no habilita el regreso'),
          ),
        ),
      );
    });
  });

  test('consulta la disponibilidad del chofer autenticado', () async {
    final routes = service(
      (_) => http.Response(
        jsonEncode({
          ..._availability,
          'isAvailable': false,
          'hasPersistedHolds': true,
          'blockingRouteIds': ['r1'],
        }),
        200,
      ),
    );
    final availability = await routes.fetchMyAvailability();
    expect(availability.isAvailable, isFalse);
    expect(availability.blockingRouteIds, ['r1']);
    expect(requests.single.url.path, endsWith('/drivers/me/availability'));
    expect(requests.single.url.queryParameters, isEmpty);
  });
}
