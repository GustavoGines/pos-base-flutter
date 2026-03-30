/// Configuración centralizada de la aplicación.
/// Modificar aquí para cambiar el endpoint del servidor en toda la app.
class AppConfig {
  AppConfig._(); // No instanciable

  /// URL base de la API del backend local (Laragon/Apache).
  static const String kApiBaseUrl =
      'http://127.0.0.1/Sistema_POS/pos-backend/public/api';
}
