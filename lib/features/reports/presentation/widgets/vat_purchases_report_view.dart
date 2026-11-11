import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../providers/reports_provider.dart';

class VatPurchasesReportView extends StatefulWidget {
  const VatPurchasesReportView({super.key});

  @override
  State<VatPurchasesReportView> createState() => _VatPurchasesReportViewState();
}

class _VatPurchasesReportViewState extends State<VatPurchasesReportView> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ReportsProvider>();
      if (provider.vatPurchasesSummary.isEmpty && !provider.isLoadingVatPurchases) {
        provider.fetchVatPurchases();
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
      initialDateRange: DateTimeRange(
        start: provider.vatPurchasesStartDate,
        end: provider.vatPurchasesEndDate,
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Seleccionar Período Fiscal (Libro IVA Compras)',
    );
    if (picked != null) {
      provider.setVatPurchasesDateRange(picked.start, picked.end);
    }
  }

  void _setCurrentMonth(ReportsProvider provider) {
    final now = DateTime.now();
    provider.setVatPurchasesDateRange(DateTime(now.year, now.month, 1), now);
  }

  void _setPreviousMonth(ReportsProvider provider) {
    final now = DateTime.now();
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);
    final prevMonthEnd = DateTime(now.year, now.month, 0);
    provider.setVatPurchasesDateRange(prevMonthStart, prevMonthEnd);
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  String _formatMoney(double amount) {
    if (amount < 0) {
      return '-\$${amount.abs().toCurrency()}';
    }
    return '\$${amount.toCurrency()}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReportsProvider>(
      builder: (context, provider, _) {
        final summary = provider.vatPurchasesSummary;
        final allVouchers = provider.vatPurchasesVouchers;
        final filter = provider.vatPurchasesFilter;
        final q = provider.vatPurchasesSearchQuery.trim().toLowerCase();

        final filteredVouchers = allVouchers.where((raw) {
          final v = raw is Map ? raw : <String, dynamic>{};
          final kind = (v['kind'] ?? v['type'] ?? 'invoice').toString();
          final letter = (v['voucher_letter'] ?? '').toString().toUpperCase();

          if (filter == 'NC' && kind != 'credit_note') return false;
          if (filter == 'A' && (kind == 'credit_note' || (letter != 'A' && letter != 'M'))) return false;
          if (filter == 'B_C' && (kind == 'credit_note' || (letter != 'B' && letter != 'C'))) return false;

          if (q.isNotEmpty) {
            final numStr = (v['formatted_number'] ?? v['invoice_number'] ?? '').toString().toLowerCase();
            final provName = (v['supplier_name'] ?? '').toString().toLowerCase();
            final cuit = (v['supplier_cuit'] ?? '').toString().toLowerCase();
            if (!numStr.contains(q) && !provName.contains(q) && !cuit.contains(q)) {
              return false;
            }
          }
          return true;
        }).toList();

        final totalCreditFiscal = _toDouble(summary['total_credit_fiscal'] ?? summary['total_iva']);
        final totalNet = _toDouble(summary['total_net']);
        final totalAmount = _toDouble(summary['total_amount']);
        final ivaPerception = _toDouble(summary['total_iva_perception'] ?? summary['iva_perceptions']);
        final iibbPerception = _toDouble(summary['total_iibb_perception'] ?? summary['iibb_perceptions']);
        final internalTaxes = _toDouble(summary['total_internal_taxes']);
        final totalPerceptions = ivaPerception + iibbPerception + internalTaxes;
        final totalNonTaxed = _toDouble(summary['total_non_taxed']) + _toDouble(summary['total_exempt']);

        final net21 = _toDouble(summary['total_net_21'] ?? summary['net_21']);
        final iva21 = _toDouble(summary['total_iva_21'] ?? summary['iva_21']);
        final net105 = _toDouble(summary['total_net_105'] ?? summary['net_105']);
        final iva105 = _toDouble(summary['total_iva_105'] ?? summary['iva_105']);
        final net27 = _toDouble(summary['total_net_27'] ?? summary['net_27']);
        final iva27 = _toDouble(summary['total_iva_27'] ?? summary['iva_27']);

        final invoicesCount = summary['invoices_count'] ?? 0;
        final creditNotesCount = summary['credit_notes_count'] ?? 0;

        final df = DateFormat('dd/MM/yyyy');
        final now = DateTime.now();
        final isCurrentMonth = provider.vatPurchasesStartDate.year == now.year &&
            provider.vatPurchasesStartDate.month == now.month &&
            provider.vatPurchasesStartDate.day == 1 &&
            provider.vatPurchasesEndDate.year == now.year &&
            provider.vatPurchasesEndDate.month == now.month &&
            provider.vatPurchasesEndDate.day == now.day;

        final prevStart = DateTime(now.year, now.month - 1, 1);
        final prevEnd = DateTime(now.year, now.month, 0);
        final isPreviousMonth = provider.vatPurchasesStartDate.year == prevStart.year &&
            provider.vatPurchasesStartDate.month == prevStart.month &&
            provider.vatPurchasesStartDate.day == 1 &&
            provider.vatPurchasesEndDate.year == prevEnd.year &&
            provider.vatPurchasesEndDate.month == prevEnd.month &&
            provider.vatPurchasesEndDate.day == prevEnd.day;

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
                            Icon(Icons.inventory_2_outlined, size: 16, color: Colors.indigo.shade800),
                            const SizedBox(width: 6),
                            Text(
                              'Subdiario Fiscal ARCA / AFIP (Libro IVA Compras)',
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
                          '${df.format(provider.vatPurchasesStartDate)} - ${df.format(provider.vatPurchasesEndDate)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.indigo.shade800,
                          side: BorderSide(color: Colors.indigo.shade200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      IconButton(
                        onPressed: provider.isLoadingVatPurchases ? null : () => provider.fetchVatPurchases(),
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Actualizar Libro IVA Compras',
                        color: Colors.indigo,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: provider.isExportingVatPurchasesExcel
                            ? null
                            : () async {
                                await provider.exportVatPurchasesToExcel();
                                if (!context.mounted) return;
                                if (provider.vatPurchasesError != null) {
                                  SnackBarService.error(context, provider.vatPurchasesError!);
                                } else {
                                  SnackBarService.success(
                                    context,
                                    'Libro IVA Compras exportado a Excel (listo para enviar al contador).',
                                  );
                                }
                              },
                        icon: provider.isExportingVatPurchasesExcel
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.table_view_rounded, size: 17),
                        label: Text(
                          provider.isExportingVatPurchasesExcel ? 'Exportando...' : 'Exportar Excel Contador',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: provider.isExportingVatPurchasesPdf
                            ? null
                            : () async {
                                await provider.exportVatPurchasesToPdf();
                                if (!context.mounted) return;
                                if (provider.vatPurchasesError != null) {
                                  SnackBarService.error(context, provider.vatPurchasesError!);
                                } else {
                                  SnackBarService.success(
                                    context,
                                    'Subdiario Libro IVA Compras exportado a PDF.',
                                  );
                                }
                              },
                        icon: provider.isExportingVatPurchasesPdf
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.picture_as_pdf_rounded, size: 17),
                        label: Text(
                          provider.isExportingVatPurchasesPdf ? 'Generando...' : 'Exportar PDF',
                        ),
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

            if (provider.isLoadingVatPurchases)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (provider.vatPurchasesError != null && allVouchers.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400),
                      const SizedBox(height: 12),
                      Text(
                        provider.vatPurchasesError!,
                        style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => provider.fetchVatPurchases(),
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
                      // ── Tarjetas KPI Fiscales de Compras ──
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 980;
                          final cards = [
                            // Card 1: Crédito Fiscal Total (A favor para deducir)
                            _buildKpiCard(
                              title: 'CRÉDITO FISCAL TOTAL (A DESCONTAR)',
                              value: _formatMoney(totalCreditFiscal),
                              valueColor: Colors.teal.shade800,
                              icon: Icons.savings_outlined,
                              iconBg: Colors.teal.shade50,
                              iconColor: Colors.teal.shade800,
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
                            // Card 2: Total Neto Gravado Compras
                            _buildKpiCard(
                              title: 'TOTAL NETO GRAVADO (COMPRAS)',
                              value: _formatMoney(totalNet),
                              valueColor: const Color(0xFF1D4ED8),
                              icon: Icons.calculate_outlined,
                              iconBg: const Color(0xFFEFF6FF),
                              iconColor: const Color(0xFF1D4ED8),
                              subtitleWidget: Text(
                                'Neto 21%: ${_formatMoney(net21)} · Neto 10.5%: ${_formatMoney(net105)}${net27 != 0 ? " · 27%: ${_formatMoney(net27)}" : ""}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                              ),
                            ),
                            // Card 3: Percepciones Sufridas
                            _buildKpiCard(
                              title: 'PERCEPCIONES SUFRIDAS',
                              value: _formatMoney(totalPerceptions),
                              valueColor: Colors.deepPurple.shade800,
                              icon: Icons.assignment_turned_in_outlined,
                              iconBg: Colors.deepPurple.shade50,
                              iconColor: Colors.deepPurple.shade700,
                              subtitleWidget: Text(
                                'IVA: ${_formatMoney(ivaPerception)} · IIBB: ${_formatMoney(iibbPerception)}${internalTaxes != 0 ? " · Int: ${_formatMoney(internalTaxes)}" : ""}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                              ),
                            ),
                            // Card 4: Total Compras Registradas
                            _buildKpiCard(
                              title: 'TOTAL COMPRAS FACTURADAS',
                              value: _formatMoney(totalAmount),
                              valueColor: const Color(0xFF0F172A),
                              icon: Icons.shopping_bag_outlined,
                              iconBg: const Color(0xFFF1F5F9),
                              iconColor: const Color(0xFF334155),
                              subtitleWidget: Text(
                                'Facturas: $invoicesCount · NC: $creditNotesCount${totalNonTaxed > 0 ? " · No Grav/Ex: ${_formatMoney(totalNonTaxed)}" : ""}',
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

                      // ── Panel de Detalle de Comprobantes ──
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
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      _buildFilterChip(
                                        label: 'Todos (${allVouchers.length})',
                                        selected: filter == 'ALL',
                                        onTap: () => provider.setVatPurchasesFilter('ALL'),
                                      ),
                                      _buildFilterChip(
                                        label: 'Factura A',
                                        selected: filter == 'A',
                                        onTap: () => provider.setVatPurchasesFilter('A'),
                                      ),
                                      _buildFilterChip(
                                        label: 'Factura B/C',
                                        selected: filter == 'B_C',
                                        onTap: () => provider.setVatPurchasesFilter('B_C'),
                                      ),
                                      _buildFilterChip(
                                        label: 'Notas de Crédito',
                                        selected: filter == 'NC',
                                        color: Colors.red.shade700,
                                        onTap: () => provider.setVatPurchasesFilter('NC'),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    width: 280,
                                    height: 38,
                                    child: TextField(
                                      controller: _searchCtrl,
                                      onChanged: (val) => provider.setVatPurchasesSearchQuery(val),
                                      decoration: InputDecoration(
                                        hintText: 'Buscar proveedor, CUIT o Nº...',
                                        hintStyle: const TextStyle(fontSize: 12.5, color: Colors.grey),
                                        prefixIcon: const Icon(Icons.search, size: 18),
                                        suffixIcon: provider.vatPurchasesSearchQuery.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(Icons.clear, size: 16),
                                                onPressed: () {
                                                  _searchCtrl.clear();
                                                  provider.setVatPurchasesSearchQuery('');
                                                },
                                              )
                                            : null,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                        ),
                                      ),
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),

                            // Tabla de Comprobantes
                            if (filteredVouchers.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 48),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      Text(
                                        allVouchers.isEmpty
                                            ? 'No se registran compras fiscales en este período.'
                                            : 'No se encontraron comprobantes con los filtros seleccionados.',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                      ),
                                    ],
                                  ),
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
                                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                    dataRowMinHeight: 46,
                                    dataRowMaxHeight: 52,
                                    columnSpacing: 20,
                                    horizontalMargin: 20,
                                    columns: const [
                                      DataColumn(label: Text('FECHA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                                      DataColumn(label: Text('COMPROBANTE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                                      DataColumn(label: Text('NÚMERO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                                      DataColumn(label: Text('PROVEEDOR / CUIT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                                      DataColumn(label: Text('NETO GRAV.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)), numeric: true),
                                      DataColumn(label: Text('IVA 21%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)), numeric: true),
                                      DataColumn(label: Text('IVA 10.5%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)), numeric: true),
                                      DataColumn(label: Text('IVA 27%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)), numeric: true),
                                      DataColumn(label: Text('NO GRAV. / EX.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)), numeric: true),
                                      DataColumn(label: Text('PERCEP. / OTROS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)), numeric: true),
                                      DataColumn(label: Text('TOTAL COMPRA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)), numeric: true),
                                    ],
                                    rows: filteredVouchers.map((raw) {
                                      final v = raw is Map ? raw : <String, dynamic>{};
                                      final kind = (v['kind'] ?? v['type'] ?? 'invoice').toString();
                                      final isNC = kind == 'credit_note';
                                      final isHistorical = v['is_historical'] == true;
                                      final rawLetter = (v['voucher_letter'] ?? '').toString().trim().toUpperCase();
                                      final letter = rawLetter.isNotEmpty
                                          ? rawLetter
                                          : (isHistorical && _toDouble(v['iva_21']) == 0 && _toDouble(v['credit_fiscal']) == 0 ? 'S/D' : 'A');

                                      final rawDate = v['issue_date'] ?? v['date'];
                                      String dateStr = '---';
                                      if (rawDate != null) {
                                        final parsed = DateTime.tryParse(rawDate.toString())?.toLocal();
                                        if (parsed != null) dateStr = df.format(parsed);
                                      }

                                      final numStr = (v['formatted_number'] ?? v['invoice_number'] ?? '---').toString();
                                      final provName = (v['supplier_name'] ?? 'Proveedor General').toString();
                                      final cuit = (v['supplier_cuit'] ?? '').toString();

                                      final vNet = _toDouble(v['net_21']) + _toDouble(v['net_105']) + _toDouble(v['net_27']);
                                      final vIva21 = _toDouble(v['iva_21']);
                                      final vIva105 = _toDouble(v['iva_105']);
                                      final vIva27 = _toDouble(v['iva_27']);
                                      final vNonTaxed = _toDouble(v['non_taxed_amount']) + _toDouble(v['exempt_amount']);
                                      final vPercep = _toDouble(v['iva_perception']) +
                                          _toDouble(v['iibb_perception']) +
                                          _toDouble(v['internal_taxes']);
                                      final vTotal = _toDouble(v['total_amount'] ?? v['amount']);

                                      final textColor = isNC ? Colors.red.shade800 : const Color(0xFF1E293B);

                                      return DataRow(
                                        cells: [
                                          DataCell(Text(dateStr, style: const TextStyle(fontSize: 12))),
                                          DataCell(_buildVoucherBadge(kind, letter)),
                                          DataCell(
                                            Text(
                                              numStr,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  provName,
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                if (cuit.isNotEmpty)
                                                  Text(
                                                    cuit,
                                                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          DataCell(Text(_formatMoney(vNet), style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w600))),
                                          DataCell(Text(_formatMoney(vIva21), style: TextStyle(fontSize: 12, color: textColor))),
                                          DataCell(Text(_formatMoney(vIva105), style: TextStyle(fontSize: 12, color: textColor))),
                                          DataCell(Text(_formatMoney(vIva27), style: TextStyle(fontSize: 12, color: textColor))),
                                          DataCell(Text(_formatMoney(vNonTaxed), style: TextStyle(fontSize: 12, color: textColor))),
                                          DataCell(Text(_formatMoney(vPercep), style: TextStyle(fontSize: 12, color: textColor))),
                                          DataCell(
                                            Text(
                                              _formatMoney(vTotal),
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.bold,
                                                color: isNC ? Colors.red.shade800 : const Color(0xFF0F172A),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.indigo.shade700 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.indigo.shade700 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : Colors.blueGrey.shade700,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? Colors.white : Colors.blueGrey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final activeColor = color ?? Colors.indigo.shade700;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? Colors.white : Colors.blueGrey.shade800,
          ),
        ),
      ),
    );
  }

  Widget _buildVoucherBadge(String kind, String letter) {
    if (kind == 'credit_note') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Text(
          'NC $letter',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.red.shade900,
          ),
        ),
      );
    }

    Color bg;
    Color border;
    Color text;
    if (letter == 'A') {
      bg = Colors.indigo.shade50;
      border = Colors.indigo.shade200;
      text = Colors.indigo.shade900;
    } else if (letter == 'B') {
      bg = Colors.lightBlue.shade50;
      border = Colors.lightBlue.shade200;
      text = Colors.lightBlue.shade900;
    } else if (letter == 'C') {
      bg = Colors.amber.shade50;
      border = Colors.amber.shade300;
      text = Colors.amber.shade900;
    } else {
      bg = Colors.grey.shade100;
      border = Colors.grey.shade300;
      text = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        letter == 'S/D' ? 'COMP. S/D' : 'FAC $letter',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required Color valueColor,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    Widget? subtitleWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: valueColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (subtitleWidget != null) ...[
            const SizedBox(height: 6),
            subtitleWidget,
          ],
        ],
      ),
    );
  }

  Widget _buildAliquotBadge(String label, double ivaAmount, double netAmount, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: \$${ivaAmount.toCurrency()}',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}
