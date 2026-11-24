import 'dart:async';
import 'dart:convert';

import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/routes/data/routes_service.dart';
import 'package:app_movil_logistica/features/routes/presentation/my_route_page.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _driver = AuthUser(
  id: 'u1',
  name: 'Carlos Chofer',
  email: 'chofer@test.com',
  role: 'DRIVER',
);

/// Backend simulado con las reglas del servidor real para fallo, cierre y
/// regreso: idempotencia por `requestId`, 409 fuera de estado y 400 sin motivo.
class _Server {
  _Server({
    this.status = 'IN_PROGRESS',
    required List<(String, String, String)> stops,
  }) {
    for (final (orderId, orderStatus, outcome) in stops) {
      orders[orderId] = orderStatus;
      outcomes[orderId] = outcome;
    }
  }

  String status;
  Map<String, dynamic>? emergency;
  final orders = <String, String>{};
  final outcomes = <String, String>{};
  final attempts = <String, Map<String, dynamic>>{};
  String? completedAt;
  String? returnedAt;
  bool availableAfterReturn = true;
  bool returnedFlag = false;
  final requests = <http.Request>[];

  /// Permite simular pérdidas de red antes o después de persistir.
  Future<http.Response> Function(
    http.Request request,
    Future<http.Response> Function() real,
  )?
  intercept;

  int count(String method, String suffix) => requests
      .where((r) => r.method == method && r.url.path.endsWith(suffix))
      .length;

  http.Request lastPost(String suffix) => requests.lastWhere(
    (r) => r.method == 'POST' && r.url.path.endsWith(suffix),
  );

  Map<String, dynamic> get availability => {
    'isAvailable': returnedFlag && availableAfterReturn,
    'hasPersistedHolds': !returnedFlag,
    'compatibilityFlagBlocks': false,
    'blockingRouteIds': returnedFlag ? <String>[] : ['r1'],
  };

  String routesBody() {
    var order = 0;
    return jsonEncode([
      {
        'id': 'r1',
        'date': '2026-11-17T05:00:00Z',
        'status': status,
        'startedAt': '2026-11-17T13:00:00.000Z',
        'completedAt': completedAt,
        'returnedAt': returnedAt,
        'emergency': ?emergency,
        'orders': [
          for (final entry in orders.entries)
            {
              'id': entry.key,
              'deliveryAddress': 'Calle ${entry.key}',
              'status': entry.value,
              'scheduledDeliveryDate': null,
              'stopOrder': ++order,
            },
        ],
        'stops': [
          for (final orderId in orders.keys)
            {
              'id': 's-$orderId',
              'routeId': 'r1',
              'orderId': orderId,
              'outcome': outcomes[orderId],
              'isLegacy': false,
              'attempts': [?attempts[orderId]],
            },
        ],
        'events': <Map<String, dynamic>>[],
      },
    ]);
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    Future<http.Response> real() async => _apply(request);
    return intercept?.call(request, real) ?? real();
  }

  http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _apply(http.Request request) {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/drivers/me/routes')) {
      return http.Response(
        routesBody(),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/drivers/me/availability')) {
      return _json(availability);
    }
    if (request.method == 'POST' && path.contains('/stops/')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final orderId = path.split('/stops/s-').last.split('/').first;
      if (!['RECIPIENT_ABSENT', 'RECIPIENT_REFUSED'].contains(body['reason']) ||
          (body['context'] as String? ?? '').trim().isEmpty) {
        return http.Response('{}', 400);
      }
      final existing = attempts[orderId];
      if (existing != null && existing['requestId'] == body['requestId']) {
        return _json(existing);
      }
      if (status != 'IN_PROGRESS' || outcomes[orderId] != 'PENDING') {
        return http.Response('{}', 409);
      }
      outcomes[orderId] = 'FAILED';
      final attempt = {
        'id': 'a-$orderId',
        'stopId': 's-$orderId',
        'driverId': 'd1',
        'recordedAt': '2026-11-17T15:00:00.000Z',
        'outcome': 'FAILED',
        'failureReason': body['reason'],
        'context': body['context'],
        'requestId': body['requestId'],
      };
      attempts[orderId] = attempt;
      return _json(attempt);
    }
    if (request.method == 'POST' && path.endsWith('/complete')) {
      if (status == 'COMPLETED') {
        return _json({
          'id': 'r1',
          'status': status,
          'completedAt': completedAt,
        });
      }
      if (status != 'IN_PROGRESS' ||
          outcomes.values.any((outcome) => outcome == 'PENDING')) {
        return http.Response('{}', 409);
      }
      status = 'COMPLETED';
      completedAt = '2026-11-17T17:00:00.000Z';
      return _json({'id': 'r1', 'status': status, 'completedAt': completedAt});
    }
    if (request.method == 'POST' && path.endsWith('/return')) {
      if (status != 'COMPLETED' && status != 'INTERRUPTED') {
        return http.Response('{}', 409);
      }
      returnedFlag = true;
      returnedAt ??= '2026-11-17T18:30:00.000Z';
      return _json({
        'id': 'r1',
        'status': status,
        'returnedAt': returnedAt,
        'availability': availability,
      });
    }
    if (request.method == 'PATCH') {
      final orderId = path.split('/orders/').last.split('/').first;
      final next = (jsonDecode(request.body) as Map)['status'] as String;
      orders[orderId] = next;
      if (next == 'DELIVERED') outcomes[orderId] = 'SUCCESSFUL';
      return _json({'id': orderId, 'status': next});
    }
    return http.Response('{}', 404);
  }
}

