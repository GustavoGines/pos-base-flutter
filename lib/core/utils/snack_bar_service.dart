import 'package:flutter/material.dart';

/// Servicio global de notificaciones visuales tipo Snackbar.
///
/// Provee mensajes semánticos consistentes en toda la app:
/// - [success] → verde (operación completada)
/// - [error]   → rojo (falla o excepción)
/// - [info]    → azul (información neutral)
/// - [warning] → naranja (advertencia no crítica)
///
/// Uso desde cualquier widget:
/// ```dart
/// SnackBarService.success(context, '¡Venta registrada!');
/// SnackBarService.error(context, 'Error de conexión con el servidor.');
/// ```
class SnackBarService {
  SnackBarService._();

  // ─── Constructores Semánticos ──────────────────────────────────────────

  static void success(BuildContext context, String message, {Duration? duration}) {
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFF2E7D32),  // Green 800
      icon: Icons.check_circle_outline_rounded,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  static void error(BuildContext context, String message, {Duration? duration}) {
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFFC62828),  // Red 800
      icon: Icons.error_outline_rounded,
      duration: duration ?? const Duration(seconds: 5),
    );
  }

  static void info(BuildContext context, String message, {Duration? duration}) {
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFF1565C0),  // Blue 800
      icon: Icons.info_outline_rounded,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  static void warning(BuildContext context, String message, {Duration? duration}) {
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFFE65100),  // Deep Orange 900
      icon: Icons.warning_amber_rounded,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  // ─── Implementación Interna ──────────────────────────────────────────────

  static void _show(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    required IconData icon,
    required Duration duration,
  }) {
    // Descartar cualquier Snackbar previo para evitar acumulación
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: '✕',
          textColor: Colors.white70,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }
}
