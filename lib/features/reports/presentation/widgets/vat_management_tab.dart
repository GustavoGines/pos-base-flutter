import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) {
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
                        tooltip: 'Balance Mensual Débito vs Crédito',
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
                        tooltip: 'Subdiario Fiscal de Compras de Proveedores',
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
            children: const [
              VatPositionReportView(),
              VatSalesReportView(),
              VatPurchasesReportView(),
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
            color: isSelected ? Colors.indigo.shade700 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? Colors.white : Colors.blueGrey.shade800,
            ),
          ),
        ),
      ),
    );
  }
}
