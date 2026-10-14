import 'dart:convert';

import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStorage {
  static const _key = 'auth_session';

  final _storage = const FlutterSecureStorage();

  Future<void> save(AuthSession session) async {
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) {
      return null;
    }
    return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
