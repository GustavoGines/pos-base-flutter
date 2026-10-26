import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/shared_user_menu.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/inventory_alerts_widget.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/core/utils/scale_serial_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend_desktop/features/updater/data/services/update_service.dart';
import 'package:frontend_desktop/features/updater/presentation/widgets/update_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/live_clock_widget.dart';


class GlobalAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String currentRoute;
  final String title;
  final Widget? extraAction;
  final bool showBackButton;
  /// Widget opcional (ej: TabBar) que aparece debajo de la barra principal.
  /// Idéntico al parámetro `bottom` del AppBar estándar de Flutter.
  final PreferredSizeWidget? bottom;

  const GlobalAppBar({
    super.key,
    required this.currentRoute,
    this.title = 'Sistema POS',
    this.extraAction,
    this.showBackButton = false,
    this.bottom,
  });

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0.0;
    // Agregamos un buffer de 4.0px para evitar overflows de redondeo en Windows (2.8px detectados)
    return Size.fromHeight(kToolbarHeight + bottomHeight + 4.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final hideCompanyName = screenWidth < 900;

    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1.5)),
              ),
              height: kToolbarHeight,
              child: Row(
            children: [
              // ── LEFT: Logo + Empresa ──────────────────────────────────────
              Padding(
                padding: EdgeInsets.only(left: screenWidth < 500 ? 6 : 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showBackButton) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.blueGrey),
                        tooltip: 'Volver',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Consumer<SettingsProvider>(
                      builder: (context, settings, _) {
                        final logoUrl = settings.settings?.effectiveLogoUrl;
                        final name = settings.settings?.companyName ?? title;
                        final uri = logoUrl != null ? Uri.tryParse(logoUrl) : null;
                        final hasValidLogo = uri != null &&
                            uri.hasScheme &&
                            uri.hasAuthority &&
                            uri.host.isNotEmpty;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasValidLogo)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    logoUrl!,
                                    width: 26,
                                    height: 26,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.point_of_sale_rounded,
                                      color: Colors.blueAccent,
                                      size: 26,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.point_of_sale_rounded,
                                  color: Colors.blueAccent,
                                  size: 26,
                                ),
                              ),
                            if (!hideCompanyName)
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 150),
                                child: Text(
                                  name.isNotEmpty ? name : title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── CENTER: Navegación Modular (Senior UX) ─────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final isIconOnly = w < 480;
                    final isCompact  = w < 760;

                    return Consumer<SettingsProvider>(
                      builder: (context, settings, _) {
                        final bool canAccessPos = settings.features.fastPos;
                        final bool canAccessAdvancedReports = settings.features.advancedReports;
                        final bool canAccessQuotes = settings.features.quotes;
                        final bool canAccessCurrentAccounts = settings.features.currentAccounts;
                        final bool canAccessChecks = settings.features.checks;
                        final bool canAccessSuppliers = settings.features.suppliers;
                        final bool canAccessExpenses = settings.features.expenses;


                        return Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 1. Terminal POS (Standalone - Principal)
                                if (canAccessPos)
                                  _buildNavTab(
                                    context: context,
                                    label: 'Terminal POS',
                                    shortLabel: 'POS',
                                    icon: Icons.point_of_sale,
                                    route: '/pos',
                                    activeColor: Colors.teal.shade700,
                                    isCompact: isCompact,
                                    isIconOnly: isIconOnly,
                                  ),

                                // 2. Gestión (Ventas, Presupuestos, Catálogo, Proveedores)
                                _NavDropdownGroup(
                                  label: 'Gestión',
                                  icon: Icons.dashboard_customize_outlined,
                                  isCompact: isCompact,
                                  isIconOnly: isIconOnly,
                                  isActive: ['/sales-history', '/catalog', '/quotes', '/suppliers'].contains(currentRoute),
                                  activeColor: Colors.blueAccent,
                                  menuChildren: [
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Registro de Ventas',
                                      icon: Icons.receipt_long_outlined,
                                      color: Colors.blueAccent,
                                      route: '/sales-history',
                                    ),
                                    if (canAccessQuotes)
                                      _buildMenuItem(
                                        context: context,
                                        label: 'Presupuestos',
                                        icon: Icons.description_outlined,
                                        color: Colors.indigo.shade700,
                                        route: '/quotes',
                                        permissionKey: AppPermissions.manageQuotes,
                                      ),
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Catálogo de Productos',
                                      icon: Icons.inventory_2_outlined,
                                      color: Colors.deepPurple,
                                      route: '/catalog',
                                      permissionKey: AppPermissions.manageCatalog,
                                    ),
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Proveedores',
                                      icon: canAccessSuppliers ? Icons.local_shipping_outlined : Icons.lock_outline,
                                      color: Colors.brown.shade600,
                                      route: '/suppliers',
                                      permissionKey: AppPermissions.viewSuppliers,
                                      isLocked: !canAccessSuppliers,
                                      lockedTitle: 'Proveedores PREMIUM',
                                      lockedFeatures: [
                                        'Catálogo ilimitado de proveedores',
                                        'Control de deudas y saldos por proveedor',
                                      ],
                                    ),
                                  ],
                                ),

                                // 3. Finanzas (Ctas Ctes, Cheques, Gastos, Reportes)
                                _NavDropdownGroup(
                                  label: 'Finanzas',
                                  icon: Icons.account_balance_outlined,
                                  isCompact: isCompact,
                                  isIconOnly: isIconOnly,
                                  isActive: ['/cuentas-corrientes', '/reports', '/checks', '/cash-movements'].contains(currentRoute),
                                  activeColor: Colors.orange.shade700,
                                  menuChildren: [
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Gastos y Mov. de Caja',
                                      icon: canAccessExpenses ? Icons.receipt_long_outlined : Icons.lock_outline,
                                      color: Colors.blue.shade700,
                                      route: '/cash-movements',
                                      permissionKey: AppPermissions.viewExpenses,
                                      isLocked: !canAccessExpenses,
                                      lockedTitle: 'Gestión de Gastos PREMIUM',
                                      lockedFeatures: [
                                        'Registro y control de gastos operativos',
                                        'Movimientos mixtos de caja chica',
                                        'Impacto directo en reportes y arqueos Z',
                                      ],
                                    ),
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Cuentas Corrientes',
                                      icon: canAccessCurrentAccounts ? Icons.account_balance_wallet_outlined : Icons.lock_outline,
                                      color: Colors.orange.shade700,
                                      route: '/cuentas-corrientes',
                                      permissionKey: AppPermissions.viewCustomersAccount,
                                      isLocked: !canAccessCurrentAccounts,
                                      lockedTitle: 'Cuentas Corrientes PREMIUM',
                                      lockedFeatures: [
                                        'Cuentas corrientes y límites de crédito por cliente',
                                        'Pago de tickets específicos',
                                        'Historial de movimientos en tiempo real',
                                        'Alertas de crédito insuficiente',
                                      ],
                                    ),
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Cartera de Cheques',
                                      icon: canAccessChecks ? Icons.account_balance_wallet : Icons.lock_outline,
                                      color: Colors.green.shade700,
                                      route: '/checks',
                                      permissionKey: AppPermissions.viewChecks,
                                      isLocked: !canAccessChecks,
                                      lockedTitle: 'Cartera de Cheques PREMIUM',
                                      lockedFeatures: [
                                        'Recepción de cheques de terceros en POS',
                                        'Gestión y visualización de cartera',
                                        'Alertas de vencimiento y cobro',
                                      ],
                                    ),
                                    // Espacio reservado: Gastos / Caja Chica se inyectará aquí en la Fase 3
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Reportes Gerenciales',
                                      icon: canAccessAdvancedReports ? Icons.bar_chart : Icons.lock_outline,
                                      color: Colors.purple.shade700,
                                      route: '/reports',
                                      permissionKey: AppPermissions.viewReports,
                                      isLocked: !canAccessAdvancedReports,
                                      lockedTitle: 'Reportes Gerenciales PREMIUM',
                                      lockedFeatures: [
                                        'Balance mensual con ganancias y márgenes',
                                        'Exportación a Excel y PDF gerencial',
                                        'Análisis por categoría y período',
                                        'Comparativas de rendimiento',
                                      ],
                                    ),
                                  ],
                                ),

                                // 4. Operaciones / Logística
                                if (settings.features.logistics)
                                  _NavDropdownGroup(
                                    label: 'Operaciones',
                                    icon: Icons.local_shipping_outlined,
                                    isCompact: isCompact,
                                    isIconOnly: isIconOnly,
                                    isActive: ['/delivery-notes'].contains(currentRoute),
                                    activeColor: Colors.green.shade800,
                                    menuChildren: [
                                      _buildMenuItem(
                                        context: context,
                                        label: 'Logística / Remitos',
                                        icon: Icons.airport_shuttle,
                                        color: Colors.green.shade800,
                                        route: '/delivery-notes',
                                        permissionKey: AppPermissions.manageDeliveryNotes,
                                      ),
                                      // Se pueden agregar más módulos aquí como Acopios
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // ── RIGHT: Alertas + Impresora + Usuario ───────────────────────────────────
              Padding(
                padding: EdgeInsets.only(right: screenWidth < 500 ? 6 : 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const UpdateBadgeWidget(),
                    const InventoryAlertsWidget(),
                    const SizedBox(width: 2),
                    // ─ Ícono de Periféricos de Caja (Impresora / Gaveta / Balanza) ─
                    Consumer<LocalTerminalProvider>(
                      builder: (ctx, terminal, _) {
                        final isA4 = terminal.printerFormat == 'a4';
                        final scaleStatus = terminal.scaleComPort.trim().isNotEmpty
                            ? ' • Balanza: ${terminal.scaleComPort}'
                            : '';
                        return Tooltip(
                          message: 'Periféricos de esta Caja (Impresora / Cajón / Balanza)\n'
                              'Formato: ${terminal.printerFormat}'
                              '${isA4 ? ' • Papel: ${terminal.pdfPaperSize.toUpperCase()}' : ''}'
                              '$scaleStatus',
                          child: IconButton(
                            icon: const Icon(Icons.print_rounded, size: 22),
                            color: Colors.blueGrey,
                            visualDensity: screenWidth < 500 ? VisualDensity.compact : VisualDensity.standard,
                            onPressed: () => showTerminalPeripheralsDialog(ctx),
                          ),
                        );
                      },
                    ),
                    if (screenWidth >= 880) ...[
                      LiveClockWidget(compact: screenWidth < 1050),
                      const SizedBox(width: 8),
                    ],
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
        ), // ← cierra Container(height: kToolbarHeight)
        if (bottom != null) bottom!,
          ], // ← cierra Column.children
        ), // ← cierra Column
      ), // ← cierra SafeArea
    ); // ← cierra Material
  }

  // Elemento Directo (Terminal POS)
  Widget _buildNavTab({
    required BuildContext context,
    required String label,
    required String shortLabel,
    required IconData icon,
    required String route,
    required Color activeColor,
    required bool isCompact,
    required bool isIconOnly,
  }) {
    final isActive = currentRoute == route;
    final color = isActive ? activeColor : Colors.blueGrey;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isIconOnly ? 1.0 : 2.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: isActive
              ? Border(bottom: BorderSide(color: activeColor, width: 3))
              : const Border(bottom: BorderSide(color: Colors.transparent, width: 3)),
        ),
        child: Tooltip(
          message: label,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: isIconOnly ? 10 : (isCompact ? 12 : 16),
                vertical: 12,
              ),
              shape: const ContinuousRectangleBorder(),
              foregroundColor: color,
            ),
            onPressed: isActive ? null : () => Navigator.of(context).pushNamedAndRemoveUntil('/pos', (r) => false),
            icon: Icon(icon, size: isActive ? 19 : 17),
            label: isIconOnly ? const SizedBox.shrink() : Text(
              isCompact ? shortLabel : label,
              style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, fontSize: isCompact ? 13 : 14),
            ),
          ),
        ),
      ),
    );
  }

  // Builder para elementos dentro de los Dropdowns
  MenuItemButton _buildMenuItem({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required String route,
    String? permissionKey,
    bool isLocked = false,
    String lockedTitle = 'Módulo PRO',
    List<String> lockedFeatures = const [],
    VoidCallback? onTap,
  }) {
    final isActive = currentRoute == route;
    final displayColor = isLocked ? Colors.grey.shade400 : color;

    return MenuItemButton(
      leadingIcon: Icon(icon, color: displayColor, size: 20),
      onPressed: (isActive && onTap == null)
          ? null
          : () async {
              if (isLocked) {
                _showUpgradeDialog(context, title: lockedTitle, features: lockedFeatures);
                return;
              }
              String? unlockedPin;
              if (permissionKey != null) {
                final resultPin = await AdminPinDialog.verifyAndGetPin(context, action: label, permissionKey: permissionKey);
                if (resultPin == null || !context.mounted) return;
                unlockedPin = resultPin == 'ALREADY_AUTHORIZED' ? null : resultPin;
              }
              if (onTap != null) {
                onTap();
                return;
              }
              Navigator.of(context).pushReplacementNamed(
                route,
                arguments: {'unlocked_pin': unlockedPin},
              );
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isLocked ? Colors.grey.shade600 : Colors.black87,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: displayColor, shape: BoxShape.circle),
              )
            ],
            if (isLocked) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('PREMIUM', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
              )
            ]
          ],
        ),
      ),
    );
  }
}

