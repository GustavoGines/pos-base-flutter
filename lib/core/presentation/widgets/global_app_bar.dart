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
    super.key,
    required this.currentRoute,
    this.title = 'Sistema POS',
    this.extraAction,
    this.showBackButton = false,
  });

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
              Flexible(
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
              const Spacer(),

              // ── CENTER BLOCK (navigation tabs — always centered) ──────
              Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  final bool canAccessCuentasCorrientes = settings.hasFeature('cuentas_corrientes');

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
                        label: 'Registro de Ventas',
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
                        icon: canAccessCuentasCorrientes ? Icons.account_balance_wallet_outlined : Icons.lock_outline,
                        route: '/cuentas-corrientes',
                        activeColor: Colors.orange.shade700,
                        isLocked: !canAccessCuentasCorrientes,
                      ),
                    ],
                  );
                },
              ),

              const Spacer(),

              // ── RIGHT BLOCK ───────────────────────────────────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (extraAction != null) ...[
                    extraAction!,
                    const SizedBox(width: 8),
                  ],
                  const SharedUserMenu(),
                ],
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
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              width: 400,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Gradient header
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF7C3AED), Color(0xFF3B82F6)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
                                        ),
                                        const SizedBox(height: 12),
                                        const Text('Módulo PRO Disponible',
                                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Text('Plan Básico activo',
                                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  // Body
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Lleva el control total de tus clientes con el módulo de Cuentas Corrientes:',
                                          style: TextStyle(fontSize: 14, color: Colors.black87),
                                        ),
                                        const SizedBox(height: 16),
                                        _proFeature('Cuentas corrientes y límites de crédito por cliente'),
                                        _proFeature('Pago de tickets específicos'),
                                        _proFeature('Historial de movimientos en tiempo real'),
                                        _proFeature('Alertas de crédito insuficiente'),
                                        const SizedBox(height: 20),
                                        const Text(
                                          'Contacta a soporte para activar la Fase 2 de tu Sistema POS.',
                                          style: TextStyle(fontSize: 12, color: Colors.black54),
                                        ),
                                        const SizedBox(height: 20),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF7C3AED),
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('Entendido', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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

/// Helper top-level para el diálogo de upgrade PRO
Widget _proFeature(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Row(
    children: [
      const Icon(Icons.check_circle_rounded, color: Color(0xFF7C3AED), size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87))),
    ],
  ),
);

