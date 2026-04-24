import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/usecases/process_sale_usecase.dart';
import '../../domain/usecases/search_products_usecase.dart';
import '../../domain/repositories/pos_repository.dart';
import '../../data/datasources/pos_remote_datasource.dart'
    show ClosedShiftException;
import 'package:frontend_desktop/core/network/api_client.dart'
    show SessionExpiredException;
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/utils/a4_split_pdf_service.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

class PosProvider with ChangeNotifier {
  final ProcessSaleUseCase processSaleUseCase;
  final SearchProductsUseCase searchProductsUseCase;
  final PosRepository repository;
  final ReceiptPrinterService? printerService;

  final List<CartItem> _cart = [];
  List<CartItem> get cart => _cart;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Guard: evita que un doble-click genere dos API calls antes de que el Consumer reconstruya el botón
  bool _isHoldingOrder = false;
  bool get isHoldingOrder => _isHoldingOrder;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _printerWarning;
  String? get printerWarning => _printerWarning;

  // ── Seguridad: Turno Cerrado Remotamente ─────────────────────────
  // Se activa cuando el backend rechaza una venta porque el turno ya
  // fue cerrado desde otra terminal. La UI observa este flag para
  // mostrar el diálogo crítico y forzar la recarga del estado.
  bool _isShiftClosed = false;
  bool get isShiftClosed => _isShiftClosed;

  void resetShiftClosedFlag() {
    _isShiftClosed = false;
    notifyListeners();
  }

  // ── Órdenes Pendientes ──────────────────────────────────────────
  List<Map<String, dynamic>> _pendingSales = [];
  List<Map<String, dynamic>> get pendingSales => _pendingSales;

  // Seguimiento de ID de venta (útil para Corralón/Remitos post-checkout)
  int? _lastSaleId;
  double? _lastSaleTotal;
  double? _lastSaleShippingCost;
  double? _lastTenderedAmount;
  double? _lastChangeAmount;
  double? _lastSurchargeAmount;
  List<Map<String, dynamic>> _lastSalePayments = [];

  int get lastSaleId => _lastSaleId ?? 0;
  double get lastSaleTotal => _lastSaleTotal ?? 0.0;
  double get lastSaleShippingCost => _lastSaleShippingCost ?? 0.0;
  double get lastTenderedAmount => _lastTenderedAmount ?? 0.0;
  double get lastChangeAmount => _lastChangeAmount ?? 0.0;
  double get lastSurchargeAmount => _lastSurchargeAmount ?? 0.0;
  List<Map<String, dynamic>> get lastSalePayments => _lastSalePayments;

  // Rastrea si la última venta disparó un remito automático desde el checkout
  // (true = cajero activó el toggle "Enviar a Logística" y el remito ya fue creado)
  bool _wasLastSaleDispatched = false;
  bool get wasLastSaleDispatched => _wasLastSaleDispatched;

  Map<String, dynamic>? _lastDeliveryNote;
  Map<String, dynamic>? get lastDeliveryNote => _lastDeliveryNote;

  // Snapshot del carrito de la última venta (disponible incluso después de clearCart)
  List<CartItem> _lastSaleCart = [];
  List<CartItem> get lastSaleCart => _lastSaleCart;

  bool _isPendingLoading = false;
  bool get isPendingLoading => _isPendingLoading;

  // [multiple-prices] Gestión del Nivel de Precio Activo
  PriceTier _activeTier = PriceTier.base;
  PriceTier get activeTier => _activeTier;

  String? _customTierLabel;
  String? get customTierLabel => _customTierLabel;

  double _currentWholesaleFactor = 1.0;
  double _currentCardFactor = 1.0;
  double _currentCustomFactor = 1.0;
  double get currentCustomFactor => _currentCustomFactor;

