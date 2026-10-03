import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/presentation/widgets/print_format_selector.dart';
import '../../providers/cash_movement_provider.dart';
import '../../providers/expense_category_provider.dart';

import '../../../suppliers/providers/supplier_provider.dart';
import '../../../checks/presentation/providers/check_provider.dart';
import '../../../checks/domain/entities/third_party_check.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/constants/app_permissions.dart';
import '../../../suppliers/presentation/widgets/supplier_invoice_form_dialog.dart';
import '../../../../core/utils/receipt_printer_service.dart';
import '../../../../core/providers/local_terminal_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
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
  int? _expenseCategoryId;
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
    if (_type == 'withdrawal') {
      return ['Retiro', 'Adelanto de Sueldo', 'Otros'];
    }
    if (_type == 'supplier_payment') {
      return ['Pago a Proveedor'];
    }
    return ['Otros']; // Fallback
  }

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? 'expense';
    _category = widget.initialCategory ?? 'Mercadería';
    if (!_currentCategories.contains(_category) && _currentCategories.isNotEmpty) {
      _category = _currentCategories.first;
    }
    _selectedSupplierId = widget.initialSupplierId;

    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _payments.add(PaymentItem(method: 'cash', amount: widget.initialAmount!));
    }

    _paymentAmountController.addListener(() {
      if (mounted) {
        setState(() {}); // Re-render to update live total
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SupplierProvider>().fetchSuppliers();
      context.read<CheckProvider>().loadChecks();
      context.read<ExpenseCategoryProvider>().fetchCategories();
      // Cargar preferencia de impresión y verificar si hay impresora
      _loadPrintPreference();
    });
  }

  Future<void> _loadPrintPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final localTerminal = context.read<LocalTerminalProvider>();
    final hasPrinter =
        localTerminal.printerConnection.toLowerCase() != 'none' ||
            localTerminal.printerFormat.toLowerCase().startsWith('a4');
    if (mounted) {
      setState(() {
        _printReceipt =
            hasPrinter && (prefs.getBool('auto_print_cash_movement') ?? true);
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

  double? _sanitizeAndParse(String text) {
    var clean = text.trim();
    if (clean.contains('.') && clean.contains(',')) {
      if (clean.lastIndexOf(',') > clean.lastIndexOf('.')) {
        // Formato latinoamericano/europeo: 1.234,56 -> 1234.56
        clean = clean.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // Formato anglosajón: 1,234.56 -> 1234.56
        clean = clean.replaceAll(',', '');
      }
    } else {
      clean = clean.replaceAll(',', '.');
    }
    final val = double.tryParse(clean);
    if (val == null || val <= 0 || val.isNaN || val.isInfinite) return null;
    return double.parse(val.toStringAsFixed(2));
  }

  double get _totalAmount {
    final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
    final pendingSum = _sanitizeAndParse(_paymentAmountController.text) ?? 0.0;
    return double.parse((listSum + pendingSum).toStringAsFixed(2));
  }

  void _addPayment() {
    final amount = _sanitizeAndParse(_paymentAmountController.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingrese un monto válido mayor a 0.')));
      return;
    }

    ThirdPartyCheck? checkObj;
    if (_currentPaymentMethod == 'check') {
      if (_currentCheckId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Seleccione un cheque.')));
        return;
      }

      // DEFENSIVE GUARD: Duplicate check prevention
      final isAlreadyAdded = _payments.any(
          (p) => p.method == 'check' && p.checkId == _currentCheckId);
      if (isAlreadyAdded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este cheque ya ha sido agregado a la lista de pagos.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final checks = context.read<CheckProvider>().checks;
      try {
        checkObj = checks.firstWhere((c) => c.id == _currentCheckId);
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El cheque seleccionado no es válido.')));
        return;
      }
    }

    // ENFORCE FACE VALUE: Check tender amount must strictly match carton nominal value
    final finalAmount = (_currentPaymentMethod == 'check' && checkObj != null)
        ? checkObj.amount
        : amount;

    setState(() {
      _payments.add(PaymentItem(
        method: _currentPaymentMethod,
        amount: finalAmount,
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

  void _editPayment(int index) {
    final p = _payments[index];
    setState(() {
      _payments.removeAt(index);
      _currentPaymentMethod = p.method;
      _currentCheckId = p.checkId;
      _paymentAmountController.text = p.amount % 1 == 0
          ? p.amount.toInt().toString()
          : p.amount.toStringAsFixed(2);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final pendingAmount = _sanitizeAndParse(_paymentAmountController.text) ?? 0;

    // GUARD: Prevent silent input discard if user typed an unparsable/invalid number
    if (_paymentAmountController.text.trim().isNotEmpty && pendingAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El monto ingresado en el campo es inválido. Corríjalo o bórrelo antes de procesar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Auto-agregar el pago si el usuario lo escribió pero olvidó presionar "Agregar"
    if (pendingAmount > 0) {
      if (_currentPaymentMethod == 'check') {
        if (_currentCheckId != null &&
            !_payments.any((p) => p.method == 'check' && p.checkId == _currentCheckId)) {
          _addPayment();
        }
      } else {
        _addPayment();
      }
    }

    if (_payments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agregue al menos un método de pago.')));
      return;
    }

    // STRICT SUBMISSION INTEGRITY BARRIER: Guarantee zero duplicate checks in payload
    final checkIds = _payments
        .where((p) => p.method == 'check' && p.checkId != null)
        .map((p) => p.checkId!)
        .toList();
    if (checkIds.length != checkIds.toSet().length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No se permite utilizar el mismo cheque en múltiples líneas.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // V-03 GUARD: Detect overpayment with checks and confirm cash change (vuelto)
    if (_type == 'supplier_payment' && _selectedSupplierId != null) {
      final supplierProv = context.read<SupplierProvider>();
      final supps = supplierProv.suppliers.where((s) => s.id == _selectedSupplierId);
      if (supps.isNotEmpty) {
        final supplier = supps.first;
        final debt = supplier.balance > 0 ? supplier.balance : 0.0;
        final totalPaid = _payments.fold(0.0, (sum, p) => sum + p.amount);
        final hasCheck = _payments.any((p) => p.method == 'check');

        if (totalPaid > debt && debt > 0 && hasCheck) {
          final changeAmount = double.parse((totalPaid - debt).toStringAsFixed(2));
          final proceed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.monetization_on, color: Colors.teal),
                  SizedBox(width: 8),
                  Text('Vuelto de Proveedor por Cheque'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('La suma de pagos (\$${totalPaid.toStringAsFixed(2)}) supera la deuda actual (\$${debt.toStringAsFixed(2)}).'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Vuelto a ingresar a caja:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('\$${changeAmount.toStringAsFixed(2)}',
                            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green.shade800, fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('¿Desea asentar el pago e ingresar el vuelto a la caja registradora?'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  child: const Text('Confirmar e Ingresar Vuelto'),
                ),
              ],
            ),
          );

          if (proceed != true) return;
        }
      }
    }

    await AdminPinDialog.protectAction(
      context,
      action: 'Registrar Movimiento de Caja',
      permissionKey: widget.initialType == 'supplier_payment' ? AppPermissions.paySuppliers : AppPermissions.createExpenses,
      onAuthorized: () async {
        await _executeSubmit();
      },
    );
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
        final supps = supplierProvider.suppliers
            .where((s) => s.id == _selectedSupplierId);
        if (supps.isNotEmpty) {
          balanceBeforePayment = supps.first.balance;
          supplierName = supps.first.name;
          supplierCuit = supps.first.cuit;
        }
      }

      final activeShift = context.read<CashRegisterProvider>().currentShift;
      final data = {
        'type': _type,
        'category': _category,
        'cash_shift_id': activeShift?.id,
        'expense_category_id': (_expenseCategoryId == -1) ? null : _expenseCategoryId,
        'description': _descriptionController.text,
        'receipt_number': _receiptController.text,
        'supplier_id': (_type == 'supplier_payment' || _category == 'Cobro de Saldo a Favor') ? _selectedSupplierId : null,
        'payments': _payments
            .map((p) => {
                  'amount': p.amount,
                  'payment_method': p.method,
                  'check_id': p.checkId,
                })
            .toList()
      };

      // ══ 1. GUARDAR EN BASE DE DATOS (prioridad absoluta) ══
      final createdIds =
          await provider.createMovement(data, adminPin: adminPin);

      if (mounted && _selectedSupplierId != null) {
        supplierProvider.fetchSuppliers();
      }
      if (mounted) {
        context.read<CheckProvider>().loadChecks();
      }

      // ══ 2. IMPRESIÓN (no bloqueante) ══
      String format = localTerminal.printerFormat;
      if (_printReceipt) {
        final selectedFormat = await PrintFormatSelector.show(context);
        if (selectedFormat != null) {
          format = selectedFormat;
        } else {
          // Si el usuario cancela, desactivamos la impresion
          format = 'none';
        }
      }
      final bool isA4 = format.startsWith('a4');
      final bool shouldPrint = _printReceipt && format != 'none';
      final bool hasCash = _payments.any((p) => p.method == 'cash');
      final bool isSupplierPayment = (_type == 'supplier_payment' ||
              _category == 'Cobro de Saldo a Favor') &&
          _selectedSupplierId != null;

      if (shouldPrint && !isA4) {
        // ── Impresión Térmica ──
        try {
          final paymentMaps = _payments
              .map((p) => <String, dynamic>{
                    'payment_method': p.method,
                    'amount': p.amount,
                  })
              .toList();

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
                content: const Text(
                    'Movimiento guardado, pero la impresora no respondio.'),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else if (!shouldPrint && hasCash) {
        // ── Drawer Kick Aislado: no se imprime, pero hay efectivo ──
        try {
          await ReceiptPrinterService.instance.openCashDrawer(localTerminal);
        } catch (_) {
          // Silenciar — la gaveta no es crítica
        }
      } else if (shouldPrint && isA4) {
        // ── Impresión A4/Carta (PDF) ──
        try {
          final paymentMaps = _payments
              .map((p) => <String, dynamic>{
                    'payment_method': p.method,
                    'amount': p.amount,
                  })
              .toList();

          if (isSupplierPayment && supplierName != null) {
            await CashMovementPdfService.printSupplierPayment(
              context: context,
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
              context: context,
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
        } catch (printError) {
          debugPrint('Error de impresion PDF (no bloqueante): $printError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Movimiento guardado, pero falló la generación del PDF.'),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
        // ── Apertura de gaveta separada (no debe afectar al estado del PDF) ──
        if (hasCash) {
          try {
            await ReceiptPrinterService.instance.openCashDrawer(localTerminal);
          } catch (_) {
            // Silenciar — la gaveta no es crítica
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
    final selectedCheckIds = _payments
        .where((p) => p.method == 'check' && p.checkId != null)
        .map((p) => p.checkId!)
        .toSet();

    final availableChecks = checkProv.checks
        .where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id))
        .toList();

    return AlertDialog(
      title: const Text('Registrar Movimiento de Caja'),
      content: SizedBox(
        width: 600,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // DATOS GENERALES
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _type,
                          decoration: const InputDecoration(
                              labelText: 'Tipo de Movimiento'),
                          items: const [
                            DropdownMenuItem(
                                value: 'expense',
                                child: Text('Gasto Operativo (Salida)')),
                            DropdownMenuItem(
                                value: 'supplier_payment',
                                child: Text('Pago a Proveedor (Salida)')),
                            DropdownMenuItem(
                                value: 'withdrawal',
                                child: Text('Retiro de Dueño (Salida)')),
                            DropdownMenuItem(
                                value: 'deposit',
                                child: Text('Ingreso Extra (Entrada)')),
                          ],
                          onChanged: (val) => setState(() {
                            _type = val!;
                            if (_type != 'supplier_payment') {
                              _selectedSupplierId = null;
                              _payments.removeWhere((p) => p.method == 'check');
                              if (_currentPaymentMethod == 'check') {
                                _currentPaymentMethod = 'cash';
                                _currentCheckId = null;
                                _paymentAmountController.clear();
                              }
                            }
                            if (_type != 'expense') {
                              _expenseCategoryId = null;
                              _category = _currentCategories.first;
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _type == 'expense'
                            ? Consumer<ExpenseCategoryProvider>(
                                builder: (context, provider, _) {
                                  if (provider.isLoading) {
                                    return const Center(
                                        child: CircularProgressIndicator());
                                  }
                                  final activeCategories = provider.categories
                                      .where((c) => c.isActive)
                                      .toList();

                                  // Verificar si ya existe una categoría llamada "Otros"
                                  final hasOtros = activeCategories.any((c) => c.name.toLowerCase() == 'otros');
                                  
                                  return DropdownButtonFormField<int?>(
                                    initialValue: _expenseCategoryId,
                                    decoration: const InputDecoration(
                                        labelText: 'Categoría de Gasto'),
                                    items: [
                                      const DropdownMenuItem<int?>(
                                        value: null,
                                        child: Text('Seleccione una categoría'),
                                      ),
                                      ...activeCategories.map((c) => DropdownMenuItem<int?>(
                                            value: c.id,
                                            child: Text(c.name),
                                          )),
                                      if (!hasOtros)
                                        const DropdownMenuItem<int?>(
                                          value: -1,
                                          child: Text('Otros'),
                                        ),
                                    ],
                                    onChanged: (val) => setState(() {
                                      _expenseCategoryId = val;
                                      if (val == -1) {
                                        _category = 'Otros';
                                      } else if (val != null) {
                                        _category = activeCategories
                                            .firstWhere((c) => c.id == val)
                                            .name;
                                      }
                                    }),
                                    validator: (val) => val == null
                                        ? 'Seleccione una categoría'
                                        : null,
                                  );
                                },
                              )
                            : DropdownButtonFormField<String>(
                                key: ValueKey(_type),
                                initialValue: _category,
                                decoration: const InputDecoration(
                                    labelText: 'Categoría'),
                                items: _currentCategories
                                    .map((c) => DropdownMenuItem(
                                        value: c, child: Text(c)))
                                    .toList(),
                                onChanged: (val) =>
                                    setState(() => _category = val!),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_type == 'supplier_payment' &&
                      widget.initialSupplierId == null)
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
                          Icon(Icons.lightbulb_outline,
                              color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('¿Ingresó mercadería nueva?',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900)),
                                Text(
                                    'Para mantener sus cuentas al día, registre primero el comprobante.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade800)),
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
                                final supps = supplierProv.suppliers
                                    .where((s) => s.id == _selectedSupplierId);
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
                                Navigator.of(context)
                                    .pushReplacementNamed('/suppliers');
                              }
                            },
                            child: Text(
                                _selectedSupplierId != null
                                    ? 'Cargar Factura'
                                    : 'Ir a Proveedores',
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),

                  if (_type == 'supplier_payment' ||
                      _category == 'Cobro de Saldo a Favor') ...[
                    supplierProv.suppliers.isEmpty
                        ? DropdownButtonFormField<int>(
                            initialValue: null,
                            decoration: const InputDecoration(
                                labelText: 'Seleccionar Proveedor'),
                            items: const [
                              DropdownMenuItem(
                                  value: null,
                                  child: Text('No hay proveedores registrados'))
                            ],
                            onChanged: null,
                            validator: (val) => 'Registre proveedores primero',
                          )
                        : DropdownButtonFormField<int>(
                            initialValue: _selectedSupplierId,
                            decoration: const InputDecoration(
                                labelText: 'Seleccionar Proveedor'),
                            items: supplierProv.suppliers
                                .map((s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(s.name),
                                    ))
                                .toList(),
                            onChanged: (val) => setState(() {
                              if (val != _selectedSupplierId) {
                                _selectedSupplierId = val;
                                _payments.clear();
                                _paymentAmountController.clear();
                                _currentCheckId = null;
                              }
                            }),
                            validator: (val) => val == null
                                ? 'Debe seleccionar un proveedor'
                                : null,
                          ),
                    if (_selectedSupplierId != null)
                      Builder(builder: (context) {
                        final supps = supplierProv.suppliers
                            .where((s) => s.id == _selectedSupplierId);
                        if (supps.isEmpty) return const SizedBox.shrink();
                        final supplier = supps.first;

                        final isDebt = supplier.balance > 0;
                        final balanceColor = supplier.balance == 0
                            ? Colors.grey.shade700
                            : (isDebt
                                ? Colors.red.shade700
                                : Colors.green.shade700);
                        final balanceBg = supplier.balance == 0
                            ? Colors.grey.shade50
                            : (isDebt
                                ? Colors.red.shade50
                                : Colors.green.shade50);
                        final balanceLabel = supplier.balance == 0
                            ? 'Cuenta al día'
                            : (isDebt ? 'Deuda Actual' : 'Saldo a Favor');

                        return Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: balanceBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: supplier.balance == 0
                                    ? Colors.grey.shade300
                                    : (isDebt
                                        ? Colors.red.shade200
                                        : Colors.green.shade200)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(balanceLabel,
                                      style: TextStyle(
                                          color: balanceColor,
                                          fontWeight: FontWeight.bold)),
                                  if (supplier.contactName != null &&
                                      supplier.contactName!.isNotEmpty)
                                    Text('Contacto: ${supplier.contactName}',
                                        style: TextStyle(
                                            fontSize: 12, color: balanceColor)),
                                ],
                              ),
                              Row(
                                children: [
                                  Text(
                                    NumberFormat.currency(symbol: '\$')
                                        .format(supplier.balance.abs()),
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: balanceColor),
                                  ),
                                  if (((_type == 'expense' && isDebt) ||
                                      (_type == 'supplier_payment' && isDebt) ||
                                      (_type == 'deposit' &&
                                          !isDebt &&
                                          supplier.balance != 0)) &&
                                      supplier.balance.abs() > _payments.fold(0.0, (sum, item) => sum + item.amount)) ...[
                                    const SizedBox(width: 12),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        backgroundColor: isDebt
                                            ? Colors.red.shade100
                                            : Colors.green.shade100,
                                        foregroundColor: balanceColor,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () {
                                        if (_currentPaymentMethod == 'check') {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('El monto de un cheque no puede modificarse.'),
                                            ),
                                          );
                                          return;
                                        }
                                        setState(() {
                                          final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
                                          final remaining = double.parse((supplier.balance.abs() - listSum).toStringAsFixed(2));
                                          if (remaining <= 0) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('La deuda ya está completamente cubierta o no hay saldo pendiente.')),
                                            );
                                            return;
                                          }
                                          _paymentAmountController.text = 
                                              (remaining % 1 == 0 ? remaining.toInt().toString() : remaining.toStringAsFixed(2));
                                        });
                                      },
                                      child: Text(
                                          isDebt
                                              ? (_payments.isEmpty ? 'Pagar Total' : 'Pagar Restante')
                                              : (_payments.isEmpty ? 'Cobrar Total' : 'Cobrar Restante'),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ]
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                  ],

                  if (widget.helperText != null && (() {
                    // Hide the helper banner once the user has added payments
                    // that fully cover the initial amount (the invoice debt).
                    final paidSoFar = _payments.fold(0.0, (sum, p) => sum + p.amount);
                    final target = widget.initialAmount ?? 0.0;
                    return target <= 0 || paidSoFar < target;
                  })())
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
                          Icon(Icons.info_outline,
                              color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.helperText!,
                              style: TextStyle(
                                  color: Colors.green.shade900, fontSize: 13),
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
                          decoration: InputDecoration(
                            labelText: _category.toLowerCase() == 'otros' 
                                ? 'Detalle / Descripción *' 
                                : 'Detalle / Descripción (Opcional)',
                          ),
                          validator: (val) {
                            if (_category.toLowerCase() == 'otros' && (val == null || val.trim().isEmpty)) {
                              return 'Especifique el detalle de "Otros"';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _receiptController,
                          decoration: const InputDecoration(
                              labelText: 'Nº Comprobante (Opc.)'),
                        ),
                      ),
                    ],
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Divider(),
                  ),

                  // PAGOS MIXTOS
                  Text('Métodos de Pago',
                      style: Theme.of(context).textTheme.titleMedium),
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
                          final String methodLabel = p.method == 'cash'
                              ? 'EFECTIVO'
                              : (p.method == 'transfer'
                                  ? 'TRANSFERENCIA'
                                  : (p.method == 'check'
                                      ? 'CHEQUE'
                                      : p.method.toUpperCase()));
                          return ListTile(
                            dense: true,
                            onTap: () => _editPayment(index),
                            title: Text(methodLabel),
                            subtitle: p.checkObj != null
                                ? Text(
                                    'Cheque Nº ${p.checkObj!.checkNumber} - ${p.checkObj!.bankName}')
                                : const Text('Toque para editar',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                    NumberFormat.currency(symbol: '\$')
                                        .format(p.amount),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                IconButton(
                                  icon: Icon(Icons.edit_outlined,
                                      color: Colors.blue.shade400, size: 20),
                                  tooltip: 'Editar pago',
                                  onPressed: () => _editPayment(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red, size: 20),
                                  tooltip: 'Eliminar pago',
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
                                key: ValueKey('payment_method_dropdown_$_type'),
                                initialValue: _currentPaymentMethod,
                                decoration: const InputDecoration(
                                    labelText: 'Método', isDense: true),
                                items: [
                                  const DropdownMenuItem(
                                      value: 'cash', child: Text('Efectivo')),
                                  const DropdownMenuItem(
                                      value: 'transfer',
                                      child: Text('Transf.')),
                                  if (_type == 'supplier_payment')
                                    const DropdownMenuItem(
                                        value: 'check', child: Text('Cheque')),
                                ],
                                onChanged: (val) => setState(() {
                                  final oldMethod = _currentPaymentMethod;
                                  _currentPaymentMethod = val!;
                                  _currentCheckId = null;
                                  // Solo limpiar el monto si cambiamos A cheque
                                  // (porque el cheque tiene valor nominal fijo)
                                  // o si venimos DE cheque (el valor era del cheque, no del usuario)
                                  if (val == 'check' || oldMethod == 'check') {
                                    _paymentAmountController.clear();
                                  }
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _paymentAmountController,
                                decoration: const InputDecoration(
                                    labelText: 'Monto',
                                    prefixText: '\$',
                                    isDense: true),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
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
                          availableChecks.isEmpty
                              ? DropdownButtonFormField<int>(
                                  initialValue: null,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Seleccionar Cheque en Cartera',
                                      isDense: true),
                                  items: const [
                                    DropdownMenuItem(
                                        value: null,
                                        child:
                                            Text('No hay cheques disponibles'))
                                  ],
                                  onChanged: null,
                                )
                              : DropdownButtonFormField<int>(
                                  key: ValueKey('check_dropdown_${selectedCheckIds.length}_$_currentCheckId'),
                                  initialValue: availableChecks.any((c) => c.id == _currentCheckId)
                                      ? _currentCheckId
                                      : null,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Seleccionar Cheque en Cartera',
                                      isDense: true),
                                  items: availableChecks
                                      .map((c) => DropdownMenuItem(
                                            value: c.id,
                                            child: Text(
                                                'Nº ${c.checkNumber} (\$ ${c.amount}) - ${c.bankName}'),
                                          ))
                                      .toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _currentCheckId = val;
                                      if (val != null) {
                                        final check = availableChecks
                                            .firstWhere((c) => c.id == val);
                                        _paymentAmountController.text =
                                            check.amount.toString();
                                      }
                                    });
                                  },
                                ),
                        ],
                      ],
                    ),
                  ),

                  // ── Checkbox de Impresión ──
                  if (context
                              .watch<LocalTerminalProvider>()
                              .printerConnection
                              .toLowerCase() !=
                          'none' ||
                      context
                          .watch<LocalTerminalProvider>()
                          .printerFormat
                          .toLowerCase()
                          .startsWith('a4'))
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: CheckboxListTile(
                        value: _printReceipt,
                        onChanged: (val) {
                          setState(() => _printReceipt = val ?? true);
                          _savePrintPreference(val ?? true);
                        },
                        title: const Text('Imprimir comprobante',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: const Text(
                            'Imprime un vale con espacio para firma',
                            style: TextStyle(fontSize: 12)),
                        secondary: Icon(Icons.print,
                            color: _printReceipt ? Colors.blue : Colors.grey),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 24),
                    decoration: BoxDecoration(
                      color: _totalAmount > 0
                          ? (_type == 'deposit'
                              ? Colors.green.shade50
                              : Colors.red.shade50)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _totalAmount > 0
                              ? (_type == 'deposit'
                                  ? Colors.green.shade200
                                  : Colors.red.shade200)
                              : Colors.grey.shade300,
                          width: 2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _type == 'deposit'
                              ? 'TOTAL INGRESO:'
                              : 'TOTAL EGRESO:',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _totalAmount > 0
                                  ? (_type == 'deposit'
                                      ? Colors.green.shade900
                                      : Colors.red.shade900)
                                  : Colors.grey.shade600),
                        ),
                        Text(
                          NumberFormat.currency(symbol: '\$')
                              .format(_totalAmount),
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: _totalAmount > 0
                                  ? (_type == 'deposit'
                                      ? Colors.green.shade700
                                      : Colors.red.shade700)
                                  : Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: const Text('Procesar Movimiento'),
        ),
      ],
    );
  }
}
