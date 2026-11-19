import '../entities/product.dart';
import '../entities/category.dart';
import '../entities/brand.dart';
import '../entities/rubro.dart';
import '../../data/models/product_batch_model.dart';
import '../../data/models/production_order_model.dart';

abstract class CatalogRepository {
  /// Returns {data: `List<Product>`, current_page: int, last_page: int}
  Future<Map<String, dynamic>> getProducts({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
    int? categoryId,
    int? brandId,
    int? supplierId,
    bool? active,
  });
  Future<Map<String, dynamic>> getProductsAdvanced({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
    int? categoryId,
    int? brandId,
    int? supplierId,
    bool? active,
    bool? isSoldByWeight,
    List<int>? ids,
  });
  Future<List<Category>> getCategories();
  // Rubro CRUD
  Future<List<Rubro>> getRubros();
  Future<Rubro> createRubro(String name, {String? description});
  Future<Rubro> updateRubro(int id, String name, {String? description});
  Future<void> deleteRubro(int id);
  // Brand CRUD
  Future<List<Brand>> getBrands();
  Future<Brand> createBrand(String name, {String? description});
  Future<Brand> updateBrand(int id, String name, {String? description});
  Future<void> deleteBrand(int id);
  // Category CRUD
  Future<Category> createCategory(String name, {String? description, int? rubroId});
  Future<Category> updateCategory(int id, String name, {String? description, int? rubroId});
  Future<void> deleteCategory(int id);
  // Product CRUD
  Future<Product> createProduct(Map<String, dynamic> productData);
  Future<Product> updateProduct(int id, Map<String, dynamic> productData);
  Future<Map<String, dynamic>> importProducts(List<int> fileBytes, String filename);
  Future<void> deleteProduct(int id);
  Future<Map<String, dynamic>> bulkDeleteProducts(List<int> ids);
  Future<Map<String, dynamic>> bulkUpdateProducts(
    List<int> ids, {
    int? categoryId,
    bool clearCategory = false,
    int? brandId,
    bool clearBrand = false,
    bool? active,
    int? supplierId,
    bool clearSupplier = false,
  });
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  });

  Future<Map<String, dynamic>> bulkPricePreview({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  });

  Future<List<dynamic>> getBulkPriceHistory();
  Future<String> revertBulkPrice(int historyId);
  Future<Map<String, dynamic>> adjustStock({
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
  });
  Future<ProductBatchesResponse> fetchProductBatches(
    int productId, {
    bool includeClosed = true,
  });
  Future<Map<String, dynamic>> createProductBatch(
    int productId, {
    required double quantity,
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  });
  Future<Map<String, dynamic>> updateProductBatch(
    int batchId, {
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  });
  Future<Map<String, dynamic>> writeOffBatch(
    int batchId, {
    double? quantity,
    String? notes,
  });
  Future<Map<String, dynamic>> fetchExpiredBatches({bool includeToday = true});
  Future<Map<String, dynamic>> splitBatch(
    int batchId, {
    required double quantity,
    String? expirationDate,
    String? batchCode,
    String? notes,
  });
  Future<Map<String, dynamic>> writeOffExpiredBatches({
    List<Map<String, dynamic>>? items,
    bool includeToday = true,
    String? notes,
  });
  Future<Map<String, dynamic>> fetchProductionOrders({
    int page = 1,
    int? productId,
    String? status,
    String? search,
  });
  Future<ProductionOrderModel> createProductionOrder(Map<String, dynamic> payload);
  Future<Map<String, dynamic>> createBatchProductionOrders(Map<String, dynamic> payload);
  Future<ProductionOrderModel> voidProductionOrder(int orderId);
  Future<Map<String, dynamic>> fetchWasteReport({
    String? startDate,
    String? endDate,
  });
  Future<List<Product>> fetchCriticalAlerts();
  /// Fetches only {id, stock} for the given IDs. Avoids a full catalog reload post-sale.
  Future<List<Map<String, dynamic>>> fetchBulkStock(List<int> ids);
  Future<String> uploadProductImage(int productId, String filePath, {List<int>? bytes, String? filename});
  Future<void> deleteProductImage(int productId);
}
