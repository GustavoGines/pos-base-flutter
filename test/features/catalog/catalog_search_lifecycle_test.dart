import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';

class MockCatalogRepository implements CatalogRepository {
  String? lastSearchReceived;
  int lastPageReceived = 1;

  @override
  Future<Map<String, dynamic>> getProducts({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
  }) async {
    lastPageReceived = page;
    lastSearchReceived = search;

    final allMockProducts = [
      Product(
        id: 1,
        name: 'Celular Xiaomi 17T Pro',
        internalCode: 'XIAOMI-17T',
        costPrice: 100000,
        sellingPrice: 150000,
        stock: 5,
        active: true,
        isSoldByWeight: false,
      ),
      Product(
        id: 2,
        name: 'Smart TV Samsung 55',
        internalCode: 'SAMS-55',
        costPrice: 250000,
        sellingPrice: 350000,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      ),
    ];

    final filtered = search != null && search.isNotEmpty
        ? allMockProducts.where((p) => p.name.toLowerCase().contains(search.toLowerCase())).toList()
        : allMockProducts;

    return {
      'data': filtered,
      'current_page': page,
      'last_page': 1,
      'total': filtered.length,
    };
  }

  @override
  Future<List<Category>> getCategories() async => [];

  @override
  Future<List<Brand>> getBrands() async => [];

  @override
  Future<List<Rubro>> getRubros() async => [];

  @override
  Future<Map<String, dynamic>> importProducts(List<int> fileBytes, String filename) async {
    return {'message': 'Import successful', 'imported': 2};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockCatalogRepository mockRepo;
  late GetProductsUseCase getProductsUseCase;
  late CatalogProvider provider;

  setUp(() {
    mockRepo = MockCatalogRepository();
    getProductsUseCase = GetProductsUseCase(mockRepo);
    provider = CatalogProvider(
      getProductsUseCase: getProductsUseCase,
      repository: mockRepo,
    );
  });

  group('CatalogProvider Search Lifecycle & State Isolation Tests', () {
    test('Initial state has empty searchQuery and fetches all products without search filter', () async {
      expect(provider.searchQuery, '');

      await provider.loadProducts(page: 1);

      expect(mockRepo.lastSearchReceived, isNull);
      expect(provider.products.length, 2);
      expect(provider.searchQuery, '');
    });

    test('Searching updates searchQuery and filters products to matched item', () async {
      await provider.loadProducts(page: 1, search: 'Xiaomi');

      expect(provider.searchQuery, 'Xiaomi');
      expect(mockRepo.lastSearchReceived, 'Xiaomi');
      expect(provider.products.length, 1);
      expect(provider.products.first.name, 'Celular Xiaomi 17T Pro');
    });

    test('Reloading with explicit search: "" resets searchQuery and retrieves all products', () async {
      // 1. Perform a search
      await provider.loadProducts(page: 1, search: 'Xiaomi');
      expect(provider.products.length, 1);

      // 2. Simulating CatalogScreen re-entering or refresh with cleared search
      await provider.loadProducts(page: 1, search: '');

      expect(provider.searchQuery, '');
      expect(mockRepo.lastSearchReceived, isNull);
      expect(provider.products.length, 2);
    });

    test('clearSearch() resets the query state', () async {
      await provider.loadProducts(page: 1, search: 'Samsung');
      expect(provider.searchQuery, 'Samsung');

      provider.clearSearch();
      expect(provider.searchQuery, '');
    });

    test('Pagination preserves active search query when search argument is omitted (null)', () async {
      // 1. Search first
      await provider.loadProducts(page: 1, search: 'Xiaomi');
      expect(provider.searchQuery, 'Xiaomi');

      // 2. Paginate to page 2 without passing search
      await provider.loadProducts(page: 2);

      expect(mockRepo.lastPageReceived, 2);
      expect(mockRepo.lastSearchReceived, 'Xiaomi');
      expect(provider.searchQuery, 'Xiaomi');
    });

    test('importProducts resets search query to empty string and reloads all products', () async {
      // 1. Set a pre-existing search filter
      await provider.loadProducts(page: 1, search: 'Xiaomi');
      expect(provider.searchQuery, 'Xiaomi');
      expect(provider.products.length, 1);

      // 2. Execute import
      await provider.importProducts(fileBytes: [1, 2, 3], filename: 'catalog.xlsx');

      // 3. Search query must be cleared and all products returned
      expect(provider.searchQuery, '');
      expect(mockRepo.lastSearchReceived, isNull);
      expect(provider.products.length, 2);
    });
  });

  group('CatalogProvider.searchProductsRemote (picker de Ofertas)', () {
    test('Consulta al servidor aunque el producto NO esté cargado en memoria', () async {
      // Memoria local: solo Samsung (simula la página cargada del POS)
      await provider.loadProducts(page: 1, search: 'Samsung');
      expect(provider.products.length, 1);

      final results = await provider.searchProductsRemote('Xiaomi');

      expect(mockRepo.lastSearchReceived, 'Xiaomi');
      expect(results.length, 1);
      expect(results.first.name, 'Celular Xiaomi 17T Pro');
    });

    test('NO altera products, searchQuery ni la paginación del catálogo', () async {
      await provider.loadProducts(page: 1, search: 'Samsung');

      await provider.searchProductsRemote('Xiaomi');

      expect(provider.searchQuery, 'Samsung');
      expect(provider.products.length, 1);
      expect(provider.products.first.name, 'Smart TV Samsung 55');
    });

    test('Query vacía o en blanco devuelve lista vacía sin llamar al servidor', () async {
      final results = await provider.searchProductsRemote('   ');

      expect(results, isEmpty);
      expect(mockRepo.lastSearchReceived, isNull);
    });
  });
}
