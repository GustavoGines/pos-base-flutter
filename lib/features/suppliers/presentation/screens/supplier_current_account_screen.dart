import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import '../../providers/supplier_provider.dart';
import '../../../../core/presentation/widgets/global_app_bar.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../../../cash_movements/presentation/widgets/movement_form_dialog.dart';
import '../../../cash_movements/services/cash_movement_pdf_service.dart';
import '../../services/supplier_statement_pdf_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/utils/receipt_printer_service.dart';
import '../../../../core/presentation/widgets/print_format_selector.dart';
import '../../../../core/presentation/widgets/thermal_receipt_widget.dart';
import '../../../../core/presentation/widgets/ticket_preview_dialog.dart';
import '../../../../core/providers/local_terminal_provider.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../widgets/supplier_document_detail_dialog.dart';
import '../../../../core/utils/currency_formatter.dart';

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
  bool _isAccessDenied = false;
  String? _adminPin;
  List<dynamic> _history = [];
  List<dynamic> _filteredHistory = [];
  double _currentBalance = 0;
  String? _supplierCuit;
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
      _isAccessDenied = false;
    });

    try {
      final provider = context.read<SupplierProvider>();
      final data = await provider.fetchCurrentAccount(widget.supplierId, adminPin: _adminPin);
      if (mounted) {
        setState(() {
          _history = data['history'] ?? [];
          _currentBalance = double.tryParse(data['supplier']['balance'].toString()) ?? 0;
          _supplierCuit = data['supplier']?['cuit']?.toString();
          _isLoading = false;
          _applyFilter();
        });
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString();
        final isDenied = errorMsg.contains('Acceso denegado') || 
                         errorMsg.contains('403') || 
                         errorMsg.contains('permiso');
        setState(() {
          _error = errorMsg;
          _isAccessDenied = isDenied;
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilter() {
    List<dynamic> temp = List.from(_history);
    
    if (_filterType == 'invoices') {
      temp = temp.where((item) => item['type'] == 'invoice').toList();
    } else if (_filterType == 'delivery_notes') {
      temp = temp.where((item) => item['type'] == 'delivery_note').toList();
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

  Future<void> _reprintPaymentRow(
    dynamic item,
    DateTime issuedAt,
    double amount,
    double runningBalance,
    bool isIncrease,
  ) async {
    final format = await PrintFormatSelector.show(context);
    if (format == null || !mounted) return;

    final localTerminal = context.read<LocalTerminalProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final movId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final movType = item['type']?.toString() ?? 'supplier_payment';
    final pm = item['payment_method']?.toString() ?? 'cash';
    final fs = item['funding_source']?.toString() ??
        (pm == 'owner_funds' ? 'owner_funds' : 'cash_register');
    final payments = <Map<String, dynamic>>[
      {
        'payment_method': pm,
        'funding_source': fs,
        'amount': amount,
      }
    ];
    final balanceBefore =
        isIncrease ? runningBalance - amount : runningBalance + amount;
    final cashierLabel = item['user_name']?.toString();
    final desc = item['description']?.toString();
    final recNum = item['invoice_number']?.toString();

    if (format == 'a4') {
      await CashMovementPdfService.printSupplierPayment(
        context: context,
        type: movType,
        supplierName: widget.supplierName,
        supplierCuit: _supplierCuit,
        totalAmount: amount,
        balanceBefore: balanceBefore,
        payments: payments,
        businessName: settings?.companyName ?? 'MI NEGOCIO',
        businessTaxId: settings?.taxId,
        businessSettings: settings,
        movementIds: movId > 0 ? [movId] : const [],
        description: desc,
        receiptNumber: recNum,
        cashierName: cashierLabel,
        paperSize: localTerminal.pdfPaperSize,
        issuedAt: issuedAt,
      );
    } else if (format == 'thermal') {
      final isNarrow = localTerminal.printerFormat == 'thermal_58';
      ThermalPaperWidth chosenWidth =
          isNarrow ? ThermalPaperWidth.mm58 : ThermalPaperWidth.mm80;

      final confirmed = await TicketPreviewDialog.show(
        context,
        title: 'Vista Previa — Pago a Proveedor${movId > 0 ? " #$movId" : ""}',
        paperWidth: chosenWidth,
        onConfirmPrintWithWidth: (w) => chosenWidth = w,
        linesBuilder: (w) => CashMovementPdfService.buildSupplierPaymentTicketLines(
          type: movType,
          supplierName: widget.supplierName,
          supplierCuit: _supplierCuit,
          totalAmount: amount,
          balanceBefore: balanceBefore,
          payments: payments,
          businessName: settings?.companyName ?? 'MI NEGOCIO',
          businessAddress: settings?.address,
          businessTaxId: settings?.taxId,
          movementIds: movId > 0 ? [movId] : const [],
          description: desc,
          receiptNumber: recNum,
          cashierName: cashierLabel,
          issuedAt: issuedAt,
          is58mm: w == ThermalPaperWidth.mm58,
        ),
      );
      if (!confirmed || !mounted) return;

      if (localTerminal.printerConnection.toLowerCase() == 'none') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay ticketera física configurada en Ajustes > Hardware.'),
          ),
        );
        return;
      }

      if (settings != null) {
        await ReceiptPrinterService.instance.printSupplierPaymentTicket(
          type: movType,
          supplierName: widget.supplierName,
          supplierCuit: _supplierCuit,
          totalAmount: amount,
          balanceBefore: balanceBefore,
          payments: payments,
          settings: settings,
          localTerminal: localTerminal,
          movementIds: movId > 0 ? [movId] : const [],
          description: desc,
          receiptNumber: recNum,
          cashierName: cashierLabel,
          openDrawer: false,
          paperSizeOverride: chosenWidth == ThermalPaperWidth.mm58
              ? PaperSize.mm58
              : PaperSize.mm80,
        );
      }
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
      if (_isAccessDenied) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, color: Colors.orange.shade700, size: 64),
                const SizedBox(height: 20),
                Text(
                  'Acceso Restringido',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No tenés permisos para ver el estado de cuenta de este proveedor.\nPodés solicitar autorización ingresando el PIN del administrador.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  icon: const Icon(Icons.vpn_key, size: 20),
                  label: const Text('INGRESAR PIN DE ADMINISTRADOR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final pin = await showDialog<String>(
                      context: context,
                      barrierDismissible: true,
                      builder: (_) => const AdminPinDialog(actionDescription: 'Ver estado de cuenta de proveedor'),
                    );
                    if (pin != null && mounted) {
                      _adminPin = pin;
                      _loadData();
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Volver', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      }
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
                                 final localTerminal = context.read<LocalTerminalProvider>();
                                 SupplierStatementPdfService.printStatement(
                                   context: context,
                                   supplierName: widget.supplierName,
                                   supplierCuit: _supplierCuit,
                                   history: _filteredHistory,
                                   currentBalance: _currentBalance,
                                   businessName: settings?.companyName ?? 'MI NEGOCIO',
                                   businessTaxId: settings?.taxId ?? '',
                                   dateRange: _dateRange,
                                   paperSize: localTerminal.pdfPaperSize,
                                 );
                               } else if (format == 'thermal') {
                                 final localTerminal = context.read<LocalTerminalProvider>();
                                 final isNarrow = localTerminal.printerFormat == 'thermal_58';
                                 ThermalPaperWidth chosenWidth =
                                     isNarrow ? ThermalPaperWidth.mm58 : ThermalPaperWidth.mm80;

                                 final confirmed = await TicketPreviewDialog.show(
                                   context,
                                   title: 'Vista Previa — Estado de Cuenta',
                                   paperWidth: chosenWidth,
                                   onConfirmPrintWithWidth: (w) => chosenWidth = w,
                                   linesBuilder: (w) => CashMovementPdfService.buildSupplierStatementTicketLines(
                                     supplierName: widget.supplierName,
                                     currentBalance: _currentBalance,
                                     businessName: settings?.companyName ?? 'MI NEGOCIO',
                                     businessTaxId: settings?.taxId,
                                     supplierCuit: _supplierCuit,
                                     is58mm: w == ThermalPaperWidth.mm58,
                                   ),
                                 );
                                 if (!confirmed || !context.mounted) return;

                                 if (localTerminal.printerConnection.toLowerCase() == 'none') {
                                   ScaffoldMessenger.of(context).showSnackBar(
                                     const SnackBar(
                                       content: Text('No hay ticketera física configurada en Ajustes > Hardware.'),
                                     ),
                                   );
                                   return;
                                 }

                                 if (settings != null) {
                                   try {
                                     await ReceiptPrinterService.instance.printSupplierStatementTicket(
                                       supplierName: widget.supplierName,
                                       currentBalance: _currentBalance,
                                       settings: settings,
                                       localTerminal: localTerminal,
                                       supplierCuit: _supplierCuit,
                                       paperSizeOverride: chosenWidth == ThermalPaperWidth.mm58
                                           ? PaperSize.mm58
                                           : PaperSize.mm80,
                                     );
                                   } catch (e) {
                                     if (context.mounted) {
                                       ScaffoldMessenger.of(context).showSnackBar(
                                         SnackBar(content: Text('Error de impresión: $e')),
                                       );
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
                              final cashProv = context.read<CashRegisterProvider>();
                              if (!isDebt && (cashProv.currentShift == null || !cashProv.currentShift!.isOpen)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Debe abrir un turno de caja para ingresar un cobro de saldo a favor.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              await showDialog(
                                context: context,
                                barrierDismissible: true,
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
                        '\$${_currentBalance.abs().toCurrency()}',
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
                      final picked = await showCompactDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDateRange: _dateRange,
                        helpText: 'Filtrar Movimientos por Fecha',
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
                          DropdownMenuItem(value: 'invoices', child: Text('Solo Facturas')),
                          DropdownMenuItem(value: 'delivery_notes', child: Text('Solo Remitos')),
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
                  
                  final isIncrease = (item['source'] == 'invoice' &&
                          (item['type'] == 'invoice' || item['type'] == 'delivery_note')) ||
                      (item['source'] == 'payment' && item['type'] == 'deposit');

                  String actionLabel = '';
                  Color actionColor = Colors.grey;
                  IconData iconData = Icons.receipt;

                  if (item['source'] == 'invoice') {
                    if (item['type'] == 'delivery_note') {
                      actionLabel = 'Remito de Mercadería';
                      actionColor = Colors.indigo.shade700;
                      iconData = Icons.inventory_2_outlined;
                    } else if (item['type'] == 'credit_note') {
                      actionLabel = 'Nota de Crédito';
                      actionColor = Colors.green.shade600;
                      iconData = Icons.assignment_return;
                    } else {
                      actionLabel = 'Factura de Compra';
                      actionColor = Colors.red.shade600;
                      iconData = Icons.receipt_long;
                    }
                  } else {
                    actionLabel = item['type'] == 'deposit' ? 'Ajuste Saldo (Deuda)' : 'Pago Entregado';
                    actionColor = item['type'] == 'deposit' ? Colors.red.shade600 : Colors.green.shade600;
                    iconData = Icons.payments;
                  }

                  final amount = double.tryParse(item['amount'].toString()) ?? 0;
                  final runningBalance = double.tryParse(item['running_balance'].toString()) ?? 0;
                  final itemsCount = (item['items_count'] as num?)?.toInt() ?? 0;

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
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        onTap: item['source'] == 'invoice'
                          ? () {
                              showDialog(
                                context: context,
                                builder: (_) => SupplierDocumentDetailDialog(
                                  document: Map<String, dynamic>.from(item),
                                  supplierName: widget.supplierName,
                                  onChanged: _loadData,
                                ),
                              );
                            }
                          : null,
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
                          Flexible(
                            child: Text(
                              actionLabel,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item['invoice_number'] != null && item['invoice_number'].toString().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blueGrey.shade100),
                                ),
                                child: Text(
                                  'Nº ${item['invoice_number']}',
                                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          if (item['source'] == 'invoice') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$itemsCount art. • Ver detalle',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.indigo.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (item['is_edited'] == true ||
                                ((int.tryParse((item['edit_count'] ?? 0).toString()) ?? 0) > 0)) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.shade600),
                                ),
                                child: Text(
                                  'EDITADO (${item['edit_count'] ?? 1}x)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ] else if (item['source'] == 'payment' && item['payment_method'] != null) ...[
                            const SizedBox(width: 8),
                            Builder(builder: (context) {
                              final pm = item['payment_method'].toString();
                              final fs = item['funding_source']?.toString() ?? (pm == 'owner_funds' ? 'owner_funds' : 'cash_register');
                              final bool isOwnerFunds = fs == 'owner_funds' || pm == 'owner_funds';
                              final String baseMethod = pm == 'cash' || pm == 'owner_funds'
                                  ? 'Efectivo'
                                  : (pm == 'transfer'
                                      ? 'Transferencia'
                                      : (pm == 'card'
                                          ? 'Tarjeta'
                                          : (pm == 'check' ? 'Cheque' : pm.toUpperCase())));
                              final String pmLabel = pm == 'check'
                                  ? 'Cheque'
                                  : (isOwnerFunds
                                      ? '$baseMethod • Bolsillo'
                                      : (pm == 'cash' ? 'Efectivo • Caja' : baseMethod));
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOwnerFunds ? Colors.deepPurple.shade50 : Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isOwnerFunds ? Colors.deepPurple.shade200 : Colors.teal.shade200,
                                  ),
                                ),
                                child: Text(
                                  pmLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isOwnerFunds ? Colors.deepPurple.shade800 : Colors.teal.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }),
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
                            if (item['user_name'] != null) ...[
                              const SizedBox(width: 10),
                              const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                              const SizedBox(width: 3),
                              Text(item['user_name'].toString(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isIncrease ? '+' : '-'}\$${amount.toCurrency()}',
                                style: TextStyle(fontWeight: FontWeight.w900, color: actionColor, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Saldo: \$${runningBalance.toCurrency()}',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (item['source'] == 'payment') ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.print_outlined, size: 20, color: Colors.blueGrey),
                              tooltip: 'Imprimir / Vista Previa del Pago',
                              onPressed: () => _reprintPaymentRow(item, date, amount, runningBalance, isIncrease),
                            ),
                          ],
                        ],
                      ),
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

