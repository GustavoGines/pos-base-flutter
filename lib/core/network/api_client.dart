import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// ExcepciÃ³n para errores de red genÃ©ricos (servidor caÃ­do, sin conexiÃ³n).
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  @override
  String toString() => message;
}

/// ExcepciÃ³n tipada para SesiÃ³n Ãšnica Activa.
/// Se lanza cuando el servidor responde 401 con error_code SESSION_EXPIRED,
/// lo que significa que otro dispositivo hizo login con el mismo usuario.
/// Los providers y screens capturan esta excepciÃ³n para mostrar el dialog
/// de seguridad y forzar la navegaciÃ³n a /login.
class SessionExpiredException implements Exception {
  final String message;
  const SessionExpiredException(
      [this.message =
          'Tu sesiÃ³n fue cerrada porque otro dispositivo iniciÃ³ sesiÃ³n con tu usuario.']);
  @override
  String toString() => message;
}

/// Cliente HTTP centralizado que:
///   1. Inyecta el header X-Session-Token en TODOS los requests (Single Active Session).
///   2. Intercepta 401 SESSION_EXPIRED â†’ lanza SessionExpiredException tipada.
///   3. Intercepta 5xx y errores de red â†’ lanza NetworkException amigable.
///
/// Al ser un http.BaseClient, cubre automÃ¡ticamente todos los datasources
/// sin necesidad de modificar cada uno individualmente.
class ApiClient extends http.BaseClient {
  final http.Client _inner;

  /// Token de sesiÃ³n activo. Se setea desde AuthProvider al hacer login
  /// y se limpia al hacer logout. El setter es thread-safe para Dart.
  String? sessionToken;

  /// Callback global para manejar el error 401 de forma centralizada.
  void Function()? onSessionExpired;

  static const String _friendlyErrorMessage =
      'No se pudo conectar con el servidor principal. Verifique su conexiÃ³n a red o si el servidor estÃ¡ encendido.';

  ApiClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      // â”€â”€ InyecciÃ³n del token de sesiÃ³n â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // Se inyecta en CADA request que pase por este cliente.
      // null = usuario no logueado o logout limpio â†’ no se envÃ­a el header.
      if (sessionToken != null) {
        request.headers['X-Session-Token'] = sessionToken!;
      }

      // Prevenir el reÃºso de sockets muertos (SocketException/ClientException)
      // que ocurre cuando Apache/Nginx cierra la conexiÃ³n por inactividad.
      request.headers['Connection'] = 'close';

      final response = await _inner.send(request).timeout(const Duration(seconds: 20));

      // â”€â”€ IntercepciÃ³n de 401: SesiÃ³n expirada â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // El backend devuelve 401 en dos casos:
      //   a) PIN Incorrecto (o error de login normal)
      //   b) SESSION_EXPIRED: el token no existe en BD (fue sobrescrito por otro login)
      // Solo en el caso b) disparamos el SessionExpiredException.
      if (response.statusCode == 401) {
        final bodyBytes = await response.stream.toBytes();
        final bodyString = utf8.decode(bodyBytes, allowMalformed: true);

        if (bodyString.contains('SESSION_EXPIRED')) {
          onSessionExpired?.call();
          throw const SessionExpiredException();
        }

        // Si es un 401 normal (ej: PIN incorrecto), devolvemos la respuesta original
        // recreando el stream para que el caller pueda parsearla sin problemas.
        return http.StreamedResponse(
          Stream.value(bodyBytes),
          response.statusCode,
          contentLength: bodyBytes.length,
          request: response.request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
        );
      }

      // â”€â”€ IntercepciÃ³n de errores del servidor (5xx) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      if (response.statusCode >= 500) {
        throw NetworkException(_friendlyErrorMessage);
      }

      return response;
    } on TimeoutException {
      throw NetworkException('El servidor está tardando demasiado en responder. Intente de nuevo.');
    } on SocketException {
      throw NetworkException(_friendlyErrorMessage);
    } on http.ClientException {
      throw NetworkException(_friendlyErrorMessage);
    } catch (e) {
      rethrow;
    }
  }
}
