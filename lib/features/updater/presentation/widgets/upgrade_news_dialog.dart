import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/presentation/widgets/app_modal_shell.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/snack_bar_service.dart';
import '../../data/services/update_service.dart';
import 'update_dialog.dart';

/// Modal comercial sutil mostrado cuando existe una versión nueva pero la licencia
/// no tiene habilitada la actualización automática OTA (por ej. Pago Único / Lifetime).
class UpgradeNewsDialog extends StatefulWidget {
  final UpdateCheckResult checkResult;
  final String currentAppVersion;
  final bool showDismissVersionAction;

  const UpgradeNewsDialog({
    super.key,
    required this.checkResult,
    this.currentAppVersion = '',
    this.showDismissVersionAction = true,
  });

  @override
  State<UpgradeNewsDialog> createState() => _UpgradeNewsDialogState();
}

class _UpgradeNewsDialogState extends State<UpgradeNewsDialog> {
  static const String _whatsappNumber = '5493704367202';
  static const String _whatsappDisplay = '+54 9 3704 36-7202';

  bool _isCheckingPermission = false;
  String? _inlineFeedback;
  bool _feedbackIsError = false;

  String get _targetVersion => widget.checkResult.targetVersion ?? 'nueva';
  String get _currentVersion {
    final explicit = widget.currentAppVersion.trim();
    if (explicit.isNotEmpty) return explicit;
    final fromResult = widget.checkResult.currentFrontendVersion.trim();
    return fromResult.isNotEmpty ? fromResult : '2.2.0';
  }

  String get _changelog {
    final text = widget.checkResult.primaryUpdate?.changelog.trim() ?? '';
    return text.isNotEmpty
        ? text
        : 'Mejoras de rendimiento, estabilidad y nuevas funcionalidades.';
  }

  String? get _reason => widget.checkResult.otaBlockReason;
  bool get _isLifetimeUpgrade => _reason == 'lifetime_upgrade_required';
  bool get _isSubscriptionExpired => _reason == 'subscription_expired';
  bool get _isTrialExpired => _reason == 'trial_expired';

