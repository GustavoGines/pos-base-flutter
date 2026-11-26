import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../features/settings/presentation/providers/settings_provider.dart';
import '../../services/license_heartbeat_service.dart';
import '../../utils/snack_bar_service.dart';

class LicenseLockScreen extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final LicenseSecurityStatus securityStatus;
  final bool missingMobileAddon;
  final bool missingRemoteAddon;

  const LicenseLockScreen({
    super.key,
    required this.navigatorKey,
    this.securityStatus = LicenseSecurityStatus.ok,
    this.missingMobileAddon = false,
    this.missingRemoteAddon = false,
  });

  @override
  State<LicenseLockScreen> createState() => _LicenseLockScreenState();
}

class _LicenseLockScreenState extends State<LicenseLockScreen> {
  static const String _whatsappNumber = '5493704367202';
  static const String _whatsappDisplay = '+54 9 3704 36-7202';

  final _licenseKeyCtrl = TextEditingController();
  bool _isActivating = false;
  bool _showAlternateKeyInput = false;

  @override
  void dispose() {
    _licenseKeyCtrl.dispose();
    super.dispose();
  }

  String _sanitizeError(String error) {
    if (error.contains('<html') ||
        error.contains('<!DOCTYPE') ||
        error.contains('<body')) {
      return 'Error de comunicación con el servidor. Verifica tu conexión y la URL configurada.';
    }
    return error.replaceAll('Exception: ', '');
  }

