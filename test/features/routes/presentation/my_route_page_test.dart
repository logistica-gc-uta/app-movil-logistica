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

String routesJson({
  required String routeStatus,
  required String orderStatus,
  String? startedAt,
  String? returnedAt,
}) {
  return jsonEncode([
    {
      'id': 'r1',
      'date': '2026-10-18T05:00:00Z',
      'zone': {'id': 'z1', 'name': 'Centro', 'code': 'CEN-01'},
      'status': routeStatus,
      'startedAt': startedAt,
      'returnedAt': returnedAt,
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

/// Entra a las paradas de una ruta ya iniciada desde su tarjeta.
Future<void> enterRoute(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-route-r1')));
  await tester.pumpAndSettle();
}

/// Las acciones de cada parada pueden quedar debajo del borde de la pantalla.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  late List<http.Request> requests;

  Future<void> openPage(
    WidgetTester tester,
    Future<http.Response> Function(http.Request request) server, {
    AuthUser user = driver,
  }) async {
    requests = [];
    // Pantalla de teléfono (411 × 914), no la superficie de 800 × 600.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final client = MockClient((request) {
      requests.add(request);
      return server(request);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MyRoutePage(
          user: user,
          routesService: RoutesService(ApiClient(httpClient: client)),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('3 éxitos y un fallo muestran 75 % y 4/4 visitas resueltas', (
    tester,
  ) async {
    final data =
        jsonDecode(
              routesJson(routeStatus: 'COMPLETED', orderStatus: 'DELIVERED'),
            )
            as List;
    data.first['orders'] = [
      for (var i = 1; i <= 4; i++)
        {
          'id': 'o$i',
          'deliveryAddress': 'DEMO $i',
          'stopOrder': i,
          'status': i == 4 ? 'ASSIGNED' : 'DELIVERED',
        },
    ];
    data.first['stops'] = [
      for (var i = 1; i <= 4; i++)
        {'orderId': 'o$i', 'outcome': i == 4 ? 'FAILED' : 'SUCCESSFUL'},
    ];
    await openPage(tester, (_) async => http.Response(jsonEncode(data), 200));
    expect(
      find.text('3 de 4 entregados · 1 con intento fallido'),
      findsOneWidget,
    );
    expect(find.text('75 % entregado · 4/4 visitas resueltas'), findsOneWidget);
    expect(find.textContaining('Sigues ocupado'), findsOneWidget);
    await enterRoute(tester);
    expect(find.text('75 % entregado · 4/4 visitas resueltas'), findsOneWidget);
    expect(find.text('Intento fallido'), findsOneWidget);
  });

  testWidgets('ruta vacía muestra 0 % sin dividir por cero', (tester) async {
    final data =
        jsonDecode(routesJson(routeStatus: 'ASSIGNED', orderStatus: 'ASSIGNED'))
            as List;
    data.first['orders'] = [];
    await openPage(tester, (_) async => http.Response(jsonEncode(data), 200));
    expect(find.text('0 % entregado · 0/0 visitas resueltas'), findsOneWidget);
  });

  for (final persisted in [false, true]) {
    testWidgets(
      'timeout de entrega recupera GET (persistida=$persisted), sin reenvío ni éxito falso',
      (tester) async {
        var changed = false;
        await openPage(tester, (request) async {
          if (request.method == 'PATCH') {
            changed = true;
            throw TimeoutException('Respuesta perdida');
          }
          return http.Response(
            routesJson(
              routeStatus: 'IN_PROGRESS',
              orderStatus: changed && persisted ? 'DELIVERED' : 'IN_TRANSIT',
            ),
            200,
          );
        });
        await enterRoute(tester);
        await tapVisible(tester, find.text('Entregado'));
        await tester.pumpAndSettle();
        expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
        expect(requests.where((r) => r.method == 'GET'), hasLength(2));
        expect(find.text('Pedido actualizado.'), findsNothing);
        // Un GET autorizado puede confirmar la entrega que perdió su respuesta.
        expect(
          find.text('Entregado con éxito'),
          persisted ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('${persisted ? 1 : 0} de 2 entregados'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'sin red conserva la ruta, bloquea reenvío y recupera con GET manual',
    (tester) async {
      var changed = false;
      var online = true;
      await openPage(tester, (request) async {
        if (request.method == 'PATCH') {
          changed = true;
          online = false;
        }
        if (!online) throw http.ClientException('Sin red');
        return http.Response(
          routesJson(
            routeStatus: 'IN_PROGRESS',
            orderStatus: changed ? 'DELIVERED' : 'IN_TRANSIT',
          ),
          200,
        );
      });
      await enterRoute(tester);
      await tapVisible(tester, find.text('Entregado'));
      await tester.pumpAndSettle();
      expect(find.text('Calle Primera 100'), findsOneWidget);
      expect(find.text('0 de 2 entregados'), findsOneWidget);
      // La causa y la instrucción comparten un único aviso de recuperación.
      expect(find.byIcon(Icons.info_rounded), findsOneWidget);
      expect(find.byTooltip('Reintentar'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Entregado'),
            )
            .onPressed,
        isNull,
      );
      online = true;
      await tapVisible(tester, find.byTooltip('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('1 de 2 entregados'), findsOneWidget);
      expect(find.byTooltip('Actualizar estado'), findsNothing);
      expect(find.byTooltip('Reintentar'), findsNothing);
      expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
    },
  );

  testWidgets('al regresar a primer plano recupera GET sin mutaciones', (
    tester,
  ) async {
    var status = 'ASSIGNED';
    await openPage(
      tester,
      (_) async => http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: status),
        200,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    status = 'DELIVERED';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('1 de 2 entregados'), findsOneWidget);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(requests, hasLength(2));
  });

  for (final code in [400, 409]) {
    testWidgets(
      'rechazo $code conserva ruta, consulta estado y no confirma éxito',
      (tester) async {
        await openPage(
          tester,
          (r) async => r.method == 'PATCH'
              ? http.Response('{}', code)
              : http.Response(
                  routesJson(
                    routeStatus: 'IN_PROGRESS',
                    orderStatus: 'IN_TRANSIT',
                  ),
                  200,
                ),
        );
        await enterRoute(tester);
        await tapVisible(tester, find.text('Entregado'));
        await tester.pumpAndSettle();
        expect(find.text('0 de 2 entregados'), findsOneWidget);
        expect(find.text('Pedido actualizado.'), findsNothing);
        expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
        expect(requests.where((r) => r.method == 'GET'), hasLength(2));
      },
    );
  }

  testWidgets('GET con formato inválido conserva lista y permite recuperar', (
    tester,
  ) async {
    var invalid = false;
    await openPage(
      tester,
      (_) async => http.Response(
        invalid
            ? '{}'
            : routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'ASSIGNED'),
        200,
      ),
    );
    invalid = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Centro'), findsOneWidget);
    expect(find.textContaining('rutas inválidas'), findsOneWidget);
    invalid = false;
    await tapVisible(tester, find.byTooltip('Actualizar estado'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Actualizar estado'), findsNothing);
  });

  testWidgets('GET anterior al PATCH no revierte el progreso confirmado', (
    tester,
  ) async {
    final stale = Completer<http.Response>();
    var gets = 0;
    var changed = false;
    await openPage(tester, (request) async {
      if (request.method == 'PATCH') {
        changed = true;
        return http.Response('{}', 200);
      }
      gets++;
      if (gets == 2) return stale.future;
      return http.Response(
        routesJson(
          routeStatus: 'IN_PROGRESS',
          orderStatus: changed ? 'DELIVERED' : 'IN_TRANSIT',
        ),
        200,
      );
    });
    await enterRoute(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Entregado'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 2 entregados'), findsOneWidget);
    stale.complete(
      http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'IN_TRANSIT'),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 de 2 entregados'), findsOneWidget);
    expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
  });

  testWidgets(
    'retomar durante PATCH pendiente no inicia GET ni repite acción',
    (tester) async {
      final pending = Completer<http.Response>();
      await openPage(
        tester,
        (request) async => request.method == 'PATCH'
            ? pending.future
            : http.Response(
                routesJson(
                  routeStatus: 'IN_PROGRESS',
                  orderStatus: 'IN_TRANSIT',
                ),
                200,
              ),
      );
      await enterRoute(tester);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Entregado'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(requests.where((r) => r.method == 'GET'), hasLength(1));
      expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
      pending.complete(http.Response('{}', 409));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method == 'GET'), hasLength(2));
    },
  );

  testWidgets('sin rutas muestra el aviso de día libre', (tester) async {
    await openPage(tester, (_) async => http.Response('[]', 200));

    expect(find.text('No tienes rutas para hoy'), findsOneWidget);
  });

  testWidgets(
    'un GET anterior al inicio no restaura ASSIGNED al responder tarde',
    (tester) async {
      var gets = 0;
      final oldResponse = Completer<http.Response>();
      await openPage(tester, (request) async {
        if (request.method == 'POST') {
          return http.Response(
            '{"id":"r1","status":"IN_PROGRESS","startedAt":"2026-10-22T14:30:00Z"}',
            200,
          );
        }
        gets++;
        if (gets == 2) return oldResponse.future;
        return http.Response(
          routesJson(
            routeStatus: gets == 1 ? 'ASSIGNED' : 'IN_PROGRESS',
            orderStatus: 'ASSIGNED',
          ),
          200,
        );
      });
      final refresh = tester
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
          .show();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(gets, 2);
      await tester.tap(find.text('Iniciar ruta'));
      await tester.pump(const Duration(seconds: 1));
      oldResponse.complete(
        http.Response(
          routesJson(routeStatus: 'ASSIGNED', orderStatus: 'ASSIGNED'),
          200,
        ),
      );
      await tester.pumpAndSettle();
      await refresh;
      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Iniciar ruta'), findsNothing);
    },
  );

  const startResponse =
      '{"id":"r1","status":"IN_PROGRESS","startedAt":"2026-10-22T14:30:00Z"}';

  testWidgets(
    'inicia tras confirmación, muestra hora de Ecuador y conserva orden',
    (tester) async {
      var status = 'ASSIGNED';
      await openPage(tester, (request) async {
        if (request.method == 'POST') {
          status = 'IN_PROGRESS';
          return http.Response(startResponse, 200);
        }
        return http.Response(
          routesJson(
            routeStatus: status,
            orderStatus: 'ASSIGNED',
            startedAt: status == 'IN_PROGRESS' ? '2026-10-22T14:30:00Z' : null,
          ),
          200,
        );
      });
      expect(find.text('En camino'), findsNothing);
      await tester.tap(find.text('Iniciar ruta'));
      await tester.pumpAndSettle();
      final post = requests.singleWhere((r) => r.method == 'POST');
      expect(post.url.path, endsWith('/routes/r1/start'));
      expect(post.body, '{}');
      expect(find.text('Ruta iniciada.'), findsOneWidget);
      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Inicio: 09:30 (Ecuador)'), findsOneWidget);
      expect(find.text('Iniciar ruta'), findsNothing);
      // Solo la parada 1 está en turno; la 2 espera.
      expect(find.text('En camino'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Calle Primera 100')).dy,
        lessThan(tester.getTopLeft(find.text('Av. Segunda 200')).dy),
      );
      expect(
        find.text('Ruta en curso. Atiende las paradas en orden, una a la vez.'),
        findsNothing,
      );
    },
  );

  testWidgets('doble toque durante latencia envía un solo inicio', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var status = 'ASSIGNED';
    await openPage(tester, (request) async {
      if (request.method == 'POST') return response.future;
      return http.Response(
        routesJson(routeStatus: status, orderStatus: 'ASSIGNED'),
        200,
      );
    });
    final start = find.byKey(const ValueKey('start-route-r1'));
    await tester.tap(start);
    await tester.tap(start);
    await tester.pump();
    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    expect(find.text('Iniciando…'), findsOneWidget);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    expect(find.text('Ruta iniciada.'), findsNothing);
    expect(find.text('En camino'), findsNothing);
    status = 'IN_PROGRESS';
    response.complete(http.Response(startResponse, 200));
    await tester.pumpAndSettle();
    expect(find.text('Ruta iniciada.'), findsOneWidget);
  });

  for (final code in [401, 403, 409, 500]) {
    testWidgets('inicio rechazado $code no simula éxito', (tester) async {
      await openPage(
        tester,
        (request) async => request.method == 'POST'
            ? http.Response('{}', code)
            : http.Response(
                routesJson(routeStatus: 'ASSIGNED', orderStatus: 'ASSIGNED'),
                200,
              ),
      );
      await tester.tap(find.text('Iniciar ruta'));
      await tester.pumpAndSettle();
      expect(find.text('Ruta iniciada.'), findsNothing);
      expect(find.text('En curso'), findsNothing);
      expect(find.text('En camino'), findsNothing);
      expect(find.text('Asignada'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      if (code == 403) {
        expect(
          find.text('No tienes permiso para iniciar esta ruta.'),
          findsOneWidget,
        );
      }
      if (code == 409) {
        expect(
          find.textContaining('La ruta no se puede iniciar'),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('timeout recupera IN_PROGRESS desde GET sin reenviar inicio', (
    tester,
  ) async {
    var status = 'ASSIGNED';
    await openPage(tester, (request) async {
      if (request.method == 'POST') {
        status = 'IN_PROGRESS';
        throw TimeoutException('response lost');
      }
      return http.Response(
        routesJson(routeStatus: status, orderStatus: 'ASSIGNED'),
        200,
      );
    });
    await tester.tap(find.text('Iniciar ruta'));
    await tester.pumpAndSettle();
    expect(find.text('En curso'), findsOneWidget);
    expect(find.text('Iniciar ruta'), findsNothing);
    expect(find.text('Ruta iniciada.'), findsNothing);
    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    expect(requests.where((r) => r.method == 'GET'), hasLength(2));
  });

  testWidgets('inicio incierto bloquea otro intento hasta recuperar un GET', (
    tester,
  ) async {
    var failed = false;
    await openPage(tester, (request) async {
      if (request.method == 'POST') {
        failed = true;
        throw TimeoutException('fixture');
      }
      return failed
          ? http.Response('{}', 500)
          : http.Response(
              routesJson(routeStatus: 'ASSIGNED', orderStatus: 'ASSIGNED'),
              200,
            );
    });
    await tester.tap(find.text('Iniciar ruta'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar ruta'), findsNothing);
    expect(find.text('Centro'), findsOneWidget);
    expect(
      find.text(
        'Actualiza la lista antes de volver a intentar iniciar una ruta.',
      ),
      findsOneWidget,
    );
    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    failed = false;
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar ruta'), findsOneWidget);
  });

  testWidgets('POST confirmado más GET fallido conserva inicio y hora', (
    tester,
  ) async {
    var started = false;
    await openPage(tester, (request) async {
      if (request.method == 'POST') {
        started = true;
        return http.Response(startResponse, 200);
      }
      return started
          ? http.Response('{}', 500)
          : http.Response(
              routesJson(routeStatus: 'ASSIGNED', orderStatus: 'ASSIGNED'),
              200,
            );
    });
    await tester.tap(find.text('Iniciar ruta'));
    await tester.pumpAndSettle();
    expect(find.text('En curso'), findsOneWidget);
    expect(find.text('Inicio: 09:30 (Ecuador)'), findsOneWidget);
    expect(find.text('Iniciar ruta'), findsNothing);
    expect(
      find.textContaining('El servidor confirmó el inicio.'),
      findsOneWidget,
    );
  });

  for (final status in ['DRAFT', 'UNVERIFIED', 'IN_PROGRESS', 'COMPLETED']) {
    testWidgets('$status no permite iniciar otra vez', (tester) async {
      await openPage(
        tester,
        (_) async => http.Response(
          routesJson(routeStatus: status, orderStatus: 'ASSIGNED'),
          200,
        ),
      );
      expect(find.text('Iniciar ruta'), findsNothing);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    });
  }

  for (final role in ['ADMIN', 'CLIENT']) {
    testWidgets('$role no ve Iniciar ruta aunque reciba una ASSIGNED', (
      tester,
    ) async {
      await openPage(
        tester,
        (_) async => http.Response(
          routesJson(routeStatus: 'ASSIGNED', orderStatus: 'ASSIGNED'),
          200,
        ),
        user: AuthUser(
          id: 'u2',
          name: 'Fixture',
          email: 'fixture@test.invalid',
          role: role,
        ),
      );
      expect(find.text('Iniciar ruta'), findsNothing);
    });
  }

  testWidgets(
    'COMPLETED sin retorno sigue ocupado y conserva visitas y orden',
    (tester) async {
      final data =
          jsonDecode(
                routesJson(routeStatus: 'COMPLETED', orderStatus: 'DELIVERED'),
              )
              as List;
      data.first['stops'] = [
        {'orderId': 'o1', 'outcome': 'SUCCESSFUL'},
        {'orderId': 'o2', 'outcome': 'FAILED'},
      ];
      await openPage(tester, (_) async => http.Response(jsonEncode(data), 200));
      await enterRoute(tester);
      expect(find.textContaining('Sigues ocupado'), findsOneWidget);
      expect(
        find.text('1 de 2 entregados · 1 con intento fallido'),
        findsOneWidget,
      );
      expect(find.text('Intento fallido'), findsOneWidget);
      expect(find.text('Iniciar ruta'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Calle Primera 100')).dy,
        lessThan(tester.getTopLeft(find.text('Av. Segunda 200')).dy),
      );
    },
  );

  testWidgets('retorno persistido evita afirmar que continúa retornando', (
    tester,
  ) async {
    await openPage(
      tester,
      (_) async => http.Response(
        routesJson(
          routeStatus: 'COMPLETED',
          orderStatus: 'DELIVERED',
          returnedAt: '2026-10-22T19:00:00Z',
        ),
        200,
      ),
    );
    expect(
      find.text('Visitas finalizadas. Regreso al depósito confirmado.'),
      findsOneWidget,
    );
    expect(find.textContaining('Sigues ocupado'), findsNothing);
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
    await tester.tap(find.byKey(const ValueKey('flip-route-r1')));
    await tester.pumpAndSettle();

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

    expect(find.text('Iniciar ruta'), findsOneWidget);
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
    await enterRoute(tester);

    await tapVisible(tester, find.text('En camino').first);
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
    await enterRoute(tester);

    await tapVisible(tester, find.text('En camino').first);
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
    await enterRoute(tester);
    await tapVisible(tester, find.text('Entregado'));
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
    await enterRoute(tester);
    await tapVisible(tester, find.text('En camino').first);
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
    await enterRoute(tester);
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
    await enterRoute(tester);
    await tapVisible(tester, find.text('En camino').first);
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

  testWidgets('solo la parada en turno ofrece acciones', (tester) async {
    await openPage(
      tester,
      (_) async => http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'ASSIGNED'),
        200,
      ),
    );
    await enterRoute(tester);
    final first = find.ancestor(
      of: find.text('Calle Primera 100'),
      matching: find.byType(Column),
    );
    final second = find.ancestor(
      of: find.text('Av. Segunda 200'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: first.first, matching: find.text('En camino')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second.first, matching: find.text('En camino')),
      findsNothing,
    );
  });

  testWidgets('un intento fallido da el turno a la parada siguiente', (
    tester,
  ) async {
    final data =
        jsonDecode(
              routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'ASSIGNED'),
            )
            as List;
    data.first['stops'] = [
      {'orderId': 'o1', 'outcome': 'FAILED'},
      {'orderId': 'o2', 'outcome': 'PENDING'},
    ];
    await openPage(tester, (_) async => http.Response(jsonEncode(data), 200));
    await enterRoute(tester);
    final second = find.ancestor(
      of: find.text('Av. Segunda 200'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: second.first, matching: find.text('En camino')),
      findsOneWidget,
    );
    expect(find.textContaining('Disponible al terminar'), findsNothing);
  });

  testWidgets('la tarjeta gira y muestra las paradas resumidas', (
    tester,
  ) async {
    await openPage(
      tester,
      (_) async => http.Response(
        routesJson(routeStatus: 'ASSIGNED', orderStatus: 'ASSIGNED'),
        200,
      ),
    );
    final flip = find.byKey(const ValueKey('flip-route-r1'));
    expect(find.text('Calle Primera 100'), findsNothing);
    await tester.tap(flip);
    await tester.pumpAndSettle();
    expect(find.text('Calle Primera 100'), findsOneWidget);
    expect(find.text('Av. Segunda 200'), findsOneWidget);
    expect(find.text('Iniciar ruta'), findsOneWidget);
    await tester.tap(flip);
    await tester.pumpAndSettle();
    expect(find.text('Calle Primera 100'), findsNothing);
    expect(find.text('0 de 2 entregados'), findsOneWidget);
  });

  testWidgets('Regresar vuelve a las rutas del día', (tester) async {
    await openPage(
      tester,
      (_) async => http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'ASSIGNED'),
        200,
      ),
    );
    expect(find.text('Calle Primera 100'), findsNothing);
    await enterRoute(tester);
    expect(find.text('Hola, Carlos Chofer'), findsNothing);
    expect(find.text('Calle Primera 100'), findsOneWidget);
    await tester.tap(find.text('Regresar'));
    await tester.pumpAndSettle();
    expect(find.text('Hola, Carlos Chofer'), findsOneWidget);
    expect(find.text('Continuar ruta'), findsOneWidget);
    expect(find.text('Calle Primera 100'), findsNothing);
  });

  testWidgets('el botón atrás del teléfono regresa sin salir de la app', (
    tester,
  ) async {
    await openPage(
      tester,
      (_) async => http.Response(
        routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'ASSIGNED'),
        200,
      ),
    );
    await enterRoute(tester);
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Hola, Carlos Chofer'), findsOneWidget);
    expect(find.byType(MyRoutePage), findsOneWidget);
  });

  /// Ruta en curso: o1 con [first] y o2 en camino hasta que se entrega.
  Future<void> openLastStop(
    WidgetTester tester, {
    required String firstOutcome,
  }) async {
    var delivered = false;
    await openPage(tester, (request) async {
      if (request.method == 'PATCH') {
        delivered = true;
        return http.Response('{}', 200);
      }
      final data =
          jsonDecode(
                routesJson(routeStatus: 'IN_PROGRESS', orderStatus: 'ASSIGNED'),
              )
              as List;
      final orders = data.first['orders'] as List;
      orders[0]['status'] = delivered ? 'DELIVERED' : 'IN_TRANSIT';
      orders[1]['status'] = firstOutcome == 'SUCCESSFUL'
          ? 'DELIVERED'
          : 'ASSIGNED';
      data.first['stops'] = [
        {'orderId': 'o1', 'outcome': firstOutcome},
        {'orderId': 'o2', 'outcome': delivered ? 'SUCCESSFUL' : 'PENDING'},
      ];
      return http.Response(jsonEncode(data), 200);
    });
    expect(find.text('Paradas completadas'), findsNothing);
    await enterRoute(tester);
    await tapVisible(tester, find.text('Entregado'));
  }

  testWidgets('al entregar, el camión llega antes de mostrar el resultado', (
    tester,
  ) async {
    await openLastStop(tester, firstOutcome: 'SUCCESSFUL');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Llegando al destino'), findsOneWidget);
    expect(find.text('Entregado con éxito'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Llegando al destino'), findsNothing);
    expect(find.text('Entregado con éxito'), findsNWidgets(2));
  });

  testWidgets('la última entrega confirma la ruta y la marca en su tarjeta', (
    tester,
  ) async {
    await openLastStop(tester, firstOutcome: 'SUCCESSFUL');
    await tester.pumpAndSettle();
    expect(find.text('Paradas completadas'), findsOneWidget);
    expect(find.text('Entregaste 2 de 2 paradas con éxito.'), findsOneWidget);
    await tester.tap(find.text('Volver a mis rutas'));
    await tester.pumpAndSettle();
    expect(find.text('Hola, Carlos Chofer'), findsOneWidget);
    expect(find.text('PARADAS COMPLETADAS'), findsOneWidget);
    expect(find.text('Ver resumen'), findsOneWidget);
    // El servidor aún no cerró la ruta: el estado no se inventa.
    expect(find.text('En curso'), findsOneWidget);
  });

  testWidgets('con un intento fallido no anuncia éxito total', (tester) async {
    await openLastStop(tester, firstOutcome: 'FAILED');
    await tester.pumpAndSettle();
    expect(find.text('Paradas completadas'), findsNothing);
    expect(find.text('Paradas finalizadas'), findsOneWidget);
    expect(
      find.text('1 entrega exitosa · 1 con intento fallido.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Ver paradas'));
    await tester.pumpAndSettle();
    expect(find.text('Intento fallido'), findsOneWidget);
    expect(find.text('Hola, Carlos Chofer'), findsNothing);
  });
}
