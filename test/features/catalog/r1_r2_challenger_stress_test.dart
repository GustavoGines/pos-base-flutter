import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_access_view.dart';
import 'package:frontend_desktop/features/pos/presentation/pages/pos_screen.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';

// ─── TEST REPOSITORIES & PROVIDERS ───────────────────────────────────────────

class StressCatalogRepository implements CatalogRepository {
  List<int>? lastIds;
  int? lastCategoryId;
  bool? lastClearCategory;
  int? lastBrandId;
  bool? lastClearBrand;
  int? lastSupplierId;
  bool? lastClearSupplier;

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
    lastIds = List.from(ids);
    lastCategoryId = categoryId;
    lastClearCategory = clearCategory;
    lastBrandId = brandId;
    lastClearBrand = clearBrand;
    lastSupplierId = supplierId;
    lastClearSupplier = clearSupplier;

    return {
      'message': 'Actualizados ${ids.length} productos.',
      'updated_count': ids.length,
      'affected_ids': ids,
    };
  }

  @override
  Future<List<Brand>> getBrands() async => [Brand(id: 1, name: 'Brand A')];

  @override
  Future<List<Category>> getCategories() async => [Category(id: 1, name: 'Cat A')];

  List<Product> productsToReturn = [];

  @override
  Future<Map<String, dynamic>> getProducts({int page = 1, String? search, String? sortBy, String? sortDirection, int? perPage}) async => {
        'data': productsToReturn,
        'current_page': 1,
        'last_page': 1,
        'total': productsToReturn.length,
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StressSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings? _settings;

  StressSettingsProvider({BusinessSettings? initialSettings}) {
    _settings = initialSettings ??
        const BusinessSettings(
          companyName: 'Challenger POS',
          logoUrl: 'http://pos.test/storage/logo.png',
          licensePlanType: 'premium',
          features: FeatureFlags(quotes: true, suppliers: true, multiRubro: true, multiplePrices: true),
        );
  }

  void updateLogo(String? newLogo) {
    _settings = BusinessSettings(
      companyName: 'Challenger POS',
      logoUrl: newLogo,
      licensePlanType: 'premium',
      features: const FeatureFlags(quotes: true, suppliers: true, multiRubro: true, multiplePrices: true),
    );
    notifyListeners();
  }

  @override
  BusinessSettings? get settings => _settings;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => 'premium';
  @override
  FeatureFlags get features => const FeatureFlags(quotes: true, suppliers: true, multiRubro: true, multiplePrices: true);
  @override
  bool hasFeature(String featureName) => true;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StressSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [Supplier(id: 1, name: 'Proveedor 1', balance: 0.0, isActive: true)];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchSuppliers({String? search}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StressAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StressInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
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

class StressPosProvider extends ChangeNotifier implements PosProvider {
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

class FakeStressQuoteRepo extends Fake implements QuoteRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Challenger Hypothesis 1 & 3: Bulk Unset Serialization Boundaries', () {
    test('Boundary: Empty list of product IDs is handled safely by RemoteDataSource', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode({'message': 'OK', 'updated_count': 0}), 200);
      });
      final ds = CatalogRemoteDataSourceImpl(baseUrl: 'http://pos.test/api', client: client);

      final res = await ds.bulkUpdateProducts([], clearCategory: true);
      expect(res['updated_count'], 0);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['product_ids'], isEmpty);
      expect(body['category_id'], isNull);
    });

    test('Boundary: Unsetting only brand does NOT clear category or supplier', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode({'message': 'OK', 'updated_count': 1}), 200);
      });
      final ds = CatalogRemoteDataSourceImpl(baseUrl: 'http://pos.test/api', client: client);

      await ds.bulkUpdateProducts([55], clearBrand: true);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['product_ids'], [55]);
      expect(body.containsKey('brand_id'), isTrue);
      expect(body['brand_id'], isNull);
      expect(body.containsKey('category_id'), isFalse);
      expect(body.containsKey('supplier_id'), isFalse);
    });
  });

  group('Challenger Hypothesis 2: 50 Products Bulk Quote Preload Stress', () {
    testWidgets('Preloads 50 products into Quote cart and Pos cart without dropping any', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final manyProducts = List.generate(
        50,
        (i) => Product(
          id: 1000 + i,
          name: 'Stress Item $i',
          barcode: '779000000${i.toString().padLeft(4, '0')}',
          internalCode: 'S$i',
          costPrice: 10.0 * (i + 1),
          sellingPrice: 20.0 * (i + 1),
          stock: 100.0,
          active: true,
          isSoldByWeight: i % 2 == 0,
        ),
      );

      final fakeRepo = StressCatalogRepository()..productsToReturn = manyProducts;
      final catalogProvider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      final quoteProvider = QuoteProvider(repository: FakeStressQuoteRepo());
      final posProvider = StressPosProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
            ChangeNotifierProvider<SettingsProvider>(create: (_) => StressSettingsProvider()),
            ChangeNotifierProvider<SupplierProvider>(create: (_) => StressSupplierProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => LocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => StressAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>(create: (_) => StressInventoryAlertsProvider()),
            ChangeNotifierProvider<QuoteProvider>.value(value: quoteProvider),
            ChangeNotifierProvider<PosProvider>.value(value: posProvider),
          ],
          child: const MaterialApp(
            home: CatalogScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check "select all" checkbox
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.first);
      await tester.pump();

      expect(find.text('Lote (50)'), findsOneWidget);
      await tester.tap(find.text('Lote (50)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generar Presupuesto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // All 50 products are now in quote cart
      expect(quoteProvider.cart.length, 50);
      // All 50 products are now in pos cart
      expect(posProvider.cart.length, 50);
      // Selection cleared
      expect(find.text('Lote (50)'), findsNothing);
    });
  });

  group('Challenger Hypothesis 4: Extreme Character Wrapping in POS Grid Cards', () {
    testWidgets('300-char unbroken name with billions in price produces 0 overflow at 320x480', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final extremeProduct = Product(
        id: 9999,
        name: 'WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW',
        internalCode: 'EXTR1',
        costPrice: 999999999.0,
        sellingPrice: 999999999.99,
        stock: 999999.99,
        active: true,
        isSoldByWeight: true,
        imageUrl: 'http://pos.test/storage/huge.png',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 480,
              child: PosQuickAccessCatalogView(
                products: [extremeProduct],
                viewMode: 'grid_medium',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('Challenger Hypothesis 5: PosWatermarkLogo Dynamic Logo Transition', () {
    testWidgets('Dynamically transitioning logo from network to null and back does not crash', (tester) async {
      final settingsProv = StressSettingsProvider(
        initialSettings: const BusinessSettings(
          companyName: 'Test',
          logoUrl: 'http://pos.test/storage/logo1.png',
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProv,
          child: const MaterialApp(
            home: Scaffold(
              body: PosWatermarkLogo(size: 200),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsNothing);

      // Transition to null logo
      settingsProv.updateLogo(null);
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);

      // Transition back to new logo
      settingsProv.updateLogo('http://pos.test/storage/logo2.png');
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Challenger Hypothesis 6: ProductFormDialog Boundary at exactly 449px vs 450px', () {
    Widget buildDialog(Size size) {
      final fakeRepo = StressCatalogRepository();
      final catProv = CatalogProvider(getProductsUseCase: GetProductsUseCase(fakeRepo), repository: fakeRepo);
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogProvider>.value(value: catProv),
          ChangeNotifierProvider<SettingsProvider>(create: (_) => StressSettingsProvider()),
          ChangeNotifierProvider<SupplierProvider>(create: (_) => StressSupplierProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(size: size),
              child: Center(
                child: ProductFormDialog(provider: catProv),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Boundary 449px renders vertical column layout without overflow', (tester) async {
      tester.view.physicalSize = const Size(449, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDialog(const Size(449, 700)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('product_image_container')), findsOneWidget);
    });

    testWidgets('Boundary 450px renders horizontal side-by-side row layout without overflow', (tester) async {
      tester.view.physicalSize = const Size(450, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDialog(const Size(450, 700)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final imageBox = tester.getTopLeft(find.byKey(const ValueKey('product_image_container')));
      final nameField = tester.getTopLeft(find.widgetWithText(TextFormField, 'Nombre del Producto *'));
      expect(imageBox.dx, lessThan(nameField.dx));
    });
  });
}
