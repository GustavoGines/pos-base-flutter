import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/catalog/data/models/category_model.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';

class _FakeCatalogRepo extends Fake implements CatalogRepository {
  @override
  Future<List<Category>> getCategories() async => const [];

  @override
  Future<List<Brand>> getBrands() async => const [];

  @override
  Future<List<Rubro>> getRubros() async => const [];
}

class _FakeGetProductsUseCase extends Fake implements GetProductsUseCase {
  final List<Product> products;

  _FakeGetProductsUseCase(this.products);

  @override
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
    bool? isSoldByWeight,
    List<int>? ids,
  }) async {
    Iterable<Product> filtered = products;
    if (active != null) {
      filtered = filtered.where((p) => p.active == active);
    }
    if (categoryId != null) {
      filtered = filtered.where((p) => p.category?.id == categoryId);
    }
    if (isSoldByWeight != null) {
      filtered = filtered.where((p) => p.isSoldByWeight == isSoldByWeight);
    }
    if (ids != null) {
      final idSet = ids.toSet();
      filtered = filtered.where((p) => idSet.contains(p.id));
    }
    return {
      'data': filtered.toList(),
      'current_page': 1,
      'last_page': 1,
    };
  }
}

ProductModel _buildProduct({
  required int id,
  required String name,
  required bool active,
  bool isWeight = false,
  int? categoryId,
}) {
  return ProductModel(
    id: id,
    name: name,
    internalCode: 'HW$id',
    costPrice: 100,
    sellingPrice: 150,
    stock: 20,
    active: active,
    isSoldByWeight: isWeight,
    category: categoryId != null
        ? CategoryModel(id: categoryId, name: 'Cat $categoryId')
        : null,
  );
}

void main() {
  group('CatalogProvider.activeProducts (Productos Inactivos)', () {
    test('activeProducts excluye productos con active=false mientras products los conserva para administración', () async {
      final items = [
        _buildProduct(id: 1, name: 'Machimbre Pino 1/2', active: true, categoryId: 10),
        _buildProduct(id: 2, name: 'Empanadas de Carne x12', active: false, categoryId: 20),
        _buildProduct(id: 3, name: 'Chapa C27 4.5m', active: true, categoryId: 10),
        _buildProduct(id: 4, name: 'Pollo al Spiedo', active: false, categoryId: 20),
      ];
      final provider = CatalogProvider(
        getProductsUseCase: _FakeGetProductsUseCase(items),
        repository: _FakeCatalogRepo(),
      );

      await provider.loadProducts(page: 1, perPage: 500);

      expect(provider.products.length, 4);
      expect(provider.activeProducts.length, 2);
      expect(provider.activeProducts.map((p) => p.id), [1, 3]);
      expect(provider.activeProducts.every((p) => p.active), isTrue);
    });

    test('pinnedExtraProducts filtra productos inactivos traídos por IDs fijados', () async {
      final items = [
        _buildProduct(id: 10, name: 'Fijado Activo', active: true),
        _buildProduct(id: 11, name: 'Fijado Dado de Baja', active: false),
      ];
      final useCase = _FakeGetProductsUseCase(items);
      final provider = CatalogProvider(
        getProductsUseCase: useCase,
        repository: _FakeCatalogRepo(),
      );

      await provider.syncPinnedProducts({10, 11});

      expect(provider.pinnedExtraProducts.map((p) => p.id), [10]);
    });
  });

  group('LocalTerminalProvider Historial de Búsquedas POS', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Filtro anti-basura rechaza códigos cortos, numéricos largos y etiquetas internas', () {
      // Inválidos / basura
      expect(LocalTerminalProvider.isValidRecentSearchTerm(''), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm(' '), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('a'), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('1'), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('12345'), isFalse); // 5 dígitos
      expect(LocalTerminalProvider.isValidRecentSearchTerm('77912345'), isFalse); // EAN-8
      expect(LocalTerminalProvider.isValidRecentSearchTerm('7791234567890'), isFalse); // EAN-13
      expect(LocalTerminalProvider.isValidRecentSearchTerm('L#42'), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('L#42#W#500'), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('PRES-0012'), isFalse);

      // Válidos
      expect(LocalTerminalProvider.isValidRecentSearchTerm('T2'), isTrue);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('Machimbre'), isTrue);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('Chapa C27'), isTrue);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('HW101'), isTrue);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('101'), isTrue); // <5 dígitos alfanum/PLU corto
    });

    test('recordRecentSearch respeta MRU, deduplicación case-insensitive, límites y limpieza', () async {
      final provider = LocalTerminalProvider();
      await Future<void>.delayed(Duration.zero);

      // Grabar 10 términos válidos -> solo deben quedar los últimos 8 en orden MRU
      for (int i = 1; i <= 10; i++) {
        await provider.recordRecentSearch(term: 'Termino $i', selectedProductId: i);
      }

      expect(provider.recentSearchTerms.length, LocalTerminalProvider.maxRecentSearchTerms);
      expect(provider.recentSearchTerms.first, 'Termino 10');
      expect(provider.recentSearchTerms.last, 'Termino 3');

      expect(provider.recentSearchProductIds.length, LocalTerminalProvider.maxRecentSearchProducts);
      expect(provider.recentSearchProductIds, [10, 9, 8, 7, 6]);

      // Deduplicación case-insensitive mueve al primer lugar con nuevo casing
      await provider.recordRecentSearch(term: 'termino 5', selectedProductId: 7);
      expect(provider.recentSearchTerms.first, 'termino 5');
      expect(
        provider.recentSearchTerms.where((t) => t.toLowerCase() == 'termino 5').length,
        1,
      );
      expect(provider.recentSearchProductIds.first, 7);

      // Basura no se registra ni altera el historial
      await provider.recordRecentSearch(term: '7790001234567');
      await provider.recordRecentSearch(term: 'x');
      expect(provider.recentSearchTerms.first, 'termino 5');

      // Eliminar un término y un producto puntualmente
      await provider.removeRecentSearchTerm('termino 5');
      expect(provider.recentSearchTerms.contains('termino 5'), isFalse);

      await provider.removeRecentSearchProductId(7);
      expect(provider.recentSearchProductIds.contains(7), isFalse);

      // Verificar persistencia recargando nuevo provider desde SharedPreferences
      final reloaded = LocalTerminalProvider();
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.recentSearchTerms, provider.recentSearchTerms);
      expect(reloaded.recentSearchProductIds, provider.recentSearchProductIds);

      // Limpiar todo
      await provider.clearRecentSearches();
      expect(provider.recentSearchTerms, isEmpty);
      expect(provider.recentSearchProductIds, isEmpty);
    });
  });
}
