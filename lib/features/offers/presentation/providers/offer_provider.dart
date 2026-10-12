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
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _activeOffers = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAllOffers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _allOffers = await repository.getAllOffers();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Busca si un producto tiene una oferta activa hoy.
  OfferModel? getActiveOfferForProduct(int productId) {
    for (final offer in _activeOffers) {
      final hasProduct = offer.products.any((p) => p['id'] == productId);
      if (hasProduct) return offer;
    }
    return null;
  }

  /// Retorna el precio unitario con oferta si aplica hoy, o null si no hay oferta.
  double? getDiscountedPrice(Product product) {
    final offer = getActiveOfferForProduct(product.id);
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
