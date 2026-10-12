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
}
