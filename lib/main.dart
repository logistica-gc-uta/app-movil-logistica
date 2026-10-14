import 'package:app_movil_logistica/app.dart';
import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
import 'package:app_movil_logistica/features/auth/data/session_storage.dart';
import 'package:flutter/material.dart';

void main() {
  final authService = AuthService(
    apiClient: ApiClient(),
    storage: SessionStorage(),
  );
  runApp(LogisticaApp(authService: authService));
}