  void setPriceTier(
    PriceTier tier, {
    double? wholesaleFactor,
    double? cardFactor,
    double? customFactor,
    String? customLabel,
  }) {
    if (wholesaleFactor != null) _currentWholesaleFactor = wholesaleFactor;
    if (cardFactor != null) _currentCardFactor = cardFactor;
    if (customFactor != null) _currentCustomFactor = customFactor;
    if (customLabel != null) _customTierLabel = customLabel;
    if (tier != PriceTier.custom) _customTierLabel = null;
    _activeTier = tier;

    // Propagar a todos los ítems del carrito
    for (var item in _cart) {
      item.activeTier = _activeTier;
      item.wholesaleFactor = _currentWholesaleFactor;
      item.cardFactor = _currentCardFactor;
      item.customFactor = _currentCustomFactor;
      item.customTierLabel = _customTierLabel;
    }
    notifyListeners();
  }

  void resetPriceTier() => setPriceTier(PriceTier.base);

  int get pendingCount => _pendingSales.length;

  int? _activePendingSaleId;
  int? get activePendingSaleId => _activePendingSaleId;

  // Si el carrito actual proviene de recuperar un presupuesto
  int? _activeQuoteId;
  int? get activeQuoteId => _activeQuoteId;

  String? _recalledUserName;
  String? get recalledUserName => _recalledUserName;

  List<PaymentMethod> _paymentMethods = [];
  List<PaymentMethod> get paymentMethods => _paymentMethods;

  // ── Persistencia de Estado de Logística (UI) ──
  // Estos campos mantienen el estado del CheckoutDialog durante la misma venta
  bool _currentRequiresDispatch = false;
  bool get currentRequiresDispatch => _currentRequiresDispatch;

  String _currentFulfillmentStatus = 'pending';
  String get currentFulfillmentStatus => _currentFulfillmentStatus;

  void setCurrentLogistics(bool requires, String status) {
    _currentRequiresDispatch = requires;
    _currentFulfillmentStatus = status;
    notifyListeners();
  }

  PosProvider({
    required this.processSaleUseCase,
    required this.searchProductsUseCase,
    required this.repository,
    this.printerService,
  }) {
    loadPaymentMethods();
    _loadLastShippingCost();
  }

  Future<void> _loadLastShippingCost() async {
    final prefs = await SharedPreferences.getInstance();
    _shippingCost = 0.0; // Empieza en 0 cada sesión
    _lastUsedShippingCost = prefs.getDouble('last_shipping_cost') ?? 0.0;
    notifyListeners();
  }

  double _shippingCost = 0.0;
  double get shippingCost => _shippingCost;
  
  // Memoria del último flete para sugerirlo en la siguiente venta
  double _lastUsedShippingCost = 0.0;
  double get lastUsedShippingCost => _lastUsedShippingCost;

  void setShippingCost(double cost) async {
    _shippingCost = cost;
    if (cost > 0) {
      _lastUsedShippingCost = cost;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_shipping_cost', cost);
    }
    notifyListeners();
  }

  double get cartSubtotal {
    return _cart.fold(0.0, (total, item) => total + item.subtotal);
  }

  double get cartTotal {
    // Solo sumamos el flete al total general si la logística está activa y pendiente
    final bool applyShipping = _currentRequiresDispatch && _currentFulfillmentStatus == 'pending';
    return cartSubtotal + (applyShipping ? _shippingCost : 0.0);
  }

  // Garantiza que siempre tengamos un printerService, incluso si no se inyecta
  ReceiptPrinterService get _activePrinter =>
      printerService ?? ReceiptPrinterService.instance;

  bool requestAddToCart(Product product) {
    if (product.isSoldByWeight) {
      return false;
    }
    _addToCartDirectly(product, 1.0);
    return true;
  }

  void submitWeighedProduct(Product product, double weightInKg) {
    double finalWeight = weightInKg;
    if (finalWeight > 50) {
      finalWeight = finalWeight / 1000.0;
    }
    _addToCartDirectly(product, finalWeight);
  }

