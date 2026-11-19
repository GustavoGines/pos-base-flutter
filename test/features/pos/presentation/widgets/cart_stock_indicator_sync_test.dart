import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/pages/pos_screen.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings = const BusinessSettings(
    companyName: 'Test POS',
    afipEnabled: false,
    features: FeatureFlags(fastPos: true, logistics: false),
  );

  @override
  int get assignedRegisterId => 1;
  @override
  BusinessSettings? get settings => _settings;
  @override
  FeatureFlags get features => _settings.features;
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

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerProvider extends ChangeNotifier implements CustomerProvider {
  @override
  List<Customer> get customers => const [];
  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
  @override
  CashRegisterShift? get currentShift => CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openedAt: DateTime.now(),
        openingBalance: 10000.0,
        status: 'open',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  List<Product> _products;
  Product? _lastUpdatedProduct;
  _FakeCatalogProvider(this._products);

  @override
  Product? get lastUpdatedProduct => _lastUpdatedProduct;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  int get catalogOrderVersion => 1;
  @override
  List<Product> get products => _products;
  @override
  List<Category> get categories => const [];
  @override
  List<Brand> get brands => const [];
  @override
  List<Product> get weightOnlyProducts => const [];
  @override
  List<Product> get pinnedExtraProducts => const [];
  @override
  List<Product> getCategoryExtraProducts(int categoryId) => const [];
  @override
  bool isCategoryHydrated(int categoryId) => true;
  @override
  bool get isWeightHydrated => true;
  @override
  bool isPinnedHydrated(Set<int> pinnedIds) => true;
  @override
  Future<void> syncCategoryProducts(int categoryId) async {}
  @override
  Future<void> syncWeightProducts() async {}
  @override
  Future<void> syncPinnedProducts(Set<int> pinnedIds) async {}
  @override
  Future<void> loadMetadata({bool force = false}) async {}
  @override
  void invalidateQuickAccessExtraCaches() {}
  @override
  Future<void> fetchCriticalAlerts() async {}
  @override
  Future<void> prefetchCategories(List<int> categoryIds) async {}
  @override
  Future<void> loadProducts({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
  }) async {}

  @override
  Future<bool> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    double? minStock,
    String? notes,
    int? batchId,
    String? batchCode,
    String? expirationDate,
    String? manufacturedAt,
    double? unitCost,
    String? reasonCode,
  }) async {
    _products = _products.map((p) {
      if (p.id != productId) return p;
      final newStock = type == 'increment' ? p.stock + quantity : p.stock - quantity;
      final updated = p.copyWith(stock: newStock);
      _lastUpdatedProduct = updated;
      return updated;
    }).toList();
    notifyListeners();
    return true;
  }

  @override
  List<Product> applyStockUpdatesToProductList(
    List<Product> list,
    Map<int, double> updatedStockById, {
    Map<int, String?>? updatedExpirationById,
  }) {
    return list.map((p) {
      final s = updatedStockById[p.id];
      return s != null ? p.copyWith(stock: s) : p;
    }).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOfferProvider extends ChangeNotifier implements OfferProvider {
  @override
  List<OfferModel> get activeOffers => const [];
  @override
  bool get isLoading => false;
  @override
  bool get isLoadingActive => false;
  @override
  bool get isLoadingHistory => false;
  @override
  Future<void> loadActiveOffers() async {}
  @override
  double? getDiscountedPrice(Product product) => null;
  @override
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) => null;
  @override
  Set<int> get currentlyActiveOfferProductIds => const {};
  @override
  List<Product> get offerOnlyProducts => const [];
  @override
  Future<void> syncOfferOnlyProducts(Set<int> loadedProductIds, {bool force = false}) async {}
  @override
  void invalidateOfferOnlyProducts() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeQuoteProvider extends ChangeNotifier implements QuoteProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
  String? alertStatus;
  List<dynamic> expAlerts;
  int fetchCalls = 0;

  _FakeInventoryAlertsProvider({
    this.alertStatus,
    this.expAlerts = const [],
  });

  @override
  String? getAlertStatusForProduct(int productId) =>
      productId == 10 ? alertStatus : null;

  @override
  int get totalAlertsCount => (alertStatus != null ? 1 : 0) + expAlerts.length;

  @override
  List<dynamic> get alerts => const [];
  @override
  List<dynamic> get reactiveAlerts => const [];
  @override
  List<dynamic> get expirationAlerts => expAlerts;
  @override
  List<dynamic> get predictiveCriticalAlerts => const [];
  @override
  bool get isLoading => false;
  @override
  String? get error => null;

  @override
  Future<void> fetchAlerts({int threshold = 7}) async {
    fetchCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Ajustar stock positivo desde Ctrl+E refresca InventoryAlertsProvider y apaga el badge rojo Crítico aunque la alerta previa siga caché en memoria',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final ps5 = Product(
        id: 10,
        name: 'CONSOLA PLAY STATION 5 PRO',
        internalCode: '00010',
        barcode: '456456456',
        costPrice: 2500000.0,
        sellingPrice: 2600000.0,
        stock: -3.0,
        minStock: 2.0,
        active: true,
        isSoldByWeight: false,
      );

      final mockClient = MockClient((_) async => http.Response('[]', 200));
      final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProv = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );
      posProv.requestAddToCart(ps5);

      final catalogProv = _FakeCatalogProvider([ps5]);
      // Simulamos caché reactiva obsoleta ("out_of_stock") aún después de ajustar stock
      final alertsProv = _FakeInventoryAlertsProvider(alertStatus: 'out_of_stock');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<SettingsProvider>(create: (_) => _FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => LocalTerminalProvider()),
            ChangeNotifierProvider<CustomerProvider>(create: (_) => _FakeCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(create: (_) => _FakeCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<OfferProvider>(create: (_) => _FakeOfferProvider()),
            ChangeNotifierProvider<QuoteProvider>(create: (_) => _FakeQuoteProvider()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: alertsProv),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Inicialmente con stock -3: muestra badge crítico en el carrito
      expect(find.textContaining('Crítico'), findsOneWidget);
      final initialFetches = alertsProv.fetchCalls;

      // Abrir modal Ctrl+E desde el ícono de editar línea
      await tester.tap(find.byTooltip('Editar Línea en Carrito (Clic / Clic Der. / Ctrl+E)'));
      await tester.pumpAndSettle();

      final zone2 = find.text('Corregir en catálogo (BD)');
      await tester.ensureVisible(zone2);
      await tester.tap(zone2);
      await tester.pumpAndSettle();

      // Subir stock físico de -3 a 8
      final stockField = find.widgetWithText(TextFormField, '-3');
      await tester.ensureVisible(stockField);
      await tester.enterText(stockField, '8');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aplicar y Guardar en BD (Enter)'));
      await tester.pumpAndSettle();

      // Debe haber disparado fetchAlerts() para sincronizar la campanita y apagado Crítico en el carrito
      expect(alertsProv.fetchCalls, greaterThan(initialFetches));
      expect(posProv.cart.first.product.stock, 8.0);
      expect(find.textContaining('Crítico'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Alerta de vencimiento crítico NO queda tapada aunque el stock físico sea positivo',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final expProd = Product(
        id: 10,
        name: 'YOGUR POR VENCER',
        internalCode: '00010',
        costPrice: 500.0,
        sellingPrice: 1000.0,
        stock: 25.0,
        minStock: 2.0,
        active: true,
        isSoldByWeight: false,
      );

      final mockClient = MockClient((_) async => http.Response('[]', 200));
      final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProv = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );
      posProv.requestAddToCart(expProd);

      final catalogProv = _FakeCatalogProvider([expProd]);
      final alertsProv = _FakeInventoryAlertsProvider(
        expAlerts: const [
          {'product_id': 10, 'alert_level': 'critical', 'stage_code': 'expired'},
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<SettingsProvider>(create: (_) => _FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => LocalTerminalProvider()),
            ChangeNotifierProvider<CustomerProvider>(create: (_) => _FakeCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(create: (_) => _FakeCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<OfferProvider>(create: (_) => _FakeOfferProvider()),
            ChangeNotifierProvider<QuoteProvider>(create: (_) => _FakeQuoteProvider()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: alertsProv),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Vencido'), findsOneWidget);
      expect(find.textContaining('Crítico'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
