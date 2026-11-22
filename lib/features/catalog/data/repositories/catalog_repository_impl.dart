import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/brand.dart';
import '../../domain/entities/rubro.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../datasources/catalog_remote_datasource.dart';
import '../models/product_batch_model.dart';
import '../models/production_order_model.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  final CatalogRemoteDataSource remoteDataSource;

  CatalogRepositoryImpl({required this.remoteDataSource});

  @override
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
  }) async {
    return await remoteDataSource.fetchProducts(
      page: page,
      search: search,
      sortBy: sortBy,
      sortDirection: sortDirection,
      perPage: perPage,
      categoryId: categoryId,
      brandId: brandId,
      supplierId: supplierId,
      active: active,
    );
  }

  @override
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
  }) async {
    return await remoteDataSource.fetchProducts(
      page: page,
      search: search,
      sortBy: sortBy,
      sortDirection: sortDirection,
      perPage: perPage,
      categoryId: categoryId,
      brandId: brandId,
      supplierId: supplierId,
      active: active,
      isSoldByWeight: isSoldByWeight,
      ids: ids,
    );
  }

  @override
  Future<List<Category>> getCategories() async {
    return await remoteDataSource.fetchCategories();
  }

  @override
  Future<List<Rubro>> getRubros() async {
    return await remoteDataSource.fetchRubros();
  }

  @override
  Future<Rubro> createRubro(String name, {String? description}) async {
    return await remoteDataSource.createRubro(name, description: description);
  }

  @override
  Future<Rubro> updateRubro(int id, String name, {String? description}) async {
    return await remoteDataSource.updateRubro(id, name, description: description);
  }

  @override
  Future<void> deleteRubro(int id) async {
    return await remoteDataSource.deleteRubro(id);
  }

  @override
  Future<List<Brand>> getBrands() async {
    return await remoteDataSource.fetchBrands();
  }

  @override
  Future<Brand> createBrand(String name, {String? description}) async {
    return await remoteDataSource.createBrand(name, description: description);
  }

  @override
  Future<Brand> updateBrand(int id, String name, {String? description}) async {
    return await remoteDataSource.updateBrand(id, name, description: description);
  }

  @override
  Future<void> deleteBrand(int id) async {
    return await remoteDataSource.deleteBrand(id);
  }

  @override
  Future<Category> createCategory(String name, {String? description, int? rubroId}) async {
    return await remoteDataSource.createCategory(name, description: description, rubroId: rubroId);
  }

  @override
  Future<Category> updateCategory(int id, String name, {String? description, int? rubroId}) async {
    return await remoteDataSource.updateCategory(id, name, description: description, rubroId: rubroId);
  }

  @override
  Future<void> deleteCategory(int id) async {
    return await remoteDataSource.deleteCategory(id);
  }

  @override
  Future<Product> createProduct(Map<String, dynamic> productData) async {
    return await remoteDataSource.createProduct(productData);
  }

  @override
  Future<Product> updateProduct(int id, Map<String, dynamic> productData) async {
    return await remoteDataSource.updateProduct(id, productData);
  }

  @override
  Future<void> deleteProduct(int id) async {
    return await remoteDataSource.deleteProduct(id);
  }

  @override
  Future<Map<String, dynamic>> bulkDeleteProducts(List<int> ids) async {
    return await remoteDataSource.bulkDeleteProducts(ids);
  }

  @override
  Future<Map<String, dynamic>> bulkUpdateProducts(
    List<int> ids, {
    int? categoryId,
    bool clearCategory = false,
    int? brandId,
    bool clearBrand = false,
    bool? active,
    int? supplierId,
    bool clearSupplier = false,
  }) async {
    return await remoteDataSource.bulkUpdateProducts(
      ids,
      categoryId: categoryId,
      clearCategory: clearCategory,
      brandId: brandId,
      clearBrand: clearBrand,
      active: active,
      supplierId: supplierId,
      clearSupplier: clearSupplier,
    );
  }

  @override
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  }) async {
    return await remoteDataSource.bulkPriceUpdate(
      percentage: percentage,
      roundingRule: roundingRule,
      targetField: targetField,
      productIds: productIds,
      categoryId: categoryId,
      brandId: brandId,
      supplierId: supplierId,
    );
  }

  @override
  Future<Map<String, dynamic>> bulkPricePreview({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  }) async {
    return await remoteDataSource.bulkPricePreview(
      percentage: percentage,
      roundingRule: roundingRule,
      targetField: targetField,
      productIds: productIds,
      categoryId: categoryId,
      brandId: brandId,
      supplierId: supplierId,
    );
  }

  @override
  Future<List<dynamic>> getBulkPriceHistory() async {
    return await remoteDataSource.getBulkPriceHistory();
  }

  @override
  Future<String> revertBulkPrice(int historyId) async {
    return await remoteDataSource.revertBulkPrice(historyId);
  }

  @override
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
  }) async {
    return await remoteDataSource.adjustStock(
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
  }

  @override
  Future<ProductBatchesResponse> fetchProductBatches(
    int productId, {
    bool includeClosed = true,
  }) async {
    return await remoteDataSource.fetchProductBatches(
      productId,
      includeClosed: includeClosed,
    );
  }

  @override
  Future<Map<String, dynamic>> createProductBatch(
    int productId, {
    required double quantity,
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  }) async {
    return await remoteDataSource.createProductBatch(
      productId,
      quantity: quantity,
      batchCode: batchCode,
      manufacturedAt: manufacturedAt,
      expirationDate: expirationDate,
      unitCost: unitCost,
      notes: notes,
    );
  }

  @override
  Future<Map<String, dynamic>> updateProductBatch(
    int batchId, {
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  }) async {
    return await remoteDataSource.updateProductBatch(
      batchId,
      batchCode: batchCode,
      manufacturedAt: manufacturedAt,
      expirationDate: expirationDate,
      unitCost: unitCost,
      notes: notes,
    );
  }

  @override
  Future<Map<String, dynamic>> writeOffBatch(
    int batchId, {
    double? quantity,
    String? notes,
  }) async {
    return await remoteDataSource.writeOffBatch(
      batchId,
      quantity: quantity,
      notes: notes,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchExpiredBatches({bool includeToday = true}) async {
    return await remoteDataSource.fetchExpiredBatches(includeToday: includeToday);
  }

  @override
  Future<Map<String, dynamic>> splitBatch(
    int batchId, {
    required double quantity,
    String? expirationDate,
    String? batchCode,
    String? notes,
  }) async {
    return await remoteDataSource.splitBatch(
      batchId,
      quantity: quantity,
      expirationDate: expirationDate,
      batchCode: batchCode,
      notes: notes,
    );
  }

  @override
  Future<Map<String, dynamic>> writeOffExpiredBatches({
    List<Map<String, dynamic>>? items,
    bool includeToday = true,
    String? notes,
  }) async {
    return await remoteDataSource.writeOffExpiredBatches(
      items: items,
      includeToday: includeToday,
      notes: notes,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchProductionOrders({
    int page = 1,
    int? productId,
    String? status,
    String? search,
  }) async {
    return await remoteDataSource.fetchProductionOrders(
      page: page,
      productId: productId,
      status: status,
      search: search,
    );
  }

  @override
  Future<ProductionOrderModel> createProductionOrder(Map<String, dynamic> payload) async {
    return await remoteDataSource.createProductionOrder(payload);
  }

  @override
  Future<Map<String, dynamic>> createBatchProductionOrders(Map<String, dynamic> payload) async {
    return await remoteDataSource.createBatchProductionOrders(payload);
  }

  @override
  Future<ProductionOrderModel> voidProductionOrder(int orderId) async {
    return await remoteDataSource.voidProductionOrder(orderId);
  }

  @override
  Future<Map<String, dynamic>> fetchWasteReport({
    String? startDate,
    String? endDate,
  }) async {
    return await remoteDataSource.fetchWasteReport(
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  Future<List<Product>> fetchCriticalAlerts() async {
    return await remoteDataSource.fetchCriticalAlerts();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBulkStock(List<int> ids) async {
    return await remoteDataSource.fetchBulkStock(ids);
  }

  @override
  Future<String> uploadProductImage(int productId, String filePath, {List<int>? bytes, String? filename}) async {
    return await remoteDataSource.uploadProductImage(productId, filePath, bytes: bytes, filename: filename);
  }

  @override
  Future<void> deleteProductImage(int productId) async {
    return await remoteDataSource.deleteProductImage(productId);
  }

  @override
  Future<Map<String, dynamic>> importProducts(List<int> fileBytes, String filename) async {
    return await remoteDataSource.importProducts(fileBytes, filename);
  }

  @override
  Future<Product> updateProductCalcConfig(
    int productId,
    Map<String, dynamic>? calcConfig,
  ) async {
    return await remoteDataSource.updateProductCalcConfig(productId, calcConfig);
  }
}
