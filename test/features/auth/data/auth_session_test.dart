import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final loginResponse = {
    'access_token': 'abc123',
    'user': {
      'id': 'u1',
      'name': 'Carlos Chofer',
      'email': 'chofer@test.com',
      'role': 'DRIVER',
    },
  };

  test('fromJson lee el token y el usuario de la respuesta del login', () {
    final session = AuthSession.fromJson(loginResponse);

    expect(session.token, 'abc123');
    expect(session.user.name, 'Carlos Chofer');
    expect(session.user.isDriver, true);
  });

  test('isDriver es falso para un rol que no es DRIVER', () {
    const admin = AuthUser(
      id: 'u2',
      name: 'Ana Admin',
      email: 'admin@test.com',
      role: 'ADMIN',
    );

    expect(admin.isDriver, false);
  });

  test('toJson conserva los datos al volver a leerlos', () {
    final session = AuthSession.fromJson(loginResponse);

    final copy = AuthSession.fromJson(session.toJson());

    expect(copy.token, 'abc123');
    expect(copy.user.email, 'chofer@test.com');
  });
}
