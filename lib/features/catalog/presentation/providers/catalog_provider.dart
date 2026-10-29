import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/brand.dart';
import '../../domain/entities/rubro.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../../domain/usecases/get_products_usecase.dart';
import '../../data/models/product_model.dart';

class CatalogProvider with ChangeNotifier {
  final GetProductsUseCase getProductsUseCase;
  final CatalogRepository repository;

  List<Product> _products = [];
  List<Product> get products => _products;

  List<Category> _categories = [];
  List<Category> get categories => _categories;

  List<Brand> _brands = [];
  List<Brand> get brands => _brands;

  List<Rubro> _rubros = [];
  List<Rubro> get rubros => _rubros;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Product> _criticalAlerts = [];
  List<Product> get criticalAlerts => _criticalAlerts;

  Product? _lastCreatedProduct;
  Product? get lastCreatedProduct => _lastCreatedProduct;

  Product? _lastUpdatedProduct;
  Product? get lastUpdatedProduct => _lastUpdatedProduct;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ── Quick Access Dynamic Filter Cache ─────────────────────
  final Map<int, List<Product>> _categoryExtraProducts = {};
  final Set<int> _categoriesLoading = {};
  List<Product> _weightOnlyProducts = [];
  bool _weightLoading = false;
  // Bandera explícita de "ya sincronizado": una lista vacía es un resultado válido
  // (todos los pesables ya estaban en memoria) y no debe disparar otra consulta.
  bool _weightSynced = false;
  List<Product> _pinnedExtraProducts = [];
  bool _pinnedLoading = false;
  // IDs fijados ya consultados (existan o no en el servidor) para no reconsultar en cada build.
  final Set<int> _pinnedRequestedIds = {};
  bool _prefetchRunning = false;
  // Generación de caché: invalida respuestas en vuelo iniciadas antes de un refresco.
  int _quickAccessCacheGeneration = 0;

  List<Product> getCategoryExtraProducts(int categoryId) => _categoryExtraProducts[categoryId] ?? const [];
  List<Product> get weightOnlyProducts => _weightOnlyProducts;
  List<Product> get pinnedExtraProducts => _pinnedExtraProducts;

  /// La categoría ya tiene su catálogo completo disponible en memoria (sin red pendiente).
  /// Si el servidor informa `productsCount` y ya hay esa cantidad de activos cargados en
  /// los primeros 500, no hace falta consultar: se considera hidratada al instante.
  bool isCategoryHydrated(int categoryId) {
    if (_categoryExtraProducts.containsKey(categoryId)) return true;
    return _categoryFullyInMemory(categoryId);
  }

  bool get isWeightHydrated => _weightSynced;

  /// Los fijados que no están en memoria ya fueron consultados al servidor.
  bool isPinnedHydrated(Set<int> pinnedIds) {
    final loadedIds = _products.map((p) => p.id).toSet();
    return pinnedIds.every((id) => loadedIds.contains(id) || _pinnedRequestedIds.contains(id));
  }

  bool _categoryFullyInMemory(int categoryId) {
    int? expected;
    for (final c in _categories) {
      if (c.id == categoryId) {
        expected = c.productsCount;
        break;
      }
    }
    // Backend v1.8.5 no envía products_count: sin dato no se puede asumir completitud.
    if (expected == null) return false;
    final localActive = _products.where((p) => p.active && p.category?.id == categoryId).length;
    return localActive >= expected;
  }

  /// Limpia las cachés adicionales del Acceso Rápido al recargar o refrescar el catálogo
  void invalidateQuickAccessExtraCaches() {
    _quickAccessCacheGeneration++;
    _categoryExtraProducts.clear();
    _categoriesLoading.clear();
    _weightOnlyProducts = [];
    _weightLoading = false;
    _weightSynced = false;
    _pinnedExtraProducts = [];
    _pinnedLoading = false;
    _pinnedRequestedIds.clear();
    _prefetchRunning = false;
  }

