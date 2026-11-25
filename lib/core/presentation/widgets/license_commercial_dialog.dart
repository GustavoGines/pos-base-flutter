import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../features/settings/presentation/providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/snack_bar_service.dart';
import 'app_modal_shell.dart';

/// Badge sutil en la barra superior que informa los días restantes de Demo
/// (y aviso preventivo en SaaS pago cuando faltan <= 5 días).
class LicenseExpiryBadgeWidget extends StatelessWidget {
  const LicenseExpiryBadgeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    SettingsProvider? settingsProv;
    try {
      settingsProv = context.watch<SettingsProvider?>();
    } catch (_) {}

    if (settingsProv == null) {
      return const SizedBox.shrink();
    }

    bool isActive = false;
    try {
      isActive = settingsProv.isLicenseActive;
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (!isActive) {
      return const SizedBox.shrink();
    }

    final settings = () {
      try {
        return settingsProv!.settings;
      } catch (_) {
        return null;
      }
    }();
    if (settings == null || settings.isLifetime) {
      return const SizedBox.shrink();
    }

    final remainingDays = settings.remainingLicenseDays;
    if (remainingDays == null) {
      return const SizedBox.shrink();
    }

    final bool isTrial = settings.isTrial;
    if (!isTrial && remainingDays > 5) {
      return const SizedBox.shrink();
    }

    final bool isUrgent = remainingDays <= 3;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 1180;

    final String label;
    if (isTrial) {
      if (remainingDays <= 0) {
        label = isCompact ? '⏳ Hoy' : '⏳ Prueba vence hoy';
      } else if (remainingDays == 1) {
        label = isCompact ? '⏳ 1d' : '⏳ Prueba · 1 día';
      } else {
        label = isCompact
            ? '${isUrgent ? '⏳' : '🎯'} ${remainingDays}d'
            : '${isUrgent ? '⏳' : '🎯'} Prueba · $remainingDays días';
      }
    } else {
      if (remainingDays <= 0) {
        label = isCompact ? '📅 Hoy' : '📅 Abono vence hoy';
      } else {
        label = isCompact ? '📅 ${remainingDays}d' : '📅 Vence en ${remainingDays}d';
      }
    }

    final Color baseColor =
        isUrgent ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    final Color textColor =
        isUrgent ? const Color(0xFFFEF3C7) : const Color(0xFFD1FAE5);

    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: Tooltip(
        excludeFromSemantics: true,
        message: isTrial
            ? 'Estás en período de prueba gratuita. Tocá para activar tu plan sin perder datos.'
            : 'Tu suscripción SaaS vence pronto. Tocá para ver opciones de renovación.',
        child: InkWell(
          key: const Key('license_expiry_badge'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => LicenseCommercialDialog.show(context),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: 0.16),
              border: Border.all(color: baseColor.withValues(alpha: 0.50)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal comercial limpio para convertir una Demo activa a plan pago
/// o recordar la renovación preventiva en SaaS.
class LicenseCommercialDialog extends StatefulWidget {
  const LicenseCommercialDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const LicenseCommercialDialog(),
    );
  }

  @override
  State<LicenseCommercialDialog> createState() =>
      _LicenseCommercialDialogState();
}

class _LicenseCommercialDialogState extends State<LicenseCommercialDialog> {
  static const String _whatsappNumber = '5493704367202';
  static const String _whatsappDisplay = '+54 9 3704 36-7202';

  bool _isSyncing = false;
  String? _inlineFeedback;
  bool _feedbackIsError = false;

  String _formatLocalExpiry(DateTime? dt) {
    if (dt == null) return 'Sin fecha definida';
    final local = dt.toLocal();
    try {
      return '${DateFormat('dd/MM/yyyy', 'es_AR').format(local)} · 23:59 hs';
    } catch (_) {
      return '${DateFormat('dd/MM/yyyy').format(local)} · 23:59 hs';
    }
  }

  Future<void> _openWhatsApp({
    required bool isTrial,
    required String? companyName,
    required String? planName,
  }) async {
    final commerce = (companyName != null && companyName.trim().isNotEmpty)
        ? ' para "${companyName.trim()}"'
        : '';
    final planTag = (planName ?? '').toLowerCase().contains('pro') ||
            (planName ?? '').toLowerCase().contains('premium')
        ? 'Premium'
        : 'Básico';

    final msg = isTrial
        ? 'Hola! Estoy probando Caja4U$commerce (Plan $planTag) y quiero activar mi licencia definitiva (Mensual o Pago Único) conservando todos mis datos.'
        : 'Hola! Quiero renovar mi suscripción mensual de Caja4U$commerce (Plan $planTag).';

    final uri = Uri.parse(
      'https://wa.me/$_whatsappNumber?text=${Uri.encodeComponent(msg)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _isSyncing = true;
      _inlineFeedback = null;
      _feedbackIsError = false;
    });
    try {
      final provider = context.read<SettingsProvider>();
      final prefs = await SharedPreferences.getInstance();
      final activeUrl = prefs.getString('pos_api') ?? provider.currentApiUrl;
      await provider.syncLicenseWithServer(activeUrl);
      if (!mounted) return;

      final updated = provider.settings;
      if (updated != null && (!updated.isTrial || updated.isLifetime)) {
        Navigator.of(context).pop();
        SnackBarService.success(
          context,
          updated.isLifetime
              ? '¡Licencia Pago Único activada! Todos tus datos siguen intactos.'
              : '¡Plan confirmado! Tu licencia quedó activa.',
        );
        return;
      }

      setState(() {
        _inlineFeedback =
            'Estado sincronizado correctamente. Tu licencia sigue vigente hasta ${_formatLocalExpiry(updated?.localLicenseExpiresAt)}.';
        _feedbackIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineFeedback = e.toString().replaceAll('Exception: ', '');
        _feedbackIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProv = context.watch<SettingsProvider>();
    final settings = settingsProv.settings;
    final bool isTrial = settings?.isTrial ?? false;
    final int remaining = settings?.remainingLicenseDays ?? 0;
    final localExp = settings?.localLicenseExpiresAt;

    final String title = isTrial
        ? 'Tu Prueba Gratuita de Caja4U'
        : 'Renovación de Suscripción';
    final String subtitle = remaining <= 0
        ? 'Vence hoy a las 23:59 hs (${_formatLocalExpiry(localExp)})'
        : 'Quedan $remaining ${remaining == 1 ? 'día' : 'días'} · Vence el ${_formatLocalExpiry(localExp)}';

    return AppModalShell(
      title: title,
      subtitle: subtitle,
      icon: isTrial ? Icons.rocket_launch_rounded : Icons.event_available_rounded,
      accent: isTrial ? AppModalAccent.emerald : AppModalAccent.amber,
      compact: true,
      maxWidth: 520,
      onClose: () => Navigator.of(context).pop(),
      bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  color: Color(0xFF059669),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    settings?.demoModeActive == true
                        ? 'Tu configuración, usuarios e impresoras quedan 100% guardados al activar tu plan, y podrás limpiar los datos de ejemplo con 1 clic cuando quieras empezar en real.'
                        : 'Todos tus productos, precios, clientes, caja, ventas y configuración fiscal quedan 100% guardados en este equipo cuando actives tu plan.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (isTrial)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Elegí la modalidad que mejor se adapte a tu comercio:',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Plan Mensual SaaS: actualizaciones automáticas, soporte prioritario y bajo costo mensual.',
                    style: TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Licencia Pago Único (Lifetime): abonás una sola vez y el sistema es tuyo para siempre.',
                    style: TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                ],
              ),
            ),
          if (_inlineFeedback != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _feedbackIsError
                    ? Colors.red.shade50
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _feedbackIsError
                      ? Colors.red.shade200
                      : Colors.blue.shade200,
                ),
              ),
              child: Text(
                _inlineFeedback!,
                style: TextStyle(
                  fontSize: 12.2,
                  color: _feedbackIsError
                      ? Colors.red.shade800
                      : Colors.blue.shade900,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => _openWhatsApp(
                isTrial: isTrial,
                companyName: settings?.companyName,
                planName: settings?.licensePlanType,
              ),
              icon: const Icon(Icons.chat_rounded, size: 19),
              label: Text(
                isTrial
                    ? 'Activar mi licencia por WhatsApp'
                    : 'Renovar suscripción por WhatsApp',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'WhatsApp Comercial Dev4U: $_whatsappDisplay',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _isSyncing ? null : _syncNow,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(
                _isSyncing
                    ? 'Verificando...'
                    : 'Ya contraté / renové · Sincronizar ahora',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
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
