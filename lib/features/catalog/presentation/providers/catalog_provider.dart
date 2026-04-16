import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
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

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Product> _criticalAlerts = [];
  List<Product> get criticalAlerts => _criticalAlerts;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ── Pagination State ─────────────────────────────────────
  int _currentPage = 1;
  int _lastPage = 1;
  int get currentPage => _currentPage;
  int get lastPage => _lastPage;
  bool get hasNextPage => _currentPage < _lastPage;
  bool get hasPrevPage => _currentPage > 1;

  // ── Search ───────────────────────────────────────────────
  String _searchQuery = '';

  // ── Sort ─────────────────────────────────────────────────
  String _sortBy = 'name';
  String _sortDirection = 'asc';
  String get sortBy => _sortBy;
  String get sortDirection => _sortDirection;

  CatalogProvider({required this.getProductsUseCase, required this.repository});

  Future<void> loadProducts({int page = 1, String? search, String? sortBy, String? sortDirection}) async {
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
        sortBy: _sortBy,
        sortDirection: _sortDirection,
      );
      _products = List<Product>.from(result['data'] as List);
      _currentPage = result['current_page'] as int;
      _lastPage = result['last_page'] as int;
      if (page == 1) {
        if (_categories.isEmpty) {
          _categories = await repository.getCategories();
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

  /// Refuerzo Senior: Actualiza los contadores de ventas en memoria para que la UI 
  /// se reordene al instante sin necesidad de una petición de red.
  void updateProductSalesCountLocally(Map<int, int> productSales) {
    bool changed = false;
    for (var entry in productSales.entries) {
      final index = _products.indexWhere((p) => p.id == entry.key);
      if (index != -1) {
        final current = _products[index];
        _products[index] = current.copyWith(
          salesCount: (current.salesCount) + entry.value,
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<bool> createProduct(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final product = await repository.createProduct(data);
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

  Future<bool> updateProduct(int id, Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await repository.updateProduct(id, data);
      final idx = _products.indexWhere((p) => p.id == id);
      if (idx != -1) _products[idx] = updated;
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

  Future<String?> bulkUpdateProducts(List<int> ids, {int? categoryId, bool? active}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.bulkUpdateProducts(ids, categoryId: categoryId, active: active);
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

  Future<String?> bulkPriceUpdate({
    required double percentage,
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
        productIds: productIds,
        categoryId: categoryId,
        brandId: brandId,
      );
      // Reload current page to reflect new prices
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
        final updatedProduct = ProductModel.fromJson(result['product'] as Map<String, dynamic>);
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
  // GESTIÓN DE CATEGORÍAS
  // ───────────────────────────────────────────────────────

  Future<bool> createCategory(String name, {String? description}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created = await repository.createCategory(name, description: description);
      _categories = [..._categories, created];
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateCategory(int id, String name, {String? description}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await repository.updateCategory(id, name, description: description);
      final idx = _categories.indexWhere((c) => c.id == id);
      if (idx != -1) {
        final newList = List.of(_categories);
        newList[idx] = updated;
        _categories = newList;
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

  Future<bool> deleteCategory(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.deleteCategory(id);
      _categories.removeWhere((c) => c.id == id);
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
