import 'package:flutter/material.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/shared_user_menu.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class GlobalAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String currentRoute;
  final String title;
  final Widget? extraAction;
  final bool showBackButton;

  const GlobalAppBar({
    Key? key,
    required this.currentRoute,
    this.title = 'Sistema POS',
    this.extraAction,
    this.showBackButton = false,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              // ── LEFT BLOCK ────────────────────────────────────────────
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Back button for secondary screens
                        if (showBackButton)
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.blueGrey),
                            tooltip: 'Volver',
                            onPressed: () => Navigator.of(context).pop(),
                          )
                        else
                          const SizedBox(width: 8),
                        const Icon(Icons.point_of_sale_rounded,
                            color: Colors.blueAccent, size: 28),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Consumer<SettingsProvider>(
                            builder: (context, settings, _) {
                              final name =
                                  settings.settings?.companyName ?? title;
                              return Text(
                                name.isNotEmpty ? name : title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 18),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── CENTER BLOCK (navigation tabs — always centered) ──────
              Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  final String currentPlan = settings.currentPlan;
                  final bool isProOrEnterprise = currentPlan == 'pro' || currentPlan == 'enterprise';

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildNavTab(
                        context: context,
                        label: 'Terminal POS',
                        icon: Icons.point_of_sale,
                        route: '/pos',
                        activeColor: Colors.teal.shade700,
                      ),
                      _buildNavTab(
                        context: context,
                        label: 'Ventas del Día',
                        icon: Icons.receipt_long_outlined,
                        route: '/sales-history',
                        activeColor: Colors.blueAccent,
                        permissionKey: 'view_global_history',
                      ),
                      _buildNavTab(
                        context: context,
                        label: 'Catálogo',
                        icon: Icons.inventory_2_outlined,
                        route: '/catalog',
                        activeColor: Colors.deepPurple,
                        permissionKey: 'manage_catalog',
                      ),
                      _buildNavTab(
                        context: context,
                        label: 'Cuentas Corrientes',
                        icon: isProOrEnterprise ? Icons.account_balance_wallet_outlined : Icons.lock_outline,
                        route: '/cuentas-corrientes',
                        activeColor: Colors.orange.shade700,
                        isLocked: !isProOrEnterprise,
                      ),
                    ],
                  );
                },
              ),

              // ── RIGHT BLOCK ───────────────────────────────────────────
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (extraAction != null) ...[
                      extraAction!,
                      const SizedBox(width: 8),
                    ],
                    const SharedUserMenu(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavTab({
    required BuildContext context,
    required String label,
    required IconData icon,
    required String route,
    required Color activeColor,
    String? permissionKey,
    bool isLocked = false,
  }) {
    final isActive = currentRoute == route;
    final color = isLocked ? Colors.grey.shade400 : (isActive ? activeColor : Colors.blueGrey);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          border: isActive
              ? Border(bottom: BorderSide(color: activeColor, width: 3))
              : const Border(
                  bottom: BorderSide(color: Colors.transparent, width: 3)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Hidden bold text to pre-reserve max width so tab never shifts
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: TextButton.icon(
                icon: Icon(icon, size: 20),
                label: Text(
                  label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: null,
              ),
            ),
            // Real interactive button
            TextButton.icon(
              icon: Icon(icon, color: color, size: isActive ? 20 : 18),
              label: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: isActive ? 15 : 14,
                ),
              ),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: const ContinuousRectangleBorder(),
              ),
              onPressed: isActive
                  ? null
                  : () async {
                      if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber),
                                SizedBox(width: 8),
                                Expanded(child: Text('Esta función requiere el plan PRO. Comunícate con soporte para actualizar tu licencia.')),
                              ],
                            ),
                            backgroundColor: Colors.blueGrey.shade900,
                            behavior: SnackBarBehavior.floating,
                            action: SnackBarAction(
                              label: 'OK',
                              textColor: Colors.amber,
                              onPressed: () {},
                            ),
                          ),
                        );
                        return;
                      }
                      if (permissionKey != null) {
                        final authorized = await AdminPinDialog.verify(
                            context,
                            action: label,
                            permissionKey: permissionKey);
                        if (!authorized || !context.mounted) return;
                      }
                      if (route == '/pos') {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                            '/pos', (r) => false);
                      } else {
                        Navigator.of(context).pushReplacementNamed(route);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
