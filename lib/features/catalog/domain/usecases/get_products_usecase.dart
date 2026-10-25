import '../repositories/catalog_repository.dart';

class GetProductsUseCase {
  final CatalogRepository repository;

  GetProductsUseCase(this.repository);

  /// Returns {data: `List<Product>`, current_page: int, last_page: int}
  Future<Map<String, dynamic>> call({
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
    return await repository.getProducts(
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
}
