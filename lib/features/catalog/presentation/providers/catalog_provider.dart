import 'package:flutter/material.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../../domain/usecases/get_products_usecase.dart';

class CatalogProvider with ChangeNotifier {
  final GetProductsUseCase getProductsUseCase;
  final CatalogRepository repository;

  List<Product> _products = [];
  List<Product> get products => _products;

  List<Category> _categories = [];
  List<Category> get categories => _categories;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CatalogProvider({required this.getProductsUseCase, required this.repository});

  Future<void> loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _products = await getProductsUseCase();
      _categories = await repository.getCategories();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  Future<String?> bulkPriceUpdate({
    required double percentage,
    int? categoryId,
    int? brandId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.bulkPriceUpdate(
        percentage: percentage,
        categoryId: categoryId,
        brandId: brandId,
      );
      // Reload products to reflect new prices
      _products = await getProductsUseCase();
      return result['message'] as String?;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Ajuste manual de stock (entrada o salida de mercadería).
  /// Actualiza el stock localmente usando `new_stock` devuelto por el backend.
  Future<bool> adjustStock({
    required int productId,
    required String type,
    required double quantity,
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
        notes: notes,
      );
      // Actualizar el stock en la lista local sin tener que recargar toda la lista
      final newStock = double.parse(result['new_stock'].toString());
      final idx = _products.indexWhere((p) => p.id == productId);
      if (idx != -1) {
        _products[idx] = _products[idx].copyWithStock(newStock);
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

  /// Crea una nueva categoría y la agrega a la lista local.
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

  /// Edita el nombre (y descripción) de una categoría existente.
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

  /// Elimina una categoría. El backend rechaza con 422 si tiene productos.
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
