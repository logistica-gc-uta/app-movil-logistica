import 'package:app_movil_logistica/core/config/app_config.dart';
import 'package:app_movil_logistica/core/config/config_error_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkApiBaseUrl', () {
    String? check(String url, {bool release = true, bool allowHttp = false}) =>
        checkApiBaseUrl(
          url,
          releaseBuild: release,
          allowInsecureHttp: allowHttp,
        );

    test('acepta HTTPS en release', () {
      expect(check('https://api.ejemplo.test/api/v1'), isNull);
      expect(check('https://api.ejemplo.test/api/v1/'), isNull);
    });

    test('rechaza http:// en release sin permiso explícito', () {
      expect(check('http://192.168.1.20:3000/api/v1'), contains('HTTPS'));
    });

    test('permite http:// en release solo con ALLOW_INSECURE_HTTP', () {
      expect(check('http://192.168.1.20:3000/api/v1', allowHttp: true), isNull);
    });

    test('en debug acepta http:// para el desarrollo local', () {
      expect(check('http://10.0.2.2:3000/api/v1', release: false), isNull);
    });

    test('rechaza URLs sin esquema http(s), sin host o con consulta', () {
      for (final url in [
        '',
        'api.ejemplo.test/api/v1',
        'ftp://api.ejemplo.test/api/v1',
        'https:///api/v1',
        'https://api.ejemplo.test/api/v1?token=x',
        'https://api.ejemplo.test/api/v1#x',
      ]) {
        expect(check(url), contains('no es válida'), reason: url);
      }
    });

    test('rechaza credenciales dentro de la URL', () {
      expect(
        check('https://usuario:clave@api.ejemplo.test/api/v1'),
        contains('usuario ni contraseña'),
      );
    });
  });

  test('normalizeApiBaseUrl quita espacios y barras finales', () {
    expect(
      normalizeApiBaseUrl(' https://api.ejemplo.test/api/v1// '),
      'https://api.ejemplo.test/api/v1',
    );
  });

  group('describeBuild', () {
    test('sin commit no hay etiqueta (desarrollo)', () {
      expect(
        describeBuild(version: '1.0.0+1', environment: 'local', commit: ''),
        isNull,
      );
    });

    test('combina versión, entorno y commit', () {
      expect(
        describeBuild(
          version: '1.0.0+2',
          environment: 'staging',
          commit: '1a2b3c4-dirty',
        ),
        'v1.0.0+2 · staging · 1a2b3c4-dirty',
      );
    });
  });

  testWidgets('ConfigErrorApp explica el problema y no pide credenciales', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ConfigErrorApp(
        message: 'Esta versión solo se conecta por HTTPS.',
        buildLabel: 'v1.0.0+2 · lan · 1a2b3c4',
      ),
    );

    expect(
      find.text('Esta versión solo se conecta por HTTPS.'),
      findsOneWidget,
    );
    expect(find.text('v1.0.0+2 · lan · 1a2b3c4'), findsOneWidget);
    expect(find.text('Correo'), findsNothing);
    expect(find.text('Contraseña'), findsNothing);
  });
}
