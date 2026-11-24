import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/brand.dart';
import '../../domain/entities/rubro.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../../domain/usecases/get_products_usecase.dart';
import '../../data/datasources/catalog_remote_datasource.dart'
    show CatalogHttpException;
import '../../data/repositories/catalog_repository_impl.dart';
import '../../data/models/product_model.dart';
import '../../data/models/product_batch_model.dart';
import '../../data/models/production_order_model.dart';

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
  // Caché de sesión para productos vistos en búsquedas remotas (SKUs >500) y lookups en 0 ms.
  final Map<int, Product> _recentlySeenProductsById = {};
  static const int _maxRecentlySeenProducts = 200;

  void _rememberProducts(Iterable<Product> items) {
    for (final p in items) {
      if (p.id <= 0) continue;
      _recentlySeenProductsById.remove(p.id);
      _recentlySeenProductsById[p.id] = p;
      while (_recentlySeenProductsById.length > _maxRecentlySeenProducts) {
        _recentlySeenProductsById.remove(_recentlySeenProductsById.keys.first);
      }
    }
  }

  List<Product> getCategoryExtraProducts(int categoryId) =>
      (_categoryExtraProducts[categoryId] ?? const [])
          .where((p) => p.active)
          .toList(growable: false);
  List<Product> get weightOnlyProducts =>
      _weightOnlyProducts.where((p) => p.active).toList(growable: false);
  List<Product> get pinnedExtraProducts =>
      _pinnedExtraProducts.where((p) => p.active).toList(growable: false);

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

  int? _filterSupplierId;
  String? _filterSupplierName;
  bool _supplierFilterFallbackActive = false;
  int? _filterCategoryId;
  int? _filterBrandId;
  bool? _filterActive;

  int? get filterSupplierId => _filterSupplierId;
  String? get filterSupplierName => _filterSupplierName;
  bool get supplierFilterFallbackActive => _supplierFilterFallbackActive;
  int? get filterCategoryId => _filterCategoryId;
  int? get filterBrandId => _filterBrandId;
  bool? get filterActive => _filterActive;
  int get activeCatalogFiltersCount =>
      (_filterSupplierId != null ? 1 : 0) +
      (_filterCategoryId != null ? 1 : 0) +
      (_filterBrandId != null ? 1 : 0) +
      (_filterActive != null ? 1 : 0);

  void clearSearch() {
    _searchQuery = '';
  }

  void clearSupplierFilterSilently() {
    _filterSupplierId = null;
    _filterSupplierName = null;
    _supplierFilterFallbackActive = false;
  }

  void clearCatalogFiltersSilently() {
    clearSupplierFilterSilently();
    _filterCategoryId = null;
    _filterBrandId = null;
    _filterActive = null;
  }

  Future<void> setSupplierFilter(
    int? supplierId, {
    String? supplierName,
    bool reload = true,
  }) async {
    _filterSupplierId = supplierId;
    _filterSupplierName =
        supplierId == null ? null : (supplierName?.trim().isNotEmpty == true ? supplierName!.trim() : null);
    _supplierFilterFallbackActive = false;
    if (reload) {
      await loadProducts(page: 1);
    } else {
      notifyListeners();
    }
  }

  Future<void> setCategoryFilter(int? categoryId, {bool reload = true}) async {
    _filterCategoryId = categoryId;
    if (reload) {
      await loadProducts(page: 1);
    } else {
      notifyListeners();
    }
  }

  Future<void> setBrandFilter(int? brandId, {bool reload = true}) async {
    _filterBrandId = brandId;
    if (reload) {
      await loadProducts(page: 1);
    } else {
      notifyListeners();
    }
  }

  Future<void> setActiveFilter(bool? active, {bool reload = true}) async {
    _filterActive = active;
    if (reload) {
      await loadProducts(page: 1);
    } else {
      notifyListeners();
    }
  }

  Future<void> clearAllCatalogFilters({bool reload = true}) async {
    clearCatalogFiltersSilently();
    if (reload) {
      await loadProducts(page: 1);
    } else {
      notifyListeners();
    }
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
      if (_categories.isEmpty || force) {
        _categories = sortByAlphabeticalName(
          await repository.getCategories(),
          (c) => c.name,
        );
      }
      if (_brands.isEmpty || force) {
        _brands = sortByAlphabeticalName(
          await repository.getBrands(),
          (b) => b.name,
        );
      }
      if (_rubros.isEmpty || force) {
        _rubros = sortByAlphabeticalName(
          await repository.getRubros(),
          (r) => r.name,
        );
      }
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
    final isPosDefaultOrder = _sortBy == '';
    final activeSupplierId = isPosDefaultOrder ? null : _filterSupplierId;
    final activeCategoryId = isPosDefaultOrder ? null : _filterCategoryId;
    final activeBrandId = isPosDefaultOrder ? null : _filterBrandId;
    final activeStatusFilter = isPosDefaultOrder ? null : _filterActive;
    notifyListeners();
    try {
      final result = await getProductsUseCase(
        page: page,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        sortBy: _sortBy.isNotEmpty ? _sortBy : null,
        sortDirection: _sortBy.isNotEmpty ? _sortDirection : null,
        perPage: perPage,
        categoryId: activeCategoryId,
        brandId: activeBrandId,
        supplierId: activeSupplierId,
        active: activeStatusFilter,
      );
      var fetched = List<Product>.from(result['data'] as List);
      _rememberProducts(fetched);
      if (activeSupplierId != null) {
        final hasForeignSupplier = fetched.any(
          (p) => p.supplier?.id != activeSupplierId,
        );
        _supplierFilterFallbackActive = hasForeignSupplier;
        if (hasForeignSupplier) {
          fetched = fetched
              .where((p) => p.supplier?.id == activeSupplierId)
              .toList();
        }
      } else {
        _supplierFilterFallbackActive = false;
      }
      _products = fetched;
      _currentPage = result['current_page'] as int;
      _lastPage = result['last_page'] as int;
      _catalogOrderVersion++;
      if (page == 1) {
        invalidateQuickAccessExtraCaches();
        if (_categories.isEmpty) {
          _categories = sortByAlphabeticalName(
            await repository.getCategories(),
            (c) => c.name,
          );
        }
        if (_brands.isEmpty) {
          _brands = sortByAlphabeticalName(
            await repository.getBrands(),
            (b) => b.name,
          );
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
      _rememberProducts(_products);
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
  /// Resuelve un producto por su ID buscando primero en todas las listas en memoria (0 ms)
  /// y, si no está cargado en la página actual ni en cachés secundarias, lo solicita
  /// directamente al backend sin alterar el estado de paginación de la grilla.
  Future<Product?> resolveProductById(int productId) async {
    for (final p in _products) {
      if (p.id == productId) return p;
    }
    for (final p in _pinnedExtraProducts) {
      if (p.id == productId) return p;
    }
    for (final p in _weightOnlyProducts) {
      if (p.id == productId) return p;
    }
    for (final extras in _categoryExtraProducts.values) {
      for (final p in extras) {
        if (p.id == productId) return p;
      }
    }
    final seenCached = _recentlySeenProductsById[productId];
    if (seenCached != null) return seenCached;
    try {
      final result = await getProductsUseCase(
        page: 1,
        perPage: 1,
        ids: [productId],
      );
      final list = List<Product>.from(result['data'] as List);
      for (final p in list) {
        if (p.id == productId) {
          _rememberProducts([p]);
          return p;
        }
      }
    } catch (e) {
      debugPrint('Error en resolveProductById(): ');
    }
    return null;
  }

  Future<List<Product>> searchProductsRemote(String query,
      {int perPage = 30, bool activeOnly = true}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final result = await getProductsUseCase(
        page: 1,
        search: q,
        sortBy: 'name',
        sortDirection: 'asc',
        perPage: perPage,
        active: activeOnly ? true : null,
      );
      final list = List<Product>.from(result['data'] as List);
      _rememberProducts(list);
      return activeOnly ? list.where((p) => p.active).toList() : list;
    } catch (e) {
      debugPrint('Error en searchProductsRemote: $e');
      return [];
    }
  }

  /// Obtiene todos los productos activos del catálogo paginando de a 500
  /// para pickers de Producción Propia y Recetas sin alterar la paginación principal.
  Future<List<Product>> fetchAllActiveProductsForProduction() async {
    try {
      final byId = <int, Product>{};
      int page = 1;
      int lastPage = 1;

      do {
        final result = await getProductsUseCase(
          page: page,
          sortBy: 'name',
          sortDirection: 'asc',
          perPage: 500,
          active: true,
        );
        final pageData = List<Product>.from(result['data'] as List);
        for (final p in pageData) {
          if (p.active) byId[p.id] = p;
        }
        lastPage = (result['last_page'] as int?) ?? 1;
        page++;
      } while (page <= lastPage && page <= 25);

      return byId.values.toList();
    } catch (e) {
      debugPrint('Error en fetchAllActiveProductsForProduction: $e');
      return List<Product>.from(_products);
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
      final missingSet = missingIds.toSet();
      final List<Product> extras = List<Product>.from(_pinnedExtraProducts);
      for (final p in pageData) {
        if (!missingSet.contains(p.id)) continue;
        _rememberProducts([p]);
        if (p.active && !loadedIds.contains(p.id) && !extras.any((e) => e.id == p.id)) {
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
    Map<int, double> updatedStockById, {
    Map<int, String?>? updatedExpirationById,
  }) {
    if (updatedStockById.isEmpty || list.isEmpty) return list;
    bool anyChanged = false;
    final updatedList = list.map((p) {
      Product current = p;
      if (updatedStockById.containsKey(current.id)) {
        anyChanged = true;
        final hasExpKey =
            updatedExpirationById != null && updatedExpirationById.containsKey(current.id);
        final nextExp = hasExpKey ? updatedExpirationById[current.id] : null;
        current = current.copyWith(
          stock: updatedStockById[current.id]!,
          expirationDate: nextExp,
          clearExpirationDate: hasExpKey && nextExp == null,
        );
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
            final fit = calcUnitsFitStock(s, q);
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
      final updatedExpirationById = <int, String?>{};
      bool changed = false;

      for (final entry in updates) {
        final id = (entry['id'] as num?)?.toInt();
        final stock = double.tryParse(entry['stock']?.toString() ?? '');
        if (id == null || stock == null) continue;
        updatedStockById[id] = stock;
        if (entry.containsKey('expiration_date')) {
          final rawExp = entry['expiration_date'];
          updatedExpirationById[id] = rawExp != null &&
                  rawExp.toString() != 'null' &&
                  rawExp.toString().trim().isNotEmpty
              ? rawExp.toString().split('T').first
              : null;
        }
      }

      // FT-01: Replicar la actualización de stock en _products y en todas las
      // colecciones complementarias del Acceso Rápido (categorías, pesables y fijados).
      if (updatedStockById.isNotEmpty) {
        final updatedMain = applyStockUpdatesToProductList(
          _products,
          updatedStockById,
          updatedExpirationById: updatedExpirationById,
        );
        if (!identical(updatedMain, _products)) {
          _products = updatedMain;
          changed = true;
        }

        if (_categoryExtraProducts.isNotEmpty) {
          for (final key in _categoryExtraProducts.keys.toList()) {
            final original = _categoryExtraProducts[key]!;
            final updated = applyStockUpdatesToProductList(
              original,
              updatedStockById,
              updatedExpirationById: updatedExpirationById,
            );
            if (!identical(original, updated)) {
              _categoryExtraProducts[key] = updated;
              changed = true;
            }
          }
        }
        if (_weightOnlyProducts.isNotEmpty) {
          final updated = applyStockUpdatesToProductList(
            _weightOnlyProducts,
            updatedStockById,
            updatedExpirationById: updatedExpirationById,
          );
          if (!identical(_weightOnlyProducts, updated)) {
            _weightOnlyProducts = updated;
            changed = true;
          }
        }
        if (_pinnedExtraProducts.isNotEmpty) {
          final updated = applyStockUpdatesToProductList(
            _pinnedExtraProducts,
            updatedStockById,
            updatedExpirationById: updatedExpirationById,
          );
          if (!identical(_pinnedExtraProducts, updated)) {
            _pinnedExtraProducts = updated;
            changed = true;
          }
        }
        if (_recentlySeenProductsById.isNotEmpty) {
          for (final id in updatedStockById.keys) {
            final cached = _recentlySeenProductsById[id];
            if (cached == null) continue;
            final updatedCached = applyStockUpdatesToProductList(
              [cached],
              updatedStockById,
              updatedExpirationById: updatedExpirationById,
            );
            if (!identical(cached, updatedCached.first)) {
              _recentlySeenProductsById[id] = updatedCached.first;
              changed = true;
            }
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
      final matchesActiveSupplierFilter = _filterSupplierId == null ||
          product.supplier?.id == _filterSupplierId ||
          data['supplier_id'] == _filterSupplierId;
      if (matchesActiveSupplierFilter) {
        _products = [product, ..._products];
      }
      _rememberProducts([product]);
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
      _rememberProducts([_lastUpdatedProduct!]);
      invalidateQuickAccessExtraCaches();
      unawaited(loadMetadata(force: true));
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Actualiza el precio de venta, costo y/o código de barras de un producto directamente desde el carrito del POS,
  /// preservando el orden visual de la grilla y sin activar el spinner global de carga.
  Future<Product?> updateProductPriceFromPos(
    int id, {
    String? name,
    double? sellingPrice,
    double? costPrice,
    double? ivaRate,
    String? barcode,
  }) async {
    _errorMessage = null;
    final cleanBarcode = barcode?.trim();
    final cleanName = name?.trim();
    final payload = <String, dynamic>{
      if (cleanName != null && cleanName.isNotEmpty) 'name': cleanName,
      if (sellingPrice != null) 'selling_price': sellingPrice,
      if (costPrice != null) 'cost_price': costPrice,
      if (ivaRate != null) 'iva_rate': ivaRate,
      if (cleanBarcode != null && cleanBarcode.isNotEmpty) 'barcode': cleanBarcode,
    };
    if (payload.isEmpty) return null;

    try {
      Product updated = await repository.updateProduct(id, payload);

      List<Product> replaceInList(List<Product> list) {
        final idx = list.indexWhere((p) => p.id == id);
        if (idx == -1) return list;
        final copy = List<Product>.from(list);
        final existing = copy[idx];
        final merged = (updated.imageUrl == null && existing.imageUrl != null)
            ? updated.copyWith(imageUrl: existing.imageUrl)
            : updated;
        updated = merged;
        copy[idx] = merged;
        return copy;
      }

      _products = replaceInList(_products);
      if (_categoryExtraProducts.isNotEmpty) {
        for (final key in _categoryExtraProducts.keys.toList()) {
          _categoryExtraProducts[key] =
              replaceInList(_categoryExtraProducts[key]!);
        }
      }
      if (_weightOnlyProducts.isNotEmpty) {
        _weightOnlyProducts = replaceInList(_weightOnlyProducts);
      }
      if (_pinnedExtraProducts.isNotEmpty) {
        _pinnedExtraProducts = replaceInList(_pinnedExtraProducts);
      }

      _lastUpdatedProduct = updated;
      _rememberProducts([updated]);
      notifyListeners();
      return updated;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteProduct(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.deleteProduct(id);
      _products.removeWhere((p) => p.id == id);
      _recentlySeenProductsById.remove(id);
      invalidateQuickAccessExtraCaches();
      unawaited(loadMetadata(force: true));
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
      unawaited(loadMetadata(force: true));
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
      unawaited(loadMetadata(force: true));
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
      invalidateQuickAccessExtraCaches();
      await loadProducts(page: _currentPage, search: _searchQuery);
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
    int? supplierId,
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
        supplierId: supplierId,
      );
      invalidateQuickAccessExtraCaches();
      // Reload current page to reflect new prices
      await loadProducts(page: _currentPage, search: _searchQuery);
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
    int? supplierId,
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
        supplierId: supplierId,
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

  Product _mergeProductSnapshot(Product existing, Product incoming) {
    return Product(
      id: incoming.id,
      name: incoming.name,
      barcode: incoming.barcode ?? existing.barcode,
      internalCode: incoming.internalCode,
      costPrice: incoming.costPrice,
      sellingPrice: incoming.sellingPrice,
      priceWholesale: incoming.priceWholesale,
      priceCard: incoming.priceCard,
      stock: incoming.stock,
      minStock: incoming.minStock,
      active: incoming.active,
      isSoldByWeight: incoming.isSoldByWeight,
      isCombo: incoming.isCombo,
      isService: incoming.isService,
      comboIngredients: incoming.comboIngredients ?? existing.comboIngredients,
      priceTiers: incoming.priceTiers ?? existing.priceTiers,
      salesCount: incoming.salesCount != 0 ? incoming.salesCount : existing.salesCount,
      vencimientoDias: incoming.vencimientoDias ?? existing.vencimientoDias,
      expirationDate: incoming.expirationDate,
      expiryAlertDays: incoming.expiryAlertDays ?? existing.expiryAlertDays,
      trackBatches: incoming.trackBatches,
      lotDeductionPolicy: incoming.lotDeductionPolicy,
      allowSellExpired: incoming.allowSellExpired,
      hasProductionRecipe: incoming.hasProductionRecipe,
      recipeYieldQuantity: incoming.recipeYieldQuantity,
      recipeIngredients: incoming.recipeIngredients ?? existing.recipeIngredients,
      unitType: incoming.unitType,
      supplierSku: incoming.supplierSku ?? existing.supplierSku,
      storageLocation: incoming.storageLocation ?? existing.storageLocation,
      technicalSpec: incoming.technicalSpec ?? existing.technicalSpec,
      purchasePackageName:
          incoming.purchasePackageName ?? existing.purchasePackageName,
      conversionFactor: incoming.conversionFactor ?? existing.conversionFactor,
      calcConfig: incoming.calcConfig,
      ivaRate: incoming.ivaRate,
      needsCatalogReview: incoming.needsCatalogReview,
      imageUrl: incoming.imageUrl ?? existing.imageUrl,
      category: incoming.category ?? existing.category,
      categories: incoming.categories ?? existing.categories,
      brand: incoming.brand ?? existing.brand,
      supplier: incoming.supplier ?? existing.supplier,
    );
  }

  void syncProductSnapshot(Product updatedProduct) {
    _syncProductSnapshotInCaches(updatedProduct);
    notifyListeners();
  }

  /// Actualiza la configuración de la Calculadora Ferretera (`calc_config`) en el backend
  /// sin requerir PIN de administrador y sincroniza la instancia en memoria en todas las listas.
  /// Ante rechazo 4xx del servidor (excepto 404/408), no contamina la caché en memoria.
  Future<Product?> updateProductCalcConfigFromPos(
    int productId,
    Map<String, dynamic>? calcConfig,
  ) async {
    if (productId <= 0) return null;
    try {
      final updated = await repository.updateProductCalcConfig(productId, calcConfig);
      _syncProductSnapshotInCaches(updated);
      notifyListeners();
      return updated;
    } on CatalogHttpException catch (e) {
      if (e.isClientError && e.statusCode != 404 && e.statusCode != 408) {
        debugPrint(
          'updateProductCalcConfigFromPos rejected (${e.statusCode}): ${e.message}',
        );
        return null;
      }
      debugPrint('updateProductCalcConfigFromPos fallback (${e.statusCode}): $e');
      return _applyLocalCalcConfigFallback(productId, calcConfig);
    } catch (e) {
      debugPrint('updateProductCalcConfigFromPos warning (fallback offline activo): $e');
      return _applyLocalCalcConfigFallback(productId, calcConfig);
    }
  }

  Product? _applyLocalCalcConfigFallback(
    int productId,
    Map<String, dynamic>? calcConfig,
  ) {
    final idx = _products.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      final localUpdated = _products[idx].copyWith(
        calcConfig: calcConfig,
        clearCalcConfig: calcConfig == null,
      );
      _syncProductSnapshotInCaches(localUpdated);
      notifyListeners();
      return localUpdated;
    }
    return null;
  }

  void _syncProductSnapshotInCaches(Product updatedProduct) {
    Product merged = updatedProduct;
    final idx = _products.indexWhere((p) => p.id == updatedProduct.id);
    if (idx != -1) {
      merged = _mergeProductSnapshot(_products[idx], updatedProduct);
      _products[idx] = merged;
    }
    _lastUpdatedProduct = merged;
    _rememberProducts([merged]);
    final stockMap = <int, double>{merged.id: merged.stock};
    final expMap = <int, String?>{merged.id: merged.expirationDate};
    _products = applyStockUpdatesToProductList(
      _products,
      stockMap,
      updatedExpirationById: expMap,
    );
    if (_categoryExtraProducts.isNotEmpty) {
      for (final key in _categoryExtraProducts.keys.toList()) {
        final updatedList = applyStockUpdatesToProductList(
          _categoryExtraProducts[key]!,
          stockMap,
          updatedExpirationById: expMap,
        );
        _categoryExtraProducts[key] = updatedList
            .map((p) => p.id == merged.id ? merged : p)
            .toList();
      }
    }
    if (_weightOnlyProducts.isNotEmpty) {
      final updatedList = applyStockUpdatesToProductList(
        _weightOnlyProducts,
        stockMap,
        updatedExpirationById: expMap,
      );
      _weightOnlyProducts =
          updatedList.map((p) => p.id == merged.id ? merged : p).toList();
    }
    if (_pinnedExtraProducts.isNotEmpty) {
      final updatedList = applyStockUpdatesToProductList(
        _pinnedExtraProducts,
        stockMap,
        updatedExpirationById: expMap,
      );
      _pinnedExtraProducts =
          updatedList.map((p) => p.id == merged.id ? merged : p).toList();
    }
  }

  Future<bool> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    double? minStock,
    String? notes,
    int? batchId,
    String? batchCode,
    String? expirationDate,
    String? manufacturedAt,
    double? unitCost,
    String? reasonCode,
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
        batchId: batchId,
        batchCode: batchCode,
        expirationDate: expirationDate,
        manufacturedAt: manufacturedAt,
        unitCost: unitCost,
        reasonCode: reasonCode,
      );
      if (result.containsKey('product')) {
        final updatedProduct =
            ProductModel.fromJson(result['product'] as Map<String, dynamic>);
        _syncProductSnapshotInCaches(updatedProduct);
      } else if (result.containsKey('new_stock')) {
        final newStock = double.parse(result['new_stock'].toString());
        final idx = _products.indexWhere((p) => p.id == productId);
        if (idx != -1) {
          _syncProductSnapshotInCaches(_products[idx].copyWith(stock: newStock));
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

  Future<ProductBatchesResponse> fetchProductBatches(
    int productId, {
    bool includeClosed = true,
  }) async {
    return await repository.fetchProductBatches(
      productId,
      includeClosed: includeClosed,
    );
  }

  Future<Map<String, dynamic>?> createProductBatch(
    int productId, {
    required double quantity,
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  }) async {
    _errorMessage = null;
    try {
      final res = await repository.createProductBatch(
        productId,
        quantity: quantity,
        batchCode: batchCode,
        manufacturedAt: manufacturedAt,
        expirationDate: expirationDate,
        unitCost: unitCost,
        notes: notes,
      );
      if (res['product'] is Map) {
        _syncProductSnapshotInCaches(
          ProductModel.fromJson(Map<String, dynamic>.from(res['product'] as Map)),
        );
        notifyListeners();
      }
      return res;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateProductBatch(
    int batchId, {
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  }) async {
    _errorMessage = null;
    try {
      final res = await repository.updateProductBatch(
        batchId,
        batchCode: batchCode,
        manufacturedAt: manufacturedAt,
        expirationDate: expirationDate,
        unitCost: unitCost,
        notes: notes,
      );
      if (res['product'] is Map) {
        _syncProductSnapshotInCaches(
          ProductModel.fromJson(Map<String, dynamic>.from(res['product'] as Map)),
        );
        notifyListeners();
      }
      return res;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> writeOffBatch(
    int batchId, {
    double? quantity,
    String? notes,
  }) async {
    _errorMessage = null;
    try {
      final res = await repository.writeOffBatch(
        batchId,
        quantity: quantity,
        notes: notes,
      );
      if (res['product'] is Map) {
        _syncProductSnapshotInCaches(
          ProductModel.fromJson(Map<String, dynamic>.from(res['product'] as Map)),
        );
        notifyListeners();
      }
      return res;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchExpiredBatches({bool includeToday = true}) async {
    return await repository.fetchExpiredBatches(includeToday: includeToday);
  }

  Future<Map<String, dynamic>?> splitBatch(
    int batchId, {
    required double quantity,
    String? expirationDate,
    String? batchCode,
    String? notes,
  }) async {
    _errorMessage = null;
    try {
      final res = await repository.splitBatch(
        batchId,
        quantity: quantity,
        expirationDate: expirationDate,
        batchCode: batchCode,
        notes: notes,
      );
      if (res['product'] is Map) {
        _syncProductSnapshotInCaches(
          ProductModel.fromJson(Map<String, dynamic>.from(res['product'] as Map)),
        );
        notifyListeners();
      }
      return res;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> writeOffExpiredBatches({
    List<Map<String, dynamic>>? items,
    bool includeToday = true,
    String? notes,
  }) async {
    _errorMessage = null;
    try {
      final res = await repository.writeOffExpiredBatches(
        items: items,
        includeToday: includeToday,
        notes: notes,
      );
      await loadProducts(page: _currentPage);
      invalidateQuickAccessExtraCaches();
      return res;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchProductionOrders({
    int page = 1,
    int? productId,
    String? status,
    String? search,
  }) async {
    return await repository.fetchProductionOrders(
      page: page,
      productId: productId,
      status: status,
      search: search,
    );
  }

  Future<ProductionOrderModel?> createProductionOrder(Map<String, dynamic> payload) async {
    _errorMessage = null;
    try {
      final order = await repository.createProductionOrder(payload);
      await loadProducts(page: _currentPage);
      invalidateQuickAccessExtraCaches();
      return order;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> createBatchProductionOrders(Map<String, dynamic> payload) async {
    _errorMessage = null;
    try {
      final res = await repository.createBatchProductionOrders(payload);
      await loadProducts(page: _currentPage);
      invalidateQuickAccessExtraCaches();
      return res;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<ProductionOrderModel?> voidProductionOrder(int orderId) async {
    _errorMessage = null;
    try {
      final order = await repository.voidProductionOrder(orderId);
      await loadProducts(page: _currentPage);
      invalidateQuickAccessExtraCaches();
      return order;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchWasteReport({
    String? startDate,
    String? endDate,
  }) async {
    return await repository.fetchWasteReport(
      startDate: startDate,
      endDate: endDate,
    );
  }

  // ───────────────────────────────────────────────────────
  // GESTIÓN DE RUBROS
  // ───────────────────────────────────────────────────────

  Future<void> loadRubros() async {
    try {
      _rubros = sortByAlphabeticalName(
        await repository.getRubros(),
        (r) => r.name,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading rubros: $e');
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<int?> createRubro(
    String name, {
    String? description,
    String? verticalType,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created = await repository.createRubro(
        name,
        description: description,
        verticalType: verticalType,
      );
      _rubros = sortByAlphabeticalName([..._rubros, created], (r) => r.name);
      return created.id;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateRubro(
    int id,
    String name, {
    String? description,
    String? verticalType,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await repository.updateRubro(
        id,
        name,
        description: description,
        verticalType: verticalType,
      );
      final idx = _rubros.indexWhere((r) => r.id == id);
      if (idx != -1) {
        final newList = List.of(_rubros);
        newList[idx] = updated;
        _rubros = sortByAlphabeticalName(newList, (r) => r.name);
      }
      if (_categories.isNotEmpty) {
        _categories = _categories.map((cat) {
          if (cat.rubroId == id || cat.rubro?.id == id) {
            return cat.copyWith(rubro: updated);
          }
          return cat;
        }).toList();
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
      _categories = sortByAlphabeticalName(
        [..._categories, created],
        (c) => c.name,
      );
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
        _categories = sortByAlphabeticalName(newList, (c) => c.name);
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
      _brands = sortByAlphabeticalName([..._brands, created], (b) => b.name);
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
        _brands = sortByAlphabeticalName(newList, (b) => b.name);
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

  Future<Map<String, dynamic>> importProducts({
    required List<int> fileBytes,
    required String filename,
    int? defaultSupplierId,
    double? defaultMarginPercent,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      Map<String, dynamic> result;
      final hasOptions =
          defaultSupplierId != null || defaultMarginPercent != null;
      if (hasOptions && repository is CatalogRepositoryImpl) {
        result = await (repository as CatalogRepositoryImpl)
            .importProductsWithOptions(
          fileBytes,
          filename,
          defaultSupplierId: defaultSupplierId,
          defaultMarginPercent: defaultMarginPercent,
        );
      } else {
        result = await repository.importProducts(fileBytes, filename);
      }
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
      _brands = sortByAlphabeticalName(
        await repository.getBrands(),
        (b) => b.name,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading brands: $e');
    }
  }
}

extension CatalogProviderActiveProductsX on CatalogProvider {
  /// Productos activos en memoria (`active == true`).
  /// Única fuente de verdad para mostrador (Terminal POS, Presupuestos, F5, F7).
  List<Product> get activeProducts =>
      products.where((p) => p.active).toList(growable: false);
}

/// Extensión segura para registrar y resolver productos recientes (incluidos SKUs >500).
/// Envuelve lecturas/escrituras internas en `try/catch` para convivir con mocks
/// que usan `implements CatalogProvider` en tests.
extension CatalogProviderRecentLookupX on CatalogProvider {
  static final Expando<Map<int, Product>> _fallbackSeenByInstance =
      Expando<Map<int, Product>>('_fallbackSeenProducts');

  Map<int, Product> _ensureFallbackSeenMap() {
    var map = _fallbackSeenByInstance[this];
    if (map == null) {
      map = {};
      _fallbackSeenByInstance[this] = map;
    }
    return map;
  }

  void registerRecentlySeenProducts(Iterable<Product> items) {
    try {
      _rememberProducts(items);
      return;
    } catch (_) {}
    final map = _ensureFallbackSeenMap();
    for (final p in items) {
      if (p.id > 0) {
        map[p.id] = p;
      }
    }
  }

  List<Product> resolveRecentProducts(
    Iterable<int> ids, {
    bool activeOnly = true,
  }) {
    final idList = ids.where((id) => id > 0).toList();
    if (idList.isEmpty) return const [];

    final byId = <int, Product>{};
    try {
      for (final p in products) {
        if (!activeOnly || p.active) byId[p.id] = p;
      }
    } catch (_) {}
    try {
      for (final p in pinnedExtraProducts) {
        if (!activeOnly || p.active) byId.putIfAbsent(p.id, () => p);
      }
    } catch (_) {}
    try {
      for (final p in weightOnlyProducts) {
        if (!activeOnly || p.active) byId.putIfAbsent(p.id, () => p);
      }
    } catch (_) {}
    try {
      for (final extras in _categoryExtraProducts.values) {
        for (final p in extras) {
          if (!activeOnly || p.active) byId.putIfAbsent(p.id, () => p);
        }
      }
    } catch (_) {}
    try {
      for (final p in _recentlySeenProductsById.values) {
        if (!activeOnly || p.active) byId.putIfAbsent(p.id, () => p);
      }
    } catch (_) {}
    final fallbackMap = _fallbackSeenByInstance[this];
    if (fallbackMap != null) {
      for (final p in fallbackMap.values) {
        if (!activeOnly || p.active) byId.putIfAbsent(p.id, () => p);
      }
    }

    final resolved = <Product>[];
    for (final id in idList) {
      final prod = byId[id];
      if (prod != null && (!activeOnly || prod.active)) {
        resolved.add(prod);
      }
    }
    return resolved;
  }

  /// Devuelve solo los IDs de [ids] que aún no existen en memoria (activos o
  /// inactivos) ni fueron consultados previamente (`isPinnedHydrated`), evitando
  /// agendar re-hidrataciones repetidas para productos dados de baja.
  Set<int> unhydratedRecentProductIds(Iterable<int> ids) {
    final idSet = ids.where((id) => id > 0).toSet();
    if (idSet.isEmpty) return const <int>{};

    final knownOrChecked = <int>{};
    try {
      if (isPinnedHydrated(idSet)) return const <int>{};
    } catch (_) {
      // Mocks simples que usan `implements CatalogProvider` sin implementar
      // `isPinnedHydrated` ni `syncPinnedProducts`.
      return const <int>{};
    }
    try {
      for (final p in products) {
        knownOrChecked.add(p.id);
      }
    } catch (_) {}
    try {
      for (final p in _pinnedExtraProducts) {
        knownOrChecked.add(p.id);
      }
    } catch (_) {}
    try {
      for (final p in _weightOnlyProducts) {
        knownOrChecked.add(p.id);
      }
    } catch (_) {}
    try {
      for (final extras in _categoryExtraProducts.values) {
        for (final p in extras) {
          knownOrChecked.add(p.id);
        }
      }
    } catch (_) {}
    try {
      knownOrChecked.addAll(_recentlySeenProductsById.keys);
    } catch (_) {}
    try {
      knownOrChecked.addAll(_pinnedRequestedIds);
    } catch (_) {}
    final fallbackMap = _fallbackSeenByInstance[this];
    if (fallbackMap != null) {
      knownOrChecked.addAll(fallbackMap.keys);
    }

    return idSet
        .where((id) => !knownOrChecked.contains(id))
        .toSet();
  }
}

extension CatalogProviderSupplierFilterX on CatalogProvider {
  /// Lectura tolerante para mocks heredados (`implements CatalogProvider`) que
  /// no sobrescriben getters nuevos en tests antiguos.
  int? get safeFilterSupplierId {
    try {
      return filterSupplierId;
    } catch (_) {
      return null;
    }
  }

  String? get safeFilterSupplierName {
    try {
      return filterSupplierName;
    } catch (_) {
      return null;
    }
  }

  bool get safeSupplierFilterFallbackActive {
    try {
      return supplierFilterFallbackActive;
    } catch (_) {
      return false;
    }
  }

  void safeClearSupplierFilterSilently() {
    try {
      clearSupplierFilterSilently();
    } catch (_) {}
  }

  int? get safeFilterCategoryId {
    try {
      return filterCategoryId;
    } catch (_) {
      return null;
    }
  }

  int? get safeFilterBrandId {
    try {
      return filterBrandId;
    } catch (_) {
      return null;
    }
  }

  bool? get safeFilterActive {
    try {
      return filterActive;
    } catch (_) {
      return null;
    }
  }

  int get safeActiveCatalogFiltersCount {
    try {
      return activeCatalogFiltersCount;
    } catch (_) {
      return safeFilterSupplierId != null ? 1 : 0;
    }
  }

  void safeClearCatalogFiltersSilently() {
    try {
      clearCatalogFiltersSilently();
    } catch (_) {
      safeClearSupplierFilterSilently();
    }
  }

  Future<void> safeSetSupplierFilter(
    int? supplierId, {
    String? supplierName,
    bool reload = true,
  }) async {
    try {
      await setSupplierFilter(
        supplierId,
        supplierName: supplierName,
        reload: reload,
      );
    } catch (_) {}
  }

  Future<void> safeSetCategoryFilter(int? categoryId, {bool reload = true}) async {
    try {
      await setCategoryFilter(categoryId, reload: reload);
    } catch (_) {}
  }

  Future<void> safeSetBrandFilter(int? brandId, {bool reload = true}) async {
    try {
      await setBrandFilter(brandId, reload: reload);
    } catch (_) {}
  }

  Future<void> safeSetActiveFilter(bool? active, {bool reload = true}) async {
    try {
      await setActiveFilter(active, reload: reload);
    } catch (_) {}
  }

  Future<void> safeClearAllCatalogFilters({bool reload = true}) async {
    try {
      await clearAllCatalogFilters(reload: reload);
    } catch (_) {
      safeClearSupplierFilterSilently();
    }
  }

  List<Rubro> get safeRubros {
    try {
      return rubros;
    } catch (_) {
      return const [];
    }
  }

  Future<void> loadProductsWithoutSupplierFilter({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
  }) async {
    safeClearCatalogFiltersSilently();
    await loadProducts(
      page: page,
      search: search,
      sortBy: sortBy,
      sortDirection: sortDirection,
      perPage: perPage,
    );
  }
}
