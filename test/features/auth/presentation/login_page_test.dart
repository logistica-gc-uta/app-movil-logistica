import 'dart:convert';

import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/auth/data/session_storage.dart';
import 'package:app_movil_logistica/features/auth/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response loginOk(String role) {
  return http.Response(
    jsonEncode({
      'access_token': 'abc123',
      'user': {
        'id': 'u1',
        'name': 'Carlos Chofer',
        'email': 'chofer@test.com',
        'role': role,
      },
    }),
    200,
  );
}

void main() {
  AuthSession? loggedIn;
  var requests = 0;

  Future<void> openLogin(WidgetTester tester, http.Response response) async {
    final authService = AuthService(
      apiClient: ApiClient(
        httpClient: MockClient((request) async {
          requests++;
          return response;
        }),
      ),
      storage: SessionStorage(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          authService: authService,
          onLoggedIn: (session) => loggedIn = session,
        ),
      ),
    );
  }

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).first, 'a@test.com');
    await tester.enterText(find.byType(TextFormField).last, 'secreto');
    await tester.tap(find.text('Ingresar al turno'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    loggedIn = null;
    requests = 0;
  });

  testWidgets('con campos vacíos muestra errores y no llama al servidor', (
    tester,
  ) async {
    await openLogin(tester, loginOk('DRIVER'));

    await tester.tap(find.text('Ingresar al turno'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe tu correo.'), findsOneWidget);
    expect(find.text('Escribe tu contraseña.'), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('un DRIVER entra a la app', (tester) async {
    await openLogin(tester, loginOk('DRIVER'));

    await fillAndSubmit(tester);

    expect(loggedIn?.user.name, 'Carlos Chofer');
  });

  testWidgets('con credenciales incorrectas muestra el mensaje', (
    tester,
  ) async {
    await openLogin(tester, http.Response('{"statusCode": 401}', 401));

    await fillAndSubmit(tester);

    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    expect(loggedIn, isNull);
  });

  testWidgets('un ADMIN ve que la app es solo para choferes', (tester) async {
    await openLogin(tester, loginOk('ADMIN'));

    await fillAndSubmit(tester);

    expect(find.text('Esta aplicación es solo para choferes.'), findsOneWidget);
    expect(loggedIn, isNull);
  });
}
