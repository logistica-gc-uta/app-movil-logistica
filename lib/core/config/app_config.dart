import 'package:flutter/foundation.dart';

/// Configuración fijada al compilar con `--dart-define` o
/// `--dart-define-from-file=config/<entorno>.json`. No hay URLs del servidor
/// ni secretos escritos en el código: cada build recibe los suyos.
class AppConfig {
  static const String _rawApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );

  /// URL base de la API, sin barra final, para poder anteponerla a rutas
  /// como `/auth/login`.
  static String get apiBaseUrl => normalizeApiBaseUrl(_rawApiBaseUrl);

  /// Nombre del entorno de la build: `emulator`, `lan`, `staging`...
  /// Solo identifica la build; no cambia el comportamiento.
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'local',
  );

  /// Versión y commit corto con que se compiló (con sufijo `-dirty` si había
  /// cambios sin confirmar). Los pasa `tool/build_demo_apk.ps1`; en
  /// `flutter run` quedan vacíos.
  static const String appVersion = String.fromEnvironment('APP_VERSION');
  static const String gitCommit = String.fromEnvironment('GIT_COMMIT');

  /// Permite `http://` en una build release. Solo para la demo en red local
  /// sin TLS; el staging siempre va por HTTPS.
  static const bool allowInsecureHttp = bool.fromEnvironment(
    'ALLOW_INSECURE_HTTP',
  );

  /// Si es true, la bienvenida aparece en cada arranque aunque ya se haya
  /// visto. Sirve para revisar su diseño; la app final no la activa.
  static const bool alwaysShowWelcome = bool.fromEnvironment(
    'ALWAYS_SHOW_WELCOME',
  );

  /// Etiqueta visible de la build, por ejemplo `v1.0.0+2 · staging · 1a2b3c4`.
  /// Es null cuando la build no lleva commit (desarrollo con `flutter run`).
  static String? get buildLabel => describeBuild(
    version: appVersion,
    environment: environment,
    commit: gitCommit,
  );

  /// Motivo por el que esta build no debe conectarse, o null si puede.
  static String? get apiUrlProblem => checkApiBaseUrl(
    _rawApiBaseUrl,
    releaseBuild: kReleaseMode,
    allowInsecureHttp: allowInsecureHttp,
  );
}

String normalizeApiBaseUrl(String url) {
  var result = url.trim();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// Revisa la URL base antes de enviar credenciales. En release exige HTTPS
/// salvo que la build permita `http://` de forma explícita.
String? checkApiBaseUrl(
  String url, {
  required bool releaseBuild,
  required bool allowInsecureHttp,
}) {
  final uri = Uri.tryParse(normalizeApiBaseUrl(url));
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return 'La URL de la API no es válida. '
        'Debe tener la forma https://<servidor>/api/v1.';
  }
  if (uri.userInfo.isNotEmpty) {
    return 'La URL de la API no puede incluir usuario ni contraseña.';
  }
  if (releaseBuild && uri.isScheme('http') && !allowInsecureHttp) {
    return 'Esta versión solo se conecta por HTTPS, para proteger tu '
        'contraseña y tu sesión.';
  }
  return null;
}

String? describeBuild({
  required String version,
  required String environment,
  required String commit,
}) {
  if (commit.isEmpty) return null;
  return [
    if (version.isNotEmpty) 'v$version',
    if (environment.isNotEmpty) environment,
    commit,
  ].join(' · ');
}