void main() {
  Future<void> openPage(WidgetTester tester, _Server server) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MyRoutePage(
          user: _driver,
          routesService: RoutesService(
            ApiClient(httpClient: MockClient(server.handle)),
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterRoute(WidgetTester tester) =>
      tapVisible(tester, find.byKey(const ValueKey('open-route-r1')));

  /// Abre la hoja de la parada en turno y completa motivo y descripción.
  Future<void> fillFailure(
    WidgetTester tester, {
    String orderId = 'o1',
    String reason = 'RECIPIENT_ABSENT',
    String text = 'Nadie respondió',
  }) async {
    await tapVisible(tester, find.byKey(ValueKey('fail-stop-$orderId')));
    await tester.tap(find.byKey(ValueKey('failure-reason-$reason')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('failure-context')), text);
    await tester.pump();
  }

  FilledButton submitButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const ValueKey('submit-failure')));

  group('intento fallido', () {
    testWidgets(
      'exige motivo y descripción y no marca entregado ni cancelado',
      (tester) async {
        final server = _Server(
          stops: [
            ('o1', 'IN_TRANSIT', 'PENDING'),
            ('o2', 'ASSIGNED', 'PENDING'),
          ],
        );
        await openPage(tester, server);
        await enterRoute(tester);
        await tapVisible(tester, find.byKey(const ValueKey('fail-stop-o1')));
        expect(submitButton(tester).onPressed, isNull);
        await tester.tap(
          find.byKey(const ValueKey('failure-reason-RECIPIENT_ABSENT')),
        );
        await tester.pump();
        expect(submitButton(tester).onPressed, isNull, reason: 'Falta texto');
        await tester.enterText(
          find.byKey(const ValueKey('failure-context')),
          '   ',
        );
        await tester.pump();
        expect(submitButton(tester).onPressed, isNull, reason: 'Solo espacios');
        await tester.enterText(
          find.byKey(const ValueKey('failure-context')),
          '  Nadie respondió  ',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('submit-failure')));
        await tester.pumpAndSettle();

        final body =
            jsonDecode(server.lastPost('/failure').body)
                as Map<String, dynamic>;
        expect(body['reason'], 'RECIPIENT_ABSENT');
        expect(body['context'], 'Nadie respondió');
        expect(body['requestId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
        expect(server.count('PATCH', '/status'), 0);
        expect(find.text('Intento fallido registrado.'), findsOneWidget);
        expect(
          find.text('Intento fallido · Destinatario ausente'),
          findsOneWidget,
        );
        expect(find.text('Nadie respondió'), findsOneWidget);
        expect(
          find.text('0 de 2 entregados · 1 con intento fallido'),
          findsOneWidget,
        );
        expect(find.text('AHORA · PARADA 2'), findsOneWidget);
        // El pedido conserva su estado comercial: no se inventa CANCELLED.
        expect(server.orders['o1'], 'IN_TRANSIT');
      },
    );

    testWidgets('cancelar la hoja no envía nada', (tester) async {
      final server = _Server(stops: [('o1', 'ASSIGNED', 'PENDING')]);
      await openPage(tester, server);
      await enterRoute(tester);
      await fillFailure(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(server.count('POST', '/failure'), 0);
      expect(find.text('Intento fallido registrado.'), findsNothing);
    });

    testWidgets(
      'respuesta perdida tras persistir se recupera por GET sin reenviar',
      (tester) async {
        final server = _Server(stops: [('o1', 'ASSIGNED', 'PENDING')]);
        server.intercept = (request, real) async {
          if (request.url.path.endsWith('/failure')) {
            await real();
            throw TimeoutException('Respuesta perdida');
          }
          return real();
        };
        await openPage(tester, server);
        await enterRoute(tester);
        await fillFailure(tester);
        await tester.tap(find.byKey(const ValueKey('submit-failure')));
        await tester.pumpAndSettle();
        expect(server.count('POST', '/failure'), 1);
        expect(
          find.text('El servidor ya había registrado el intento fallido.'),
          findsOneWidget,
        );
        expect(
          find.text('Intento fallido · Destinatario ausente'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'si no se persistió, reenviar los mismos datos repite el requestId',
      (tester) async {
        final server = _Server(stops: [('o1', 'ASSIGNED', 'PENDING')]);
        var offline = true;
        server.intercept = (request, real) async {
          if (offline && request.url.path.endsWith('/failure')) {
            throw http.ClientException('Sin red');
          }
          return real();
        };
        await openPage(tester, server);
        await enterRoute(tester);
        await fillFailure(tester);
        await tester.tap(find.byKey(const ValueKey('submit-failure')));
        await tester.pumpAndSettle();
        expect(
          find.text('No se pudo conectar con el servidor.'),
          findsOneWidget,
        );
        expect(find.text('Intento fallido registrado.'), findsNothing);
        final first = jsonDecode(server.lastPost('/failure').body)['requestId'];

        // La hoja recuerda lo escrito; enviar igual es una repetición segura.
        offline = false;
        await tapVisible(tester, find.byKey(const ValueKey('fail-stop-o1')));
        expect(find.text('Nadie respondió'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('submit-failure')));
        await tester.pumpAndSettle();
        expect(
          jsonDecode(server.lastPost('/failure').body)['requestId'],
          first,
        );
        expect(find.text('Intento fallido registrado.'), findsOneWidget);
      },
    );

    testWidgets('cambiar los datos tras un fallo usa un requestId nuevo', (
      tester,
    ) async {
      final server = _Server(stops: [('o1', 'ASSIGNED', 'PENDING')]);
      var offline = true;
      server.intercept = (request, real) async {
        if (offline && request.url.path.endsWith('/failure')) {
          throw http.ClientException('Sin red');
        }
        return real();
      };
      await openPage(tester, server);
      await enterRoute(tester);
      await fillFailure(tester);
      await tester.tap(find.byKey(const ValueKey('submit-failure')));
      await tester.pumpAndSettle();
      final first = jsonDecode(server.lastPost('/failure').body)['requestId'];
      offline = false;
      await fillFailure(
        tester,
        reason: 'RECIPIENT_REFUSED',
        text: 'No aceptó el paquete',
      );
      await tester.tap(find.byKey(const ValueKey('submit-failure')));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(server.lastPost('/failure').body)['requestId'],
        isNot(first),
      );
      expect(find.text('Intento fallido · Rechazó el pedido'), findsOneWidget);
    });

    testWidgets('403 se muestra sin recuperar ni anunciar éxito', (
      tester,
    ) async {
      final server = _Server(stops: [('o1', 'ASSIGNED', 'PENDING')]);
      server.intercept = (request, real) async =>
          request.url.path.endsWith('/failure')
          ? http.Response('{}', 403)
          : real();
      await openPage(tester, server);
      await enterRoute(tester);
      final gets = server.count('GET', '/routes');
      await fillFailure(tester);
      await tester.tap(find.byKey(const ValueKey('submit-failure')));
      await tester.pumpAndSettle();
      expect(find.textContaining('no es tuya'), findsOneWidget);
      expect(server.count('GET', '/routes'), gets);
      expect(find.text('Intento fallido registrado.'), findsNothing);
      expect(find.byKey(const ValueKey('fail-stop-o1')), findsOneWidget);
    });

    testWidgets('sin visita verificada no ofrece registrar el fallo', (
      tester,
    ) async {
      final server = _Server(stops: [('o1', 'ASSIGNED', 'PENDING')]);
      final legacy = jsonDecode(server.routesBody()) as List;
      legacy.first['stops'] = [];
      server.intercept = (request, real) async =>
          request.url.path.endsWith('/drivers/me/routes')
          ? http.Response(jsonEncode(legacy), 200)
          : real();
      await openPage(tester, server);
      await enterRoute(tester);
      expect(find.text('En camino'), findsOneWidget);
      expect(find.byKey(const ValueKey('fail-stop-o1')), findsNothing);
    });

    testWidgets('el último fallo resuelve las visitas y pide cerrar la ruta', (
      tester,
    ) async {
      final server = _Server(
        stops: [
          ('o1', 'DELIVERED', 'SUCCESSFUL'),
          ('o2', 'ASSIGNED', 'PENDING'),
        ],
      );
      await openPage(tester, server);
      await enterRoute(tester);
      await fillFailure(tester, orderId: 'o2');
      await tester.tap(find.byKey(const ValueKey('submit-failure')));
      await tester.pumpAndSettle();
      expect(find.text('Paradas finalizadas'), findsOneWidget);
      await tester.tap(find.text('Ver paradas'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('complete-route-r1')), findsOneWidget);
      // Visitas resueltas no equivalen a ruta cerrada.
      expect(find.text('En curso'), findsOneWidget);
    });
  });

  group('cerrar ruta', () {
    _Server resolved() => _Server(
      stops: [('o1', 'DELIVERED', 'SUCCESSFUL'), ('o2', 'ASSIGNED', 'FAILED')],
    );

    testWidgets('pide confirmación y cerrarla no libera al chofer', (
      tester,
    ) async {
      final server = resolved();
      await openPage(tester, server);
      expect(find.text('Ver resumen'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('complete-route-r1')));
      expect(find.text('¿Cerrar la ruta?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(server.count('POST', '/complete'), 0);

      await tapVisible(tester, find.byKey(const ValueKey('complete-route-r1')));
      await tester.tap(find.byKey(const ValueKey('confirm-dialog')));
      await tester.pumpAndSettle();
      expect(server.count('POST', '/complete'), 1);
      expect(server.lastPost('/complete').body, '{}');
      expect(
        find.text('Ruta cerrada. Regresa al depósito y confirma tu llegada.'),
        findsOneWidget,
      );
      expect(find.text('Completada'), findsOneWidget);
      expect(find.textContaining('Sigues ocupado'), findsOneWidget);
      expect(find.byKey(const ValueKey('return-route-r1')), findsOneWidget);
      // Cerrar no consulta ni afirma disponibilidad.
      expect(server.count('GET', '/availability'), 0);
    });

    testWidgets('409 no cierra la ruta ni anuncia éxito', (tester) async {
      final server = resolved();
      server.intercept = (request, real) async =>
          request.url.path.endsWith('/complete')
          ? http.Response('{}', 409)
          : real();
      await openPage(tester, server);
      await tapVisible(tester, find.byKey(const ValueKey('complete-route-r1')));
      await tester.tap(find.byKey(const ValueKey('confirm-dialog')));
      await tester.pumpAndSettle();
      expect(find.textContaining('aún no permite cerrar'), findsOneWidget);
      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Completada'), findsNothing);
    });

    testWidgets('mientras se cierra bloquea las demás acciones', (
      tester,
    ) async {
      final server = resolved();
      final pending = Completer<void>();
      server.intercept = (request, real) async {
        if (request.url.path.endsWith('/complete')) await pending.future;
        return real();
      };
      await openPage(tester, server);
      await tapVisible(tester, find.byKey(const ValueKey('complete-route-r1')));
      await tester.tap(find.byKey(const ValueKey('confirm-dialog')));
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<RouteActionButton>(
              find.byKey(const ValueKey('complete-route-r1')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('open-route-r1')))
            .onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(server.count('POST', '/complete'), 1);
    });
  });

  group('regreso al depósito', () {
    _Server completed() => _Server(
      status: 'COMPLETED',
      stops: [('o1', 'DELIVERED', 'SUCCESSFUL'), ('o2', 'ASSIGNED', 'FAILED')],
    )..completedAt = '2026-11-17T17:00:00.000Z';

    Future<void> confirmReturn(WidgetTester tester) async {
      await tapVisible(tester, find.byKey(const ValueKey('return-route-r1')));
      expect(find.text('¿Ya estás en el depósito?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-dialog')));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra disponible solo con la respuesta del servidor', (
      tester,
    ) async {
      final server = completed();
      await openPage(tester, server);
      await confirmReturn(tester);
      expect(server.count('POST', '/return'), 1);
      expect(server.lastPost('/return').body, '{}');
      expect(find.text('Llegada al depósito confirmada.'), findsOneWidget);
      expect(
        find.text('Visitas finalizadas. Regreso al depósito confirmado.'),
        findsOneWidget,
      );
      await enterRoute(tester);
      expect(find.text('Ruta cerrada'), findsOneWidget);
      expect(find.text('Cerrada a las 12:00 (Ecuador)'), findsOneWidget);
      expect(find.text('Confirmado a las 13:30 (Ecuador)'), findsOneWidget);
      expect(
        find.text('El servidor te marca disponible para una nueva ruta.'),
        findsOneWidget,
      );
    });

    testWidgets('si el servidor no lo libera, no se muestra disponible', (
      tester,
    ) async {
      final server = completed()..availableAfterReturn = false;
      await openPage(tester, server);
      await confirmReturn(tester);
      await enterRoute(tester);
      expect(find.textContaining('aún no te habilita'), findsOneWidget);
      expect(find.textContaining('te marca disponible'), findsNothing);
    });

    testWidgets(
      'respuesta perdida: GET confirma el regreso y la disponibilidad se consulta',
      (tester) async {
        final server = completed();
        server.intercept = (request, real) async {
          if (request.url.path.endsWith('/return')) {
            await real();
            throw TimeoutException('Respuesta perdida');
          }
          return real();
        };
        await openPage(tester, server);
        await confirmReturn(tester);
        expect(server.count('POST', '/return'), 1);
        expect(find.text('Llegada al depósito confirmada.'), findsNothing);
        await enterRoute(tester);
        expect(find.text('Confirmado a las 13:30 (Ecuador)'), findsOneWidget);
        expect(
          find.text('Consulta al servidor si puedes recibir una nueva ruta.'),
          findsOneWidget,
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('check-availability')),
        );
        expect(server.count('GET', '/drivers/me/availability'), 1);
        expect(
          find.text('El servidor te marca disponible para una nueva ruta.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('COMPLETED sin regreso no ofrece consultar disponibilidad', (
      tester,
    ) async {
      final server = completed();
      await openPage(tester, server);
      await enterRoute(tester);
      expect(
        find.text('Pendiente: sigues ocupado hasta confirmarlo'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('check-availability')), findsNothing);
    });
  });

  testWidgets('ruta interrumpida: sin acciones de parada y con regreso', (
    tester,
  ) async {
    final server = _Server(
      status: 'INTERRUPTED',
      stops: [('o1', 'DELIVERED', 'SUCCESSFUL'), ('o2', 'ASSIGNED', 'PENDING')],
    )..emergency = {'id': 'e1', 'reason': 'Falla mecánica'};
    await openPage(tester, server);
    expect(find.text('Interrumpida'), findsOneWidget);
    expect(find.textContaining('interrumpió esta ruta'), findsOneWidget);
    await enterRoute(tester);
    expect(find.text('En camino'), findsNothing);
    expect(find.byKey(const ValueKey('fail-stop-o2')), findsNothing);
    expect(find.text('Ruta interrumpida'), findsOneWidget);
    expect(find.text('Por la administración: Falla mecánica'), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('return-route-r1')));
    await tester.tap(find.byKey(const ValueKey('confirm-dialog')));
    await tester.pumpAndSettle();
    expect(server.count('POST', '/return'), 1);
    expect(find.textContaining('la administración gestiona'), findsOneWidget);
  });

  testWidgets('la lista no menciona zonas: solo paradas', (tester) async {
    final server = _Server(stops: [('o1', 'ASSIGNED', 'PENDING')]);
    await openPage(tester, server);
    expect(find.text('1 parada'), findsOneWidget);
    expect(find.textContaining('zona', findRichText: true), findsNothing);
    expect(find.textContaining('Zona', findRichText: true), findsNothing);
  });
}
