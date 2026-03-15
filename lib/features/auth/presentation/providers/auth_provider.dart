import 'package:flutter/material.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthProvider with ChangeNotifier {
  final AuthRepository repository;

  Map<String, dynamic>? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider({required this.repository});

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?['role'] == 'admin';

  /// Verifica si el usuario actual tiene un permiso específico.
  /// Los Admins siempre tienen todos los permisos.
  bool hasPermission(String key) {
    if (isAdmin) return true;
    final perms = _currentUser?['permissions'];
    if (perms == null) return false;
    return (perms as List).contains(key);
  }

  Future<bool> verifyPin(String pin) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await repository.verifyPin(pin);
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  /// Restaura el usuario activo a un snapshot previo (usado por AdminPinDialog)
  void restoreUser(Map<String, dynamic>? snapshot) {
    _currentUser = snapshot;
    _errorMessage = null;
    notifyListeners();
  }
}
