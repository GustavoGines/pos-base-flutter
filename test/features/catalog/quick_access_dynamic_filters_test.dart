import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/catalog/data/models/category_model.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';

class _FakeCatalogRepository extends Fake implements CatalogRepository {
  List<Category> fakeCategories = [];

  @override
  Future<List<Category>> getCategories() async => fakeCategories;

  @override
  Future<List<Brand>> getBrands() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGetProductsUseCase extends Fake implements GetProductsUseCase {
  final Map<String, dynamic> Function({
    int page,
    int? perPage,
    int? categoryId,
    bool? isSoldByWeight,
    List<int>? ids,
  }) handler;

  _FakeGetProductsUseCase(this.handler);

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
    return handler(
      page: page,
      perPage: perPage,
      categoryId: categoryId,
      isSoldByWeight: isSoldByWeight,
      ids: ids,
    );
  }
}

Product _makeProduct({
  required int id,
  required String name,
  required double stock,
  int? categoryId,
  bool isWeight = false,
}) {
  return ProductModel(
    id: id,
    name: name,
    internalCode: 'P-$id',
    costPrice: 50,
    sellingPrice: 100,
    stock: stock,
    active: true,
    isSoldByWeight: isWeight,
    category: categoryId != null ? CategoryModel(id: categoryId, name: 'Cat $categoryId') : null,
  );
}

