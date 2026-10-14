import 'dart:convert';

import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
import 'package:app_movil_logistica/features/auth/data/session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AuthService buildService(http.Response response) {
  return AuthService(
    apiClient: ApiClient(httpClient: MockClient((request) async => response)),
    storage: SessionStorage(),
  );
}

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
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('un DRIVER inicia sesión, se guarda y se activa el token', () async {
    final service = buildService(loginOk('DRIVER'));

    final session = await service.login('chofer@test.com', 'secreto');

    expect(session.user.isDriver, true);
    expect(service.apiClient.token, 'abc123');
    expect(await service.storage.read(), isNotNull);
  });

  test('un ADMIN es rechazado y no se guarda sesión', () async {
    final service = buildService(loginOk('ADMIN'));

    await expectLater(
      service.login('admin@test.com', 'secreto'),
      throwsA(isA<AuthException>()),
    );

    expect(service.apiClient.token, isNull);
    expect(await service.storage.read(), isNull);
  });

  test('una respuesta 401 lanza AuthException y no guarda sesión', () async {
    final service = buildService(http.Response('{"statusCode": 401}', 401));

    await expectLater(
      service.login('chofer@test.com', 'incorrecta'),
      throwsA(isA<AuthException>()),
    );

    expect(await service.storage.read(), isNull);
  });

  test('logout borra la sesión guardada y el token', () async {
    final service = buildService(loginOk('DRIVER'));
    await service.login('chofer@test.com', 'secreto');

    await service.logout();

    expect(service.apiClient.token, isNull);
    expect(await service.storage.read(), isNull);
  });

  test('restoreSession recupera la sesión al reabrir la app', () async {
    final firstRun = buildService(loginOk('DRIVER'));
    await firstRun.login('chofer@test.com', 'secreto');

    final secondRun = buildService(loginOk('DRIVER'));
    final session = await secondRun.restoreSession();

    expect(session?.user.email, 'chofer@test.com');
    expect(secondRun.apiClient.token, 'abc123');
  });
}