  void _addToCartDirectly(Product product, double quantity) {
    if (product.isSoldByWeight) {
      _cart.add(CartItem(
        product: product,
        quantity: quantity,
        activeTier: _activeTier,
        wholesaleFactor: _currentWholesaleFactor,
        cardFactor: _currentCardFactor,
      ));
    } else {
      final index = _cart.indexWhere(
        (item) => item.product.id == product.id && !item.product.isSoldByWeight,
      );
      if (index >= 0) {
        _cart[index].product = product; // Actualizar con el stock más reciente
        _cart[index].quantity += quantity;
      } else {
        _cart.add(CartItem(
          product: product,
          quantity: quantity,
          activeTier: _activeTier,
          wholesaleFactor: _currentWholesaleFactor,
          cardFactor: _currentCardFactor,
          customFactor: _currentCustomFactor,
          customTierLabel: _customTierLabel,
        ));
      }
    }
    notifyListeners();
  }

  void updateQuantity(CartItem cartItem, double newQuantity) {
    final index = _cart.indexOf(cartItem);
    if (index >= 0 && newQuantity > 0) {
      _cart[index].quantity = newQuantity;
      notifyListeners();
    }
  }

  void removeFromCart(CartItem cartItem) {
    _cart.remove(cartItem);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _activePendingSaleId = null;
    _activeQuoteId = null;
    _recalledUserName = null;
    _errorMessage = null;
    _isShiftClosed = false;
    // No reseteamos estas variables aquí porque la UI las necesita
    // inmediatamente después de la venta para mostrar el PDF Split.
    // _wasLastSaleDispatched = false;
    // _lastDeliveryNote = null;
    // Reseteamos el flete a 0.0 para que el carrito vacío muestre $0
    _shippingCost = 0.0;
    
    // Reseteamos el estado de logística para la próxima venta
    _currentRequiresDispatch = false;
    _currentFulfillmentStatus = 'pending';

    // Reset price tier a base al iniciar una nueva venta
    _activeTier = PriceTier.base;
    _customTierLabel = null;
    notifyListeners();
  }

  /// Carga un presupuesto en el carrito. Asume que Items ya vienen hidratados.
  void loadQuoteToCart(Quote quote) {
    clearCart();
    _activeQuoteId = quote.id;
    for (var item in quote.items) {
      if (item.product != null) {
        _cart.add(CartItem(product: item.product!, quantity: item.quantity));
      }
    }
    notifyListeners();
  }

  void clearRecall() {
    _activePendingSaleId = null;
    clearCart();
  }

  /// Restaura el carrito al estado de la última venta procesada.
  /// Usado por el flujo de anulación en la vista previa del comprobante.
  void restoreLastSaleCart() {
    _cart.clear();
    _cart.addAll(_lastSaleCart);
    _shippingCost = _lastSaleShippingCost ?? 0.0;
    notifyListeners();
  }

  void recallOrderToCart(Map<String, dynamic> sale) {
    clearCart();
    // Use un temporizador mínimo o asegure que se haya limpiado el carrito (ya es sincrónico).

    final saleId = (sale['id'] as num).toInt();
    final rawItems = (sale['items'] as List?) ?? [];

    final List<CartItem> recalledItems = rawItems.map<CartItem>((itemMap) {
      final prod = itemMap['product'] as Map<String, dynamic>? ?? {};
      final product = Product(
        id: (prod['id'] as num?)?.toInt() ?? 0,
        name: itemMap['product_name']?.toString() ??
            prod['name']?.toString() ??
            'Producto',
        internalCode: prod['internal_code']?.toString() ?? '',
        costPrice: 0,
        sellingPrice: double.tryParse(itemMap['unit_price'].toString()) ?? 0.0,
        stock: double.tryParse(prod['stock']?.toString() ?? '0') ?? 0.0,
        active: true,
        isSoldByWeight:
            prod['is_sold_by_weight'] == true || prod['is_sold_by_weight'] == 1,
      );
      return CartItem(
        product: product,
        quantity: double.tryParse(itemMap['quantity'].toString()) ?? 1.0,
      );
    }).toList();

    _cart.addAll(recalledItems);
    _activePendingSaleId = saleId;
    _shippingCost = double.tryParse(sale['shipping_cost']?.toString() ?? '0') ?? 0.0;
    _recalledUserName = sale['user']?['name']?.toString();
    
    // Al recuperar, mantenemos el despacho desactivado por defecto para que el cajero
    // lo active manualmente si corresponde, evitando cobros automáticos inesperados.
    _currentRequiresDispatch = false;
    _currentFulfillmentStatus = 'pending';
    
    notifyListeners();
  }

