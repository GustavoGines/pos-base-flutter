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
}