  String _formatLocalDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    try {
      return DateFormat('dd/MM/yyyy', 'es_AR').format(local);
    } catch (_) {
      return DateFormat('dd/MM/yyyy').format(local);
    }
  }

  LicenseSecurityStatus _resolveEffectiveStatus(SettingsProvider settings) {
    if (widget.securityStatus != LicenseSecurityStatus.ok) {
      return widget.securityStatus;
    }
    final reason = settings.settings?.licenseBlockReason;
    if (reason == 'trial_expired') return LicenseSecurityStatus.trialExpired;
    if (reason == 'subscription_expired') {
      return LicenseSecurityStatus.subscriptionExpired;
    }
    if (reason == 'offline_grace_expired') {
      return LicenseSecurityStatus.offlineExpired;
    }
    if (reason == 'clock_tampered') return LicenseSecurityStatus.clockTampered;
    if (reason == 'suspended') return LicenseSecurityStatus.suspended;
    if (settings.settings?.isTrial == true) {
      return LicenseSecurityStatus.trialExpired;
    }
    return LicenseSecurityStatus.ok;
  }

  Future<void> _openWhatsApp({
    required LicenseSecurityStatus effectiveStatus,
    required String? companyName,
  }) async {
    final commerce = (companyName != null && companyName.trim().isNotEmpty)
        ? ' para "${companyName.trim()}"'
        : '';

    final String msg;
    if (widget.missingMobileAddon) {
      msg = 'Hola! Quiero sumar el módulo "Caja4U Móvil"$commerce.';
    } else if (widget.missingRemoteAddon) {
      msg = 'Hola! Quiero sumar el módulo "Acceso Remoto"$commerce.';
    } else if (effectiveStatus == LicenseSecurityStatus.trialExpired) {
      msg =
          'Hola! Finalizó mi prueba gratuita de Caja4U$commerce y quiero activar mi licencia (Plan Mensual o Pago Único) conservando todos mis datos.';
    } else if (effectiveStatus == LicenseSecurityStatus.subscriptionExpired) {
      msg =
          'Hola! Quiero renovar la suscripción mensual de Caja4U$commerce para reactivar mi caja.';
    } else if (effectiveStatus == LicenseSecurityStatus.clockTampered) {
      msg =
          'Hola! Necesito asistencia con la validación de fecha y hora en Caja4U$commerce.';
    } else {
      msg =
          'Hola! Necesito ayuda para habilitar/renovar mi licencia de Caja4U$commerce.';
    }

    final uri = Uri.parse(
      'https://wa.me/$_whatsappNumber?text=${Uri.encodeComponent(msg)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _activate() async {
    final key = _licenseKeyCtrl.text.trim();
    if (key.isEmpty) {
      SnackBarService.error(context, 'Por favor, ingresá una clave de licencia.');
      return;
    }

    setState(() => _isActivating = true);
    try {
      final provider = context.read<SettingsProvider>();
      final prefs = await SharedPreferences.getInstance();
      final activeUrl = prefs.getString('pos_api') ?? provider.currentApiUrl;
      await provider.activateLicense(activeUrl, key);
      if (mounted) {
        _licenseKeyCtrl.clear();
        SnackBarService.success(
          context,
          'Licencia activada correctamente. ¡Ya podés seguir operando!',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, _sanitizeError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isActivating = false);
    }
  }

  Future<void> _retrySync() async {
    setState(() => _isActivating = true);
    try {
      final provider = context.read<SettingsProvider>();
      final prefs = await SharedPreferences.getInstance();
      final activeUrl = prefs.getString('pos_api') ?? provider.currentApiUrl;
      await provider.syncLicenseWithServer(activeUrl);
      if (mounted) {
        SnackBarService.success(
          context,
          'Licencia verificada y habilitada. ¡Podés continuar operando!',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, _sanitizeError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isActivating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Consumer<SettingsProvider>(
            builder: (context, settingsProv, _) {
              final s = settingsProv.settings;
              final existingKey = (s?.licenseStatus ?? '').trim();
              final bool hasExistingKey = existingKey.isNotEmpty;
              final effectiveStatus = _resolveEffectiveStatus(settingsProv);
              final error = settingsProv.errorMessage;
              final isConnectionError = error != null &&
                  (error.toLowerCase().contains('conexión') ||
                      error.toLowerCase().contains('servidor') ||
                      error.toLowerCase().contains('json'));

              final _LockVisualConfig visual = _buildVisualConfig(
                effectiveStatus: effectiveStatus,
                hasExistingKey: hasExistingKey,
                localExpFormatted: _formatLocalDate(s?.localLicenseExpiresAt),
              );

              final bool showKeyFieldDirectly = !hasExistingKey;
              final bool showKeyInput =
                  showKeyFieldDirectly || _showAlternateKeyInput;

              return Container(
                width: 520,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
                decoration: BoxDecoration(
                  color: const Color(0xFF16233F),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 36,
                      offset: const Offset(0, 14),
                    ),
                  ],
                  border: Border.all(
                    color: visual.accentColor.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: visual.accentColor.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: visual.accentColor.withValues(alpha: 0.40),
                        ),
                      ),
                      child: Icon(
                        visual.icon,
                        size: 38,
                        color: visual.accentColor,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      visual.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      visual.subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    if (visual.showDataSafeBanner) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                const Color(0xFF34D399).withValues(alpha: 0.45),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.verified_user_rounded,
                              color: Color(0xFF34D399),
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Todos tus productos, precios, clientes, turnos y ventas siguen guardados y seguros en este equipo. Al activar tu licencia continuás exactamente donde dejaste.',
                                style: TextStyle(
                                  color: Color(0xFFECFDF5),
                                  fontSize: 13,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (error != null && isConnectionError) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.wifi_off_rounded,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _sanitizeError(error),
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (hasExistingKey) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.key_rounded,
                                color: Colors.white54, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                existingKey,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (visual.showWhatsAppCta) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          key: const Key('lock_screen_whatsapp_button'),
                          onPressed: () => _openWhatsApp(
                            effectiveStatus: effectiveStatus,
                            companyName: s?.companyName,
                          ),
                          icon: const Icon(Icons.chat_rounded, size: 20),
                          label: Text(
                            visual.whatsAppLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'WhatsApp Ventas y Soporte Dev4U: $_whatsappDisplay',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (hasExistingKey) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          key: const Key('lock_screen_verify_button'),
                          onPressed: _isActivating ? null : _retrySync,
                          icon: _isActivating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.sync_rounded),
                          label: Text(
                            _isActivating
                                ? 'Verificando licencia...'
                                : visual.verifyButtonLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        key: const Key('lock_screen_toggle_alt_key'),
                        onPressed: () {
                          setState(() {
                            _showAlternateKeyInput = !_showAlternateKeyInput;
                            // Nunca precargar ni conservar la clave enmascarada (pos_****)
                            _licenseKeyCtrl.clear();
                          });
                        },
                        icon: Icon(
                          _showAlternateKeyInput
                              ? Icons.expand_less_rounded
                              : Icons.vpn_key_outlined,
                          size: 18,
                          color: Colors.white60,
                        ),
                        label: Text(
                          _showAlternateKeyInput
                              ? 'Ocultar ingreso manual'
                              : 'Ingresar otra clave de licencia',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (showKeyInput) ...[
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('lock_screen_license_key_field'),
                        controller: _licenseKeyCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: hasExistingKey
                              ? 'Nueva clave de licencia'
                              : 'Clave de licencia',
                          labelStyle: const TextStyle(color: Colors.white54),
                          hintText: 'pos_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                          hintStyle: const TextStyle(color: Colors.white24),
                          prefixIcon: Icon(
                            Icons.vpn_key_rounded,
                            color: visual.accentColor,
                          ),
                          suffixIcon: IconButton(
                            icon:
                                const Icon(Icons.paste, color: Colors.white70),
                            tooltip: 'Pegar licencia',
                            onPressed: () async {
                              final data =
                                  await Clipboard.getData('text/plain');
                              if (data != null &&
                                  data.text != null &&
                                  data.text!.isNotEmpty) {
                                _licenseKeyCtrl.text = data.text!;
                              }
                            },
                          ),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton(
                          key: const Key('lock_screen_activate_button'),
                          onPressed: _isActivating ? null : _activate,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: visual.accentColor.withValues(alpha: 0.7),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isActivating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  hasExistingKey
                                      ? 'ACTIVAR NUEVA CLAVE'
                                      : 'ACTIVAR LICENCIA',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            widget.navigatorKey.currentState
                                ?.pushNamed('/close-shift');
                          },
                          icon: const Icon(
                            Icons.point_of_sale_rounded,
                            color: Colors.orangeAccent,
                            size: 18,
                          ),
                          label: const Text(
                            'CERRAR CAJA / ARQUEO DE TURNO',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            context.read<AuthProvider>().logout();
                            widget.navigatorKey.currentState
                                ?.pushNamedAndRemoveUntil(
                                    '/login', (route) => false);
                          },
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white54,
                            size: 18,
                          ),
                          label: const Text(
                            'CERRAR SESIÓN',
                            style: TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  _LockVisualConfig _buildVisualConfig({
    required LicenseSecurityStatus effectiveStatus,
    required bool hasExistingKey,
    required String localExpFormatted,
  }) {
    if (widget.missingMobileAddon) {
      return const _LockVisualConfig(
        icon: Icons.smartphone_rounded,
        accentColor: Color(0xFF38BDF8),
        title: 'Módulo Caja4U Móvil no incluido',
        subtitle:
            'Tu licencia actual no incluye la app móvil. Comunicate con Dev4U para habilitarla al instante.',
        showDataSafeBanner: false,
        showWhatsAppCta: true,
        whatsAppLabel: 'Solicitar Caja4U Móvil por WhatsApp',
        verifyButtonLabel: 'Ya actualicé mi plan · Verificar ahora',
      );
    }

    if (widget.missingRemoteAddon) {
      return const _LockVisualConfig(
        icon: Icons.public_off_rounded,
        accentColor: Color(0xFF38BDF8),
        title: 'Acceso Remoto no incluido',
        subtitle:
            'Tu licencia actual opera solo en red local. Sumá Acceso Remoto para conectarte desde fuera del local.',
        showDataSafeBanner: false,
        showWhatsAppCta: true,
        whatsAppLabel: 'Solicitar Acceso Remoto por WhatsApp',
        verifyButtonLabel: 'Ya actualicé mi plan · Verificar ahora',
      );
    }

    if (!hasExistingKey) {
      return const _LockVisualConfig(
        icon: Icons.vpn_key_rounded,
        accentColor: Color(0xFF10B981),
        title: 'Activación de Caja4U',
        subtitle:
            'Ingresá tu clave de licencia para comenzar a usar el sistema en este equipo.',
        showDataSafeBanner: false,
        showWhatsAppCta: true,
        whatsAppLabel: 'Solicitar licencia o Demo por WhatsApp',
        verifyButtonLabel: 'Verificar licencia',
      );
    }

    return switch (effectiveStatus) {
      LicenseSecurityStatus.trialExpired => _LockVisualConfig(
          icon: Icons.rocket_launch_rounded,
          accentColor: const Color(0xFF10B981),
          title: '¡Gracias por probar Caja4U!',
          subtitle: localExpFormatted.isNotEmpty
              ? 'Tu período de prueba gratuita finalizó el $localExpFormatted. Elegí Plan Mensual o Pago Único para continuar.'
              : 'Tu período de prueba gratuita finalizó. Elegí Plan Mensual o Pago Único para continuar.',
          showDataSafeBanner: true,
          showWhatsAppCta: true,
          whatsAppLabel: 'Quiero activar mi licencia por WhatsApp',
          verifyButtonLabel: 'Ya activé mi licencia · Verificar ahora',
        ),
      LicenseSecurityStatus.subscriptionExpired => _LockVisualConfig(
          icon: Icons.event_repeat_rounded,
          accentColor: const Color(0xFFF59E0B),
          title: 'Suscripción pendiente de renovación',
          subtitle: localExpFormatted.isNotEmpty
              ? 'Tu abono mensual venció el $localExpFormatted. Renová tu suscripción para destrabar el punto de venta al instante.'
              : 'Tu suscripción mensual se encuentra vencida. Renová tu abono para destrabar el punto de venta al instante.',
          showDataSafeBanner: true,
          showWhatsAppCta: true,
          whatsAppLabel: 'Renovar o informar pago por WhatsApp',
          verifyButtonLabel: 'Ya aboné · Verificar habilitación ahora',
        ),
      LicenseSecurityStatus.offlineExpired => const _LockVisualConfig(
          icon: Icons.wifi_tethering_error_rounded,
          accentColor: Color(0xFFF59E0B),
          title: 'Validación en línea requerida',
          subtitle:
              'Pasaron más de 72 horas sin conexión a internet. Conectá este equipo a la red y verificá tu licencia para continuar.',
          showDataSafeBanner: true,
          showWhatsAppCta: false,
          whatsAppLabel: 'Consultar soporte por WhatsApp',
          verifyButtonLabel: 'Verificar conexión y licencia ahora',
        ),
      LicenseSecurityStatus.clockTampered => const _LockVisualConfig(
          icon: Icons.schedule_rounded,
          accentColor: Color(0xFFF87171),
          title: 'Verificación de fecha y hora requerida',
          subtitle:
              'Se detectó un cambio en el reloj del sistema. Corregí la fecha y hora de Windows, conectate a internet y verificá tu licencia.',
          showDataSafeBanner: true,
          showWhatsAppCta: true,
          whatsAppLabel: 'Contactar soporte por WhatsApp',
          verifyButtonLabel: 'Ya corregí la hora · Verificar ahora',
        ),
      LicenseSecurityStatus.suspended ||
      LicenseSecurityStatus.ok =>
        const _LockVisualConfig(
          icon: Icons.pause_circle_outline_rounded,
          accentColor: Color(0xFFF59E0B),
          title: 'Licencia pausada o pendiente de validación',
          subtitle:
              'Esta licencia no figura activa en este momento. Si ya regularizaste tu estado, presioná Verificar ahora.',
          showDataSafeBanner: true,
          showWhatsAppCta: true,
          whatsAppLabel: 'Contactar soporte por WhatsApp',
          verifyButtonLabel: 'Verificar habilitación ahora',
        ),
    };
  }
}

class _LockVisualConfig {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final bool showDataSafeBanner;
  final bool showWhatsAppCta;
  final String whatsAppLabel;
  final String verifyButtonLabel;

  const _LockVisualConfig({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.showDataSafeBanner,
    required this.showWhatsAppCta,
    required this.whatsAppLabel,
    required this.verifyButtonLabel,
  });
}
