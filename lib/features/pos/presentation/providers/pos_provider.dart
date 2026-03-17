import 'package:flutter/material.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/usecases/process_sale_usecase.dart';
import '../../domain/usecases/search_products_usecase.dart';
import '../../domain/repositories/pos_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';

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

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ── Órdenes Pendientes ──────────────────────────────────────────
  List<Map<String, dynamic>> _pendingSales = [];
  List<Map<String, dynamic>> get pendingSales => _pendingSales;

  bool _isPendingLoading = false;
  bool get isPendingLoading => _isPendingLoading;

  int get pendingCount => _pendingSales.length;

  int? _activePendingSaleId;
  int? get activePendingSaleId => _activePendingSaleId;

  PosProvider({
    required this.processSaleUseCase,
    required this.searchProductsUseCase,
    required this.repository,
    this.printerService,
  });

  double get cartTotal {
    return _cart.fold(0.0, (sum, item) => sum + item.subtotal);
  }

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
        internalCode: '',
        costPrice: 0,
        sellingPrice: double.tryParse(itemMap['unit_price'].toString()) ?? 0.0,
        stock: double.tryParse(prod['stock'].toString()) ?? 0.0,
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

  // ─────────────────────────────────────────────────────────────────
  // FLUJO NORMAL: Cobrar directamente
  // ─────────────────────────────────────────────────────────────────
  Future<bool> processCheckout({
    required int shiftId,
    required String paymentMethod,
    required double tenderedAmount,
    required double changeAmount,
    int? userId,
    String? userName,
    BusinessSettings? settings,
  }) async {
    if (_cart.isEmpty) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final cartSnapshot = List<CartItem>.from(_cart);
    final totalSnapshot = cartTotal;

    try {
      if (_activePendingSaleId != null) {
        final success = await payPendingSale(
          saleId: _activePendingSaleId!,
          saleTotal: totalSnapshot,
          paymentMethod: paymentMethod,
          tenderedAmount: tenderedAmount,
          changeAmount: changeAmount,
          userName: userName,
          settings: settings,
          items: cartSnapshot,
        );
        if (!success) {
          // El error se seteó dentro de payPendingSale
          return false;
        }
      } else {
        await processSaleUseCase(
          total: totalSnapshot,
          paymentMethod: paymentMethod,
          tenderedAmount: tenderedAmount,
          changeAmount: changeAmount,
          shiftId: shiftId,
          items: cartSnapshot,
          userId: userId,
          status: 'completed',
        );
      }

      clearCart();

      if (printerService != null && settings != null) {
        printerService!
            .printSaleTicket(
              items: cartSnapshot,
              total: totalSnapshot,
              settings: settings,
              paymentMethod: paymentMethod,
              userName: userName,
            )
            .catchError((e) => debugPrint('=== Printer Error: $e ==='));
      }

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
        paymentMethod: 'pending',
        shiftId: shiftId,
        items: cartSnapshot,
        userId: userId,
        status: 'pending',
      );

      clearCart();
      await loadPendingSales();
      return true;
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
  // Cobrar una orden pendiente
  // ─────────────────────────────────────────────────────────────────
  Future<bool> payPendingSale({
    required int saleId,
    required double saleTotal,
    required String paymentMethod,
    required double tenderedAmount,
    required double changeAmount,
    String? userName,
    BusinessSettings? settings,
    List<CartItem>? items,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await repository.payPendingSale(
        saleId: saleId,
        paymentMethod: paymentMethod,
        tenderedAmount: tenderedAmount,
        changeAmount: changeAmount,
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
          printerService!
              .printSaleTicket(
                items: ticketItems,
                total: saleTotal,
                settings: settings,
                paymentMethod: paymentMethod,
                userName: userName,
              )
              .catchError((e) => debugPrint('=== Printer Error (pending): $e ==='));
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
