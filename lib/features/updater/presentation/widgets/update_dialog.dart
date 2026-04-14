import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../data/models/update_info.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({Key? key, required this.updateInfo}) : super(key: key);

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _status = 'Listo para actualizar';

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _status = 'Descargando actualización...';
    });

    try {
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final zipPath = p.join(tempDir.path, 'update_v${widget.updateInfo.version}.zip');

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

      // Validar si el updater existe (en desarrollo o 'flutter run' no existe)
      if (!File(updaterPath).existsSync()) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _status = '✅ ¡Test Exitoso! (ZIP descargado de R2.\nActualizador ignorado en modo Debug para proteger tu entorno local)';
          });
        }
        return;
      }

      // Invocar al Updater.exe pidiendo permisos de administrador a Windows mediante PowerShell
      await Process.run(
        'powershell',
        [
          'Start-Process',
          '-FilePath', '"$updaterPath"',
          '-ArgumentList', '"$zipPath", "$installPath"',
          '-Verb', 'RunAs'
        ],
      );

      // Inmediatamente después, salir para liberar los archivos
      exit(0);
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
    return WillPopScope(
      onWillPop: () async => !widget.updateInfo.isCritical && !_isDownloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.system_update_alt, color: Color(0xFF673AB7)),
            const SizedBox(width: 12),
            const Text('Actualización Disponible', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versión ${widget.updateInfo.version}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
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
                color: const Color(0xFF673AB7),
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
            ] else if (_status.startsWith('Error')) ...[
              const SizedBox(height: 16),
              Text(_status, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        ),
        actions: [
          if (!widget.updateInfo.isCritical && !_isDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('MÁS TARDE', style: TextStyle(color: Colors.grey)),
            ),
          if (!_isDownloading)
            ElevatedButton(
              onPressed: _startUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF673AB7),
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
