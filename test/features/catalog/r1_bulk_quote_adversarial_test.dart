import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';

// ─── FAKE IMPLEMENTATIONS ───────────────────────────────────────────────────

class AdversarialCatalogRepository implements CatalogRepository {
  List<int>? lastIds;
  int? lastCategoryId;
  bool? lastClearCategory;
  int? lastBrandId;
  bool? lastClearBrand;
  bool? lastActive;
  int? lastSupplierId;
  bool? lastClearSupplier;
  bool shouldFail = false;
  String failureMessage = 'Error en base de datos';

  @override
  Future<Map<String, dynamic>> bulkUpdateProducts(
    List<int> ids, {
    int? categoryId,
    bool clearCategory = false,
    int? brandId,
    bool clearBrand = false,
    bool? active,
    int? supplierId,
    bool clearSupplier = false,
  }) async {
    if (shouldFail) {
      throw Exception(failureMessage);
    }
    lastIds = List.from(ids);
    lastCategoryId = categoryId;
    lastClearCategory = clearCategory;
    lastBrandId = brandId;
    lastClearBrand = clearBrand;
    lastActive = active;
    lastSupplierId = supplierId;
    lastClearSupplier = clearSupplier;

    return {
      'message': 'Se actualizaron masivamente ${ids.length} productos.',
      'updated_count': ids.length,
      'affected_ids': ids,
    };
  }

  @override
  Future<List<Brand>> getBrands() async => [
        Brand(id: 1, name: 'Arcor'),
        Brand(id: 2, name: 'Coca-Cola'),
      ];

  @override
  Future<List<Category>> getCategories() async => [
        Category(id: 1, name: 'Bebidas'),
        Category(id: 2, name: 'Golosinas'),
      ];

  List<Product> mockProducts = [];

