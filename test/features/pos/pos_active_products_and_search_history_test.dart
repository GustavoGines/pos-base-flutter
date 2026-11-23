import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/presentation/widgets/pos_search_history_popover.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/data/models/category_model.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/domain/repositories/pos_repository.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/pages/pos_screen.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/checkout_dialog.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

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
  final bool ignoreIdsFilter;
  final List<Product> v185PageOneProducts;

  _FakeGetProductsUseCase(
    this.products, {
    this.ignoreIdsFilter = false,
    this.v185PageOneProducts = const [],
  });

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
    if (ignoreIdsFilter && ids != null) {
      return {
        'data': List<Product>.from(v185PageOneProducts),
        'current_page': 1,
        'last_page': 1,
      };
    }
    Iterable<Product> filtered = products;
    if (active != null) {
      filtered = filtered.where((p) => p.active == active);
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      filtered = filtered.where((p) =>
          p.name.toLowerCase().contains(q) ||
          p.internalCode.toLowerCase().contains(q));
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
    } else if (search == null || search.trim().isEmpty) {
      filtered = filtered.where((p) => p.id < 500);
    }
    return {
      'data': filtered.toList(),
      'current_page': 1,
      'last_page': 1,
    };
  }
}

class _BareFakeLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosSettingsProvider extends ChangeNotifier implements SettingsProvider {
  static const BusinessSettings _settings = BusinessSettings(
    companyName: 'Test Ferretería',
    enableAdvancedPriceTiers: false,
    features: FeatureFlags(fastPos: true, multiplePrices: false),
  );

  @override
  BusinessSettings? get settings => _settings;

  @override
  FeatureFlags get features => _settings.features;

  @override
  int get assignedRegisterId => 1;

  @override
  bool get isHardwareStore => false;

  @override
  bool get isIibbPerceptionAgent => false;

  @override
  String get currentPlan => 'premium';

  @override
  bool hasFeature(String featureName) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser =>
      const {'id': 1, 'name': 'Admin', 'role': 'admin'};

