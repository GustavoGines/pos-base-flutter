import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/sales_history/data/datasources/sales_history_remote_datasource.dart';
import 'package:intl/intl.dart';

/// Modal que muestra el detalle completo de un ticket (ítems + pagos)
/// al hacer clic en una transacción de Cuenta Corriente tipo "cargo".
class SaleDetailDialog extends StatefulWidget {
  final int saleId;
  final SalesHistoryRemoteDataSource dataSource;

  const SaleDetailDialog({
    super.key,
    required this.saleId,
    required this.dataSource,
  });

  /// Fábrica estática para abrir el modal correctamente.
  static Future<void> show(
    BuildContext context, {
    required int saleId,
    required SalesHistoryRemoteDataSource dataSource,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SaleDetailDialog(saleId: saleId, dataSource: dataSource),
    );
  }

  @override
  State<SaleDetailDialog> createState() => _SaleDetailDialogState();
}

class _SaleDetailDialogState extends State<SaleDetailDialog> {
  Map<String, dynamic>? _sale;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.dataSource.fetchSaleDetail(widget.saleId);
      if (mounted) setState(() { _sale = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: _isLoading
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? SizedBox(
                    height: 200,
                    child: Center(
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  )
                : _buildContent(_sale!),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> sale) {
    final items = (sale['items'] as List? ?? []);
    final payments = (sale['payments'] as List? ?? []);
    final createdAt = DateTime.tryParse(sale['created_at']?.toString() ?? '')?.toLocal();
    final dateStr = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt)
        : '—';

    final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
    final surcharge = double.tryParse(sale['total_surcharge']?.toString() ?? '0') ?? 0.0;
    final shipping = double.tryParse(sale['shipping_cost']?.toString() ?? '0') ?? 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ──
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
          decoration: BoxDecoration(
            color: Colors.indigo.shade700,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detalle Ticket #${sale['id']}',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(dateStr, style: TextStyle(color: Colors.indigo.shade100, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white70),
                tooltip: 'Cerrar',
              ),
            ],
          ),
        ),

        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Ítems ──
                const Text('Productos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      // Header tabla
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                        ),
                        child: const Row(
                          children: [
                            Expanded(child: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey))),
                            SizedBox(width: 60, child: Text('Cant.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey))),
                            SizedBox(width: 80, child: Text('P. Unit.', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey))),
                            SizedBox(width: 80, child: Text('Subtotal', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey))),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ...items.asMap().entries.map((entry) {
                        final i = entry.key;
                        final item = entry.value as Map<String, dynamic>;
                        final qty = double.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
                        final unitPrice = double.tryParse(item['unit_price']?.toString() ?? '0') ?? 0;
                        final subtotal = double.tryParse(item['subtotal']?.toString() ?? '0') ?? 0;
                        final productName = item['product_name']?.toString() ??
                            item['product']?['name']?.toString() ?? 'Producto eliminado';

                        return Column(
                          children: [
                            if (i > 0) const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(productName, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                                  ),
                                  SizedBox(width: 60, child: Text(qty.toQty(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14))),
                                  SizedBox(width: 80, child: Text('\$${unitPrice.toCurrency()}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 14))),
                                  SizedBox(width: 80, child: Text('\$${subtotal.toCurrency()}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Resumen Financiero ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      if (surcharge > 0) _summaryRow('Recargo', '\$${surcharge.toCurrency()}', color: Colors.orange.shade700),
                      if (shipping > 0) _summaryRow('Envío', '\$${shipping.toCurrency()}', color: Colors.teal),
                      _summaryRow(
                        'TOTAL',
                        '\$${(total + surcharge + shipping).toCurrency()}',
                        bold: true,
                        color: Colors.indigo.shade800,
                        fontSize: 18,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Métodos de Pago ──
                if (payments.isNotEmpty) ...[
                  const Text('Métodos de Pago', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
                  const SizedBox(height: 8),
                  ...payments.map((p) {
                    final method = (p['payment_method']?['name'] ?? 'Cuenta Corriente').toString();
                    final amount = double.tryParse(p['total_amount']?.toString() ?? '0') ?? 0;
                    final isCc = (p['payment_method']?['code'] ?? '').toString() == 'cuenta_corriente';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            isCc ? Icons.account_balance_wallet_outlined : Icons.payments_outlined,
                            size: 18,
                            color: isCc ? Colors.purple.shade600 : Colors.blueGrey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(method, style: const TextStyle(fontSize: 14))),
                          Text('\$${amount.toCurrency()}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isCc ? Colors.purple.shade700 : Colors.black87,
                              )),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),

        // ── Footer ──
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: FilledButton.tonal(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, Color? color, double fontSize = 14}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: fontSize, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color)),
          Text(value, style: TextStyle(fontSize: fontSize, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
