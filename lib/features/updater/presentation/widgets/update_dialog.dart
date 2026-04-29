import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/update_info.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final bool isFullSystemUpdate;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    this.isFullSystemUpdate = false,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  bool _isComplete = false;
  double _progress = 0.0;
  String _status = 'Listo para actualizar';

  bool get _isFrontend => widget.updateInfo.component == 'frontend';
  bool get _isFull => widget.isFullSystemUpdate;

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _status = 'Descargando actualización...';
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
      ));

      // ─────────────────────────────────────────────────────────────────
      // CRÍTICO: Guardar el ZIP en el DIRECTORIO DE INSTALACIÓN (no en
      // %TEMP%). Esto garantiza que:
      //   1. El archivo sobreviva si el proceso padre (la app) muere.
      //   2. Si el updater falla a mitad, el ZIP sigue disponible para
      //      un reintento sin re-descargar.
      //   3. No hay problemas de permisos de escritura entre particiones.
      // ─────────────────────────────────────────────────────────────────
      final installPath = File(Platform.resolvedExecutable).parent.path;
      final zipName = _isFrontend
          ? 'update_v${widget.updateInfo.version}.zip'
          : 'update_backend_v${widget.updateInfo.version}.zip';
      final zipPath = p.join(installPath, zipName);

      debugPrint('[UpdateDialog] Guardando ZIP en: $zipPath');

      await dio.download(
        widget.updateInfo.downloadUrl,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() {
              _progress = received / total;
              final mb = (received / 1024 / 1024).toStringAsFixed(1);
              final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
              _status = 'Descargando... $mb / $totalMb MB';
            });
          }
        },
      );

      if (mounted) {
        setState(() => _status = 'Preparando actualización...');
      }

      final updaterPath = p.join(installPath, 'updater.exe');

      // Obtener ruta del backend
      final prefs = await SharedPreferences.getInstance();
      String? resolvedBackendPath;

      final configuredBackendPath = prefs.getString('backend_install_path');
      if (configuredBackendPath != null && configuredBackendPath.isNotEmpty) {
        resolvedBackendPath = configuredBackendPath;
        debugPrint('[UpdateDialog] Ruta backend (manual): $resolvedBackendPath');
      } else {
        final relPath = p.join(
          File(Platform.resolvedExecutable).parent.parent.path,
          'pos-backend',
        );
        if (Directory(relPath).existsSync()) {
          resolvedBackendPath = relPath;
          debugPrint('[UpdateDialog] Ruta backend (auto-detectada): $resolvedBackendPath');
        }
      }

      if (!_isFrontend && resolvedBackendPath == null) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _status =
                '❌ Ruta del backend no configurada.\n\nAndá a Ajustes → Red y Terminales → "Ruta del Backend" y escribí la ruta de instalación del servidor.\nEjemplo: C:\\laragon\\www\\Sistema_POS\\pos-backend';
          });
        }
        return;
      }

      final targetDir = _isFrontend ? installPath : resolvedBackendPath!;
      final componentArg = _isFrontend ? 'frontend' : 'backend';

      debugPrint('[UpdateDialog] targetDir para $componentArg: $targetDir');

      // Modo debug/desarrollo: no hay updater.exe → simular OK
      if (!File(updaterPath).existsSync()) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _status = '✅ ¡Test Exitoso! (Updater ignorado en modo Debug)';
          });
        }
        return;
      }

      // ─────────────────────────────────────────────────────────────────
      // GUARDAR ESTADO PENDIENTE antes de lanzar el updater.
      // Si la app se cierra y el updater falla, al abrir de nuevo sabremos
      // exactamente qué versión se estaba intentando instalar y mostraremos
      // el log de error al usuario.
      // ─────────────────────────────────────────────────────────────────
      await _writePendingState(
        installPath: installPath,
        component: componentArg,
        version: widget.updateInfo.version,
        zipPath: zipPath,
        targetDir: targetDir,
      );

      // Limpiar resultado anterior para que el startup-check no muestre el
      // resultado viejo mientras el updater está trabajando.
      try {
        final oldResult = File(p.join(targetDir, 'ota_result.txt'));
        if (oldResult.existsSync()) oldResult.deleteSync();
      } catch (_) {}

      // ─────────────────────────────────────────────────────────────────
      // LANZAR UPDATER — Técnica de desacoplamiento total del proceso padre.
      //
      // PROBLEMA ANTERIOR: Process.start() crea PowerShell como hijo de
      // Flutter. En Windows 11, cuando Flutter hace exit(0), Windows mata
      // todos los procesos del Job Object (incluidos los hijos). Esto
      // causaba que el updater se cerrara junto con la app antes de hacer
      // nada.
      //
      // SOLUCIÓN: Escribimos un .bat con los comandos y lo lanzamos con
      // ProcessStartMode.detached. Dart marca el proceso con
      // CREATE_NO_WINDOW | DETACHED_PROCESS: el proceso BAT/CMD queda
      // completamente fuera del árbol de procesos de Flutter y sobrevive
      // al exit(0).
      //
      // Flujo resultante:
      //   Flutter → cmd /c launcher.bat (DETACHED) → powershell Start-Process
      //             -Verb RunAs → updater.exe (elevado, independiente)
      // ─────────────────────────────────────────────────────────────────
      await _launchUpdaterDetached(
        updaterPath: updaterPath,
        componentArg: componentArg,
        targetDir: targetDir,
        zipPath: zipPath,
        installPath: installPath,
      );

      if (_isFrontend) {
        // Mostrar countdown para que el usuario tenga tiempo de aceptar el UAC
        for (int i = 5; i >= 1; i--) {
          if (mounted) {
            setState(() {
              _status = _isFull
                  ? '⚠️ Aceptá el permiso de Administrador.\nAl reiniciar, el Servidor se actualizará automáticamente.\nCerrando en $i segundo${i != 1 ? 's' : ''}...'
                  : '⚠️ Aceptá el permiso de Administrador que aparecerá.\nCerrando en $i segundo${i != 1 ? 's' : ''}...';
            });
          }
          await Future.delayed(const Duration(seconds: 1));
        }
        // Salir — el updater ya está completamente desacoplado
        exit(0);
      } else {
        // Backend: esperar el archivo de resultado del updater (hasta 120s)
        if (mounted) {
          setState(() => _status = '⏳ Aplicando migraciones en segundo plano...');
        }

        final resultFile = File(p.join(targetDir, 'ota_result.txt'));

        bool resultFound = false;
        for (int i = 0; i < 120; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          if (resultFile.existsSync()) {
            resultFound = true;
            break;
          }
          // Actualizar status cada 10s para que el usuario sepa que sigue vivo
          if (i > 0 && i % 10 == 0) {
            if (mounted) {
              setState(() => _status = '⏳ Aplicando migraciones... (${i}s)');
            }
          }
        }

        String finalStatus;
        bool success = false;
        if (!resultFound) {
          finalStatus =
              '⚠️ Tiempo de espera agotado. Revisá el archivo updater_log.txt en la carpeta del servidor para ver el detalle.';
        } else {
          final resultRaw = resultFile.readAsStringSync().trim();
          if (resultRaw.startsWith('{')) {
            try {
              final data = json.decode(resultRaw);
              success = data['status'] == 'SUCCESS';
            } catch (_) {
              success = false;
            }
          } else {
            success = resultRaw == 'SUCCESS';
          }
          
          finalStatus = success
              ? '✅ Servidor actualizado exitosamente.'
              : '❌ Error durante la actualización.\nRevisá updater_log.txt en la carpeta del servidor para más detalles.';
        }

        if (success) {
          await prefs.setString('backend_version', widget.updateInfo.version);
          // Limpiar estado pendiente
          await _clearPendingState(installPath);
        }

        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isComplete = success;
            _progress = 1.0;
            _status = finalStatus;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _status = 'Error: $e';
        });
      }
    }
  }

  /// Escribe un launcher.bat en el dir de instalación y lo lanza con
  /// ProcessStartMode.detached para que el proceso sea completamente
  /// independiente de la app Flutter (sobrevive al exit(0)).
  Future<void> _launchUpdaterDetached({
    required String updaterPath,
    required String componentArg,
    required String targetDir,
    required String zipPath,
    required String installPath,
  }) async {
    // Escapar comillas simples en rutas para el argumento de PowerShell
    String psEscape(String s) => s.replaceAll("'", "''");

    final argList =
        "--component=$componentArg --target-dir='${psEscape(targetDir)}' --zip-path='${psEscape(zipPath)}'";

    // El batch simplemente llama a PowerShell que eleva el updater con UAC.
    // -ExecutionPolicy Bypass evita problemas con políticas restrictivas en W11.
    final batContent = '@echo off\r\n'
        'powershell -ExecutionPolicy Bypass -Command "'
        'Start-Process -FilePath \'${psEscape(updaterPath)}\' '
        '-ArgumentList \'$argList\' '
        '-Verb RunAs'
        '"\r\n';

    final batPath = p.join(installPath, '_ota_launcher.bat');
    try {
      File(batPath).writeAsStringSync(batContent);
      debugPrint('[UpdateDialog] Launcher BAT escrito en: $batPath');
    } catch (e) {
      debugPrint('[UpdateDialog] Error escribiendo BAT: $e');
      rethrow;
    }

    // ProcessStartMode.detached: equivale a CREATE_NO_WINDOW | DETACHED_PROCESS.
    // El proceso CMD queda fuera del Job Object de Flutter → sobrevive al exit(0).
    await Process.start(
      'cmd',
      ['/c', batPath],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    debugPrint('[UpdateDialog] Launcher lanzado en modo DETACHED.');
  }

  /// Persiste info del update pendiente en disco para diagnóstico post-crash.
  Future<void> _writePendingState({
    required String installPath,
    required String component,
    required String version,
    required String zipPath,
    required String targetDir,
  }) async {
    try {
      final pendingFile = File(p.join(installPath, 'ota_pending.json'));
      pendingFile.writeAsStringSync(jsonEncode({
        'component': component,
        'version': version,
        'zip_path': zipPath,
        'target_dir': targetDir,
        'started_at': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  /// Elimina el archivo de estado pendiente tras un resultado exitoso.
  Future<void> _clearPendingState(String installPath) async {
    try {
      final f = File(p.join(installPath, 'ota_pending.json'));
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final Color componentColor = _isFull
        ? const Color(0xFF1E3A8A)
        : _isFrontend
            ? const Color(0xFF673AB7)
            : const Color(0xFF0D9488);
    final IconData componentIcon = _isFull
        ? Icons.auto_mode_rounded
        : _isFrontend
            ? Icons.monitor
            : Icons.dns_rounded;
    final String componentLabel = _isFull
        ? 'Actualización Integral del Sistema'
        : _isFrontend
            ? 'App (Frontend)'
            : 'Servidor (Backend)';
    final String componentDescription = _isFull
        ? 'Esta actualización sincronizada actualizará tanto la App como el Servidor. Se descargará la App primero y, tras reiniciarse, se completará la actualización del Servidor automáticamente.'
        : _isFrontend
            ? 'Esta actualización reemplaza la aplicación y requiere reinicio.'
            : 'Esta actualización se aplica en segundo plano al servidor local.';

    return PopScope(
      canPop: widget.updateInfo.isCritical ? false : !_isDownloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: componentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: componentColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(componentIcon, size: 14, color: componentColor),
                  const SizedBox(width: 6),
                  Text(
                    componentLabel,
                    style: TextStyle(
                        fontSize: 12,
                        color: componentColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                    _isFull
                        ? Icons.system_update_rounded
                        : Icons.system_update_alt,
                    color: componentColor),
                const SizedBox(width: 10),
                Text(_isFull ? 'Actualización del Sistema' : 'Actualización Disponible',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versión ${widget.updateInfo.version}',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: componentColor),
            ),
            const SizedBox(height: 6),
            Text(
              componentDescription,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            const Text('Novedades:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, _) {
                final maxH = MediaQuery.of(context).size.height * 0.4;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: SingleChildScrollView(
                    child: Text(widget.updateInfo.changelog),
                  ),
                );
              },
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 24),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.grey.shade200,
                color: componentColor,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _status,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ] else if (_status != 'Listo para actualizar') ...[
              const SizedBox(height: 16),
              Text(
                _status,
                style: TextStyle(
                  color: _status.startsWith('Error') ||
                          _status.startsWith('❌')
                      ? Colors.red
                      : _status.startsWith('⚠️')
                          ? Colors.orange.shade700
                          : Colors.green.shade700,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!_isDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(_isComplete),
              child: Text(
                _isComplete ? 'FINALIZAR' : 'Cerrar',
                style: TextStyle(
                  color: _isComplete
                      ? componentColor
                      : Colors.grey.shade600,
                  fontWeight:
                      _isComplete ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          if (!_isDownloading && !_isComplete)
            ElevatedButton(
              onPressed: _startUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: componentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(_isFull ? 'ACTUALIZAR SISTEMA' : 'ACTUALIZAR AHORA'),
            ),
        ],
      ),
    );
  }
}
