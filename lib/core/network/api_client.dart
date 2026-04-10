import 'dart:io';
import 'package:http/http.dart' as http;

/// Excepción para errores de red genéricos (servidor caído, sin conexión).
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  @override
  String toString() => message;
}

/// Excepción tipada para Sesión Única Activa.
/// Se lanza cuando el servidor responde 401 con error_code SESSION_EXPIRED,
/// lo que significa que otro dispositivo hizo login con el mismo usuario.
/// Los providers y screens capturan esta excepción para mostrar el dialog
/// de seguridad y forzar la navegación a /login.
class SessionExpiredException implements Exception {
  final String message;
  const SessionExpiredException(
      [this.message =
          'Tu sesión fue cerrada porque otro dispositivo inició sesión con tu usuario.']);
  @override
  String toString() => message;
}

/// Cliente HTTP centralizado que:
///   1. Inyecta el header X-Session-Token en TODOS los requests (Single Active Session).
///   2. Intercepta 401 SESSION_EXPIRED → lanza SessionExpiredException tipada.
///   3. Intercepta 5xx y errores de red → lanza NetworkException amigable.
///
/// Al ser un http.BaseClient, cubre automáticamente todos los datasources
/// sin necesidad de modificar cada uno individualmente.
class ApiClient extends http.BaseClient {
  final http.Client _inner;

  /// Token de sesión activo. Se setea desde AuthProvider al hacer login
  /// y se limpia al hacer logout. El setter es thread-safe para Dart.
  String? sessionToken;

  static const String _friendlyErrorMessage =
      'No se pudo conectar con el servidor principal. Verifique su conexión a red o si el servidor está encendido.';

  ApiClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      // ── Inyección del token de sesión ────────────────────────────────────
      // Se inyecta en CADA request que pase por este cliente.
      // null = usuario no logueado o logout limpio → no se envía el header.
      if (sessionToken != null) {
        request.headers['X-Session-Token'] = sessionToken!;
      }

      final response = await _inner.send(request);

      // ── Intercepción de 401: Sesión expirada ─────────────────────────────
      // El backend devuelve 401 en dos casos:
      //   a) SESSION_MISSING: no vino header (no debería ocurrir si el token está bien inyectado)
      //   b) SESSION_EXPIRED: el token no existe en BD (fue sobrescrito por otro login)
      // En ambos casos forzamos re-login, pero SESSION_EXPIRED es el caso crítico
      // de seguridad de la Vulnerabilidad #3.
      if (response.statusCode == 401) {
        throw const SessionExpiredException();
      }

      // ── Intercepción de errores del servidor (5xx) ───────────────────────
      if (response.statusCode >= 500) {
        throw NetworkException(_friendlyErrorMessage);
      }

      return response;
    } on SocketException {
      throw NetworkException(_friendlyErrorMessage);
    } on http.ClientException {
      throw NetworkException(_friendlyErrorMessage);
    } catch (e) {
      rethrow;
    }
  }
}
