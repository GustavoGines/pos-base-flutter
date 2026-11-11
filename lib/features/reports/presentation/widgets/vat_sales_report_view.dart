import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../providers/reports_provider.dart';

class VatSalesReportView extends StatefulWidget {
  const VatSalesReportView({super.key});

  @override
  State<VatSalesReportView> createState() => _VatSalesReportViewState();
}

class _VatSalesReportViewState extends State<VatSalesReportView> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ReportsProvider>();
      if (provider.vatSalesSummary.isEmpty && !provider.isLoadingVatSales) {
        provider.fetchVatSales();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectCustomDateRange(BuildContext context, ReportsProvider provider) async {
    final picked = await showCompactDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: provider.vatStartDate, end: provider.vatEndDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Seleccionar Período Fiscal (Libro IVA Ventas)',
    );
    if (picked != null) {
      provider.setVatDateRange(picked.start, picked.end);
    }
  }

  void _setCurrentMonth(ReportsProvider provider) {
    final now = DateTime.now();
    provider.setVatDateRange(DateTime(now.year, now.month, 1), now);
  }

  void _setPreviousMonth(ReportsProvider provider) {
    final now = DateTime.now();
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);
    final prevMonthEnd = DateTime(now.year, now.month, 0);
    provider.setVatDateRange(prevMonthStart, prevMonthEnd);
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
        final summary = provider.vatSalesSummary;
        final allVouchers = provider.vatSalesVouchers;
        final filter = provider.vatVoucherFilter;
        final q = provider.vatSearchQuery.trim().toLowerCase();

        final filteredVouchers = allVouchers.where((raw) {
          final v = raw is Map ? raw : <String, dynamic>{};
          final kind = (v['kind'] ?? 'invoice').toString();
          final letter = (v['voucher_letter'] ?? '').toString().toUpperCase();

          if (filter == 'NC' && kind != 'credit_note') return false;
          if (filter == 'A' && (kind != 'invoice' || letter != 'A')) return false;
          if (filter == 'B' && (kind != 'invoice' || letter != 'B')) return false;

          if (q.isNotEmpty) {
            final numStr = (v['formatted_number'] ?? '').toString().toLowerCase();
            final docStr = (v['doc_number'] ?? '').toString().toLowerCase();
            final nameStr = (v['receiver_name'] ?? '').toString().toLowerCase();
            final caeStr = (v['cae'] ?? '').toString().toLowerCase();
            if (!numStr.contains(q) && !docStr.contains(q) && !nameStr.contains(q) && !caeStr.contains(q)) {
              return false;
            }
          }
          return true;
        }).toList();

        final totalIva = _toDouble(summary['total_iva']);
        final totalNet = _toDouble(summary['total_net']);
        final netFiscalTotal = _toDouble(summary['net_fiscal_total']);
        final totalInvoiced = _toDouble(summary['total_invoiced']);
        final totalCreditNotes = _toDouble(summary['total_credit_notes']);
        final totalTributes = _toDouble(summary['total_tributes']);
        final totalExempt = _toDouble(summary['total_exempt']) + _toDouble(summary['total_untaxed']);

        final net21 = _toDouble(summary['net_21']);
        final iva21 = _toDouble(summary['iva_21']);
        final net105 = _toDouble(summary['net_105']);
        final iva105 = _toDouble(summary['iva_105']);
        final net27 = _toDouble(summary['net_27']);
        final iva27 = _toDouble(summary['iva_27']);

        final df = DateFormat('dd/MM/yyyy');
        final now = DateTime.now();
        final isCurrentMonth = provider.vatStartDate.year == now.year &&
            provider.vatStartDate.month == now.month &&
            provider.vatStartDate.day == 1 &&
            provider.vatEndDate.year == now.year &&
            provider.vatEndDate.month == now.month &&
            provider.vatEndDate.day == now.day;

        final prevStart = DateTime(now.year, now.month - 1, 1);
        final prevEnd = DateTime(now.year, now.month, 0);
        final isPreviousMonth = provider.vatStartDate.year == prevStart.year &&
            provider.vatStartDate.month == prevStart.month &&
            provider.vatStartDate.day == 1 &&
            provider.vatEndDate.year == prevEnd.year &&
            provider.vatEndDate.month == prevEnd.month &&
            provider.vatEndDate.day == prevEnd.day;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Barra Superior de Período Fiscal y Exportación Contable ──
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
                            Icon(Icons.account_balance_rounded, size: 16, color: Colors.indigo.shade800),
                            const SizedBox(width: 6),
                            Text(
                              'Subdiario Fiscal ARCA / AFIP (F. 2002)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildPeriodChip(
                        label: 'Mes Actual',
                        icon: Icons.today_rounded,
                        selected: isCurrentMonth,
                        onTap: () => _setCurrentMonth(provider),
                      ),
                      _buildPeriodChip(
                        label: 'Mes Anterior (Cerrar IVA)',
                        icon: Icons.history_rounded,
                        selected: isPreviousMonth,
                        onTap: () => _setPreviousMonth(provider),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _selectCustomDateRange(context, provider),
                        icon: const Icon(Icons.date_range, size: 16),
                        label: Text(
                          '${df.format(provider.vatStartDate)} - ${df.format(provider.vatEndDate)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.indigo.shade800,
                          side: BorderSide(color: Colors.indigo.shade200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      IconButton(
                        onPressed: provider.isLoadingVatSales ? null : () => provider.fetchVatSales(),
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Actualizar Libro IVA Ventas',
                        color: Colors.indigo,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: provider.isExportingVatExcel
                            ? null
                            : () async {
                                await provider.exportVatSalesToExcel();
                                if (!context.mounted) return;
                                if (provider.vatSalesError != null) {
                                  SnackBarService.error(context, provider.vatSalesError!);
                                } else {
                                  SnackBarService.success(
                                    context,
                                    'Libro IVA Ventas exportado a Excel (listo para enviar al contador).',
                                  );
                                }
                              },
                        icon: provider.isExportingVatExcel
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.table_view_rounded, size: 17),
                        label: Text(provider.isExportingVatExcel ? 'Exportando...' : 'Exportar Excel Contador'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: provider.isExportingVatPdf
                            ? null
                            : () async {
                                await provider.exportVatSalesToPdf();
                                if (!context.mounted) return;
                                if (provider.vatSalesError != null) {
                                  SnackBarService.error(context, provider.vatSalesError!);
                                } else {
                                  SnackBarService.success(
                                    context,
                                    'Subdiario Libro IVA Ventas exportado a PDF.',
                                  );
                                }
                              },
                        icon: provider.isExportingVatPdf
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.picture_as_pdf_rounded, size: 17),
                        label: Text(provider.isExportingVatPdf ? 'Generando...' : 'Exportar PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (provider.isLoadingVatSales)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (provider.vatSalesError != null && allVouchers.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400),
                      const SizedBox(height: 12),
                      Text(
                        provider.vatSalesError!,
                        style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => provider.fetchVatSales(),
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Tarjetas KPI Fiscales (Desglose F. 2002 ARCA / AFIP) ──
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 980;
                          final cards = [
                            // Card 1: IVA Débito Fiscal (El dato central para el contador)
                            _buildKpiCard(
                              title: 'IVA DÉBITO FISCAL A DECLARAR',
                              value: '\$${totalIva.toCurrency()}',
                              valueColor: Colors.amber.shade900,
                              icon: Icons.gavel_rounded,
                              iconBg: Colors.amber.shade50,
                              iconColor: Colors.amber.shade800,
                              subtitleWidget: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _buildAliquotBadge('IVA 21%', iva21, net21, Colors.amber.shade900, Colors.amber.shade50),
                                  _buildAliquotBadge('IVA 10.5%', iva105, net105, Colors.teal.shade800, Colors.teal.shade50),
                                  if (iva27 != 0 || net27 != 0)
                                    _buildAliquotBadge('IVA 27%', iva27, net27, Colors.purple.shade800, Colors.purple.shade50),
                                ],
                              ),
                            ),
                            // Card 2: Neto Gravado Total (Base Imponible sin IVA)
                            _buildKpiCard(
                              title: 'TOTAL NETO GRAVADO (SIN IVA)',
                              value: '\$${totalNet.toCurrency()}',
                              valueColor: const Color(0xFF1D4ED8),
                              icon: Icons.calculate_outlined,
                              iconBg: const Color(0xFFEFF6FF),
                              iconColor: const Color(0xFF1D4ED8),
                              subtitleWidget: Text(
                                'Neto 21%: \$${net21.toCurrency()} · Neto 10.5%: \$${net105.toCurrency()}${net27 != 0 ? " · 27%: \$${net27.toCurrency()}" : ""}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                              ),
                            ),
                            // Card 3: Total Facturado Fiscal Bruto (Neto de NC)
                            _buildKpiCard(
                              title: 'TOTAL FACTURADO FISCAL (CON IVA)',
                              value: '\$${netFiscalTotal.toCurrency()}',
                              valueColor: const Color(0xFF0F172A),
                              icon: Icons.receipt_long_rounded,
                              iconBg: const Color(0xFFF1F5F9),
                              iconColor: const Color(0xFF334155),
                              subtitleWidget: Text(
                                'Facturas: \$${totalInvoiced.toCurrency()}${totalCreditNotes > 0 ? " · Notas de Crédito: -\$${totalCreditNotes.toCurrency()}" : ""}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                              ),
                            ),
                            // Card 4: Percepciones IIBB y Exentos
                            _buildKpiCard(
                              title: 'PERCEPCIONES IIBB Y EXENTOS',
                              value: '\$${(totalTributes + totalExempt).toCurrency()}',
                              valueColor: Colors.deepPurple.shade800,
                              icon: Icons.account_balance_wallet_outlined,
                              iconBg: Colors.deepPurple.shade50,
                              iconColor: Colors.deepPurple.shade700,
                              subtitleWidget: Text(
                                'Percep. IIBB: \$${totalTributes.toCurrency()} · Exento / 0%: \$${totalExempt.toCurrency()}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ];

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 12, child: cards[0]),
                                const SizedBox(width: 12),
                                Expanded(flex: 10, child: cards[1]),
                                const SizedBox(width: 12),
                                Expanded(flex: 10, child: cards[2]),
                                const SizedBox(width: 12),
                                Expanded(flex: 9, child: cards[3]),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              for (int i = 0; i < cards.length; i++) ...[
                                if (i > 0) const SizedBox(height: 10),
                                cards[i],
                              ],
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // ── Panel de Detalle de Comprobantes Autorizados ──
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Barra de filtros internos de la tabla
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      const Text(
                                        'Comprobantes Autorizados (Con CAE)',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      _buildVoucherTypeFilterChip(
                                        provider: provider,
                                        value: 'ALL',
                                        label: 'Todos (${allVouchers.length})',
                                      ),
                                      _buildVoucherTypeFilterChip(
                                        provider: provider,
                                        value: 'A',
                                        label: 'Factura A',
                                      ),
                                      _buildVoucherTypeFilterChip(
                                        provider: provider,
                                        value: 'B',
                                        label: 'Factura B',
                                      ),
                                      _buildVoucherTypeFilterChip(
                                        provider: provider,
                                        value: 'NC',
                                        label: 'Notas de Crédito',
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    width: 280,
                                    child: TextField(
                                      controller: _searchCtrl,
                                      onChanged: provider.setVatSearchQuery,
                                      decoration: InputDecoration(
                                        hintText: 'Buscar N°, CUIT, cliente o CAE...',
                                        prefixIcon: const Icon(Icons.search, size: 18),
                                        suffixIcon: _searchCtrl.text.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(Icons.clear, size: 16),
                                                onPressed: () {
                                                  _searchCtrl.clear();
                                                  provider.setVatSearchQuery('');
                                                },
                                              )
                                            : null,
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),

                            if (filteredVouchers.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 48, color: Colors.blueGrey.shade200),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'No hay comprobantes fiscales autorizados en este período o filtro.',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: MediaQuery.of(context).size.width - 84,
                                  ),
                                  child: DataTable(
                                    headingRowColor: const WidgetStatePropertyAll(Color(0xFFF8FAFC)),
                                    headingTextStyle: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11.5,
                                      color: Color(0xFF334155),
                                    ),
                                    dataRowMinHeight: 42,
                                    dataRowMaxHeight: 54,
                                    columnSpacing: 18,
                                    columns: const [
                                      DataColumn(label: Text('FECHA')),
                                      DataColumn(label: Text('COMPROBANTE')),
                                      DataColumn(label: Text('NÚMERO')),
                                      DataColumn(label: Text('CLIENTE / RECEPTOR')),
                                      DataColumn(label: Text('NETO GRAV.'), numeric: true),
                                      DataColumn(label: Text('IVA 21%'), numeric: true),
                                      DataColumn(label: Text('IVA 10.5%'), numeric: true),
                                      DataColumn(label: Text('PERCEP. / EX.'), numeric: true),
                                      DataColumn(label: Text('TOTAL FISCAL'), numeric: true),
                                      DataColumn(label: Text('CAE')),
                                    ],
                                    rows: filteredVouchers.map((raw) {
                                      final v = raw is Map ? raw : <String, dynamic>{};
                                      final isNc = (v['kind'] ?? '') == 'credit_note';
                                      final letter = (v['voucher_letter'] ?? 'B').toString().toUpperCase();
                                      final label = (v['voucher_label'] ?? (isNc ? 'Nota de Crédito $letter' : 'Factura $letter')).toString();
                                      final issuedRaw = v['issued_at']?.toString();
                                      DateTime? issuedDt;
                                      if (issuedRaw != null && issuedRaw.isNotEmpty) {
                                        issuedDt = DateTime.tryParse(issuedRaw)?.toLocal();
                                      }
                                      final dateStr = issuedDt != null
                                          ? DateFormat('dd/MM/yyyy HH:mm').format(issuedDt)
                                          : '-';

                                      final vNet = _toDouble(v['net_amount']);
                                      final vIva21 = _toDouble(v['iva_21']);
                                      final vIva105 = _toDouble(v['iva_105']);
                                      final vIva27 = _toDouble(v['iva_27']);
                                      final vTribAndEx = _toDouble(v['tribute_amount']) +
                                          _toDouble(v['exempt_amount']) +
                                          _toDouble(v['untaxed_amount']) +
                                          vIva27;
                                      final vTotal = _toDouble(v['total_amount']);

                                      final badgeColor = isNc
                                          ? Colors.red.shade700
                                          : (letter == 'A' ? Colors.indigo.shade700 : Colors.blue.shade700);
                                      final badgeBg = isNc
                                          ? Colors.red.shade50
                                          : (letter == 'A' ? Colors.indigo.shade50 : Colors.blue.shade50);

                                      return DataRow(
                                        cells: [
                                          DataCell(Text(dateStr, style: const TextStyle(fontSize: 12))),
                                          DataCell(
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: badgeBg,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                                              ),
                                              child: Text(
                                                label,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: badgeColor,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              (v['formatted_number'] ?? '').toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12.5,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  (v['receiver_name'] ?? 'Consumidor Final').toString(),
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.2),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  'Doc: ${(v['doc_number'] ?? '0')} · ${(v['receiver_tax_condition'] ?? 'Consumidor Final')}',
                                                  style: const TextStyle(fontSize: 10.8, color: Color(0xFF64748B)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              '\$${vNet.toCurrency()}',
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                fontWeight: FontWeight.w600,
                                                color: isNc ? Colors.red.shade700 : const Color(0xFF1E293B),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              '\$${vIva21.toCurrency()}',
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                fontWeight: vIva21 != 0 ? FontWeight.w700 : FontWeight.normal,
                                                color: vIva21 != 0
                                                    ? (isNc ? Colors.red.shade700 : Colors.amber.shade900)
                                                    : Colors.grey.shade400,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              '\$${vIva105.toCurrency()}',
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                fontWeight: vIva105 != 0 ? FontWeight.w700 : FontWeight.normal,
                                                color: vIva105 != 0
                                                    ? (isNc ? Colors.red.shade700 : Colors.teal.shade800)
                                                    : Colors.grey.shade400,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              '\$${vTribAndEx.toCurrency()}',
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                color: vTribAndEx != 0 ? const Color(0xFF334155) : Colors.grey.shade400,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              '\$${vTotal.toCurrency()}',
                                              style: TextStyle(
                                                fontSize: 12.8,
                                                fontWeight: FontWeight.w800,
                                                color: isNc ? Colors.red.shade700 : const Color(0xFF0F172A),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            SelectableText(
                                              (v['cae'] ?? '').toString(),
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: Color(0xFF475569),
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
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

  Widget _buildPeriodChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.indigo.shade700 : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.indigo.shade700 : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : const Color(0xFF475569),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoucherTypeFilterChip({
    required ReportsProvider provider,
    required String value,
    required String label,
  }) {
    final selected = provider.vatVoucherFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => provider.setVatVoucherFilter(value),
      selectedColor: Colors.indigo.shade50,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: selected ? Colors.indigo.shade900 : const Color(0xFF475569),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required Color valueColor,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required Widget subtitleWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: valueColor,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          subtitleWidget,
        ],
      ),
    );
  }

  Widget _buildAliquotBadge(
    String label,
    double ivaAmount,
    double netAmount,
    Color textColor,
    Color bgColor,
  ) {
    return Tooltip(
      message: 'Neto Gravado: \$${netAmount.toCurrency()} · $label: \$${ivaAmount.toCurrency()}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: textColor.withValues(alpha: 0.25)),
        ),
        child: Text(
          '$label: \$${ivaAmount.toCurrency()}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
