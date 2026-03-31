import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../features/settings/presentation/providers/settings_provider.dart';
import '../../../features/auth/presentation/providers/auth_provider.dart';
import '../../utils/snack_bar_service.dart';
import '../../services/license_heartbeat_service.dart';
import '../../config/app_config.dart';

class LicenseLockScreen extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final LicenseSecurityStatus securityStatus;

  const LicenseLockScreen({
    super.key,
    required this.navigatorKey,
    this.securityStatus = LicenseSecurityStatus.ok,
  });

  @override
  State<LicenseLockScreen> createState() => _LicenseLockScreenState();
}

class _LicenseLockScreenState extends State<LicenseLockScreen> {
  final _licenseKeyCtrl = TextEditingController();
  bool _isActivating = false;

  @override
  void dispose() {
    _licenseKeyCtrl.dispose();
    super.dispose();
  }

  String _sanitizeError(String error) {
    if (error.contains('<html') || error.contains('<!DOCTYPE') || error.contains('<body')) {
      return 'Error de comunicación con el servidor. Verifica tu conexión y la URL configurada.';
    }
    return error.replaceAll('Exception: ', '');
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
      // La base URL se toma de la misma que usa el sistema por defecto
      await provider.activateLicense(AppConfig.kApiBaseUrl, key);
      if (mounted) {
        SnackBarService.success(context, '✅ Licencia activada con éxito. El sistema se ha desbloqueado.');
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
      backgroundColor: const Color(0xFF111827), // Dark grey/black
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              )
            ],
            border: Border.all(color: Colors.red.shade900, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.securityStatus == LicenseSecurityStatus.clockTampered 
                    ? Icons.security_rounded 
                    : Icons.lock_person_rounded, 
                size: 80, 
                color: Colors.redAccent
              ),
              const SizedBox(height: 24),
              Text(
                widget.securityStatus == LicenseSecurityStatus.clockTampered 
                    ? 'BLOQUEO POR SEGURIDAD' 
                    : 'SISTEMA BLOQUEADO',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  final error = settings.errorMessage;
                  final isConnectionError = error != null && 
                      (error.toLowerCase().contains('conexión') || 
                       error.toLowerCase().contains('servidor') ||
                       error.toLowerCase().contains('json'));

                  if (error != null && isConnectionError) {
                    return Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _sanitizeError(error),
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Text(
                    widget.securityStatus == LicenseSecurityStatus.clockTampered 
                        ? 'Se detectó una anomalía en el reloj del sistema.\nPor seguridad, el acceso ha sido revocado. Contacte soporte.'
                        : widget.securityStatus == LicenseSecurityStatus.offlineExpired
                            ? 'Se ha excedido el periodo de gracia offline (72hs).\nEs necesario conectar el equipo a internet para validar la suscripción.'
                            : 'Tu licencia ha expirado, ha sido suspendida o es inexistente en este equipo.\nPara continuar operando, por favor ingresá una clave válida.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                  );
                },
              ),
              const SizedBox(height: 40),
              
              // Campo de Activación In-Situ
              TextField(
                controller: _licenseKeyCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Clave de Licencia',
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: 'XXXX-XXXX-XXXX-XXXX',
                  hintStyle: const TextStyle(color: Colors.white12),
                  prefixIcon: const Icon(Icons.vpn_key, color: Colors.redAccent),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isActivating ? null : _activate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isActivating
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('ACTIVAR AHORA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              ),
              
              const SizedBox(height: 48),
              const Divider(color: Colors.white10),
              const SizedBox(height: 24),
              
              // Acciones de Emergencia
              Row(
                children: [
                   Expanded(
                     child: OutlinedButton.icon(
                       onPressed: () {
                         widget.navigatorKey.currentState?.pushNamed('/close-shift');
                       },
                       icon: const Icon(Icons.point_of_sale_rounded),
                       label: const Text('CERRAR CAJA'),
                       style: OutlinedButton.styleFrom(
                         foregroundColor: Colors.orangeAccent,
                         side: const BorderSide(color: Colors.orangeAccent),
                         padding: const EdgeInsets.symmetric(vertical: 16),
                       ),
                     ),
                   ),
                   const SizedBox(width: 16),
                   Expanded(
                     child: OutlinedButton.icon(
                       onPressed: () {
                         context.read<AuthProvider>().logout();
                         widget.navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
                       },
                       icon: const Icon(Icons.logout_rounded),
                       label: const Text('CERRAR SESIÓN'),
                       style: OutlinedButton.styleFrom(
                         foregroundColor: Colors.white70,
                         side: const BorderSide(color: Colors.white24),
                         padding: const EdgeInsets.symmetric(vertical: 16),
                       ),
                     ),
                   ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
