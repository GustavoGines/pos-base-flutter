import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import 'app_modal_shell.dart';

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
  final String title;
  final String featureName;
  final String description;
  final VoidCallback? onNavigateToSettings;

  const PlanUpgradeDialog({
    super.key,
    this.title = 'Plan Premium Requerido',
    required this.featureName,
    required this.description,
    this.onNavigateToSettings,
  });

  // ───── Contacto de soporte ─────────────────────────────────────────────────
  static const _whatsappNumber = '5493704367202'; // +54 9 3704 36-7202 (Argentina)
  static const _whatsappDisplay = '+54 9 3704 36-7202';
  static const _whatsappPrefilledMsg =
      '¡Hola! Necesito ampliar mi licencia de Caja4U. '
      'Quiero acceder a más funciones de mi plan actual.';

  // ───── API estática para mostrar el diálogo ────────────────────────────────
  static Future<void> show(
    BuildContext context, {
    String title = 'Plan Premium Requerido',
    required String featureName,
    required String description,
    VoidCallback? onNavigateToSettings,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PlanUpgradeDialog(
        title: title,
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
    return AppModalShell(
      title: title,
      subtitle: 'Desbloqueá esta herramienta mejorando tu licencia',
      icon: Icons.workspace_premium_rounded,
      accent: AppModalAccent.amber,
      compact: true,
      maxWidth: 440,
      bodyPadding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Función bloqueada ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    featureName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
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
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // ── Botón WhatsApp ──
          SizedBox(
            width: double.infinity,
            height: 50,
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
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'WhatsApp Soporte: $_whatsappDisplay',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),

          // ── Botón "Ver planes" (opcional) ──
          if (onNavigateToSettings != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: onNavigateToSettings,
                icon: const Icon(Icons.verified_user_outlined, size: 20),
                label: const Text(
                  'Ver Planes y Precios',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