void main() {
  test('CategoryModel.fromJson parses products_count correctly', () {
    final json = {
      'id': 128,
      'name': 'Xiaomi',
      'products_count': 17,
    };
    final model = CategoryModel.fromJson(json);
    expect(model.id, 128);
    expect(model.name, 'Xiaomi');
    expect(model.productsCount, 17);
  });

  group('CatalogProvider Quick Access Dynamic Filters', () {
    late _FakeCatalogRepository repo;
    late CatalogProvider provider;

    test('syncCategoryProducts trae del backend solo productos no cargados en _products', () async {
      repo = _FakeCatalogRepository();
      final useCase = _FakeGetProductsUseCase(({page = 1, perPage, categoryId, isSoldByWeight, ids}) {
        if (categoryId == 128) {
          return {
            'data': [
              _makeProduct(id: 1, name: 'Xiaomi En Memoria', stock: 10, categoryId: 128),
              _makeProduct(id: 2, name: 'Xiaomi Fuera de 500 A', stock: 5, categoryId: 128),
              _makeProduct(id: 3, name: 'Xiaomi Fuera de 500 B', stock: 8, categoryId: 128),
            ],
            'current_page': 1,
            'last_page': 1,
          };
        }
        return {
          'data': [_makeProduct(id: 1, name: 'Xiaomi En Memoria', stock: 10, categoryId: 128)],
          'current_page': 1,
          'last_page': 1,
        };
      });

      provider = CatalogProvider(getProductsUseCase: useCase, repository: repo);

      // Simular que el producto 1 ya estaba en el lote inicial de 500
      provider.deductStockLocallyForProductList([], {}); // no-op
      // Cargamos producto 1 en provider._products simulando loadProducts
      final initUseCase = _FakeGetProductsUseCase(({page = 1, perPage, categoryId, isSoldByWeight, ids}) => {
        'data': [_makeProduct(id: 1, name: 'Xiaomi En Memoria', stock: 10, categoryId: 128)],
        'current_page': 1,
        'last_page': 1,
      });
      final pWithInitial = CatalogProvider(getProductsUseCase: initUseCase, repository: repo);
      await pWithInitial.loadProducts(page: 1, perPage: 500);

      expect(pWithInitial.products.length, 1);
      expect(pWithInitial.products.first.id, 1);

      // Sincronizar categoría 128 con el usecase que retorna los 3
      final customProvider = CatalogProvider(getProductsUseCase: useCase, repository: repo);
      await customProvider.loadProducts(page: 1, perPage: 500); // carga prod 1

      await customProvider.syncCategoryProducts(128);

      final extras = customProvider.getCategoryExtraProducts(128);
      // Debe contener id: 2 y 3, pero NO el 1 porque ya estaba en _products
      expect(extras.map((p) => p.id).toList(), equals([2, 3]));
    });

    test('syncWeightProducts trae del backend productos pesables fuera del bloque inicial', () async {
      repo = _FakeCatalogRepository();
      final useCase = _FakeGetProductsUseCase(({page = 1, perPage, categoryId, isSoldByWeight, ids}) {
        if (isSoldByWeight == true) {
          return {
            'data': [
              _makeProduct(id: 10, name: 'Queso Memoria', stock: 5, isWeight: true),
              _makeProduct(id: 20, name: 'Jamon Fuera de 500', stock: 3, isWeight: true),
            ],
            'current_page': 1,
            'last_page': 1,
          };
        }
        return {
          'data': [_makeProduct(id: 10, name: 'Queso Memoria', stock: 5, isWeight: true)],
          'current_page': 1,
          'last_page': 1,
        };
      });

      provider = CatalogProvider(getProductsUseCase: useCase, repository: repo);
      await provider.loadProducts(page: 1, perPage: 500);

      await provider.syncWeightProducts();

      expect(provider.weightOnlyProducts.length, 1);
      expect(provider.weightOnlyProducts.first.id, 20);
    });

    test('syncPinnedProducts trae productos fijados faltantes por IDs', () async {
      repo = _FakeCatalogRepository();
      final useCase = _FakeGetProductsUseCase(({page = 1, perPage, categoryId, isSoldByWeight, ids}) {
        if (ids != null && ids.contains(99)) {
          return {
            'data': [_makeProduct(id: 99, name: 'Fijado Remoto', stock: 15)],
            'current_page': 1,
            'last_page': 1,
          };
        }
        return {'data': <Product>[], 'current_page': 1, 'last_page': 1};
      });

      provider = CatalogProvider(getProductsUseCase: useCase, repository: repo);
      await provider.syncPinnedProducts({99});

      expect(provider.pinnedExtraProducts.length, 1);
      expect(provider.pinnedExtraProducts.first.id, 99);
    });

    test('applyImmediateLocalStockDeduction descuenta stock en caliente en _products, categorías, peso y fijados', () async {
      repo = _FakeCatalogRepository();
      final useCase = _FakeGetProductsUseCase(({page = 1, perPage, categoryId, isSoldByWeight, ids}) {
        if (categoryId == 128) {
          return {
            'data': [_makeProduct(id: 2, name: 'Xiaomi Extra', stock: 10, categoryId: 128)],
            'current_page': 1,
            'last_page': 1,
          };
        }
        if (isSoldByWeight == true) {
          return {
            'data': [_makeProduct(id: 3, name: 'Queso Extra', stock: 5.0, isWeight: true)],
            'current_page': 1,
            'last_page': 1,
          };
        }
        if (ids != null) {
          return {
            'data': [_makeProduct(id: 4, name: 'Fijado Extra', stock: 7)],
            'current_page': 1,
            'last_page': 1,
          };
        }
        return {
          'data': [_makeProduct(id: 1, name: 'Prod Memoria', stock: 20)],
          'current_page': 1,
          'last_page': 1,
        };
      });

      provider = CatalogProvider(getProductsUseCase: useCase, repository: repo);
      await provider.loadProducts(page: 1, perPage: 500); // Carga prod 1 con stock 20
      await provider.syncCategoryProducts(128); // Carga prod 2 con stock 10
      await provider.syncWeightProducts(); // Carga prod 3 con stock 5.0
      await provider.syncPinnedProducts({4}); // Carga prod 4 con stock 7

      // Descontamos en caliente por venta
      provider.applyImmediateLocalStockDeduction({
        1: 2.0, // 20 - 2 = 18
        2: 3.0, // 10 - 3 = 7
        3: 1.5, // 5.0 - 1.5 = 3.5
        4: 2.0, // 7 - 2 = 5
      });

      expect(provider.products.first.stock, 18.0);
      expect(provider.getCategoryExtraProducts(128).first.stock, 7.0);
      expect(provider.weightOnlyProducts.first.stock, 3.5);
      expect(provider.pinnedExtraProducts.first.stock, 5.0);
    });

    test('invalidateQuickAccessExtraCaches limpia todas las colecciones extra', () async {
      repo = _FakeCatalogRepository();
      final useCase = _FakeGetProductsUseCase(({page = 1, perPage, categoryId, isSoldByWeight, ids}) => {
        'data': [_makeProduct(id: 99, name: 'P', stock: 1)],
        'current_page': 1,
        'last_page': 1,
      });

      provider = CatalogProvider(getProductsUseCase: useCase, repository: repo);
      await provider.syncPinnedProducts({99});
      expect(provider.pinnedExtraProducts.length, 1);

      provider.invalidateQuickAccessExtraCaches();
      expect(provider.pinnedExtraProducts.isEmpty, isTrue);
      expect(provider.weightOnlyProducts.isEmpty, isTrue);
      expect(provider.getCategoryExtraProducts(128).isEmpty, isTrue);
    });
  });
}