  /// Precarga en segundo plano (secuencial, una petición a la vez) las categorías indicadas
  /// para que al tocarlas el Acceso Rápido muestre todos sus productos al instante.
  Future<void> prefetchCategories(List<int> categoryIds) async {
    if (_prefetchRunning || categoryIds.isEmpty) return;
    _prefetchRunning = true;
    final generation = _quickAccessCacheGeneration;
    try {
      for (final id in categoryIds) {
        if (generation != _quickAccessCacheGeneration) return;
        if (isCategoryHydrated(id) || _categoriesLoading.contains(id)) continue;
        await syncCategoryProducts(id);
      }
    } finally {
      if (generation == _quickAccessCacheGeneration) _prefetchRunning = false;
    }
  }

  // ── Pagination State ─────────────────────────────────────
  int _currentPage = 1;
  int _lastPage = 1;
  int get currentPage => _currentPage;
  int get lastPage => _lastPage;
  bool get hasNextPage => _currentPage < _lastPage;
  bool get hasPrevPage => _currentPage > 1;

  // ── Search ───────────────────────────────────────────────
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  void clearSearch() {
    _searchQuery = '';
  }

  // ── Sort ─────────────────────────────────────────────────
  String _sortBy = 'name';
  String _sortDirection = 'asc';
  String get sortBy => _sortBy;
  String get sortDirection => _sortDirection;

  /// Versión de ordenamiento del catálogo para proteger el Acceso Rápido POS del "Efecto Baile".
  /// Solo aumenta al recargar productos desde el servidor (inicio de turno / refresco explícito),
  /// pero NO al actualizar contadores o stock en caliente tras cobrar una venta.
  int _catalogOrderVersion = 0;
  int get catalogOrderVersion => _catalogOrderVersion;

  void bumpCatalogOrderVersion() {
    _catalogOrderVersion++;
    notifyListeners();
  }

  CatalogProvider({required this.getProductsUseCase, required this.repository});

  Future<void> loadMetadata({bool force = false}) async {
    try {
      if (_categories.isEmpty || force) _categories = await repository.getCategories();
      if (_brands.isEmpty || force) _brands = await repository.getBrands();
      if (_rubros.isEmpty || force) _rubros = await repository.getRubros();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading metadata: $e');
    }
  }

