class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );

  /// Si es true, la bienvenida aparece en cada arranque aunque ya se haya
  /// visto. Sirve para revisar su diseño; la app final no la activa.
  static const bool alwaysShowWelcome = bool.fromEnvironment(
    'ALWAYS_SHOW_WELCOME',
  );
}
