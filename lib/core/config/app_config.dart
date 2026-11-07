import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io' show Directory, File, Platform;

/// Configuración centralizada de la aplicación.
/// Modificar aquí para cambiar el endpoint del servidor en toda la app.
class AppConfig {
  AppConfig._(); // No instanciable

  /// URL base de la API del backend local (Laragon/Apache).
  static const String kApiBaseUrl =
      'http://192.168.1.200/Sistema_POS/pos-backend/public/api';

  /// URLs locales de fallback cuando la app corre en la misma PC Servidor (Laragon).
  static const String kLocalhostLaragonUrl =
      'http://127.0.0.1/Sistema_POS/pos-backend/public/api';
  static const String kLocalhostDirectUrl =
      'http://localhost/Sistema_POS/pos-backend/public/api';

  /// URL de la API del Servidor de Licencias Central (Render)
  /// Utilizado para consultar check-update (OTA) de manera directa.
  static const String kLicenseServerUrl =
      'https://pos-license-server-2jma.onrender.com'; // Actualizado con tu instancia real

  /// Navigation key global para poder mostrar dialogos/rutas desde Providers sin contexto explícito
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Bandera híbrida para Corralones y Madereras
  static const bool isCorralonMode = true;

  // ── Detección de plataforma ──────────────────────────────────────────────
  // Usar estos getters en lugar de Platform.isAndroid || Platform.isIOS
  // disperso por el código. Si en el futuro se agrega iOS o Linux,
  // solo hay que actualizar aquí.

  /// Permite sobrescribir la detección de plataforma exclusivamente en pruebas de unidad/widget.
  @visibleForTesting
  static bool? debugOverrideIsMobile;

  /// True si la app corre en un dispositivo móvil (Android o iOS).
  static bool get isMobile =>
      debugOverrideIsMobile ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  /// True si la app corre en escritorio (Windows, Linux o macOS).
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// True si la app corre en el navegador web.
  static bool get isWeb => kIsWeb;

  /// Determina si una URL apunta a una dirección IPv4 privada de red local
  /// (ej. 192.168.x.x, 10.x.x.x, 172.16-31.x.x), la cual suele cambiar o fallar
  /// cuando una notebook se traslada de una red Wi-Fi a otra.
  static bool isPrivateLanIpUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final host = uri.host.trim();
      if (host.isEmpty) return false;
      final ipv4Regex = RegExp(
        r'^(192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})$',
      );
      return ipv4Regex.hasMatch(host);
    } catch (_) {
      return false;
    }
  }

  /// Verifica en Windows si esta máquina cuenta con una instalación local de Laragon / pos-backend
  /// (PC Servidor), permitiendo hacer fallback automático a 127.0.0.1 cuando falla la IP LAN.
  static bool hasLocalLaragonServer() {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      const candidateDirs = <String>[
        r'C:\laragon\www\Sistema_POS\pos-backend',
        r'C:\laragon\www\pos-backend',
        r'C:\laragon',
      ];
      for (final path in candidateDirs) {
        if (Directory(path).existsSync()) return true;
      }
      final exeDir = File(Platform.resolvedExecutable).parent;
      final siblingBackend = Directory('${exeDir.parent.path}\\pos-backend');
      if (siblingBackend.existsSync()) return true;
    } catch (_) {}
    return false;
  }
}
