import 'dart:convert';

import 'package:app_movil_logistica/app.dart';
import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/core/network/api_exception.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
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
    await tester.tap(find.text('Ingresar al turno'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await OnboardingStorage().markWelcomeSeen();
  });

  testWidgets('el selector cambia la paleta y se recuerda al reabrir', (
    tester,
  ) async {
    await openApp(tester);
    expect(find.text('Coral'), findsOneWidget);

    await tester.tap(find.text('Coral'));
    await tester.pumpAndSettle();
    expect(find.text('Naranja'), findsOneWidget);

    await openApp(tester);
    expect(find.text('Naranja'), findsOneWidget);
  });

  testWidgets('la primera vez muestra la bienvenida y después ya no', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});

    await openApp(tester);
    expect(find.text('Bienvenido'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);

    await openApp(tester);
    expect(find.text('Bienvenido'), findsNothing);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('sin sesión muestra el login y al entrar abre Mi Ruta del Día', (
    tester,
  ) async {
    await openApp(tester);
    expect(find.text('Iniciar sesión'), findsOneWidget);

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
    expect(find.text('Iniciar sesión'), findsNothing);
  });

  testWidgets('cerrar sesión vuelve al login y no se conserva', (tester) async {
    await openApp(tester);
    await login(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);

    await openApp(tester);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('si el token caduca (401) vuelve al login con un aviso', (
    tester,
  ) async {
    final authService = await openApp(tester);
    await login(tester);

    await expectLater(
      authService.apiClient.get('/drivers/me/routes'),
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
