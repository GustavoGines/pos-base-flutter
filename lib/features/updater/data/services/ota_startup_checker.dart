import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Resultado de la última operación OTA leída desde disco.
class OtaStartupResult {
  final bool success;
  final String component;
  final String version;
  final String logContent;
  final bool wasPending;

  const OtaStartupResult({
    required this.success,
    required this.component,
    required this.version,
    required this.logContent,
    required this.wasPending,
  });
}

/// Servicio que se ejecuta al arrancar la app para verificar si el updater
/// corrió mientras la app estaba cerrada y qué resultado tuvo.
///
/// Archivos que chequea en el directorio de instalación:
///   - ota_result.txt   → 'SUCCESS' o 'FAILED' (escrito por updater.exe)
///   - ota_pending.json → info del update que se intentó instalar
///   - updater_log.txt  → log completo para diagnóstico
class OtaStartupChecker {
  static final String _installPath =
      File(Platform.resolvedExecutable).parent.path;

  static File get _resultFile =>
      File(p.join(_installPath, 'ota_result.txt'));
  static File get _pendingFile =>
      File(p.join(_installPath, 'ota_pending.json'));
  static File get _logFile =>
      File(p.join(_installPath, 'updater_log.txt'));

  /// Revisa si hay un resultado OTA pendiente de mostrar al usuario.
  /// Retorna null si no hay nada que mostrar.
  static OtaStartupResult? check() {
    try {
      if (!_resultFile.existsSync()) return null;

      final resultRaw = _resultFile.readAsStringSync().trim();
      final success = resultRaw == 'SUCCESS';

      String component = 'frontend';
      String version = 'desconocida';
      bool wasPending = false;

      if (_pendingFile.existsSync()) {
        try {
          final data =
              jsonDecode(_pendingFile.readAsStringSync()) as Map<String, dynamic>;
          component = data['component']?.toString() ?? 'frontend';
          version = data['version']?.toString() ?? 'desconocida';
          wasPending = true;
        } catch (_) {}
      }

      String logContent = '';
      if (_logFile.existsSync()) {
        try {
          final lines = _logFile.readAsStringSync().split('\n');
          final tail =
              lines.length > 40 ? lines.sublist(lines.length - 40) : lines;
          logContent = tail.join('\n').trim();
        } catch (_) {}
      }

      return OtaStartupResult(
        success: success,
        component: component,
        version: version,
        logContent: logContent,
        wasPending: wasPending,
      );
    } catch (_) {
      return null;
    }
  }

  /// Limpia los archivos de estado OTA tras mostrar el resultado al usuario.
  /// El updater_log.txt NO se elimina — queda para soporte técnico.
  static void clearState() {
    for (final file in [_resultFile, _pendingFile]) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  /// Path absoluto del log para que el soporte técnico lo encuentre fácilmente.
  static String get logPath => _logFile.path;
}
