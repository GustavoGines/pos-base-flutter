import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/supplier_provider.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';

class SupplierCurrentAccountScreen extends StatefulWidget {
  final int supplierId;
  final String supplierName;

  const SupplierCurrentAccountScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  @override
  State<SupplierCurrentAccountScreen> createState() => _SupplierCurrentAccountScreenState();
}

class _SupplierCurrentAccountScreenState extends State<SupplierCurrentAccountScreen> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _history = [];
  List<dynamic> _filteredHistory = [];
  double _currentBalance = 0;
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<SupplierProvider>();
      final data = await provider.fetchCurrentAccount(widget.supplierId);
      if (mounted) {
        setState(() {
          _history = data['history'] ?? [];
          _currentBalance = double.tryParse(data['supplier']['balance'].toString()) ?? 0;
          _isLoading = false;
          _applyFilter();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilter() {
    if (_filterType == 'all') {
      _filteredHistory = List.from(_history);
    } else if (_filterType == 'invoices') {
      _filteredHistory = _history.where((item) => item['type'] == 'invoice').toList();
    } else if (_filterType == 'payments') {
      _filteredHistory = _history.where((item) => item['type'] == 'supplier_payment' || item['type'] == 'payment').toList();
    } else if (_filterType == 'credit_notes') {
      _filteredHistory = _history.where((item) => item['type'] == 'credit_note').toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlobalAppBar(
        currentRoute: '/suppliers/account',
        title: 'Cuenta Corriente: ${widget.supplierName}',
        showBackButton: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    final isDebt = _currentBalance > 0;
    final balanceColor = _currentBalance == 0 ? Colors.grey.shade700 : (isDebt ? Colors.red.shade700 : Colors.green.shade700);
    final balanceBg = _currentBalance == 0 ? Colors.grey.shade100 : (isDebt ? Colors.red.shade50 : Colors.green.shade50);
    final balanceLabel = _currentBalance == 0 ? 'Cuenta al día' : (isDebt ? 'DEUDA ACTUAL' : 'SALDO A FAVOR');

    return Column(
      children: [
        // Resumen
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: balanceBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: balanceColor.withValues(alpha: 0.3)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(balanceLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: balanceColor)),
              Text(
                NumberFormat.currency(symbol: '\$').format(_currentBalance.abs()),
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 32, color: balanceColor),
              ),
            ],
          ),
        ),

        // Filtros
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Filtrar por: ', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _filterType,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Todos los movimientos')),
                  DropdownMenuItem(value: 'invoices', child: Text('Solo Remitos/Facturas')),
                  DropdownMenuItem(value: 'payments', child: Text('Solo Pagos')),
                  DropdownMenuItem(value: 'credit_notes', child: Text('Notas de Crédito')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _filterType = val;
                      _applyFilter();
                    });
                  }
                },
              ),
            ],
          ),
        ),

        // Historial
        Expanded(
          child: _filteredHistory.isEmpty
            ? const Center(child: Text('No hay movimientos registrados para el filtro actual.'))
            : Container(
                margin: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: ListView.separated(
                  itemCount: _filteredHistory.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _filteredHistory[index];
                    final date = DateTime.tryParse(item['date'].toString()) ?? DateTime.now();
                    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(date);
                    
                    final isIncrease = (item['source'] == 'invoice' && item['type'] == 'invoice') || 
                                       (item['source'] == 'payment' && item['type'] == 'deposit');

                    String actionLabel = '';
                    Color actionColor = Colors.grey;
                    IconData iconData = Icons.receipt;

                    if (item['source'] == 'invoice') {
                      actionLabel = item['type'] == 'invoice' ? 'Factura/Remito' : 'Nota de Crédito';
                      actionColor = item['type'] == 'invoice' ? Colors.red.shade700 : Colors.green.shade700;
                      iconData = item['type'] == 'invoice' ? Icons.receipt_long : Icons.assignment_return;
                    } else {
                      actionLabel = item['type'] == 'deposit' ? 'Ajuste Saldo (Deuda)' : 'Pago Entregado';
                      actionColor = item['type'] == 'deposit' ? Colors.red.shade700 : Colors.green.shade700;
                      iconData = Icons.payments;
                    }

                    final amount = double.tryParse(item['amount'].toString()) ?? 0;
                    final runningBalance = double.tryParse(item['running_balance'].toString()) ?? 0;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: actionColor.withValues(alpha: 0.1),
                        foregroundColor: actionColor,
                        child: Icon(iconData, size: 20),
                      ),
                      title: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('$formattedDate ${item['invoice_number'] != null ? ' | Comp: ${item['invoice_number']}' : ''}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isIncrease ? '+' : '-'}\$${amount.toStringAsFixed(2)}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: actionColor, fontSize: 16),
                          ),
                          Text(
                            'Saldo: \$${runningBalance.toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
        ),
      ],
    );
  }
}
