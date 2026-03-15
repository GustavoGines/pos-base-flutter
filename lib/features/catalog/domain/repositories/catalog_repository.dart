import '../entities/product.dart';
import '../entities/category.dart';

abstract class CatalogRepository {
  Future<List<Product>> getProducts();
  Future<List<Category>> getCategories();
}
