import 'package:flutter/material.dart';
import '../../data/quote_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

/// Ítem del carrito de presupuesto (wrapper local, sin afectar PosProvider).
class QuoteCartItem {
  final Product product;
  double quantity;
  double unitPrice; // precio seleccionado (venta, mayorista, tarjeta)

  QuoteCartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });

  double get subtotal => unitPrice * quantity;
}

class QuoteProvider extends ChangeNotifier {
  final QuoteRepository repository;

  QuoteProvider({required this.repository});

  // ── Carrito ──────────────────────────────────────────────────────────────
  final List<QuoteCartItem> _cart = [];
  List<QuoteCartItem> get cart => List.unmodifiable(_cart);

  double get cartTotal => _cart.fold(0, (s, i) => s + i.subtotal);

  void addToCart(Product product, {double quantity = 1, double? overridePrice}) {
    final price = overridePrice ?? product.sellingPrice;
    final idx = _cart.indexWhere((i) => i.product.id == product.id && i.unitPrice == price);
    if (idx >= 0) {
      _cart[idx].quantity += quantity;
    } else {
      _cart.add(QuoteCartItem(product: product, quantity: quantity, unitPrice: price));
    }
    notifyListeners();
  }

  void removeFromCart(QuoteCartItem item) {
    _cart.remove(item);
    notifyListeners();
  }

  void updateQuantity(QuoteCartItem item, double qty) {
    if (qty <= 0) {
      _cart.remove(item);
    } else {
      item.quantity = qty;
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  // ── Estado de pantalla ────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _errorMessage;
  Quote? _lastCreatedQuote;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Quote? get lastCreatedQuote => _lastCreatedQuote;

  // ── Historial (lista rápida) ──────────────────────────────────────────────
  List<Quote> _quotes = [];
  List<Quote> get quotes => List.unmodifiable(_quotes);

  // ── Acciones ──────────────────────────────────────────────────────────────

  /// Genera el presupuesto y lo guarda en el backend.
  /// NUNCA modifica stock.
  Future<Quote?> generateQuote({
    String? customerName,
    String? customerPhone,
    String? notes,
    String? validUntil,
    int? userId,
  }) async {
    if (_cart.isEmpty) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final items = _cart.map((c) => QuoteItem(
        productId: c.product.id,
        productName: c.product.name,
        unitPrice: c.unitPrice,
        quantity: c.quantity,
        subtotal: c.subtotal,
      )).toList();

      final quote = await repository.createQuote(
        items: items,
        customerName: customerName,
        customerPhone: customerPhone,
        notes: notes,
        validUntil: validUntil,
        userId: userId,
      );

      _lastCreatedQuote = quote;
      _cart.clear();
      return quote;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadQuotes({String? search, String? status}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _quotes = await repository.listQuotes(search: search, status: status);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
