import 'dart:convert';

import 'package:app_movil_logistica/core/config/app_config.dart';
import 'package:app_movil_logistica/core/network/api_exception.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<dynamic> get(String path) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final response = await _httpClient.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    throw ApiException(response.statusCode, response.body);
  }
}
