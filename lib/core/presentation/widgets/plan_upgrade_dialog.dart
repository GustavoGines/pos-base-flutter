import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Diálogo premium de upselling reutilizable.
/// Se muestra cuando el usuario intenta usar una función que requiere un plan superior.
///
/// Uso rápido:
/// ```dart
/// PlanUpgradeDialog.show(context,
///   featureName: 'Multi-Caja',
///   description: 'Tu descripción aquí.',
///   onNavigateToSettings: () => Navigator.pushNamed(context, '/settings'),
/// );
/// ```
class PlanUpgradeDialog extends StatelessWidget {
  final String featureName;
  final String description;
  final VoidCallback? onNavigateToSettings;

  const PlanUpgradeDialog({
    Key? key,
    required this.featureName,
    required this.description,
    this.onNavigateToSettings,
  }) : super(key: key);

  // ───── Contacto de soporte ─────────────────────────────────────────────────
  static const _whatsappNumber = '543704787285'; // +54 370 478-7285 (Argentina)
  static const _whatsappPrefilledMsg =
      '¡Hola! Necesito ampliar mi licencia del Sistema POS. '
      'Quiero acceder a más funciones de mi plan actual.';

  // ───── API estática para mostrar el diálogo ────────────────────────────────
  static Future<void> show(
    BuildContext context, {
    required String featureName,
    required String description,
    VoidCallback? onNavigateToSettings,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PlanUpgradeDialog(
        featureName: featureName,
        description: description,
        onNavigateToSettings: onNavigateToSettings != null
            ? () {
                Navigator.of(ctx).pop();
                onNavigateToSettings();
              }
            : null,
      ),
    );
  }

  // ───── Lanzar WhatsApp ─────────────────────────────────────────────────────
  Future<void> _openWhatsApp() async {
    final encoded = Uri.encodeComponent(_whatsappPrefilledMsg);
    final uri = Uri.parse('https://wa.me/$_whatsappNumber?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Ícono con gradiente ──
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B1FA2), Color(0xFF512DA8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF673AB7).withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: 28),

              // ── Título ──
              const Text(
                'Plan Premium Requerido',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),

              // ── Función bloqueada ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E5F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: Color(0xFF7B1FA2)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        featureName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4A148C),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Descripción ──
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),

              // ── Botón WhatsApp ──
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _openWhatsApp,
                  icon: const Icon(Icons.chat_rounded, size: 20),
                  label: const Text(
                    'Contactar Soporte por WhatsApp',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Botón "Ver planes" (opcional) ──
              if (onNavigateToSettings != null)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: onNavigateToSettings,
                    icon: const Icon(Icons.verified_user_outlined, size: 20),
                    label: const Text(
                      'Ver Planes y Precios',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF512DA8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),

              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cerrar',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
