import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../../../core/services/license_heartbeat_service.dart';
import '../../../../core/network/api_client.dart';

/// Clave usada en SharedPreferences para persistir el session_token.
/// Sobrevive a reinicios de app y crashes (Riesgo #3 del plan de seguridad).
const _kSessionTokenKey = 'pos_session_token';

class AuthProvider with ChangeNotifier {
  final AuthRepository repository;

  /// Referencia al ApiClient compartido para poder actualizar su
  /// sessionToken sin dependencias circulares.
  /// Se inyecta desde main.dart justo después de crear el provider.
  ApiClient? apiClient;

  Map<String, dynamic>? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  /// Token de sesión activo (UUID 64 chars).
  /// NULL = sin sesión activa.
  String? _sessionToken;

  AuthProvider({required this.repository});

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get sessionToken => _sessionToken;

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

  // ──────────────────────────────────────────────────────────────────────────
  // INIT: Restaurar token persistido (Crash Recovery)
  // Llamar desde main.dart ANTES de runApp para que el token esté disponible
  // en el primer request que haga la app al iniciarse.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> restoreSessionFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_kSessionTokenKey);
    if (savedToken != null) {
      _sessionToken = savedToken;
      _updateApiClientToken(savedToken);
      debugPrint('=== AUTH: Token restaurado desde SharedPreferences ===');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LOGIN COMPLETO
  // ──────────────────────────────────────────────────────────────────────────
  Future<bool> verifyPin(String pin) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await repository.verifyPin(pin);

      _currentUser = data['user'] as Map<String, dynamic>;
      final token = data['session_token'] as String;

      await _persistToken(token);

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

  // ──────────────────────────────────────────────────────────────────────────
  // LOGOUT MANUAL
  // Nullifica el token en BD (fire-and-forget) y limpia el estado local.
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    // 1. Notificar al backend (best-effort: si falla, igual limpiamos local)
    if (_sessionToken != null) {
      repository.logout(_sessionToken!).catchError((e) {
        debugPrint('=== LOGOUT remote call failed (non-critical): $e ===');
      });
    }

    // 2. Limpiar todo el estado local
    await _clearToken();
    LicenseHeartbeatService().stop();
    _currentUser = null;
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FORCED LOGOUT (sesión expirada remotamente)
  // Igual que logout pero sin llamar al backend (el token ya es inválido).
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> forceLogout() async {
    await _clearToken();
    LicenseHeartbeatService().stop();
    _currentUser = null;
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // RESTAURAR USUARIO (usado por AdminPinDialog para snapshot temporal)
  // No toca el session_token — solo cambia el _currentUser en memoria.
  // ──────────────────────────────────────────────────────────────────────────
  void restoreUser(Map<String, dynamic>? snapshot) {
    _currentUser = snapshot;
    _errorMessage = null;
    notifyListeners();
  }

  // ── Helpers privados ──────────────────────────────────────────────────────

  Future<void> _persistToken(String token) async {
    _sessionToken = token;
    _updateApiClientToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionTokenKey, token);
    debugPrint('=== AUTH: Token guardado en SharedPreferences ===');
  }

  Future<void> _clearToken() async {
    _sessionToken = null;
    _updateApiClientToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionTokenKey);
    debugPrint('=== AUTH: Token eliminado de SharedPreferences ===');
  }

  /// Actualiza el token en el ApiClient sin dependencia circular.
  /// ApiClient es una referencia simple (no un Provider), por lo que
  /// setearla aquí es seguro y no requiere context.
  void _updateApiClientToken(String? token) {
    apiClient?.sessionToken = token;
  }
}
