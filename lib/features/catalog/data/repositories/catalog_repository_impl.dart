import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../datasources/catalog_remote_datasource.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  final CatalogRemoteDataSource remoteDataSource;

  CatalogRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Map<String, dynamic>> getProducts({int page = 1, String? search, String? sortBy, String? sortDirection}) async {
    return await remoteDataSource.fetchProducts(page: page, search: search, sortBy: sortBy, sortDirection: sortDirection);
  }

  @override
  Future<List<Category>> getCategories() async {
    return await remoteDataSource.fetchCategories();
  }

  @override
  Future<Category> createCategory(String name, {String? description}) async {
    return await remoteDataSource.createCategory(name, description: description);
  }

  @override
  Future<Category> updateCategory(int id, String name, {String? description}) async {
    return await remoteDataSource.updateCategory(id, name, description: description);
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
  Future<Map<String, dynamic>> bulkUpdateProducts(List<int> ids, {int? categoryId, bool? active}) async {
    return await remoteDataSource.bulkUpdateProducts(ids, categoryId: categoryId, active: active);
  }

  @override
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
  }) async {
    return await remoteDataSource.bulkPriceUpdate(
      percentage: percentage,
      productIds: productIds,
      categoryId: categoryId,
      brandId: brandId,
    );
  }

  @override
  Future<Map<String, dynamic>> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    String? notes,
  }) async {
    return await remoteDataSource.adjustStock(
      productId: productId,
      type: type,
      quantity: quantity,
      notes: notes,
    );
  }
}
