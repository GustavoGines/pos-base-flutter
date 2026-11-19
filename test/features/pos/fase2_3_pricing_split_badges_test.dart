import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/pages/pos_screen.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/data/models/business_settings_model.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

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
  String get currentPlan => 'premium';
  @override
  bool hasFeature(String featureName) => true;

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
  final List<OfferModel> _offers;

  _TestOfferProvider(this._offers);

  @override
  List<OfferModel> get activeOffers => _offers;
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
      _offers.isNotEmpty ? _offers.first : null;
  @override
  Set<int> get currentlyActiveOfferProductIds =>
      _offers.expand((o) => o.products.map((p) => (p['id'] as num).toInt())).toSet();
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final ps5 = Product(
    id: 1,
    name: 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
    internalCode: '00001',
    costPrice: 2500000.0,
    sellingPrice: 3250000.0,
    stock: 8.0,
    active: true,
    isSoldByWeight: false,
    ivaRate: 10.5,
  );

  final adaptador = Product(
    id: 2,
    name: 'ADAPTADOR TIPO C A USB PARA IPHONE',
    internalCode: '00002',
    costPrice: 30000.0,
    sellingPrice: 55000.0,
    stock: 20.0,
    active: true,
    isSoldByWeight: false,
    ivaRate: 21.0,
  );

  group('Fase 2: DiscountTierOnOffersMode unit & serialization', () {
    test('bestPriceWins vs wholesaleOverridesOffer resolves Mayorista + Oferta cleanly', () {
      // PS5 $3.250.000: Oferta Semanal $2.600.000 vs Mayorista -15% ($2.762.500)
      final bestPrice = ProductPricingCalculator.calculate(
        product: ps5,
        activeTier: PriceTier.wholesale,
        wholesaleFactor: 0.85,
        cardFactor: 1.15,
        promotionalPrice: 2600000.0,
        hasExplicitOffer: true,
        discountTierOnOffersMode: DiscountTierOnOffersMode.bestPriceWins,
      );
      expect(bestPrice.finalUnitPrice, 2600000.0);
      expect(bestPrice.hasActiveOffer, isTrue);
      expect(bestPrice.offerBeatDiscountTier, isTrue);

      // Si Mayorista fuera -30% ($2.275.000 < $2.600.000) -> gana Mayorista sin badge de oferta ganadora
      final wholesaleLower = ProductPricingCalculator.calculate(
        product: ps5,
        activeTier: PriceTier.wholesale,
        wholesaleFactor: 0.70,
        cardFactor: 1.15,
        promotionalPrice: 2600000.0,
        hasExplicitOffer: true,
        discountTierOnOffersMode: DiscountTierOnOffersMode.bestPriceWins,
      );
      expect(wholesaleLower.finalUnitPrice, 2275000.0);
      expect(wholesaleLower.hasActiveOffer, isFalse);
      expect(wholesaleLower.offerBeatDiscountTier, isFalse);

      // Regla Opción 2: Mayorista ignora Ofertas minoristas -> cobra $2.762.500
      final overrideMode = ProductPricingCalculator.calculate(
        product: ps5,
        activeTier: PriceTier.wholesale,
        wholesaleFactor: 0.85,
        cardFactor: 1.15,
        promotionalPrice: 2600000.0,
        hasExplicitOffer: true,
        discountTierOnOffersMode: DiscountTierOnOffersMode.wholesaleOverridesOffer,
      );
      expect(overrideMode.finalUnitPrice, 2762500.0);
      expect(overrideMode.hasActiveOffer, isFalse);
      expect(overrideMode.offerBeatDiscountTier, isFalse);
    });

    test('BusinessSettingsModel parses and serializes discount_tier_on_offers_mode', () {
      final parsedDefault = BusinessSettingsModel.fromJson(const {});
      expect(parsedDefault.discountTierOnOffersMode, 'best_price_wins');

      final parsedOverride = BusinessSettingsModel.fromJson(const {
        'discount_tier_on_offers_mode': 'wholesale_overrides_offer',
      });
      expect(parsedOverride.discountTierOnOffersMode, 'wholesale_overrides_offer');
      expect(
        parsedOverride.toJson()['discount_tier_on_offers_mode'],
        'wholesale_overrides_offer',
      );
    });
  });

  group('Fase 3: Transparent discount vs surcharge split in CartItem', () {
    test('separates offer discountSavings (\$650.000) from Tarjeta surchargeAmount (\$390.000)', () {
      final item = CartItem(
        product: ps5,
        quantity: 1.0,
        activeTier: PriceTier.card,
        wholesaleFactor: 0.85,
        cardFactor: 1.15,
        promotionalPrice: 2600000.0,
        promotionalLabel: 'Oferta Semanal',
        cardSurchargeOnOffersMode: CardSurchargeOnOffersMode.surchargeOnOffer,
      );

      expect(item.regularSubtotal, 3250000.0);
      expect(item.unitPrice, 2990000.0);
      expect(item.subtotal, 2990000.0);
      expect(item.discountSavings, 650000.0);
      expect(item.surchargeAmount, 390000.0);
      expect(item.hasDiscount, isTrue);
      expect(item.hasSurcharge, isTrue);
      expect(
        item.regularSubtotal - item.discountSavings + item.surchargeAmount,
        item.subtotal,
      );
    });
  });

  group('Fases 0, 2 y 3 en PosScreen: Split View, IVA inline, (Mejor precio) y Resumen Transparente', () {
    Future<PosProvider> pumpPosScreen(
      WidgetTester tester, {
      required Size viewport,
      required PriceTier initialTier,
      required DiscountTierOnOffersMode discountMode,
      double splitRatio = 0.42,
    }) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final localTerminal = LocalTerminalProvider();
      await localTerminal.setPosSplitRatio(splitRatio);

      final mockClient = MockClient((_) async => http.Response('[]', 200));
      final ds = PosRemoteDataSourceImpl(
          baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProv = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );

      final settings = BusinessSettings(
        companyName: 'Test POS',
        afipEnabled: true,
        taxCondition: 'Responsable Inscripto',
        enableAdvancedPriceTiers: true,
        globalWholesalePercentage: -15.0,
        globalCardPercentage: 15.0,
        discountTierOnOffersMode: discountMode.apiValue,
        cardSurchargeOnOffersMode: 'surcharge_on_offer',
        features: const FeatureFlags(fastPos: true, multiplePrices: true),
      );
      posProv.updateSettings(settings);
      posProv.setDiscountTierOnOffersMode(discountMode);

      posProv.requestAddToCartWithPromo(
        ps5,
        promotionalPrice: 2600000.0,
        promotionalLabel: 'Oferta Semanal',
        promotionalPeriodType: 'weekly',
      );
      posProv.requestAddToCart(adaptador);
      posProv.setPriceTier(
        initialTier,
        wholesaleFactor: 0.85,
        cardFactor: 1.15,
      );

      final offer = OfferModel(
        id: 77,
        name: 'Oferta Semanal',
        type: 'fixed_price',
        discountAmount: 650000.0,
        periodType: 'weekly',
        isActive: true,
        products: [
          {
            'id': ps5.id,
            'selling_price': ps5.sellingPrice,
            'pivot': {'special_price': 2600000.0},
          },
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _TestSettingsProvider(settings)),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: localTerminal),
            ChangeNotifierProvider<CustomerProvider>(
                create: (_) => _TestCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(
                create: (_) => _TestCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>(
                create: (_) => _TestCatalogProvider([ps5, adaptador])),
            ChangeNotifierProvider<OfferProvider>(
                create: (_) => _TestOfferProvider([offer])),
            ChangeNotifierProvider<QuoteProvider>(
                create: (_) => _TestQuoteProvider()),
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => _TestAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>(
                create: (_) => _TestInventoryAlertsProvider()),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return posProv;
    }

    testWidgets(
      'PosScreen ancho: muestra IVA inline en Fila 2, badge (Mejor precio) bajo Mayorista + bestPriceWins, y desglose separado bajo Lista Tarjeta',
      (tester) async {
        final posProv = await pumpPosScreen(
          tester,
          viewport: const Size(1600, 960),
          initialTier: PriceTier.wholesale,
          discountMode: DiscountTierOnOffersMode.bestPriceWins,
          splitRatio: 0.42,
        );

        expect(tester.takeException(), isNull);
        // Fase 0: Micro-badges de IVA inline presentes (ej. IVA 10.5% / IVA 21%)
        expect(find.text('IVA 10.5%'), findsOneWidget);
        expect(find.text('IVA 21%'), findsOneWidget);

        // Fase 2: PS5 gana con Oferta ($2.600.000 < Mayorista $2.762.500) -> muestra "(Mejor precio)"
        expect(find.textContaining('(Mejor precio)'), findsOneWidget);
        expect(find.text('🏭 Mayorista'), findsAtLeastNWidgets(1)); // Adaptador sin oferta
        expect(find.byTooltip('Lista Mayorista aplicada'), findsOneWidget);

        // Cambiar a regla Mayorista ignora Ofertas -> PS5 cobra $2.762.500 y ya no muestra "(Mejor precio)"
        posProv.setDiscountTierOnOffersMode(
          DiscountTierOnOffersMode.wholesaleOverridesOffer,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('(Mejor precio)'), findsNothing);
        expect(posProv.cart.first.unitPrice, 2762500.0);

        // Fase 3: Cambiar carrito a Lista Tarjeta (+15% s/ oferta) -> desglosa Ahorro y Recargo Lista Tarjeta separados
        posProv.setPriceTier(
          PriceTier.card,
          wholesaleFactor: 0.85,
          cardFactor: 1.15,
        );
        await tester.pumpAndSettle();

        expect(find.text('RESUMEN DEL TICKET'), findsOneWidget);
        expect(find.text('Subtotal Lista:'), findsOneWidget);
        expect(find.textContaining('Ahorro'), findsWidgets);
        expect(find.textContaining('Recargo Lista'), findsOneWidget);
        // PS5: $2.990.000 (ahorro -$650.000, recargo +$390.000) + Adaptador: $63.250 (recargo +$8.250) = $3.053.250
        expect(find.text('\$3.305.000'), findsOneWidget);
        expect(find.text('-\$650.000'), findsOneWidget);
        expect(find.text('+\$398.250'), findsOneWidget);
        expect(find.text('\$3.053.250'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosScreen Split View angosto (cart 384px < 395): acorta etiquetas ("Tarj. s/Of." y micro IVA compacto) sin overflow',
      (tester) async {
        await pumpPosScreen(
          tester,
          viewport: const Size(1280, 900),
          initialTier: PriceTier.card,
          discountMode: DiscountTierOnOffersMode.bestPriceWins,
          splitRatio: 0.30,
        );

        expect(find.textContaining('Tarj. s/Of.'), findsOneWidget);
        expect(find.text('10.5%'), findsOneWidget);
        expect(find.text('21%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosScreen: escanear código no registrado y presionar F3 abre Producto Rápido con el EAN sin error',
      (tester) async {
        await pumpPosScreen(
          tester,
          viewport: const Size(1280, 900),
          initialTier: PriceTier.base,
          discountMode: DiscountTierOnOffersMode.bestPriceWins,
          splitRatio: 0.38,
        );

        final searchField = find.byType(TextField).first;
        await tester.enterText(searchField, '124111SP');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text('Código de Barras No Registrado'), findsOneWidget);
        expect(find.text('EAN escaneado: 124111SP'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.f3);
        await tester.pumpAndSettle();

        expect(find.text('Producto Rápido en Mostrador'), findsOneWidget);
        expect(
          find.textContaining('Código escaneado: "124111SP"'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