  Future<void> _openWhatsApp() async {
    final String msg;
    if (_isTrialExpired) {
      msg = 'Hola, estaba probando Caja4U v$_currentVersion y quiero '
          'activar mi licencia definitiva para actualizar a v$_targetVersion.';
    } else if (_isSubscriptionExpired) {
      msg = 'Hola, tengo Caja4U v$_currentVersion Plan Mensual y quiero '
          'renovar mi suscripción para actualizar a v$_targetVersion.';
    } else {
      msg = 'Hola, tengo Caja4U v$_currentVersion Pago Único y quiero consultar '
          'para actualizar a v$_targetVersion o pasarme a plan mensual';
    }
    final uri = Uri.parse(
      'https://wa.me/$_whatsappNumber?text=${Uri.encodeComponent(msg)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _recheckPermission() async {
    setState(() {
      _isCheckingPermission = true;
      _inlineFeedback = null;
      _feedbackIsError = false;
    });

    try {
      final fresh = await UpdateService().checkUpdate(
        throwErrors: true,
        allowInDebug: true,
      );
      if (!mounted) return;

      if (!fresh.hasAny) {
        Navigator.of(context).pop();
        SnackBarService.success(
          context,
          'Tu sistema ya se encuentra actualizado (v$_currentVersion).',
        );
        return;
      }

      if (fresh.canAutoUpdate) {
        final update = fresh.frontendUpdate ?? fresh.backendUpdate!;
        final isFull = fresh.isFullSystemUpdate;
        final navigator = Navigator.of(context);
        navigator.pop();
        await showDialog<bool>(
          context: navigator.context,
          barrierDismissible: !update.isCritical,
          builder: (_) => UpdateDialog(
            updateInfo: update,
            isFullSystemUpdate: isFull,
          ),
        );
        return;
      }

      setState(() {
        _inlineFeedback = _isTrialExpired
            ? 'Tu prueba gratuita finalizó. Activa tu licencia por WhatsApp conservando todos tus datos y volvé a verificar.'
            : (_isSubscriptionExpired
                ? 'Tu suscripción mensual aún figura pendiente de renovación. Si acabás de abonar, aguardá unos instantes y volvé a intentar.'
                : 'Todavía no figura habilitada la ventana de actualización en tu licencia. Contactá a soporte por WhatsApp para activarla.');
        _feedbackIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineFeedback =
            'No se pudo verificar con el servidor: ${e.toString().replaceAll('Exception: ', '')}';
        _feedbackIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isCheckingPermission = false);
      }
    }
  }

  Future<void> _dismissThisVersion() async {
    await UpdateService().dismissUpgradeVersion(_targetVersion);
    if (!mounted) return;
    Navigator.of(context).pop();
    SnackBarService.info(
      context,
      'Aviso ocultado hasta la próxima versión. Podés consultarlo cuando quieras en Configuración → Buscar Actualizaciones.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final String title;
    final String subtitle;
    final IconData icon;
    final AppModalAccent accent;

    if (_isTrialExpired) {
      title = 'Actualización v$_targetVersion Disponible';
      subtitle = 'Tu prueba gratuita finalizó';
      icon = Icons.rocket_launch_rounded;
      accent = AppModalAccent.emerald;
    } else if (_isSubscriptionExpired) {
      title = 'Actualización v$_targetVersion Disponible';
      subtitle = 'Suscripción mensual pendiente de renovación';
      icon = Icons.autorenew_rounded;
      accent = AppModalAccent.orange;
    } else if (_isLifetimeUpgrade) {
      title = 'Novedades v$_targetVersion';
      subtitle = 'Nueva versión disponible para Caja4U';
      icon = Icons.auto_awesome_rounded;
      accent = AppModalAccent.amber;
    } else {
      title = 'Actualización v$_targetVersion Disponible';
      subtitle = 'Requiere licencia activa para descargar';
      icon = Icons.vpn_key_outlined;
      accent = AppModalAccent.blue;
    }

    return AppModalShell(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accent: accent,
      compact: true,
      maxWidth: 520,
      bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.amber.withValues(alpha: 0.40),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isLifetimeUpgrade
                          ? Icons.workspace_premium_outlined
                          : Icons.info_outline_rounded,
                      size: 14,
                      color: AppColors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isTrialExpired
                          ? 'Prueba Gratuita Finalizada'
                          : (_isSubscriptionExpired
                              ? 'Plan Mensual SaaS'
                              : (_isLifetimeUpgrade
                                  ? 'Licencia Pago Único'
                                  : 'Estado de Licencia')),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'v$_targetVersion',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Novedades de esta versión:',
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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.28,
              ),
              child: SingleChildScrollView(
                child: Text(
                  _changelog,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isSubscriptionExpired
                  ? AppColors.orange.withValues(alpha: 0.08)
                  : AppColors.amber.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isSubscriptionExpired
                    ? AppColors.orange.withValues(alpha: 0.30)
                    : AppColors.amber.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              _isTrialExpired
                  ? 'Tu período de prueba gratuita finalizó. Todos tus productos y ventas están guardados; activá tu licencia para actualizar a v$_targetVersion y seguir operando.'
                  : (_isSubscriptionExpired
                      ? 'Tu suscripción mensual se encuentra vencida. Renová tu abono para descargar e instalar automáticamente la versión v$_targetVersion.'
                      : (_isLifetimeUpgrade
                          ? 'Tu licencia actual es Pago Único (v$_currentVersion). Para actualizar a v$_targetVersion podés abonar la actualización por única vez o pasarte al Plan Mensual con actualizaciones automáticas y soporte incluido.'
                          : 'Activá o sincronizá una licencia vigente en Configuración → Suscripción y Licencia para descargar esta actualización.')),
              style: const TextStyle(
                fontSize: 12.8,
                color: AppColors.textPrimary,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_inlineFeedback != null) ...[
            const SizedBox(height: 10),
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
                  fontSize: 12,
                  color: _feedbackIsError
                      ? Colors.red.shade800
                      : Colors.blue.shade900,
                ),
              ),
            ),
          ],
          if (_isLifetimeUpgrade || _isSubscriptionExpired || _isTrialExpired) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _openWhatsApp,
                icon: const Icon(Icons.chat_rounded, size: 19),
                label: Text(
                  _isTrialExpired
                      ? 'Activar mi licencia por WhatsApp'
                      : (_isSubscriptionExpired
                          ? 'Renovar Plan Mensual por WhatsApp'
                          : 'Consultar actualización por WhatsApp'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
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
                'WhatsApp Soporte Dev4U: $_whatsappDisplay',
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
                onPressed: _isCheckingPermission ? null : _recheckPermission,
                icon: _isCheckingPermission
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  _isCheckingPermission
                      ? 'Verificando habilitación...'
                      : (_isTrialExpired
                          ? 'Ya activé mi licencia · Verificar ahora'
                          : (_isSubscriptionExpired
                              ? 'Ya renové · Verificar habilitación'
                              : 'Ya aboné · Verificar habilitación')),
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
        ],
      ),
      footerActions: [
        if (_isLifetimeUpgrade && widget.showDismissVersionAction)
          TextButton.icon(
            onPressed: _isCheckingPermission ? null : _dismissThisVersion,
            icon: const Icon(Icons.visibility_off_outlined, size: 17),
            label: const Text('Ocultar aviso de esta versión'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
