import 'package:flutter/material.dart';
import '../../data/quote_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';

/// QuoteProvider reutiliza el motor de precios CartItem del POS (Principio DRY).
/// Todos los cálculos de precio (override fijo / % global / listas custom)
/// ocurren dentro de CartItem.unitPrice, idéntico a la pantalla de ventas.
class QuoteProvider extends ChangeNotifier {
  final QuoteRepository repository;

  QuoteProvider({required this.repository});

  // ── Carrito con motor híbrido ──────────────────────────────────────────────
  final List<CartItem> _cart = [];
  List<CartItem> get cart => List.unmodifiable(_cart);

  double get cartTotal => _cart.fold(0, (s, i) => s + i.subtotal);

  // ── Tier de precio activo (sincronizado con todo el carrito) ───────────────
  PriceTier _activeTier = PriceTier.base;
  PriceTier get activeTier => _activeTier;

  String? _customTierLabel;
  String? get customTierLabel => _customTierLabel;

  double _wholesaleFactor = 0.85; // Default -15%
  double _cardFactor = 1.15;      // Default +15%
  double _customFactor = 1.0;

  // Getters públicos para que la UI pueda leer los factores en preview
  double get wholesaleFactor => _wholesaleFactor;
  double get cardFactor => _cardFactor;
  double get customFactor => _customFactor;

  /// Inyecta externamente los factores globales desde SettingsProvider.
  /// Llamar una vez al abrir la pantalla de presupuestos.
  void setGlobalFactors({double? wholesale, double? card}) {
    _wholesaleFactor = wholesale ?? 0.85;
    _cardFactor = card ?? 1.15;
    // Actualizar items ya en el carrito
    _applyTierToCart();
    notifyListeners();
  }

  /// Cambia la lista de precios para TODO el carrito (mismo comportamiento que POS).
  void setPriceTier(
    PriceTier tier, {
    double? customFactor,
    String? customLabel,
  }) {
    _activeTier = tier;
    if (tier == PriceTier.custom && customFactor != null) {
      _customFactor = customFactor;
      _customTierLabel = customLabel;
    } else {
      if (tier != PriceTier.custom) {
        _customTierLabel = null;
        _customFactor = 1.0;
      }
    }
    _applyTierToCart();
    notifyListeners();
  }

  /// Aplica el tier activo a todos los items del carrito.
  void _applyTierToCart() {
    for (final item in _cart) {
      item.activeTier = _activeTier;
      item.wholesaleFactor = _wholesaleFactor;
      item.cardFactor = _cardFactor;
      item.customFactor = _customFactor;
      item.customTierLabel = _customTierLabel;
    }
  }

  /// Label de la lista activa para enviar al backend y mostrar en PDF.
  String get activePriceListKey {
    switch (_activeTier) {
      case PriceTier.wholesale: return 'wholesale';
      case PriceTier.card:      return 'card';
      case PriceTier.custom:    return _customTierLabel ?? 'custom';
      case PriceTier.base:      return 'base';
    }
  }

  /// Label legible del tier activo para mostrar en la UI.
  String get activePriceListLabel {
    switch (_activeTier) {
      case PriceTier.wholesale: return 'Mayorista';
      case PriceTier.card:      return 'Tarjeta';
      case PriceTier.custom:    return _customTierLabel ?? 'Custom';
      case PriceTier.base:      return 'Lista Base';
    }
  }

  Color get activePriceListColor {
    switch (_activeTier) {
      case PriceTier.wholesale: return const Color(0xFF3949AB); // indigo
      case PriceTier.card:      return const Color(0xFF00695C); // teal
      case PriceTier.custom:    return const Color(0xFF6A1B9A); // purple
      case PriceTier.base:      return const Color(0xFF2E7D32); // green
    }
  }

  void addToCart(Product product, {double quantity = 1}) {
    // Si ya existe el mismo producto con el mismo tier, sumar cantidad
    final existingIdx = _cart.indexWhere(
      (i) => i.product.id == product.id && i.activeTier == _activeTier,
    );

    if (existingIdx >= 0) {
      _cart[existingIdx].quantity += quantity;
    } else {
      _cart.add(CartItem(
        product: product,
        quantity: quantity,
        activeTier: _activeTier,
        wholesaleFactor: _wholesaleFactor,
        cardFactor: _cardFactor,
        customFactor: _customFactor,
        customTierLabel: _customTierLabel,
      ));
    }
    notifyListeners();
  }

  void removeFromCart(CartItem item) {
    _cart.remove(item);
    notifyListeners();
  }

  void updateQuantity(CartItem item, double qty) {
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
  /// El precio de cada item se calcula dinámicamente vía CartItem.unitPrice.
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
      // Serializar CartItem → QuoteItem usando precios calculados por el motor híbrido
      final items = _cart.map((c) => QuoteItem(
        productId: c.product.id,
        productName: c.product.name,
        unitPrice: c.unitPrice,    // Motor híbrido: override o % global
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
        priceList: activePriceListKey,  // ← guardamos la lista usada en BD
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
