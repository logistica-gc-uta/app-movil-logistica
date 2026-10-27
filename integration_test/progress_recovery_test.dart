import 'dart:async';
import 'dart:convert';

import 'package:app_movil_logistica/core/config/app_config.dart';
import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/routes/data/routes_service.dart';
import 'package:app_movil_logistica/features/routes/presentation/my_route_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

/// Los rechazos y las respuestas son reales. Solo se inyecta la pérdida de
/// transporte antes de enviar o después de recibir la respuesta persistida.
class _RecoveryClient extends http.BaseClient {
  final _delegate = http.Client();
  bool offline = false;
  bool disconnectNextPatch = false;
  String? loseResponseSuffix;
  int patches = 0;
  int returns = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PATCH') {
      patches++;
      if (disconnectNextPatch) {
        disconnectNextPatch = false;
        offline = true;
      }
    }
    if (request.method == 'POST' && request.url.path.endsWith('/return')) {
      returns++;
    }
    if (offline) throw http.ClientException('Conexión interrumpida de prueba');
    final response = await _delegate.send(request);
    if (loseResponseSuffix != null &&
        request.url.path.endsWith(loseResponseSuffix!) &&
        request.method != 'GET') {
      loseResponseSuffix = null;
      await response.stream.drain<void>();
      expect(response.statusCode, 200);
      throw TimeoutException('Respuesta persistida perdida de prueba');
    }
    return response;
  }

  @override
  void close() => _delegate.close();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android: progreso real, pérdida de red y contratos de fallo/retorno',
    (tester) async {
      const routeId = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c';
      const stopId = '172458d0-8e18-42ad-87ec-9d6611a76d24';
      const base = 'http://127.0.0.1:3003/api/v1';
      expect(
        AppConfig.apiBaseUrl,
        base,
        reason: 'Solo fixture aislada en puerto 3003',
      );
      final transport = _RecoveryClient();
      addTearDown(transport.close);

      Future<AuthSession> login(String account) async {
        final response = await http.post(
          Uri.parse('$base/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': '$account@fixture.invalid',
            'password': 'fixture-only-123',
          }),
        );
        expect(response.statusCode, 200);
        return AuthSession.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      Future<http.Response> post(
        String path,
        String? token,
        Map<String, dynamic> body,
      ) => http.post(
        Uri.parse('$base$path'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 300; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('No apareció la interfaz esperada: $finder');
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
      }

      Future<void> refresh() async {
        // La recarga usa el mismo GET que al recuperar el primer plano.
        await tester.drag(find.byType(ListView), const Offset(0, 2200));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 500));
        await tester.pumpAndSettle();
      }

      final owner = await login('owner');
      final api = ApiClient(httpClient: transport)..token = owner.token;
      final service = RoutesService(api);
      final failure = {
        'reason': 'RECIPIENT_ABSENT',
        'context': 'Visita ficticia issue 5',
        'requestId': '272458d0-8e18-42ad-87ec-9d6611a76d24',
      };
      final failurePath = '/routes/$routeId/stops/$stopId/failure';
      expect((await post(failurePath, null, failure)).statusCode, 401);
      for (final account in ['other', 'admin', 'client']) {
        final session = await login(account);
        expect(
          (await post(failurePath, session.token, failure)).statusCode,
          403,
        );
        expect(
          (await post('/routes/$routeId/return', session.token, {})).statusCode,
          403,
        );
      }
      expect((await post(failurePath, owner.token, failure)).statusCode, 409);
      expect(
        (await post('/routes/$routeId/return', owner.token, {})).statusCode,
        409,
      );
      await service.startRoute(routeId);
      expect(
        (await post(failurePath, owner.token, {
          'context': 'Sin motivo',
          'requestId': failure['requestId'],
        })).statusCode,
        400,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: MyRoutePage(
            user: owner.user,
            routesService: service,
            onLogout: () {},
          ),
        ),
      );
      await waitFor(find.text('Continuar ruta'));
      await tap(find.text('Continuar ruta'));
      await tester.pumpAndSettle();
      transport.disconnectNextPatch = true;
      await tap(find.widgetWithText(FilledButton, 'En camino'));
      await waitFor(find.byTooltip('Actualizar estado'));
      expect(transport.patches, 1);
      expect(find.text('0 de 4 entregados'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'En camino'),
            )
            .onPressed,
        isNull,
      );
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('android-network-recovery');
      transport.offline = false;
      await tap(find.byTooltip('Actualizar estado'));
      await waitFor(find.text('Calle DEMO 1'));
      await tester.pumpAndSettle();
      expect(transport.patches, 1, reason: 'GET no reenvía el PATCH fallido');

      for (var i = 1; i <= 3; i++) {
        await tap(find.widgetWithText(FilledButton, 'En camino'));
        await waitFor(find.widgetWithText(FilledButton, 'Entregado'));
        if (i == 1) transport.loseResponseSuffix = '/orders/order-1/status';
        await tap(find.widgetWithText(FilledButton, 'Entregado'));
        await waitFor(find.text('$i de 4 entregados'));
        if (i == 1) {
          expect(find.text('Pedido actualizado.'), findsNothing);
          expect(
            transport.patches,
            3,
            reason: 'Un envío fallido y dos mutaciones, sin repetición',
          );
        }
      }
      // #8 implementará los controles de fallo/cierre/retorno. Aquí se prueban
      // sus contratos reales por REST y su representación de lectura en Flutter.
      final attempt =
          await api.post(failurePath, failure) as Map<String, dynamic>;
      expect(attempt['outcome'], 'FAILED');
      expect(attempt['failureReason'], 'RECIPIENT_ABSENT');
      final replay =
          await api.post(failurePath, failure) as Map<String, dynamic>;
      expect(replay['id'], attempt['id']);
      expect(
        (await post(failurePath, owner.token, {
          ...failure,
          'reason': 'RECIPIENT_REFUSED',
        })).statusCode,
        409,
      );
      await api.post('/routes/$routeId/complete', {});
      await refresh();
      await waitFor(find.text('75 % entregado · 4/4 visitas resueltas'));
      expect(
        find.text('3 de 4 entregados · 1 con intento fallido'),
        findsOneWidget,
      );
      expect(find.textContaining('Sigues ocupado'), findsOneWidget);
      final completed = (await service.fetchMyRoutes(
        todayInGuayaquil(),
      )).single;
      expect(completed.status, 'COMPLETED');
      expect(completed.stops.last.status, 'ASSIGNED');
      expect(completed.stops.last.isFailed, isTrue);
      expect(completed.returnedAt, isNull);
      expect(
        (await api.get('/drivers/me/availability'))['isAvailable'],
        isFalse,
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('android-progress-75');

      // Se pierde la respuesta DESPUÉS del commit. La recuperación consulta GET
      // antes de cualquier repetición y no deduce disponibilidad de COMPLETED.
      transport.loseResponseSuffix = '/return';
      await expectLater(
        api.post('/routes/$routeId/return', {}),
        throwsA(isA<TimeoutException>()),
      );
      final recovered = (await service.fetchMyRoutes(
        todayInGuayaquil(),
      )).single;
      expect(recovered.returnedAt, isNotNull);
      final availability = await api.get('/drivers/me/availability');
      expect(availability['isAvailable'], isTrue);
      expect(availability['hasPersistedHolds'], isFalse);
      expect(transport.returns, 1);
      final returned =
          await api.post('/routes/$routeId/return', {}) as Map<String, dynamic>;
      expect(
        DateTime.parse(returned['returnedAt'] as String),
        recovered.returnedAt,
      );
      expect(
        transport.returns,
        2,
        reason: 'Solo repetición explícita de idempotencia',
      );
      await refresh();
      await waitFor(
        find.text('Visitas finalizadas. Regreso al depósito confirmado.'),
      );
      expect(find.textContaining('Sigues ocupado'), findsNothing);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('android-return-confirmed');
    },
  );
}
