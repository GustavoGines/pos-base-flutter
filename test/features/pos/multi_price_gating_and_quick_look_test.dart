import 'dart:convert';
import 'package:flutter/gestures.dart';
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
import 'package:frontend_desktop/features/catalog/utils/product_share_helper.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/pages/pos_screen.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_price_lookup_dialog.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _TestSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings _settings;

  _TestSettingsProvider(this._settings);

  void setSettings(BusinessSettings next) {
    _settings = next;
    notifyListeners();
  }

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
  String get currentPlan => _settings.licensePlanType ?? 'premium';
  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser =>
      {'id': 1, 'name': 'Admin', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestCustomerProvider extends ChangeNotifier implements CustomerProvider {
  @override
  List<Customer> get customers => const [];
  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestCashRegisterProvider extends ChangeNotifier
    implements CashRegisterProvider {
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

class _TestCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Product> _products;

  _TestCatalogProvider(this._products);

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestOfferProvider extends ChangeNotifier implements OfferProvider {
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
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) =>
      null;
  @override
  Set<int> get currentlyActiveOfferProductIds => const {};
  @override
  List<Product> get offerOnlyProducts => const [];
  @override
  Future<void> syncOfferOnlyProducts(Set<int> loadedProductIds,
      {bool force = false}) async {}
  @override
  void invalidateOfferOnlyProducts() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestQuoteProvider extends ChangeNotifier implements QuoteProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  @override
  String? getAlertStatusForProduct(int productId) => null;
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
  bool get isLoading => false;
  @override
  String? get error => null;
  @override
  Future<void> fetchAlerts({int threshold = 7}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PosProvider _createPosProvider({List<Product> searchResults = const []}) {
  final mockClient = MockClient((req) async {
    if (req.url.path.contains('/products')) {
      final payload = searchResults
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'barcode': p.barcode,
                'internal_code': p.internalCode,
                'cost_price': p.costPrice,
                'selling_price': p.sellingPrice,
                'price_wholesale': p.priceWholesale,
                'price_card': p.priceCard,
                'stock': p.stock,
                'active': p.active,
                'is_sold_by_weight': p.isSoldByWeight,
                'is_combo': p.isCombo,
                'is_service': p.isService,
                'iva_rate': p.ivaRate,
              })
          .toList();
      return http.Response(jsonEncode({'data': payload}), 200);
    }
    return http.Response('[]', 200);
  });
  final ds = PosRemoteDataSourceImpl(
    baseUrl: 'http://localhost/api',
    client: mockClient,
  );
  final repo = PosRepositoryImpl(remoteDataSource: ds);
  return PosProvider(
    processSaleUseCase: ProcessSaleUseCase(repo),
    searchProductsUseCase: SearchProductsUseCase(repo),
    repository: repo,
    remoteDataSource: ds,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  final matero = Product(
    id: 390,
    name: 'MATERO STANLEY - CELESTE- EDICION MESSI 10',
    barcode: 'PROD-390',
    internalCode: 'G3-0390',
    costPrice: 70000.0,
    sellingPrice: 116600.0,
    priceWholesale: 104000.0,
    priceCard: 125840.0,
    stock: 992.0,
    minStock: 2.0,
    active: true,
    isSoldByWeight: false,
    salesCount: 8,
    priceTiers: const [
      {'min_quantity': 3, 'unit_price': 110000.0},
    ],
  );

  final auricular = Product(
    id: 1637,
    name: 'AURICULAR BUDS 8 LITE - AZUL',
    barcode: '2000000PROD-16378',
    internalCode: 'PROD-1637',
    costPrice: 28000.0,
    sellingPrice: 50000.0,
    priceWholesale: null,
    priceCard: null,
    stock: 992.0,
    minStock: 0.0,
    active: true,
    isSoldByWeight: false,
    salesCount: 7,
  );

  group('Multi-Listas: ProductPricingCalculator.buildMultiPricePreviews', () {
    test('returns empty list when multiPriceEnabled is false even with static DB overrides & custom tiers', () {
      final previews = ProductPricingCalculator.buildMultiPricePreviews(
        product: matero,
        multiPriceEnabled: false,
        wholesaleFactor: 0.85,
        cardFactor: 1.15,
        customTiers: const [
          {'name': 'VIP', 'modifier': -10},
        ],
      );

      expect(previews, isEmpty);
    });

    test('computes dynamic tiers + custom tiers when product has null fixed overrides and multiPriceEnabled is true', () {
      final previews = ProductPricingCalculator.buildMultiPricePreviews(
        product: auricular,
        multiPriceEnabled: true,
        wholesaleFactor: 0.85,
        cardFactor: 1.15,
        customTiers: const [
          {'name': 'VIP', 'modifier': -20},
          {'name': 'Cuotas 6x', 'modifier': 30},
        ],
      );

      expect(previews.length, 4);
      expect(previews[0].label, 'Mayorista');
      expect(previews[0].price, 42500.0);
      expect(previews[0].isFixedOverride, isFalse);

      expect(previews[1].label, 'Tarjeta');
      expect(previews[1].price, 57500.0);
      expect(previews[1].isFixedOverride, isFalse);

      expect(previews[2].label, 'VIP');
      expect(previews[2].price, 40000.0);
      expect(previews[2].isCustomTier, isTrue);

      expect(previews[3].label, 'Cuotas 6x');
      expect(previews[3].price, 65000.0);
      expect(previews[3].isCustomTier, isTrue);
    });

    test('marks legacy fixed DB overrides with isFixedOverride = true when used', () {
      final previews = ProductPricingCalculator.buildMultiPricePreviews(
        product: matero,
        multiPriceEnabled: true,
        wholesaleFactor: 0.85,
        cardFactor: 1.15,
      );

      expect(previews.length, 2);
      expect(previews[0].label, 'Mayorista');
      expect(previews[0].price, 104000.0);
      expect(previews[0].isFixedOverride, isTrue);

      expect(previews[1].label, 'Tarjeta');
      expect(previews[1].price, 125840.0);
      expect(previews[1].isFixedOverride, isTrue);
    });
  });

  group('Multi-Listas: PosProvider gating & ProductShareHelper', () {
    test('PosProvider resets active & default tier to base when Multi-Listas transitions ON -> OFF', () {
      final pos = _createPosProvider();
      const enabledSettings = BusinessSettings(
        companyName: 'Test POS',
        enableAdvancedPriceTiers: true,
        globalWholesalePercentage: -15.0,
        globalCardPercentage: 15.0,
        features: FeatureFlags(fastPos: true, multiplePrices: true),
      );
      pos.updateSettings(enabledSettings);
      pos.setDefaultTier('wholesale', 'Mayorista');
      pos.setPriceTier(PriceTier.wholesale, wholesaleFactor: 0.85, cardFactor: 1.15);
      expect(pos.activeTier, PriceTier.wholesale);

      const disabledSettings = BusinessSettings(
        companyName: 'Test POS',
        enableAdvancedPriceTiers: false,
        globalWholesalePercentage: -15.0,
        globalCardPercentage: 15.0,
        features: FeatureFlags(fastPos: true, multiplePrices: false),
      );
      pos.updateSettings(disabledSettings);

      expect(pos.activeTier, PriceTier.base);
      pos.clearCart();
      expect(pos.activeTier, PriceTier.base);
    });

    test('ProductShareHelper.formatProductShareText omits wholesale/card when includeMultiPrices is false', () {
      final withoutMulti = ProductShareHelper.formatProductShareText(
        matero,
        includeMultiPrices: false,
      );
      expect(withoutMulti, contains('MATERO STANLEY'));
      expect(withoutMulti, contains('\$116.600'));
      expect(withoutMulti, isNot(contains('Mayorista')));
      expect(withoutMulti, isNot(contains('Tarjeta')));

      final withMulti = ProductShareHelper.formatProductShareText(
        matero,
        includeMultiPrices: true,
      );
      expect(withMulti, contains('Mayorista: \$104.000'));
      expect(withMulti, contains('Tarjeta: \$125.840'));
    });
  });

  group('Multi-Listas: PosScreen Quick Look & PosPriceLookupDialog UI', () {
    Future<void> pumpPosQuickAccess(
      WidgetTester tester, {
      required _TestSettingsProvider settingsProv,
      LocalTerminalProvider? localTerminal,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final terminal = localTerminal ?? LocalTerminalProvider();
      final posProv = _createPosProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: terminal,
            ),
            ChangeNotifierProvider<CustomerProvider>(
              create: (_) => _TestCustomerProvider(),
            ),
            ChangeNotifierProvider<CashRegisterProvider>(
              create: (_) => _TestCashRegisterProvider(),
            ),
            ChangeNotifierProvider<CatalogProvider>(
              create: (_) => _TestCatalogProvider([matero, auricular]),
            ),
            ChangeNotifierProvider<OfferProvider>(
              create: (_) => _TestOfferProvider(),
            ),
            ChangeNotifierProvider<QuoteProvider>(
              create: (_) => _TestQuoteProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => _TestAuthProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>(
              create: (_) => _TestInventoryAlertsProvider(),
            ),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Quick Look con Multi-Listas DESACTIVADA oculta Mayorista/Tarjeta aunque existan precios fijos en BD, pero mantiene tramos por cantidad y limpia lista fijada',
      (tester) async {
        final localTerminal = LocalTerminalProvider();
        await localTerminal.setLockedPriceTier('wholesale');

        final settingsProv = _TestSettingsProvider(
          const BusinessSettings(
            companyName: 'Test POS',
            enableAdvancedPriceTiers: true,
            globalWholesalePercentage: -15.0,
            globalCardPercentage: 15.0,
            features: FeatureFlags(fastPos: true, multiplePrices: false),
          ),
        );

        await pumpPosQuickAccess(
          tester,
          settingsProv: settingsProv,
          localTerminal: localTerminal,
        );

        // Lista fijada obsoleta se limpió al estar Multi-Listas desactivada
        expect(localTerminal.lockedPriceTier, 'none');

        // Clic derecho en tarjeta MATERO STANLEY en Acceso Rápido
        final materoCard = find.textContaining('MATERO STANLEY').first;
        await tester.tap(materoCard, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        expect(find.text('Precio Base'), findsOneWidget);
        expect(find.text('\$116.600'), findsWidgets);
        expect(find.textContaining('Precio Mayorista'), findsNothing);
        expect(find.textContaining('Precio Tarjeta'), findsNothing);
        // Tramos por cantidad siguen visibles porque aplican sobre Base
        expect(find.text('Tramos por cantidad:'), findsOneWidget);
        expect(find.text('3+ unidades'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Quick Look con Multi-Listas ACTIVADA y ignoreProductFixedPrices=false calcula listas globales para productos sin override y marca (Fijo) los overrides estáticos',
      (tester) async {
        final settingsProv = _TestSettingsProvider(
          const BusinessSettings(
            companyName: 'Test POS',
            enableAdvancedPriceTiers: true,
            ignoreProductFixedPrices: false,
            globalWholesalePercentage: -15.0,
            globalCardPercentage: 15.0,
            customPriceTiers: [
              {'name': 'Lista Especial', 'modifier': 10},
            ],
            features: FeatureFlags(fastPos: true, multiplePrices: true),
          ),
        );

        await pumpPosQuickAccess(tester, settingsProv: settingsProv);

        // 1) Producto sin overrides estáticos (AURICULAR $50.000): muestra cálculos globales + custom
        await tester.tap(
          find.textContaining('AURICULAR BUDS').first,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Precio Base'), findsOneWidget);
        expect(find.text('Precio Mayorista'), findsOneWidget);
        expect(find.text('\$42.500'), findsOneWidget);
        expect(find.text('Precio Tarjeta'), findsOneWidget);
        expect(find.text('\$57.500'), findsOneWidget);
        expect(find.text('Precio Lista Especial'), findsOneWidget);
        expect(find.text('\$55.000'), findsOneWidget);

        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();

        // 2) Producto con overrides estáticos (MATERO STANLEY): distingue "(Fijo)"
        await tester.tap(
          find.textContaining('MATERO STANLEY').first,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Precio Mayorista (Fijo)'), findsOneWidget);
        expect(find.text('\$104.000'), findsOneWidget);
        expect(find.text('Precio Tarjeta (Fijo)'), findsOneWidget);
        expect(find.text('\$125.840'), findsOneWidget);
        expect(find.text('Precio Lista Especial'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Quick Look por defecto (ignoreProductFixedPrices=true) aplica % globales sobre productos con precio fijo heredado y actualiza al cambiar de 15% a 5%',
      (tester) async {
        final settingsProv = _TestSettingsProvider(
          const BusinessSettings(
            companyName: 'Test POS',
            enableAdvancedPriceTiers: true,
            globalWholesalePercentage: -15.0,
            globalCardPercentage: 15.0,
            features: FeatureFlags(fastPos: true, multiplePrices: true),
          ),
        );

        await pumpPosQuickAccess(tester, settingsProv: settingsProv);

        // MATERO STANLEY ($116.600) con -15% ($99.110) y +15% ($134.090), ignorando los fijos ($104.000 / $125.840)
        await tester.tap(
          find.textContaining('MATERO STANLEY').first,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Precio Mayorista'), findsOneWidget);
        expect(find.text('Precio Mayorista (Fijo)'), findsNothing);
        expect(find.text('\$99.110'), findsOneWidget);
        expect(find.text('\$134.090'), findsOneWidget);

        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();

        // Cambiar descuento Mayorista de 15% a 5% (incluso escrito positivo 5.0) y Tarjeta a 10%
        settingsProv.setSettings(
          const BusinessSettings(
            companyName: 'Test POS',
            enableAdvancedPriceTiers: true,
            globalWholesalePercentage: 5.0,
            globalCardPercentage: 10.0,
            features: FeatureFlags(fastPos: true, multiplePrices: true),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.textContaining('MATERO STANLEY').first,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        // $116.600 * 0.95 = $110.770 y $116.600 * 1.10 = $128.260
        expect(find.text('Precio Mayorista'), findsOneWidget);
        expect(find.text('\$110.770'), findsOneWidget);
        expect(find.text('Precio Tarjeta'), findsOneWidget);
        expect(find.text('\$128.260'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosPriceLookupDialog (F5) oculta listas cuando Multi-Listas está OFF y muestra listas calculadas + (Fijo) cuando está ON',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final settingsProv = _TestSettingsProvider(
          const BusinessSettings(
            companyName: 'Test POS',
            enableAdvancedPriceTiers: false,
            globalWholesalePercentage: -15.0,
            globalCardPercentage: 15.0,
            features: FeatureFlags(fastPos: true, multiplePrices: false),
          ),
        );
        final posProv = _createPosProvider(searchResults: [auricular]);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<CatalogProvider>(
                create: (_) => _TestCatalogProvider([auricular]),
              ),
              ChangeNotifierProvider<OfferProvider>(
                create: (_) => _TestOfferProvider(),
              ),
              ChangeNotifierProvider<SettingsProvider>.value(
                value: settingsProv,
              ),
              ChangeNotifierProvider<SupplierProvider>(
                create: (_) => _TestSupplierProvider(),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () => PosPriceLookupDialog.show(ctx),
                    child: const Text('Abrir F5'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir F5'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '2000000PROD-16378');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Con Multi-Listas OFF: oculta Mayorista y Tarjeta
        expect(find.textContaining('AURICULAR BUDS'), findsWidgets);
        expect(find.text('Mayorista'), findsNothing);
        expect(find.text('Tarjeta'), findsNothing);

        // Reactivar Multi-Listas en vivo: aparecen Mayorista (-15%) y Tarjeta (+15%)
        settingsProv.setSettings(
          const BusinessSettings(
            companyName: 'Test POS',
            enableAdvancedPriceTiers: true,
            globalWholesalePercentage: -15.0,
            globalCardPercentage: 15.0,
            features: FeatureFlags(fastPos: true, multiplePrices: true),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Mayorista'), findsOneWidget);
        expect(find.text('\$42.500'), findsOneWidget);
        expect(find.text('Tarjeta'), findsOneWidget);
        expect(find.text('\$57.500'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
