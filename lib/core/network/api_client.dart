import 'dart:io';
import 'package:http/http.dart' as http;

/// Excepción personalizada para errores de red o servidor inalcanzable.
class NetworkException implements Exception {
  final String message;

  NetworkException(this.message);

  @override
  String toString() => message;
}

/// Cliente HTTP que intercepta las peticiones para capturar errores
/// de conexión o de servidor (500, 502, etc.) y traducirlos a un
/// mensaje amigable para el usuario.
class ApiClient extends http.BaseClient {
  final http.Client _inner;
  
  static const String _friendlyErrorMessage = 
      'No se pudo conectar con el servidor principal. Verifique su conexión a red o si el servidor está encendido.';

  ApiClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);
      
      // Si el servidor responde con errores críticos (500 Internal Server Error, 502 Bad Gateway, 503, 504)
      if (response.statusCode >= 500) {
        throw NetworkException(_friendlyErrorMessage);
      }
      
      return response;
    } on SocketException {
      // Error de red a nivel de sockets (ej. connection refused o host inalcanzable)
      throw NetworkException(_friendlyErrorMessage);
    } on http.ClientException {
      // Error de red capturado por el cliente http
      throw NetworkException(_friendlyErrorMessage);
    } catch (e) {
      // Relanzar cualquier otra excepción para que se maneje normalmente
      rethrow;
    }
  }
}
