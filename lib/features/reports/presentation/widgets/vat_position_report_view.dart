import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import '../providers/reports_provider.dart';

class VatPositionReportView extends StatefulWidget {
  const VatPositionReportView({super.key});

  @override
  State<VatPositionReportView> createState() => _VatPositionReportViewState();
}

class _VatPositionReportViewState extends State<VatPositionReportView> {
  static const List<String> _months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ReportsProvider>();
      if (provider.vatPositionData.isEmpty && !provider.isLoadingVatPosition) {
        provider.fetchVatPosition();
      }
    });
  }

  void _prevMonth(ReportsProvider provider) {
    var y = provider.vatPositionYear;
    var m = provider.vatPositionMonth - 1;
    if (m < 1) {
      m = 12;
      y -= 1;
    }
    provider.setVatPositionPeriod(y, m);
  }

  void _nextMonth(ReportsProvider provider) {
    var y = provider.vatPositionYear;
    var m = provider.vatPositionMonth + 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
    provider.setVatPositionPeriod(y, m);
  }

  void _setCurrentMonth(ReportsProvider provider) {
    final now = DateTime.now();
    provider.setVatPositionPeriod(now.year, now.month);
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReportsProvider>(
      builder: (context, provider, _) {
        final currentYear = provider.vatPositionYear;
        final currentMonth = provider.vatPositionMonth;
        final data = provider.vatPositionData;

        final sales = data['sales'] is Map ? data['sales'] as Map : {};
        final purchases = data['purchases'] is Map ? data['purchases'] as Map : {};
        final balance = data['balance'] is Map ? data['balance'] as Map : {};

        final fiscalDebit = _toDouble(balance['fiscal_debit'] ?? sales['fiscal_debit']);
        final fiscalCredit = _toDouble(balance['fiscal_credit'] ?? purchases['fiscal_credit']);
        final ivaPerceptions = _toDouble(balance['iva_perceptions'] ?? purchases['iva_perceptions']);

        // net_balance = fiscalDebit - fiscalCredit - ivaPerceptions
        final netBalance = balance.containsKey('net_balance')
            ? _toDouble(balance['net_balance'])
            : (fiscalDebit - fiscalCredit - ivaPerceptions);

        final isToPay = netBalance > 0.001;

        // Desglose de Ventas
        final debit21 = _toDouble(sales['debit_21']);
        final debit105 = _toDouble(sales['debit_105']);
        final debit27 = _toDouble(sales['debit_27']);
        final totalSalesAmount = _toDouble(sales['total_sales_amount']);
        final salesNet = _toDouble(sales['total_invoiced_net']);
        final salesCount = sales['invoices_count'] ?? 0;
        final salesNcCount = sales['credit_notes_count'] ?? 0;

        // Desglose de Compras
        final credit21 = _toDouble(purchases['credit_21']);
        final credit105 = _toDouble(purchases['credit_105']);
        final credit27 = _toDouble(purchases['credit_27']);
        final iibbPerceptions = _toDouble(purchases['iibb_perceptions']);
        final totalPurchasesAmount = _toDouble(purchases['total_purchases_amount']);
        final purchasesNet = _toDouble(purchases['total_purchases_net']);
        final purchasesCount = purchases['invoices_count'] ?? 0;
        final purchasesNcCount = purchases['credit_notes_count'] ?? 0;

        final now = DateTime.now();
        final isNow = currentYear == now.year && currentMonth == now.month;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Barra Superior de Selección de Período ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.balance_rounded, size: 16, color: Colors.indigo.shade800),
                            const SizedBox(width: 6),
                            Text(
                              'Control Fiscal Mensual (F. 2002 ARCA / AFIP)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => _prevMonth(provider),
                        icon: const Icon(Icons.chevron_left, size: 20),
                        tooltip: 'Mes Anterior',
                        visualDensity: VisualDensity.compact,
                      ),
                      // Dropdown de Mes
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: currentMonth,
                            items: List.generate(12, (index) {
                              return DropdownMenuItem<int>(
                                value: index + 1,
                                child: Text(
                                  _months[index],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              );
                            }),
                            onChanged: (val) {
                              if (val != null) {
                                provider.setVatPositionPeriod(currentYear, val);
                              }
                            },
                          ),
                        ),
                      ),
                      // Dropdown de Año
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: currentYear,
                            items: {currentYear - 2, currentYear - 1, currentYear, currentYear + 1}
                                .map((y) => DropdownMenuItem<int>(
                                      value: y,
                                      child: Text(
                                        y.toString(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                provider.setVatPositionPeriod(val, currentMonth);
                              }
                            },
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => _nextMonth(provider),
                        icon: const Icon(Icons.chevron_right, size: 20),
                        tooltip: 'Mes Siguiente',
                        visualDensity: VisualDensity.compact,
                      ),
                      if (!isNow)
                        ActionChip(
                          avatar: const Icon(Icons.today, size: 14),
                          label: const Text('Mes Actual', style: TextStyle(fontSize: 12)),
                          onPressed: () => _setCurrentMonth(provider),
                        ),
                      IconButton(
                        onPressed: provider.isLoadingVatPosition ? null : () => provider.fetchVatPosition(),
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Recalcular Posición',
                        color: Colors.indigo,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (provider.isLoadingVatPosition)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (provider.vatPositionError != null && data.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400),
                      const SizedBox(height: 12),
                      Text(
                        provider.vatPositionError!,
                        style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => provider.fetchVatPosition(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── 1. Hero KPI Card: Gran Saldo Estimado ──
                      _buildHeroCard(
                        isToPay: isToPay,
                        netBalance: netBalance,
                        monthName: _months[currentMonth - 1],
                        year: currentYear,
                      ),

                      const SizedBox(height: 20),

                      // ── 2. Desglose de la Ecuación Fiscal F. 2002 ──
                      _buildEquationCard(
                        fiscalDebit: fiscalDebit,
                        fiscalCredit: fiscalCredit,
                        ivaPerceptions: ivaPerceptions,
                        netBalance: netBalance,
                        isToPay: isToPay,
                      ),

                      const SizedBox(height: 20),

                      // ── 3. Paneles Comparativos (Ventas vs Compras) ──
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 900;
                          final salesPanel = _buildSalesComparativePanel(
                            fiscalDebit: fiscalDebit,
                            salesNet: salesNet,
                            totalSalesAmount: totalSalesAmount,
                            debit21: debit21,
                            debit105: debit105,
                            debit27: debit27,
                            salesCount: salesCount,
                            salesNcCount: salesNcCount,
                          );

                          final purchasesPanel = _buildPurchasesComparativePanel(
                            fiscalCredit: fiscalCredit,
                            purchasesNet: purchasesNet,
                            totalPurchasesAmount: totalPurchasesAmount,
                            credit21: credit21,
                            credit105: credit105,
                            credit27: credit27,
                            ivaPerceptions: ivaPerceptions,
                            iibbPerceptions: iibbPerceptions,
                            purchasesCount: purchasesCount,
                            purchasesNcCount: purchasesNcCount,
                          );

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: salesPanel),
                                const SizedBox(width: 16),
                                Expanded(child: purchasesPanel),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              salesPanel,
                              const SizedBox(height: 16),
                              purchasesPanel,
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // ── 4. Disclaimer Legal Contable Obligatorio ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 20, color: Colors.amber.shade900),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AVISO LEGAL Y DE CONTROL DE GESTIÓN',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.amber.shade900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Estimación de gestión para control interno. No reemplaza la declaración jurada mensual F. 2002 de ARCA/AFIP (puede diferir por saldos a favor de libre disponibilidad de meses anteriores, retenciones bancarias, retenciones sufridas o ajustes contables del profesional).',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: const Color(0xFF78350F),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeroCard({
    required bool isToPay,
    required double netBalance,
    required String monthName,
    required int year,
  }) {
    final title = isToPay
        ? 'SALDO ESTIMADO A PAGAR (ARCA / AFIP)'
        : 'SALDO TÉCNICO A FAVOR ESTIMADO';
    final subtitle = isToPay
        ? 'El Débito Fiscal de ventas supera al Crédito Fiscal y Percepciones del período $monthName $year.'
        : 'El Crédito Fiscal y Percepciones de compras superan al Débito Fiscal del período $monthName $year.';

    final bgColor = isToPay ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
    final borderColor = isToPay ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0);
    final primaryColor = isToPay ? const Color(0xFFB91C1C) : const Color(0xFF15803D);
    final icon = isToPay ? Icons.payments_outlined : Icons.savings_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 36, color: primaryColor),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '\$${netBalance.abs().toCurrency()}',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.blueGrey.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquationCard({
    required double fiscalDebit,
    required double fiscalCredit,
    required double ivaPerceptions,
    required double netBalance,
    required bool isToPay,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.functions_rounded, size: 18, color: Colors.indigo.shade800),
              const SizedBox(width: 8),
              const Text(
                'Ecuación Impositiva del Período (F. 2002)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildEquationRow(
            label: '(+) Débito Fiscal (Libro IVA Ventas)',
            amount: fiscalDebit,
            color: const Color(0xFFB45309), // Amber 700
            isBold: false,
          ),
          const Divider(height: 14),
          _buildEquationRow(
            label: '(-) Crédito Fiscal (Libro IVA Compras)',
            amount: -fiscalCredit,
            color: const Color(0xFF0F766E), // Teal 700
            isBold: false,
          ),
          const Divider(height: 14),
          _buildEquationRow(
            label: '(-) Percepciones de IVA Sufridas en Compras',
            amount: -ivaPerceptions,
            color: const Color(0xFF6B21A8), // Purple 800
            isBold: false,
          ),
          const Divider(height: 18, thickness: 1.5),
          _buildEquationRow(
            label: '(=) Saldo del Período Estimado',
            amount: netBalance,
            color: isToPay ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
            isBold: true,
            fontSize: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildEquationRow({
    required String label,
    required double amount,
    required Color color,
    required bool isBold,
    double fontSize = 13.5,
  }) {
    final prefix = amount < 0 ? '-' : (amount > 0 && !isBold ? '+' : '');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isBold ? const Color(0xFF0F172A) : const Color(0xFF475569),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$prefix\$${amount.abs().toCurrency()}',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSalesComparativePanel({
    required double fiscalDebit,
    required double salesNet,
    required double totalSalesAmount,
    required double debit21,
    required double debit105,
    required double debit27,
    required int salesCount,
    required int salesNcCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.outbox_rounded, size: 16, color: Colors.amber.shade800),
              ),
              const SizedBox(width: 8),
              const Text(
                '📤 Ventas (Débito Fiscal)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailItem('IVA Débito 21%', '\$${debit21.toCurrency()}'),
          _buildDetailItem('IVA Débito 10.5%', '\$${debit105.toCurrency()}'),
          if (debit27 != 0) _buildDetailItem('IVA Débito 27%', '\$${debit27.toCurrency()}'),
          const Divider(height: 12),
          _buildDetailItem('Total Neto Gravado', '\$${salesNet.toCurrency()}'),
          _buildDetailItem('Facturación Bruta (con IVA)', '\$${totalSalesAmount.toCurrency()}'),
          _buildDetailItem('Comprobantes Emitidos', '$salesCount fac. · $salesNcCount NC'),
          const Divider(height: 12),
          _buildDetailItem('TOTAL DÉBITO FISCAL', '\$${fiscalDebit.toCurrency()}', isHighlight: true, color: Colors.amber.shade900),
        ],
      ),
    );
  }

  Widget _buildPurchasesComparativePanel({
    required double fiscalCredit,
    required double purchasesNet,
    required double totalPurchasesAmount,
    required double credit21,
    required double credit105,
    required double credit27,
    required double ivaPerceptions,
    required double iibbPerceptions,
    required int purchasesCount,
    required int purchasesNcCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.inbox_rounded, size: 16, color: Colors.teal.shade800),
              ),
              const SizedBox(width: 8),
              const Text(
                '📥 Compras (Crédito Fiscal)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailItem('IVA Crédito 21%', '\$${credit21.toCurrency()}'),
          _buildDetailItem('IVA Crédito 10.5%', '\$${credit105.toCurrency()}'),
          if (credit27 != 0) _buildDetailItem('IVA Crédito 27%', '\$${credit27.toCurrency()}'),
          _buildDetailItem('Percepciones IVA Sufridas', '\$${ivaPerceptions.toCurrency()}'),
          _buildDetailItem('Percepciones IIBB Sufridas', '\$${iibbPerceptions.toCurrency()}'),
          const Divider(height: 12),
          _buildDetailItem('Total Neto Gravado Compras', '\$${purchasesNet.toCurrency()}'),
          _buildDetailItem('Total Compras Facturadas', '\$${totalPurchasesAmount.toCurrency()}'),
          _buildDetailItem('Comprobantes Recibidos', '$purchasesCount fac. · $purchasesNcCount NC'),
          const Divider(height: 12),
          _buildDetailItem('TOTAL CRÉDITO FISCAL', '\$${fiscalCredit.toCurrency()}', isHighlight: true, color: Colors.teal.shade800),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {bool isHighlight = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
                color: isHighlight ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isHighlight ? FontWeight.w900 : FontWeight.w600,
              color: color ?? const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}
