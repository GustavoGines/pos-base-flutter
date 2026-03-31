import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  AuthRemoteDataSource({required this.baseUrl, required this.client});

  Future<Map<String, dynamic>> verifyPin(String pin) async {
    final url = '$baseUrl/auth/verify-pin';
    debugPrint('=== AUTH: Llamando a POST $url ===');
    try {
      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({'pin': pin}),
      ).timeout(const Duration(seconds: 10));

      debugPrint('=== AUTH: Status ${response.statusCode}, body: ${response.body} ===');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          return data['user'];
        } catch (_) {
          throw const FormatException('La respuesta del servidor no es un JSON válido.');
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
}
