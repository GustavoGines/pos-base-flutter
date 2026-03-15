import '../../domain/repositories/pos_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

class SearchProductsUseCase {
  final PosRepository repository;

  SearchProductsUseCase(this.repository);

  Future<List<Product>> call(String query) async {
    return await repository.searchProducts(query);
  }
}
