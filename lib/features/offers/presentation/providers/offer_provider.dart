import 'package:flutter/material.dart';
import '../../data/models/offer_model.dart';
import '../../data/offer_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

class OfferProvider with ChangeNotifier {
  final OfferRepository repository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<OfferModel> _activeOffers = [];
  List<OfferModel> get activeOffers => _activeOffers;

  List<OfferModel> _allOffers = [];
  List<OfferModel> get allOffers => _allOffers;

  OfferProvider({required this.repository});

  Future<void> loadActiveOffers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _activeOffers = await repository.getActiveOffers();
    } catch (e) {
      // Reintento único ante micro-cortes o congestión de sockets al volver al POS
      try {
        await Future.delayed(const Duration(milliseconds: 600));
        _activeOffers = await repository.getActiveOffers();
      } catch (retryError) {
        _errorMessage = retryError.toString().replaceAll('Exception: ', '');
        // IMPORTANTE: No vaciar _activeOffers en caso de error de red transitorio
        // para no borrar el contador de ofertas ni desaplicar promociones del carrito.
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAllOffers({String? status, String? search}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _allOffers = await repository.getAllOffers(status: status, search: search);
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  static int? _extractProductId(dynamic p) {
    if (p is! Map) return null;
    final raw = p['id'] ?? p['product_id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw != null) return int.tryParse(raw.toString());
    return null;
  }

  /// Busca si un producto tiene una oferta activa hoy.
  /// Si hay múltiples ofertas para el mismo producto, retorna la que otorgue el menor precio (mayor descuento).
  /// [basePrice] es el precio base de venta del producto (sellingPrice) para calcular el descuento real.
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) {
    OfferModel? bestOffer;
    double? bestPrice;

    for (final offer in _activeOffers) {
      final hasProduct = offer.products.any((p) => _extractProductId(p) == productId);
      if (hasProduct) {
        // Obtener el precio base del producto si no se proporcionó
        double? currentBasePrice = basePrice;
        if (currentBasePrice == null) {
          final productData = offer.products.firstWhere(
            (p) => _extractProductId(p) == productId,
            orElse: () => {},
          );
          // Laravel devuelve selling_price como String debido al cast decimal:2
          currentBasePrice = double.tryParse(productData['selling_price']?.toString() ?? '');
        }

        if (currentBasePrice != null && currentBasePrice > 0) {
          final discountedPrice = offer.calculateDiscountedPrice(currentBasePrice, productId: productId);
          if (bestPrice == null || discountedPrice < bestPrice) {
            bestPrice = discountedPrice;
            bestOffer = offer;
          }
        }
      }
    }
    return bestOffer;
  }

  /// Retorna el precio unitario con oferta si aplica hoy, o null si no hay oferta.
  double? getDiscountedPrice(Product product) {
    final offer = getActiveOfferForProduct(product.id, basePrice: product.sellingPrice);
    if (offer != null) {
      return offer.calculateDiscountedPrice(product.sellingPrice, productId: product.id);
    }
    return null;
  }

  Future<bool> createQuickOffer({
    required String name,
    String? description,
    required String type,
    double? discountPercentage,
    double? discountAmount,
    required String periodType, // 'daily', 'weekly', 'monthly'
    List<String>? daysOfWeek,
    required List<int> productIds,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final productsPayload = productIds.map((id) => {'product_id': id}).toList();
      final newOffer = await repository.createOffer(
        name: name,
        description: description,
        type: type,
        discountPercentage: discountPercentage,
        discountAmount: discountAmount,
        periodType: periodType,
        daysOfWeek: daysOfWeek,
        products: productsPayload,
      );

      // Agregar a activas de inmediato
      _activeOffers.insert(0, newOffer);
      _allOffers.insert(0, newOffer);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateOffer({
    required int id,
    required String name,
    String? description,
    required String type,
    double? discountPercentage,
    double? discountAmount,
    required String periodType,
    List<String>? daysOfWeek,
    required List<int> productIds,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final productsPayload = productIds.map((id) => {'product_id': id}).toList();
      final updated = await repository.updateOffer(
        id: id,
        name: name,
        description: description,
        type: type,
        discountPercentage: discountPercentage,
        discountAmount: discountAmount,
        periodType: periodType,
        daysOfWeek: daysOfWeek,
        products: productsPayload,
      );

      final activeIdx = _activeOffers.indexWhere((o) => o.id == id);
      if (activeIdx >= 0) {
        _activeOffers[activeIdx] = updated;
      } else {
        _activeOffers.insert(0, updated);
      }

      final allIdx = _allOffers.indexWhere((o) => o.id == id);
      if (allIdx >= 0) {
        _allOffers[allIdx] = updated;
      }

      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> relaunchOffer({
    required int id,
    required String periodType,
    DateTime? startDate,
    DateTime? endDate,
    bool duplicate = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await repository.relaunchOffer(
        id: id,
        periodType: periodType,
        startDate: startDate,
        endDate: endDate,
        duplicate: duplicate,
      );

      final OfferModel launched = result['offer'] as OfferModel;

      // Actualizar activas si corresponde
      if (launched.isCurrentlyActive) {
        final activeIdx = _activeOffers.indexWhere((o) => o.id == launched.id);
        if (activeIdx >= 0) {
          _activeOffers[activeIdx] = launched;
        } else {
          _activeOffers.insert(0, launched);
        }
      }

      // Actualizar lista histórica
      final histIdx = _allOffers.indexWhere((o) => o.id == launched.id);
      if (histIdx >= 0) {
        _allOffers[histIdx] = launched;
      } else {
        _allOffers.insert(0, launched);
      }

      return result;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> toggleOfferStatus(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updated = await repository.toggleOfferStatus(id);

      final activeIdx = _activeOffers.indexWhere((o) => o.id == id);
      if (updated.isCurrentlyActive) {
        if (activeIdx >= 0) {
          _activeOffers[activeIdx] = updated;
        } else {
          _activeOffers.insert(0, updated);
        }
      } else {
        if (activeIdx >= 0) {
          _activeOffers.removeAt(activeIdx);
        }
      }

      final allIdx = _allOffers.indexWhere((o) => o.id == id);
      if (allIdx >= 0) {
        _allOffers[allIdx] = updated;
      }

      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteOffer(int id) async {
    try {
      await repository.deleteOffer(id);
      _activeOffers.removeWhere((o) => o.id == id);
      _allOffers.removeWhere((o) => o.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}
