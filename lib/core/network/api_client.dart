import 'dart:convert';

import 'package:app_movil_logistica/core/config/app_config.dart';
import 'package:app_movil_logistica/core/network/api_exception.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Duration timeout;

  String? token;
  void Function()? onUnauthorized;

  Future<dynamic> get(String path) async {
    final response = await _httpClient
        .get(_uri(path), headers: _headers())
        .timeout(timeout);
    return _decode(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await _httpClient
        .post(_uri(path), headers: _headers(), body: jsonEncode(body))
        .timeout(timeout);
    return _decode(response);
  }

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, String> _headers() {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    if (response.statusCode == 401 && token != null) {
      onUnauthorized?.call();
    }
    throw ApiException(response.statusCode, response.body);
  }
}