// ── Widget Group Nav (Dropdown Profesional) ──────────────────────────
class _NavDropdownGroup extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isCompact;
  final bool isIconOnly;
  final bool isActive;
  final Color activeColor;
  final List<Widget> menuChildren;

  const _NavDropdownGroup({
    required this.label,
    required this.icon,
    required this.isCompact,
    required this.isIconOnly,
    required this.isActive,
    required this.activeColor,
    required this.menuChildren,
  });

  @override
  State<_NavDropdownGroup> createState() => _NavDropdownGroupState();
}

class _NavDropdownGroupState extends State<_NavDropdownGroup> {
  final MenuController _controller = MenuController();
  bool _isHoveringButton = false;
  bool _isHoveringMenu = false;

  void _checkClose() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (!_isHoveringButton && !_isHoveringMenu) {
        if (_controller.isOpen) {
          _controller.close();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.menuChildren.isEmpty) return const SizedBox.shrink();

    final color = widget.isActive ? widget.activeColor : Colors.blueGrey;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.isIconOnly ? 1.0 : 2.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: widget.isActive
              ? Border(bottom: BorderSide(color: widget.activeColor, width: 3))
              : const Border(bottom: BorderSide(color: Colors.transparent, width: 3)),
        ),
        child: MenuAnchor(
          controller: _controller,
          style: MenuStyle(
            elevation: WidgetStateProperty.all(8),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            backgroundColor: WidgetStateProperty.all(Colors.white),
          ),
          builder: (context, controller, child) {
            return MouseRegion(
              onEnter: (_) {
                _isHoveringButton = true;
                if (!controller.isOpen) {
                  controller.open();
                }
              },
              onExit: (_) {
                _isHoveringButton = false;
                _checkClose();
              },
              child: widget.isIconOnly
                  ? Tooltip(
                      message: widget.label,
                      waitDuration: const Duration(milliseconds: 500),
                      child: _buildButton(color, controller),
                    )
                  : _buildButton(color, controller),
            );
          },
          menuChildren: [
            MouseRegion(
              onEnter: (_) => _isHoveringMenu = true,
              onExit: (_) {
                _isHoveringMenu = false;
                _checkClose();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.menuChildren,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildButton(Color color, MenuController controller) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: widget.isIconOnly ? 10 : (widget.isCompact ? 10 : 14),
          vertical: 12,
        ),
        shape: const ContinuousRectangleBorder(),
        foregroundColor: color,
      ),
      onPressed: () {
        if (controller.isOpen) {
          controller.close();
        } else {
          controller.open();
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: widget.isActive ? 19 : 17),
          if (!widget.isIconOnly) ...[
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(fontWeight: widget.isActive ? FontWeight.bold : FontWeight.normal, fontSize: 14),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: controller.isOpen ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, size: 16, color: color.withValues(alpha: 0.7)),
            ),
          ]
        ],
      ),
    );
  }
}

