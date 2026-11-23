import 'package:flutter/material.dart';
import '../../../../core/presentation/widgets/app_modal_shell.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/update_info.dart';
import '../../data/services/mobile_update_service.dart';

/// Diálogo de actualización in-app para Android.
///
/// Muestra la versión disponible, el changelog y una barra de progreso
/// durante la descarga. Al finalizar, lanza el instalador del sistema.
class MobileUpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const MobileUpdateDialog({super.key, required this.updateInfo});

  @override
  State<MobileUpdateDialog> createState() => _MobileUpdateDialogState();
}

class _MobileUpdateDialogState extends State<MobileUpdateDialog> {
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  bool _downloadComplete = false;
  String? _errorMessage;

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    try {
      await MobileUpdateService.downloadAndInstall(
        widget.updateInfo.downloadUrl,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      if (mounted) setState(() => _downloadComplete = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCritical = widget.updateInfo.isCritical;

    return PopScope(
      // Si es crítica, no se puede cerrar con el botón atrás
      canPop: !isCritical && !_isDownloading,
      child: AppModalShell(
        title: isCritical
            ? 'Actualización Crítica'
            : 'Nueva Versión Disponible',
        subtitle: 'Versión v${widget.updateInfo.version}',
        icon: Icons.system_update_outlined,
        accent: isCritical ? AppModalAccent.red : AppModalAccent.blue,
        showCloseButton: !isCritical && !_isDownloading,
        compact: true,
        maxWidth: 400,
        bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Novedades:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(
                  widget.updateInfo.changelog,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ),

            // ── Progreso de descarga ────────────────────────────
            if (_isDownloading) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: _downloadProgress < 1.0 ? _downloadProgress : null,
                backgroundColor: AppColors.surfaceAlt,
                color: AppColors.primary,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _downloadComplete
                      ? 'Descarga completa — abrí el instalador'
                      : 'Descargando... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            // ── Error ───────────────────────────────────────────
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade800,
                  ),
                ),
              ),
            ],
          ],
        ),
        footerActions: [
          if (!isCritical && !_isDownloading)
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Más tarde'),
            ),
          FilledButton.icon(
            onPressed: _isDownloading ? null : _startUpdate,
            style: FilledButton.styleFrom(
              backgroundColor: isCritical ? AppColors.danger : AppColors.primary,
            ),
            icon: _isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(
              _isDownloading ? 'Descargando...' : 'Actualizar ahora',
            ),
          ),
        ],
      ),
    );
  }
}
