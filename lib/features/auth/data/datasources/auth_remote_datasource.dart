import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  AuthRemoteDataSource({required this.baseUrl, required this.client});

  // ──────────────────────────────────────────────────────────────────────────
  // LOGIN COMPLETO
  // Devuelve { user: {...}, session_token: "..." }
  // El session_token se guarda en AuthProvider y se inyecta en ApiClient.
  // ──────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> verifyPin(String pin) async {
    final url = '$baseUrl/auth/verify-pin';
    debugPrint('=== AUTH: Llamando a POST $url ===');
    try {
      final response = await client
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: json.encode({'pin': pin}),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint(
          '=== AUTH: Status ${response.statusCode}, body: ${response.body} ===');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          // Devolvemos el objeto completo { user, session_token }
          // para que AuthProvider pueda guardar ambas cosas.
          return {
            'user': data['user'] as Map<String, dynamic>,
            'session_token': data['session_token'] as String,
          };
        } catch (_) {
          throw const FormatException(
              'La respuesta del servidor no es un JSON válido.');
        }
      } else if (response.statusCode == 401) {
        throw Exception('PIN incorrecto');
      } else if (response.statusCode == 404) {
        throw Exception(
          'Error de conexión: No se encontró el servidor. Por favor, verifica la URL en la configuración (⋮).',
        );
      } else if (response.statusCode == 500) {
        throw Exception('Error interno del servidor. Contacte a soporte técnico.');
      } else {
        throw Exception('Error del servidor (${response.statusCode})');
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      debugPrint('=== AUTH ERROR: $e ===');
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('ClientException') ||
          errStr.contains('Connection refused')) {
        throw Exception(
          'Error de conexión: No se encontró el servidor. Por favor, verifica la URL en la configuración (⋮).',
        );
      }
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // AUTORIZACIÓN PUNTUAL (AdminPinDialog)
  // Solo valida el PIN — NO genera token, NO invalida sesiones.
  // Usar EXCLUSIVAMENTE para flujos de autorización in-app (ej: anulaciones).
  // ──────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> authorizePin(String pin) async {
    final url = '$baseUrl/auth/authorize-pin';
    debugPrint('=== AUTH: Autorización puntual POST $url ===');
    try {
      final response = await client
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: json.encode({'pin': pin}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['user'] as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        throw Exception('PIN incorrecto');
      } else {
        throw Exception('Error del servidor (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('=== AUTHORIZE PIN ERROR: $e ===');
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('Connection refused')) {
        throw Exception('Error de conexión con el servidor.');
      }
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LOGOUT
  // Nullifica el session_token en BD. Idempotente (200 aunque el token
  // ya haya sido invalidado por otro login).
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> logout(String sessionToken) async {
    final url = '$baseUrl/auth/logout';
    debugPrint('=== AUTH: Logout POST $url ===');
    try {
      await client
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-Session-Token': sessionToken,
            },
          )
          .timeout(const Duration(seconds: 5));
      // Fire-and-forget: no lanzamos error si falla el logout remoto.
      // El token ya fue limpiado localmente por AuthProvider.
    } catch (e) {
      debugPrint('=== LOGOUT WARNING (non-critical): $e ===');
    }
  }
}
