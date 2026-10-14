import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Recuerda en el teléfono la paleta de colores que eligió el repartidor.
class PaletteStorage {
  static const _key = 'palette';

  final _storage = const FlutterSecureStorage();

  /// Devuelve la paleta guardada, o Coral si no hay ninguna.
  Future<AppPalette> read() async {
    final name = await _storage.read(key: _key);
    return AppPalette.values.asNameMap()[name] ?? AppPalette.coral;
  }

  Future<void> save(AppPalette palette) async {
    await _storage.write(key: _key, value: palette.name);
  }
}
