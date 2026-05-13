import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import '../providers/pos_provider.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/payment_method.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../customers/presentation/widgets/customer_form_dialog.dart';
import '../../../customers/providers/customer_provider.dart';
import '../../../customers/models/customer_model.dart';
import '../../../../core/utils/snack_bar_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/presentation/widgets/ticket_preview_dialog.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';

class PaymentLine {
  PaymentMethod? method;
  TextEditingController controller;
  TextEditingController percentageController;
  FocusNode percentageFocus;

  TextEditingController checkBankController;
  TextEditingController checkNumberController;
  TextEditingController checkIssuerCuitController;
  TextEditingController checkIssuerNameController;
  TextEditingController checkIssueDateController;
  TextEditingController checkPaymentDateController;

  PaymentLine({this.method, double initialAmount = 0.0, double? defaultCardSurcharge, bool disableSurcharge = false})
      : controller = TextEditingController(text: initialAmount > 0 ? initialAmount.toCurrency() : ''),
        percentageController = TextEditingController(),
        percentageFocus = FocusNode(),
        checkBankController = TextEditingController(),
        checkNumberController = TextEditingController(),
        checkIssuerCuitController = TextEditingController(),
        checkIssuerNameController = TextEditingController(),
        checkIssueDateController = TextEditingController(text: DateTime.now().toString().split(' ')[0]),
        checkPaymentDateController = TextEditingController(text: DateTime.now().add(const Duration(days: 30)).toString().split(' ')[0]) {
    updateMethod(method, defaultCardSurcharge: defaultCardSurcharge, disableSurcharge: disableSurcharge);
  }

  double get amount => double.tryParse(controller.text.replaceAll(',', '.')) ?? 0.0;
  double get currentPercentage => double.tryParse(percentageController.text.replaceAll(',', '.')) ?? 0.0;
  
  double get surcharge {
    if (method == null || method!.isCash) return 0.0;
    return (currentPercentage / 100.0) * amount;
  }
  
  double get total => amount + surcharge;

  void updateMethod(PaymentMethod? m, {double? defaultCardSurcharge, bool disableSurcharge = false}) {
    method = m;
    if (disableSurcharge) {
      percentageController.text = '0.0';
      return;
    }
    double val = m?.surchargeValue ?? 0.0;
    
    // Si el cajero selecciona tarjeta de crédito/débito y la BD local no tiene un recargo específico,
    // inyectamos automáticamente el recargo global de configuraciones (ej: 15%).
    if (m != null && val == 0.0 && defaultCardSurcharge != null && defaultCardSurcharge > 0) {
      if (m.code.contains('credito') || m.code.contains('tarjeta')) {
        val = defaultCardSurcharge;
      }
    }
    
    percentageController.text = val.toStringAsFixed(1);
  }

