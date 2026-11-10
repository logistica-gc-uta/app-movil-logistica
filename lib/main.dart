import 'package:app_movil_logistica/app.dart';
import 'package:app_movil_logistica/core/config/app_config.dart';
import 'package:app_movil_logistica/core/config/config_error_app.dart';
import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
import 'package:app_movil_logistica/features/auth/data/session_storage.dart';
import 'package:flutter/material.dart';

void main() {
  final problem = AppConfig.apiUrlProblem;
  if (problem != null) {
    runApp(ConfigErrorApp(message: problem, buildLabel: AppConfig.buildLabel));
    return;
  }
  final authService = AuthService(
    apiClient: ApiClient(),
    storage: SessionStorage(),
  );
  runApp(
    LogisticaApp(authService: authService, buildLabel: AppConfig.buildLabel),
  );
}
