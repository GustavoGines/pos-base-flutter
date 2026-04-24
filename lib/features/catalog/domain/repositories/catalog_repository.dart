import '../entities/product.dart';
import '../entities/category.dart';
import '../entities/brand.dart';

abstract class CatalogRepository {
  /// Returns {data: List<Product>, current_page: int, last_page: int}
  Future<Map<String, dynamic>> getProducts({int page = 1, String? search, String? sortBy, String? sortDirection, int? perPage});
  Future<List<Category>> getCategories();
  // Brand CRUD
  Future<List<Brand>> getBrands();
  Future<Brand> createBrand(String name, {String? description});
  Future<Brand> updateBrand(int id, String name, {String? description});
  Future<void> deleteBrand(int id);
  // Category CRUD
  Future<Category> createCategory(String name, {String? description});
  Future<Category> updateCategory(int id, String name, {String? description});
  Future<void> deleteCategory(int id);
  // Product CRUD
  Future<Product> createProduct(Map<String, dynamic> productData);
  Future<Product> updateProduct(int id, Map<String, dynamic> productData);
  Future<void> deleteProduct(int id);
  Future<Map<String, dynamic>> bulkDeleteProducts(List<int> ids);
  Future<Map<String, dynamic>> bulkUpdateProducts(List<int> ids, {int? categoryId, bool? active});
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
  });
  Future<Map<String, dynamic>> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    double? minStock,
    String? notes,
  });
  Future<List<Product>> fetchCriticalAlerts();
  /// Fetches only {id, stock} for the given IDs. Avoids a full catalog reload post-sale.
  Future<List<Map<String, dynamic>>> fetchBulkStock(List<int> ids);
}
