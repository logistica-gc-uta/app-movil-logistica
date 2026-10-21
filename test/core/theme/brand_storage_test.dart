import 'package:app_movil_logistica/core/theme/brand_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('invertir empieza apagado', () async {
    expect(await BrandStorage().readInverted(), false);
  });

  test('saveInverted guarda la opción y readInverted la recupera', () async {
    await BrandStorage().saveInverted(true);

    expect(await BrandStorage().readInverted(), true);
  });
}