  @override
  Future<Map<String, dynamic>> getProducts({int page = 1, String? search, String? sortBy, String? sortDirection, int? perPage}) async => {
        'data': mockProducts,
        'current_page': 1,
        'last_page': 1,
        'total': mockProducts.length,
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdversarialSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings? get settings => const BusinessSettings(
        licensePlanType: 'premium',
        features: FeatureFlags(suppliers: true, multiRubro: true, multiplePrices: true),
      );
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => 'premium';
  @override
  FeatureFlags get features => const FeatureFlags(suppliers: true, multiRubro: true, multiplePrices: true);
  @override
  bool hasFeature(String featureName) => true;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdversarialSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [
        Supplier(id: 1, name: 'Distribuidora Norte', balance: 0.0, isActive: true),
        Supplier(id: 2, name: 'Mayorista Sur', balance: 0.0, isActive: true),
      ];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchSuppliers({String? search}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdversarialLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdversarialAuthProvider extends ChangeNotifier implements AuthProvider {
  bool allowPin = true;

  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'SuperAdmin', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;
  Future<bool> verifyAdminPin(String pin) async => allowPin;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdversarialInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => [];
  @override
  int get totalAlertsCount => 0;
  @override
  List<dynamic> get reactiveAlerts => [];
  @override
  List<dynamic> get predictiveCriticalAlerts => [];
  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuoteRepo extends Fake implements QuoteRepository {}

class AdversarialPosProvider extends ChangeNotifier implements PosProvider {
  final List<CartItem> _cart = [];
  @override
  List<CartItem> get cart => _cart;

  @override
  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  @override
  bool requestAddToCart(Product product) {
    if (product.isSoldByWeight) return false;
    _cart.add(CartItem(product: product, quantity: 1.0));
    notifyListeners();
    return true;
  }

  @override
  void submitWeighedProduct(Product product, double weightInKg) {
    _cart.add(CartItem(product: product, quantity: weightInKg));
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─── SAMPLE DATA ────────────────────────────────────────────────────────────

final sampleProduct1 = Product(
  id: 101,
  name: 'Coca Cola 2.25L',
  barcode: '7790895000445',
  internalCode: 'COC01',
  costPrice: 1200.0,
  sellingPrice: 1800.0,
  priceWholesale: 1500.0,
  stock: 25.0,
  active: true,
  isSoldByWeight: false,
);

final sampleProduct2 = Product(
  id: 102,
  name: 'Galletitas Oreo 118g',
  barcode: '7622300744648',
  internalCode: 'ORE01',
  costPrice: 450.0,
  sellingPrice: 700.0,
  priceWholesale: 600.0,
  stock: 50.0,
  active: true,
  isSoldByWeight: false,
);

final sampleWeighedProduct = Product(
  id: 103,
  name: 'Queso Cremoso La Paulina (x Kg)',
  barcode: '2000000001030',
  internalCode: 'QUE01',
  costPrice: 3500.0,
  sellingPrice: 5200.0,
  priceWholesale: 4800.0,
  stock: 80.0,
  active: true,
  isSoldByWeight: true,
);

// ─── MAIN TEST SUITE ────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  Widget buildTestApp({
    required CatalogProvider catalogProvider,
    QuoteProvider? quoteProvider,
    PosProvider? posProvider,
    AdversarialAuthProvider? authProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
        ChangeNotifierProvider<SettingsProvider>(create: (_) => AdversarialSettingsProvider()),
        ChangeNotifierProvider<SupplierProvider>(create: (_) => AdversarialSupplierProvider()),
        ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => AdversarialLocalTerminalProvider()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => authProvider ?? AdversarialAuthProvider()),
        ChangeNotifierProvider<InventoryAlertsProvider>(create: (_) => AdversarialInventoryAlertsProvider()),
        if (quoteProvider != null) ChangeNotifierProvider<QuoteProvider>.value(value: quoteProvider),
        if (posProvider != null) ChangeNotifierProvider<PosProvider>.value(value: posProvider),
      ],
      child: const MaterialApp(
        home: CatalogScreen(),
      ),
    );
  }

  group('R1 Adversarial: Remote DataSource Payload Stress Tests', () {
    test('Unsetting category sends category_id: null in payload', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode({'message': 'OK', 'updated_count': 2}), 200);
      });
      final ds = CatalogRemoteDataSourceImpl(baseUrl: 'http://pos.test/api', client: client);

      await ds.bulkUpdateProducts([10, 20], clearCategory: true);

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/catalog/bulk-update');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['product_ids'], [10, 20]);
      expect(body.containsKey('category_id'), isTrue);
      expect(body['category_id'], isNull);
      expect(body.containsKey('brand_id'), isFalse);
      expect(body.containsKey('supplier_id'), isFalse);
    });

    test('Unsetting brand sends brand_id: null in payload', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode({'message': 'OK', 'updated_count': 1}), 200);
      });
      final ds = CatalogRemoteDataSourceImpl(baseUrl: 'http://pos.test/api', client: client);

      await ds.bulkUpdateProducts([99], clearBrand: true);

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['product_ids'], [99]);
      expect(body.containsKey('brand_id'), isTrue);
      expect(body['brand_id'], isNull);
    });

    test('Unsetting supplier sends supplier_id: null in payload', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode({'message': 'OK', 'updated_count': 1}), 200);
      });
      final ds = CatalogRemoteDataSourceImpl(baseUrl: 'http://pos.test/api', client: client);

      await ds.bulkUpdateProducts([77], clearSupplier: true);

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['product_ids'], [77]);
      expect(body.containsKey('supplier_id'), isTrue);
      expect(body['supplier_id'], isNull);
    });

    test('Boundary: Unsetting category, brand AND supplier simultaneously on 100 products', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode({'message': 'OK', 'updated_count': 100}), 200);
      });
      final ds = CatalogRemoteDataSourceImpl(baseUrl: 'http://pos.test/api', client: client);

      final ids = List.generate(100, (i) => i + 1);
      await ds.bulkUpdateProducts(
        ids,
        clearCategory: true,
        clearBrand: true,
        clearSupplier: true,
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['product_ids'].length, 100);
      expect(body['category_id'], isNull);
      expect(body['brand_id'], isNull);
      expect(body['supplier_id'], isNull);
    });

    test('Adversarial: Server returns 500 error throws Exception', () async {
      final client = MockClient((req) async {
        return http.Response(jsonEncode({'message': 'Internal Server Error'}), 500);
      });
      final ds = CatalogRemoteDataSourceImpl(baseUrl: 'http://pos.test/api', client: client);

      expect(
        () => ds.bulkUpdateProducts([1], clearCategory: true),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('R1 Adversarial: CatalogProvider State Resilience & Error Capturing', () {
    test('Provider captures error message and returns null when repository fails', () async {
      final fakeRepo = AdversarialCatalogRepository()..shouldFail = true;
      final provider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      final result = await provider.bulkUpdateProducts([10, 20], clearCategory: true);

      expect(result, isNull);
      expect(provider.errorMessage, contains('Error en base de datos'));
      expect(provider.isLoading, isFalse);
    });
  });

  group('R1 & R2: Bulk Operations Menu Cleanup & Integrated Quitar Options', () {
    testWidgets('Bulk popup menu displays Asignar options and removes standalone Quitar options (R1)', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct1, sampleProduct2];
      final provider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      await tester.pumpWidget(buildTestApp(catalogProvider: provider));
      await tester.pumpAndSettle();

      // Select first product
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      // Open Lote menu
      expect(find.text('Lote (1)'), findsOneWidget);
      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      // Verify requirement: Asignar options & Generar Presupuesto present
      expect(find.text('Asignar Categoría'), findsOneWidget);
      expect(find.text('Asignar Marca'), findsOneWidget);
      expect(find.text('Asignar Proveedor'), findsOneWidget);
      expect(find.text('Generar Presupuesto'), findsOneWidget);

      // Verify R1: Standalone Quitar options removed
      expect(find.text('Quitar Categoría'), findsNothing);
      expect(find.text('Quitar Marca'), findsNothing);
      expect(find.text('Quitar Proveedor'), findsNothing);
    });

    testWidgets('R2: Tapping "Asignar Categoría" and choosing "— Quitar Categoría —" unsets category', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct1, sampleProduct2];
      final provider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      await tester.pumpWidget(buildTestApp(catalogProvider: provider));
      await tester.pumpAndSettle();

      // Select products
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1)); // Product 101
      await tester.tap(checkboxes.at(2)); // Product 102
      await tester.pump();

      expect(find.text('Lote (2)'), findsOneWidget);
      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Categoría'));
      await tester.pumpAndSettle();

      expect(find.text('Asignar Categoría'), findsOneWidget);

      // Open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      // Choose — Quitar Categoría —
      expect(find.text('— Quitar Categoría —'), findsWidgets);
      await tester.tap(find.text('— Quitar Categoría —').last);
      await tester.pumpAndSettle();

      // Confirm assignment
      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      // Repository should have been called with clearCategory: true and categoryId: null
      expect(fakeRepo.lastClearCategory, isTrue);
      expect(fakeRepo.lastCategoryId, isNull);
      expect(fakeRepo.lastIds, unorderedEquals([101, 102]));

      // Selection should now be cleared
      expect(find.text('Lote (2)'), findsNothing);
    });

    testWidgets('R2: Tapping "Asignar Marca" and choosing "— Quitar Marca —" unsets brand', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct1];
      final provider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      await tester.pumpWidget(buildTestApp(catalogProvider: provider));
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Marca'));
      await tester.pumpAndSettle();

      // Open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      // Choose — Quitar Marca —
      expect(find.text('— Quitar Marca —'), findsWidgets);
      await tester.tap(find.text('— Quitar Marca —').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastClearBrand, isTrue);
      expect(fakeRepo.lastBrandId, isNull);
      expect(fakeRepo.lastIds, [101]);
      expect(find.text('Lote (1)'), findsNothing);
    });

    testWidgets('R2: Tapping "Asignar Proveedor" and choosing "— Quitar Proveedor —" unsets supplier', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct1];
      final provider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      await tester.pumpWidget(buildTestApp(catalogProvider: provider));
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Proveedor'));
      await tester.pumpAndSettle();

      // Open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      // Choose — Quitar Proveedor —
      expect(find.text('— Quitar Proveedor —'), findsWidgets);
      await tester.tap(find.text('— Quitar Proveedor —').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastClearSupplier, isTrue);
      expect(fakeRepo.lastSupplierId, isNull);
      expect(fakeRepo.lastIds, [101]);
      expect(find.text('Lote (1)'), findsNothing);
    });

    testWidgets('Canceling assignment dialog DOES NOT call repository and keeps selection', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct1];
      final provider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      await tester.pumpWidget(buildTestApp(catalogProvider: provider));
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Categoría'));
      await tester.pumpAndSettle();

      // Tap Cancelar
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Repository was NOT called
      expect(fakeRepo.lastClearCategory, isNull);
      // Selection is still intact
      expect(find.text('Lote (1)'), findsOneWidget);
    });

    testWidgets('Server failure during bulk unset shows error snackbar and PRESERVES selection', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..shouldFail = true..mockProducts = [sampleProduct1];
      final provider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      await tester.pumpWidget(buildTestApp(catalogProvider: provider));
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Categoría'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('— Quitar Categoría —').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      // Selection preserved so user does not lose their selection state
      expect(find.text('Lote (1)'), findsOneWidget);
      // Error snackbar displayed
      expect(find.textContaining('Error en base de datos'), findsAtLeastNWidgets(1));
    });
  });

  group('R1 Adversarial: "Generar Presupuesto" Quote Preloading & Navigation Stress Tests', () {
    testWidgets('Generar Presupuesto with single unit product loads QuoteProvider cart & PosProvider cart', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct1];
      final catalogProvider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      final quoteProvider = QuoteProvider(repository: FakeQuoteRepo());
      final posProvider = AdversarialPosProvider();

      await tester.pumpWidget(buildTestApp(
        catalogProvider: catalogProvider,
        quoteProvider: quoteProvider,
        posProvider: posProvider,
      ));
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generar Presupuesto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // QuoteProvider cart should have 1 item with quantity 1.0
      expect(quoteProvider.cart.length, 1);
      expect(quoteProvider.cart.first.product.id, 101);
      expect(quoteProvider.cart.first.quantity, 1.0);
      expect(quoteProvider.cartTotal, 1800.0);

      // PosProvider cart should also have the product
      expect(posProvider.cart.length, 1);
      expect(posProvider.cart.first.product.id, 101);
      expect(posProvider.cart.first.quantity, 1.0);

      // Catalog selection cleared
      expect(find.text('Lote (1)'), findsNothing);
    });

    testWidgets('Generar Presupuesto with weighed product uses submitWeighedProduct (quantity 1.0 kg)', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleWeighedProduct];
      final catalogProvider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      final quoteProvider = QuoteProvider(repository: FakeQuoteRepo());
      final posProvider = AdversarialPosProvider();

      await tester.pumpWidget(buildTestApp(
        catalogProvider: catalogProvider,
        quoteProvider: quoteProvider,
        posProvider: posProvider,
      ));
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generar Presupuesto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Weighed product in QuoteProvider has quantity 1.0 and unit price $5200
      expect(quoteProvider.cart.length, 1);
      expect(quoteProvider.cart.first.product.isSoldByWeight, isTrue);
      expect(quoteProvider.cart.first.quantity, 1.0);
      expect(quoteProvider.cartTotal, 5200.0);

      // PosProvider cart has weighed product with 1.0 kg
      expect(posProvider.cart.length, 1);
      expect(posProvider.cart.first.product.isSoldByWeight, isTrue);
      expect(posProvider.cart.first.quantity, 1.0);
    });

    testWidgets('Generar Presupuesto with multiple mixed products (unit + weighed)', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct1, sampleProduct2, sampleWeighedProduct];
      final catalogProvider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      final quoteProvider = QuoteProvider(repository: FakeQuoteRepo());
      final posProvider = AdversarialPosProvider();

      await tester.pumpWidget(buildTestApp(
        catalogProvider: catalogProvider,
        quoteProvider: quoteProvider,
        posProvider: posProvider,
      ));
      await tester.pumpAndSettle();

      // Select all products using header checkbox
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.first); // Select all
      await tester.pump();

      expect(find.text('Lote (3)'), findsOneWidget);
      await tester.tap(find.text('Lote (3)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generar Presupuesto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(quoteProvider.cart.length, 3);
      // Total = 1800 + 700 + 5200 = 7700
      expect(quoteProvider.cartTotal, 7700.0);
      expect(posProvider.cart.length, 3);
    });

    testWidgets('Pre-existing items in quote cart are cleared when generating new bulk quote', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct2];
      final catalogProvider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      final quoteProvider = QuoteProvider(repository: FakeQuoteRepo());
      // Seed quote cart with previous leftover item
      quoteProvider.addToCart(sampleProduct1, quantity: 5.0);
      expect(quoteProvider.cart.length, 1);

      await tester.pumpWidget(buildTestApp(
        catalogProvider: catalogProvider,
        quoteProvider: quoteProvider,
      ));
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generar Presupuesto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Old item was cleared; now only sampleProduct2 exists
      expect(quoteProvider.cart.length, 1);
      expect(quoteProvider.cart.first.product.id, 102);
      expect(quoteProvider.cartTotal, 700.0);
    });

    testWidgets('Quote preloading survives gracefully when QuoteProvider is NOT in widget tree', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct1];
      final catalogProvider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      // QuoteProvider is intentionally omitted (null)
      await tester.pumpWidget(buildTestApp(
        catalogProvider: catalogProvider,
        quoteProvider: null,
      ));
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      // Tapping must NOT throw ProviderNotFoundException
      await tester.tap(find.text('Generar Presupuesto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.text('Lote (1)'), findsNothing);
    });

    testWidgets('Active Wholesale tier in QuoteProvider properly calculates unit prices for preloaded batch items', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = AdversarialCatalogRepository()..mockProducts = [sampleProduct1, sampleProduct2];
      final catalogProvider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      final quoteProvider = QuoteProvider(repository: FakeQuoteRepo());
      // Set wholesale tier actively
      quoteProvider.setPriceTier(PriceTier.wholesale);

      await tester.pumpWidget(buildTestApp(
        catalogProvider: catalogProvider,
        quoteProvider: quoteProvider,
      ));
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.first); // Select all
      await tester.pump();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generar Presupuesto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(quoteProvider.cart.length, 2);
      // sampleProduct1 wholesale = 1500, sampleProduct2 wholesale = 600 -> Total = 2100
      expect(quoteProvider.cartTotal, 2100.0);
    });
  });
}