  /// [sortBy] = '' pide el orden por defecto del servidor (peso → más vendidos → nombre),
  /// que es el que usa el Acceso Rápido del POS.
  Future<void> loadProducts(
      {int page = 1,
      String? search,
      String? sortBy,
      String? sortDirection,
      int? perPage}) async {
    _isLoading = true;
    _errorMessage = null;
    if (search != null) _searchQuery = search;
    if (sortBy != null) _sortBy = sortBy;
    if (sortDirection != null) _sortDirection = sortDirection;
    notifyListeners();
    try {
      final result = await getProductsUseCase(
        page: page,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        sortBy: _sortBy.isNotEmpty ? _sortBy : null,
        sortDirection: _sortBy.isNotEmpty ? _sortDirection : null,
        perPage: perPage,
      );
      _products = List<Product>.from(result['data'] as List);
      _currentPage = result['current_page'] as int;
      _lastPage = result['last_page'] as int;
      _catalogOrderVersion++;
      if (page == 1) {
        invalidateQuickAccessExtraCaches();
        if (_categories.isEmpty) {
          _categories = await repository.getCategories();
        }
        if (_brands.isEmpty) {
          _brands = await repository.getBrands();
        }
      }
    } catch (e, stack) {
      debugPrint('=== Error in loadProducts ===');
      debugPrint('Exception: $e');
      debugPrint('Stack: $stack');
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Recarga en segundo plano la página 1 del Acceso Rápido (orden del servidor: más
  /// vendidos → peso → nombre) SIN activar `isLoading`, para no provocar parpadeo de la grilla.
  /// Si falla, conserva silenciosamente los datos actuales.
  Future<void> refreshQuickAccessSilently(
      {bool preserveVisualOrder = false}) async {
    try {
      final result = await getProductsUseCase(page: 1, perPage: 500);
      _searchQuery = '';
      _sortBy = '';
      _products = List<Product>.from(result['data'] as List);
      _currentPage = result['current_page'] as int;
      _lastPage = result['last_page'] as int;
      if (!preserveVisualOrder) {
        _catalogOrderVersion++;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('refreshQuickAccessSilently: fallo silencioso ($e)');
    }
  }

  Future<void> fetchCriticalAlerts() async {
    try {
      _criticalAlerts = await repository.fetchCriticalAlerts();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching critical alerts: $e');
    }
  }

  Future<void> nextPage() async {
    if (hasNextPage) await loadProducts(page: _currentPage + 1);
  }

  Future<void> prevPage() async {
    if (hasPrevPage) await loadProducts(page: _currentPage - 1);
  }

  /// Búsqueda dedicada para el picker de ingredientes de combos.
  /// NO toca el estado de paginación de la pantalla de catálogo.
  /// Trae hasta 500 productos del backend filtrando por [query].
  Future<List<Product>> searchProductsForCombo(String query) async {
    try {
      final result = await getProductsUseCase(
        page: 1,
        search: query.isNotEmpty ? query : null,
        sortBy: 'name',
        sortDirection: 'asc',
        perPage: 500,
      );
      return List<Product>.from(result['data'] as List);
    } catch (e) {
      debugPrint('Error en searchProductsForCombo: $e');
      return [];
    }
  }

  /// Búsqueda remota para pickers (p. ej. Ofertas Rápidas): consulta todo el catálogo en el
  /// servidor (nombre, código de barras o código interno) en lugar de filtrar solo la página
  /// cargada en memoria. NO modifica `products` ni el estado de paginación/orden.
  Future<List<Product>> searchProductsRemote(String query,
      {int perPage = 30}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final result = await getProductsUseCase(
        page: 1,
        search: q,
        sortBy: 'name',
        sortDirection: 'asc',
        perPage: perPage,
      );
      return List<Product>.from(result['data'] as List);
    } catch (e) {
      debugPrint('Error en searchProductsRemote: $e');
      return [];
    }
  }

  /// Obtiene todos los productos activos pertenecientes a una Categoría, Marca o Proveedor
  /// sin alterar el estado de paginación del catálogo principal.
  Future<List<Product>> fetchProductsByGroup({
    int? categoryId,
    int? brandId,
    int? supplierId,
  }) async {
    try {
      final List<Product> allGroupProducts = [];
      int page = 1;
      int lastPage = 1;

      do {
        final result = await getProductsUseCase(
          page: page,
          sortBy: 'name',
          sortDirection: 'asc',
          perPage: 500,
          categoryId: categoryId,
          brandId: brandId,
          supplierId: supplierId,
          active: true,
        );
        final pageData = List<Product>.from(result['data'] as List);
        allGroupProducts.addAll(pageData.where((p) => p.active));
        lastPage = (result['last_page'] as int?) ?? 1;
        page++;
      } while (page <= lastPage && page <= 5);

      return allGroupProducts;
    } catch (e) {
      debugPrint('Error en fetchProductsByGroup: $e');
      return [];
    }
  }

  /// Refuerzo Senior: Actualiza los contadores de ventas en memoria para que la UI
  /// se reordene al instante sin necesidad de una petición de red.
  ///
  /// Devuelve `true` si algún producto vendido NO estaba cargado en memoria (p. ej. se vendió
  /// desde el buscador y no está en la página 1). No se inserta desde el carrito porque esos
  /// objetos pueden estar incompletos (órdenes recuperadas sin imagen/código): quien llama
  /// debe hacer un `loadProducts(silent: true)` para traer el dato real del servidor.
  bool updateProductSalesCountLocally(Map<int, int> productSales) {
    bool changed = false;
    bool anyMissing = false;

    List<Product> bumpInList(List<Product> list, int productId, int delta) {
      final idx = list.indexWhere((p) => p.id == productId);
      if (idx == -1) return list;
      final copy = List<Product>.from(list);
      copy[idx] = copy[idx].copyWith(salesCount: copy[idx].salesCount + delta);
      return copy;
    }

    for (var entry in productSales.entries) {
      final index = _products.indexWhere((p) => p.id == entry.key);
      if (index != -1) {
        final current = _products[index];
        _products[index] = current.copyWith(
          salesCount: (current.salesCount) + entry.value,
        );
        changed = true;
      } else {
        anyMissing = true;
      }

      if (_categoryExtraProducts.isNotEmpty) {
        for (final key in _categoryExtraProducts.keys.toList()) {
          final orig = _categoryExtraProducts[key]!;
          final next = bumpInList(orig, entry.key, entry.value);
          if (!identical(orig, next)) {
            _categoryExtraProducts[key] = next;
            changed = true;
          }
        }
      }
      if (_weightOnlyProducts.isNotEmpty) {
        final next = bumpInList(_weightOnlyProducts, entry.key, entry.value);
        if (!identical(_weightOnlyProducts, next)) {
          _weightOnlyProducts = next;
          changed = true;
        }
      }
      if (_pinnedExtraProducts.isNotEmpty) {
        final next = bumpInList(_pinnedExtraProducts, entry.key, entry.value);
        if (!identical(_pinnedExtraProducts, next)) {
          _pinnedExtraProducts = next;
          changed = true;
        }
      }
    }
    if (changed) notifyListeners();
    return anyMissing;
  }

  /// Descuenta en memoria (0ms) el stock de los productos e ingredientes vendidos,
  /// devolviendo una función que también actualiza cualquier lista externa (ej. _searchResults).
  List<Product> deductStockLocallyForProductList(
    List<Product> sourceList,
    Map<int, double> consumedByIngredientOrProductId,
  ) {
    if (consumedByIngredientOrProductId.isEmpty) return sourceList;
    return sourceList.map((p) {
      if (p.isCombo && p.comboIngredients != null && p.comboIngredients!.isNotEmpty) {
        bool comboTouched = false;
        int? minCombos;
        final newIngs = p.comboIngredients!.map((ing) {
          final copy = Map<String, dynamic>.from(ing);
          final ingId = (copy['id'] as num?)?.toInt();
          final oldStock = (copy['stock'] as num?)?.toDouble() ?? 0.0;
          final consumed = ingId != null ? (consumedByIngredientOrProductId[ingId] ?? 0.0) : 0.0;
          final newStock = oldStock - consumed;
          if (consumed != 0.0) {
            copy['stock'] = newStock;
            comboTouched = true;
          }
          final reqQty = (copy['quantity'] as num?)?.toDouble() ?? 1.0;
          if (reqQty > 0) {
            final fit = newStock < 0 ? 0 : (newStock / reqQty).floor();
            if (minCombos == null || fit < minCombos!) {
              minCombos = fit;
            }
          }
          return copy;
        }).toList();

        if (comboTouched) {
          return p.copyWith(
            comboIngredients: newIngs,
            stock: (minCombos ?? 0).toDouble(),
          );
        }
        return p;
      } else if (consumedByIngredientOrProductId.containsKey(p.id)) {
        final consumed = consumedByIngredientOrProductId[p.id]!;
        return p.copyWith(stock: p.stock - consumed);
      }
      return p;
    }).toList();
  }

  void applyImmediateLocalStockDeduction(Map<int, double> consumedByProductId) {
    if (consumedByProductId.isEmpty) return;
    _products = deductStockLocallyForProductList(_products, consumedByProductId);

    if (_categoryExtraProducts.isNotEmpty) {
      for (final key in _categoryExtraProducts.keys.toList()) {
        _categoryExtraProducts[key] = deductStockLocallyForProductList(_categoryExtraProducts[key]!, consumedByProductId);
      }
    }
    if (_weightOnlyProducts.isNotEmpty) {
      _weightOnlyProducts = deductStockLocallyForProductList(_weightOnlyProducts, consumedByProductId);
    }
    if (_pinnedExtraProducts.isNotEmpty) {
      _pinnedExtraProducts = deductStockLocallyForProductList(_pinnedExtraProducts, consumedByProductId);
    }
    notifyListeners();
  }

  /// Trae del backend los productos de la categoría que NO estén presentes en `_products`.
  /// Idempotente y protegido contra peticiones concurrentes.
  Future<void> syncCategoryProducts(int categoryId) async {
    if (_categoriesLoading.contains(categoryId) || isCategoryHydrated(categoryId)) {
      return;
    }
    _categoriesLoading.add(categoryId);
    final generation = _quickAccessCacheGeneration;
    try {
      final List<Product> extras = [];
      final loadedIds = _products.map((p) => p.id).toSet();
      int page = 1;
      int lastPage = 1;

      do {
        final result = await getProductsUseCase(
          page: page,
          perPage: 500,
          categoryId: categoryId,
          active: true,
        );
        final pageData = List<Product>.from(result['data'] as List);
        for (final p in pageData) {
          if (p.active && !loadedIds.contains(p.id) && !extras.any((e) => e.id == p.id)) {
            extras.add(p);
          }
        }
        lastPage = (result['last_page'] as int?) ?? 1;
        page++;
      } while (page <= lastPage && page <= 5);

      if (generation != _quickAccessCacheGeneration) return; // respuesta vieja: descartar
      _categoryExtraProducts[categoryId] = extras;
    } catch (e) {
      debugPrint('Error en syncCategoryProducts($categoryId): $e');
      // Sin red: se muestra lo que hay en memoria (sin loader infinito). El botón
      // "Actualizar" invalida la caché y reintenta.
      if (generation == _quickAccessCacheGeneration) {
        _categoryExtraProducts[categoryId] = const [];
      }
    } finally {
      if (generation == _quickAccessCacheGeneration) {
        _categoriesLoading.remove(categoryId);
        notifyListeners();
      }
    }
  }

  /// Trae del backend los productos pesables que NO estén presentes en `_products`.
  Future<void> syncWeightProducts() async {
    if (_weightLoading || _weightSynced) return;
    _weightLoading = true;
    final generation = _quickAccessCacheGeneration;
    try {
      final List<Product> extras = [];
      final loadedIds = _products.map((p) => p.id).toSet();
      int page = 1;
      int lastPage = 1;

      do {
        final result = await getProductsUseCase(
          page: page,
          perPage: 500,
          isSoldByWeight: true,
          active: true,
        );
        final pageData = List<Product>.from(result['data'] as List);
        for (final p in pageData) {
          if (p.active && !loadedIds.contains(p.id) && !extras.any((e) => e.id == p.id)) {
            extras.add(p);
          }
        }
        lastPage = (result['last_page'] as int?) ?? 1;
        page++;
      } while (page <= lastPage && page <= 5);

      if (generation != _quickAccessCacheGeneration) return;
      _weightOnlyProducts = extras;
    } catch (e) {
      debugPrint('Error en syncWeightProducts: $e');
    } finally {
      if (generation == _quickAccessCacheGeneration) {
        _weightSynced = true; // también ante error: evita reintentos en cada build
        _weightLoading = false;
        notifyListeners();
      }
    }
  }

  /// Trae del backend los productos fijados que NO estén presentes en `_products`.
  Future<void> syncPinnedProducts(Set<int> pinnedIds) async {
    if (_pinnedLoading || pinnedIds.isEmpty) return;
    final loadedIds = _products.map((p) => p.id).toSet();
    // Solo los que nunca se consultaron: un fijado eliminado en el servidor no vuelve
    // a pedirse en cada build.
    final missingIds = pinnedIds
        .where((id) => !loadedIds.contains(id) && !_pinnedRequestedIds.contains(id))
        .toList();
    if (missingIds.isEmpty) return;

    _pinnedLoading = true;
    final generation = _quickAccessCacheGeneration;
    try {
      final result = await getProductsUseCase(
        page: 1,
        perPage: 500,
        ids: missingIds,
      );
      if (generation != _quickAccessCacheGeneration) return;
      final pageData = List<Product>.from(result['data'] as List);
      final List<Product> extras = List<Product>.from(_pinnedExtraProducts);
      for (final p in pageData) {
        if (!loadedIds.contains(p.id) && !extras.any((e) => e.id == p.id)) {
          extras.add(p);
        }
      }
      _pinnedExtraProducts = extras;
    } catch (e) {
      debugPrint('Error en syncPinnedProducts: $e');
    } finally {
      if (generation == _quickAccessCacheGeneration) {
        _pinnedRequestedIds.addAll(missingIds);
        _pinnedLoading = false;
        notifyListeners();
      }
    }
  }

  List<Product> applyStockUpdatesToProductList(
    List<Product> list,
    Map<int, double> updatedStockById,
  ) {
    if (updatedStockById.isEmpty || list.isEmpty) return list;
    bool anyChanged = false;
    final updatedList = list.map((p) {
      Product current = p;
      if (updatedStockById.containsKey(current.id)) {
        anyChanged = true;
        current = current.copyWith(stock: updatedStockById[current.id]!);
      }
      if (current.isCombo && current.comboIngredients != null && current.comboIngredients!.isNotEmpty) {
        bool comboChanged = false;
        int? limitingCombos;
        final updatedIngredients = current.comboIngredients!.map((ing) {
          final copy = Map<String, dynamic>.from(ing);
          final ingId = (copy['id'] as num?)?.toInt();
          if (ingId != null && updatedStockById.containsKey(ingId)) {
            copy['stock'] = updatedStockById[ingId];
            comboChanged = true;
          }
          final s = (copy['stock'] as num?)?.toDouble() ?? 0.0;
          final q = (copy['quantity'] as num?)?.toDouble() ?? 1.0;
          if (q > 0) {
            final fit = s < 0 ? 0 : (s / q).floor();
            if (limitingCombos == null || fit < limitingCombos!) {
              limitingCombos = fit;
            }
          }
          return copy;
        }).toList();

        if (comboChanged) {
          anyChanged = true;
          current = current.copyWith(
            comboIngredients: updatedIngredients,
            stock: (limitingCombos ?? 0).toDouble(),
          );
        }
      }
      return current;
    }).toList();

    return anyChanged ? updatedList : list;
  }

  /// Actualiza SILENCIOSAMENTE solo el stock de los productos vendidos.
  /// Reemplaza el loadProducts() completo post-venta, eliminando el parpadeo de la grilla.
  /// Se llama en background (fire-and-forget) tras procesar un cobro exitoso.
  Future<Map<int, double>> refreshStockForSoldProducts(
    List<int> soldIds, {
    List<Product>? soldProductsSnapshot,
  }) async {
    if (soldIds.isEmpty) return {};
    try {
      // Expandir IDs localmente por si se vendió un combo (incluir sus ingredientes)
      final expandedIds = <int>{...soldIds};
      final allKnownProducts = <Product>[
        ..._products,
        for (final extra in _categoryExtraProducts.values) ...extra,
        ..._weightOnlyProducts,
        ..._pinnedExtraProducts,
        if (soldProductsSnapshot != null) ...soldProductsSnapshot,
      ];
      for (final p in allKnownProducts) {
        if (p.isCombo && p.comboIngredients != null) {
          final ingIds = p.comboIngredients!
              .map((ing) => (ing['id'] as num?)?.toInt())
              .whereType<int>()
              .toSet();
          if (expandedIds.contains(p.id) || ingIds.intersection(expandedIds).isNotEmpty) {
            expandedIds.add(p.id);
            expandedIds.addAll(ingIds);
          }
        }
      }

      final updates = await repository.fetchBulkStock(expandedIds.toList());
      final updatedStockById = <int, double>{};
      bool changed = false;

      for (final entry in updates) {
        final id = (entry['id'] as num?)?.toInt();
        final stock = double.tryParse(entry['stock']?.toString() ?? '');
        if (id == null || stock == null) continue;
        updatedStockById[id] = stock;
      }

      // FT-01: Replicar la actualización de stock en _products y en todas las
      // colecciones complementarias del Acceso Rápido (categorías, pesables y fijados).
      if (updatedStockById.isNotEmpty) {
        final updatedMain = applyStockUpdatesToProductList(_products, updatedStockById);
        if (!identical(updatedMain, _products)) {
          _products = updatedMain;
          changed = true;
        }

        if (_categoryExtraProducts.isNotEmpty) {
          for (final key in _categoryExtraProducts.keys.toList()) {
            final original = _categoryExtraProducts[key]!;
            final updated = applyStockUpdatesToProductList(original, updatedStockById);
            if (!identical(original, updated)) {
              _categoryExtraProducts[key] = updated;
              changed = true;
            }
          }
        }
        if (_weightOnlyProducts.isNotEmpty) {
          final updated = applyStockUpdatesToProductList(_weightOnlyProducts, updatedStockById);
          if (!identical(_weightOnlyProducts, updated)) {
            _weightOnlyProducts = updated;
            changed = true;
          }
        }
        if (_pinnedExtraProducts.isNotEmpty) {
          final updated = applyStockUpdatesToProductList(_pinnedExtraProducts, updatedStockById);
          if (!identical(_pinnedExtraProducts, updated)) {
            _pinnedExtraProducts = updated;
            changed = true;
          }
        }
      }

      if (changed) notifyListeners();
      return updatedStockById;
    } catch (e) {
      // Silent failure: el stock local puede quedar levemente desincronizado hasta
      // el próximo loadProducts() periódico, lo cual es aceptable en un POS.
      debugPrint('refreshStockForSoldProducts: fallo silencioso ($e)');
      return {};
    }
  }

  Future<bool> createProduct(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final product = await repository.createProduct(data);
      _lastCreatedProduct = product;
      _products = [product, ..._products];
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> uploadProductImage(int productId, String filePath,
      {List<int>? bytes, String? filename}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final imageUrl = await repository.uploadProductImage(productId, filePath,
          bytes: bytes, filename: filename);
      final idx = _products.indexWhere((p) => p.id == productId);
      if (idx != -1) {
        _products[idx] = _products[idx].copyWith(imageUrl: imageUrl);
      }
      if (_lastCreatedProduct?.id == productId) {
        _lastCreatedProduct = _lastCreatedProduct!.copyWith(imageUrl: imageUrl);
      }
      if (_lastUpdatedProduct?.id == productId) {
        _lastUpdatedProduct = _lastUpdatedProduct!.copyWith(imageUrl: imageUrl);
      }
      return imageUrl;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteProductImage(int productId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.deleteProductImage(productId);
      final idx = _products.indexWhere((p) => p.id == productId);
      if (idx != -1) {
        _products[idx] =
            _products[idx].copyWith(imageUrl: null, clearImageUrl: true);
      }
      if (_lastCreatedProduct?.id == productId) {
        _lastCreatedProduct =
            _lastCreatedProduct!.copyWith(imageUrl: null, clearImageUrl: true);
      }
      if (_lastUpdatedProduct?.id == productId) {
        _lastUpdatedProduct =
            _lastUpdatedProduct!.copyWith(imageUrl: null, clearImageUrl: true);
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

  Future<bool> updateProduct(int id, Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await repository.updateProduct(id, data);
      _lastUpdatedProduct = updated;
      final idx = _products.indexWhere((p) => p.id == id);
      if (idx != -1) {
        if (updated.imageUrl == null && _products[idx].imageUrl != null) {
          _products[idx] = updated.copyWith(imageUrl: _products[idx].imageUrl);
        } else {
          _products[idx] = updated;
        }
        _lastUpdatedProduct = _products[idx];
      }
      invalidateQuickAccessExtraCaches();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteProduct(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.deleteProduct(id);
      _products.removeWhere((p) => p.id == id);
      invalidateQuickAccessExtraCaches();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> bulkDeleteProducts(List<int> ids) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.bulkDeleteProducts(ids);
      await loadProducts(page: _currentPage);
      return result['message'] as String?;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> bulkUpdateProducts(
    List<int> ids, {
    int? categoryId,
    bool clearCategory = false,
    int? brandId,
    bool clearBrand = false,
    bool? active,
    int? supplierId,
    bool clearSupplier = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.bulkUpdateProducts(
        ids,
        categoryId: categoryId,
        clearCategory: clearCategory,
        brandId: brandId,
        clearBrand: clearBrand,
        active: active,
        supplierId: supplierId,
        clearSupplier: clearSupplier,
      );
      await loadProducts(page: _currentPage);
      return result['message'] as String?;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<dynamic> _priceHistory = [];
  List<dynamic> get priceHistory => _priceHistory;

  Future<void> fetchPriceHistory() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _priceHistory = await repository.getBulkPriceHistory();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> revertPriceHistory(int historyId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final message = await repository.revertBulkPrice(historyId);
      await loadProducts(page: _currentPage);
      await fetchPriceHistory();
      return message;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> bulkPriceUpdate({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.bulkPriceUpdate(
        percentage: percentage,
        roundingRule: roundingRule,
        targetField: targetField,
        productIds: productIds,
        categoryId: categoryId,
        brandId: brandId,
      );
      // Reload current page to reflect new prices
      await loadProducts(page: _currentPage);
      return result['message'] as String;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> bulkPricePreview({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.bulkPricePreview(
        percentage: percentage,
        roundingRule: roundingRule,
        targetField: targetField,
        productIds: productIds,
        categoryId: categoryId,
        brandId: brandId,
      );
      return result;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    double? minStock,
    String? notes,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.adjustStock(
        productId: productId,
        type: type,
        quantity: quantity,
        minStock: minStock,
        notes: notes,
      );
      // Actualizamos el producto completo en la lista si el backend lo devuelve (mejor consistencia)
      if (result.containsKey('product')) {
        final updatedProduct =
            ProductModel.fromJson(result['product'] as Map<String, dynamic>);
        final idx = _products.indexWhere((p) => p.id == productId);
        if (idx != -1) _products[idx] = updatedProduct;
      } else {
        // Fallback al comportamiento anterior si el backend no envía el objeto completo
        final newStock = double.parse(result['new_stock'].toString());
        final idx = _products.indexWhere((p) => p.id == productId);
        if (idx != -1) {
          _products[idx] = _products[idx].copyWith(stock: newStock);
        }
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

  // ───────────────────────────────────────────────────────
  // GESTIÓN DE RUBROS
  // ───────────────────────────────────────────────────────

  Future<void> loadRubros() async {
    try {
      _rubros = await repository.getRubros();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading rubros: $e');
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<int?> createRubro(String name, {String? description}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created =
          await repository.createRubro(name, description: description);
      _rubros = [..._rubros, created];
      return created.id;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateRubro(int id, String name, {String? description}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated =
          await repository.updateRubro(id, name, description: description);
      final idx = _rubros.indexWhere((r) => r.id == id);
      if (idx != -1) {
        final newList = List.of(_rubros);
        newList[idx] = updated;
        _rubros = newList;
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteRubro(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.deleteRubro(id);
      _rubros.removeWhere((r) => r.id == id);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ───────────────────────────────────────────────────────
  // GESTIÓN DE CATEGORÍAS
  // ───────────────────────────────────────────────────────

  Future<int?> createCategory(String name,
      {String? description, int? rubroId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created = await repository.createCategory(name,
          description: description, rubroId: rubroId);
      _categories = [..._categories, created];
      return created.id;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateCategory(int id, String name,
      {String? description, int? rubroId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await repository.updateCategory(id, name,
          description: description, rubroId: rubroId);
      final idx = _categories.indexWhere((c) => c.id == id);
      if (idx != -1) {
        final newList = List.of(_categories);
        newList[idx] = updated;
        _categories = newList;
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteCategory(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.deleteCategory(id);
      _categories.removeWhere((c) => c.id == id);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ───────────────────────────────────────────────────────
  // GESTIÓN DE MARCAS
  // ───────────────────────────────────────────────────────

  Future<int?> createBrand(String name, {String? description}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created =
          await repository.createBrand(name, description: description);
      _brands = [..._brands, created];
      return created.id;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateBrand(int id, String name, {String? description}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated =
          await repository.updateBrand(id, name, description: description);
      final idx = _brands.indexWhere((b) => b.id == id);
      if (idx != -1) {
        final newList = List.of(_brands);
        newList[idx] = updated;
        _brands = newList;
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

  Future<void> exportCatalogToExcel(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      final token = prefs.getString('pos_session_token');
      final uri = Uri.parse('$baseUrl/catalog/products/export');

      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Generando y descargando Excel...'),
            ],
          ),
        ),
      );

      final response = await http.get(
        uri,
        headers: {
          'X-Session-Token': token ?? '',
          'Accept': 'application/json',
        },
      );

      if (context.mounted) Navigator.of(context).pop(); // Cerrar loader

      if (response.statusCode == 200) {
        final now = DateTime.now();
        final formattedDate =
            '${now.day.toString().padLeft(2, '0')}_${now.month.toString().padLeft(2, '0')}_${now.year}';

        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Lista de Precios',
          fileName: 'lista_precios_$formattedDate.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsBytes(response.bodyBytes);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Excel guardado exitosamente.')),
            );
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error del servidor: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      // Cerrar loader si está abierto
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>> importProducts(
      {required List<int> fileBytes, required String filename}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.importProducts(fileBytes, filename);
      // Reload products after a successful import
      await loadProducts(page: 1, search: '');
      return result;
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteBrand(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.deleteBrand(id);
      _brands.removeWhere((b) => b.id == id);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadBrands() async {
    try {
      _brands = await repository.getBrands();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading brands: $e');
    }
  }
}
