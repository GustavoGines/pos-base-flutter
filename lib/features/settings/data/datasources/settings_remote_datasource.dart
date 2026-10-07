import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:frontend_desktop/core/utils/image_url_resolver.dart';
import '../models/business_settings_model.dart';

abstract class SettingsRemoteDataSource {
  Future<BusinessSettingsModel> fetchSettings();
  Future<BusinessSettingsModel> updateSettings(Map<String, dynamic> data);
  Future<String> uploadLogo(String filePath, {List<int>? bytes, String? filename});
  Future<Map<String, dynamic>> fetchIntegrations();
  Future<bool> updateIntegrations(Map<String, dynamic> data);
  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken});
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

  MediaType _resolveMediaType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'webp':
        return MediaType('image', 'webp');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  String _parseApiError(String responseBody, String defaultMsg) {
    try {
      final decoded = json.decode(responseBody);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('errors')) {
          final errors = decoded['errors'] as Map<String, dynamic>;
          if (errors.isNotEmpty) {
            final firstError = errors.values.first;
            if (firstError is List && firstError.isNotEmpty) {
              return firstError.first.toString();
            }
          }
        }
        if (decoded.containsKey('message')) {
          return decoded['message'].toString();
        }
      }
    } catch (_) {}
    return defaultMsg;
  }

  @override
  Future<String> uploadLogo(String filePath, {List<int>? bytes, String? filename}) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/settings/logo'),
      );
      request.headers['Accept'] = 'application/json';

      final name = filename ?? (filePath.isNotEmpty ? filePath.split(RegExp(r'[/\\]')).last : 'logo.png');
      final mediaType = _resolveMediaType(name);

      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes('logo', bytes, filename: name, contentType: mediaType));
      } else {
        request.files.add(await http.MultipartFile.fromPath('logo', filePath, contentType: mediaType));
      }

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final jsonMap = json.decode(response.body);
        final rawLogo = (jsonMap['logo_path'] ?? jsonMap['logo_url'])?.toString();
        return resolveImageUrl(rawLogo, baseUrl: baseUrl) ?? (rawLogo ?? '');
      } else if (response.statusCode == 404) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      } else if (response.statusCode == 500) {
        throw Exception('Error interno del servidor. Contacte a soporte técnico.');
      } else {
        throw Exception(_parseApiError(response.body, 'Error al subir logotipo (Status: ${response.statusCode})'));
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      print('=== API Error en uploadLogo: $e ===');
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
  Future<Map<String, dynamic>> fetchIntegrations() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/settings/integrations'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        try {
          return json.decode(response.body) as Map<String, dynamic>;
        } catch (_) {
          throw const FormatException('La respuesta del servidor no es un JSON válido.');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      } else if (response.statusCode == 500) {
        throw Exception('Error interno del servidor. Contacte a soporte técnico.');
      } else {
        throw Exception(_parseApiError(response.body, 'Error al obtener integraciones (Status: ${response.statusCode})'));
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } catch (e) {
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
  Future<bool> updateIntegrations(Map<String, dynamic> data) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/settings/integrations'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 404) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      } else if (response.statusCode == 500) {
        throw Exception('Error interno del servidor. Contacte a soporte técnico.');
      } else {
        throw Exception(_parseApiError(response.body, 'Error al guardar integraciones (Status: ${response.statusCode})'));
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } catch (e) {
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
  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken}) async {
    try {
      final Map<String, dynamic> payload = {};
      if (mpAccessToken != null) {
        payload['mp_access_token'] = mpAccessToken;
      }

      final response = await client.post(
        Uri.parse('$baseUrl/settings/integrations/mercadopago/test'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      final Map<String, dynamic> decoded;
      try {
        decoded = json.decode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw const FormatException('La respuesta del servidor no es un JSON válido.');
      }

      if (response.statusCode == 200) {
        return {
          'success': decoded['success'] == true,
          'message': decoded['message']?.toString() ?? 'Conexión exitosa',
          'collector_id': decoded['collector_id'],
          'nickname': decoded['nickname'],
        };
      } else {
        return {
          'success': false,
          'message': decoded['message']?.toString() ?? 'Error al conectar con Mercado Pago',
        };
      }
    } on FormatException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('ClientException')) {
        return {
          'success': false,
          'message': 'No se pudo conectar con el servidor principal.',
        };
      }
      return {
        'success': false,
        'message': 'Error inesperado al probar la conexión.',
      };
    }
  }
}
