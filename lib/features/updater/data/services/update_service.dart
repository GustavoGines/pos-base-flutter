import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/app_config.dart';
import '../models/update_info.dart';

class UpdateCheckResult {
  final UpdateInfo? frontendUpdate;
  final UpdateInfo? backendUpdate;

  UpdateCheckResult({this.frontendUpdate, this.backendUpdate});

  bool get hasAny => frontendUpdate != null || backendUpdate != null;
}

class UpdateService {
  /// Consulta al servidor si hay versiones nuevas disponibles.
  /// Chequea backend y frontend de forma separada.
  /// Retorna [UpdateCheckResult] con ambos componentes (si hay actualizaciones).
  Future<UpdateCheckResult> checkUpdate({bool throwErrors = false}) async {
    UpdateInfo? frontendUpdate;
    UpdateInfo? backendUpdate;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentFrontendVersion = packageInfo.version;

      final prefs = await SharedPreferences.getInstance();
      
      // 0. Obtener versión REAL del backend local (Single Source of Truth).
      // IMPORTANTE: si /version-check falla (timeout, URL incorrecta, etc.)
      // usamos '0.0.0' como fallback —nunca el valor cacheado en SharedPrefs—
      // para evitar que un entorno cambiado (ej: Sistema_POS → Sistema_POS_test)
      // bloquee silenciosamente la detección de actualizaciones.
      String currentBackendVersion = '0.0.0';
      try {
        final currentApiUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
        final localBackendUri = Uri.parse('$currentApiUrl/version-check?t=${DateTime.now().millisecondsSinceEpoch}');
        final localResponse = await http.get(localBackendUri).timeout(const Duration(seconds: 5));
        if (localResponse.statusCode == 200) {
          final localData = json.decode(localResponse.body);
          currentBackendVersion = localData['version'] ?? '0.0.0';
        } else {
          // Si el servidor responde pero hay error (500, 404), usamos 0.0.0 para permitir que el OTA lo repare.
          currentBackendVersion = '0.0.0'; 
        }
      } on TimeoutException {
        // Laragon o la red no ha arrancado todavía
        if (throwErrors) throw Exception('El servidor local está apagado o iniciando (Timeout).');
      } catch (e) {
        // Conexión rechazada (SocketException), etc.
        if (throwErrors) throw Exception('El servidor local está apagado o inaccesible.');
      }

      final updateChannel = prefs.getString('update_channel') ?? 'stable';

      // 1. Chequeo de Backend
      final backendUri = Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update')
          .replace(queryParameters: {'component': 'backend', 'current_version': currentBackendVersion, 'channel': updateChannel});

      final backendResponse = await http
          .get(backendUri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(minutes: 4));

      if (backendResponse.statusCode == 200) {
        final data = json.decode(backendResponse.body);
        if (data['success'] == true && data['update_available'] == true && data['data'] != null) {
          backendUpdate = UpdateInfo.fromJson(data['data'], component: 'backend');
        }
      }

      // 2. Chequeo de Frontend
      final frontendUri = Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update')
          .replace(queryParameters: {'component': 'frontend', 'current_version': currentFrontendVersion, 'channel': updateChannel});

      final frontendResponse = await http
          .get(frontendUri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(minutes: 4));

      if (frontendResponse.statusCode == 200) {
        final data = json.decode(frontendResponse.body);
        if (data['success'] == true && data['update_available'] == true && data['data'] != null) {
          frontendUpdate = UpdateInfo.fromJson(data['data'], component: 'frontend');
        }
      }
    } on TimeoutException {
      if (throwErrors) throw Exception('Timeout esperando al servidor (posible arranque en Render).');
    } catch (e) {
      if (throwErrors) rethrow;
    }

    return UpdateCheckResult(frontendUpdate: frontendUpdate, backendUpdate: backendUpdate);
  }
}

