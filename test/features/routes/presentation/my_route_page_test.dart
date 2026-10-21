import 'dart:async';
import 'dart:convert';

import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/routes/data/routes_service.dart';
import 'package:app_movil_logistica/features/routes/presentation/my_route_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const driver = AuthUser(
  id: 'u1',
  name: 'Carlos Chofer',
  email: 'chofer@test.com',
  role: 'DRIVER',
);

String routesJson({required String routeStatus, required String orderStatus}) {
  return jsonEncode([
    {
      'id': 'r1',
      'date': '2026-10-18T05:00:00Z',
      'zone': {'id': 'z1', 'name': 'Centro', 'code': 'CEN-01'},
      'status': routeStatus,
      'orders': [
        {
          'id': 'o2',
          'deliveryAddress': 'Av. Segunda 200',
          'status': 'ASSIGNED',
          'scheduledDeliveryDate': null,
          'stopOrder': 2,
        },
        {
          'id': 'o1',
          'deliveryAddress': 'Calle Primera 100',
          'status': orderStatus,
          'scheduledDeliveryDate': null,
          'stopOrder': 1,
        },
      ],
      'stops': <Map<String, dynamic>>[],
      'events': <Map<String, dynamic>>[],
    },
  ]);
}

void main() {
  late List<http.Request> requests;

  Future<void> openPage(
    WidgetTester tester,
    Future<http.Response> Function(http.Request request) server,
  ) async {
    requests = [];
    final client = MockClient((request) {
      requests.add(request);
      return server(request);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MyRoutePage(
          user: driver,
          routesService: RoutesService(ApiClient(httpClient: client)),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin rutas muestra el aviso de día libre', (tester) async {
    await openPage(tester, (_) async => http.Response('[]', 200));

    expect(find.text('No tienes rutas para hoy'), findsOneWidget);
  });

  testWidgets('si falla la carga muestra el error y permite reintentar', (
    tester,
  ) async {
    var calls = 0;
    await openPage(tester, (_) async {
      calls++;
      return calls == 1 ? http.Response('{}', 500) : http.Response('[]', 200);
    });
    expect(find.text('No se pudieron cargar tus rutas'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('No tienes rutas para hoy'), findsOneWidget);
  });

  testWidgets('muestra las paradas ordenadas por stopOrder', (tester) async {
    await openPage(
      tester,
      (_) async => http.Response(
        routesJson(routeStatus: 'ASSIGNED', orderStatus: 'ASSIGNED'),
        200,
      ),
    );

    final first = tester.getTopLeft(find.text('Calle Primera 100'));
    final second = tester.getTopLeft(find.text('Av. Segunda 200'));
    expect(first.dy, lessThan(second.dy));
  });

  testWidgets('con la ruta sin iniciar no ofrece acciones', (tester) async {
    await openPage(
      tester,
      (_) async => http.Response(
        routesJson(routeStatus: 'ASSIGNED', orderStatus: 'ASSIGNED'),
        200,
      ),
    );

    expect(
      find.text('Inicia la ruta para poder actualizar las entregas.'),
      findsOneWidget,
    );
    expect(find.text('En camino'), findsNothing);
  });

  testWidgets('En camino actualiza el pedido y refresca la lista', (
    tester,
  ) async {
    var orderStatus = 'ASSIGNED';
    await openPage(tester, (request) async {
      if (request.method == 'PATCH') {
        orderStatus = 'IN_TRANSIT';
        return http.Response('{}', 200);
      }
      return http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: orderStatus),
        200,
      );
    });

    await tester.tap(find.text('En camino').first);
    await tester.pumpAndSettle();

    final patch = requests.singleWhere((request) => request.method == 'PATCH');
    expect(patch.url.path, endsWith('/orders/o1/status'));
    expect(patch.body, '{"status":"IN_TRANSIT"}');
    expect(find.text('Pedido actualizado.'), findsOneWidget);
    expect(find.text('Entregado'), findsOneWidget);
  });

  testWidgets('si el servidor rechaza la acción no muestra éxito', (
    tester,
  ) async {
    await openPage(tester, (request) async {
      if (request.method == 'PATCH') {
        return http.Response('{}', 403);
      }
      return http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'ASSIGNED'),
        200,
      );
    });

    await tester.tap(find.text('En camino').first);
    await tester.pumpAndSettle();

    expect(find.text('Pedido actualizado.'), findsNothing);
    expect(
      find.textContaining('Verifica que la ruta esté iniciada'),
      findsOneWidget,
    );
  });

  testWidgets('Entregado confirma y refresca el progreso desde API', (
    tester,
  ) async {
    var status = 'IN_TRANSIT';
    await openPage(tester, (request) async {
      if (request.method == 'PATCH') {
        status = 'DELIVERED';
        return http.Response('{}', 200);
      }
      return http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: status),
        200,
      );
    });
    await tester.tap(find.text('Entregado'));
    await tester.pumpAndSettle();
    expect(
      requests.singleWhere((r) => r.method == 'PATCH').body,
      '{"status":"DELIVERED"}',
    );
    expect(find.text('1 de 2 entregados'), findsOneWidget);
    expect(find.text('Pedido actualizado.'), findsOneWidget);
  });

  testWidgets('si falla el GET tras guardar conserva la ruta y avisa', (
    tester,
  ) async {
    var saved = false;
    await openPage(tester, (request) async {
      if (request.method == 'PATCH') {
        saved = true;
        return http.Response('{}', 200);
      }
      if (saved) return http.Response('{}', 500);
      return http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'ASSIGNED'),
        200,
      );
    });
    await tester.tap(find.text('En camino').first);
    await tester.pumpAndSettle();
    expect(find.text('Calle Primera 100'), findsOneWidget);
    expect(find.text('Pedido actualizado.'), findsNothing);
    expect(
      find.textContaining('El servidor confirmó el cambio'),
      findsOneWidget,
    );
    expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
  });

  testWidgets('una visita fallida conserva su resultado y no suma progreso', (
    tester,
  ) async {
    final data =
        jsonDecode(
              routesJson(routeStatus: 'COMPLETED', orderStatus: 'DELIVERED'),
            )
            as List;
    data.first['stops'] = [
      {'orderId': 'o1', 'outcome': 'FAILED'},
    ];
    await openPage(tester, (_) async => http.Response(jsonEncode(data), 200));
    expect(
      find.text('0 de 2 entregados · 1 con intento fallido'),
      findsOneWidget,
    );
    expect(find.text('Intento fallido'), findsOneWidget);
    expect(find.text('Entregado'), findsNothing);
  });

  testWidgets('bloquea acciones mientras una mutación está en espera', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    await openPage(tester, (request) async {
      if (request.method == 'PATCH') return response.future;
      return http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'ASSIGNED'),
        200,
      );
    });
    await tester.tap(find.text('En camino').first);
    await tester.pump();
    expect(
      tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .every((b) => b.onPressed == null),
      isTrue,
    );
    expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
    response.complete(http.Response('{}', 409));
    await tester.pumpAndSettle();
    expect(find.text('Pedido actualizado.'), findsNothing);
    expect(
      find.text('El pedido cambió de estado. Actualiza la lista.'),
      findsOneWidget,
    );
  });
}
