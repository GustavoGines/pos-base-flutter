import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/business_settings_model.dart';

abstract class SettingsRemoteDataSource {
  Future<BusinessSettingsModel> fetchSettings();
  Future<BusinessSettingsModel> updateSettings(Map<String, dynamic> data);
}

class SettingsRemoteDataSourceImpl implements SettingsRemoteDataSource {
  String baseUrl; // ej. http://localhost:8000/api
  final http.Client client;

  SettingsRemoteDataSourceImpl({required this.baseUrl, required this.client});

  void updateBaseUrl(String newUrl) {
    baseUrl = newUrl;
  }

  @override
  Future<BusinessSettingsModel> fetchSettings() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/settings'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        try {
          final jsonMap = json.decode(response.body);
          return BusinessSettingsModel.fromJson(jsonMap);
        } catch (_) {
          throw const FormatException('La respuesta del servidor no es un JSON válido.');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      } else if (response.statusCode == 500) {
        throw Exception('Error interno del servidor. Contacte a soporte técnico.');
      } else {
        throw Exception('Failed to load settings (Status: ${response.statusCode})');
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      print('=== API Error en fetchSettings: $e ===');
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('ClientException')) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      }
      rethrow;
    }
  }

  @override
  Future<BusinessSettingsModel> updateSettings(Map<String, dynamic> data) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/settings'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        try {
          final jsonMap = json.decode(response.body);
          return BusinessSettingsModel.fromJson(jsonMap['settings']);
        } catch (_) {
          throw const FormatException('La respuesta del servidor no es un JSON válido.');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      } else if (response.statusCode == 500) {
        throw Exception('Error interno del servidor. Contacte a soporte técnico.');
      } else {
        throw Exception('Failed to update settings (Status: ${response.statusCode})');
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      print('=== API Error en updateSettings: $e ===');
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('ClientException')) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      }
      rethrow;
    }
  }
}
