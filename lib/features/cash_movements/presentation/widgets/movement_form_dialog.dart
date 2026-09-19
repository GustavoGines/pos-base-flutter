import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/cash_movement_provider.dart';
import '../../../suppliers/providers/supplier_provider.dart';
import '../../../checks/presentation/providers/check_provider.dart';
import '../../../checks/domain/entities/third_party_check.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../suppliers/presentation/widgets/supplier_invoice_form_dialog.dart';
import '../../../../core/utils/receipt_printer_service.dart';
import '../../../../core/providers/local_terminal_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../services/cash_movement_pdf_service.dart';

class PaymentItem {
  final String method;
  final double amount;
  final int? checkId;
  final ThirdPartyCheck? checkObj;

  PaymentItem({
    required this.method,
    required this.amount,
    this.checkId,
    this.checkObj,
  });
}

class MovementFormDialog extends StatefulWidget {
  final int? initialSupplierId;
  final String? initialType;
  final String? initialCategory;
  final double? initialAmount;
  final String? helperText;

  const MovementFormDialog({
    super.key,
    this.initialSupplierId,
    this.initialType,
    this.initialCategory,
    this.initialAmount,
    this.helperText,
  });

  @override
  State<MovementFormDialog> createState() => _MovementFormDialogState();
}

class _MovementFormDialogState extends State<MovementFormDialog> {
  final _formKey = GlobalKey<FormState>();
  
  late String _type;
  late String _category;
  
  final _descriptionController = TextEditingController();
  final _receiptController = TextEditingController();
  
  int? _selectedSupplierId;
  bool _isLoading = false;

  // Pagos mixtos
  final List<PaymentItem> _payments = [];
  String _currentPaymentMethod = 'cash';
  int? _currentCheckId;
  final _paymentAmountController = TextEditingController();

  // Impresión
  bool _printReceipt = true;

