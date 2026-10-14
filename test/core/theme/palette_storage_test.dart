import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/core/theme/palette_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('sin nada guardado devuelve Coral', () async {
    expect(await PaletteStorage().read(), AppPalette.coral);
  });

  test('save guarda la paleta y read la recupera', () async {
    await PaletteStorage().save(AppPalette.negro);

    expect(await PaletteStorage().read(), AppPalette.negro);
  });

  test('un valor desconocido vuelve a Coral', () async {
    FlutterSecureStorage.setMockInitialValues({'palette': 'morado'});

    expect(await PaletteStorage().read(), AppPalette.coral);
  });
}
