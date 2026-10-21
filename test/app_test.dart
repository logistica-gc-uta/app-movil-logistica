import 'dart:convert';

import 'package:app_movil_logistica/app.dart';
import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/core/network/api_exception.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/auth/data/onboarding_storage.dart';
import 'package:app_movil_logistica/features/auth/data/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final loginResponse = http.Response(
  jsonEncode({
    'access_token': 'abc123',
    'user': {
      'id': 'u1',
      'name': 'Carlos Chofer',
      'email': 'chofer@test.com',
      'role': 'DRIVER',
    },
  }),
  200,
);

void main() {
  Future<AuthService> openApp(WidgetTester tester) async {
    final authService = AuthService(
      apiClient: ApiClient(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            return loginResponse;
          }
          if (request.url.path.endsWith('/drivers/me/routes')) {
            return http.Response('[]', 200);
          }
          return http.Response('{}', 401);
        }),
      ),
      storage: SessionStorage(),
    );
    await tester.pumpWidget(
      LogisticaApp(key: UniqueKey(), authService: authService),
    );
    await tester.pumpAndSettle();
    return authService;
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).first, 'a@test.com');
    await tester.enterText(find.byType(TextFormField).last, 'secreto');
    await tester.ensureVisible(find.text('Ingresar al turno'));
    await tester.tap(find.text('Ingresar al turno'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await OnboardingStorage().markWelcomeSeen();
  });

  testWidgets('el botón Invertir alterna y se recuerda al reabrir', (
    tester,
  ) async {
    await openApp(tester);
    expect(find.text('Invertir'), findsOneWidget);

    await tester.tap(find.text('Invertir'));
    await tester.pumpAndSettle();
    expect(find.text('Normal'), findsOneWidget);

    await openApp(tester);
    expect(find.text('Normal'), findsOneWidget);
  });

  testWidgets('con sesión guardada sin bienvenida vista, la muestra antes', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final session = AuthSession.fromJson(
      jsonDecode(loginResponse.body) as Map<String, dynamic>,
    );
    await tester.runAsync(() => SessionStorage().save(session));

    await openApp(tester);
    expect(find.text('Bienvenido'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Hola, Carlos Chofer'), findsOneWidget);
  });

  testWidgets('la primera vez muestra la bienvenida y después ya no', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});

    await openApp(tester);
    expect(find.text('Bienvenido'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);

    await openApp(tester);
    expect(find.text('Bienvenido'), findsNothing);
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);
  });

  testWidgets('sin sesión muestra el login y al entrar abre Mi Ruta del Día', (
    tester,
  ) async {
    await openApp(tester);
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);

    await login(tester);

    expect(find.text('Hola, Carlos Chofer'), findsOneWidget);
  });

  testWidgets('la sesión se conserva al cerrar y reabrir la app', (
    tester,
  ) async {
    await openApp(tester);
    await login(tester);

    await openApp(tester);

    expect(find.text('Hola, Carlos Chofer'), findsOneWidget);
    expect(find.text('INICIAR SESIÓN'), findsNothing);
  });

  testWidgets('cerrar sesión vuelve al login y no se conserva', (tester) async {
    await openApp(tester);
    await login(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);

    await openApp(tester);
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);
  });

  testWidgets('si el token caduca (401) vuelve al login con un aviso', (
    tester,
  ) async {
    final authService = await openApp(tester);
    await login(tester);

    await expectLater(
      authService.apiClient.get('/orders/123'),
      throwsA(isA<ApiException>()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Tu sesión caducó. Inicia sesión de nuevo.'),
      findsOneWidget,
    );
    expect(authService.apiClient.token, isNull);
  });
}
