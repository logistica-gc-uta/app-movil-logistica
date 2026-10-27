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

/// Uses the real transport; delays only the first start by 500 ms so the
/// disabled button and double tap can be exercised deterministically.
class _MeasuredClient extends http.BaseClient {
  final _delegate = http.Client();
  int starts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/start')) {
      starts++;
      if (starts == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android: inicio propio, idempotencia, paradas congeladas y retorno pendiente',
    (tester) async {
      const routeId = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c';
      const base = 'http://127.0.0.1:3003/api/v1';
      expect(
        AppConfig.apiBaseUrl,
        base,
        reason: 'Use only the isolated fixture on port 3003',
      );
      final transport = _MeasuredClient();
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

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 300; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('Expected UI did not appear');
      }

      Future<void> refresh() async {
        await tester.drag(find.byType(ListView), const Offset(0, 1500));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 400));
        await tester.pumpAndSettle();
      }

      for (final account in ['other', 'admin', 'client']) {
        final session = await login(account);
        final response = await http.post(
          Uri.parse('$base/routes/$routeId/start'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.token}',
          },
          body: '{}',
        );
        expect(response.statusCode, 403);
      }
      expect(
        (await http.post(
          Uri.parse('$base/routes/$routeId/start'),
          headers: {'Content-Type': 'application/json'},
          body: '{}',
        )).statusCode,
        401,
      );

      final owner = await login('owner');
      final api = ApiClient(httpClient: transport)..token = owner.token;
      final service = RoutesService(api);
      final before = (await service.fetchMyRoutes(todayInGuayaquil())).single;
      expect(before.status, 'ASSIGNED');
      expect(before.startedAt, isNull);
      final sequence = before.stops.map((s) => s.orderId).toList();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: MyRoutePage(
            user: owner.user,
            routesService: service,
            onLogout: () {},
          ),
        ),
      );
      final startButton = find.byKey(const ValueKey('start-route-$routeId'));
      await waitFor(startButton);
      expect(find.widgetWithText(FilledButton, 'En camino'), findsNothing);
      await tester.ensureVisible(startButton);
      await tester.tap(startButton);
      await tester.pump();
      expect(tester.widget<FilledButton>(startButton).onPressed, isNull);
      await tester.tap(startButton);
      await waitFor(find.text('En curso'));
      expect(transport.starts, 1);
      expect(find.text('Iniciar ruta'), findsNothing);
      expect(
        find.text('AHORA · PARADA 1'),
        findsOneWidget,
      );
      final started = (await service.fetchMyRoutes(todayInGuayaquil())).single;
      expect(started.startedAt, isNotNull);
      expect(started.stops.map((s) => s.orderId), sequence);
      expect(find.text(formatRouteStart(started.startedAt!)), findsOneWidget);
      expect(await service.startRoute(routeId), started.startedAt);
      expect(
        transport.starts,
        2,
      ); // One UI action plus one explicit replay check.
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('android-route-started');

      for (var i = 1; i <= 3; i++) {
        final tile = find
            .ancestor(
              of: find.text('Calle DEMO $i'),
              matching: find.byType(Column),
            )
            .first;
        final transit = find.descendant(
          of: tile,
          matching: find.widgetWithText(FilledButton, 'En camino'),
        );
        await tester.ensureVisible(transit);
        await tester.tap(transit);
        final delivered = find.descendant(
          of: tile,
          matching: find.widgetWithText(FilledButton, 'Entregado'),
        );
        await waitFor(delivered);
        await tester.ensureVisible(delivered);
        await tester.tap(delivered);
        await waitFor(find.text('$i de 4 entregados'));
      }

      // Fixture preparation only: failure reporting and completion/return UI
      // belong to issue #8. Verify their read-only representation here.
      await api.post(
        '/routes/$routeId/stops/172458d0-8e18-42ad-87ec-9d6611a76d24/failure',
        {
          'reason': 'RECIPIENT_ABSENT',
          'context': 'Visita ficticia de prueba de inicio',
          'requestId': '272458d0-8e18-42ad-87ec-9d6611a76d24',
        },
      );
      await api.post('/routes/$routeId/complete', {});
      await refresh();
      await waitFor(find.text('Completada'));
      expect(find.textContaining('Sigues ocupado'), findsOneWidget);
      expect(
        find.text('3 de 4 entregados · 1 con intento fallido'),
        findsOneWidget,
      );
      expect(find.text('Iniciar ruta'), findsNothing);
      final completed = (await service.fetchMyRoutes(
        todayInGuayaquil(),
      )).single;
      expect(completed.stops.map((s) => s.orderId), sequence);
      expect(completed.returnedAt, isNull);
      final availability =
          await api.get('/drivers/me/availability') as Map<String, dynamic>;
      expect(availability['isAvailable'], isFalse);
      expect(availability['hasPersistedHolds'], isTrue);
      final rejected = await http.post(
        Uri.parse('$base/routes/$routeId/start'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${owner.token}',
        },
        body: '{}',
      );
      expect(rejected.statusCode, 409);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('android-completed-return-pending');
    },
  );
}
