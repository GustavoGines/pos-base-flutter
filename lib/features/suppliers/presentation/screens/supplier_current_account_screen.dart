import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/supplier_provider.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import '../../../cash_movements/presentation/widgets/movement_form_dialog.dart';
import '../../services/supplier_statement_pdf_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/utils/receipt_printer_service.dart';
import '../../../../core/presentation/widgets/print_format_selector.dart';
import '../../../../core/providers/local_terminal_provider.dart';

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
  DateTimeRange? _dateRange;

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
    List<dynamic> temp = List.from(_history);
    
    if (_filterType == 'invoices') {
      temp = temp.where((item) => item['type'] == 'invoice').toList();
    } else if (_filterType == 'payments') {
      temp = temp.where((item) => item['type'] == 'supplier_payment' || item['type'] == 'payment').toList();
    } else if (_filterType == 'credit_notes') {
      temp = temp.where((item) => item['type'] == 'credit_note').toList();
    }

    if (_dateRange != null) {
      temp = temp.where((item) {
        final dateStr = item['date'] ?? item['created_at'];
        if (dateStr == null) return true;
        try {
          final dt = DateTime.parse(dateStr.toString());
          final start = _dateRange!.start.subtract(const Duration(milliseconds: 1));
          final end = _dateRange!.end.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
          return dt.isAfter(start) && dt.isBefore(end);
        } catch (e) {
          return true;
        }
      }).toList();
    }

    _filteredHistory = temp;
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

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          children: [
            // Cabecera Profesional
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Identidad y Acciones
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ESTADO DE CUENTA', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text(
                      widget.supplierName,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: const Text('Imprimir Historial'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey.shade50,
                            foregroundColor: Colors.blueGrey.shade800,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onPressed: () async {
                               final settings = context.read<SettingsProvider>().settings;
                               
                               final format = await PrintFormatSelector.show(context);
                               if (format == null) return;
                               if (!context.mounted) return;

                               if (format == 'a4') {
                                 SupplierStatementPdfService.printStatement(
                                   context: context,
                                   supplierName: widget.supplierName,
                                   supplierCuit: null, // Si estuviera en el modelo lo pasaríamos
                                   history: _filteredHistory,
                                   currentBalance: _currentBalance,
                                   businessName: settings?.companyName ?? 'MI NEGOCIO',
                                   businessTaxId: settings?.taxId ?? '',
                                   dateRange: _dateRange,
                                 );
                               } else if (format == 'thermal') {
                                 if (settings != null) {
                                   try {
                                     await ReceiptPrinterService.instance.printSupplierStatementTicket(
                                       supplierName: widget.supplierName,
                                       currentBalance: _currentBalance,
                                       settings: settings,
                                       localTerminal: context.read<LocalTerminalProvider>(),
                                       supplierCuit: null,
                                     );
                                   } catch (e) {
                                     if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de impresión: $e')));
                                     }
                                   }
                                 }
                               }
                          },
                        ),
                        if (_currentBalance != 0)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.payments_outlined, size: 18),
                            label: Text(isDebt ? 'Abonar Saldo' : 'Cobrar Saldo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDebt ? Colors.red.shade600 : Colors.green.shade600,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onPressed: () async {
                              await showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => MovementFormDialog(
                                  initialSupplierId: widget.supplierId,
                                  initialType: 'supplier_payment',
                                ),
                              );
                              _loadData();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Divisor
              Container(
                width: 1,
                height: 80,
                color: Colors.grey.shade200,
                margin: const EdgeInsets.symmetric(horizontal: 32),
              ),

              // KPI Deuda
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: balanceBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: balanceColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(balanceLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: balanceColor)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 42,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        NumberFormat.currency(symbol: '\$').format(_currentBalance.abs()),
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 36, color: balanceColor),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Filtros
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: Text(_dateRange == null 
                        ? 'Filtrar por Fecha' 
                        : '${DateFormat('dd/MM').format(_dateRange!.start)} - ${DateFormat('dd/MM').format(_dateRange!.end)}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueGrey.shade700,
                      side: BorderSide(color: Colors.blueGrey.shade200),
                    ),
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDateRange: _dateRange,
                        builder: (context, child) {
                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 500,
                                maxHeight: 600,
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.light(
                                    primary: Colors.blue,
                                    onPrimary: Colors.white,
                                    onSurface: Colors.black,
                                  ),
                                ),
                                child: child!,
                              ),
                            ),
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          _dateRange = picked;
                          _applyFilter();
                        });
                      }
                    },
                  ),
                  if (_dateRange != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      tooltip: 'Quitar filtro de fecha',
                      onPressed: () {
                        setState(() {
                          _dateRange = null;
                          _applyFilter();
                        });
                      }
                    ),
                  ]
                ],
              ),
              Row(
                children: [
                  const Text('Tipo: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blueGrey.shade200),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filterType,
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.blueGrey),
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
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Historial
        Expanded(
          child: _filteredHistory.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('No hay movimientos registrados.', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 24),
                itemCount: _filteredHistory.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _filteredHistory[index];
                  final date = DateTime.tryParse(item['date'].toString()) ?? DateTime.now();
                  final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(date);
                  
                  final isIncrease = (item['source'] == 'invoice' && item['type'] == 'invoice') || 
                                     (item['source'] == 'payment' && item['type'] == 'deposit');

                  String actionLabel = '';
                  Color actionColor = Colors.grey;
                  IconData iconData = Icons.receipt;

                  if (item['source'] == 'invoice') {
                    actionLabel = item['type'] == 'invoice' ? 'Factura / Remito' : 'Nota de Crédito';
                    actionColor = item['type'] == 'invoice' ? Colors.red.shade600 : Colors.green.shade600;
                    iconData = item['type'] == 'invoice' ? Icons.receipt_long : Icons.assignment_return;
                  } else {
                    actionLabel = item['type'] == 'deposit' ? 'Ajuste Saldo (Deuda)' : 'Pago Entregado';
                    actionColor = item['type'] == 'deposit' ? Colors.red.shade600 : Colors.green.shade600;
                    iconData = Icons.payments;
                  }

                  final amount = double.tryParse(item['amount'].toString()) ?? 0;
                  final runningBalance = double.tryParse(item['running_balance'].toString()) ?? 0;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(iconData, size: 22, color: actionColor),
                      ),
                      title: Row(
                        children: [
                          Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          if (item['invoice_number'] != null && item['invoice_number'].toString().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blueGrey.shade100),
                              ),
                              child: Text('Nº ${item['invoice_number']}', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(formattedDate, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isIncrease ? '+' : '-'}\$${amount.toStringAsFixed(2)}',
                            style: TextStyle(fontWeight: FontWeight.w900, color: actionColor, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Saldo: \$${runningBalance.toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
        ),
      ),
    );
  }
}