  void dispose() {
    controller.dispose();
    percentageController.dispose();
    percentageFocus.dispose();
    checkBankController.dispose();
    checkNumberController.dispose();
    checkIssuerCuitController.dispose();
    checkIssuerNameController.dispose();
    checkIssueDateController.dispose();
    checkPaymentDateController.dispose();
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
  bool _showPreview = false;
  bool _requiresDispatch = false; 
  String _fulfillmentStatus = 'pending'; 

  // Global cash tendered
  final _cashTenderedCtrl = TextEditingController();
  // FocusNode dedicado para poder enfocar el campo por código
  final _cashTenderedFocus = FocusNode();
  
  late TextEditingController _shippingCostCtrl;
  final _deliveryAddressCtrl = TextEditingController();

  Customer? _selectedCustomer;
  
  bool get _isCartAlreadySurcharged {
    // En Modo Básico (toggle off) los surcharges de métodos de pago SIEMPRE aplican.
    final settings = context.read<SettingsProvider>().settings;
    if (settings == null || !settings.enableAdvancedPriceTiers) return false;
    // En Modo Avanzado: suprimimos el recargo del método si el carrito ya tiene
    // el factor de tarjeta o un custom con recargo positivo (para evitar doble cobro).
    final pos = context.read<PosProvider>();
    return pos.activeTier == PriceTier.card || (pos.activeTier == PriceTier.custom && pos.currentCustomFactor > 1.0);
  }

  @override
  void initState() {
    super.initState();
    final posProvider = context.read<PosProvider>();
    
    // Auto-seleccionar el último cliente usado en Cta Cte si existe
    _selectedCustomer = posProvider.lastSelectedCustomer;
    if (_selectedCustomer != null) {
      _deliveryAddressCtrl.text = _selectedCustomer!.deliveryAddress ?? '';
    }
    
    // Recuperar estado persistente si existe, o usar la memoria del último flete
    _requiresDispatch = posProvider.currentRequiresDispatch;
    _fulfillmentStatus = posProvider.currentFulfillmentStatus;
    
    // Si la venta actual tiene 0 (porque acabamos de empezar o limpiar), sugerimos el último usado
    final initialShipping = posProvider.shippingCost > 0 
        ? posProvider.shippingCost 
        : posProvider.lastUsedShippingCost;

    _shippingCostCtrl = TextEditingController(
      text: initialShipping > 0 
          ? initialShipping.toCurrency() 
          : ''
    );
    // Sincronizar la memoria local del diálogo con el último flete usado
    // (No llamamos a setShippingCost del provider para no alterar el total del fondo prematuramente)
    _shippingCostCtrl.addListener(() {
      setState(() {});
      _syncPaymentsWithShipping();
    });
    _loadPrintPreference();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFirstLine();
    });
    _cashTenderedCtrl.addListener(() => setState(() {}));
  }

  Future<void> _loadPrintPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _printReceipt = prefs.getBool('auto_print_receipt') ?? true;
        _showPreview = prefs.getBool('show_preview_receipt') ?? false;
      });
    }
  }

  void _initFirstLine() {
    final provider = context.read<PosProvider>();
    final settings = context.read<SettingsProvider>().settings;
    if (provider.paymentMethods.isNotEmpty) {
      final defaultCash = provider.paymentMethods.firstWhere((p) => p.isCash, orElse: () => provider.paymentMethods.first);
      final line = PaymentLine(
        method: defaultCash, 
        initialAmount: widget.total + (_requiresDispatch ? _shippingCostToApply : 0.0),
        defaultCardSurcharge: settings?.globalCardPercentage,
        disableSurcharge: _isCartAlreadySurcharged,
      );
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
    _shippingCostCtrl.dispose();
    _cashTenderedFocus.dispose();
    _deliveryAddressCtrl.dispose();
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
    final newText = req > 0 ? req.toCurrency() : '';
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

  /// Cuando el flete cambia y hay UNA SOLA línea de pago, actualiza el
  /// monto automáticamente para que el Saldo Pendiente quede en $0.
  void _syncPaymentsWithShipping() {
    if (_lines.length != 1) return; // Solo auto-sync con pago único
    final newTotal = widget.total + _shippingCostToApply;
    final line = _lines[0];
    // Actualizar el amount de la línea
    final newText = newTotal.toCurrency();
    if (line.controller.text != newText) {
      line.controller.text = newText;
      line.controller.selection = TextSelection.fromPosition(
        TextPosition(offset: line.controller.text.length),
      );
    }
    // Sincronizar el campo de efectivo recibido
    _syncCashField();
  }

  void _addLine() {
    final provider = context.read<PosProvider>();
    final settings = context.read<SettingsProvider>().settings;
    if (provider.paymentMethods.isEmpty) return;
    
    // Auto-fill available balance
    double left = _pendingBalance > 0 ? _pendingBalance : 0.0;

    // Usar el primer método que no sea cuenta_corriente como default seguro
    final defaultMethod = provider.paymentMethods.firstWhere(
      (m) => m.code != 'cuenta_corriente',
      orElse: () => provider.paymentMethods.first,
    );

    final line = PaymentLine(
      method: defaultMethod, 
      initialAmount: left,
      defaultCardSurcharge: settings?.globalCardPercentage,
      disableSurcharge: _isCartAlreadySurcharged,
    );
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
  
  double get _shippingCostToApply {
    if (_requiresDispatch && _fulfillmentStatus == 'pending') {
      return double.tryParse(_shippingCostCtrl.text.replaceAll(',', '.')) ?? 0.0;
    }
    return 0.0;
  }

  double get _grandTotal => widget.total + _totalSurcharge + _shippingCostToApply;
  double get _pendingBalance => widget.total + _shippingCostToApply - _totalBaseAmount;

  double get _cashRequired {
    return _lines.where((l) => l.method?.isCash == true).fold(0.0, (sum, l) => sum + l.total);
  }

  double get _actualTendered {
    if (_cashRequired == 0) return 0;
    return double.tryParse(_cashTenderedCtrl.text.replaceAll(',', '.')) ?? 0.0;
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
    if (_pendingBalance > 0.01) return false; // Saldo pendiente sin cubrir
    // Solo bloquear si el cajero ingresó un monto recibido MENOR al efectivo de la línea
    // y el campo fue modificado manualmente (no está vacío ni igual al monto de la línea)
    if (_cashRequired > 0) {
      final tendered = _actualTendered;
      final cashText = _cashTenderedCtrl.text.trim();
      // Si el campo tiene algo escrito y es menor al requerido → bloquear
      if (cashText.isNotEmpty && tendered > 0 && tendered < (_cashRequired - 0.01)) return false;
    }
    if (_hasCuentaCorriente && _selectedCustomer == null) return false;
    return true;
  }

  void _showProUpsellDialog([String? methodName]) {
    final isCheque = methodName?.toLowerCase().contains('cheque') == true;
    final title = isCheque ? 'Actualizá a Premium' : 'Actualizá a Premium';
    final content = isCheque 
        ? 'El cobro con cheques de terceros es exclusivo del Plan Premium.\n\n¿Qué te permite?\n• Registrar cheques diferidos.\n• Visualizar la cartera en el dashboard.\n• Semáforo de pagos próximos.'
        : 'El módulo de Cuentas Corrientes es exclusivo para el Plan Premium.\n\n¿Qué te permite?\n• Fiar a tus clientes de confianza.\n• Controlar saldos deudores.\n• Armar estados de cuenta fiables.\n\nContatáte para subir al Plan Premium y desbloquearlo.';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(content),
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
          setState(() {
            _selectedCustomer = c;
            _deliveryAddressCtrl.text = c.deliveryAddress ?? '';
          });
          context.read<PosProvider>().setLastSelectedCustomer(c);
          final localTerminal = context.read<LocalTerminalProvider>();
          if (localTerminal.lockedPriceTier == 'none' && c.defaultPriceTier != null && c.defaultPriceTier!.isNotEmpty) {
            final appSettings = context.read<SettingsProvider>();
            if (appSettings.settings?.features.multiplePrices == true) {
              PriceTier tier;
              switch (c.defaultPriceTier) {
                case 'wholesale': tier = PriceTier.wholesale; break;
                case 'card': tier = PriceTier.card; break;
                default: 
                  if (c.defaultPriceTier!.startsWith('custom_')) {
                    tier = PriceTier.custom;
                  } else {
                    tier = PriceTier.base;
                  }
              }
              final settings = appSettings.settings;
              
              if (tier == PriceTier.custom) {
                final customLabel = c.defaultPriceTier!.substring(7);
                final customTiers = settings?.customPriceTiers ?? [];
                final match = customTiers.firstWhere((t) => t['name'] == customLabel, orElse: () => {});
                final mod = (match['modifier'] as num?)?.toDouble() ?? 0.0;
                context.read<PosProvider>().setPriceTier(
                  tier,
                  customFactor: 1 + (mod / 100),
                  customLabel: customLabel,
                );
              } else {
                context.read<PosProvider>().setPriceTier(
                  tier,
                  wholesaleFactor: settings != null ? 1 + (settings.globalWholesalePercentage / 100) : null,
                  cardFactor: settings != null ? 1 + (settings.globalCardPercentage / 100) : null,
                );
              }
              // Como CheckoutDialog tiene copia estática del 'total', si el tier bajó los precios el total debe recalcularse.
              // Para no complicar la caja con saldos saltando de golpe, le avisamos al Provider que ya recalculó en background.
              // El cajero verá el nuevo total en la barra superior del diálogo si lo cerramos.
            }
          }
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
      if (!_selectedCustomer!.isInternalAccount && ccNeed > _availableCredit) {
        SnackBarService.error(context,
          'El cliente no tiene límite de crédito suficiente. '
          'Disponible: \$${_availableCredit.toCurrency()}');
        return;
      }
    }

    final isPending = widget.saleId != null;
    final posProvider = context.read<PosProvider>();
    final currentUser = context.read<AuthProvider>().currentUser;
    final userName = currentUser?['name'] as String?;
    final settings = context.read<SettingsProvider>().settings;

    // Build Check Details Payload if a cheque is used
    Map<String, dynamic>? checkDetailsPayload;
    try {
      final chequeLine = _lines.firstWhere((l) => l.method?.code == 'cheque');
      if (chequeLine.checkBankController.text.trim().isEmpty ||
          chequeLine.checkNumberController.text.trim().isEmpty ||
          chequeLine.checkIssuerCuitController.text.trim().isEmpty ||
          chequeLine.checkIssuerNameController.text.trim().isEmpty) {
        SnackBarService.error(context, 'Complete los datos obligatorios del cheque (Banco, Número, CUIT, Firmante).');
        return;
      }
      checkDetailsPayload = {
        'bank_name': chequeLine.checkBankController.text.trim(),
        'check_number': chequeLine.checkNumberController.text.trim(),
        'issuer_cuit': chequeLine.checkIssuerCuitController.text.trim(),
        'issuer_name': chequeLine.checkIssuerNameController.text.trim(),
        'issue_date': chequeLine.checkIssueDateController.text.trim(),
        'payment_date': chequeLine.checkPaymentDateController.text.trim(),
        'amount': chequeLine.total,
      };
    } catch (_) {
      // No cheque payment line found, which is fine.
    }

    // Convert lines to payload
    List<Map<String, dynamic>> paymentsPayload = _lines.map((l) => {
      'payment_method_id': l.method!.id,
      'base_amount': l.amount,
      'surcharge_amount': l.surcharge,
      'total_amount': l.total,
    }).toList();

    // Vista Previa: solo aplica para impresoras térmicas.
    // Para A4, el provider maneja el visor PDF directamente según showPreview.
    final localTerminal = Provider.of<LocalTerminalProvider>(context, listen: false);
    final isA4 = localTerminal.printerFormat.startsWith('a4');

    if (_printReceipt && _showPreview && !isA4) {
      final cart = posProvider.cart;
      final isNarrow = localTerminal.printerFormat == 'thermal_58';

      // ──── Replicar EXACTAMENTE la lógica de printSaleTicket ────
      final bool isComplexPayment = _lines.length > 1 || _totalSurcharge > 0.01;
      final bool hasTendered = _actualTendered > 0.01;

      final lines = <TicketLine>[
        // Encabezado
        if (settings?.companyName != null)
          TicketLine(settings!.companyName!.toUpperCase(), align: TicketAlign.center, isBold: true, isLarge: true),
        if (settings?.address != null && settings!.address!.isNotEmpty)
          TicketLine(settings.address!, align: TicketAlign.center),
        if (settings?.taxId != null && settings!.taxId!.isNotEmpty)
          TicketLine('CUIT: ${settings.taxId}', align: TicketAlign.center, isBold: true),
        const TicketLine.hr(bold: true),
        TicketLine('COMPROBANTE DE VENTA', align: TicketAlign.center, isBold: true),
        const TicketLine.hr(),
        TicketLine('FECHA: ${DateTime.now().day.toString().padLeft(2,'0')}/${DateTime.now().month.toString().padLeft(2,'0')}/${DateTime.now().year}'),
        if (userName != null) TicketLine('CAJERO: ${userName.toUpperCase()}'),
        const TicketLine.hr(),

        // Ítems del carrito
        ...cart.map((item) => [
          TicketLine(
            '${item.product.isSoldByWeight ? item.quantity.toQty() + " kg" : item.quantity.toInt().toString() + " un"} x \$${item.product.sellingPrice.toCurrency()}',
            rightText: '\$${item.subtotal.toCurrency()}',
          ),
          TicketLine(item.product.name.toUpperCase(), isBold: true),
        ]).expand((l) => l),
        const TicketLine.hr(bold: true),

        // ──── Sección de pago (igual que el ticket real) ────
        if (isComplexPayment) ...[
          TicketLine('SUBTOTAL:', rightText: '\$${widget.total.toCurrency()}', isBold: true),
          const TicketLine.hr(),
          // Un renglón por cada método de pago
          ..._lines.map((l) => TicketLine(
            (l.method?.name ?? 'PAGO').toUpperCase(),
            rightText: '\$${l.amount.toCurrency()}',
            isBold: true,
          )),
          if (_totalSurcharge > 0.01)
            TicketLine('RECARGO BANCARIO:', rightText: '\$${_totalSurcharge.toCurrency()}'),
          const TicketLine.hr(),
          if (_shippingCostToApply > 0.01)
            TicketLine('FLETE / ENVÍO:', rightText: '\$${_shippingCostToApply.toCurrency()}'),
          TicketLine('TOTAL COBRADO:', rightText: '\$${_grandTotal.toCurrency()}', isBold: true, isLarge: true),
          if (hasTendered)
            TicketLine('EFECTIVO RECIBIDO:', rightText: '\$${_actualTendered.toCurrency()}'),
          if (hasTendered)
            TicketLine('SU VUELTO:', rightText: '\$${_change.toCurrency()}', isBold: true),
        ] else ...[
          // Venta simple: un pago, sin recargos
          if (_shippingCostToApply > 0.01)
            TicketLine('FLETE / ENVÍO:', rightText: '\$${_shippingCostToApply.toCurrency()}'),
          TicketLine('TOTAL GENERAL:', rightText: '\$${_grandTotal.toCurrency()}', isBold: true, isLarge: true),
          const TicketLine.hr(),
          TicketLine('PAGO EN:', rightText: (_lines.isNotEmpty ? _lines.first.method?.name ?? 'EFECTIVO' : 'EFECTIVO').toUpperCase()),
          if (hasTendered)
            TicketLine('EFECTIVO RECIBIDO:', rightText: '\$${_actualTendered.toCurrency()}'),
          if (hasTendered)
            TicketLine('SU VUELTO:', rightText: '\$${_change.toCurrency()}', isBold: true),
        ],
        const TicketLine.space(),
        TicketLine(
          isNarrow ? '**NO VALIDO COMO FACTURA**' : '*** NO VALIDO COMO FACTURA ***',
          align: TicketAlign.center,
        ),
      ];

      // AGREGADO: Si es split ticket (Retira ya), mostrar también el remito en la vista previa
      if (_requiresDispatch && _fulfillmentStatus == 'delivered') {
        lines.add(const TicketLine.space());
        lines.add(const TicketLine.hr(bold: true)); // Simular corte
        lines.add(const TicketLine.space());
        lines.add(const TicketLine('ORDEN DE RETIRO / REMITO', align: TicketAlign.center, isBold: true));
        lines.add(const TicketLine.hr());
        lines.add(const TicketLine('REMITO N°: (PROXIMO)'));
        lines.add(const TicketLine('VENTA ASOC: (PROXIMA)'));
        lines.add(TicketLine('FECHA: ${DateTime.now().day.toString().padLeft(2,"0")}/${DateTime.now().month.toString().padLeft(2,"0")}/${DateTime.now().year}'));
        if (_selectedCustomer != null) {
          lines.add(TicketLine('CLIENTE: ${_selectedCustomer!.name.toUpperCase()}', isBold: true));
        }
        if (userName != null) {
          lines.add(TicketLine('VENDIÓ: ${userName.toUpperCase()}'));
        }
        lines.add(const TicketLine.hr());
        lines.add(const TicketLine('ARTICULOS A RETIRAR:', isBold: true));
        lines.add(const TicketLine.hr());
        
        for (final item in cart) {
          final qtyStr = item.product.isSoldByWeight ? '${item.quantity.toStringAsFixed(3)} kg' : '${item.quantity.toInt()} un';
          lines.add(TicketLine(item.product.name.toUpperCase(), rightText: qtyStr, isBold: true));
        }
        
        lines.add(const TicketLine.hr(bold: true));
        lines.add(const TicketLine.space());
        lines.add(const TicketLine('FIRMA DESPACHANTE:'));
        lines.add(const TicketLine.space());
        lines.add(const TicketLine('__________________________', align: TicketAlign.center));
        lines.add(const TicketLine.space());
        lines.add(const TicketLine('FIRMA CLIENTE / RETIRA:'));
        lines.add(const TicketLine.space());
        lines.add(const TicketLine('__________________________', align: TicketAlign.center));
        lines.add(const TicketLine.space());
      }

      if (!mounted) return;
      final confirmed = await TicketPreviewDialog.show(
        context,
        title: 'Vista Previa — Ticket ${isNarrow ? "58mm" : "80mm"}',
        lines: lines,
      );
      if (!mounted || !confirmed) return;
    }

    context.read<PosProvider>().setShippingCost(
      double.tryParse(_shippingCostCtrl.text.replaceAll(',', '.')) ?? 0.0
    );

    bool success;

    final shiftId = context.read<CashRegisterProvider>().currentShift?.id;
    final userId = currentUser?['id'] as int?;

    if (shiftId == null) {
      SnackBarService.error(context, 'No hay turno de caja abierto');
      return;
    }

    if (isPending) {
      success = await posProvider.payPendingSale(
        saleId: widget.saleId!,
        saleTotal: _grandTotal,
        totalSurcharge: _totalSurcharge,
        payments: paymentsPayload,
        tenderedAmount: _actualTendered,
        changeAmount: _change,
        shiftId: shiftId,
        localTerminal: localTerminal,
        userName: userName,
        settings: _printReceipt ? settings : null,
        userId: userId,
        showPreview: _showPreview,
        checkDetails: checkDetailsPayload,
      );
    } else {
      success = await posProvider.processCheckout(
        shiftId: shiftId,
        totalSurcharge: _totalSurcharge,
        payments: paymentsPayload,
        tenderedAmount: _actualTendered,
        changeAmount: _change,
        printerFormat: localTerminal.printerFormat,
        localTerminal: localTerminal,
        userId: userId,
        customerId: _selectedCustomer?.id,
        userName: userName,
        settings: _printReceipt ? settings : null,
        showPreview: _showPreview,
        requiresDispatch: _requiresDispatch,
        fulfillmentStatus: _fulfillmentStatus,
        checkDetails: checkDetailsPayload,
        deliveryAddress: _deliveryAddressCtrl.text.trim().isEmpty ? null : _deliveryAddressCtrl.text.trim(),
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
        final errMsg = posProvider.errorMessage ?? '';

        if (errMsg == 'ANNULLED') {
          Navigator.of(context).pop(false);
          return;
        }

        // ──── Sesión Única: el error viene del ValidateSessionToken middleware ────
        // El dialog se cierra con false para devolver el control a _handleCheckout
        // en pos_screen, que es quien muestra el dialog de seguridad naranja y
        // fuerza el logout + navegación a /login.
        if (errMsg.contains('SESSION_EXPIRED') || errMsg.contains('otro dispositivo')) {
          Navigator.of(context).pop(false);
          return;
        }

        SnackBarService.error(context, errMsg.isNotEmpty ? errMsg : 'Error al procesar el pago');

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
              // ──── Header
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
                const Text('Desglose de Pago', style: TextStyle(fontSize: 18, color: Colors.black54, fontWeight: FontWeight.bold)),
              
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
                              Text('\$${widget.total.toCurrency()}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Text('+', style: TextStyle(fontSize: 24, color: Colors.black26)),
                          Column(
                            children: [
                              Text('Recargos', style: TextStyle(fontSize: 14, color: Colors.orange.shade700, fontWeight: FontWeight.bold)),
                              Text('\$${_totalSurcharge.toCurrency()}',
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                            ],
                          ),
                          Text('=', style: TextStyle(fontSize: 24, color: Colors.black26)),
                          Column(
                            children: [
                              const Text('Gran Total', style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.bold)),
                              Text('\$${_grandTotal.toCurrency()}',
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
                              Text('\$${_grandTotal.toCurrency()}',
                                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                            ],
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 24),

              // ──── Líneas de Pago
              Column(
                children: _lines.asMap().entries.map((entry) {
                  int idx = entry.key;
                  PaymentLine line = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      children: [
                        Row(
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
                              final bool isCheque = m.code == 'cheque';
                              final bool isLocked = (isCuentaCorriente && settings?.features.currentAccounts != true) || (isCheque && settings?.features.checks != true);
                              
                              return DropdownMenuItem<PaymentMethod>(
                                value: m,
                                // enabled: true —  el item es clickeable aunque sea Premium.
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
                                    // Hint sutil de que es premium —  no deshabilita ni grisea
                                    if (isLocked) ...[
                                      const SizedBox(width: 6),
                                      Tooltip(
                                        message: 'Función Pro —  Hacé clic para conocer más',
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
                              
                              final bool isCuentaCorrienteSel = val.code == 'cuenta_corriente';
                              final bool isChequeSel = val.code == 'cheque';
                              final bool isLockedSel = (isCuentaCorrienteSel && settings?.features.currentAccounts != true) || (isChequeSel && settings?.features.checks != true);

                              if (isLockedSel) {
                                _showProUpsellDialog(val.name);
                                
                                // Revertir explícitamente al último método válido
                                final prev = (idx < _previousValidMethods.length)
                                    ? _previousValidMethods[idx]
                                    : line.method;
                                    
                                // Truco Flutter: Primero aceptamos el valor bloqueado para forzar a 
                                // que cambie la `ValueKey` y elimine el estado interno bugeado.
                                setState(() => line.updateMethod(val, defaultCardSurcharge: settings?.globalCardPercentage, disableSurcharge: _isCartAlreadySurcharged));
                                
                                // En el microsegundo siguiente, restauramos el método verdadero
                                // Así Flutter se ve forzado a renderizar desde cero con la opción original.
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    setState(() => line.updateMethod(prev, defaultCardSurcharge: settings?.globalCardPercentage, disableSurcharge: _isCartAlreadySurcharged));
                                  }
                                });
                                return;
                              }
                              setState(() {
                                // Guardar el nuevo método como "previo válido" antes de cambiar
                                if (idx < _previousValidMethods.length) {
                                  _previousValidMethods[idx] = val;
                                }
                                line.updateMethod(val, defaultCardSurcharge: settings?.globalCardPercentage, disableSurcharge: _isCartAlreadySurcharged);
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
                                  final newPct = double.tryParse(line.percentageController.text.replaceAll(',', '.')) ?? 0.0;
                                  if (newPct != line.method!.surchargeValue) {
                                    provider.updatePaymentMethodSurcharge(line.method!.id, newPct);
                                  }
                                }
                              },
                              child: TextFormField(
                                controller: line.percentageController,
                                readOnly: _isCartAlreadySurcharged,
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
                                Text('\$${line.surcharge.toCurrency()}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
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
                        // ── Formulario de cheque (se despliega cuando code == 'cheque') ──
                        if (line.method?.code == 'cheque')
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Detalles del Cheque', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: TextField(controller: line.checkBankController, decoration: InputDecoration(labelText: 'Banco', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                    const SizedBox(width: 8),
                                    Expanded(child: TextField(controller: line.checkNumberController, decoration: InputDecoration(labelText: 'Nro Cheque', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: TextField(controller: line.checkIssuerCuitController, decoration: InputDecoration(labelText: 'CUIT Firmante', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                    const SizedBox(width: 8),
                                    Expanded(child: TextField(controller: line.checkIssuerNameController, decoration: InputDecoration(labelText: 'Nombre Firmante', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: TextField(controller: line.checkIssueDateController, decoration: InputDecoration(labelText: 'Emisión (YYYY-MM-DD)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                    const SizedBox(width: 8),
                                    Expanded(child: TextField(controller: line.checkPaymentDateController, decoration: InputDecoration(labelText: 'Cobro (YYYY-MM-DD)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white))),
                                  ],
                                ),
                              ],
                            ),
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
                    _pendingBalance > 0 ? '\$${_pendingBalance.toCurrency()}' : '\$0.00',
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
                                    Text(_selectedCustomer!.isInternalAccount ? 'Crédito disp: Ilimitado (Cuenta Interna)' : 'Crédito disp: \$${_availableCredit.toCurrency()}', style: TextStyle(fontSize: 12)),
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
                              _change >= 0 ? '\$${_change.toCurrency()}' : '-\$${_change.abs().toCurrency()}',
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

              // Options: Imprimir + Vista Previa
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      title: const Text('Imprimir Comprobante', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: _printReceipt,
                      activeColor: Colors.blue.shade600,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() => _printReceipt = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('auto_print_receipt', val);
                        }
                      },
                    ),
                  ),
                  if (_printReceipt)
                    Tooltip(
                      message: 'Ver previa antes de imprimir',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _showPreview,
                            activeColor: Colors.orange,
                            onChanged: (val) async {
                              if (val != null) {
                                setState(() => _showPreview = val);
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setBool('show_preview_receipt', val);
                              }
                            },
                          ),
                          const Text('Vista Previa', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Toggle Logística a Demanda ──────────────────────────
              // Solo visible si el plan tiene la feature 'logistics' habilitada
              if (settings?.features.logistics == true && !isPending) ...[
                const Divider(),
                Material(
                  color: _requiresDispatch
                      ? Colors.orange.shade50
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _requiresDispatch = !_requiresDispatch;
                        context.read<PosProvider>().setCurrentLogistics(_requiresDispatch, _fulfillmentStatus);
                        _syncPaymentsWithShipping();
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 24,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: _requiresDispatch
                                  ? Colors.orange.shade600
                                  : Colors.grey.shade300,
                            ),
                            child: AnimatedAlign(
                              duration: const Duration(milliseconds: 200),
                              alignment: _requiresDispatch
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.all(3),
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.local_shipping_outlined, size: 18, color: Colors.black54),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Enviar a Logística (Armar Pedido)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: _requiresDispatch
                                        ? Colors.orange.shade800
                                        : Colors.black87,
                                  ),
                                ),
                                Text(
                                  _requiresDispatch
                                      ? 'Se creará un remito automáticamente al confirmar'
                                      : 'Se entrega en el momento (sin remito)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _requiresDispatch
                                        ? Colors.orange.shade600
                                        : Colors.grey.shade500,
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
                
                if (_requiresDispatch) ...[
                  const SizedBox(height: 12),
                  Container(
                    margin: const EdgeInsets.only(left: 48), // Indentar a la altura del texto
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estado de Entrega:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('A Preparar (Pendiente)', style: TextStyle(fontSize: 12)),
                                value: 'pending',
                                groupValue: _fulfillmentStatus,
                                activeColor: Colors.orange.shade700,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                  onChanged: (val) {
                                  setState(() {
                                    _fulfillmentStatus = val!;
                                    context.read<PosProvider>().setCurrentLogistics(_requiresDispatch, _fulfillmentStatus);
                                    _syncPaymentsWithShipping();
                                  });
                                },

                              ),
                            ),
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('Se lo lleva AHORA', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                                value: 'delivered',
                                groupValue: _fulfillmentStatus,
                                activeColor: Colors.green,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                  onChanged: (val) {
                                  setState(() {
                                    _fulfillmentStatus = val!;
                                    context.read<PosProvider>().setCurrentLogistics(_requiresDispatch, _fulfillmentStatus);
                                    _syncPaymentsWithShipping();
                                  });
                                },

                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                    if (_requiresDispatch && _fulfillmentStatus == 'pending') ...[
                      const SizedBox(height: 12),
                      Container(
                        margin: const EdgeInsets.only(left: 48),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.local_shipping_outlined, size: 18, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                const Text('Flete / Envío:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const Spacer(),
                                SizedBox(
                                  width: 120,
                                  height: 36,
                                  child: TextField(
                                    controller: _shippingCostCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.right,
                                    decoration: const InputDecoration(
                                      prefixText: '\$ ',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) {
                                      // El listener de _shippingCostCtrl ya dispara setState() y _syncPaymentsWithShipping()
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 18, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _deliveryAddressCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Dirección de Entrega (Opcional)',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
              ],

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