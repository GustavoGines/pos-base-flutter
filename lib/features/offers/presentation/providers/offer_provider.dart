import 'package:flutter/material.dart';
import '../../data/models/offer_model.dart';
import '../../data/offer_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

class OfferProvider with ChangeNotifier {
  final OfferRepository repository;

  bool _isLoadingActive = false;
  bool get isLoadingActive => _isLoadingActive;

  bool _isLoadingHistory = false;
  bool get isLoadingHistory => _isLoadingHistory;

  bool _isLoading = false;
  bool get isLoading => _isLoading || _isLoadingActive || _isLoadingHistory;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<OfferModel> _activeOffers = [];
  List<OfferModel> get activeOffers => _activeOffers;

  List<OfferModel> _allOffers = [];
  List<OfferModel> get allOffers => _allOffers;

  String _lastStatusFilter = 'all';
  String _lastSearchQuery = '';

  OfferProvider({required this.repository});

  bool _matchesCurrentHistoryFilter(OfferModel offer) {
    if (_lastStatusFilter != 'all' && _lastStatusFilter.isNotEmpty) {
      switch (_lastStatusFilter) {
        case 'active':
          if (offer.status != OfferStatus.active) return false;
          break;
        case 'expired':
          if (offer.status != OfferStatus.expired) return false;
          break;
        case 'paused':
          if (offer.status != OfferStatus.paused) return false;
          break;
        case 'scheduled':
          if (offer.status != OfferStatus.scheduled) return false;
          break;
      }
    }

    if (_lastSearchQuery.isNotEmpty) {
      final q = _lastSearchQuery.toLowerCase();
      final matchesName = offer.name.toLowerCase().contains(q);
      final matchesDesc = (offer.description ?? '').toLowerCase().contains(q);
      final matchesProduct = offer.products.any((p) {
        final pName = (p['name'] ?? '').toString().toLowerCase();
        final pBarcode = (p['barcode'] ?? '').toString().toLowerCase();
        final pCode = (p['internal_code'] ?? '').toString().toLowerCase();
        return pName.contains(q) || pBarcode.contains(q) || pCode.contains(q);
      });
      if (!matchesName && !matchesDesc && !matchesProduct) {
        return false;
      }
    }

    return true;
  }

  void _syncOfferInHistoryList(OfferModel offer) {
    final idx = _allOffers.indexWhere((o) => o.id == offer.id);
    final matches = _matchesCurrentHistoryFilter(offer);
    if (matches) {
      if (idx >= 0) {
        _allOffers[idx] = offer;
      } else {
        _allOffers.insert(0, offer);
      }
    } else {
      if (idx >= 0) {
        _allOffers.removeAt(idx);
      }
    }
  }

  Future<void> loadActiveOffers() async {
    _isLoadingActive = true;
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
      _isLoadingActive = false;
      notifyListeners();
    }
  }

  Future<void> loadAllOffers({String? status, String? search}) async {
    if (status != null) {
      _lastStatusFilter = status;
    }
    if (search != null) {
      _lastSearchQuery = search.trim();
    }

    _isLoadingHistory = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _allOffers = await repository.getAllOffers(
        status: _lastStatusFilter,
        search: _lastSearchQuery,
      );
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoadingHistory = false;
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
      // Validar en tiempo real por si la terminal cruzó la medianoche sin recargar
      if (!offer.isCurrentlyActive) continue;

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
          if (discountedPrice > 0 && (bestPrice == null || discountedPrice < bestPrice)) {
            bestPrice = discountedPrice;
            bestOffer = offer;
          }
        }
      }
    }
    return bestOffer;
  }

  // ── OF-01: Productos en oferta fuera del bloque inicial del Acceso Rápido ──────────
  // El POS carga solo los primeros 500 productos (por ventas). Un producto en oferta con
  // pocas ventas puede quedar afuera y desaparecer del filtro "Ofertas". Aquí se guardan,
  // completos y en una lista aparte, para no alterar "Todos", categorías ni atajos Ctrl+N.
  List<Product> _offerOnlyProducts = [];
  List<Product> get offerOnlyProducts => _offerOnlyProducts;

  String? _offerOnlySignature;
  int _offerOnlyRequestSeq = 0;

  /// IDs de productos incluidos en ofertas vigentes en este momento (fecha + día de semana).
  Set<int> get currentlyActiveOfferProductIds {
    final ids = <int>{};
    for (final offer in _activeOffers) {
      if (!offer.isCurrentlyActive) continue;
      for (final p in offer.products) {
        final id = _extractProductId(p);
        if (id != null && id > 0) ids.add(id);
      }
    }
    return ids;
  }

  /// Trae del servidor los productos en oferta vigente que NO están en [loadedProductIds].
  /// Es idempotente: si el conjunto faltante no cambió, no vuelve a consultar (salvo [force]).
  Future<void> syncOfferOnlyProducts(Set<int> loadedProductIds, {bool force = false}) async {
    final missing = currentlyActiveOfferProductIds.difference(loadedProductIds).toList()..sort();
    final signature = missing.join(',');
    if (!force && signature == _offerOnlySignature) return;
    _offerOnlySignature = signature;
    final seq = ++_offerOnlyRequestSeq;

    if (missing.isEmpty) {
      if (_offerOnlyProducts.isNotEmpty) {
        _offerOnlyProducts = [];
        notifyListeners();
      }
      return;
    }

    try {
      final fetched = await repository.getProductsByIds(missing);
      if (seq != _offerOnlyRequestSeq) return; // Respuesta vieja: llegó otra sincronización después
      _offerOnlyProducts = fetched;
      notifyListeners();
    } catch (e) {
      // Error de red: se conserva la lista anterior. No se reintenta en cada frame; se vuelve a
      // intentar cuando cambie el conjunto faltante o al refrescar manualmente (force/invalidate).
      debugPrint('OF-01: no se pudieron traer productos en oferta fuera del catálogo: $e');
    }
  }

  /// Obliga a que la próxima [syncOfferOnlyProducts] vuelva a consultar (ej. botón Actualizar).
  void invalidateOfferOnlyProducts() {
    _offerOnlySignature = null;
  }

  /// Reemplaza la lista (ej. tras descontar stock en memoria al cobrar), sin consultar al servidor.
  void replaceOfferOnlyProducts(List<Product> products) {
    _offerOnlyProducts = products;
    notifyListeners();
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

      // Agregar a activas de inmediato si aplica para hoy
      if (newOffer.isCurrentlyActive) {
        _activeOffers.insert(0, newOffer);
      }
      _syncOfferInHistoryList(newOffer);
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

      _syncOfferInHistoryList(updated);

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
      final activeIdx = _activeOffers.indexWhere((o) => o.id == launched.id);
      if (launched.isCurrentlyActive) {
        if (activeIdx >= 0) {
          _activeOffers[activeIdx] = launched;
        } else {
          _activeOffers.insert(0, launched);
        }
      } else if (activeIdx >= 0) {
        _activeOffers.removeAt(activeIdx);
      }

      // Actualizar lista histórica respetando el filtro activo
      _syncOfferInHistoryList(launched);

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

      _syncOfferInHistoryList(updated);

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
