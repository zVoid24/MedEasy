import 'dart:convert';

import '../core/http_client.dart';
import '../models/auth_payload.dart';

class AuthService {
  Future<AuthPayload> login({
    required String email,
    required String password,
  }) async {
    final client = ApiClient();
    final response = await client.post('/auth/login', {
      'email': email,
      'password': password,
    });
    if (response.statusCode != 200) {
      throw ApiError(_messageFromResponse(response.body));
    }
    return AuthPayload.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AuthPayload> registerOwner({
    required String username,
    required String email,
    required String password,
    required String pharmacyName,
    String? pharmacyAddress,
    String? pharmacyLocation,
  }) async {
    final client = ApiClient();
    final response = await client.post('/auth/register', {
      'username': username,
      'email': email,
      'password': password,
      'role': 'owner',
      'pharmacy_name': pharmacyName,
      'pharmacy_address': pharmacyAddress,
      'pharmacy_location': pharmacyLocation,
    });
    if (response.statusCode != 201) {
      throw ApiError(_messageFromResponse(response.body));
    }
    return AuthPayload.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    final client = ApiClient(token: token);
    final response = await client.post('/auth/reset-password', {'new_password': newPassword});
    if (response.statusCode != 200) {
      throw ApiError(_messageFromResponse(response.body));
    }
  }

  Future<void> registerEmployee({
    required String token,
    required String username,
    required String email,
    required String password,
    required int pharmacyId,
  }) async {
    final client = ApiClient(token: token);
    final response = await client.post('/auth/register', {
      'username': username,
      'email': email,
      'password': password,
      'role': 'employee',
      'pharmacy_id': pharmacyId,
    });
    if (response.statusCode != 201) {
      throw ApiError(_messageFromResponse(response.body));
    }
  }

  String _messageFromResponse(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['error'] as String? ?? 'Unexpected error';
    } catch (_) {
      return 'Unexpected error';
    }
  }
}