// ── Upgrade Dialog (Permanente) ──────────────────────────────────────
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
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Plan Básico activo — Mejorá tu plan para desbloquear', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Con el Plan Premium desbloqueás:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),
                  ...features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF7C3AED), size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(f, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                      ],
                    ),
                  )),
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
                      label: const Text('Contratar Plan Premium por WhatsApp', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      onPressed: () async {
                        final url = Uri.parse('https://wa.me/543704787285?text=Hola,%20quiero%20contratar%20el%20Plan%20Premium%20del%20Sistema%20POS');
                        if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
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

// ── Dialog de Periféricos de Caja (Impresora, Gaveta Registradora y Balanza) ──────
void showTerminalPeripheralsDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _TerminalPeripheralsDialog(),
  );
}

class _TerminalPeripheralsDialog extends StatefulWidget {
  const _TerminalPeripheralsDialog();

  @override
  State<_TerminalPeripheralsDialog> createState() =>
      _TerminalPeripheralsDialogState();
}

class _TerminalPeripheralsDialogState
    extends State<_TerminalPeripheralsDialog> {
  static const String _manualUsbSentinel = '__manual_usb_entry__';

  late TextEditingController _printerNameController;
  late TextEditingController _mpDeviceIdController;
  List<String> _usbPrinters = [];
  List<SerialPortInfo> _serialPorts = [];
  bool _isLoadingPrinters = false;
  bool _isLoadingPorts = false;
  bool _useManualPrinterName = false;

  bool _isTestingPrinter = false;
  bool _isTestingDrawer = false;
  bool _isTestingScale = false;
  bool _isSearchingPointDevices = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<LocalTerminalProvider>();
    _printerNameController = TextEditingController(text: p.printerNameOrIp);
    _mpDeviceIdController = TextEditingController(text: p.mpPointDeviceId);
    _refreshHardwareLists();
  }

  @override
  void dispose() {
    _printerNameController.dispose();
    _mpDeviceIdController.dispose();
    super.dispose();
  }

  Future<void> _refreshHardwareLists() async {
    await Future.wait([
      _loadUsbPrinters(),
      _loadSerialPorts(),
    ]);
  }

  Future<void> _loadUsbPrinters() async {
    if (!mounted) return;
    setState(() => _isLoadingPrinters = true);
    try {
      final list = await ReceiptPrinterService.instance.getAvailableUsbPrinters();
      if (!mounted) return;
      setState(() {
        _usbPrinters = list;
        _isLoadingPrinters = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingPrinters = false);
    }
  }

  Future<void> _loadSerialPorts() async {
    if (!mounted) return;
    setState(() => _isLoadingPorts = true);
    try {
      final ports = ScaleSerialService.instance.getAvailablePorts();
      if (!mounted) return;
      setState(() {
        _serialPorts = ports;
        _isLoadingPorts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingPorts = false);
    }
  }

  void _setFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  Future<void> _handleTestPrinter(LocalTerminalProvider p) async {
    setState(() {
      _isTestingPrinter = true;
      _statusMessage = null;
    });
    try {
      await ReceiptPrinterService.instance.printTestTicket(p);
      _setFeedback('Ticket de prueba enviado correctamente a "${p.printerNameOrIp}".');
    } catch (e) {
      _setFeedback(
        'Error al imprimir: ${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isTestingPrinter = false);
    }
  }

  Future<void> _handleTestDrawer(LocalTerminalProvider p) async {
    setState(() {
      _isTestingDrawer = true;
      _statusMessage = null;
    });
    try {
      await ReceiptPrinterService.instance.openCashDrawer(p, throwOnError: true);
      _setFeedback('Pulso de apertura RJ-11 enviado a la gaveta a través de "${p.printerNameOrIp}".');
    } catch (e) {
      _setFeedback(
        'No se pudo abrir el cajón: ${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isTestingDrawer = false);
    }
  }

  Future<void> _handleSearchPointDevices(LocalTerminalProvider p) async {
    setState(() {
      _isSearchingPointDevices = true;
      _statusMessage = null;
    });

    try {
      final settingsProvider = context.read<SettingsProvider>();
      final devices = await settingsProvider.fetchMpPointDevices();
      if (!mounted) return;

      if (devices.isEmpty) {
        _setFeedback(
          'No se encontraron terminales Point en la cuenta de Mercado Pago.',
          isError: true,
        );
        return;
      }

      final selectedDevice = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.point_of_sale, color: Color(0xFF009EE3)),
              SizedBox(width: 8),
              Text(
                'Seleccionar Point para esta Caja',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: devices.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final d = devices[i];
                final id = d['id']?.toString() ?? '';
                final posId = d['pos_id']?.toString() ?? '';
                final mode = d['operating_mode']?.toString().toUpperCase() ?? 'PDV';
                final isSelected = p.mpPointDeviceId == id;

                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.contactless_rounded,
                    color: isSelected ? const Color(0xFF009EE3) : Colors.grey,
                  ),
                  title: Text(
                    id,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? const Color(0xFF009EE3) : Colors.black87,
                    ),
                  ),
                  subtitle: Text('Modo: $mode ${posId.isNotEmpty ? "• Caja MP #$posId" : ""}'),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xFF009EE3), size: 20)
                      : null,
                  onTap: () => Navigator.of(dialogCtx).pop(d),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(null),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

      if (selectedDevice != null && mounted) {
        final newId = selectedDevice['id']?.toString() ?? '';
        if (newId.isNotEmpty) {
          _mpDeviceIdController.text = newId;
          await p.setMpPointDeviceId(newId);
          _setFeedback('Point "$newId" asignado a esta Caja.');
        }
      }
    } catch (e) {
      _setFeedback('Error buscando terminales Point: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSearchingPointDevices = false);
      }
    }
  }

  Future<void> _handleTestScale(LocalTerminalProvider p) async {
    final port = p.scaleComPort.trim();
    if (port.isEmpty) {
      _setFeedback('Seleccione primero un puerto COM para la balanza.', isError: true);
      return;
    }
    setState(() {
      _isTestingScale = true;
      _statusMessage = 'Leyendo balanza en $port...';
      _statusIsError = false;
    });
    try {
      final res = await ScaleSerialService.instance.readWeight(port);
      if (res.success && res.weightKg != null) {
        _setFeedback(
          'Lectura exitosa en $port: ${res.weightKg!.toStringAsFixed(3)} Kg',
          isError: false,
        );
      } else {
        _setFeedback(
          res.errorMessage ?? 'No se pudo leer el peso en $port.',
          isError: true,
        );
      }
    } catch (e) {
      _setFeedback('Error al probar balanza en $port: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isTestingScale = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalTerminalProvider>(
      builder: (context, p, _) {
        final savedPrinter = p.printerNameOrIp.trim();
        final savedComPort = p.scaleComPort.trim();

        // Armar opciones de impresora USB garantizando que el valor guardado siempre exista
        final List<DropdownMenuItem<String>> usbPrinterItems = [
          const DropdownMenuItem(
            value: '',
            child: Text('Seleccione una impresora de Windows...'),
          ),
        ];
        final Set<String> addedPrinters = {''};
        for (final name in _usbPrinters) {
          if (addedPrinters.add(name)) {
            usbPrinterItems.add(
              DropdownMenuItem(
                value: name,
                child: Text(name, overflow: TextOverflow.ellipsis),
              ),
            );
          }
        }
        if (savedPrinter.isNotEmpty && !addedPrinters.contains(savedPrinter)) {
          addedPrinters.add(savedPrinter);
          usbPrinterItems.add(
            DropdownMenuItem(
              value: savedPrinter,
              child: Text(
                '$savedPrinter (Guardada)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }
        usbPrinterItems.add(
          const DropdownMenuItem(
            value: _manualUsbSentinel,
            child: Text('✏️ Escribir nombre manualmente...'),
          ),
        );

        final String selectedUsbDropdownValue = _useManualPrinterName
            ? _manualUsbSentinel
            : (addedPrinters.contains(savedPrinter) ? savedPrinter : '');

        // Armar opciones de puerto COM de balanza garantizando que el puerto guardado siempre exista
        final List<DropdownMenuItem<String>> scalePortItems = [
          const DropdownMenuItem(
            value: '',
            child: Text('Sin balanza (Ingreso manual de peso)'),
          ),
        ];
        final Set<String> addedPorts = {''};
        for (final info in _serialPorts) {
          if (addedPorts.add(info.portName)) {
            scalePortItems.add(
              DropdownMenuItem(
                value: info.portName,
                child: Text(
                  info.displayName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }
        }
        if (savedComPort.isNotEmpty && !addedPorts.contains(savedComPort)) {
          addedPorts.add(savedComPort);
          scalePortItems.add(
            DropdownMenuItem(
              value: savedComPort,
              child: Text(
                '$savedComPort (Guardado - No detectado ahora)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }

        final bool canTestThermal = p.printerConnection != 'none' &&
            p.printerFormat != 'a4' &&
            savedPrinter.isNotEmpty;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.print_rounded, color: Colors.blue),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Periféricos de esta Caja',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              IconButton(
                tooltip: 'Refrescar dispositivos conectados',
                icon: (_isLoadingPrinters || _isLoadingPorts)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.blueGrey),
                onPressed: (_isLoadingPrinters || _isLoadingPorts)
                    ? null
                    : _refreshHardwareLists,
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── SECCIÓN 1: IMPRESORA ──
                  _buildSectionHeader(
                    icon: Icons.receipt_long_rounded,
                    title: '1. Impresora de Tickets / Comprobantes',
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Formato de Impresión',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              key: ValueKey('fmt_${p.printerFormat}'),
                              initialValue: p.printerFormat,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'thermal_80',
                                  child: Text('Térmica 80mm'),
                                ),
                                DropdownMenuItem(
                                  value: 'thermal_58',
                                  child: Text('Térmica 58mm'),
                                ),
                                DropdownMenuItem(
                                  value: 'a4',
                                  child: Text('Hoja A4 / Carta'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) p.setPrinterFormat(v);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tipo de Conexión',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              key: ValueKey('conn_${p.printerConnection}'),
                              initialValue: p.printerConnection,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'none',
                                  child: Text('Desactivada'),
                                ),
                                DropdownMenuItem(
                                  value: 'usb',
                                  child: Text('USB (Windows)'),
                                ),
                                DropdownMenuItem(
                                  value: 'network',
                                  child: Text('Red LAN / Wi-Fi (IP)'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _useManualPrinterName = false);
                                  p.setPrinterConnection(v);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (p.printerFormat == 'a4') ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Tamaño de Hoja PDF:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: ValueKey('paper_${p.pdfPaperSize}'),
                      initialValue: p.pdfPaperSize,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'a4',
                          child: Text('A4 (Predeterminado)'),
                        ),
                        DropdownMenuItem(
                          value: 'letter',
                          child: Text('Carta (Letter)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) p.setPdfPaperSize(v);
                      },
                    ),
                  ],
                  if (p.printerConnection == 'usb') ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Impresora Instalada en Windows:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: ValueKey('usb_sel_$selectedUsbDropdownValue'),
                      initialValue: selectedUsbDropdownValue,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: usbPrinterItems,
                      onChanged: (v) {
                        if (v == null) return;
                        if (v == _manualUsbSentinel) {
                          setState(() => _useManualPrinterName = true);
                        } else {
                          setState(() => _useManualPrinterName = false);
                          _printerNameController.text = v;
                          p.setPrinterNameOrIp(v);
                        }
                      },
                    ),
                    if (_useManualPrinterName || _usbPrinters.isEmpty) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _printerNameController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          labelText: 'Nombre exacto de la impresora en Windows',
                          hintText: 'Ej: POS-80 o EPSON TM-T20II',
                        ),
                        onChanged: (v) => p.setPrinterNameOrIp(v),
                      ),
                    ],
                  ] else if (p.printerConnection == 'network') ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Dirección IP de la Impresora (Puerto 9100):',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _printerNameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: 'Ej: 192.168.1.100',
                      ),
                      onChanged: (v) => p.setPrinterNameOrIp(v),
                    ),
                  ],
                  if (p.printerConnection != 'none' && p.printerFormat != 'a4') ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: (!canTestThermal || _isTestingPrinter)
                            ? null
                            : () => _handleTestPrinter(p),
                        icon: _isTestingPrinter
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined, size: 18),
                        label: const Text('Probar Ticket'),
                      ),
                    ),
                  ],

                  const Divider(height: 26),

                  // ── SECCIÓN 2: GAVETA DE DINERO (RJ-11) ──
                  _buildSectionHeader(
                    icon: Icons.point_of_sale_rounded,
                    title: '2. Caja Registradora / Gaveta de Dinero (RJ-11)',
                    color: Colors.teal.shade700,
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Abrir cajón automáticamente al cobrar',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    subtitle: const Text(
                      'Envía el pulso eléctrico por el cable telefónico (RJ-11) conectado detrás de la impresora térmica.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: p.autoOpenCashDrawer,
                    onChanged: (val) => p.setAutoOpenCashDrawer(val),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: (p.printerConnection == 'none' ||
                              savedPrinter.isEmpty ||
                              _isTestingDrawer)
                          ? null
                          : () => _handleTestDrawer(p),
                      icon: _isTestingDrawer
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_rounded, size: 18),
                      label: const Text('Probar Abrir Cajón'),
                    ),
                  ),

                  const Divider(height: 26),

                  // ── SECCIÓN 3: BALANZA ELECTRÓNICA (COM / USB) ──
                  _buildSectionHeader(
                    icon: Icons.scale_rounded,
                    title: '3. Balanza Electrónica (Cable Serie / USB-COM)',
                    color: Colors.indigo.shade700,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Puerto COM de la Balanza (Systel, Kretz, Moretti, etc.):',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: ValueKey('scale_port_$savedComPort'),
                    initialValue: addedPorts.contains(savedComPort) ? savedComPort : '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: scalePortItems,
                    onChanged: (v) {
                      if (v != null) {
                        p.setScaleComPort(v);
                        _setFeedback(
                          v.isEmpty
                              ? 'Balanza desactivada (modo ingreso manual).'
                              : 'Puerto $v seleccionado para la balanza.',
                        );
                      }
                    },
                  ),
                  if (savedComPort.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _isTestingScale ? null : () => _handleTestScale(p),
                        icon: _isTestingScale
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.monitor_weight_outlined, size: 18),
                        label: const Text('Probar Lectura de Peso'),
                      ),
                    ),
                  ],

                  const Divider(height: 26),

                  // ── SECCIÓN 4: POSNET MERCADO PAGO POINT (POR CAJA) ──
                  _buildSectionHeader(
                    icon: Icons.credit_card_rounded,
                    title: '4. Posnet Mercado Pago Point (Opcional por Caja)',
                    color: const Color(0xFF009EE3),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Dispositivo Point asignado a este puesto de venta:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Si se deja vacío, se utilizará el terminal Point predeterminado configurado en Ajustes Generales.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _mpDeviceIdController,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            isDense: true,
                            hintText: 'Ej: PAX_A910__12345678 (o vacío)',
                            prefixIcon: const Icon(
                              Icons.point_of_sale,
                              size: 20,
                              color: Color(0xFF009EE3),
                            ),
                            suffixIcon: p.mpPointDeviceId.isNotEmpty
                                ? IconButton(
                                    tooltip: 'Limpiar (Usar predeterminado)',
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _mpDeviceIdController.clear();
                                      p.setMpPointDeviceId('');
                                      _setFeedback('Se usará el Point predeterminado de la empresa.');
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (val) {
                            p.setMpPointDeviceId(val);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF009EE3),
                          side: const BorderSide(color: Color(0xFF009EE3)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onPressed: _isSearchingPointDevices
                            ? null
                            : () => _handleSearchPointDevices(p),
                        icon: _isSearchingPointDevices
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF009EE3),
                                ),
                              )
                            : const Icon(Icons.search, size: 18),
                        label: const Text('Buscar Point'),
                      ),
                    ],
                  ),

                  // ── MENSAJE DE ESTADO / FEEDBACK EN VIVO ──
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _statusIsError
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _statusIsError
                              ? Colors.red.shade200
                              : Colors.green.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _statusIsError
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            color: _statusIsError
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _statusIsError
                                    ? Colors.red.shade800
                                    : Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Estos ajustes se guardan automáticamente y aplican solo a esta computadora (Caja).',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class UpdateBadgeWidget extends StatelessWidget {
  const UpdateBadgeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateCheckResult?>(
      valueListenable: UpdateService.updateNotifier,
      builder: (context, result, child) {
        if (result == null || !result.hasAny) return const SizedBox.shrink();

        final isCritical = (result.frontendUpdate?.isCritical == true) || 
                           (result.backendUpdate?.isCritical == true);

        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Tooltip(
            message: '¡Nueva actualización disponible!',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                final update = result.frontendUpdate ?? result.backendUpdate!;
                showDialog(
                  context: context,
                  barrierDismissible: !update.isCritical,
                  builder: (_) => UpdateDialog(updateInfo: update),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isCritical ? Colors.red.shade50 : Colors.purple.shade50,
                  border: Border.all(color: isCritical ? Colors.red : Colors.purple.shade300),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: (isCritical ? Colors.red : Colors.purple).withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.system_update_rounded,
                      size: 16,
                      color: isCritical ? Colors.red.shade700 : Colors.purple.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Actualizar',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isCritical ? Colors.red.shade800 : Colors.purple.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
