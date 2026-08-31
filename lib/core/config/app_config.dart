import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;

/// Configuración centralizada de la aplicación.
/// Modificar aquí para cambiar el endpoint del servidor en toda la app.
class AppConfig {
  AppConfig._(); // No instanciable

  /// URL base de la API del backend local (Laragon/Apache).
  static const String kApiBaseUrl =
      'http://192.168.1.200/Sistema_POS/pos-backend/public/api';

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

  /// True si la app corre en un dispositivo móvil (Android o iOS).
  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// True si la app corre en escritorio (Windows, Linux o macOS).
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// True si la app corre en el navegador web.
  static bool get isWeb => kIsWeb;
}
