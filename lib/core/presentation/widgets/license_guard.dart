import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import 'package:provider/provider.dart';
import '../../../features/settings/presentation/providers/settings_provider.dart';
import '../pages/license_lock_screen.dart';

class LicenseGuard extends StatelessWidget {
  final Widget child;
  final ValueNotifier<String?> routeNotifier;
  final GlobalKey<NavigatorState> navigatorKey;

  const LicenseGuard({
    super.key,
    required this.child,
    required this.routeNotifier,
    required this.navigatorKey,
  });

  /// L-13: Determina si una URL de API apunta a un servidor remoto fuera de la red local (LAN).
  /// Evalúa el host real en lugar de asumir que cualquier URL con `https://` es remota.
  static bool isRemoteApiUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return false;

    final host = uri.host.toLowerCase();

    // Dominios de túneles conocidos son siempre remotos
    if (host.endsWith('.trycloudflare.com') ||
        host.endsWith('.ngrok.io') ||
        host.endsWith('.ngrok-free.app') ||
        host.endsWith('.loca.lt')) {
      return true;
    }

    // Loopback, localhost y nombres de red local (.local, .lan, .internal, o hostname simple de Windows sin puntos)
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.endsWith('.local') ||
        host.endsWith('.lan') ||
        host.endsWith('.home') ||
        host.endsWith('.internal') ||
        !host.contains('.')) {
      return false;
    }

    // Verificar rangos IPv4 privados RFC 1918 y Link-Local
    final ipv4Parts = host.split('.');
    if (ipv4Parts.length == 4) {
      final octets = ipv4Parts.map(int.tryParse).toList();
      if (octets.every((o) => o != null && o >= 0 && o <= 255)) {
        final a = octets[0]!;
        final b = octets[1]!;
        if (a == 10) return false; // 10.0.0.0/8
        if (a == 127) return false; // 127.0.0.0/8
        if (a == 192 && b == 168) return false; // 192.168.0.0/16
        if (a == 172 && b >= 16 && b <= 31) return false; // 172.16.0.0/12
        if (a == 169 && b == 254) return false; // 169.254.0.0/16 (APIPA)
        if (a == 100 && b >= 64 && b <= 127) return false; // 100.64.0.0/10 (Tailscale / CGNAT LAN)
        return true; // IPv4 pública externa
      }
    }

    // Cualquier otro dominio público con TLD (ej. pos.miempresa.com) es acceso remoto
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to settings for real-time license updates
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: routeNotifier,
          builder: (context, currentRoute, _) {
            // Whitelist Estricta: Solo /login y /close-shift son navegables sin licencia
            final bool isWhitelisted = 
                currentRoute == '/login' || 
                currentRoute == '/close-shift';

            final bool isMobile = AppConfig.isMobile;
            final bool missingMobileAddon = isMobile && !settingsProvider.hasFeature('mobile_app');
            
            // L-13: Lógica de acceso remoto basada en el host de red (LAN RFC 1918 vs WAN)
            final String activeUrl = settingsProvider.currentApiUrl;
            final bool isRemote = isRemoteApiUrl(activeUrl);
            final bool missingRemoteAddon = isRemote && !settingsProvider.hasFeature('remote_access');

            final bool isBlocked = (!settingsProvider.isLicenseActive || missingMobileAddon || missingRemoteAddon) && !isWhitelisted;


            return Stack(
              children: [
                // 1. Maintain the main Navigator (child) alive in the background
                // We use IgnorePointer and FocusScope to disable all interaction
                IgnorePointer(
                  ignoring: isBlocked,
                  child: FocusScope(
                    canRequestFocus: !isBlocked,
                    child: child,
                  ),
                ),
                
                // 2. Render the FireWall on top with its own isolated Navigator
                // This provides the Overlay required by TextField, while keeping
                // the main Navigator alive so navigatorKey.currentState works!
                if (isBlocked)
                  Positioned.fill(
                    child: HeroControllerScope.none(
                      child: Navigator(
                        // We provide an empty list of observers to avoid sharing 
                        // the global HeroController, which causes conflicts.
                        observers: const [],
                        onGenerateRoute: (settings) => MaterialPageRoute(
                          builder: (context) => LicenseLockScreen(
                            navigatorKey: navigatorKey,
                            securityStatus: settingsProvider.securityStatus,
                            missingMobileAddon: missingMobileAddon,
                            missingRemoteAddon: missingRemoteAddon,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
