import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/plan_upgrade_dialog.dart';
import 'pos_quick_quotes_dialog.dart';
import 'pos_quick_customer_dialog.dart';
import 'pos_quick_offers_dialog.dart';

class PosQuickActionButtons extends StatelessWidget {
  final VoidCallback onHoldOrder;
  final VoidCallback onOpenPendingList;
  final VoidCallback? onAfterDialogClosed;

  const PosQuickActionButtons({
    super.key,
    required this.onHoldOrder,
    required this.onOpenPendingList,
    this.onAfterDialogClosed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer3<PosProvider, OfferProvider, SettingsProvider>(
      builder: (context, pos, offerProv, settingsProv, _) {
        final pendingCount = pos.pendingCount;
        final hasCustomer = pos.selectedCustomer != null;
        final activeOffersCount = offerProv.activeOffers.length;
        final hasActiveQuote = pos.activeQuoteId != null;
        final hasQuotes = settingsProv.settings?.features.quotes ?? false;
        final hasCurrentAccounts = settingsProv.settings?.features.currentAccounts ?? false;

        return Row(
          children: [
            // 1. En Espera
            Expanded(
              child: _QuickTile(
                icon: Icons.pause_circle_outline_rounded,
                label: 'En Espera',
                color: const Color(0xFFE65100), // Naranja / Ámbar
                badgeText: pendingCount > 0 ? '$pendingCount' : null,
                badgeColor: Colors.deepOrange,
                tooltip: pendingCount > 0
                    ? 'Guardar orden actual o ver las $pendingCount en espera'
                    : 'Dejar orden actual en espera',
                onTap: () {
                  if (pos.cart.isNotEmpty && !pos.isLoading && pos.activePendingSaleId == null) {
                    onHoldOrder();
                  } else {
                    onOpenPendingList();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),

            // 2. Presupuestos
            Expanded(
              child: _QuickTile(
                icon: hasQuotes ? Icons.request_quote_rounded : Icons.lock_outline_rounded,
                label: 'Presupuestos',
                color: hasQuotes ? const Color(0xFF3F51B5) : Colors.indigo.shade400,
                badgeText: !hasQuotes ? 'PRO' : (hasActiveQuote ? 'Activo' : null),
                badgeColor: !hasQuotes ? Colors.amber.shade800 : Colors.indigo.shade700,
                tooltip: !hasQuotes
                    ? '🔒 Presupuestos • Requiere Plan Premium'
                    : 'Generar presupuesto del carrito o recuperar anteriores',
                onTap: () async {
                  if (!hasQuotes) {
                    await PlanUpgradeDialog.show(
                      context,
                      featureName: 'Presupuestos Rápidos',
                      description:
                          'La generación y gestión de presupuestos está disponible en el Plan Ferretería/Corralón o como módulo adicional.',
                    );
                    onAfterDialogClosed?.call();
                    return;
                  }
                  await showDialog(
                    context: context,
                    builder: (ctx) => const PosQuickQuotesDialog(),
                  );
                  onAfterDialogClosed?.call();
                },
              ),
            ),
            const SizedBox(width: 8),

            // 3. Clientes
            Expanded(
              child: _QuickTile(
                icon: hasCurrentAccounts
                    ? Icons.person_pin_circle_rounded
                    : Icons.lock_outline_rounded,
                label: hasCustomer
                    ? (pos.selectedCustomer!.name.length > 9
                        ? '${pos.selectedCustomer!.name.substring(0, 8)}…'
                        : pos.selectedCustomer!.name)
                    : 'Clientes',
                color: hasCurrentAccounts
                    ? const Color(0xFF1976D2)
                    : Colors.blue.shade400,
                badgeText: !hasCurrentAccounts
                    ? 'PRO'
                    : (hasCustomer ? '✓' : null),
                badgeColor: !hasCurrentAccounts
                    ? Colors.amber.shade800
                    : Colors.teal.shade700,
                tooltip: !hasCurrentAccounts
                    ? '🔒 Clientes y Cta. Cte. • Requiere Plan Premium'
                    : (hasCustomer
                        ? 'Cliente: ${pos.selectedCustomer!.name} (Toca para gestionar)'
                        : 'Gestionar o asignar clientes al ticket'),
                onTap: () async {
                  if (!hasCurrentAccounts) {
                    await PlanUpgradeDialog.show(
                      context,
                      featureName: 'Gestión de Clientes y Cuentas Corrientes',
                      description:
                          'El registro de clientes, asignación al ticket y control de Cuentas Corrientes (Fiado) está disponible en el Plan Premium o como módulo adicional.',
                    );
                    onAfterDialogClosed?.call();
                    return;
                  }
                  await showDialog(
                    context: context,
                    builder: (ctx) => const PosQuickCustomerDialog(),
                  );
                  onAfterDialogClosed?.call();
                },
              ),
            ),
            const SizedBox(width: 8),

            // 4. Ofertas
            Expanded(
              child: _QuickTile(
                icon: Icons.local_offer_rounded,
                label: 'Ofertas',
                color: const Color(0xFF7B1FA2), // Púrpura / Fucsia
                badgeText: activeOffersCount > 0 ? '$activeOffersCount' : null,
                badgeColor: Colors.purple.shade700,
                tooltip: activeOffersCount > 0
                    ? '$activeOffersCount oferta(s) activas hoy. Toca para ver o crear.'
                    : 'Armar ofertas diarias, semanales o mensuales',
                onTap: () async {
                  await showDialog(
                    context: context,
                    builder: (ctx) => const PosQuickOffersDialog(),
                  );
                  onAfterDialogClosed?.call();
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? badgeText;
  final Color? badgeColor;
  final String tooltip;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.color,
    this.badgeText,
    this.badgeColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<_QuickTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              decoration: BoxDecoration(
                color: _isHovered
                    ? widget.color.withValues(alpha: 0.16)
                    : widget.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isHovered
                      ? widget.color
                      : widget.color.withValues(alpha: 0.35),
                  width: _isHovered ? 1.5 : 1.2,
                ),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 20, color: widget.color),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: widget.color,
                            letterSpacing: 0.1,
                            height: 1.1,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  if (widget.badgeText != null)
                    Positioned(
                      top: -6,
                      right: -3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: widget.badgeColor ?? Colors.red,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: Text(
                          widget.badgeText!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
