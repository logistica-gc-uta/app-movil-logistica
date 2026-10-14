import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Recuerda si el repartidor ya vio la pantalla de bienvenida.
///
/// Usa el mismo almacenamiento del teléfono que la sesión, pero con otra
/// clave: cerrar sesión no la borra, así que la bienvenida sale una sola vez.
class OnboardingStorage {
  static const _key = 'welcome_seen';

  final _storage = const FlutterSecureStorage();

  Future<bool> hasSeenWelcome() async {
    return await _storage.read(key: _key) == 'true';
  }

  Future<void> markWelcomeSeen() async {
    await _storage.write(key: _key, value: 'true');
  }
}
