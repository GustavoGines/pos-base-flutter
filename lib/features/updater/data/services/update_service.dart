import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../core/config/app_config.dart';
import '../models/update_info.dart';

class UpdateService {
  /// Consulta al servidor si hay una versión más nueva disponible.
  ///
  /// - Envía la versión actual del cliente como query param [current_version].
  /// - El servidor compara y responde con [update_available] + datos del release.
  /// - Si [throwErrors] es true, los errores de red se propagan (para el botón
  ///   manual en Settings). Si es false, los errores se silencian (heartbeat).
  Future<UpdateInfo?> checkUpdate({bool throwErrors = false}) async {
    try {
      // Leer la versión actual del pubspec.yaml compilado
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // ej: "1.1.0"

      final uri = Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update')
          .replace(queryParameters: {'current_version': currentVersion});

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(minutes: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // El servidor ahora devuelve update_available: true/false
        if (data['success'] == true && data['update_available'] == true && data['data'] != null) {
          return UpdateInfo.fromJson(data['data']);
        }

        // update_available: false → sistema al día, no es un error
        return null;
      }

      if (throwErrors) {
        throw Exception('El servidor respondió con código ${response.statusCode}');
      }
      return null;

    } on TimeoutException {
      if (throwErrors) {
        throw Exception('Timeout esperando al servidor (posible arranque en Render).');
      }
      return null;
    } catch (e) {
      if (throwErrors) rethrow;
      return null;
    }
  }
}
