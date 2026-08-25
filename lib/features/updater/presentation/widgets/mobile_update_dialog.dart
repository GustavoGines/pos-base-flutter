import 'package:flutter/material.dart';
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
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ─────────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E2D45), Color(0xFF2A4080)],
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.system_update_outlined,
                        color: Colors.white, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      isCritical
                          ? '🚨 Actualización Crítica'
                          : '🚀 Nueva Versión Disponible',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${widget.updateInfo.version}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14),
                    ),
                  ],
                ),
              ),

              // ── Changelog ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Novedades:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                        child: Text(
                          widget.updateInfo.changelog,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF444444)),
                        ),
                      ),
                    ),

                    // ── Progreso de descarga ────────────────────────────
                    if (_isDownloading) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                        value: _downloadProgress < 1.0
                            ? _downloadProgress
                            : null,
                        backgroundColor: Colors.grey.shade200,
                        color: const Color(0xFF1E2D45),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _downloadComplete
                            ? '✅ Descarga completa — abrí el instalador'
                            : 'Descargando... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
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
                              fontSize: 12, color: Colors.red.shade800),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Acciones ───────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    if (!isCritical && !_isDownloading)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Más tarde'),
                        ),
                      ),
                    if (!isCritical && !_isDownloading)
                      const SizedBox(width: 12),
                    Expanded(
                      flex: isCritical ? 1 : 1,
                      child: FilledButton.icon(
                        onPressed: _isDownloading ? null : _startUpdate,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E2D45),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.download_rounded),
                        label: Text(
                          _isDownloading ? 'Descargando...' : 'Actualizar ahora',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
