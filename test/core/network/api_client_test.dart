import 'dart:async';

import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('get devuelve los datos cuando el servidor responde 200', () async {
    final fakeServer = MockClient((request) async {
      return http.Response('{"status": "ok"}', 200);
    });
    final apiClient = ApiClient(httpClient: fakeServer);

    final data = await apiClient.get('/health');

    expect(data, {'status': 'ok'});
  });

  test('get lanza ApiException cuando el servidor responde 401', () async {
    final fakeServer = MockClient((request) async {
      return http.Response('No autorizado', 401);
    });
    final apiClient = ApiClient(httpClient: fakeServer);

    expect(apiClient.get('/drivers/me/routes'), throwsA(isA<ApiException>()));
  });

  test('post envía el cuerpo como JSON', () async {
    final fakeServer = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.body, '{"email":"chofer@test.com"}');
      return http.Response('{"ok": true}', 200);
    });
    final apiClient = ApiClient(httpClient: fakeServer);

    final data = await apiClient.post('/auth/login', {
      'email': 'chofer@test.com',
    });

    expect(data, {'ok': true});
  });

  test('envía el token como Bearer cuando existe', () async {
    final fakeServer = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer abc123');
      return http.Response('{}', 200);
    });
    final apiClient = ApiClient(httpClient: fakeServer);
    apiClient.token = 'abc123';

    await apiClient.get('/drivers/me/routes');
  });

  test('avisa cuando una petición con token recibe 401', () async {
    final fakeServer = MockClient((request) async {
      return http.Response('{}', 401);
    });
    final apiClient = ApiClient(httpClient: fakeServer);
    var notified = false;
    apiClient.token = 'caducado';
    apiClient.onUnauthorized = () => notified = true;

    await expectLater(
      apiClient.get('/drivers/me/routes'),
      throwsA(isA<ApiException>()),
    );

    expect(notified, true);
  });

  test('no avisa de un 401 cuando no hay token', () async {
    final fakeServer = MockClient((request) async {
      return http.Response('{}', 401);
    });
    final apiClient = ApiClient(httpClient: fakeServer);
    var notified = false;
    apiClient.onUnauthorized = () => notified = true;

    await expectLater(
      apiClient.post('/auth/login', {'email': 'a@test.com'}),
      throwsA(isA<ApiException>()),
    );

    expect(notified, false);
  });

  test('lanza TimeoutException si el servidor no responde a tiempo', () async {
    final fakeServer = MockClient((request) {
      return Completer<http.Response>().future;
    });
    final apiClient = ApiClient(
      httpClient: fakeServer,
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      apiClient.get('/drivers/me/routes'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
