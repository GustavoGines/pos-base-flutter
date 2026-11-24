import 'dart:async';
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
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/cash_movements/providers/cash_movement_provider.dart';
import 'package:frontend_desktop/features/sales_history/presentation/providers/sales_history_provider.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';


class GlobalAppBar extends StatelessWidget implements PreferredSizeWidget {
  static const Color kNavBgStart = Color(0xFF121C33);
  static const Color kNavBgMid = Color(0xFF16233F);
  static const Color kNavBorderBottom = Color(0xFF1E2D4A);
  static const Color kNavDropdownBg = Color(0xFF16233F);
  static const Color kNavDropdownBorder = Color(0xFF2A3F66);
  static const Color kNavDropdownHover = Color(0xFF1E2F52);
  static const Color kBrandEmerald = Color(0xFF10B981);
  static const Color kBrandMint = Color(0xFF34D399);
  static const Color kBrandAmber = Color(0xFFF59E0B);
  static const Color kBrandAmberLight = Color(0xFFFBBF24);

  /// Rutas de primer nivel que ya se muestran resaltadas en la barra central
  /// (Terminal POS, Gestión • ..., Finanzas • ..., Operaciones • ...).
  /// Nunca deben mostrar breadcrumb al lado del nombre de la empresa para evitar
  /// redundancia visual y recorte de espacio en la barra de navegación.
  static const Set<String> kPrimaryNavRoutes = {
    '/pos',
    '/sales-history',
    '/quotes',
    '/catalog',
    '/suppliers',
    '/cash-movements',
    '/cuentas-corrientes',
    '/checks',
    '/reports',
    '/delivery-notes',
  };

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
    this.title = 'Caja4U',
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
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      color: kNavBgStart,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kNavBgStart, kNavBgMid, kNavBgStart],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                border: Border(
                  bottom: BorderSide(color: kNavBorderBottom, width: 1.0),
                ),
              ),
              height: kToolbarHeight,
              child: Row(
            children: [
              // ── LEFT: Botón Volver + Logo + Empresa + Breadcrumb ───────────
              Padding(
                padding: EdgeInsets.only(left: screenWidth < 500 ? 6 : 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showBackButton) ...[
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        tooltip: 'Volver',
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      SizedBox(width: screenWidth < 500 ? 6 : 8),
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
                        final isPrimaryNavRoute =
                            kPrimaryNavRoutes.contains(currentRoute);
                        final showBreadcrumb = !hideCompanyName &&
                            screenWidth >= 1100 &&
                            !isPrimaryNavRoute &&
                            name.isNotEmpty &&
                            title.isNotEmpty &&
                            title != 'Caja4U' &&
                            title != 'Sistema POS' &&
                            title != name;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 9),
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: kBrandEmerald.withValues(alpha: 0.35),
                                  width: 1,
                                ),
                              ),
                              child: hasValidLogo
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.network(
                                        logoUrl!,
                                        width: 26,
                                        height: 26,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => ClipRRect(
                                          borderRadius: BorderRadius.circular(5),
                                          child: Image.asset(
                                            'assets/app_logo.png',
                                            width: 26,
                                            height: 26,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.asset(
                                        'assets/app_logo.png',
                                        width: 26,
                                        height: 26,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(
                                          Icons.point_of_sale_rounded,
                                          color: kBrandMint,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                            ),
                            if (!hideCompanyName) ...[
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: showBreadcrumb ? 105 : 140,
                                ),
                                child: Text(
                                  name.isNotEmpty ? name : title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (showBreadcrumb) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: Colors.white38,
                                ),
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: title,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kBrandEmerald.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: kBrandEmerald.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: screenWidth >= 1400 ? 210 : 170,
                                      ),
                                      child: Text(
                                        title,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: kBrandMint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
                    final isCompact = w < 640;

                    final String? gestionSubLabel = switch (currentRoute) {
                      '/sales-history' => 'Ventas',
                      '/quotes' => 'Presupuestos',
                      '/catalog' => 'Catálogo',
                      '/suppliers' => 'Proveedores',
                      _ => null,
                    };
                    final String? finanzasSubLabel = switch (currentRoute) {
                      '/cash-movements' => 'Gastos',
                      '/cuentas-corrientes' => 'Ctas. Ctes.',
                      '/checks' => 'Cheques',
                      '/reports' => 'Reportes',
                      _ => null,
                    };
                    final String? operacionesSubLabel =
                        currentRoute == '/delivery-notes' ? 'Logística' : null;

                    return Consumer<SettingsProvider>(
                      builder: (context, settings, _) {
                        final bool canAccessPos = settings.features.fastPos;
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
                                    isCompact: isCompact,
                                    isIconOnly: isIconOnly,
                                  ),

                                // 2. Gestión (Ventas, Presupuestos, Catálogo, Proveedores)
                                _NavDropdownGroup(
                                  label: 'Gestión',
                                  activeSubLabel: gestionSubLabel,
                                  icon: Icons.dashboard_customize_outlined,
                                  isCompact: isCompact,
                                  isIconOnly: isIconOnly,
                                  isActive: ['/sales-history', '/catalog', '/quotes', '/suppliers'].contains(currentRoute),
                                  menuChildren: [
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Registro de Ventas',
                                      icon: Icons.receipt_long_outlined,
                                      color: const Color(0xFF60A5FA),
                                      route: '/sales-history',
                                    ),
                                    if (canAccessQuotes)
                                      _buildMenuItem(
                                        context: context,
                                        label: 'Presupuestos',
                                        icon: Icons.description_outlined,
                                        color: const Color(0xFF818CF8),
                                        route: '/quotes',
                                        permissionKey: AppPermissions.manageQuotes,
                                      ),
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Catálogo de Productos',
                                      icon: Icons.inventory_2_outlined,
                                      color: const Color(0xFFA78BFA),
                                      route: '/catalog',
                                      permissionKey: AppPermissions.manageCatalog,
                                    ),
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Proveedores',
                                      icon: canAccessSuppliers ? Icons.local_shipping_outlined : Icons.lock_outline,
                                      color: const Color(0xFFFBBF24),
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
                                  activeSubLabel: finanzasSubLabel,
                                  icon: Icons.account_balance_outlined,
                                  isCompact: isCompact,
                                  isIconOnly: isIconOnly,
                                  isActive: ['/cuentas-corrientes', '/reports', '/checks', '/cash-movements'].contains(currentRoute),
                                  menuChildren: [
                                    _buildMenuItem(
                                      context: context,
                                      label: 'Gastos y Mov. de Caja',
                                      icon: canAccessExpenses ? Icons.receipt_long_outlined : Icons.lock_outline,
                                      color: const Color(0xFF38BDF8),
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
                                      color: const Color(0xFFFB923C),
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
                                      color: const Color(0xFF34D399),
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
                                      icon: Icons.bar_chart,
                                      color: const Color(0xFFC084FC),
                                      route: '/reports',
                                      permissionKey: AppPermissions.viewReports,
                                      isLocked: false,
                                    ),
                                  ],
                                ),

                                // 4. Operaciones / Logística
                                if (settings.features.logistics)
                                  _NavDropdownGroup(
                                    label: 'Operaciones',
                                    activeSubLabel: operacionesSubLabel,
                                    icon: Icons.local_shipping_outlined,
                                    isCompact: isCompact,
                                    isIconOnly: isIconOnly,
                                    isActive: ['/delivery-notes'].contains(currentRoute),
                                    menuChildren: [
                                      _buildMenuItem(
                                        context: context,
                                        label: 'Logística / Remitos',
                                        icon: Icons.airport_shuttle,
                                        color: const Color(0xFF4ADE80),
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

              // ── RIGHT: Acciones + Alertas | Caja Activa + Reloj + Usuario ──
              Padding(
                padding: EdgeInsets.only(right: screenWidth < 500 ? 6 : 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const UpdateBadgeWidget(),
                    if (extraAction != null) ...[
                      extraAction!,
                      const SizedBox(width: 6),
                    ],
                    const InventoryAlertsWidget(),
                    if (screenWidth >= 640)
                      Container(
                        width: 1,
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: Colors.white.withValues(alpha: 0.12),
                      )
                    else
                      const SizedBox(width: 4),
                    // ── MC-01: Badge de Caja Activa y Turno ────────────────────────
                    Consumer<SettingsProvider>(
                      builder: (ctx, settingsProv, _) {
                        final cashProv = ctx.watch<CashRegisterProvider?>();
                        dynamic shift;
                        int? activeRegId;
                        String regName = '';
                        try {
                          shift = cashProv?.currentShift;
                          final assignedId = settingsProv.assignedRegisterId;
                          activeRegId = shift?.cashRegisterId ??
                              (assignedId > 0 ? assignedId : cashProv?.activeRegisterId);
                          regName = shift?.cashRegisterName ?? '';
                          if (regName.trim().isEmpty && activeRegId != null) {
                            if (cashProv?.availableRegisters != null) {
                              final match = cashProv!.availableRegisters!
                                  .where((r) => r.id == activeRegId)
                                  .firstOrNull;
                              if (match != null) regName = match.name;
                            } else if (cashProv != null && !cashProv.isLoading) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (ctx.mounted && cashProv.availableRegisters == null && !cashProv.isLoading) {
                                  cashProv.loadRegisters();
                                }
                              });
                            }
                          }
                        } catch (_) {
                          shift = null;
                        }
                        final isOpen = shift != null && shift.isOpen;
                        if (regName.trim().isEmpty) {
                          regName = activeRegId != null ? 'Caja #$activeRegId' : 'Caja Principal';
                        }

                        final compactBadge = screenWidth < 720;
                        final isVeryNarrow = screenWidth < 360;
                        final badgeColor = isOpen ? kBrandMint : kBrandAmberLight;
                        final badgeBg = isOpen
                            ? kBrandEmerald.withValues(alpha: 0.15)
                            : kBrandAmber.withValues(alpha: 0.16);
                        final badgeBorder = isOpen
                            ? kBrandEmerald.withValues(alpha: 0.45)
                            : kBrandAmber.withValues(alpha: 0.45);

                        return Tooltip(
                          message: isOpen
                              ? 'Terminal operando en: $regName\nTurno abierto #${shift.id}${shift.userName != null ? ' (${shift.userName})' : ''}\n(Clic para ver estado de Terminal y Periféricos)'
                              : 'Terminal en: $regName (Sin turno abierto)\n(Clic para ver estado de Terminal y Periféricos)',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: cashProv != null
                                ? () => showTerminalPeripheralsDialog(ctx, initialTab: 0)
                                : null,
                            child: Container(
                              key: const Key('global_app_bar_register_badge'),
                              height: 34,
                              padding: EdgeInsets.symmetric(
                                horizontal: isVeryNarrow ? 6 : (compactBadge ? 9 : 12),
                              ),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: badgeBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isOpen && !isVeryNarrow) ...[
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: kBrandMint,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Icon(
                                    isOpen ? Icons.point_of_sale_rounded : Icons.lock_clock_outlined,
                                    size: 15,
                                    color: badgeColor,
                                  ),
                                  if (!isVeryNarrow) ...[
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: compactBadge
                                            ? (screenWidth < 400 ? 55 : 90)
                                            : 155,
                                      ),
                                      child: Text(
                                        compactBadge
                                            ? regName
                                            : (isOpen ? '$regName • T#${shift.id}' : '$regName (Cerrada)'),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isOpen ? Colors.white : kBrandAmberLight,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (screenWidth >= 880) ...[
                      const SizedBox(width: 6),
                      LiveClockWidget(compact: screenWidth < 1440),
                    ],
                    SizedBox(width: screenWidth < 500 ? 4 : 6),
                    const SharedUserMenu(),
                  ],
                ),
              ),
            ],
          ),
        ), // ← cierra Container(height: kToolbarHeight)
        if (bottom != null)
          Material(
            color: Colors.white,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: bottom!,
              ),
            ),
          ),
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
    required bool isCompact,
    required bool isIconOnly,
  }) {
    final isActive = currentRoute == route;
    final iconColor = isActive ? kBrandMint : const Color(0xFF94A3B8);
    final textColor = isActive ? Colors.white : const Color(0xFFCBD5E1);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isIconOnly ? 2.0 : 3.0),
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 36,
          decoration: BoxDecoration(
            color: isActive ? kBrandEmerald.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? kBrandEmerald.withValues(alpha: 0.45) : Colors.transparent,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 36,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.symmetric(
                      horizontal: isIconOnly ? 10 : (isCompact ? 11 : 14),
                      vertical: 0,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    foregroundColor: textColor,
                    overlayColor: Colors.white.withValues(alpha: 0.08),
                  ),
                  onPressed: isActive
                      ? null
                      : () => Navigator.of(context).pushNamedAndRemoveUntil('/pos', (r) => false),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 17, color: iconColor),
                      if (!isIconOnly) ...[
                        const SizedBox(width: 6),
                        Text(
                          isCompact ? shortLabel : label,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                            fontSize: isCompact ? 13 : 13.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (isActive)
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 22,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: kBrandMint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Builder para elementos dentro de los Dropdowns
  Widget _buildMenuItem({
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
    final displayColor = isLocked ? const Color(0xFF94A3B8) : color;
    final badgeIconColor = isActive ? GlobalAppBar.kBrandMint : displayColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      child: MenuItemButton(
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          ),
          minimumSize: WidgetStateProperty.all(const Size(230, 44)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
              side: isActive
                  ? BorderSide(
                      color: GlobalAppBar.kBrandMint.withValues(alpha: 0.30),
                    )
                  : BorderSide.none,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (isActive) {
              return GlobalAppBar.kBrandEmerald.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return GlobalAppBar.kNavDropdownHover;
            }
            return Colors.transparent;
          }),
          overlayColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.05),
          ),
        ),
        leadingIcon: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isActive
                ? GlobalAppBar.kBrandEmerald.withValues(alpha: 0.22)
                : (isLocked
                    ? Colors.white.withValues(alpha: 0.06)
                    : displayColor.withValues(alpha: 0.16)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? GlobalAppBar.kBrandMint.withValues(alpha: 0.45)
                  : (isLocked
                      ? Colors.white.withValues(alpha: 0.12)
                      : displayColor.withValues(alpha: 0.30)),
            ),
          ),
          child: Icon(icon, color: badgeIconColor, size: 17),
        ),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                color: isActive
                    ? GlobalAppBar.kBrandMint
                    : (isLocked
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFFF1F5F9)),
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: GlobalAppBar.kBrandMint,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: GlobalAppBar.kBrandMint.withValues(alpha: 0.55),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
            if (isLocked) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GlobalAppBar.kBrandAmber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: GlobalAppBar.kBrandAmber.withValues(alpha: 0.45),
                  ),
                ),
                child: const Text(
                  'PREMIUM',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: GlobalAppBar.kBrandAmberLight,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Widget Group Nav (Dropdown Profesional) ──────────────────────────
class _NavDropdownGroup extends StatefulWidget {
  final String label;
  final String? activeSubLabel;
  final IconData icon;
  final bool isCompact;
  final bool isIconOnly;
  final bool isActive;
  final List<Widget> menuChildren;

  const _NavDropdownGroup({
    required this.label,
    this.activeSubLabel,
    required this.icon,
    required this.isCompact,
    required this.isIconOnly,
    required this.isActive,
    required this.menuChildren,
  });

  @override
  State<_NavDropdownGroup> createState() => _NavDropdownGroupState();
}

class _NavDropdownGroupState extends State<_NavDropdownGroup> {
  final MenuController _controller = MenuController();
  Timer? _openTimer;
  Timer? _closeTimer;
  bool _isHoveringButton = false;
  bool _isHoveringMenu = false;

  bool get _canMutateMenu =>
      mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    super.dispose();
  }

  void _scheduleOpen() {
    _closeTimer?.cancel();
    _openTimer?.cancel();
    _openTimer = Timer(const Duration(milliseconds: 90), () {
      if (!_canMutateMenu || !_isHoveringButton) return;
      if (!_controller.isOpen) {
        _controller.open();
      }
    });
  }

  void _checkClose() {
    if (!_isHoveringButton) {
      _openTimer?.cancel();
    }
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 150), () {
      if (!_canMutateMenu) return;
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

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.isIconOnly ? 2.0 : 3.0),
      child: MenuAnchor(
        controller: _controller,
        style: MenuStyle(
          elevation: WidgetStateProperty.all(14),
          shadowColor: WidgetStateProperty.all(const Color(0x73020617)),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          padding: WidgetStateProperty.all(EdgeInsets.zero),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(
                color: GlobalAppBar.kNavDropdownBorder,
                width: 1.5,
              ),
            ),
          ),
          backgroundColor: WidgetStateProperty.all(GlobalAppBar.kNavDropdownBg),
        ),
        builder: (context, controller, child) {
          final isHighlighted = widget.isActive || controller.isOpen || _isHoveringButton;
          final Color bgColor = widget.isActive
              ? GlobalAppBar.kBrandEmerald.withValues(alpha: 0.16)
              : (isHighlighted
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent);
          final Color borderColor = widget.isActive
              ? GlobalAppBar.kBrandEmerald.withValues(alpha: 0.45)
              : (isHighlighted
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.transparent);
          final Color iconColor = widget.isActive
              ? GlobalAppBar.kBrandMint
              : (isHighlighted ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8));
          final Color textColor = (widget.isActive || isHighlighted)
              ? Colors.white
              : const Color(0xFFCBD5E1);

          return MouseRegion(
            onEnter: (_) {
              if (mounted) {
                setState(() => _isHoveringButton = true);
              }
              _scheduleOpen();
            },
            onExit: (_) {
              if (mounted) {
                setState(() => _isHoveringButton = false);
              }
              _checkClose();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 36,
                    child: widget.isIconOnly
                        ? Tooltip(
                            message: widget.label,
                            waitDuration: const Duration(milliseconds: 500),
                            child: _buildButton(iconColor, textColor, controller),
                          )
                        : _buildButton(iconColor, textColor, controller),
                  ),
                  if (widget.isActive)
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 22,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: GlobalAppBar.kBrandMint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
        menuChildren: [
          MouseRegion(
            onEnter: (_) => _isHoveringMenu = true,
            onExit: (_) {
              _isHoveringMenu = false;
              _checkClose();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 236),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 3.0,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            GlobalAppBar.kBrandEmerald,
                            GlobalAppBar.kBrandMint,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...widget.menuChildren,
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildButton(Color iconColor, Color textColor, MenuController controller) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.symmetric(
          horizontal: widget.isIconOnly ? 10 : (widget.isCompact ? 10 : 13),
          vertical: 0,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        foregroundColor: textColor,
        overlayColor: Colors.white.withValues(alpha: 0.08),
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
          Icon(widget.icon, size: 17, color: iconColor),
          if (!widget.isIconOnly) ...[
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(
                color: textColor,
                fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: widget.isCompact ? 13 : 13.5,
              ),
            ),
            if (widget.isActive && widget.activeSubLabel != null) ...[
              const SizedBox(width: 5),
              Text(
                '• ${widget.activeSubLabel}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GlobalAppBar.kBrandMint,
                ),
              ),
            ],
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: controller.isOpen ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.expand_more,
                size: 16,
                color: textColor.withValues(alpha: 0.7),
              ),
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
    builder: (ctx) => AppModalShell(
      title: title,
      subtitle: 'Plan Básico activo — Mejorá tu plan para desbloquear',
      icon: Icons.workspace_premium_rounded,
      accent: AppModalAccent.amber,
      compact: true,
      maxWidth: 440,
      onClose: () => Navigator.pop(ctx),
      bodyPadding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Con el Plan Premium desbloqueás:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.chat_rounded, color: Colors.white),
              label: const Text(
                'Contratar Plan Premium por WhatsApp',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed: () async {
                final url = Uri.parse(
                  'https://wa.me/5493704367202?text=Hola,%20quiero%20contratar%20el%20Plan%20Premium%20del%20Sistema%20POS',
                );
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'WhatsApp Soporte: +54 9 3704 36-7202',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

// ── Dialog Enterprise de Terminal, Caja y Periféricos (Impresora, Gaveta, Balanza y Point) ──
void showTerminalPeripheralsDialog(BuildContext context, {int initialTab = 0}) {
  try {
    final cashProv = context.read<CashRegisterProvider?>();
    if (cashProv != null && cashProv.availableRegisters == null && !cashProv.isLoading) {
      cashProv.loadRegisters();
    }
  } catch (_) {}

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _TerminalPeripheralsDialog(initialTab: initialTab),
  );
}

class _TerminalPeripheralsDialog extends StatefulWidget {
  final int initialTab;
  const _TerminalPeripheralsDialog({this.initialTab = 0});

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
        builder: (dialogCtx) => AppModalShell(
          title: 'Seleccionar Point para esta Caja',
          subtitle: 'Terminales detectadas en Mercado Pago',
          icon: Icons.point_of_sale_rounded,
          accent: AppModalAccent.blue,
          compact: true,
          maxWidth: 440,
          onClose: () => Navigator.of(dialogCtx).pop(null),
          bodyPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          body: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: devices.length,
            separatorBuilder: (_, __) => const Divider(height: 6),
            itemBuilder: (ctx, i) {
              final d = devices[i];
              final id = d['id']?.toString() ?? '';
              final posId = d['pos_id']?.toString() ?? '';
              final mode = d['operating_mode']?.toString().toUpperCase() ?? 'PDV';
              final isSelected = p.mpPointDeviceId == id;

              return Material(
                color: isSelected ? AppColors.primarySoft : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected ? AppColors.primaryBorder : Colors.transparent,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.contactless_rounded,
                    color: isSelected ? const Color(0xFF009EE3) : Colors.grey,
                  ),
                  title: Text(
                    id,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF009EE3)
                          : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text('Modo: $mode ${posId.isNotEmpty ? "• Caja MP #$posId" : ""}'),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xFF009EE3), size: 20)
                      : null,
                  onTap: () => Navigator.of(dialogCtx).pop(d),
                ),
              );
            },
          ),
          footerActions: [
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
      if (e is FormatException && e.message == 'ENDPOINT_NOT_FOUND') {
        _setFeedback(
          'Servidor en versión v1.8.5: Ingrese el Device ID manualmente en el campo.',
          isError: false,
        );
      } else {
        _setFeedback('Error buscando terminales Point: $e', isError: true);
      }
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

        final cashProvider = context.watch<CashRegisterProvider?>();
        final settingsProvider = context.watch<SettingsProvider?>();
        final bool showScaleSection =
            (settingsProvider?.safeVerticalProfile.canUseScaleWeight ?? true) ||
                savedComPort.isNotEmpty;
        final shift = cashProvider?.currentShift;
        final isOpen = shift != null && shift.isOpen;
        final registers = cashProvider?.availableRegisters ?? [];
        final assignedId = settingsProvider?.assignedRegisterId ?? 1;
        final activeRegId = shift?.cashRegisterId ??
            (assignedId > 0 ? assignedId : (cashProvider?.activeRegisterId ?? registers.firstOrNull?.id ?? 1));

        String regName = shift?.cashRegisterName ?? '';
        if (regName.trim().isEmpty && registers.isNotEmpty) {
          final match = registers.where((r) => r.id == activeRegId).firstOrNull;
          if (match != null) regName = match.name;
        }
        if (regName.trim().isEmpty) {
          regName = activeRegId == 1 ? 'Caja Principal' : 'Caja #$activeRegId';
        }

        final String printerSummary = p.printerConnection == 'none'
            ? 'Desactivada'
            : (p.printerFormat == 'a4'
                ? 'Hoja ${p.pdfPaperSize.toUpperCase()}'
                : '${p.printerFormat == 'thermal_58' ? 'Térmica 58mm' : 'Térmica 80mm'}${savedPrinter.isNotEmpty ? ' • $savedPrinter' : ''}');
        final String drawerSummary = p.autoOpenCashDrawer
            ? 'Apertura automática RJ-11'
            : 'Apertura manual';
        final String scaleSummary = savedComPort.isNotEmpty
            ? 'Conectada en $savedComPort'
            : 'Sin balanza (Peso manual)';
        final String pointSummary = p.mpPointDeviceId.trim().isNotEmpty
            ? p.mpPointDeviceId.trim()
            : 'Predeterminado del sistema';

        return DefaultTabController(
          length: 3,
          initialIndex: widget.initialTab.clamp(0, 2),
          child: Builder(
            builder: (tabContext) {
              return AppModalShell(
                titleWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        regName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isOpen
                            ? GlobalAppBar.kBrandEmerald.withValues(alpha: 0.18)
                            : GlobalAppBar.kBrandAmber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOpen
                              ? GlobalAppBar.kBrandEmerald.withValues(alpha: 0.45)
                              : GlobalAppBar.kBrandAmber.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        isOpen ? 'TURNO #${shift.id}' : 'CERRADA',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isOpen
                              ? GlobalAppBar.kBrandMint
                              : GlobalAppBar.kBrandAmberLight,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: 'Configuración de Terminal Física y Periféricos Conectados',
                icon: Icons.point_of_sale_rounded,
                accent: isOpen ? AppModalAccent.emerald : AppModalAccent.amber,
                maxWidth: 640,
                maxHeight: 620,
                expandBody: true,
                onClose: () => Navigator.pop(context),
                headerTrailing: IconButton(
                  tooltip: 'Refrescar dispositivos conectados',
                  constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                    ),
                  ),
                  icon: (_isLoadingPrinters || _isLoadingPorts)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFCBD5E1),
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: Color(0xFFCBD5E1),
                        ),
                  onPressed: (_isLoadingPrinters || _isLoadingPorts)
                      ? null
                      : _refreshHardwareLists,
                ),
                topBar: Material(
                  color: AppColors.navyEnd,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: GlobalAppBar.kNavBorderBottom,
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: TabBar(
                        labelColor: Colors.white,
                        unselectedLabelColor: const Color(0xFF94A3B8),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: GlobalAppBar.kBrandEmerald.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: GlobalAppBar.kBrandMint.withValues(alpha: 0.50),
                          ),
                        ),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                        tabs: [
                          const Tab(
                            height: 36,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.desktop_windows_outlined, size: 16),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Terminal y Turno',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Tab(
                            height: 36,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.print_outlined, size: 16),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Impresora y Cajón',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Tab(
                            height: 36,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  showScaleSection
                                      ? Icons.scale_outlined
                                      : Icons.credit_card_outlined,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    showScaleSection
                                        ? 'Balanza y Point'
                                        : 'Posnet Point',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                bodyPadding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                body: Column(
                  children: [
                    Expanded(
                      child: TabBarView(
                        children: [
                            // ── TAB 1: TERMINAL Y TURNO ──
                            SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isOpen ? Colors.teal.shade50 : Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isOpen ? Colors.teal.shade200 : Colors.amber.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isOpen ? Icons.verified_user_outlined : Icons.lock_clock_outlined,
                                          color: isOpen ? Colors.teal.shade700 : Colors.amber.shade800,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                isOpen ? 'TURNO ABIERTO (#${shift.id}) EN ${regName.toUpperCase()}' : 'SIN TURNO ABIERTO EN ${regName.toUpperCase()}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: isOpen ? Colors.teal.shade900 : Colors.amber.shade900,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                isOpen && shift.userName != null
                                                    ? 'Operador de apertura: ${shift.userName}'
                                                    : 'Esta computadora está vinculada a $regName (ID #$activeRegId).',
                                                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (registers.length > 1 && cashProvider != null && settingsProvider != null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      'Cambiar de Caja en esta Terminal:',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey.shade800),
                                    ),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<int>(
                                      initialValue: registers.any((r) => r.id == activeRegId)
                                          ? activeRegId
                                          : registers.first.id,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        prefixIcon: Icon(Icons.desktop_windows_outlined, size: 18),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: registers
                                          .map((r) => DropdownMenuItem<int>(
                                                value: r.id,
                                                child: Text(r.name),
                                              ))
                                          .toList(),
                                      onChanged: (newId) {
                                        if (newId == null || newId == activeRegId) return;
                                        Navigator.pop(context);
                                        AdminPinDialog.protectAction(
                                          context,
                                          action: 'Cambiar Terminal de Caja',
                                          permissionKey: AppPermissions.manageSettings,
                                          onAuthorized: () async {
                                            await settingsProvider.setAssignedRegisterId(newId);
                                            await cashProvider.checkCurrentShift(registerId: newId);
                                            final newShiftId = cashProvider.currentShift?.id;
                                            final navCtx = AppConfig.navigatorKey.currentContext;
                                            if (navCtx != null && navCtx.mounted) {
                                              navCtx.read<PosProvider>().clearCart();
                                              try {
                                                if (settingsProvider.features.expenses) {
                                                  navCtx.read<CashMovementProvider>().fetchMovements(
                                                        refresh: true,
                                                        all: false,
                                                        cashShiftId: newShiftId,
                                                      );
                                                }
                                              } catch (_) {}
                                              try {
                                                navCtx.read<SalesHistoryProvider>().loadSales(
                                                      period: 'shift',
                                                      shiftId: newShiftId,
                                                    );
                                              } catch (_) {}
                                            }
                                            AppConfig.navigatorKey.currentState
                                                ?.pushNamedAndRemoveUntil('/home', (route) => false);
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  Text(
                                    'ESTADO DE PERIFÉRICOS EN ESTE PUESTO (CLIC PARA CONFIGURAR)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.7,
                                      color: Colors.blueGrey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildHardwareSummaryCard(
                                          icon: Icons.print_outlined,
                                          title: 'Impresora',
                                          value: printerSummary,
                                          isActive: p.printerConnection != 'none',
                                          color: Colors.blue.shade700,
                                          onTap: () => DefaultTabController.of(tabContext).animateTo(1),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildHardwareSummaryCard(
                                          icon: Icons.lock_open_rounded,
                                          title: 'Gaveta RJ-11',
                                          value: drawerSummary,
                                          isActive: p.autoOpenCashDrawer,
                                          color: Colors.teal.shade700,
                                          onTap: () => DefaultTabController.of(tabContext).animateTo(1),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      if (showScaleSection) ...[
                                        Expanded(
                                          child: _buildHardwareSummaryCard(
                                            icon: Icons.scale_outlined,
                                            title: 'Balanza Serie',
                                            value: scaleSummary,
                                            isActive: savedComPort.isNotEmpty,
                                            color: Colors.indigo.shade700,
                                            onTap: () => DefaultTabController.of(tabContext).animateTo(2),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      Expanded(
                                        child: _buildHardwareSummaryCard(
                                          icon: Icons.credit_card_rounded,
                                          title: 'Posnet Point',
                                          value: pointSummary,
                                          isActive: p.mpPointDeviceId.trim().isNotEmpty,
                                          color: const Color(0xFF009EE3),
                                          onTap: () => DefaultTabController.of(tabContext).animateTo(2),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // ── TAB 2: IMPRESORA Y GAVETA ──
                            SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeader(
                                    icon: Icons.receipt_long_rounded,
                                    title: 'Impresora de Tickets / Comprobantes',
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
                                  _buildSectionHeader(
                                    icon: Icons.point_of_sale_rounded,
                                    title: 'Caja Registradora / Gaveta de Dinero (RJ-11)',
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
                                ],
                              ),
                            ),

                            // ── TAB 3: BALANZA Y POSNET POINT ──
                            SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showScaleSection) ...[
                                    _buildSectionHeader(
                                      icon: Icons.scale_rounded,
                                      title: 'Balanza Electrónica (Cable Serie / USB-COM)',
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
                                  ],
                                  _buildSectionHeader(
                                    icon: Icons.credit_card_rounded,
                                    title: 'Posnet Mercado Pago Point (Opcional por Caja)',
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
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _statusIsError ? Colors.red.shade50 : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _statusIsError ? Colors.red.shade200 : Colors.green.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _statusIsError
                                    ? Icons.error_outline_rounded
                                    : Icons.check_circle_outline_rounded,
                                color: _statusIsError ? Colors.red.shade700 : Colors.green.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _statusIsError ? Colors.red.shade800 : Colors.green.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  footerLeading: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Guardado automático local para esta computadora.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  footerActions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Listo'),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    }

  Widget _buildHardwareSummaryCard({
    required IconData icon,
    required String title,
    required String value,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? color.withValues(alpha: 0.35) : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive ? color.withValues(alpha: 0.1) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: isActive ? color : Colors.blueGrey),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.black87),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: isActive ? color : Colors.blueGrey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.blueGrey.shade400),
          ],
        ),
      ),
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

  String _buildTooltipMessage(UpdateCheckResult result) {
    final channelTag = result.isBeta ? ' [Canal BETA]' : '';
    if (result.isFullSystemUpdate) {
      return 'Actualización Integral disponible$channelTag '
          '(App v${result.frontendUpdate!.version} + Servidor v${result.backendUpdate!.version})';
    }
    if (result.frontendUpdate != null) {
      return 'Nueva versión de App disponible$channelTag '
          '(v${result.frontendUpdate!.version})';
    }
    return 'Nueva actualización de Servidor disponible$channelTag '
        '(v${result.backendUpdate!.version})';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: UpdateService.isSwitchingChannelNotifier,
      builder: (context, isSwitching, _) {
        if (isSwitching) {
          final isBeta =
              UpdateService.channelNotifier.value.toLowerCase() == 'beta';
          return Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: Tooltip(
              message: isBeta
                  ? 'Buscando actualizaciones en canal BETA...'
                  : 'Buscando actualizaciones en canal Estable...',
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: (isBeta
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF38BDF8))
                      .withValues(alpha: 0.16),
                  border: Border.all(
                    color: (isBeta
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF38BDF8))
                        .withValues(alpha: 0.55),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isBeta
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFFBAE6FD),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      isBeta ? 'Verificando Beta...' : 'Verificando...',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ValueListenableBuilder<UpdateCheckResult?>(
          valueListenable: UpdateService.updateNotifier,
          builder: (context, result, child) {
            if (result == null || !result.hasAny) {
              return const SizedBox.shrink();
            }

            final isCritical = (result.frontendUpdate?.isCritical == true) ||
                (result.backendUpdate?.isCritical == true);
            final isBeta = result.isBeta;

            final Color bgColor = isCritical
                ? Colors.redAccent.withValues(alpha: 0.22)
                : (isBeta
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.22)
                    : const Color(0xFF8B5CF6).withValues(alpha: 0.25));
            final Color borderColor = isCritical
                ? Colors.redAccent
                : (isBeta
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFA78BFA));
            final Color shadowColor = isCritical
                ? Colors.redAccent
                : (isBeta
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF8B5CF6));
            final Color iconColor = isCritical
                ? const Color(0xFFFCA5A5)
                : (isBeta
                    ? const Color(0xFFFDE68A)
                    : const Color(0xFFDDD6FE));

            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: Tooltip(
                message: _buildTooltipMessage(result),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    final update =
                        result.frontendUpdate ?? result.backendUpdate!;
                    showDialog(
                      context: context,
                      barrierDismissible: !update.isCritical,
                      builder: (_) => UpdateDialog(
                        updateInfo: update,
                        isFullSystemUpdate: result.isFullSystemUpdate,
                      ),
                    );
                  },
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: bgColor,
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: shadowColor.withValues(alpha: 0.25),
                          blurRadius: 8,
                          spreadRadius: 0.5,
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.system_update_rounded,
                          size: 16,
                          color: iconColor,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Actualizar',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (isBeta) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              'BETA',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E1B18),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

