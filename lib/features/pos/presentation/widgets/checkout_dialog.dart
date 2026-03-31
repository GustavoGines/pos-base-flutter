import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import '../providers/pos_provider.dart';
import '../../domain/entities/payment_method.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../customers/presentation/widgets/customer_form_dialog.dart';
import '../../../customers/providers/customer_provider.dart';
import '../../../customers/models/customer_model.dart';
import '../../../../core/utils/snack_bar_service.dart';

class PaymentLine {
  PaymentMethod? method;
  TextEditingController controller;
  TextEditingController percentageController;
  FocusNode percentageFocus;

  PaymentLine({this.method, double initialAmount = 0.0})
      : controller = TextEditingController(text: initialAmount > 0 ? initialAmount.toStringAsFixed(2) : ''),
        percentageController = TextEditingController(text: method?.surchargeValue.toStringAsFixed(1) ?? '0.0'),
        percentageFocus = FocusNode();

  double get amount => double.tryParse(controller.text) ?? 0.0;
  double get currentPercentage => double.tryParse(percentageController.text) ?? 0.0;
  
  double get surcharge {
    if (method == null || method!.isCash) return 0.0;
    return (currentPercentage / 100.0) * amount;
  }
  
  double get total => amount + surcharge;

  void updateMethod(PaymentMethod? m) {
    method = m;
    percentageController.text = m?.surchargeValue.toStringAsFixed(1) ?? '0.0';
  }

  void dispose() {
    controller.dispose();
    percentageController.dispose();
    percentageFocus.dispose();
  }
}

class CheckoutDialog extends StatefulWidget {
  final double total;
  final int? saleId;

  const CheckoutDialog({Key? key, required this.total, this.saleId}) : super(key: key);

