import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/presentation/widgets/print_format_selector.dart';
import '../../../../core/presentation/widgets/thermal_receipt_widget.dart';
import '../../../../core/presentation/widgets/ticket_preview_dialog.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../providers/cash_movement_provider.dart';
import '../../providers/expense_category_provider.dart';
import 'expense_category_form_dialog.dart';

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
  final String fundingSource;
  final double amount;
  final int? checkId;
  final ThirdPartyCheck? checkObj;

  PaymentItem({
    required this.method,
    this.fundingSource = 'cash_register',
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

  String? _receiptFileUrl;
  String? _receiptFileName;
  bool _isUploadingFile = false;

  int? _selectedSupplierId;
  int? _expenseCategoryId;
  bool _isLoading = false;

  // Pagos mixtos
  final List<PaymentItem> _payments = [];
  String _currentPaymentMethod = 'cash';
  String _currentFundingSource = 'cash_register';
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
    _currentFundingSource = _type == 'supplier_payment' ? 'owner_funds' : 'cash_register';
    _category = widget.initialCategory ?? 'Mercadería';
    if (!_currentCategories.contains(_category) && _currentCategories.isNotEmpty) {
      _category = _currentCategories.first;
    }
    _selectedSupplierId = widget.initialSupplierId;

    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _payments.add(PaymentItem(
        method: 'cash',
        fundingSource: _currentFundingSource,
        amount: widget.initialAmount!,
      ));
    }

    _paymentAmountController.addListener(() {
      if (mounted) {
        setState(() {}); // Re-render to update live total
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cashProv = context.read<CashRegisterProvider>();
      final hasOpenShift = cashProv.currentShift != null && cashProv.currentShift!.isOpen;
      if (!hasOpenShift && mounted) {
        setState(() {
          if (_type == 'withdrawal' || _type == 'deposit') {
            _type = 'expense';
            _category = _currentCategories.first;
          }
          _currentFundingSource = 'owner_funds';
          for (int i = 0; i < _payments.length; i++) {
            if (_payments[i].method != 'check') {
              _payments[i] = PaymentItem(
                method: _payments[i].method,
                fundingSource: 'owner_funds',
                amount: _payments[i].amount,
                checkId: _payments[i].checkId,
                checkObj: _payments[i].checkObj,
              );
            }
          }
        });
      }
      context.read<SupplierProvider>().fetchSuppliers();
      context.read<CheckProvider>().loadChecks();
      context.read<ExpenseCategoryProvider>().fetchCategories();
      // Cargar preferencia de impresión y verificar si hay impresora
      _loadPrintPreference();
    });
  }

  Future<void> _loadPrintPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _printReceipt = prefs.getBool('auto_print_cash_movement') ?? true;
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
    final val = ArsThousandsInputFormatter.tryParse(text);
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
        fundingSource: _currentPaymentMethod == 'check' ? 'cash_register' : _currentFundingSource,
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
      _currentFundingSource = p.fundingSource;
      _currentCheckId = p.checkId;
      _paymentAmountController.text = p.amount.toArsInput();
    });
  }

  Future<void> _pickAndUploadReceipt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;

      setState(() => _isUploadingFile = true);
      try {
        final cashProv = context.read<CashMovementProvider>();
        final apiClient = context.read<ApiClient>();

        final uri = Uri.parse('${cashProv.baseUrl}/cash-movements/upload');
        final request = http.MultipartRequest('POST', uri);

        if (apiClient.sessionToken != null) {
          request.headers['X-Session-Token'] = apiClient.sessionToken!;
        }

        request.files.add(await http.MultipartFile.fromPath('file', filePath));

        final streamed = await request.send();
        final response = await http.Response.fromStream(streamed);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final uploadedUrl = data['url'] ?? data['path'];
          if (mounted) {
            setState(() {
              _receiptFileUrl = uploadedUrl;
              _receiptFileName = fileName;
              _isUploadingFile = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Comprobante adjuntado correctamente.'),
                backgroundColor: Colors.teal,
              ),
            );
          }
        } else {
          String errMsg = 'Error al subir comprobante (HTTP ${response.statusCode})';
          try {
            final errBody = json.decode(response.body);
            errMsg = errBody['message'] ?? errMsg;
          } catch (_) {}
          throw Exception(errMsg);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isUploadingFile = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fallo la subida del comprobante: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _removeReceipt() {
    setState(() {
      _receiptFileUrl = null;
      _receiptFileName = null;
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
                  Text('La suma de pagos (\$${totalPaid.toCurrency()}) supera la deuda actual (\$${debt.toCurrency()}).'),
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
                        Text('\$${changeAmount.toCurrency()}',
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

      final cashRegProv = context.read<CashRegisterProvider>();
      final activeShift = cashRegProv.currentShift;
      final data = {
        'type': _type,
        'category': _category,
        'cash_shift_id': activeShift?.id,
        if (cashRegProv.activeRegisterId != null)
          'cash_register_id': cashRegProv.activeRegisterId,
        'expense_category_id': (_expenseCategoryId == -1) ? null : _expenseCategoryId,
        'description': _descriptionController.text,
        'receipt_number': _receiptController.text,
        'receipt_file_url': _receiptFileUrl,
        'supplier_id': (_type == 'supplier_payment' || _category == 'Cobro de Saldo a Favor') ? _selectedSupplierId : null,
        'payments': _payments
            .map((p) => {
                  'amount': p.amount,
                  'payment_method': p.method,
                  'funding_source': p.method == 'check' ? 'cash_register' : p.fundingSource,
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
      final bool hasCash = _payments.any((p) => p.method == 'cash' && p.fundingSource == 'cash_register');
      final bool isSupplierPayment = (_type == 'supplier_payment' ||
              _category == 'Cobro de Saldo a Favor') &&
          _selectedSupplierId != null;

      if (shouldPrint && !isA4) {
        // ── Vista Previa + Impresión Térmica (58mm / 80mm) ──
        try {
          final paymentMaps = _payments
              .map((p) => <String, dynamic>{
                    'payment_method': p.method,
                    'funding_source': p.method == 'check' ? 'cash_register' : p.fundingSource,
                    'amount': p.amount,
                  })
              .toList();

          final isNarrow = localTerminal.printerFormat == 'thermal_58';
          ThermalPaperWidth chosenWidth =
              isNarrow ? ThermalPaperWidth.mm58 : ThermalPaperWidth.mm80;
          final cashierLabel = authProvider.currentUser?['name']?.toString();

          bool confirmed = true;
          if (mounted) {
            confirmed = await TicketPreviewDialog.show(
              context,
              title: isSupplierPayment
                  ? 'Vista Previa — Pago a Proveedor'
                  : 'Vista Previa — Comprobante de Caja',
              paperWidth: chosenWidth,
              onConfirmPrintWithWidth: (w) => chosenWidth = w,
              linesBuilder: (w) {
                final use58 = w == ThermalPaperWidth.mm58;
                if (isSupplierPayment && supplierName != null) {
                  return CashMovementPdfService.buildSupplierPaymentTicketLines(
                    type: _type,
                    supplierName: supplierName,
                    supplierCuit: supplierCuit,
                    totalAmount: _totalAmount,
                    balanceBefore: balanceBeforePayment ?? 0.0,
                    payments: paymentMaps,
                    businessName: settings.companyName ?? 'MI NEGOCIO',
                    businessAddress: settings.address,
                    businessTaxId: settings.taxId,
                    movementIds: createdIds,
                    description: _descriptionController.text,
                    receiptNumber: _receiptController.text,
                    cashierName: cashierLabel,
                    is58mm: use58,
                  );
                }
                return CashMovementPdfService.buildGenericMovementTicketLines(
                  type: _type,
                  category: _category,
                  totalAmount: _totalAmount,
                  payments: paymentMaps,
                  businessName: settings.companyName ?? 'MI NEGOCIO',
                  businessAddress: settings.address,
                  businessTaxId: settings.taxId,
                  movementIds: createdIds,
                  description: _descriptionController.text,
                  receiptNumber: _receiptController.text,
                  cashierName: cashierLabel,
                  is58mm: use58,
                );
              },
            );
          }

          if (confirmed) {
            final targetPaper = chosenWidth == ThermalPaperWidth.mm58
                ? PaperSize.mm58
                : PaperSize.mm80;
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
                cashierName: cashierLabel,
                openDrawer: hasCash,
                paperSizeOverride: targetPaper,
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
                cashierName: cashierLabel,
                openDrawer: hasCash,
                paperSizeOverride: targetPaper,
              );
            }
          } else if (hasCash) {
            try {
              await ReceiptPrinterService.instance.openCashDrawer(localTerminal);
            } catch (_) {}
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
                    'funding_source': p.method == 'check' ? 'cash_register' : p.fundingSource,
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
              businessSettings: settings,
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
              businessSettings: settings,
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

    final cashProv = context.watch<CashRegisterProvider>();
    final bool hasOpenShift = cashProv.currentShift != null && cashProv.currentShift!.isOpen;
    final bool allowsOwnerFunds = _type == 'supplier_payment' || _type == 'expense';
    final String effectiveFundingSource = !allowsOwnerFunds
        ? 'cash_register'
        : (!hasOpenShift ? 'owner_funds' : _currentFundingSource);
    final String effectivePaymentMethod = (_currentPaymentMethod == 'card' && !allowsOwnerFunds)
        ? 'cash'
        : ((_currentPaymentMethod == 'check' && _type != 'supplier_payment')
            ? 'cash'
            : ((!hasOpenShift && effectiveFundingSource == 'cash_register' && _currentPaymentMethod == 'cash')
                ? 'transfer'
                : _currentPaymentMethod));

    return PopScope(
      canPop: !_isLoading && !_isUploadingFile,
      child: AlertDialog(
      title: const Text('Registrar Movimiento de Caja'),
      content: SizedBox(
        width: 600,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!hasOpenShift)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet_outlined, color: Colors.indigo.shade700, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Operando con caja cerrada: se habilitaron medios externos a la caja física (Fondos Propios / Transferencia / Cheque).',
                              style: TextStyle(fontSize: 12.5, color: Colors.indigo.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // DATOS GENERALES
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _type,
                          decoration: const InputDecoration(
                              labelText: 'Tipo de Movimiento'),
                          items: [
                            const DropdownMenuItem(
                                value: 'expense',
                                child: Text('Gasto Operativo (Salida)',
                                    overflow: TextOverflow.ellipsis)),
                            const DropdownMenuItem(
                                value: 'supplier_payment',
                                child: Text('Pago a Proveedor (Salida)',
                                    overflow: TextOverflow.ellipsis)),
                            if (hasOpenShift)
                              const DropdownMenuItem(
                                  value: 'withdrawal',
                                  child: Text('Retiro de Dueño (Salida)',
                                      overflow: TextOverflow.ellipsis)),
                            if (hasOpenShift)
                              const DropdownMenuItem(
                                  value: 'deposit',
                                  child: Text('Ingreso Extra (Entrada)',
                                      overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) => setState(() {
                            _type = val!;
                            if (_type == 'supplier_payment') {
                              _currentFundingSource = 'owner_funds';
                            } else if (_type == 'expense') {
                              _currentFundingSource = hasOpenShift ? 'cash_register' : 'owner_funds';
                            } else {
                              _currentFundingSource = 'cash_register';
                            }
                            if (_type != 'supplier_payment') {
                              _selectedSupplierId = null;
                              _payments.removeWhere((p) => p.method == 'check');
                              if (_currentPaymentMethod == 'check') {
                                _currentPaymentMethod = 'cash';
                                _currentCheckId = null;
                                _paymentAmountController.clear();
                              }
                            }
                            if (_type != 'supplier_payment' && _type != 'expense') {
                              _payments.removeWhere((p) => p.method == 'card');
                              if (_currentPaymentMethod == 'card') {
                                _currentPaymentMethod = 'cash';
                              }
                              for (int i = 0; i < _payments.length; i++) {
                                if (_payments[i].fundingSource == 'owner_funds') {
                                  _payments[i] = PaymentItem(
                                    method: _payments[i].method,
                                    fundingSource: 'cash_register',
                                    amount: _payments[i].amount,
                                  );
                                }
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
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Consumer<ExpenseCategoryProvider>(
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
                                          isExpanded: true,
                                          initialValue: _expenseCategoryId,
                                          decoration: const InputDecoration(
                                              labelText: 'Categoría de Gasto'),
                                          items: [
                                            const DropdownMenuItem<int?>(
                                              value: null,
                                              child: Text(
                                                'Seleccione una categoría',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            ...activeCategories.map((c) => DropdownMenuItem<int?>(
                                                  value: c.id,
                                                  child: Text(
                                                    c.name,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                )),
                                            if (!hasOtros)
                                              const DropdownMenuItem<int?>(
                                                value: -1,
                                                child: Text(
                                                  'Otros',
                                                  overflow: TextOverflow.ellipsis,
                                                ),
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
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: IconButton.filledTonal(
                                      icon: const Icon(Icons.add),
                                      tooltip: 'Nueva Categoría',
                                      onPressed: () async {
                                        final newCat = await ExpenseCategoryFormDialog.show(context);
                                        if (newCat != null) {
                                          setState(() {
                                            _expenseCategoryId = newCat.id;
                                            _category = newCat.name;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              )
                            : DropdownButtonFormField<String>(
                                key: ValueKey(_type),
                                isExpanded: true,
                                initialValue: _category,
                                decoration: const InputDecoration(
                                    labelText: 'Categoría'),
                                items: _currentCategories
                                    .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c,
                                            overflow: TextOverflow.ellipsis)))
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
                            isExpanded: true,
                            initialValue: null,
                            decoration: const InputDecoration(
                                labelText: 'Seleccionar Proveedor'),
                            items: const [
                              DropdownMenuItem(
                                  value: null,
                                  child: Text('No hay proveedores registrados',
                                      overflow: TextOverflow.ellipsis))
                            ],
                            onChanged: null,
                            validator: (val) => 'Registre proveedores primero',
                          )
                        : DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: _selectedSupplierId,
                            decoration: const InputDecoration(
                                labelText: 'Seleccionar Proveedor'),
                            items: supplierProv.suppliers
                                .map((s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(s.name,
                                          overflow: TextOverflow.ellipsis),
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
                                    '\$${supplier.balance.abs().toCurrency()}',
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
                                          _paymentAmountController.text = remaining.toArsInput();
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isUploadingFile ? null : _pickAndUploadReceipt,
                        icon: _isUploadingFile
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _receiptFileUrl != null ? Icons.attach_file : Icons.add_photo_alternate_outlined,
                                size: 18,
                              ),
                        label: Text(
                          _isUploadingFile
                              ? 'Subiendo...'
                              : (_receiptFileUrl != null ? 'Comprobante Adjunto ✓' : 'Adjuntar Comprobante'),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _receiptFileUrl != null ? Colors.teal.shade700 : Colors.blue.shade700,
                          side: BorderSide(
                            color: _receiptFileUrl != null ? Colors.teal.shade300 : Colors.blue.shade300,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      if (_receiptFileUrl != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _receiptFileName ?? 'Archivo adjunto',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.teal.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar comprobante',
                          icon: const Icon(Icons.close, size: 18, color: Colors.red),
                          onPressed: _removeReceipt,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
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
                                  : (p.method == 'card'
                                      ? 'TARJETA'
                                      : (p.method == 'check'
                                          ? 'CHEQUE'
                                          : p.method.toUpperCase())));
                          final bool isFromPocket = p.fundingSource == 'owner_funds' && p.method != 'check';
                          final String sourceBadgeText = p.method == 'check'
                              ? 'Cartera de Cheques'
                              : (isFromPocket ? 'Fondos Propios / Bolsillo' : 'Caja Registradora');
                          return ListTile(
                            dense: true,
                            onTap: () => _editPayment(index),
                            title: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(methodLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isFromPocket ? Colors.deepPurple.shade50 : Colors.blueGrey.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isFromPocket ? Colors.deepPurple.shade200 : Colors.blueGrey.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        p.method == 'check'
                                            ? Icons.fact_check_outlined
                                            : (isFromPocket ? Icons.account_balance_wallet_outlined : Icons.point_of_sale),
                                        size: 12,
                                        color: isFromPocket ? Colors.deepPurple.shade700 : Colors.blueGrey.shade700,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        sourceBadgeText,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isFromPocket ? Colors.deepPurple.shade800 : Colors.blueGrey.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
                                    '\$${p.amount.toCurrency()}',
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (allowsOwnerFunds && effectivePaymentMethod != 'check') ...[
                          Row(
                            children: [
                              Icon(Icons.swap_horiz_rounded, size: 15, color: Colors.blueGrey.shade700),
                              const SizedBox(width: 6),
                              Text(
                                'Origen de los Fondos:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blueGrey.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  key: const Key('funding_source_owner_funds'),
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => setState(() {
                                    _currentFundingSource = 'owner_funds';
                                    if (_payments.length == 1 &&
                                        _paymentAmountController.text.trim().isEmpty &&
                                        _payments.first.checkId == null) {
                                      _payments[0] = PaymentItem(
                                        method: _payments[0].method,
                                        fundingSource: 'owner_funds',
                                        amount: _payments[0].amount,
                                      );
                                    }
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: effectiveFundingSource == 'owner_funds'
                                          ? Colors.deepPurple.shade600
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: effectiveFundingSource == 'owner_funds'
                                            ? Colors.deepPurple.shade700
                                            : Colors.blueGrey.shade200,
                                        width: effectiveFundingSource == 'owner_funds' ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.account_balance_wallet_outlined,
                                          size: 16,
                                          color: effectiveFundingSource == 'owner_funds'
                                              ? Colors.white
                                              : Colors.deepPurple.shade700,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            'De mi Bolsillo (Fondos Propios)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: effectiveFundingSource == 'owner_funds'
                                                  ? Colors.white
                                                  : Colors.deepPurple.shade900,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Tooltip(
                                  message: hasOpenShift
                                      ? 'Descuenta del efectivo esperado de la caja abierta'
                                      : 'No disponible: la caja registradora se encuentra cerrada',
                                  child: InkWell(
                                    key: const Key('funding_source_cash_register'),
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: !hasOpenShift
                                        ? null
                                        : () => setState(() {
                                              _currentFundingSource = 'cash_register';
                                              if (_payments.length == 1 &&
                                                  _paymentAmountController.text.trim().isEmpty &&
                                                  _payments.first.checkId == null) {
                                                _payments[0] = PaymentItem(
                                                  method: _payments[0].method,
                                                  fundingSource: 'cash_register',
                                                  amount: _payments[0].amount,
                                                );
                                              }
                                            }),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: !hasOpenShift
                                            ? Colors.grey.shade200
                                            : (effectiveFundingSource == 'cash_register'
                                                ? Colors.teal.shade700
                                                : Colors.white),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: !hasOpenShift
                                              ? Colors.grey.shade300
                                              : (effectiveFundingSource == 'cash_register'
                                                  ? Colors.teal.shade800
                                                  : Colors.blueGrey.shade200),
                                          width: effectiveFundingSource == 'cash_register' ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.point_of_sale,
                                            size: 16,
                                            color: !hasOpenShift
                                                ? Colors.grey.shade500
                                                : (effectiveFundingSource == 'cash_register'
                                                    ? Colors.white
                                                    : Colors.teal.shade700),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'De Caja Registradora',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: !hasOpenShift
                                                    ? Colors.grey.shade500
                                                    : (effectiveFundingSource == 'cash_register'
                                                        ? Colors.white
                                                        : Colors.teal.shade900),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey('payment_method_dropdown_${_type}_${hasOpenShift}_$effectivePaymentMethod'),
                                isExpanded: true,
                                initialValue: effectivePaymentMethod,
                                decoration: const InputDecoration(
                                    labelText: 'Método', isDense: true),
                                items: [
                                  if (hasOpenShift || effectiveFundingSource == 'owner_funds')
                                    const DropdownMenuItem(
                                        value: 'cash',
                                        child: Text('Efectivo',
                                            overflow: TextOverflow.ellipsis)),
                                  const DropdownMenuItem(
                                      value: 'transfer',
                                      child: Text('Transf.',
                                          overflow: TextOverflow.ellipsis)),
                                  if (allowsOwnerFunds)
                                    const DropdownMenuItem(
                                        value: 'card',
                                        child: Text('Tarjeta',
                                            overflow: TextOverflow.ellipsis)),
                                  if (_type == 'supplier_payment')
                                    const DropdownMenuItem(
                                        value: 'check',
                                        child: Text('Cheque',
                                            overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (val) => setState(() {
                                  final oldMethod = _currentPaymentMethod;
                                  _currentPaymentMethod = val!;
                                  _currentCheckId = null;
                                  // Si hay 1 único pago pre-cargado y el campo de monto está vacío, actualizar su método en vivo
                                  if (_payments.length == 1 &&
                                      _paymentAmountController.text.trim().isEmpty &&
                                      val != 'check' &&
                                      _payments.first.checkId == null) {
                                    _payments[0] = PaymentItem(
                                      method: val,
                                      fundingSource: effectiveFundingSource,
                                      amount: _payments[0].amount,
                                    );
                                  }
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
                                keyboardType: TextInputType.number,
                                inputFormatters: [ArsThousandsInputFormatter()],
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
                                  isExpanded: true,
                                  initialValue: null,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Seleccionar Cheque en Cartera',
                                      isDense: true),
                                  items: const [
                                    DropdownMenuItem(
                                        value: null,
                                        child: Text(
                                            'No hay cheques disponibles',
                                            overflow: TextOverflow.ellipsis))
                                  ],
                                  onChanged: null,
                                )
                              : DropdownButtonFormField<int>(
                                  key: ValueKey('check_dropdown_${selectedCheckIds.length}_$_currentCheckId'),
                                  isExpanded: true,
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
                                                'Nº ${c.checkNumber} (\$ ${c.amount.toCurrency()}) - ${c.bankName}',
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _currentCheckId = val;
                                      if (val != null) {
                                        final check = availableChecks
                                            .firstWhere((c) => c.id == val);
                                        _paymentAmountController.text =
                                            check.amount.toArsInput();
                                      }
                                    });
                                  },
                                ),
                        ],
                      ],
                    ),
                  ),

                  // ── Checkbox de Impresión / Vista Previa (o Solo Registrar si se destilda) ──
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: CheckboxListTile(
                      value: _printReceipt,
                      onChanged: (val) {
                        setState(() => _printReceipt = val ?? true);
                        _savePrintPreference(val ?? true);
                      },
                      title: const Text(
                        'Imprimir / Ver comprobante al registrar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _printReceipt
                            ? 'Al guardar podrás elegir Ticket Térmico (58/80mm) o Hoja A4/Carta'
                            : 'Solo registrar movimiento (sin abrir vista previa ni imprimir)',
                        style: TextStyle(
                          fontSize: 12,
                          color: _printReceipt ? Colors.blueGrey.shade600 : Colors.grey.shade600,
                        ),
                      ),
                      secondary: Icon(
                        _printReceipt ? Icons.print : Icons.print_disabled_outlined,
                        color: _printReceipt ? Colors.blue : Colors.grey,
                      ),
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
                          '\$${_totalAmount.toCurrency()}',
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
      ),
    );
  }
}
