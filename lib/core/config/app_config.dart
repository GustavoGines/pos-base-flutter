import 'package:flutter/material.dart';

/// Configuración centralizada de la aplicación.
/// Modificar aquí para cambiar el endpoint del servidor en toda la app.
class AppConfig {
  AppConfig._(); // No instanciable

  /// URL base de la API del backend local (Laragon/Apache).
  static const String kApiBaseUrl =
      'http://127.0.0.1/Sistema_POS/pos-backend/public/api';

  /// URL de la API del Servidor de Licencias Central (Render)
  /// Utilizado para consultar check-update (OTA) de manera directa.
  static const String kLicenseServerUrl =
      'https://pos-license-server.onrender.com'; // ¡Ajustar según donde esté subido tu License Server!

  /// Navigation key global para poder mostrar dialogos/rutas desde Providers sin contexto explícito
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}
