import '../entities/product.dart';
import '../entities/category.dart';

abstract class CatalogRepository {
  Future<List<Product>> getProducts();
  Future<List<Category>> getCategories();
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
