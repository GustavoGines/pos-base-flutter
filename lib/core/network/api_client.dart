import 'dart:io';
import 'dart:async';
import 'dart:convert';
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

  /// PIN de administrador temporal para autorizaciones a nivel global de pantalla (PermissionGuard).
  /// Solo se inyecta automáticamente en peticiones de lectura (GET).
  String? _temporaryAdminPin;

  /// PIN de administrador explícito para bloques con alcance específico (withAdminPin).
  /// Se inyecta en CUALQUIER método HTTP durante la ejecución del closure.
  String? _scopedAdminPin;

  /// Callback global para manejar el error 401 de forma centralizada.
  void Function()? onSessionExpired;

  /// Callback global para solicitar PIN de administrador cuando el backend responde 403 (permiso denegado / descuento no autorizado).
  /// Retorna el PIN validado o null si el usuario canceló la operación.
  Future<String?> Function(String? reason)? onPermissionDenied;

  /// Control de concurrencia para evitar múltiples modales simultáneos si varias peticiones reciben 403 a la vez.
  Future<String?>? _pendingPinPrompt;

  static const String _friendlyErrorMessage =
      'No se pudo conectar con el servidor principal. Verifique su conexión a red o si el servidor está encendido.';

  ApiClient(this._inner);

  /// Stack de PINs efímeros asociados a las pantallas activas (PermissionGuard).
  final List<MapEntry<Object, String>> _ephemeralPinStack = [];

  /// Setea o limpia el PIN efímero global (gestionado por PermissionGuard para la pantalla activa).
  /// Si se provee un [owner], gestiona el ciclo de vida por pantalla mediante una pila LIFO,
  /// evitando que el dispose de rutas reemplazadas (pushReplacement) anule el PIN de la pantalla activa.
  void setGlobalEphemeralPin(String? pin, [Object? owner]) {
    final cleanPin = (pin != null && pin.trim().isNotEmpty) ? pin.trim() : null;
    if (owner != null) {
      if (cleanPin != null) {
        final existingIndex = _ephemeralPinStack.indexWhere((e) => e.key == owner);
        if (existingIndex != -1) {
          _ephemeralPinStack[existingIndex] = MapEntry(owner, cleanPin);
        } else {
          _ephemeralPinStack.add(MapEntry(owner, cleanPin));
        }
        _temporaryAdminPin = _ephemeralPinStack.last.value;
      } else {
        _ephemeralPinStack.removeWhere((entry) => entry.key == owner);
        if (_ephemeralPinStack.isNotEmpty) {
          _temporaryAdminPin = _ephemeralPinStack.last.value;
        } else {
          _temporaryAdminPin = null;
        }
      }
    } else {
      _temporaryAdminPin = cleanPin;
      if (cleanPin == null) {
        _ephemeralPinStack.clear();
        _lastVerifiedPin = null;
        _lastVerifiedPinTime = null;
      }
    }
  }

  /// PIN efímero global actual (si está activo).
  String? get globalEphemeralPin => _temporaryAdminPin;

  /// Ejecuta un bloque asíncrono garantizando que todas las llamadas HTTP
  /// efectuadas dentro del closure incluyan la cabecera 'X-Admin-Pin'.
  /// Inmediatamente al concluir (éxito o error), la cabecera es purgada de memoria.
  Future<T> withAdminPin<T>(String pin, Future<T> Function() action) async {
    final previousPin = _scopedAdminPin;
    _scopedAdminPin = pin.trim().isNotEmpty ? pin.trim() : null;
    try {
      return await action();
    } finally {
      _scopedAdminPin = previousPin;
    }
  }

  String? _lastVerifiedPin;
  DateTime? _lastVerifiedPinTime;

  void markPinAsVerified(String pin) {
    _lastVerifiedPin = pin;
    _lastVerifiedPinTime = DateTime.now();
  }

  Future<String?> _promptAdminPin(String? reason) async {
    if (_lastVerifiedPin != null && _lastVerifiedPinTime != null) {
      if (DateTime.now().difference(_lastVerifiedPinTime!).inSeconds < 2) {
        return _lastVerifiedPin;
      } else {
        _lastVerifiedPin = null;
        _lastVerifiedPinTime = null;
      }
    }

    if (_pendingPinPrompt != null) {
      return _pendingPinPrompt!;
    }
    final completer = Completer<String?>();
    _pendingPinPrompt = completer.future;

    () async {
      try {
        final pin = await onPermissionDenied!(reason);
        if (pin != null && pin.isNotEmpty) {
          markPinAsVerified(pin);
        }
        completer.complete(pin);
      } catch (e) {
        completer.complete(null);
      } finally {
        _pendingPinPrompt = null;
      }
    }();

    return completer.future;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      // ── Inyección del token de sesión ────────────────────────────────────
      // Se inyecta en CADA request que pase por este cliente.
      // null = usuario no logueado o logout limpio → no se envía el header.
      if (sessionToken != null) {
        request.headers['X-Session-Token'] = sessionToken!;
      }

      final String method = request.method.toUpperCase();

      // ── Inyección de PIN de Administrador / Supervisor ─────────────────
      // 1. Inyección explícita por bloque con alcance (withAdminPin) en CUALQUIER método HTTP.
      if (_scopedAdminPin != null && _scopedAdminPin!.isNotEmpty) {
        request.headers['X-Admin-Pin'] = _scopedAdminPin!;
      }
      // 2. Inyección automática de PIN efímero global (PermissionGuard) ÚNICAMENTE en peticiones seguras (GET).
      // Para POST, PUT, DELETE, PATCH, ApiClient NO inyecta automáticamente _temporaryAdminPin.
      // No sobreescribe si la petición ya incluye un X-Admin-Pin explícito en sus encabezados.
      else if (method == 'GET' &&
               _temporaryAdminPin != null &&
               _temporaryAdminPin!.isNotEmpty &&
               (request.headers['X-Admin-Pin'] == null || request.headers['X-Admin-Pin']!.isEmpty)) {
        request.headers['X-Admin-Pin'] = _temporaryAdminPin!;
      }

      // Prevenir el reúso de sockets muertos (SocketException/ClientException)
      // que ocurre cuando Apache/Nginx cierra la conexión por inactividad.
      request.headers['Connection'] = 'close';

      // Preservar metadatos de la petición para posible reintento ante 403
      final Uri url = request.url;
      final Map<String, String> headers = Map<String, String>.from(request.headers);
      final List<int>? bodyBytes = (request is http.Request) ? request.bodyBytes : null;
      final Encoding encoding = (request is http.Request) ? request.encoding : utf8;

      final response = await _inner.send(request).timeout(const Duration(seconds: 20));

      // ── Intercepción de 401: Sesión expirada ─────────────────────────────
      // El backend devuelve 401 en dos casos:
      //   a) PIN Incorrecto (o error de login normal)
      //   b) SESSION_EXPIRED: el token no existe en BD (fue sobrescrito por otro login)
      // Solo en el caso b) disparamos el SessionExpiredException.
      if (response.statusCode == 401) {
        final bodyBytes401 = await response.stream.toBytes();
        final bodyString = utf8.decode(bodyBytes401, allowMalformed: true);

        if (bodyString.contains('SESSION_EXPIRED')) {
          onSessionExpired?.call();
          throw const SessionExpiredException();
        }

        // Si es un 401 normal (ej: PIN incorrecto), devolvemos la respuesta original
        // recreando el stream para que el caller pueda parsearla sin problemas.
        return http.StreamedResponse(
          Stream.value(bodyBytes401),
          response.statusCode,
          contentLength: bodyBytes401.length,
          request: response.request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
        );
      }

      // ── Intercepción de 403: Permiso Denegado / Autorización In Situ ──────
      if (response.statusCode == 403) {
        final path = url.path;
        final isAuthEndpoint = path.contains('/auth/authorize-pin') ||
                               path.contains('/auth/verify-pin') ||
                               path.contains('/auth/login') ||
                               path.contains('/auth/me') ||
                               path.contains('/auth/logout');

        final alreadyHasPin = headers.containsKey('X-Admin-Pin') && headers['X-Admin-Pin']!.isNotEmpty;

        if (!isAuthEndpoint && !alreadyHasPin && onPermissionDenied != null && request is http.Request) {
          final resBytes = await response.stream.toBytes();
          final resString = utf8.decode(resBytes, allowMalformed: true);

          String? reason;
          bool isPermissionError = false;

          try {
            final decoded = json.decode(resString);
            if (decoded is Map<String, dynamic>) {
              final errorCode = decoded['error_code'] as String?;
              reason = decoded['message'] as String?;

              final isLicenseOrFeatureBlock = errorCode == 'FEATURE_NOT_LICENSED' ||
                  errorCode == 'MODULE_DISABLED' ||
                  errorCode == 'DIFFERENCE_REQUIRES_ADMIN';

              if (!isLicenseOrFeatureBlock) {
                if (errorCode == 'PIN_REQUIRED' ||
                    errorCode == 'UNAUTHORIZED_PRICE_DISCOUNT' ||
                    errorCode == 'INVALID_ADMIN_PIN' ||
                    errorCode == 'FORBIDDEN' ||
                    errorCode == 'UNAUTHORIZED' ||
                    (errorCode != null && (
                      errorCode.contains('PIN') ||
                      errorCode.contains('PERMISSION') ||
                      errorCode.contains('AUTH')
                    ))) {
                  isPermissionError = true;
                } else if (reason != null) {
                  final lower = reason.toLowerCase();
                  if (lower.contains('pin') ||
                      lower.contains('permiso') ||
                      lower.contains('autoriz') ||
                      lower.contains('unauthorized') ||
                      lower.contains('denegado')) {
                    isPermissionError = true;
                  }
                }
              }
            }
          } catch (_) {
            final lower = resString.toLowerCase();
            if (lower.contains('permiso') ||
                lower.contains('unauthorized') ||
                lower.contains('forbidden') ||
                lower.contains('denegado')) {
              isPermissionError = true;
            }
          }

          if (isPermissionError) {
            final pin = await _promptAdminPin(reason);
            if (pin != null && pin.isNotEmpty) {
              final retryHeaders = Map<String, String>.from(headers)
                ..removeWhere((k, _) => k.toLowerCase() == 'content-length');
              final retryRequest = http.Request(method, url)
                ..headers.addAll(retryHeaders)
                ..encoding = encoding;
              if (bodyBytes != null && method != 'GET' && method != 'HEAD') {
                retryRequest.bodyBytes = bodyBytes;
              }
              retryRequest.headers['X-Admin-Pin'] = pin;
              if (sessionToken != null) {
                retryRequest.headers['X-Session-Token'] = sessionToken!;
              }
              retryRequest.headers['Connection'] = 'close';

              final retryResponse = await _inner.send(retryRequest).timeout(const Duration(seconds: 20));

              // ── Intercepción de 401 en el reintento (Sesión expirada durante espera del PIN) ──
              if (retryResponse.statusCode == 401) {
                final bodyBytes401 = await retryResponse.stream.toBytes();
                final bodyString = utf8.decode(bodyBytes401, allowMalformed: true);

                if (bodyString.contains('SESSION_EXPIRED')) {
                  onSessionExpired?.call();
                  throw const SessionExpiredException();
                }

                return http.StreamedResponse(
                  Stream.value(bodyBytes401),
                  retryResponse.statusCode,
                  contentLength: bodyBytes401.length,
                  request: retryResponse.request,
                  headers: retryResponse.headers,
                  isRedirect: retryResponse.isRedirect,
                  persistentConnection: retryResponse.persistentConnection,
                  reasonPhrase: retryResponse.reasonPhrase,
                );
              }

              // ── Intercepción de 5xx en el reintento ────────────────────────
              if (retryResponse.statusCode >= 500) {
                throw NetworkException(_friendlyErrorMessage);
              }

              return retryResponse;
            }
          }

          // Si el usuario canceló o no es un error de permisos interceptable,
          // devolvemos la respuesta 403 original recreando el stream.
          return http.StreamedResponse(
            Stream.value(resBytes),
            response.statusCode,
            contentLength: resBytes.length,
            request: response.request,
            headers: response.headers,
            isRedirect: response.isRedirect,
            persistentConnection: response.persistentConnection,
            reasonPhrase: response.reasonPhrase,
          );
        }
      }

      // ── Intercepción de errores del servidor (5xx) ───────────────────────
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
