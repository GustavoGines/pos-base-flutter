import '../../domain/entities/product.dart';
import '../../domain/repositories/catalog_repository.dart';

class GetProductsUseCase {
  final CatalogRepository repository;

  GetProductsUseCase(this.repository);

  Future<List<Product>> call() async {
    return await repository.getProducts();
  }
}
