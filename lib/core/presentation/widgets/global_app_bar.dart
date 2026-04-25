import 'package:flutter/material.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/shared_user_menu.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/inventory_alerts_widget.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
            SizedBox(
              height: kToolbarHeight,
              child: Row(
            children: [
              // ── LEFT: Logo + Empresa ──────────────────────────────────────
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
                    if (!hideCompanyName) ...[
                      const SizedBox(width: 8),
                      Consumer<SettingsProvider>(
                        builder: (context, settings, _) {
                          final name = settings.settings?.companyName ?? title;
                          return ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Text(
                              name.isNotEmpty ? name : title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ],
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

                                // 2. Gestión (Ventas + Catálogo)
                                _NavDropdownGroup(
                                  label: 'Gestión',
                                  icon: Icons.dashboard_customize_outlined,
                                  isCompact: isCompact,
                                  isIconOnly: isIconOnly,
                                  isActive: ['/sales-history', '/catalog'].contains(currentRoute),
                                  activeColor: Colors.blueAccent,
                                  menuChildren: [
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Registro de Ventas',
                                      icon: Icons.receipt_long_outlined,
                                      color: Colors.blueAccent,
                                      route: '/sales-history',
                                      permissionKey: 'view_global_history',
                                    ),
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Catálogo de Productos',
                                      icon: Icons.inventory_2_outlined,
                                      color: Colors.deepPurple,
                                      route: '/catalog',
                                      permissionKey: 'manage_catalog',
                                    ),
                                  ],
                                ),

                                // 3. Finanzas (Ctas Ctes, Presupuestos, Reportes)
                                _NavDropdownGroup(
                                  label: 'Finanzas',
                                  icon: Icons.account_balance_outlined,
                                  isCompact: isCompact,
                                  isIconOnly: isIconOnly,
                                  isActive: ['/cuentas-corrientes', '/quotes', '/reports', '/checks'].contains(currentRoute),
                                  activeColor: Colors.orange.shade700,
                                  menuChildren: [
                                    if (canAccessQuotes)
                                      _buildMenuItem(
                                        context: context,
                                        label: 'Presupuestos',
                                        icon: Icons.description_outlined,
                                        color: Colors.indigo.shade700,
                                        route: '/quotes',
                                      ),
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Cuentas Corrientes',
                                      icon: canAccessCurrentAccounts ? Icons.account_balance_wallet_outlined : Icons.lock_outline,
                                      color: Colors.orange.shade700,
                                      route: '/cuentas-corrientes',
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
                                      isLocked: !canAccessChecks,
                                      lockedTitle: 'Cartera de Cheques PREMIUM',
                                      lockedFeatures: [
                                        'Recepción de cheques de terceros en POS',
                                        'Gestión y visualización de cartera',
                                        'Alertas de vencimiento y cobro',
                                      ],
                                    ),
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Reportes Gerenciales',
                                      icon: canAccessAdvancedReports ? Icons.bar_chart : Icons.lock_outline,
                                      color: Colors.purple.shade700,
                                      route: '/reports',
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
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const InventoryAlertsWidget(),
                    const SizedBox(width: 2),
                    // ─ Ícono de Ajustes de Impresión (siempre visible en todas las pantallas) ─
                    Consumer<LocalTerminalProvider>(
                      builder: (ctx, terminal, _) {
                        final isA4 = terminal.printerFormat == 'a4';
                        return Tooltip(
                          message: 'Ajustes de Impresión\n'
                              'Formato: ${terminal.printerFormat}'
                              '${isA4 ? ' • Papel: ${terminal.pdfPaperSize.toUpperCase()}' : ''}',
                          child: IconButton(
                            icon: const Icon(Icons.print_rounded, size: 22),
                            color: Colors.blueGrey,
                            onPressed: () => _showPrinterSettingsDialog(ctx),
                          ),
                        );
                      },
                    ),
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
        ), // ← cierra SizedBox(height: kToolbarHeight)
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
  }) {
    final isActive = currentRoute == route;
    final displayColor = isLocked ? Colors.grey.shade400 : color;

    return MenuItemButton(
      leadingIcon: Icon(icon, color: displayColor, size: 20),
      onPressed: isActive
          ? null
          : () async {
              if (isLocked) {
                _showUpgradeDialog(context, title: lockedTitle, features: lockedFeatures);
                return;
              }
              if (permissionKey != null) {
                final authorized = await AdminPinDialog.verify(context, action: label, permissionKey: permissionKey);
                if (!authorized || !context.mounted) return;
              }
              Navigator.of(context).pushReplacementNamed(route);
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
              child: Icon(Icons.expand_more, size: 16, color: color.withOpacity(0.7)),
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
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Plan Básico activo — Mejorá tu plan para desbloquear', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.80), fontSize: 12)),
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

// ── Dialog de Ajustes de Impresión (Accesible desde toda la app) ──────
void _showPrinterSettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.print_rounded, color: Colors.blue),
          SizedBox(width: 8),
          Text('Ajustes de Impresión'),
        ],
      ),
      content: Consumer<LocalTerminalProvider>(
        builder: (context, p, _) => SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Formato de Impresión:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: p.printerFormat,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'thermal_80', child: Text('Térmica 80mm')),
                    DropdownMenuItem(value: 'thermal_58', child: Text('Térmica 58mm')),
                    DropdownMenuItem(value: 'a4', child: Text('Hoja Completa (Impresora normal)')),
                  ],
                  onChanged: (v) { if (v != null) p.setPrinterFormat(v); },
                ),
                if (p.printerFormat == 'a4') ...[
                  const SizedBox(height: 16),
                  const Text('Tamaño de Papel:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: p.pdfPaperSize,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'a4', child: Text('A4 (Predeterminado)')),
                      DropdownMenuItem(value: 'letter', child: Text('Carta (Letter)')),
                    ],
                    onChanged: (v) { if (v != null) p.setPdfPaperSize(v); },
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Tipo de Conexión:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: p.printerConnection,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('Desactivada')),
                    DropdownMenuItem(value: 'usb', child: Text('USB / Serial')),
                    DropdownMenuItem(value: 'network', child: Text('Red LAN / WiFi')),
                  ],
                  onChanged: (v) { if (v != null) p.setPrinterConnection(v); },
                ),
                const SizedBox(height: 16),
                const Text('Nombre de Impresora o IP:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: p.printerNameOrIp,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(), isDense: true,
                    hintText: 'Ej: POS-58 o 192.168.1.100',
                  ),
                  onChanged: (v) => p.setPrinterNameOrIp(v),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Estos ajustes se guardan automáticamente y aplican solo a esta terminal física.',
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
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
      ],
    ),
  );
}
