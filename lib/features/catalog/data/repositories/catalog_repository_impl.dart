import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../datasources/catalog_remote_datasource.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  final CatalogRemoteDataSource remoteDataSource;

  CatalogRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<Product>> getProducts() async {
    return await remoteDataSource.fetchProducts();
  }

  @override
  Future<List<Category>> getCategories() async {
    return await remoteDataSource.fetchCategories();
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
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    int? categoryId,
    int? brandId,
  }) async {
    return await remoteDataSource.bulkPriceUpdate(
      percentage: percentage,
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
