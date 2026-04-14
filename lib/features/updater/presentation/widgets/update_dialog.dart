import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/update_info.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({Key? key, required this.updateInfo}) : super(key: key);

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
      final dio = Dio();
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
      
      final targetDir = _isFrontend ? installPath : p.join(installPath, 'pos-backend');
      final componentArg = _isFrontend ? 'frontend' : 'backend';

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
        processArgs.add('-Wait'); // Para backend, esperamos que termine silenciosamente
      }

      await Process.run('powershell', processArgs);

      if (_isFrontend) {
        // En frontend, nos salimos para dejar que reemplace los archivos en uso
        exit(0);
      } else {
        // En backend, actualizamos las preferencias para no volver a pedirlo
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('backend_version', widget.updateInfo.version);
        
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isComplete = true; // Flag for UI
            _progress = 1.0;
            _status = '✅ Servidor actualizado exitosamente.';
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

    return WillPopScope(
      onWillPop: () async => !widget.updateInfo.isCritical && !_isDownloading,
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
                color: componentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: componentColor.withOpacity(0.4)),
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
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(widget.updateInfo.changelog),
              ),
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
            ] else if (_status.startsWith('Error') || _status.startsWith('✅')) ...[
              const SizedBox(height: 16),
              Text(
                _status,
                style: TextStyle(
                  color: _status.startsWith('Error') ? Colors.red : Colors.green.shade700,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!_isDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
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
