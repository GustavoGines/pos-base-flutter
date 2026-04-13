import 'package:flutter/material.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/shared_user_menu.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/inventory_alerts_widget.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 1100;

    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              // ── LEFT BLOCK ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showBackButton) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.blueGrey),
                        tooltip: 'Volver',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Icon(Icons.point_of_sale_rounded, color: Colors.blueAccent, size: 26),
                    const SizedBox(width: 8),
                    Consumer<SettingsProvider>(
                      builder: (context, settings, _) {
                        final name = settings.settings?.companyName ?? title;
                        return Text(
                          name.isNotEmpty ? name : title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isCompact ? 15 : 18,
                          ),
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ─── CENTER BLOCK ─────────────────────────────────────────────
              Expanded(
                child: Consumer<SettingsProvider>(
                  builder: (context, settings, _) {
                    final bool canAccessCuentasCorrientes = settings.hasFeature('current_accounts');
                    final bool canAccessQuotes = settings.hasFeature('quotes');
                    final bool canAccessPos = settings.hasFeature('fast_pos');
                    final bool canAccessAdvancedReports = settings.hasFeature('advanced_reports');

                    return Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canAccessPos)
                              _buildNavTab(
                                context: context,
                                label: 'Terminal POS',
                                icon: Icons.point_of_sale,
                                route: '/pos',
                                activeColor: Colors.teal.shade700,
                                isCompact: isCompact,
                              ),
                            _buildNavTab(
                              context: context,
                              label: 'Registro de Ventas',
                              icon: Icons.receipt_long_outlined,
                              route: '/sales-history',
                              activeColor: Colors.blueAccent,
                              permissionKey: 'view_global_history',
                              isCompact: isCompact,
                            ),
                            _buildNavTab(
                              context: context,
                              label: 'Catálogo',
                              icon: Icons.inventory_2_outlined,
                              route: '/catalog',
                              activeColor: Colors.deepPurple,
                              permissionKey: 'manage_catalog',
                              isCompact: isCompact,
                            ),
                            _buildNavTab(
                              context: context,
                              label: 'Reportes Gerenciales',
                              icon: canAccessAdvancedReports ? Icons.bar_chart : Icons.lock_outline,
                              route: '/reports',
                              activeColor: Colors.purple.shade700,
                              isLocked: !canAccessAdvancedReports,
                              lockedTitle: 'Reportes Gerenciales PRO',
                              lockedFeatures: const [
                                'Balance mensual con ganancias y márgenes',
                                'Exportación a Excel y PDF gerencial',
                                'Análisis por categoría y período',
                                'Comparativas de rendimiento',
                              ],
                              isCompact: isCompact,
                            ),
                            if (canAccessQuotes)
                              _buildNavTab(
                                context: context,
                                label: 'Presupuestos',
                                icon: Icons.description_outlined,
                                route: '/quotes',
                                activeColor: Colors.indigo.shade700,
                                isCompact: isCompact,
                              ),
                            _buildNavTab(
                              context: context,
                              label: 'Cuentas Corrientes',
                              icon: canAccessCuentasCorrientes
                                  ? Icons.account_balance_wallet_outlined
                                  : Icons.lock_outline,
                              route: '/cuentas-corrientes',
                              activeColor: Colors.orange.shade700,
                              isLocked: !canAccessCuentasCorrientes,
                              lockedTitle: 'Cuentas Corrientes PRO',
                              lockedFeatures: const [
                                'Cuentas corrientes y límites de crédito por cliente',
                                'Pago de tickets específicos',
                                'Historial de movimientos en tiempo real',
                                'Alertas de crédito insuficiente',
                              ],
                              isCompact: isCompact,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ── RIGHT BLOCK ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const InventoryAlertsWidget(),
                    const SizedBox(width: 8),
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
    required bool isCompact,
    String? permissionKey,
    bool isLocked = false,
    String lockedTitle = 'Módulo PRO',
    List<String> lockedFeatures = const [],
  }) {
    final isActive = currentRoute == route;
    final color = isLocked
        ? Colors.grey.shade400
        : (isActive ? activeColor : Colors.blueGrey);

    final Widget content = isCompact
        ? Icon(icon, color: color, size: 22)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: isActive ? 20 : 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: isActive ? 15 : 14,
                ),
              ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          border: isActive
              ? Border(bottom: BorderSide(color: activeColor, width: 3))
              : const Border(bottom: BorderSide(color: Colors.transparent, width: 3)),
        ),
        child: Tooltip(
          message: label,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 14 : 16,
                vertical: 12,
              ),
              shape: const ContinuousRectangleBorder(),
            ),
            onPressed: isActive
                ? null
                : () async {
                    if (isLocked) {
                      _showUpgradeDialog(context, title: lockedTitle, features: lockedFeatures);
                      return;
                    }
                    if (permissionKey != null) {
                      final authorized = await AdminPinDialog.verify(
                        context,
                        action: label,
                        permissionKey: permissionKey,
                      );
                      if (!authorized || !context.mounted) return;
                    }
                    if (route == '/pos') {
                      Navigator.of(context).pushNamedAndRemoveUntil('/pos', (r) => false);
                    } else {
                      Navigator.of(context).pushReplacementNamed(route);
                    }
                  },
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Diálogo genérico de upgrade PRO con botón de contacto por WhatsApp
void _showUpgradeDialog(
  BuildContext context, {
  required String title,
  required List<String> features,
}) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient header
            Container(
              width: double.infinity,
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
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Plan Básico activo — Mejorá tu plan para desbloquear',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 12)),
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
                    'Con el Plan PRO desbloqueás:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  ...features.map((f) => _proFeature(f)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.chat_rounded, color: Colors.white),
                      label: const Text(
                        'Contratar Plan PRO por WhatsApp',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      onPressed: () async {
                        final url = Uri.parse(
                            'https://wa.me/543704787285?text=Hola,%20quiero%20contratar%20el%20Plan%20PRO%20del%20Sistema%20POS');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar', style: TextStyle(color: Colors.black54)),
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
}

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
