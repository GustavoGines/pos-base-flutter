import '../config/app_config.dart';

/// Resuelve una ruta o URL de imagen a una URL HTTP/HTTPS absoluta y sanitizada.
///
/// Soporta:
/// - URLs absolutas existentes ('http://...', 'https://...').
/// - Rutas de storage de Laravel relativas ('business/logo.png', 'products/1.jpg').
/// - Rutas con prefijo 'storage/' o '/storage/'.
/// - Valores nulos, vacíos, o string 'null'.
String? resolveImageUrl(String? pathOrUrl, {String? baseUrl}) {
  if (pathOrUrl == null) return null;
  final trimmed = pathOrUrl.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;

  // Si tiene formato de URL absoluta HTTP o HTTPS
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme && uri.hasAuthority && uri.host.isNotEmpty) {
      return trimmed;
    }
    // Descartar URLs con prefijo http pero sin host o autoridad válidos (ej: 'http://')
    return null;
  }

  // Base URL del servidor activo
  final activeBase = (baseUrl != null && baseUrl.trim().isNotEmpty)
      ? baseUrl.trim()
      : AppConfig.kApiBaseUrl;

  // Remover '/api' o '/api/' al final para obtener la raíz web y eliminar trailing slash
  String baseRoot = activeBase.replaceAll(RegExp(r'/api/?$'), '');
  if (baseRoot.endsWith('/')) {
    baseRoot = baseRoot.substring(0, baseRoot.length - 1);
  }

  // Normalizar ruta de almacenamiento (reemplazar separadores Windows y slashes iniciales)
  String relativePath = trimmed.replaceAll(r'\', '/');
  while (relativePath.startsWith('/')) {
    relativePath = relativePath.substring(1);
  }

  if (relativePath.startsWith('storage/')) {
    return '$baseRoot/$relativePath';
  } else {
    return '$baseRoot/storage/$relativePath';
  }
}
