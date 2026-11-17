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

/// Respuestas y rechazos reales del backend. Solo se puede perder una
/// respuesta DESPUÉS de que el servidor la persistió.
class _Transport extends http.BaseClient {
  final _delegate = http.Client();
  String? loseResponseSuffix;
  final posts = <String, int>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') {
      final key = request.url.path.split('/').last;
      posts[key] = (posts[key] ?? 0) + 1;
    }
    final response = await _delegate.send(request);
    final lose = loseResponseSuffix;
    if (lose != null &&
        request.method == 'POST' &&
        request.url.path.endsWith(lose)) {
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
    'Android: intento fallido, cierre y regreso al depósito desde la interfaz',
    (tester) async {
      const routeId = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c';
      const foreignRouteId = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7d';
      const lastStopId = '172458d0-8e18-42ad-87ec-9d6611a76d24';
      const foreignStopId = '172458d0-8e18-42ad-87ec-9d6611a76d25';
      const base = 'http://127.0.0.1:3003/api/v1';
      expect(
        AppConfig.apiBaseUrl,
        base,
        reason: 'Solo fixture aislada en puerto 3003',
      );
      final transport = _Transport();
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

      Future<int> post(
        String path,
        String? token,
        Map<String, dynamic> body,
      ) async => (await http.post(
        Uri.parse('$base$path'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      )).statusCode;

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

      final owner = await login('owner');
      final api = ApiClient(httpClient: transport)..token = owner.token;
      final service = RoutesService(api);
      final failurePath = '/routes/$routeId/stops/$lastStopId/failure';
      final failure = {
        'reason': 'RECIPIENT_ABSENT',
        'context': 'Visita ficticia issue 8',
        'requestId': '372458d0-8e18-42ad-87ec-9d6611a76d24',
      };

      // Rechazos reales: sin sesión, ruta ajena, rol incorrecto y estado.
      expect(await post(failurePath, null, failure), 401);
      for (final account in ['other', 'admin', 'client']) {
        final session = await login(account);
        expect(await post(failurePath, session.token, failure), 403);
        expect(await post('/routes/$routeId/complete', session.token, {}), 403);
        expect(await post('/routes/$routeId/return', session.token, {}), 403);
      }
      expect(
        await post(
          '/routes/$foreignRouteId/stops/$foreignStopId/failure',
          owner.token,
          failure,
        ),
        403,
        reason: 'El id de otra ruta no autoriza al chofer',
      );
      expect(await post(failurePath, owner.token, failure), 409);
      expect(await post('/routes/$routeId/complete', owner.token, {}), 409);
      expect(await post('/routes/$routeId/return', owner.token, {}), 409);

      await service.startRoute(routeId);
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

      for (var i = 1; i <= 3; i++) {
        await tap(find.widgetWithText(FilledButton, 'En camino'));
        await waitFor(find.widgetWithText(FilledButton, 'Entregado'));
        await tap(find.widgetWithText(FilledButton, 'Entregado'));
        await waitFor(find.text('$i de 4 entregados'));
        await tester.pumpAndSettle();
      }
      // El aviso inferior dura 4 s y puede tapar la última parada.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Cuarta parada: no se pudo entregar. La respuesta se pierde después
      // del commit y la app la recupera por GET sin reenviar.
      expect(
        await post('/routes/$routeId/complete', owner.token, {}),
        409,
        reason: 'Con una visita pendiente no se puede cerrar',
      );
      await tap(find.text('No se pudo entregar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Destinatario ausente'));
      await tester.enterText(
        find.byKey(const ValueKey('failure-context')),
        'Nadie respondió en la visita ficticia',
      );
      // Se cierra el teclado para que el botón de envío quede a la vista.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('android-failed-visit-form');
      transport.loseResponseSuffix = '/failure';
      await tap(find.byKey(const ValueKey('submit-failure')));
      await waitFor(find.text('Paradas finalizadas'));
      expect(transport.posts['failure'], 1, reason: 'Sin reenvío automático');
      expect(
        find.text('El servidor ya había registrado el intento fallido.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ver paradas'));
      await tester.pumpAndSettle();
      expect(
        find.text('3 de 4 entregados · 1 con intento fallido'),
        findsOneWidget,
      );
      expect(
        find.text('75 % entregado · 4/4 visitas resueltas'),
        findsOneWidget,
      );
      expect(
        find.text('Intento fallido · Destinatario ausente'),
        findsOneWidget,
      );
      expect(find.text('En curso'), findsOneWidget);
      final failed = (await service.fetchMyRoutes(todayInGuayaquil())).single;
      expect(failed.stops.last.isFailed, isTrue);
      expect(failed.stops.last.status, 'ASSIGNED', reason: 'Sin CANCELLED');
      expect((await service.fetchMyAvailability()).isAvailable, isFalse);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('android-failed-visit');

      // Cerrar la ruta no libera al chofer.
      await tap(find.byKey(const ValueKey('complete-route-$routeId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-dialog')));
      await waitFor(find.text('Completada'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sigues ocupado'), findsOneWidget);
      expect(
        find.text('Pendiente: sigues ocupado hasta confirmarlo'),
        findsOneWidget,
      );
      expect((await service.fetchMyAvailability()).isAvailable, isFalse);
      expect(
        await post(failurePath, owner.token, {
          ...failure,
          'requestId': '472458d0-8e18-42ad-87ec-9d6611a76d24',
        }),
        409,
        reason: 'Una ruta cerrada no acepta visitas nuevas',
      );
      await binding.takeScreenshot('android-route-completed');

      // Regreso confirmado por la API: solo entonces se muestra disponible.
      await tap(find.byKey(const ValueKey('return-route-$routeId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-dialog')));
      await waitFor(find.text('Llegada al depósito confirmada.'));
      await tester.pumpAndSettle();
      expect(
        find.text('El servidor te marca disponible para una nueva ruta.'),
        findsOneWidget,
      );
      expect(transport.posts['return'], 1);
      final availability = await service.fetchMyAvailability();
      expect(availability.isAvailable, isTrue);
      expect(availability.hasPersistedHolds, isFalse);
      final replay = await service.confirmReturn(routeId);
      final returned = (await service.fetchMyRoutes(todayInGuayaquil())).single;
      expect(replay.returnedAt, returned.returnedAt, reason: 'Idempotente');
      await binding.takeScreenshot('android-return-available');
    },
  );
}
