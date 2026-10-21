import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Recuerda en el teléfono si el repartidor invirtió los colores de la
/// bienvenida y del inicio de sesión.
class BrandStorage {
  static const _invertKey = 'invert_brand';

  final _storage = const FlutterSecureStorage();

  Future<bool> readInverted() async {
    return await _storage.read(key: _invertKey) == 'true';
  }

  Future<void> saveInverted(bool inverted) async {
    await _storage.write(key: _invertKey, value: inverted.toString());
  }
}
