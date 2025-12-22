import 'package:flutter/foundation.dart';

import '../models/auth_payload.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final _authService = AuthService();

  AuthPayload? _session;
  bool _loading = false;
  String? _error;

  User? get user => _session?.user;
  String? get token => _session?.token;
  bool get isAuthenticated => _session != null;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> login(String email, String password) async {
    _setLoading(true);
    try {
      _session = await _authService.login(email: email, password: password);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> registerOwner({
    required String username,
    required String email,
    required String password,
    required String pharmacyName,
    String? pharmacyAddress,
    String? pharmacyLocation,
  }) async {
    _setLoading(true);
    try {
      _session = await _authService.registerOwner(
        username: username,
        email: email,
        password: password,
        pharmacyName: pharmacyName,
        pharmacyAddress: pharmacyAddress,
        pharmacyLocation: pharmacyLocation,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createEmployee({
    required String username,
    required String email,
    required String password,
  }) async {
    if (token == null || user?.pharmacyId == null) {
      throw Exception('Missing pharmacy context');
    }
    await _authService.registerEmployee(
      token: token!,
      username: username,
      email: email,
      password: password,
      pharmacyId: user!.pharmacyId!,
    );
  }

  void logout() {
    _session = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
