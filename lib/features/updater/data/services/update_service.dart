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
      final currentBackendVersion = prefs.getString('backend_version') ?? '0.0.0';

      // 1. Chequeo de Backend
      final backendUri = Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update')
          .replace(queryParameters: {'component': 'backend', 'current_version': currentBackendVersion});

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
          .replace(queryParameters: {'component': 'frontend', 'current_version': currentFrontendVersion});

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

