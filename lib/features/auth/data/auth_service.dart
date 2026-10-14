import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/core/network/api_exception.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/auth/data/session_storage.dart';

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}

class AuthService {
  AuthService({required this.apiClient, required this.storage});

  final ApiClient apiClient;
  final SessionStorage storage;

  Future<AuthSession> login(String email, String password) async {
    final session = await _requestSession(email, password);
    if (!session.user.isDriver) {
      throw const AuthException('Esta aplicación es solo para choferes.');
    }
    await storage.save(session);
    apiClient.token = session.token;
    return session;
  }

  Future<AuthSession?> restoreSession() async {
    final session = await storage.read();
    apiClient.token = session?.token;
    return session;
  }

  Future<void> logout() async {
    await storage.clear();
    apiClient.token = null;
  }

  Future<AuthSession> _requestSession(String email, String password) async {
    try {
      final data = await apiClient.post('/auth/login', {
        'email': email,
        'password': password,
      });
      return AuthSession.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        throw const AuthException('Correo o contraseña incorrectos.');
      }
      throw const AuthException('El servidor respondió con un error.');
    } on Exception {
      throw const AuthException('No se pudo conectar con el servidor.');
    }
  }
}
