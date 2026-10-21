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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android: aislamiento DRIVER y tres entregas más visita fallida',
    (tester) async {
      const routeId = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c';
      final base = AppConfig.apiBaseUrl;
      if (base != 'http://127.0.0.1:3003/api/v1') {
        fail('Run only against the isolated fixture on localhost:3003');
      }
      Future<Map<String, dynamic>> login(String account) async {
        final response = await http.post(
          Uri.parse('$base/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': '$account@fixture.invalid',
            'password': 'fixture-only-123',
          }),
        );
        expect(response.statusCode, 200);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      final owner = await login('owner');
      final api = ApiClient()..token = owner['access_token'] as String;
      final service = RoutesService(api);
      final date = todayInGuayaquil();
      final mine = await service.fetchMyRoutes(date);
      expect(mine.single.id, routeId);
      expect(mine.single.stops.map((s) => s.orderId), [
        'order-1',
        'order-2',
        'order-3',
        'order-4',
      ]);
      final other = await login('other');
      final otherApi = ApiClient()..token = other['access_token'] as String;
      final theirs = await RoutesService(otherApi).fetchMyRoutes(date);
      expect(theirs.single.id, isNot(routeId));
      for (final role in ['admin', 'client']) {
        final session = await login(role);
        final response = await http.get(
          Uri.parse('$base/drivers/me/routes?date=$date'),
          headers: {'Authorization': 'Bearer ${session['access_token']}'},
        );
        expect(response.statusCode, 403);
      }
      expect(
        (await http.get(
          Uri.parse('$base/drivers/me/routes?date=$date'),
        )).statusCode,
        401,
      );
      final forbidden = await http.patch(
        Uri.parse('$base/orders/order-1/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${otherApi.token}',
        },
        body: jsonEncode({'status': 'IN_TRANSIT'}),
      );
      expect(forbidden.statusCode, 403);
      // Fixture preparation only: the product start button belongs to issue #4.
      await api.post('/routes/$routeId/start', {});
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: MyRoutePage(
            user: AuthUser.fromJson(owner['user'] as Map<String, dynamic>),
            routesService: service,
            onLogout: () {},
          ),
        ),
      );
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('Expected UI did not appear');
      }

      await waitFor(find.text('Calle DEMO 1'));
      for (var i = 1; i <= 3; i++) {
        final tile = find
            .ancestor(
              of: find.text('Calle DEMO $i'),
              matching: find.byType(Column),
            )
            .first;
        final inTransit = find.descendant(
          of: tile,
          matching: find.widgetWithText(FilledButton, 'En camino'),
        );
        await tester.ensureVisible(inTransit);
        await tester.tap(inTransit);
        final delivered = find.descendant(
          of: tile,
          matching: find.widgetWithText(FilledButton, 'Entregado'),
        );
        await waitFor(delivered);
        await tester.ensureVisible(delivered);
        await tester.tap(delivered);
        await waitFor(find.text('$i de 4 entregados'));
      }
      await api.post(
        '/routes/$routeId/stops/172458d0-8e18-42ad-87ec-9d6611a76d24/failure',
        {
          'reason': 'RECIPIENT_ABSENT',
          'context': 'Visita ficticia de prueba Android',
          'requestId': '272458d0-8e18-42ad-87ec-9d6611a76d24',
        },
      );
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await waitFor(find.text('3 de 4 entregados · 1 con intento fallido'));
      final finalRoute = (await service.fetchMyRoutes(date)).single;
      expect(finalRoute.deliveredCount, 3);
      expect(finalRoute.failedCount, 1);
      expect(finalRoute.stops.last.status, isNot('DELIVERED'));
      expect(finalRoute.stops.last.status, isNot('CANCELLED'));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('android-daily-route');
    },
  );
}