  List<String> get _currentCategories {
    if (_type == 'deposit') {
      return ['Ingreso Extra', 'Cobro de Saldo a Favor', 'Otros'];
    }
    return [
      'Mercadería',
      'Sueldos',
      'Limpieza',
      'Impuestos',
      'Pago a Proveedor',
      'Otros'
    ];
  }

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? 'expense';
    _category = widget.initialCategory ?? 'Mercadería';
    _selectedSupplierId = widget.initialSupplierId;
    
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _payments.add(PaymentItem(method: 'cash', amount: widget.initialAmount!));
    }

    _paymentAmountController.addListener(() {
      setState(() {}); // Re-render to update live total
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SupplierProvider>().fetchSuppliers();
      context.read<CheckProvider>().loadChecks();
      // Cargar preferencia de impresión y verificar si hay impresora
      _loadPrintPreference();
    });
  }

  Future<void> _loadPrintPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final localTerminal = context.read<LocalTerminalProvider>();
    final hasPrinter = localTerminal.printerConnection.toLowerCase() != 'none' || localTerminal.printerFormat.toLowerCase().startsWith('a4');
    if (mounted) {
      setState(() {
        _printReceipt = hasPrinter && (prefs.getBool('auto_print_cash_movement') ?? true);
      });
    }
  }

  Future<void> _savePrintPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_print_cash_movement', value);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _receiptController.dispose();
    _paymentAmountController.dispose();
    super.dispose();
  }

  double get _totalAmount {
    final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
    final pendingSum = double.tryParse(_paymentAmountController.text) ?? 0;
    return listSum + pendingSum;
  }

  void _addPayment() {
    final amount = double.tryParse(_paymentAmountController.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingrese un monto válido.')));
      return;
    }
    
    ThirdPartyCheck? checkObj;
    if (_currentPaymentMethod == 'check') {
      if (_currentCheckId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleccione un cheque.')));
        return;
      }
      final checks = context.read<CheckProvider>().checks;
      checkObj = checks.firstWhere((c) => c.id == _currentCheckId);
    }

    setState(() {
      _payments.add(PaymentItem(
        method: _currentPaymentMethod,
        amount: amount,
        checkId: _currentCheckId,
        checkObj: checkObj,
      ));
      _paymentAmountController.clear();
      _currentCheckId = null;
    });
  }

  void _removePayment(int index) {
    setState(() {
      _payments.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Auto-agregar el pago si el usuario lo escribió pero olvidó presionar "Agregar"
    final pendingAmount = double.tryParse(_paymentAmountController.text) ?? 0;
    if (pendingAmount > 0) {
      _addPayment();
    }

    if (_payments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agregue al menos un método de pago.')));
      return;
    }

    if (_type == 'withdrawal') {
      final auth = context.read<AuthProvider>();
      if (auth.isAdmin) {
        await _executeSubmit();
        return;
      }

      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AdminPinDialog(actionDescription: 'Autorizar Retiro de Caja'),
      );

      if (pin == null) return;
      await _executeSubmit(adminPin: pin);
    } else {
      await _executeSubmit();
    }
  }

  Future<void> _executeSubmit({String? adminPin}) async {
    setState(() => _isLoading = true);

    try {
      final provider = context.read<CashMovementProvider>();
      final localTerminal = context.read<LocalTerminalProvider>();
      final settingsProvider = context.read<SettingsProvider>();
      final supplierProvider = context.read<SupplierProvider>();
      final settings = settingsProvider.settings!;
      final authProvider = context.read<AuthProvider>();
      
      // ══ CAPTURA TEMPRANA: Saldo del proveedor ANTES del POST ══
      double? balanceBeforePayment;
      String? supplierName;
      String? supplierCuit;
      if (_selectedSupplierId != null) {
        final supps = supplierProvider.suppliers.where((s) => s.id == _selectedSupplierId);
        if (supps.isNotEmpty) {
          balanceBeforePayment = supps.first.balance;
          supplierName = supps.first.name;
          supplierCuit = supps.first.cuit;
        }
      }
      
      final data = {
        'type': _type,
        'category': _category,
        'description': _descriptionController.text,
        'receipt_number': _receiptController.text,
        'supplier_id': _selectedSupplierId,
        'payments': _payments.map((p) => {
          'amount': p.amount,
          'payment_method': p.method,
          'check_id': p.checkId,
        }).toList()
      };

      // ══ 1. GUARDAR EN BASE DE DATOS (prioridad absoluta) ══
      final createdIds = await provider.createMovement(data, adminPin: adminPin);
      
      if (mounted && _selectedSupplierId != null) {
        supplierProvider.fetchSuppliers();
      }

      // ══ 2. IMPRESIÓN (no bloqueante) ══
      final bool isA4 = localTerminal.printerFormat.startsWith('a4');
      final bool hasCash = _payments.any((p) => p.method == 'cash');
      final bool isSupplierPayment = (_category == 'Pago a Proveedor' || _category == 'Cobro de Saldo a Favor')
          && _selectedSupplierId != null;

      if (_printReceipt && !isA4) {
        // ── Impresión Térmica ──
        try {
          final paymentMaps = _payments.map((p) => <String, dynamic>{
            'payment_method': p.method,
            'amount': p.amount,
          }).toList();

          if (isSupplierPayment && supplierName != null) {
            await ReceiptPrinterService.instance.printSupplierPaymentTicket(
              type: _type,
              supplierName: supplierName,
              supplierCuit: supplierCuit,
              totalAmount: _totalAmount,
              balanceBefore: balanceBeforePayment ?? 0.0,
              payments: paymentMaps,
              settings: settings,
              localTerminal: localTerminal,
              movementIds: createdIds,
              description: _descriptionController.text,
              receiptNumber: _receiptController.text,
              cashierName: authProvider.currentUser?['name'],
              openDrawer: hasCash,
            );
          } else {
            await ReceiptPrinterService.instance.printCashMovementTicket(
              type: _type,
              category: _category,
              totalAmount: _totalAmount,
              payments: paymentMaps,
              settings: settings,
              localTerminal: localTerminal,
              movementIds: createdIds,
              description: _descriptionController.text,
              receiptNumber: _receiptController.text,
              cashierName: authProvider.currentUser?['name'],
              openDrawer: hasCash,
            );
          }
        } catch (printError) {
          // ── Error de impresión: NUNCA bloquea la transacción ──
          debugPrint('Error de impresion (no bloqueante): $printError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Movimiento guardado, pero la impresora no respondio.'),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else if (!_printReceipt && hasCash) {
        // ── Drawer Kick Aislado: no se imprime, pero hay efectivo ──
        try {
          await ReceiptPrinterService.instance.openCashDrawer(localTerminal);
        } catch (_) {
          // Silenciar — la gaveta no es crítica
        }
      } else if (_printReceipt && isA4) {
        // ── Impresión A4/Carta (PDF) ──
        try {
          final paymentMaps = _payments.map((p) => <String, dynamic>{
            'payment_method': p.method,
            'amount': p.amount,
          }).toList();

          if (isSupplierPayment && supplierName != null) {
            await CashMovementPdfService.printSupplierPayment(
              type: _type,
              supplierName: supplierName,
              supplierCuit: supplierCuit,
              totalAmount: _totalAmount,
              balanceBefore: balanceBeforePayment ?? 0.0,
              payments: paymentMaps,
              businessName: settings.companyName ?? 'MI NEGOCIO',
              businessTaxId: settings.taxId,
              movementIds: createdIds,
              description: _descriptionController.text,
              receiptNumber: _receiptController.text,
              cashierName: authProvider.currentUser?['name'],
              paperSize: localTerminal.pdfPaperSize,
            );
          } else {
            await CashMovementPdfService.printGenericMovement(
              type: _type,
              category: _category,
              totalAmount: _totalAmount,
              payments: paymentMaps,
              businessName: settings.companyName ?? 'MI NEGOCIO',
              businessTaxId: settings.taxId,
              movementIds: createdIds,
              description: _descriptionController.text,
              receiptNumber: _receiptController.text,
              cashierName: authProvider.currentUser?['name'],
              paperSize: localTerminal.pdfPaperSize,
            );
          }
          if (hasCash) {
            await ReceiptPrinterService.instance.openCashDrawer(localTerminal);
          }
        } catch (printError) {
          debugPrint('Error de impresion PDF (no bloqueante): $printError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Movimiento guardado, pero falló la generación del PDF.'),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Movimiento registrado correctamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supplierProv = context.watch<SupplierProvider>();
    final checkProv = context.watch<CheckProvider>();
    final availableChecks = checkProv.checks.where((c) => c.status == 'in_wallet').toList();

    return AlertDialog(
      title: const Text('Registrar Movimiento de Caja'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // DATOS GENERALES
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: const InputDecoration(labelText: 'Tipo de Movimiento'),
                        items: const [
                          DropdownMenuItem(value: 'expense', child: Text('Gasto (Salida)')),
                          DropdownMenuItem(value: 'withdrawal', child: Text('Retiro de Dueño (Salida)')),
                          DropdownMenuItem(value: 'deposit', child: Text('Ingreso Extra (Entrada)')),
                        ],
                        onChanged: (val) => setState(() {
                          _type = val!;
                          if (!_currentCategories.contains(_category)) {
                            _category = _currentCategories.first;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_type),
                        initialValue: _category,
                        decoration: const InputDecoration(labelText: 'Categoría'),
                        items: _currentCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (val) => setState(() => _category = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (_category == 'Pago a Proveedor' && widget.initialSupplierId == null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('¿Ingresó mercadería nueva?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                              Text('Para mantener sus cuentas al día, registre primero el comprobante.', style: TextStyle(fontSize: 12, color: Colors.blue.shade800)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.blue.shade100,
                            foregroundColor: Colors.blue.shade900,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            if (_selectedSupplierId != null) {
                              final supps = supplierProv.suppliers.where((s) => s.id == _selectedSupplierId);
                              if (supps.isNotEmpty) {
                                final supplier = supps.first;
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => SupplierInvoiceFormDialog(
                                    supplierId: supplier.id,
                                    supplierName: supplier.name,
                                  ),
                                );
                              }
                            } else {
                              Navigator.of(context).pushReplacementNamed('/suppliers');
                            }
                          },
                          child: Text(_selectedSupplierId != null ? 'Cargar Factura' : 'Ir a Proveedores', style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),

                if (_category == 'Pago a Proveedor' || _category == 'Cobro de Saldo a Favor') ...[
                  DropdownButtonFormField<int>(
                    initialValue: _selectedSupplierId,
                    decoration: const InputDecoration(labelText: 'Seleccionar Proveedor'),
                    items: supplierProv.suppliers.map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedSupplierId = val),
                    validator: (val) => val == null ? 'Debe seleccionar un proveedor' : null,
                  ),
                  if (_selectedSupplierId != null) Builder(
                    builder: (context) {
                      final supps = supplierProv.suppliers.where((s) => s.id == _selectedSupplierId);
                      if (supps.isEmpty) return const SizedBox.shrink();
                      final supplier = supps.first;
                      
                      final isDebt = supplier.balance > 0;
                      final balanceColor = supplier.balance == 0 ? Colors.grey.shade700 : (isDebt ? Colors.red.shade700 : Colors.green.shade700);
                      final balanceBg = supplier.balance == 0 ? Colors.grey.shade50 : (isDebt ? Colors.red.shade50 : Colors.green.shade50);
                      final balanceLabel = supplier.balance == 0 ? 'Cuenta al día' : (isDebt ? 'Deuda Actual' : 'Saldo a Favor');
                      
                      return Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: balanceBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: supplier.balance == 0 ? Colors.grey.shade300 : (isDebt ? Colors.red.shade200 : Colors.green.shade200)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(balanceLabel, style: TextStyle(color: balanceColor, fontWeight: FontWeight.bold)),
                                if (supplier.contactName != null && supplier.contactName!.isNotEmpty)
                                  Text('Contacto: ${supplier.contactName}', style: TextStyle(fontSize: 12, color: balanceColor)),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  NumberFormat.currency(symbol: '\$').format(supplier.balance.abs()),
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: balanceColor),
                                ),
                                if ((_type == 'expense' && isDebt) || (_type == 'deposit' && !isDebt && supplier.balance != 0)) ...[
                                  const SizedBox(width: 12),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      backgroundColor: isDebt ? Colors.red.shade100 : Colors.green.shade100,
                                      foregroundColor: balanceColor,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _paymentAmountController.text = supplier.balance.abs().toString();
                                      });
                                    },
                                    child: Text(isDebt ? 'Pagar Total' : 'Cobrar Total', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ]
                              ],
                            ),
                          ],
                        ),
                      );
                    }
                  ),
                ],
                  
                if (widget.helperText != null)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.helperText!,
                            style: TextStyle(color: Colors.green.shade900, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(labelText: 'Detalle / Descripción'),
                        validator: (val) {
                          if (_category == 'Otros' && (val == null || val.isEmpty)) {
                            return 'Requerido para la categoría "Otros"';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _receiptController,
                        decoration: const InputDecoration(labelText: 'Nº Comprobante (Opc.)'),
                      ),
                    ),
                  ],
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Divider(),
                ),
                
                // PAGOS MIXTOS
                Text('Métodos de Pago', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                
                // Lista de pagos agregados
                if (_payments.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _payments.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final p = _payments[index];
                          final String methodLabel = p.method == 'cash' ? 'EFECTIVO' : (p.method == 'transfer' ? 'TRANSFERENCIA' : (p.method == 'check' ? 'CHEQUE' : p.method.toUpperCase()));
                          return ListTile(
                            dense: true,
                            title: Text(methodLabel),
                          subtitle: p.checkObj != null 
                              ? Text('Cheque Nº ${p.checkObj!.checkNumber} - ${p.checkObj!.bankName}') 
                              : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(NumberFormat.currency(symbol: '\$').format(p.amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                onPressed: () => _removePayment(index),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                // Agregar nuevo pago
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: _currentPaymentMethod,
                              decoration: const InputDecoration(labelText: 'Método', isDense: true),
                              items: const [
                                DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                                DropdownMenuItem(value: 'transfer', child: Text('Transf.')),
                                DropdownMenuItem(value: 'check', child: Text('Cheque')),
                              ],
                              onChanged: (val) => setState(() {
                                _currentPaymentMethod = val!;
                                _currentCheckId = null;
                                _paymentAmountController.clear();
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _paymentAmountController,
                              decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$', isDense: true),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: _currentPaymentMethod != 'check',
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _addPayment,
                            child: const Text('Agregar'),
                          ),
                        ],
                      ),
                      if (_currentPaymentMethod == 'check') ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _currentCheckId,
                          decoration: const InputDecoration(labelText: 'Seleccionar Cheque en Cartera', isDense: true),
                          items: availableChecks.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('Nº ${c.checkNumber} (\$ ${c.amount}) - ${c.bankName}'),
                          )).toList(),
                          onChanged: (val) {
                            setState(() {
                              _currentCheckId = val;
                              if (val != null) {
                                final check = availableChecks.firstWhere((c) => c.id == val);
                                _paymentAmountController.text = check.amount.toString();
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                
                // ── Checkbox de Impresión ──
                if (context.watch<LocalTerminalProvider>().printerConnection.toLowerCase() != 'none' || 
                    context.watch<LocalTerminalProvider>().printerFormat.toLowerCase().startsWith('a4'))
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: CheckboxListTile(
                      value: _printReceipt,
                      onChanged: (val) {
                        setState(() => _printReceipt = val ?? true);
                        _savePrintPreference(val ?? true);
                      },
                      title: const Text('Imprimir comprobante', style: TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: const Text('Imprime un vale con espacio para firma', style: TextStyle(fontSize: 12)),
                      secondary: Icon(Icons.print, color: _printReceipt ? Colors.blue : Colors.grey),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  decoration: BoxDecoration(
                    color: _totalAmount > 0 
                      ? (_type == 'deposit' ? Colors.green.shade50 : Colors.red.shade50)
                      : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _totalAmount > 0 
                        ? (_type == 'deposit' ? Colors.green.shade200 : Colors.red.shade200)
                        : Colors.grey.shade300, 
                      width: 2
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _type == 'deposit' ? 'TOTAL INGRESO:' : 'TOTAL EGRESO:',
                        style: TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.bold, 
                          color: _totalAmount > 0 
                            ? (_type == 'deposit' ? Colors.green.shade900 : Colors.red.shade900)
                            : Colors.grey.shade600
                        ),
                      ),
                      Text(
                        NumberFormat.currency(symbol: '\$').format(_totalAmount),
                        style: TextStyle(
                          fontSize: 28, 
                          fontWeight: FontWeight.w900, 
                          color: _totalAmount > 0 
                            ? (_type == 'deposit' ? Colors.green.shade700 : Colors.red.shade700)
                            : Colors.grey.shade600
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: _isLoading 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
          label: const Text('Procesar Movimiento'),
        ),
      ],
    );
  }
}
