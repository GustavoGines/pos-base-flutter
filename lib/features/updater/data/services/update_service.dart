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

class UpdateService {
  /// Consulta al servidor si hay una versión más nueva disponible.
  /// Chequea backend y frontend de forma separada.
  Future<UpdateInfo?> checkUpdate({bool throwErrors = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentFrontendVersion = packageInfo.version;

      final prefs = await SharedPreferences.getInstance();
      final currentBackendVersion = prefs.getString('backend_version') ?? '0.0.0';

      // 1. Chequeo y descarga automática de Backend
      final backendUri = Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update')
          .replace(queryParameters: {'component': 'backend', 'current_version': currentBackendVersion});
          
      final backendResponse = await http.get(backendUri, headers: {'Accept': 'application/json'}).timeout(const Duration(minutes: 4));

      if (backendResponse.statusCode == 200) {
        final data = json.decode(backendResponse.body);
        if (data['success'] == true && data['update_available'] == true && data['data'] != null) {
          final backendUpdate = UpdateInfo.fromJson(data['data'], component: 'backend');
          // Iniciamos la actualización del backend silenciosamente de fondo
          unawaited(_performBackendUpdate(backendUpdate, prefs));
        }
      }

      // 2. Chequeo de Frontend (retorna UI dialog si es necesario)
      final frontendUri = Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update')
          .replace(queryParameters: {'component': 'frontend', 'current_version': currentFrontendVersion});

      final frontendResponse = await http.get(frontendUri, headers: {'Accept': 'application/json'}).timeout(const Duration(minutes: 4));

      if (frontendResponse.statusCode == 200) {
        final data = json.decode(frontendResponse.body);
        if (data['success'] == true && data['update_available'] == true && data['data'] != null) {
          return UpdateInfo.fromJson(data['data'], component: 'frontend');
        }
      }

      return null;
    } on TimeoutException {
      if (throwErrors) throw Exception('Timeout esperando al servidor (posible arranque en Render).');
      return null;
    } catch (e) {
      if (throwErrors) rethrow;
      return null;
    }
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
      
      // Actualizamos la preferencia tras lanzar la actualización
      await prefs.setString('backend_version', update.version);
    } catch (e) {
      print('Error en backend update: $e');
    }
  }
}