  @override
  bool get isAdmin => true;

  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosCustomerProvider extends ChangeNotifier
    implements CustomerProvider {
  @override
  List<Customer> get customers => const [];

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchCustomers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosCashRegisterProvider extends ChangeNotifier
    implements CashRegisterProvider {
  @override
  int get activeRegisterId => 1;

  @override
  Future<void> checkCurrentShift({int? registerId}) async {}

  @override
  CashRegisterShift? get currentShift => CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openedAt: DateTime(2026, 11, 22, 8, 0),
        openingBalance: 10000.0,
        status: 'open',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosOfferProvider extends ChangeNotifier implements OfferProvider {
  @override
  List<OfferModel> get activeOffers => const [];

  @override
  double? getDiscountedPrice(Product product) => null;

  @override
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) =>
      null;

  @override
  Set<int> get currentlyActiveOfferProductIds => const {};

  @override
  List<Product> get offerOnlyProducts => const [];

  @override
  Future<void> loadActiveOffers() async {}

  @override
  Future<void> syncOfferOnlyProducts(Set<int> loadedProductIds,
      {bool force = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosQuoteProvider extends ChangeNotifier implements QuoteProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  @override
  int get totalAlertsCount => 0;

  @override
  List<dynamic> get alerts => const [];

  @override
  List<dynamic> get reactiveAlerts => const [];

  @override
  List<dynamic> get expirationAlerts => const [];

  @override
  List<dynamic> get predictiveCriticalAlerts => const [];

  @override
  String? getAlertStatusForProduct(int productId) => null;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<void> fetchAlerts({int threshold = 7}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProductModel _buildProduct({
  required int id,
  required String name,
  required bool active,
  bool isWeight = false,
  int? categoryId,
  double stock = 20,
}) {
  return ProductModel(
    id: id,
    name: name,
    internalCode: 'HW$id',
    costPrice: 100,
    sellingPrice: 150,
    stock: stock,
    active: active,
    isSoldByWeight: isWeight,
    category: categoryId != null
        ? CategoryModel(id: categoryId, name: 'Cat $categoryId')
        : null,
  );
}

class _FakePosRepo extends Fake implements PosRepository {
  final List<Product> searchableProducts;

  _FakePosRepo({this.searchableProducts = const []});

  @override
  Future<List<Map<String, dynamic>>> fetchPaymentMethods() async => [
        {
          'id': 1,
          'name': 'Efectivo',
          'code': 'cash',
          'surcharge_type': 'none',
          'surcharge_value': 0.0,
          'is_cash': true,
          'is_active': true,
          'sort_order': 1,
        }
      ];

  @override
  Future<List<Map<String, dynamic>>> fetchPendingSales() async => [];

  @override
  Future<List<Product>> searchProducts(String query) async {
    return searchableProducts
        .where((p) =>
            p.active &&
            matchesSpanishSearchQuery(query, [
              p.name,
              p.barcode,
              p.internalCode,
              p.supplierSku,
              p.technicalSpec,
            ]))
        .toList();
  }
}

class _FakePosRemoteDataSource extends Fake implements PosRemoteDataSourceImpl {}

PosProvider _createPosProvider({List<Product> searchableProducts = const []}) {
  final repo = _FakePosRepo(searchableProducts: searchableProducts);
  final ds = _FakePosRemoteDataSource();
  return PosProvider(
    processSaleUseCase: ProcessSaleUseCase(repo),
    searchProductsUseCase: SearchProductsUseCase(repo),
    repository: repo,
    remoteDataSource: ds,
  );
}

void main() {
  group('CatalogProvider.activeProducts y Resolvión >500 SKUs', () {
    test(
        'activeProducts excluye productos con active=false mientras products los conserva para administración',
        () async {
      final items = [
        _buildProduct(
            id: 1, name: 'Machimbre Pino 1/2', active: true, categoryId: 10),
        _buildProduct(
            id: 2,
            name: 'Empanadas de Carne x12',
            active: false,
            categoryId: 20),
        _buildProduct(
            id: 3, name: 'Chapa C27 4.5m', active: true, categoryId: 10),
        _buildProduct(
            id: 4, name: 'Pollo al Spiedo', active: false, categoryId: 20),
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

    test('pinnedExtraProducts filtra productos inactivos traídos por IDs fijados',
        () async {
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

    test(
        'resolveRecentProducts resuelve SKUs >500 cacheados en sesión en 0 ms y protege syncPinnedProducts en servidores v1.8.5',
        () async {
      final pageOneItems = [
        _buildProduct(id: 1, name: 'Producto Página 1', active: true),
        _buildProduct(id: 2, name: 'Otro Página 1', active: true),
      ];
      final sku650 = _buildProduct(
        id: 650,
        name: 'Tornillo Autoperforante 650',
        active: true,
        stock: 15,
      );
      final useCase = _FakeGetProductsUseCase(
        [...pageOneItems, sku650],
        ignoreIdsFilter: true,
        v185PageOneProducts: pageOneItems,
      );
      final provider = CatalogProvider(
        getProductsUseCase: useCase,
        repository: _FakeCatalogRepo(),
      );

      await provider.loadProducts(page: 1, perPage: 500);
      expect(provider.resolveRecentProducts([650]), isEmpty);

      // Al buscar remotamente el SKU #650 queda cacheado en sesión en 0 ms
      final remote = await provider.searchProductsRemote('650');
      expect(remote.map((p) => p.id), [650]);
      final resolved = provider.resolveRecentProducts([650]);
      expect(resolved.map((p) => p.id), [650]);
      expect(resolved.first.name, 'Tornillo Autoperforante 650');

      // Simulación v1.8.5: syncPinnedProducts({999}) recibe página 1 [1, 2], pero NO contamina pinnedExtraProducts
      await provider.syncPinnedProducts({999});
      expect(provider.pinnedExtraProducts, isEmpty);

      // Si el producto #650 pasa a inactivo, resolveRecentProducts(activeOnly: true) lo excluye
      provider.registerRecentlySeenProducts([
        sku650.copyWith(active: false),
      ]);
      expect(provider.resolveRecentProducts([650]), isEmpty);
    });
  });

  group('LocalTerminalProvider Historial Multi-Scope & Anti-Basura', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
        'Filtro anti-basura rechaza códigos cortos, numéricos largos, comprobantes, símbolos y etiquetas internas',
        () {
      // Inválidos / basura
      expect(LocalTerminalProvider.isValidRecentSearchTerm(''), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm(' '), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('a'), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('1'), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('...'), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('---'), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('A' * 46), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('12345'), isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('77912345'), isFalse);
      expect(
          LocalTerminalProvider.isValidRecentSearchTerm('7791234567890'),
          isFalse);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('L#42'), isFalse);
      expect(
          LocalTerminalProvider.isValidRecentSearchTerm('L#42#W#500'), isFalse);
      expect(
          LocalTerminalProvider.isValidRecentSearchTerm('PRES-0012'), isFalse);
      expect(
          LocalTerminalProvider.isValidRecentSearchTerm('REM00012'), isFalse);
      expect(
          LocalTerminalProvider.isValidRecentSearchTerm('ORD00045'), isFalse);
      expect(
          LocalTerminalProvider.isValidRecentSearchTerm('2000000PROD-16378'),
          isFalse);

      // Válidos
      expect(LocalTerminalProvider.isValidRecentSearchTerm('T2'), isTrue);
      expect(
          LocalTerminalProvider.isValidRecentSearchTerm('Machimbre'), isTrue);
      expect(
          LocalTerminalProvider.isValidRecentSearchTerm('Chapa C27'), isTrue);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('HW101'), isTrue);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('101'), isTrue);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('WD-40'), isTrue);
      expect(LocalTerminalProvider.isValidRecentSearchTerm('remache'), isTrue);
    });

    test(
        'recordRecentSearch normaliza espacios múltiples, respeta MRU, límites y limpieza',
        () async {
      final provider = LocalTerminalProvider();
      await Future<void>.delayed(Duration.zero);

      for (int i = 1; i <= 10; i++) {
        await provider.recordRecentSearch(
            term: 'Termino $i', selectedProductId: i);
      }

      expect(provider.recentSearchTerms.length,
          LocalTerminalProvider.maxRecentSearchTerms);
      expect(provider.recentSearchTerms.first, 'Termino 10');
      expect(provider.recentSearchTerms.last, 'Termino 3');

      expect(provider.recentSearchProductIds.length,
          LocalTerminalProvider.maxRecentSearchProducts);
      expect(provider.recentSearchProductIds, [10, 9, 8, 7, 6]);

      // Normaliza espacios múltiples y deduplica case-insensitive
      await provider.recordRecentSearch(
          term: '  termino   5  ', selectedProductId: 7);
      expect(provider.recentSearchTerms.first, 'termino 5');
      expect(
        provider.recentSearchTerms
            .where((t) => t.toLowerCase() == 'termino 5')
            .length,
        1,
      );
      expect(provider.recentSearchProductIds.first, 7);

      // Basura no se registra
      await provider.recordRecentSearch(term: '7790001234567');
      await provider.recordRecentSearch(term: 'REM00012');
      await provider.recordRecentSearch(term: 'x');
      expect(provider.recentSearchTerms.first, 'termino 5');

      await provider.removeRecentSearchTerm('termino 5');
      expect(provider.recentSearchTerms.contains('termino 5'), isFalse);

      await provider.removeRecentSearchProductId(7);
      expect(provider.recentSearchProductIds.contains(7), isFalse);

      final reloaded = LocalTerminalProvider();
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.recentSearchTerms, provider.recentSearchTerms);
      expect(reloaded.recentSearchProductIds, provider.recentSearchProductIds);

      await provider.clearRecentSearches();
      expect(provider.recentSearchTerms, isEmpty);
      expect(provider.recentSearchProductIds, isEmpty);
    });

    test(
        'Multi-scope mantiene historiales aislados entre POS, Presupuestos, F7 y Catálogo y tolera mocks',
        () async {
      final provider = LocalTerminalProvider();
      await Future<void>.delayed(Duration.zero);

      await provider.recordRecentSearchForScope(
        LocalTerminalProvider.scopePosCounter,
        term: 'Clavo 2',
        selectedProductId: 101,
      );
      await provider.recordRecentSearchForScope(
        LocalTerminalProvider.scopeQuotes,
        term: 'Chapa C27',
        selectedProductId: 202,
      );
      await provider.recordRecentSearchForScope(
        LocalTerminalProvider.scopeHardwareCalc,
        term: 'Machimbre 4',
        selectedProductId: 303,
      );
      await provider.recordRecentSearchForScope(
        LocalTerminalProvider.scopeCatalog,
        term: 'Pintura Látex',
      );

      expect(
          provider.recentTermsForScope(LocalTerminalProvider.scopePosCounter),
          ['Clavo 2']);
      expect(provider.recentTermsForScope(LocalTerminalProvider.scopeQuotes),
          ['Chapa C27']);
      expect(
          provider.recentTermsForScope(LocalTerminalProvider.scopeHardwareCalc),
          ['Machimbre 4']);
      expect(provider.recentTermsForScope(LocalTerminalProvider.scopeCatalog),
          ['Pintura Látex']);

      // Limpiar Quotes no borra POS ni F7 ni Catálogo
      await provider
          .clearRecentSearchesForScope(LocalTerminalProvider.scopeQuotes);
      expect(provider.recentTermsForScope(LocalTerminalProvider.scopeQuotes),
          isEmpty);
      expect(
          provider
              .recentProductIdsForScope(LocalTerminalProvider.scopeQuotes),
          isEmpty);
      expect(
          provider.recentTermsForScope(LocalTerminalProvider.scopePosCounter),
          ['Clavo 2']);
      expect(
          provider.recentTermsForScope(LocalTerminalProvider.scopeHardwareCalc),
          ['Machimbre 4']);

      // Persistencia tras recargar
      final reloaded = LocalTerminalProvider();
      await Future<void>.delayed(Duration.zero);
      expect(
          reloaded.recentTermsForScope(LocalTerminalProvider.scopeHardwareCalc),
          ['Machimbre 4']);
      expect(
          reloaded
              .recentProductIdsForScope(LocalTerminalProvider.scopeHardwareCalc),
          [303]);

      // Seguridad absoluta sobre mocks con implements LocalTerminalProvider
      final bareFake = _BareFakeLocalTerminalProvider();
      await bareFake.recordRecentSearchForScope(
        LocalTerminalProvider.scopeCatalog,
        term: 'Test Mock',
        selectedProductId: 55,
      );
      expect(bareFake.recentTermsForScope(LocalTerminalProvider.scopeCatalog),
          ['Test Mock']);
      expect(
          bareFake
              .recentProductIdsForScope(LocalTerminalProvider.scopeCatalog),
          [55]);
      await bareFake.removeRecentTermForScope(
          LocalTerminalProvider.scopeCatalog, 'Test Mock');
      await bareFake.clearRecentSearchesForScope(
          LocalTerminalProvider.scopeCatalog);
      expect(bareFake.recentTermsForScope(LocalTerminalProvider.scopeCatalog),
          isEmpty);
    });
  });

  group('PosSearchHistoryPopover Widget & Interacción de Foco / PosScreen',
      () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
        'TextFieldTapRegion conserva el foco y el popover al tocar X individual, X de producto y Limpiar',
        (tester) async {
      final portalController = OverlayPortalController();
      final focusNode = FocusNode();
      final textCtrl = TextEditingController();
      const tapGroupId = 'test_history_group';

      List<String> terms = ['machimbre', 'chapa c27'];
      List<Product> products = [
        _buildProduct(id: 10, name: 'Clavo Espiralado 1 1/2', active: true),
        _buildProduct(
            id: 11, name: 'Lija al Agua #120', active: true, stock: 0),
      ];
      int selectedProductCalls = 0;

      addTearDown(() {
        focusNode.dispose();
        textCtrl.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: SizedBox(
                    width: 520,
                    child: TapRegion(
                      groupId: tapGroupId,
                      child: OverlayPortal.overlayChildLayoutBuilder(
                        controller: portalController,
                        overlayChildBuilder: (overlayCtx, info) {
                          return PosSearchHistoryPopover.buildAnchoredOverlay(
                            info: info,
                            child: PosSearchHistoryPopover(
                              containerKey:
                                  const ValueKey('test_history_popover_card'),
                              terms: terms,
                              products: products,
                              tapGroupId: tapGroupId,
                              onDismiss: () => portalController.hide(),
                              onClearAll: () {
                                setState(() {
                                  terms = [];
                                  products = [];
                                });
                                portalController.hide();
                              },
                              onSelectTerm: (_) {},
                              onRemoveTerm: (t) {
                                setState(() {
                                  terms = terms.where((x) => x != t).toList();
                                  if (terms.isEmpty && products.isEmpty) {
                                    portalController.hide();
                                  }
                                });
                              },
                              onSelectProduct: (_) => selectedProductCalls++,
                              onRemoveProduct: (id) {
                                setState(() {
                                  products =
                                      products.where((p) => p.id != id).toList();
                                  if (terms.isEmpty && products.isEmpty) {
                                    portalController.hide();
                                  }
                                });
                              },
                            ),
                          );
                        },
                        child: TextField(
                          controller: textCtrl,
                          focusNode: focusNode,
                          onTap: () => portalController.show(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('test_history_popover_card')), findsOneWidget);
      expect(find.text('Stock: 20 u'), findsOneWidget);
      expect(find.text('Sin stock'), findsOneWidget);
      expect(focusNode.hasFocus, isTrue);

      // 1. Clic en la X de un término: elimina el término, mantiene abierto y mantiene foco
      await tester.tap(find.byKey(const ValueKey('remove_term_machimbre')));
      await tester.pumpAndSettle();

      expect(terms, ['chapa c27']);
      expect(find.text('machimbre'), findsNothing);
      expect(
          find.byKey(const ValueKey('test_history_popover_card')), findsOneWidget);
      expect(focusNode.hasFocus, isTrue);

      // 2. Clic en la X de un producto: lo quita SIN disparar onSelectProduct ni cerrar
      await tester.tap(find.byKey(const ValueKey('remove_product_10')));
      await tester.pumpAndSettle();

      expect(selectedProductCalls, 0);
      expect(products.map((p) => p.id), [11]);
      expect(
          find.byKey(const ValueKey('test_history_popover_card')), findsOneWidget);

      // 3. Clic en Borrar historial: vacía todo y cierra popover
      expect(find.text('Borrar historial'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search_history_clear_btn')));
      await tester.pumpAndSettle();

      expect(terms, isEmpty);
      expect(products, isEmpty);
      expect(find.byKey(const ValueKey('test_history_popover_card')),
          findsNothing);
    });

    testWidgets(
        'PosScreen elimina ítems del popover sin cerrarlo y preserva Enter: Cobrar con carrito lleno',
        timeout: const Timeout(Duration(seconds: 20)),
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'disable_pusher': true,
        'local_pos_recent_search_terms_v1': ['machimbre', 'chapa'],
        'local_pos_recent_search_product_ids_v1': ['10'],
      });

      final prodInCart =
          _buildProduct(id: 1, name: 'Producto Carrito', active: true);
      final prodRecent =
          _buildProduct(id: 10, name: 'Clavo Espiralado 10', active: true);

      final catalogProv = CatalogProvider(
        getProductsUseCase: _FakeGetProductsUseCase([prodInCart, prodRecent]),
        repository: _FakeCatalogRepo(),
      );
      final localTerminal = LocalTerminalProvider();
      final posProv = _createPosProvider();

      await tester.runAsync(() async {
        await catalogProv.loadProducts(page: 1, perPage: 500);
        await Future<void>.delayed(Duration.zero);
        await posProv.loadPaymentMethods();
      });
      posProv.requestAddToCartWithPromo(prodInCart);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: localTerminal),
            ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _PosSettingsProvider()),
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => _PosAuthProvider()),
            ChangeNotifierProvider<CustomerProvider>(
                create: (_) => _PosCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(
                create: (_) => _PosCashRegisterProvider()),
            ChangeNotifierProvider<OfferProvider>(
                create: (_) => _PosOfferProvider()),
            ChangeNotifierProvider<QuoteProvider>(
                create: (_) => _PosQuoteProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>(
                create: (_) => _PosAlertsProvider()),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Abrir popover haciendo clic en el botón de reloj
      final toggleBtn =
          find.byKey(const ValueKey('pos_search_history_toggle_btn'));
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
          find.byKey(const ValueKey('pos_search_history_overlay')), findsOneWidget);

      // Clic en X de término -> lo elimina de localTerminal y el overlay sigue abierto
      await tester.tap(find.byKey(const ValueKey('remove_term_machimbre')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(localTerminal.recentSearchTerms, ['chapa']);
      expect(
          find.byKey(const ValueKey('pos_search_history_overlay')), findsOneWidget);

      // Clic en X de producto -> lo elimina sin agregarlo al carrito
      await tester.tap(find.byKey(const ValueKey('remove_product_10')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(localTerminal.recentSearchProductIds, isEmpty);
      expect(posProv.cart.length, 1);
      expect(
          find.byKey(const ValueKey('pos_search_history_overlay')), findsOneWidget);

      // Con buscador vacío y sin ítem resaltado (highlightedIndex == -1), Enter dispara Cobrar
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
          find.byKey(const ValueKey('pos_search_history_overlay')), findsNothing);
      expect(find.byType(CheckoutDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test(
        'unhydratedRecentProductIds ignora inactivos en memoria y consolidación de prefijos evita ruido',
        () async {
      SharedPreferences.setMockInitialValues({});
      final localTerminal = LocalTerminalProvider();
      await Future<void>.delayed(Duration.zero);

      // Consolidación progresiva de prefijos al escribir con debounce
      await localTerminal.recordRecentSearch(term: 'ma');
      await localTerminal.recordRecentSearch(term: 'mach');
      await localTerminal.recordRecentSearch(term: 'machimbre');
      expect(localTerminal.recentSearchTerms, ['machimbre']);

      // Productos locales: #1 activo, #2 inactivo en memoria
      final activeProd =
          _buildProduct(id: 1, name: 'Machimbre Pino', active: true);
      final inactiveProd =
          _buildProduct(id: 2, name: 'Descontinuado', active: false);
      final catalogProv = CatalogProvider(
        getProductsUseCase:
            _FakeGetProductsUseCase([activeProd, inactiveProd]),
        repository: _FakeCatalogRepo(),
      );
      await catalogProv.loadProducts(page: 1, perPage: 500);

      // #2 ya está en memoria aunque inactivo; #999 aún no se ha consultado
      expect(catalogProv.resolveRecentProducts([1, 2, 999]).map((p) => p.id),
          [1]);
      expect(catalogProv.unhydratedRecentProductIds([1, 2, 999]), {999});

      await catalogProv.syncPinnedProducts({999});
      expect(catalogProv.unhydratedRecentProductIds([1, 2, 999]), isEmpty);

      // Tolerancia a plurales en español en helper local
      expect(
        matchesSpanishSearchQuery('machimbres', ['Machimbre Pino 1/2"']),
        isTrue,
      );
      expect(
        matchesSpanishSearchQuery('perfiles c', ['Perfil C Galvanizado 100x50']),
        isTrue,
      );
      expect(
        matchesSpanishSearchQuery('luces led', ['Luz LED Emergencia 18W']),
        isTrue,
      );
    });

    testWidgets(
        'PosScreen guarda búsqueda en vivo con plural ("machimbres") y "Limpiar filtro" la conserva en el historial',
        timeout: const Timeout(Duration(seconds: 20)),
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({'disable_pusher': true});

      final prodMachimbre = _buildProduct(
        id: 1,
        name: 'Machimbre Pino 1/2" x 4" x 3.00m',
        active: true,
      );
      final prodChapa =
          _buildProduct(id: 2, name: 'Chapa Acanalada C27', active: true);

      final catalogProv = CatalogProvider(
        getProductsUseCase:
            _FakeGetProductsUseCase([prodMachimbre, prodChapa]),
        repository: _FakeCatalogRepo(),
      );
      final localTerminal = LocalTerminalProvider();
      final posProv = _createPosProvider(
        searchableProducts: [prodMachimbre, prodChapa],
      );

      await tester.runAsync(() async {
        await catalogProv.loadProducts(page: 1, perPage: 500);
        await Future<void>.delayed(Duration.zero);
        await posProv.loadPaymentMethods();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: localTerminal),
            ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _PosSettingsProvider()),
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => _PosAuthProvider()),
            ChangeNotifierProvider<CustomerProvider>(
                create: (_) => _PosCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(
                create: (_) => _PosCashRegisterProvider()),
            ChangeNotifierProvider<OfferProvider>(
                create: (_) => _PosOfferProvider()),
            ChangeNotifierProvider<QuoteProvider>(
                create: (_) => _PosQuoteProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>(
                create: (_) => _PosAlertsProvider()),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Escribir plural "machimbres" y esperar el debounce (400ms)
      await tester.enterText(find.byType(TextField), 'machimbres');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Resultados para "machimbres"'), findsOneWidget);
      expect(find.text('Machimbre Pino 1/2" x 4" x 3.00m'), findsOneWidget);
      expect(localTerminal.recentSearchTerms, ['machimbres']);

      // Limpiar filtro sin agregar al carrito ni borrar el historial
      final clearFilterBtn =
          find.byKey(const ValueKey('pos_clear_search_filter_btn'));
      expect(clearFilterBtn, findsOneWidget);
      await tester.tap(clearFilterBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Acceso Rápido'), findsOneWidget);
      expect(localTerminal.recentSearchTerms, ['machimbres']);

      // El botón de historial aparece y al abrirlo muestra "machimbres" + "Borrar historial"
      final toggleBtn =
          find.byKey(const ValueKey('pos_search_history_toggle_btn'));
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
          find.byKey(const ValueKey('pos_search_history_overlay')), findsOneWidget);
      expect(find.text('machimbres'), findsOneWidget);
      expect(find.text('Borrar historial'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
