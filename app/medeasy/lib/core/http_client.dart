import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiClient {
  ApiClient({String? token}) : _token = token;

  final String? _token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<http.Response> get(String path, {Map<String, String>? params}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path')
        .replace(queryParameters: params);
    return http.get(uri, headers: _headers);
  }

  Future<http.Response> post(String path, dynamic body) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    return http.post(uri, headers: _headers, body: jsonEncode(body));
  }

  Future<http.Response> put(String path, dynamic body) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    return http.put(uri, headers: _headers, body: jsonEncode(body));
  }
}

class ApiError implements Exception {
  ApiError(this.message);
  final String message;

  @override
  String toString() => message;
}
