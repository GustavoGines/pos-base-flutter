import 'package:flutter/material.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/usecases/process_sale_usecase.dart';
import '../../domain/usecases/search_products_usecase.dart';
import '../../domain/repositories/pos_repository.dart';
import '../../data/datasources/pos_remote_datasource.dart' show ClosedShiftException;
import 'package:frontend_desktop/core/network/api_client.dart' show SessionExpiredException;
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';

class PosProvider with ChangeNotifier {
  final ProcessSaleUseCase processSaleUseCase;
  final SearchProductsUseCase searchProductsUseCase;
  final PosRepository repository;
  final ReceiptPrinterService? printerService;

  List<CartItem> _cart = [];
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

  bool _isPendingLoading = false;
  bool get isPendingLoading => _isPendingLoading;

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

  PosProvider({
    required this.processSaleUseCase,
    required this.searchProductsUseCase,
    required this.repository,
    this.printerService,
  }) {
    loadPaymentMethods();
  }

  double get cartTotal {
    return _cart.fold(0.0, (total, item) => total + item.subtotal);
  }

  // Garantiza que siempre tengamos un printerService, incluso si no se inyecta
  ReceiptPrinterService get _activePrinter => printerService ?? ReceiptPrinterService.instance;

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
      _cart.add(CartItem(product: product, quantity: quantity));
    } else {
      final index = _cart.indexWhere(
        (item) => item.product.id == product.id && !item.product.isSoldByWeight,
      );
      if (index >= 0) {
        _cart[index].quantity += quantity;
      } else {
        _cart.add(CartItem(product: product, quantity: quantity));
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

  void recallOrderToCart(Map<String, dynamic> sale) {
    clearCart();
    // Use un temporizador mínimo o asegure que se haya limpiado el carrito (ya es sincrónico).
    
    final saleId = (sale['id'] as num).toInt();
    final rawItems = (sale['items'] as List?) ?? [];
    
    final List<CartItem> recalledItems = rawItems.map<CartItem>((itemMap) {
      final prod = itemMap['product'] as Map<String, dynamic>? ?? {};
      final product = Product(
        id: (prod['id'] as num?)?.toInt() ?? 0,
        name: itemMap['product_name']?.toString() ?? prod['name']?.toString() ?? 'Producto',
        internalCode: prod['internal_code']?.toString() ?? '',
        costPrice: 0,
        sellingPrice: double.tryParse(itemMap['unit_price'].toString()) ?? 0.0,
        stock: double.tryParse(prod['stock']?.toString() ?? '0') ?? 0.0,
        active: true,
        isSoldByWeight: prod['is_sold_by_weight'] == true || prod['is_sold_by_weight'] == 1,
      );
      return CartItem(
        product: product,
        quantity: double.tryParse(itemMap['quantity'].toString()) ?? 1.0,
      );
    }).toList();

    _cart.addAll(recalledItems);
    _activePendingSaleId = saleId;
    _recalledUserName = sale['user']?['name'] as String?;
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
    int? userId,
    int? customerId,
    String? userName,
    BusinessSettings? settings,
  }) async {
    if (_cart.isEmpty) return false;

    _isLoading = true;
    _errorMessage = null;
    _printerWarning = null;
    notifyListeners();

    final cartSnapshot = List<CartItem>.from(_cart);
    final totalSnapshot = cartTotal;

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
          userName: userName,
          settings: settings,
          userId: userId,
          items: cartSnapshot,
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
        );

        // processSaleUseCase retorna entidad Sale
        extractedSaleId = result.id.toString();
      }

      clearCart();

      if (settings != null) {
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
                (p['total_amount'] as num?)?.toDouble() ?? 0.0;
            return {'name': method.name, 'amount': amount, '_isCash': method.isCash};
          }).toList()
            ..sort((a, b) {
              final aCash = (a['_isCash'] as bool?) ?? false;
              final bCash = (b['_isCash'] as bool?) ?? false;
              if (aCash == bCash) return 0;
              return aCash ? -1 : 1; // efectivo primero
            }))
              .map((p) => {'name': p['name'], 'amount': p['amount']})
              .toList();

          await _activePrinter.printSaleTicket(
            items: cartSnapshot,
            total: totalSnapshot,
            settings: settings,
            paymentDetails: resolvedPayments,
            receiptNumber: extractedSaleId,
            userName: _recalledUserName ?? userName,
            cashierName: userName,
            surchargeAmount: totalSurcharge,
            tenderedAmount: tenderedAmount,
            changeAmount: changeAmount,
          );
        } catch (e) {
          _printerWarning = 'Venta exitosa, pero la impresora no responde: ${e.toString()}';
          debugPrint('=== Printer Error: $e ===');
        }
      }

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
    String? userName,
    BusinessSettings? settings,
    int? userId,
    List<CartItem>? items,
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
      );

      // Imprimir ticket si hay impresora configurada. 
      // (Si items != null, significa que venimos desde processCheckout, que YA imprime el ticket)
      if (printerService != null && settings != null && items == null) {
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
            name: itemMap['product_name']?.toString() ?? prod['name']?.toString() ?? 'Producto',
            internalCode: '',
            costPrice: 0,
            sellingPrice: double.tryParse(itemMap['unit_price'].toString()) ?? 0.0,
            stock: 0,
            active: true,
            isSoldByWeight: prod['is_sold_by_weight'] == true || prod['is_sold_by_weight'] == 1,
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
                  (p['total_amount'] as num?)?.toDouble() ?? 0.0;
              return {'name': method.name, 'amount': amount, '_isCash': method.isCash};
            }).toList()
              ..sort((a, b) {
                final aCash = (a['_isCash'] as bool?) ?? false;
                final bCash = (b['_isCash'] as bool?) ?? false;
                if (aCash == bCash) return 0;
                return aCash ? -1 : 1;
              }))
                .map((p) => {'name': p['name'], 'amount': p['amount']})
                .toList();

            await printerService!.printSaleTicket(
              items: ticketItems,
              total: saleTotal,
              settings: settings,
              paymentDetails: resolvedPayments,
              userName: pendingEntry['user']?['name'] as String? ?? userName,
              cashierName: userName,
              surchargeAmount: totalSurcharge,
              tenderedAmount: tenderedAmount,
              changeAmount: changeAmount,
            );
          } catch (e) {
            _printerWarning = 'Cobro exitoso, pero la impresora no responde: ${e.toString()}';
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
