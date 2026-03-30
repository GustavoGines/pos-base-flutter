import 'package:flutter/material.dart';
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

            final bool isBlocked = !settingsProvider.isLicenseActive && !isWhitelisted;

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
