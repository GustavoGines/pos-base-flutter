import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/update_info.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  bool _isComplete = false;
  double _progress = 0.0;
  String _status = 'Listo para actualizar';

  bool get _isFrontend => widget.updateInfo.component == 'frontend';

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _status = 'Descargando actualización...';
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 5),
      ));
      final tempDir = await getTemporaryDirectory();
      final zipName = _isFrontend ? 'update_v${widget.updateInfo.version}.zip' : 'update_backend_v${widget.updateInfo.version}.zip';
      final zipPath = p.join(tempDir.path, zipName);

      await dio.download(
        widget.updateInfo.downloadUrl,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      setState(() {
        _status = 'Aplicando actualización...';
      });

      // Calcular ruta de instalación (donde está el .exe de esta aplicación)
      final installPath = File(Platform.resolvedExecutable).parent.path;
      final updaterPath = p.join(installPath, 'updater.exe');

      final prefs = await SharedPreferences.getInstance();

      // ── DETECCIÓN DE RUTA DEL BACKEND (3 niveles, sin ningún hardcode) ──────
      //
      // Nivel 1: Ruta configurada manualmente por el técnico en Ajustes → Red.
      // Nivel 2: Detección automática relativa al exe. Asume que el exe está
      //          en <raíz>/pos-frontend/ y el backend en <raíz>/pos-backend/.
      //          Si ese directorio existe físicamente en disco, lo usamos.
      // Nivel 3: No se pudo detectar → informamos al usuario y abortamos.
      //          El técnico debe configurarlo en Ajustes → Red y Terminales.
      String? resolvedBackendPath;

      final configuredBackendPath = prefs.getString('backend_install_path');
      if (configuredBackendPath != null && configuredBackendPath.isNotEmpty) {
        // ✅ Nivel 1: configurado manualmente
        resolvedBackendPath = configuredBackendPath;
        debugPrint('[UpdateDialog] Ruta backend (manual): $resolvedBackendPath');
      } else {
        // ✅ Nivel 2: auto-detección relativa al ejecutable
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
        // ❌ Nivel 3: no se pudo determinar la ruta → abortar con mensaje claro
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _status = '❌ Ruta del backend no configurada.\n\nAndá a Ajustes → Red y Terminales → "Ruta del Backend" y escribí la ruta de instalación del servidor. Ejemplo: C:\\laragon\\www\\Sistema_POS\\pos-backend';
          });
        }
        return;
      }

      final targetDir = _isFrontend ? installPath : resolvedBackendPath!;
      final componentArg = _isFrontend ? 'frontend' : 'backend';

      debugPrint('[UpdateDialog] targetDir para $componentArg: $targetDir');

      // Validar si el updater existe (en desarrollo o 'flutter run' no existe)

      if (!File(updaterPath).existsSync()) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _status = '✅ ¡Test Exitoso! (Updater ignorado en modo Debug)';
          });
        }
        return;
      }

      // Invocar al Updater.exe pidiendo permisos de administrador a Windows mediante PowerShell
      // Invocar al Updater.exe pidiendo permisos de administrador a Windows mediante PowerShell
      final argList = '--component=$componentArg --target-dir="$targetDir" --zip-path="$zipPath"';
      final processArgs = [
        'Start-Process',
        '-FilePath', '"$updaterPath"',
        '-ArgumentList', '\'$argList\'',
        '-Verb', 'RunAs'
      ];
      
      if (!_isFrontend) {
        // Se removió el -Wait porque causaba bloqueos (hangs) en PowerShell
        // cuando updater.exe invocaba a php artisan migrate.
      }

      // Usamos Process.start (fire & forget) en lugar de Process.run.
      // Process.run bloquea esperando que PowerShell+UAC termine, lo que
      // congela el diálogo indefinidamente. Start-Process lanza el proceso
      // elevado y PowerShell retorna de inmediato.
      await Process.start('powershell', processArgs);

      if (_isFrontend) {
        // En frontend, nos salimos para dejar que reemplace los archivos en uso
        exit(0);
      } else {
        // En backend: el actualizador corre en segundo plano.
        // Esperamos el archivo ota_result.txt que el updater escribe al terminar.
        // Timeout de 90 segundos (extraccion + migrate puede tardar).
        if (mounted) {
          setState(() {
            _status = '⏳ Aplicando migraciones en segundo plano...';
          });
        }

        final resultFile = File(p.join(targetDir, 'ota_result.txt'));
        // Limpiar resultado anterior si existe
        if (resultFile.existsSync()) resultFile.deleteSync();

        bool resultFound = false;
        for (int i = 0; i < 90; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (resultFile.existsSync()) {
            resultFound = true;
            break;
          }
        }

        String finalStatus;
        bool success = false;
        if (!resultFound) {
          finalStatus = '⚠️ Tiempo de espera agotado. Verificá la ventana negra del actualizador.';
        } else {
          final result = resultFile.readAsStringSync().trim();
          success = result == 'SUCCESS';
          finalStatus = success
              ? '✅ Servidor actualizado exitosamente.'
              : '❌ Error durante la actualización. Revisá la ventana del actualizador para más detalles.';
        }

        if (success) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('backend_version', widget.updateInfo.version);
        }

        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isComplete = true;
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

  @override
  Widget build(BuildContext context) {
    // Configuración visual por componente
    final Color componentColor = _isFrontend ? const Color(0xFF673AB7) : const Color(0xFF0D9488);
    final IconData componentIcon = _isFrontend ? Icons.monitor : Icons.dns_rounded;
    final String componentLabel = _isFrontend ? 'App (Frontend)' : 'Servidor (Backend)';
    final String componentDescription = _isFrontend
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
            // Badge del componente
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
                    style: TextStyle(fontSize: 12, color: componentColor, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Título principal
            Row(
              children: [
                Icon(Icons.system_update_alt, color: componentColor),
                const SizedBox(width: 10),
                const Text('Actualización Disponible', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: componentColor),
            ),
            const SizedBox(height: 6),
            Text(
              componentDescription,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            const Text('Novedades:', style: TextStyle(fontWeight: FontWeight.w600)),
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
                value: _progress,
                backgroundColor: Colors.grey.shade200,
                color: componentColor,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _status,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ] else if (_status != 'Listo para actualizar') ...[
              const SizedBox(height: 16),
              Text(
                _status,
                style: TextStyle(
                  color: _status.startsWith('Error') || _status.startsWith('❌')
                      ? Colors.red
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
              child: Text(_isComplete ? 'FINALIZAR' : 'Cerrar', style: TextStyle(color: _isComplete ? componentColor : Colors.grey.shade600, fontWeight: _isComplete ? FontWeight.bold : FontWeight.normal)),
            ),
          if (!_isDownloading && !_isComplete)
            ElevatedButton(
              onPressed: _startUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: componentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('ACTUALIZAR AHORA'),
            ),
        ],
      ),
    );
  }
}
