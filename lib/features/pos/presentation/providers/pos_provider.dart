import 'package:flutter/material.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/usecases/process_sale_usecase.dart';
import '../../domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';

class PosProvider with ChangeNotifier {
  final ProcessSaleUseCase processSaleUseCase;
  final SearchProductsUseCase searchProductsUseCase;

  List<CartItem> _cart = [];
  List<CartItem> get cart => _cart;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  PosProvider({
    required this.processSaleUseCase,
    required this.searchProductsUseCase,
  });

  double get cartTotal {
    return _cart.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  // Se añade al carrito. Si retorna un booleano falso,
  // indica a la UI que muestre un popup de balanza antes de integrarlo.
  bool requestAddToCart(Product product) {
    if (product.isSoldByWeight) {
      return false; // Indica a la UI que detenga el insert y pida el peso
    }
    
    // Si no es por peso
    _addToCartDirectly(product, 1.0);
    return true; // Se agregó correctamente por unidad
  }

  // Agrega al carrito directamente (usado internamente o luego del popup de peso)
  void submitWeighedProduct(Product product, double weightInKg) {
    // Sistema anti-errores: Si el usuario escribe 1500 (gramos) en vez de 1.5Kg,
    // es estadísticamente imposible que compre 1.5 toneladas de Harina.
    // Asumimos que sobrepasar los 50Kg significa que typeó en gramos y lo auto-convertimos.
    double finalWeight = weightInKg;
    if (finalWeight > 50) {
      finalWeight = finalWeight / 1000.0;
    }
    _addToCartDirectly(product, finalWeight);
  }

  void _addToCartDirectly(Product product, double quantity) {
    if (product.isSoldByWeight) {
      // Los productos pesados SIEMPRE entran como tickets separados
      _cart.add(CartItem(product: product, quantity: quantity));
    } else {
      // Chequear si el producto unitario ya existe en el carrito
      final index = _cart.indexWhere((item) => item.product.id == product.id && !item.product.isSoldByWeight);
      
      if (index >= 0) {
        // Incrementamos
        _cart[index].quantity += quantity;
      } else {
        // Nuevo item unitario
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

  Future<bool> checkout(CashRegisterShift currentShift, String paymentMethod) async {
    if (_cart.isEmpty) return false;
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await processSaleUseCase(
        total: cartTotal,
        paymentMethod: paymentMethod,
        shiftId: currentShift.id,
        items: _cart,
      );
      
      clearCart();
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
