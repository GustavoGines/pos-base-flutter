import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
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
          // Descarga e instala el backend silenciosamente en segundo plano
          unawaited(_performBackendUpdate(backendUpdate, prefs));
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

  Future<void> _performBackendUpdate(UpdateInfo update, SharedPreferences prefs) async {
    try {
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final zipPath = p.join(tempDir.path, 'update_backend_v${update.version}.zip');

      await dio.download(update.downloadUrl, zipPath);

      final installPath = File(Platform.resolvedExecutable).parent.path;
      final targetDir = p.join(installPath, 'pos-backend');
      final updaterPath = p.join(installPath, 'updater.exe');

      if (!File(updaterPath).existsSync()) return;

      await Process.run(
        'powershell',
        [
          'Start-Process',
          '-FilePath', '"$updaterPath"',
          '-ArgumentList', '"--component=backend", "--target-dir=\\"$targetDir\\"", "--zip-path=\\"$zipPath\\""',
          '-Verb', 'RunAs',
          '-Wait'
        ],
      );

      await prefs.setString('backend_version', update.version);
    } catch (e) {
      // Falla silenciosa: no interrumpir la sesión del usuario
      print('Error en backend update: $e');
    }
  }
}
