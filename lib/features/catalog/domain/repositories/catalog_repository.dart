import '../entities/product.dart';
import '../entities/category.dart';

abstract class CatalogRepository {
  /// Returns {data: List<Product>, current_page: int, last_page: int}
  Future<Map<String, dynamic>> getProducts({int page = 1, String? search, String? sortBy, String? sortDirection});
  Future<List<Category>> getCategories();
  // Category CRUD
  Future<Category> createCategory(String name, {String? description});
  Future<Category> updateCategory(int id, String name, {String? description});
  Future<void> deleteCategory(int id);
  // Product CRUD
  Future<Product> createProduct(Map<String, dynamic> productData);
  Future<Product> updateProduct(int id, Map<String, dynamic> productData);
  Future<void> deleteProduct(int id);
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    int? categoryId,
    int? brandId,
  });
  Future<Map<String, dynamic>> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    String? notes,
  });
}
