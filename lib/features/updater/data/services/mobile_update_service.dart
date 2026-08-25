import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/config/app_config.dart';
import '../models/update_info.dart';

/// Servicio de actualizaciones OTA exclusivo para Android.
///
/// Flujo:
///   1. [checkForUpdate] → consulta al License Server si hay APK nuevo.
///   2. [downloadAndInstall] → descarga el APK con progreso y lo instala.
///
/// El APK siempre se descarga a la carpeta de caché interna de la app
/// (`getCacheDir()/apk_downloads/`) para que el FileProvider pueda servirlo
/// al instalador del sistema sin necesidad de `WRITE_EXTERNAL_STORAGE`.
class MobileUpdateService {
  /// Notificador global reactivo. Se actualiza al detectar una nueva versión.
  static final ValueNotifier<UpdateInfo?> mobileUpdateNotifier =
      ValueNotifier(null);

  /// Consulta al License Server si hay una versión de Android más nueva.
  ///
  /// Retorna [UpdateInfo] si hay actualización disponible, `null` si está al día.
  static Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final uri =
          Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update').replace(
        queryParameters: {
          'component': 'android',
          'current_version': currentVersion,
          'channel': 'stable',
        },
      );

      final response = await Dio()
          .getUri(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true &&
            data['update_available'] == true &&
            data['data'] != null) {
          final update =
              UpdateInfo.fromJson(data['data'] as Map<String, dynamic>,
                  component: 'android');
          mobileUpdateNotifier.value = update;
          return update;
        }
      }
    } on TimeoutException {
      debugPrint('[MobileUpdate] Timeout al consultar actualizaciones.');
    } catch (e) {
      debugPrint('[MobileUpdate] Error al consultar actualizaciones: $e');
    }
    return null;
  }

  /// Descarga el APK desde [downloadUrl] y lanza el instalador del sistema.
  ///
  /// [onProgress] recibe valores de 0.0 a 1.0 durante la descarga.
  static Future<void> downloadAndInstall(
    String downloadUrl, {
    required void Function(double progress) onProgress,
  }) async {
    // ── 1. Crear directorio de descarga en caché interna ────────────────────
    final cacheDir = await getTemporaryDirectory();
    final apkDir = Directory('${cacheDir.path}/apk_downloads');
    if (!await apkDir.exists()) await apkDir.create(recursive: true);

    final apkPath = '${apkDir.path}/pos_mobile_update.apk';

    // ── 2. Descargar con Dio (mismo cliente que usa el updater de desktop) ──
    await Dio().download(
      downloadUrl,
      apkPath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress(received / total);
        }
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 10),
        headers: {'Accept': 'application/vnd.android.package-archive'},
      ),
    );

    onProgress(1.0);

    // ── 3. Lanzar el instalador del sistema ─────────────────────────────────
    // open_filex maneja internamente el FileProvider para Android 7+.
    final result = await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type != ResultType.done) {
      throw Exception(
          'No se pudo abrir el instalador: ${result.message}\n\n'
          'Verificá que "Instalar apps de fuentes desconocidas" esté '
          'habilitado en Ajustes > Apps > POS Móvil.');
    }
  }
}
