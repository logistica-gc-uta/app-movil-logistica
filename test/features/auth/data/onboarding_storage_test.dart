import 'package:app_movil_logistica/features/auth/data/onboarding_storage.dart';
import 'package:app_movil_logistica/features/auth/data/session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('al principio la bienvenida no se ha visto', () async {
    expect(await OnboardingStorage().hasSeenWelcome(), false);
  });

  test('markWelcomeSeen la recuerda', () async {
    await OnboardingStorage().markWelcomeSeen();

    expect(await OnboardingStorage().hasSeenWelcome(), true);
  });

  test('cerrar sesión no borra que ya se vio la bienvenida', () async {
    await OnboardingStorage().markWelcomeSeen();

    await SessionStorage().clear();

    expect(await OnboardingStorage().hasSeenWelcome(), true);
  });
}
