import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/presentation/widgets/app_modal_shell.dart';
import '../../data/services/ota_startup_checker.dart';

/// Diálogo que se muestra al arrancar la app si el updater dejó un resultado.
/// Muestra:
///   - ✅ Success con la versión instalada
///   - ❌ Error con el log completo para diagnóstico
class OtaResultDialog extends StatelessWidget {
  final OtaStartupResult result;

  const OtaResultDialog({super.key, required this.result});

  /// Muestra el diálogo y luego limpia los archivos de estado.
  /// Llama esto desde la pantalla principal después del primer frame.
  /// Retorna el [OtaStartupResult] si se mostró algo, para encadenamiento lógico.
  static Future<OtaStartupResult?> showIfNeeded(BuildContext context) async {
    final result = OtaStartupChecker.check();
    if (result == null) return null;

    // Limpiar inmediatamente para que no aparezca de nuevo si el usuario
    // cierra y re-abre la app.
    OtaStartupChecker.clearState();

    if (!context.mounted) return result;

    await showDialog(
      context: context,
      barrierDismissible: result.success,
      builder: (_) => OtaResultDialog(result: result),
    );

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = result.success;
    final isFrontend = result.component == 'frontend';
    final Color accentColor =
        isSuccess ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final Color bgColor =
        isSuccess ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final IconData icon =
        isSuccess ? Icons.check_circle_rounded : Icons.error_rounded;
    final String title = isSuccess
        ? '¡Actualización Exitosa!'
        : 'Error en la Actualización';
    final String componentLabel =
        isFrontend ? 'App (Frontend)' : 'Servidor (Backend)';

    return AppModalShell(
      title: title,
      subtitle: '$componentLabel — v${result.version}',
      icon: icon,
      accent: isSuccess ? AppModalAccent.emerald : AppModalAccent.red,
      showCloseButton: isSuccess,
      compact: isSuccess,
      maxWidth: isSuccess ? 480 : 640,
      onClose: () => Navigator.of(context).pop(),
      bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSuccess)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.rocket_launch_rounded,
                    color: accentColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'La versión ${result.version} se instaló correctamente mientras '
                      'la aplicación estuvo cerrada.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // ── Log de error ────────────────────────────────────────
            const Text(
              'Detalle del error (log del actualizador):',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                children: [
                  // Toolbar del log
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.terminal,
                          size: 13,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'updater_log.txt',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const Spacer(),
                        // Botón copiar log
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: result.logContent),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Log copiado al portapapeles'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.copy,
                                  size: 13,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Copiar',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Contenido del log
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(10),
                        child: SelectableText(
                          result.logContent.isEmpty
                              ? '(log vacío — el updater no generó salida)'
                              : result.logContent,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFE2E8F0),
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Path del log en disco
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 13,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    OtaStartupChecker.logPath,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Botón abrir carpeta
                InkWell(
                  onTap: () {
                    try {
                      Process.run('explorer', [
                        '/select,',
                        OtaStartupChecker.logPath,
                      ]);
                    } catch (_) {}
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      'Abrir carpeta',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      footerActions: [
        if (!isSuccess)
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cerrar'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
            ),
          ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            isSuccess ? Icons.thumb_up_rounded : Icons.refresh,
            size: 16,
          ),
          label: Text(isSuccess ? 'Perfecto' : 'Entendido'),
          style: FilledButton.styleFrom(
            backgroundColor: accentColor,
          ),
        ),
      ],
    );
  }
}
