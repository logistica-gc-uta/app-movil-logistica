import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/auth/data/session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = AuthSession(
    token: 'abc123',
    user: AuthUser(
      id: 'u1',
      name: 'Carlos Chofer',
      email: 'chofer@test.com',
      role: 'DRIVER',
    ),
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('read devuelve null cuando no hay sesión guardada', () async {
    final storage = SessionStorage();

    expect(await storage.read(), isNull);
  });

  test('save guarda la sesión y read la recupera', () async {
    final storage = SessionStorage();

    await storage.save(session);
    final restored = await storage.read();

    expect(restored?.token, 'abc123');
    expect(restored?.user.email, 'chofer@test.com');
  });

  test('clear borra la sesión guardada', () async {
    final storage = SessionStorage();
    await storage.save(session);

    await storage.clear();

    expect(await storage.read(), isNull);
  });
}