  Future<List<Product>> search(String query) async {
    try {
      return await searchProductsUseCase(query);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return [];
    }
  }

  Future<void> loadPaymentMethods() async {
    try {
      final list = await repository.fetchPaymentMethods();
      _paymentMethods = list.map((m) => PaymentMethod.fromJson(m)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading payment methods: $e');
    }
  }

  Future<bool> updatePaymentMethodSurcharge(int id, double newSurcharge) async {
    try {
      await repository.updatePaymentMethodSurcharge(id, newSurcharge);

      // Update local memory without refreshing the entire list to avoid UI flicker
      final idx = _paymentMethods.indexWhere((m) => m.id == id);
      if (idx != -1) {
        final old = _paymentMethods[idx];
        _paymentMethods[idx] = PaymentMethod(
          id: old.id,
          name: old.name,
          code: old.code,
          surchargeType: old.surchargeType,
          surchargeValue: newSurcharge,
          isCash: old.isCash,
          isActive: old.isActive,
          sortOrder: old.sortOrder,
        );
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('Error updating surcharge: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // FLUJO NORMAL: Cobrar directamente
  // ─────────────────────────────────────────────────────────────────
  Future<bool> processCheckout({
    required int shiftId,
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    required String printerFormat,
    required LocalTerminalProvider localTerminal,
    int? userId,
    int? customerId,
    String? userName,
    BusinessSettings? settings,
    bool showPreview = true,
    bool requiresDispatch = false,
    String fulfillmentStatus = 'pending',
    Map<String, dynamic>? checkDetails,
  }) async {
    if (_cart.isEmpty) return false;

    _isLoading = true;
    _errorMessage = null;
    _printerWarning = null;
    _wasLastSaleDispatched = false;
    _lastDeliveryNote = null;
    notifyListeners();

    final cartSnapshot = List<CartItem>.from(_cart);
    final totalSnapshot = cartTotal;
    // Solo aplicamos flete al comprobante si se requiere despacho y no es entrega inmediata
    final shippingCostSnapshot = (requiresDispatch && fulfillmentStatus == 'pending') ? _shippingCost : 0.0;

    try {
      String? extractedSaleId;

      if (_activePendingSaleId != null) {
        final success = await payPendingSale(
          saleId: _activePendingSaleId!,
          saleTotal: totalSnapshot,
          totalSurcharge: totalSurcharge,
          payments: payments,
          tenderedAmount: tenderedAmount,
          changeAmount: changeAmount,
          localTerminal: localTerminal,
          userName: userName,
          settings: settings,
          userId: userId,
          items: cartSnapshot,
          shippingCost: shippingCostSnapshot,
          checkDetails: checkDetails,
        );
        if (!success) {
          // El error se seteó dentro de payPendingSale
          return false;
        }
        extractedSaleId = _activePendingSaleId!.toString();
      } else {
        final result = await processSaleUseCase(
          total: totalSnapshot,
          totalSurcharge: totalSurcharge,
          payments: payments,
          tenderedAmount: tenderedAmount,
          changeAmount: changeAmount,
          shiftId: shiftId,
          items: cartSnapshot,
          userId: userId,
          customerId: customerId,
          quoteId: _activeQuoteId,
          status: 'completed',
          shippingCost: (requiresDispatch && fulfillmentStatus == 'pending') ? _shippingCost : 0.0,
          requiresDispatch: requiresDispatch,
          fulfillmentStatus: fulfillmentStatus,
          checkDetails: checkDetails,
        );

        // processSaleUseCase retorna entidad Sale
        extractedSaleId = result.id.toString();
        _lastDeliveryNote = result.deliveryNote;
      }

      // ── Lógica de Resolución de Pagos ──
      // Resolvemos los nombres de los métodos de pago para los comprobantes
      final resolvedPayments = (payments.map((p) {
        final id = (p['payment_method_id'] as num?)?.toInt();
        final method = _paymentMethods.firstWhere(
          (m) => m.id == id,
          orElse: () => PaymentMethod(
            id: id ?? 0,
            name: p['method_name']?.toString() ?? 'PAGO',
            code: '',
            surchargeType: 'none',
            surchargeValue: 0,
            isCash: false,
            isActive: true,
            sortOrder: 0,
          ),
        );
        final amount = (p['total_amount'] as num?)?.toDouble() ??
            (p['base_amount'] as num?)?.toDouble() ??
            0.0;

        return {
          'name': method.name, // Para la impresora térmica (pd['name'])
          'payment_method': {
            'name': method.name
          }, // Para el PDF A4 (p['payment_method']['name'])
          'amount': amount,
          '_isCash': method.isCash,
        };
      }).toList()
        ..sort((a, b) {
          final aCash = (a['_isCash'] as bool?) ?? false;
          final bCash = (b['_isCash'] as bool?) ?? false;
          if (aCash == bCash) return 0;
          return aCash ? -1 : 1; // efectivo primero
        }));

      _lastSaleId = int.tryParse(extractedSaleId);
      _lastSaleTotal = totalSnapshot;
      _lastSaleShippingCost = shippingCostSnapshot;
      _lastTenderedAmount = tenderedAmount;
      _lastChangeAmount = changeAmount;
      _lastSurchargeAmount = totalSurcharge;
      _lastSalePayments =
          resolvedPayments; // Guardamos la versión resuelta con nombres
      _wasLastSaleDispatched = requiresDispatch;

      // Guardar snapshot del carrito ANTES de limpiarlo (lo necesita el dialog de Remito)
      _lastSaleCart = List<CartItem>.from(_cart);
      clearCart();

      // ── Lógica de Impresión (A4 o Térmica) ──
      try {
        if (localTerminal.printerFormat.startsWith('a4')) {
          final isDeliveredNow = fulfillmentStatus == 'delivered';
          
          // Si se entrega AHORA y es un formato A4, pos_screen intercepta para armar el PDF combinado.
          // De lo contrario, usamos nuestro propio generador local de A4 para la venta simple.
          final isA4FormatForDispatch = localTerminal.printerFormat == 'a4_split' || localTerminal.printerFormat == 'a4_normal' || localTerminal.printerFormat == 'a4';
          
          if (!(requiresDispatch && isDeliveredNow) || !isA4FormatForDispatch) {
            final businessSettings = settings ?? const BusinessSettings();
            
            // Si requiere despacho pero NO es entrega inmediata, generamos el A4 normal de venta
            // pero el remito se generará después desde Logística.
            final pdfBytes = await A4SplitPdfService.generateA4SingleReceipt(
              sale: {
                'id': extractedSaleId,
                'items': cartSnapshot.map((i) => {
                  'product_name': i.product.name,
                  'quantity': i.quantity,
                  'unit_price': i.unitPrice,
                  'subtotal': i.subtotal,
                  'product': {
                    'is_sold_by_weight': i.product.isSoldByWeight,
                  }
                }).toList(),
                'total': totalSnapshot,
                'shipping_cost': shippingCostSnapshot,
                'surcharge_amount': totalSurcharge,
                'tendered_amount': tenderedAmount,
                'change_amount': changeAmount,
                'payments': resolvedPayments,
                'customer': {'name': 'Consumidor Final'}, 
                'customer_name': 'Consumidor Final',
              },
              businessName: businessSettings.companyName ?? 'Mi Negocio',
              businessAddress: businessSettings.address,
              phone: businessSettings.phone ?? '',
              cuit: businessSettings.taxId ?? '',
              vendorName: userName,
              paperSize: localTerminal.pdfPaperSize,
            );

            final ctx = AppConfig.navigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              if (showPreview) {
                final result = await showDialog<String>(
                  context: ctx,
                  barrierDismissible: false,
                  builder: (dialogCtx) {
                    bool isVoiding = false;
                    return StatefulBuilder(
                      builder: (context, setState) {
                        return Dialog(
                          child: SizedBox(
                            width: 900,
                            height: 800,
                            child: Scaffold(
                              appBar: AppBar(
                                title: Text('Vista Previa - Venta #$extractedSaleId'),
                                automaticallyImplyLeading: false,
                                actions: [
                                  if (isVoiding)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                                        ),
                                      ),
                                    )
                                  else
                                    TextButton.icon(
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: dialogCtx,
                                          builder: (c) => AlertDialog(
                                            title: const Text('¿Anular Venta?'),
                                            content: const Text('Esta acción cancelará el cobro en el sistema y devolverá los productos al carrito.'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('NO, VOLVER')),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                                onPressed: () => Navigator.pop(c, true), 
                                                child: const Text('SÍ, ANULAR')
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          setState(() { isVoiding = true; });
                                          try {
                                            // 1. Anular en el servidor
                                            await voidPendingOrder(int.parse(extractedSaleId!));
                                            // 2. Restaurar carrito localmente
                                            _cart.clear();
                                            _cart.addAll(_lastSaleCart);
                                            _shippingCost = _lastSaleShippingCost ?? 0.0;
                                            notifyListeners();
                                            // 3. Salir de la vista previa indicando anulación
                                            if (dialogCtx.mounted) {
                                              SnackBarService.warning(dialogCtx, 'Venta anulada. Los productos han vuelto al carrito.');
                                              Navigator.pop(dialogCtx, 'annulled');
                                            }
                                          } catch (e) {
                                            if (dialogCtx.mounted) {
                                              SnackBarService.error(dialogCtx, 'Error al anular: $e');
                                            }
                                            setState(() { isVoiding = false; });
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                                      label: const Text('ANULAR COBRO Y VOLVER', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                    ),
                                  const SizedBox(width: 16),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: isVoiding ? null : () => Navigator.pop(dialogCtx),
                                  ),
                                ],
                              ),
                              body: PdfPreview(
                                build: (format) async => pdfBytes,
                                canChangePageFormat: false,
                                canChangeOrientation: false,
                                pdfFileName: 'Comprobante_$extractedSaleId.pdf',
                                canDebug: false,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );


                if (result == 'annulled') {
                  _errorMessage = 'ANNULLED';
                  return false;
                }
              } else {
                await Printing.layoutPdf(
                  onLayout: (_) async => pdfBytes,
                  name: 'Comprobante_$extractedSaleId',
                );
              }
            }
          }
        } else {
          // Ruta Térmica: leer hardware 100% del LocalTerminalProvider
          if (requiresDispatch && _lastDeliveryNote != null) {
            // SPLIT TICKET: Venta + Orden de Retiro en el mismo rollo
            await _activePrinter.printSplitTicket(
              items: cartSnapshot,
              total: totalSnapshot,
              shippingCost: shippingCostSnapshot,
              settings: settings ?? const BusinessSettings(),
              localTerminal: localTerminal,
              deliveryNote: _lastDeliveryNote!,
              paymentDetails: resolvedPayments,
              receiptNumber: extractedSaleId,
              deliveryNoteNumber: _lastDeliveryNote!['id']?.toString(),
              userName: _recalledUserName ?? userName,
              cashierName: userName,
              surchargeAmount: totalSurcharge,
              tenderedAmount: tenderedAmount,
              changeAmount: changeAmount,
              customerName: _lastDeliveryNote!['sale']?['customer']?['name']
                      ?.toString() ??
                  _lastDeliveryNote!['sale']?['customer_name']?.toString(),
              paperSizeOverride:
                  localTerminal.printerFormat == 'thermal_58' ? '58mm' : '80mm',
            );
          } else {
            await _activePrinter.printSaleTicket(
              items: cartSnapshot,
              total: totalSnapshot,
              settings: settings ?? const BusinessSettings(),
              localTerminal: localTerminal,
              paperSizeOverride:
                  localTerminal.printerFormat == 'thermal_58' ? '58mm' : '80mm',
              paymentDetails: resolvedPayments,
              receiptNumber: extractedSaleId,
              userName: _recalledUserName ?? userName,
              cashierName: userName,
              surchargeAmount: totalSurcharge,
              tenderedAmount: tenderedAmount,
              changeAmount: changeAmount,
              shippingCost: shippingCostSnapshot,
            );
          }
        }
      } catch (e) {
        _printerWarning =
            'Venta exitosa, pero la impresora no responde: ${e.toString()}';
        debugPrint('=== Printer Error: $e ===');
      }

      // ── El Remito de Logística (Fricción Cero) ──
      // El backend PosController ya se encargó de crearlo atómicamente y retornarlo.
      // Si el backend no pudo crearlo o hubo un problema, ya lo capturaremos.
      // Ya extrajimos _lastDeliveryNote de la respuesta al inicio de esta función.

      return true;
    } on ClosedShiftException catch (e) {
      _isShiftClosed = true;
      _errorMessage = e.message;
      return false;
    } on SessionExpiredException catch (e) {
      // Sesión única: otro dispositivo inició sesión con este usuario.
      // Guardamos el mensaje con la key SESSION_EXPIRED para que la UI lo detecte.
      _errorMessage = 'SESSION_EXPIRED: ${e.message}';
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // FLUJO PREVENTA: Dejar en espera
  // ─────────────────────────────────────────────────────────────────
  Future<bool> holdOrder({
    required int shiftId,
    int? userId,
  }) async {
    if (_cart.isEmpty) return false;
    // Guard contra doble-click: solo permite un holdOrder a la vez
    if (_isHoldingOrder || _isLoading) return false;

    _isHoldingOrder = true;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Snapshot inmutable del carrito ANTES del await
    final cartSnapshot = List<CartItem>.from(_cart);
    final totalSnapshot = cartTotal;

    try {
      await processSaleUseCase(
        total: totalSnapshot,
        totalSurcharge: 0,
        payments: [], // Dummy para ordenes pending, se ingora en el form request de laravel por el exclude_if
        shiftId: shiftId,
        items: cartSnapshot,
        userId: userId,
        status: 'pending',
        shippingCost: (_currentRequiresDispatch && _currentFulfillmentStatus == 'pending') ? _shippingCost : 0.0,
      );

      clearCart();
      await loadPendingSales();
      return true;
    } on ClosedShiftException catch (e) {
      _isShiftClosed = true;
      _errorMessage = e.message;
      return false;
    } on SessionExpiredException catch (e) {
      _errorMessage = 'SESSION_EXPIRED: ${e.message}';
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isHoldingOrder = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Cargar lista de pendientes desde el backend
  // ─────────────────────────────────────────────────────────────────
  Future<void> loadPendingSales() async {
    _isPendingLoading = true;
    notifyListeners();
    try {
      _pendingSales = await repository.fetchPendingSales();
    } catch (e) {
      debugPrint('=== Error cargando pendientes: $e ===');
    } finally {
      _isPendingLoading = false;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Anular una orden pendiente (eliminarla y devolver stock)
  // ─────────────────────────────────────────────────────────────────
  Future<bool> voidPendingOrder(int saleId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await repository.voidPendingSale(saleId);

      if (_activePendingSaleId == saleId) {
        clearRecall();
      }

      await loadPendingSales();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Cobrar una orden pendiente
  // ─────────────────────────────────────────────────────────────────
  Future<bool> payPendingSale({
    required int saleId,
    required double saleTotal,
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    required LocalTerminalProvider localTerminal,
    String? userName,
    BusinessSettings? settings,
    int? userId,
    List<CartItem>? items,
    bool showPreview = true,
    double shippingCost = 0.0,
    Map<String, dynamic>? checkDetails,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _printerWarning = null;
    notifyListeners();

    try {
      await repository.payPendingSale(
        saleId: saleId,
        totalSurcharge: totalSurcharge,
        payments: payments,
        tenderedAmount: tenderedAmount,
        changeAmount: changeAmount,
        userId: userId,
        items: items,
        shippingCost: shippingCost,
        checkDetails: checkDetails,
      );

      // Imprimir ticket si hay impresora configurada.
      // (Si items != null, significa que venimos desde processCheckout, que YA imprime el ticket)
      if (printerService != null && settings != null && items == null) {
        final safeSettings =
            settings; // non-nullable alias for Dart type promotion
        // Reconstruir CartItems desde el mapa en memoria para el ticket
        final pendingEntry = _pendingSales.firstWhere(
          (s) => s['id'] == saleId,
          orElse: () => <String, dynamic>{},
        );
        final rawItems = (pendingEntry['items'] as List?) ?? [];
        final ticketItems = rawItems.map<CartItem>((itemMap) {
          final prod = itemMap['product'] as Map<String, dynamic>? ?? {};
          final product = Product(
            id: (prod['id'] as num?)?.toInt() ?? 0,
            name: itemMap['product_name']?.toString() ??
                prod['name']?.toString() ??
                'Producto',
            internalCode: '',
            costPrice: 0,
            sellingPrice:
                double.tryParse(itemMap['unit_price'].toString()) ?? 0.0,
            stock: 0,
            active: true,
            isSoldByWeight: prod['is_sold_by_weight'] == true ||
                prod['is_sold_by_weight'] == 1,
          );
          return CartItem(
            product: product,
            quantity: double.tryParse(itemMap['quantity'].toString()) ?? 1.0,
          );
        }).toList();

        if (ticketItems.isNotEmpty) {
          try {
            // Resolver nombres y ordenar: efectivo primero
            final resolvedPayments = (payments.map((p) {
              final id = (p['payment_method_id'] as num?)?.toInt();
              final method = _paymentMethods.firstWhere(
                (m) => m.id == id,
                orElse: () => PaymentMethod(
                  id: id ?? 0,
                  name: p['method_name']?.toString() ?? 'PAGO',
                  code: '',
                  surchargeType: 'none',
                  surchargeValue: 0,
                  isCash: false,
                  isActive: true,
                  sortOrder: 0,
                ),
              );
              final amount = (p['base_amount'] as num?)?.toDouble() ??
                  (p['total_amount'] as num?)?.toDouble() ??
                  0.0;
              return {
                'name': method.name,
                'amount': amount,
                '_isCash': method.isCash
              };
            }).toList()
                  ..sort((a, b) {
                    final aCash = (a['_isCash'] as bool?) ?? false;
                    final bCash = (b['_isCash'] as bool?) ?? false;
                    if (aCash == bCash) return 0;
                    return aCash ? -1 : 1;
                  }))
                .map((p) => {'name': p['name'], 'amount': p['amount']})
                .toList();

            if (localTerminal.printerFormat.startsWith('a4')) {
              final pdfBytes = await repository.downloadTicketPdf(saleId);
              final ctx = AppConfig.navigatorKey.currentContext;
              if (ctx != null && ctx.mounted) {
                if (showPreview) {
                  await showDialog(
                    context: ctx,
                    builder: (context) => Dialog(
                      child: SizedBox(
                        width: 800,
                        height: 600,
                        child: PdfPreview(
                          build: (format) async => pdfBytes,
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          pdfFileName: 'Comprobante_$saleId.pdf',
                        ),
                      ),
                    ),
                  );
                } else {
                  await Printing.layoutPdf(
                    onLayout: (_) async => pdfBytes,
                    name: 'Comprobante_$saleId',
                  );
                }
              }
            } else {
              await printerService!.printSaleTicket(
                items: ticketItems,
                total: saleTotal,
                settings: safeSettings,
                localTerminal: localTerminal,
                paymentDetails: resolvedPayments,
                userName: pendingEntry['user']?['name'] as String? ?? userName,
                cashierName: userName,
                surchargeAmount: totalSurcharge,
                tenderedAmount: tenderedAmount,
                changeAmount: changeAmount,
              );
            }
          } catch (e) {
            _printerWarning =
                'Cobro exitoso, pero la impresora no responde: ${e.toString()}';
            debugPrint('=== Printer Error (pending): $e ===');
          }
        }
      }

      await loadPendingSales();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