  @override
  State<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<CheckoutDialog> {
  final List<PaymentLine> _lines = [];
  // Rastreo del último método VÁLIDO por línea para revertir si el usuario
  // intenta seleccionar una opción bloqueada (ej: cuenta_corriente en plan Basic)
  final List<PaymentMethod?> _previousValidMethods = [];
  bool _printReceipt = true;

  // Global cash tendered
  final _cashTenderedCtrl = TextEditingController();
  // FocusNode dedicado para poder enfocar el campo por código
  final _cashTenderedFocus = FocusNode();

  Customer? _selectedCustomer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFirstLine();
    });
    _cashTenderedCtrl.addListener(() => setState(() {}));
  }

  void _initFirstLine() {
    final provider = context.read<PosProvider>();
    if (provider.paymentMethods.isNotEmpty) {
      final defaultCash = provider.paymentMethods.firstWhere((p) => p.isCash, orElse: () => provider.paymentMethods.first);
      final line = PaymentLine(method: defaultCash, initialAmount: widget.total);
      line.controller.addListener(_onAmountChanged);
      line.percentageController.addListener(_onAmountChanged);
      setState(() {
        _lines.add(line);
        _previousValidMethods.add(defaultCash);
      });
      // Sincronizar el campo tendered con el efectivo requerido (sin auto-focus en init)
      _syncCashField();
    }
  }

  @override
  void dispose() {
    for (var line in _lines) {
      line.dispose();
    }
    _cashTenderedCtrl.dispose();
    _cashTenderedFocus.dispose();
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  /// Sincroniza el campo "Efectivo Recibido" con la porción en efectivo actual.
  /// Se llama en cada cambio estructural: agregar/quitar línea o cambiar método.
  /// [autoFocus] pone el cursor en el campo para que el cajero tipee el monto recibido.
  void _syncCashField({bool autoFocus = false}) {
    final req = _lines
        .where((l) => l.method?.isCash == true)
        .fold(0.0, (double sum, l) => sum + l.amount);

    // Actualizar el texto solo si el valor difiere (evita recursión del listener)
    final currentText = _cashTenderedCtrl.text;
    final newText = req > 0 ? req.toStringAsFixed(2) : '';
    if (currentText != newText) {
      _cashTenderedCtrl.text = newText;
      // Mover cursor al final del texto
      _cashTenderedCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _cashTenderedCtrl.text.length),
      );
    }

    if (autoFocus && req > 0) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) {
          _cashTenderedFocus.requestFocus();
          _cashTenderedCtrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _cashTenderedCtrl.text.length,
          );
        }
      });
    }
  }

  void _addLine() {
    final provider = context.read<PosProvider>();
    if (provider.paymentMethods.isEmpty) return;
    
    // Auto-fill available balance
    double left = _pendingBalance > 0 ? _pendingBalance : 0.0;

    // Usar el primer método que no sea cuenta_corriente como default seguro
    final defaultMethod = provider.paymentMethods.firstWhere(
      (m) => m.code != 'cuenta_corriente',
      orElse: () => provider.paymentMethods.first,
    );

    final line = PaymentLine(method: defaultMethod, initialAmount: left);
    line.controller.addListener(_onAmountChanged);
    line.percentageController.addListener(_onAmountChanged);
    setState(() {
      _lines.add(line);
      _previousValidMethods.add(defaultMethod);
    });
    // Sincronizar el efectivo y auto-enfocar: el cajero tiene que tipear cuánto le dan
    _syncCashField(autoFocus: defaultMethod.isCash);
  }

  void _removeLine(int index) {
    if (_lines.length > 1) {
      final line = _lines[index];
      line.controller.removeListener(_onAmountChanged);
      line.percentageController.removeListener(_onAmountChanged);
      line.dispose();
      setState(() {
        _lines.removeAt(index);
        if (index < _previousValidMethods.length) {
          _previousValidMethods.removeAt(index);
        }
      });
      // Re-sincronizar al quitar una línea (puede cambiar el efectivo requerido)
      _syncCashField();
    }
  }

  double get _totalBaseAmount => _lines.fold(0, (sum, line) => sum + line.amount);
  double get _totalSurcharge => _lines.fold(0, (sum, line) => sum + line.surcharge);
  double get _grandTotal => widget.total + _totalSurcharge;
  double get _pendingBalance => widget.total - _totalBaseAmount;

  double get _cashRequired {
    return _lines.where((l) => l.method?.isCash == true).fold(0.0, (sum, l) => sum + l.total);
  }

  double get _actualTendered {
    if (_cashRequired == 0) return 0;
    return double.tryParse(_cashTenderedCtrl.text) ?? 0.0;
  }

  double get _change {
    if (_cashRequired == 0) return 0.0;
    return _actualTendered - _cashRequired;
  }

  bool get _hasCuentaCorriente => _lines.any((l) => l.method?.code == 'cuenta_corriente');

  double get _availableCredit {
    if (_selectedCustomer == null) return 0;
    return (_selectedCustomer!.creditLimit) - (_selectedCustomer!.balance);
  }

  bool get _canSubmit {
    if (_pendingBalance > 0.01) return false; // Allowed tiny floating errors
    if (_cashRequired > 0 && _actualTendered < (_cashRequired - 0.01)) return false;
    if (_hasCuentaCorriente && _selectedCustomer == null) return false;
    return true;
  }

  void _showProUpsellDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 8),
            const Text('Actualizá a Pro'),
          ],
        ),
        content: const Text(
            'El módulo de Cuentas Corrientes es exclusivo para licencias Pro y Enterprise.\n\n'
            '¿Qué te permite?\n'
            '• Fiar a tus clientes de confianza.\n'
            '• Controlar saldos deudores.\n'
            '• Armar estados de cuenta fiables.\n\n'
            'Contactate para subir de nivel y desbloquearlo de por vida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Colors.purple.shade700),
            child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _openCustomerPicker() async {
    final customerProvider = context.read<CustomerProvider>();
    if (customerProvider.customers.isEmpty && !customerProvider.isLoading) {
      try {
        await customerProvider.fetchCustomers();
      } catch (e) {
        if (mounted) {
          SnackBarService.error(context, 'No se pudo cargar la lista de clientes.');
        }
        return;
      }
    }

    if (!mounted) return;

    await showDialog<Customer>(
      context: context,
      builder: (ctx) => _CustomerPickerDialog(
        onSelected: (c) {
          setState(() => _selectedCustomer = c);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _processCheckout() async {
    if (_hasCuentaCorriente) {
      if (_selectedCustomer == null) {
        SnackBarService.error(context, 'Debe seleccionar un cliente para fiar.');
        return;
      }
      final ccNeed = _lines.where((l) => l.method?.code == 'cuenta_corriente').fold(0.0, (s, l) => s + l.total);
      if (ccNeed > _availableCredit) {
        SnackBarService.error(context,
          'El cliente no tiene límite de crédito suficiente. '
          'Disponible: \$${_availableCredit.toStringAsFixed(2)}');
        return;
      }
    }

    final isPending = widget.saleId != null;
    final posProvider = context.read<PosProvider>();
    final currentUser = context.read<AuthProvider>().currentUser;
    final userName = currentUser?['name'] as String?;
    final settings = context.read<SettingsProvider>().settings;

    // Convert lines to payload
    List<Map<String, dynamic>> paymentsPayload = _lines.map((l) => {
      'payment_method_id': l.method!.id,
      'base_amount': l.amount,
      'surcharge_amount': l.surcharge,
      'total_amount': l.total,
    }).toList();

    bool success;

    if (isPending) {
      success = await posProvider.payPendingSale(
        saleId: widget.saleId!,
        saleTotal: _grandTotal,
        totalSurcharge: _totalSurcharge,
        payments: paymentsPayload,
        tenderedAmount: _actualTendered,
        changeAmount: _change,
        userName: userName,
        settings: _printReceipt ? settings : null,
        userId: currentUser?['id'] as int?,
      );
    } else {
      final shiftId = context.read<CashRegisterProvider>().currentShift?.id;
      final userId = currentUser?['id'] as int?;

      if (shiftId == null) {
        SnackBarService.error(context, 'No hay turno de caja abierto');
        return;
      }

      success = await posProvider.processCheckout(
        shiftId: shiftId,
        totalSurcharge: _totalSurcharge,
        payments: paymentsPayload,
        tenderedAmount: _actualTendered,
        changeAmount: _change,
        userId: userId,
        customerId: _selectedCustomer?.id,
        userName: userName,
        settings: _printReceipt ? settings : null,
      );
    }

    if (mounted) {
      if (success) {
        if (posProvider.printerWarning != null) {
          SnackBarService.warning(context, posProvider.printerWarning!);
        }
        
        // Quick Win: Refrescar alertas de stock al finalizar la venta
        try {
          context.read<CatalogProvider>().fetchCriticalAlerts();
        } catch (e) {
          debugPrint('Error refreshing stock alerts after sale: $e');
        }

        Navigator.of(context).pop(true);
      } else {
        SnackBarService.error(context, posProvider.errorMessage ?? 'Error al procesar el pago');
      }
    }
  }

  IconData _getIconForMethod(String code) {
    if (code.contains('efectivo')) return Icons.payments_outlined;
    if (code.contains('debito')) return Icons.credit_card;
    if (code.contains('credito')) return Icons.credit_score;
    if (code.contains('transferencia')) return Icons.account_balance_outlined;
    if (code.contains('cuenta')) return Icons.book_outlined;
    return Icons.money;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final bool isBasicPlan = settings?.licensePlanType?.toLowerCase() == 'basic';
    final isPending = widget.saleId != null;

    if (provider.paymentMethods.isEmpty) {
      return Dialog(
        child: Container(
          padding: const EdgeInsets.all(32),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Cargando métodos de pago..."),
            ],
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header
              if (isPending) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, color: Colors.blue.shade700, size: 22),
                    const SizedBox(width: 8),
                    Text('Cobrar Orden #${widget.saleId}',
                        style: TextStyle(fontSize: 18, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
              ] else
                const Text('Desglose de Pago (Split Tender)', style: TextStyle(fontSize: 18, color: Colors.black54, fontWeight: FontWeight.bold)),
              
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                // Mostrar el desglose completo SOLO si hay recargos,
                // si no, mostrar solo el total para evitar confusión con "$0.00 Recargo"
                child: _totalSurcharge > 0
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('Total Base', style: TextStyle(fontSize: 14, color: Colors.black54)),
                              Text('\$${widget.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Text('+', style: TextStyle(fontSize: 24, color: Colors.black26)),
                          Column(
                            children: [
                              Text('Recargos', style: TextStyle(fontSize: 14, color: Colors.orange.shade700, fontWeight: FontWeight.bold)),
                              Text('\$${_totalSurcharge.toStringAsFixed(2)}',
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                            ],
                          ),
                          Text('=', style: TextStyle(fontSize: 24, color: Colors.black26)),
                          Column(
                            children: [
                              const Text('Gran Total', style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.bold)),
                              Text('\$${_grandTotal.toStringAsFixed(2)}',
                                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              const Text('Total a Cobrar', style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.bold)),
                              Text('\$${_grandTotal.toStringAsFixed(2)}',
                                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                            ],
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 24),

              // ── Líneas de Pago
              Column(
                children: _lines.asMap().entries.map((entry) {
                  int idx = entry.key;
                  PaymentLine line = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          // Key con method.id garantiza que Flutter recree el widget
                          // si hacemos revert explícito, evitando estados visuales desincronizados
                          child: DropdownButtonFormField<PaymentMethod>(
                            key: ValueKey('dd_${idx}_${line.method?.id}'),
                            isExpanded: true,
                            icon: Icon(Icons.arrow_drop_down_rounded, color: Colors.blue.shade700),
                            decoration: InputDecoration(
                              labelText: 'Método',
                              labelStyle: TextStyle(color: Colors.blue.shade700),
                              filled: true,
                              fillColor: Colors.blue.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.blue.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.blue.shade200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.blue.shade500, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            value: line.method,
                            items: provider.paymentMethods.map((m) {
                              final bool isCuentaCorriente = m.code == 'cuenta_corriente';
                              final bool isLocked = isCuentaCorriente && isBasicPlan;
                              
                              return DropdownMenuItem<PaymentMethod>(
                                value: m,
                                // enabled: true — el item es clickeable aunque sea Premium.
                                // Al hacer click → onChanged muestra el upsell y revierte.
                                enabled: true,
                                child: Row(
                                  children: [
                                    Icon(
                                      _getIconForMethod(m.code),
                                      color: Colors.blue.shade700,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        m.name,
                                        style: TextStyle(
                                          color: Colors.blue.shade900,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Hint sutil de que es premium — no deshabilita ni grisea
                                    if (isLocked) ...[
                                      const SizedBox(width: 6),
                                      Tooltip(
                                        message: 'Función Pro — Hacé clic para conocer más',
                                        child: Icon(
                                          Icons.workspace_premium,
                                          size: 15,
                                          color: Colors.orange.shade400,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val == null) return;
                              
                              if (val.code == 'cuenta_corriente' && isBasicPlan) {
                                _showProUpsellDialog();
                                
                                // Revertir explícitamente al último método válido
                                final prev = (idx < _previousValidMethods.length)
                                    ? _previousValidMethods[idx]
                                    : line.method;
                                    
                                // Truco Flutter: Primero aceptamos el valor bloqueado para forzar a 
                                // que cambie la `ValueKey` y elimine el estado interno bugeado.
                                setState(() => line.updateMethod(val));
                                
                                // En el microsegundo siguiente, restauramos el método verdadero
                                // Así Flutter se ve forzado a renderizar desde cero con la opción original.
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    setState(() => line.updateMethod(prev));
                                  }
                                });
                                return;
                              }
                              setState(() {
                                // Guardar el nuevo método como "previo válido" antes de cambiar
                                if (idx < _previousValidMethods.length) {
                                  _previousValidMethods[idx] = val;
                                }
                                line.updateMethod(val);
                              });
                              // Sincronizar el campo de efectivo recibido.
                              // Si el método elegido es efectivo → auto-foco para que
                              // el cajero tipee cuánto le dan.
                              _syncCashField(autoFocus: val.isCash);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: line.controller,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Monto a Cubrir',
                              prefixText: '\$ ',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        if (line.method?.isCash != true) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 64,
                            child: Focus(
                              focusNode: line.percentageFocus,
                              onFocusChange: (hasFocus) {
                                if (!hasFocus && line.method != null) {
                                  final newPct = double.tryParse(line.percentageController.text) ?? 0.0;
                                  if (newPct != line.method!.surchargeValue) {
                                    provider.updatePaymentMethodSurcharge(line.method!.id, newPct);
                                  }
                                }
                              },
                              child: TextFormField(
                                controller: line.percentageController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: '% Int.',
                                  labelStyle: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 80,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Extra', style: TextStyle(fontSize: 10, color: Colors.orange)),
                                Text('\$${line.surcharge.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: _lines.length > 1 ? () => _removeLine(idx) : null,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Completar con otro método'),
                  onPressed: _pendingBalance > 0.01 ? _addLine : null,
                ),
              ),

              const Divider(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saldo Pendiente a Cubrir:', style: TextStyle(fontSize: 16)),
                  Text(
                    _pendingBalance > 0 ? '\$${_pendingBalance.toStringAsFixed(2)}' : '\$0.00',
                    style: TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.bold, 
                      color: _pendingBalance > 0.01 ? Colors.red.shade700 : Colors.green.shade700
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Cliente Selector si usa Cta Corriente
              if (_hasCuentaCorriente) ...[
                GestureDetector(
                  onTap: _openCustomerPicker,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _selectedCustomer != null ? Colors.purple.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _selectedCustomer != null ? Colors.purple.shade300 : Colors.orange.shade400),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person, color: _selectedCustomer != null ? Colors.purple : Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _selectedCustomer == null
                              ? Text('Seleccionar Cliente (Cta. Cte.)', style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold))
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_selectedCustomer!.name, style: TextStyle(color: Colors.purple.shade700, fontWeight: FontWeight.bold)),
                                    Text('Crédito disp: \$${_availableCredit.toStringAsFixed(2)}', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Efectivo Recibido y Vuelto
              if (_cashRequired > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cashTenderedCtrl,
                        focusNode: _cashTenderedFocus,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        onTap: () {
                          // Selecciona todo el texto pre-cargado para sobreescribirlo rápido
                          _cashTenderedCtrl.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _cashTenderedCtrl.text.length,
                          );
                        },
                        decoration: InputDecoration(
                          labelText: 'Efectivo Recibido',
                          hintText: 'Ej: 1000.00',
                          prefixText: '\$ ',
                          filled: true,
                          fillColor: Colors.green.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.green.shade600, width: 2),
                          ),
                          helperText: 'Ingresá el monto que entrega el cliente',
                          helperStyle: TextStyle(fontSize: 11, color: Colors.green.shade700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _change >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _change >= 0 ? Colors.green.shade200 : Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Vuelto', style: TextStyle(fontSize: 12, color: _change >= 0 ? Colors.green.shade700 : Colors.red.shade700)),
                            Text(
                              _change >= 0 ? '\$${_change.toStringAsFixed(2)}' : '-\$${_change.abs().toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _change >= 0 ? Colors.green.shade700 : Colors.red.shade700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              // Options
              CheckboxListTile(
                title: const Text('Imprimir Comprobante', style: TextStyle(fontWeight: FontWeight.bold)),
                value: _printReceipt,
                activeColor: Colors.blue.shade600,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (val) {
                  if (val != null) setState(() => _printReceipt = val);
                },
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                      onPressed: (_canSubmit && !provider.isLoading) ? _processCheckout : null,
                      child: provider.isLoading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(
                              isPending ? 'CONFIRMAR COBRO' : 'CONFIRMAR PAGO',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerPickerDialog extends StatefulWidget {
  final Function(Customer) onSelected;
  const _CustomerPickerDialog({required this.onSelected});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 450,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Seleccionar Cliente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, DNI o Tel...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('NUEVO CLIENTE'),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => const CustomerFormDialog(),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Consumer<CustomerProvider>(
                builder: (ctx, provider, _) {
                  if (provider.isLoading && provider.customers.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final query = _searchCtrl.text.toLowerCase();
                  final list = provider.customers.where((c) {
                    return c.name.toLowerCase().contains(query) ||
                        (c.documentNumber.contains(query)) ||
                        (c.phone != null && c.phone!.contains(query));
                  }).toList();

                  if (list.isEmpty) {
                    return const Center(child: Text('No se encontraron clientes.', style: TextStyle(color: Colors.grey)));
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (ctx, i) {
                      final c = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Text(c.name[0].toUpperCase(), style: const TextStyle(color: Colors.blue)),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('ID: ${c.documentNumber} - Tel: ${c.phone ?? '-'}'),
                        onTap: () => widget.onSelected(c),
                      );
                    },
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
