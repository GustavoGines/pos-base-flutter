import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/premium_showcase_card.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'vat_position_report_view.dart';
import 'vat_sales_report_view.dart';
import 'vat_purchases_report_view.dart';

/// Pestaña unificada "🏛️ IVA / Impositivo" que agrupa:
/// 1. ⚖️ Posición Mensual de IVA (F. 2002)
/// 2. 📤 Libro IVA Ventas (Subdiario Fiscal Ventas)
/// 3. 📥 Libro IVA Compras (Subdiario Fiscal Compras)
class VatManagementTab extends StatefulWidget {
  const VatManagementTab({super.key});

  @override
  State<VatManagementTab> createState() => _VatManagementTabState();
}

class _VatManagementTabState extends State<VatManagementTab> {
  int _selectedSubView = 0;

  @override
  void initState() {
    super.initState();
    try {
      final settings = context.read<SettingsProvider?>()?.settings;
      if (settings != null && !settings.features.suppliers) {
        _selectedSubView = 1;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    SettingsProvider? settingsProv;
    try {
      settingsProv = context.watch<SettingsProvider?>();
    } catch (_) {}
    final settings = settingsProv?.settings;
    // Retrocompatibilidad: en tests standalone sin SettingsProvider se habilitan todas las vistas.
    final bool canAccessPurchasesAndPosition =
        settings == null ? true : settings.features.suppliers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Barra Superior de Sub-Vistas Tributarias ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSubViewButton(
                        index: 0,
                        label: '⚖️ Posición Mensual',
                        tooltip: canAccessPurchasesAndPosition
                            ? 'Balance Mensual Débito vs Crédito'
                            : '🔒 Posición Mensual F. 2002 • Plan Premium',
                        isLocked: !canAccessPurchasesAndPosition,
                      ),
                      const SizedBox(width: 4),
                      _buildSubViewButton(
                        index: 1,
                        label: '📤 Libro IVA Ventas',
                        tooltip: 'Subdiario Fiscal de Facturación y Notas de Crédito',
                      ),
                      const SizedBox(width: 4),
                      _buildSubViewButton(
                        index: 2,
                        label: '📥 Libro IVA Compras',
                        tooltip: canAccessPurchasesAndPosition
                            ? 'Subdiario Fiscal de Compras de Proveedores'
                            : '🔒 Libro IVA Compras • Plan Premium',
                        isLocked: !canAccessPurchasesAndPosition,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Contenido de la Sub-Vista ──
        Expanded(
          child: IndexedStack(
            index: _selectedSubView,
            children: [
              canAccessPurchasesAndPosition
                  ? const VatPositionReportView()
                  : const PremiumShowcaseCard(
                      icon: Icons.balance_rounded,
                      title: 'Posición Mensual de IVA (F. 2002)',
                      subtitle:
                          'Calculá automáticamente tu saldo estimado a pagar o a favor cruzando el Débito Fiscal de tus ventas con el Crédito Fiscal de tus Proveedores.',
                      highlights: [
                        'Cruce automático Débito Fiscal AFIP vs. Crédito Fiscal de Compras',
                        'Desglose de alícuotas 21%, 10.5%, 27% y percepciones de IVA / IIBB',
                        'Requiere módulo de Proveedores incluido en el Plan Premium',
                      ],
                    ),
              const VatSalesReportView(),
              canAccessPurchasesAndPosition
                  ? const VatPurchasesReportView()
                  : const PremiumShowcaseCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'Libro IVA Compras y Crédito Fiscal',
                      subtitle:
                          'Registrá facturas de compra de Proveedores con desglose fiscal, retenciones y percepciones para exportar directo a tu contador.',
                      highlights: [
                        'Carga de facturas A/B/C/M y Notas de Crédito de proveedores',
                        'Detección de Crédito Fiscal descontable y percepciones sufridas',
                        'Exportación contable Excel y PDF incluida en el Plan Premium',
                      ],
                      accentColor: Color(0xFF0284C7),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubViewButton({
    required int index,
    required String label,
    required String tooltip,
    bool isLocked = false,
  }) {
    final isSelected = _selectedSubView == index;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          if (_selectedSubView != index) {
            setState(() => _selectedSubView = index);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isLocked ? Colors.amber.shade800 : Colors.indigo.shade700)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: (isLocked ? Colors.amber.shade800 : Colors.indigo)
                          .withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLocked) ...[
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: isSelected ? Colors.white : Colors.amber.shade800,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.blueGrey.shade800,
                ),
              ),
              if (isLocked) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.22)
                        : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.45)
                          : Colors.amber.shade400,
                    ),
                  ),
                  child: Text(
                    'PREMIUM',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
