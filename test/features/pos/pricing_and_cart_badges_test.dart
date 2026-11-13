import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
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
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _TestSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  _TestSettingsProvider({BusinessSettings? settings})
      : _settings = settings ??
            const BusinessSettings(
              companyName: 'Dev4U Test',
              afipEnabled: true,
              taxCondition: 'IVA Responsable Inscripto',
              enableAdvancedPriceTiers: true,
              globalCardPercentage: 15.0,
              globalWholesalePercentage: -15.0,
              customPriceTiers: [
                {'name': 'Jubilados', 'modifier': -5},
              ],
              features: FeatureFlags(
                fastPos: true,
                multiplePrices: true,
                logistics: false,
              ),
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

class _TestCustomerProvider extends ChangeNotifier
    implements CustomerProvider {
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
  Map<String, dynamic>? lastUpdateData;

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
  Future<bool> updateProduct(int id, Map<String, dynamic> data) async {
    lastUpdateData = Map<String, dynamic>.from(data);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestOfferProvider extends ChangeNotifier implements OfferProvider {
  final Map<int, double> discountedPrices;
  final Map<int, OfferModel> offersByProduct;

  _TestOfferProvider({
    this.discountedPrices = const {},
    this.offersByProduct = const {},
  });

  @override
  List<OfferModel> get activeOffers => offersByProduct.values.toList();
  @override
  bool get isLoading => false;
  @override
  bool get isLoadingActive => false;
  @override
  bool get isLoadingHistory => false;
  @override
  Future<void> loadActiveOffers() async {}
  @override
  double? getDiscountedPrice(Product product) => discountedPrices[product.id];
  @override
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) =>
      offersByProduct[productId];
  @override
  Set<int> get currentlyActiveOfferProductIds => discountedPrices.keys.toSet();
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
  bool get isLoading => false;
  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  final Map<int, String> statusByProduct;
  final List<dynamic> expAlerts;

  _TestInventoryAlertsProvider({
    this.statusByProduct = const {},
    this.expAlerts = const [],
  });

  @override
  String? getAlertStatusForProduct(int productId) => statusByProduct[productId];
  @override
  int get totalAlertsCount => statusByProduct.length + expAlerts.length;
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
  Future<void> fetchAlerts({int threshold = 7}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PosProvider _buildPosProvider() {
  final mockClient = MockClient((_) async => http.Response('[]', 200));
  final ds = PosRemoteDataSourceImpl(
      baseUrl: 'http://localhost/api', client: mockClient);
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
    SharedPreferences.setMockInitialValues({});
  });

  final ps5 = Product(
    id: 1,
    name: 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
    internalCode: '00001',
    costPrice: 2500000.0,
    sellingPrice: 3250000.0,
    priceCard: 3055250.0, // Precio fijo Tarjeta obsoleto (< sellingPrice)
    stock: 8.0,
    minStock: 2.0,
    ivaRate: 10.5,
    active: true,
    isSoldByWeight: false,
  );

  final adaptador = Product(
    id: 2,
    name: 'ADAPTADOR TIPO C A USB PARA IPHONE',
    internalCode: '00002',
    costPrice: 30000.0,
    sellingPrice: 55000.0,
    stock: 20.0,
    minStock: 2.0,
    ivaRate: 21.0,
    active: true,
    isSoldByWeight: false,
  );

  final monitor = Product(
    id: 3,
    name: 'Monitor Curvo Samsung 24',
    internalCode: '00003',
    costPrice: 150000.0,
    sellingPrice: 231000.0,
    stock: 2.0,
    minStock: 2.0,
    ivaRate: 21.0,
    active: true,
    isSoldByWeight: false,
  );

  group('ProductPricingCalculator & Settings Integration', () {
    test('Elimina ruido de coma flotante (55000 * 1.15 -> \$63.250 sin ,00)',
        () {
      final calc = ProductPricingCalculator.calculate(
        product: adaptador,
        activeTier: PriceTier.card,
        cardFactor: 1.15,
      );

      expect(calc.finalUnitPrice, 63250.0);
      expect(calc.finalUnitPrice.toCurrency(), '63.250');
      expect(calc.crossedOutPrice, isNull);
      expect(calc.hasTierSurcharge, isTrue);
    });

    test('Respeta los 3 modos de Tarjeta (+15%) sobre producto con Oferta activa',
        () {
      // 1. Default: surcharge_on_offer -> 2.600.000 * 1.15 = 2.990.000
      final onOffer = ProductPricingCalculator.calculate(
        product: ps5,
        activeTier: PriceTier.card,
        cardFactor: 1.15,
        promotionalPrice: 2600000.0,
        hasExplicitOffer: true,
        cardSurchargeOnOffersMode: CardSurchargeOnOffersMode.surchargeOnOffer,
      );
      expect(onOffer.finalUnitPrice, 2990000.0);
      expect(onOffer.preSurchargeUnitPrice, 2600000.0);
      expect(onOffer.crossedOutPrice, 3250000.0);
      expect(onOffer.hasActiveOffer, isTrue);
      expect(onOffer.hasSurchargeOnOffer, isTrue);

      // 2. card_overrides_offer -> ignora oferta y cobra tarifa Tarjeta (+15% sin stale priceCard)
      final ps5NoStaleCard = ps5.copyWith(priceCard: 0.0);
      final overrideOffer = ProductPricingCalculator.calculate(
        product: ps5NoStaleCard,
        activeTier: PriceTier.card,
        cardFactor: 1.15,
        promotionalPrice: 2600000.0,
        hasExplicitOffer: true,
        cardSurchargeOnOffersMode: CardSurchargeOnOffersMode.cardOverridesOffer,
      );
      expect(overrideOffer.finalUnitPrice, 3737500.0);
      expect(overrideOffer.crossedOutPrice, isNull);
      expect(overrideOffer.hasActiveOffer, isFalse);
      expect(overrideOffer.hasTierSurcharge, isTrue);

      // 3. offer_no_surcharge -> mantiene 2.600.000 e indica exento de recargo
      final exempt = ProductPricingCalculator.calculate(
        product: ps5,
        activeTier: PriceTier.card,
        cardFactor: 1.15,
        promotionalPrice: 2600000.0,
        hasExplicitOffer: true,
        cardSurchargeOnOffersMode: CardSurchargeOnOffersMode.offerNoSurcharge,
      );
      expect(exempt.finalUnitPrice, 2600000.0);
      expect(exempt.crossedOutPrice, 3250000.0);
      expect(exempt.hasActiveOffer, isTrue);
      expect(exempt.isOfferSurchargeExempt, isTrue);
    });

    test(
        'En lista con descuento (Jubilados -5%), el tachado siempre es sellingPrice (\$3.250.000) y nunca \$3.087.500',
        () {
      final ps5JubOffer = ProductPricingCalculator.calculate(
        product: ps5,
        activeTier: PriceTier.custom,
        customFactor: 0.95,
        promotionalPrice: 2600000.0,
        hasExplicitOffer: true,
      );
      expect(ps5JubOffer.finalUnitPrice, 2600000.0);
      expect(ps5JubOffer.crossedOutPrice, 3250000.0);
      expect(ps5JubOffer.hasActiveOffer, isTrue);

      final monitorJub = ProductPricingCalculator.calculate(
        product: monitor,
        activeTier: PriceTier.custom,
        customFactor: 0.95,
      );
      expect(monitorJub.finalUnitPrice, 219450.0);
      expect(monitorJub.crossedOutPrice, 231000.0);
      expect(monitorJub.hasTierDiscount, isTrue);
    });

    test('BusinessSettingsModel serializa y deserializa card_surcharge_on_offers_mode',
        () {
      final parsed = BusinessSettingsModel.fromJson({
        'company_name': 'Mi Comercio',
        'card_surcharge_on_offers_mode': 'card_overrides_offer',
      });
      expect(parsed.cardSurchargeOnOffersMode, 'card_overrides_offer');
      expect(parsed.toJson()['card_surcharge_on_offers_mode'],
          'card_overrides_offer');

      final fallback = BusinessSettingsModel.fromJson({
        'company_name': 'Mi Comercio',
      });
      expect(fallback.cardSurchargeOnOffersMode, 'surcharge_on_offer');
    });

    test(
        'PosProvider propaga cardSurchargeOnOffersMode al carrito y separa costo manual vs precio manual',
        () {
      final pos = _buildPosProvider();
      pos.requestAddToCartWithPromo(
        ps5,
        promotionalPrice: 2600000.0,
        promotionalLabel: 'Oferta Semanal',
        promotionalPeriodType: 'weekly',
      );
      pos.setPriceTier(PriceTier.card, cardFactor: 1.15);

      expect(pos.cart.first.unitPrice, 2990000.0);
      expect(pos.cart.first.hasSurchargeOnOffer, isTrue);

      pos.updateSettings(const BusinessSettings(
        cardSurchargeOnOffersMode: 'offer_no_surcharge',
      ));
      expect(pos.cart.first.unitPrice, 2600000.0);
      expect(pos.cart.first.isOfferSurchargeExempt, isTrue);

      // Ajustar solo el costo no activa hasManualSellingPriceOverride ni borra oferta
      pos.updateCartItemCustomDescription(
        pos.cart.first,
        newCostPrice: 2400000.0,
      );
      expect(pos.cart.first.hasManualCostOverride, isTrue);
      expect(pos.cart.first.hasManualSellingPriceOverride, isFalse);
      expect(pos.cart.first.hasActiveOffer, isTrue);
    });
  });

  group('UI Carrito Unificado, Acceso Rápido y Catálogo', () {
    testWidgets(
        'PosScreen Tarjeta (+15%) aplica +15% sobre oferta, redondea \$63.250 sin ,00 y unifica badges en 1 fila ordenada',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pos = _buildPosProvider();
      pos.setPriceTier(PriceTier.card, cardFactor: 1.15);
      pos.requestAddToCartWithPromo(
        ps5,
        promotionalPrice: 2600000.0,
        promotionalLabel: 'PS5 Gamer',
        promotionalPeriodType: 'weekly',
      );
      pos.requestAddToCart(adaptador);
      pos.requestAddToCart(monitor);

      final catalogProv = _TestCatalogProvider([ps5, adaptador, monitor]);
      final offerProv = _TestOfferProvider(
        discountedPrices: {1: 2600000.0},
        offersByProduct: {
          1: OfferModel(
            id: 10,
            name: 'PS5 Gamer',
            type: 'percentage',
            discountPercentage: 20,
            periodType: 'weekly',
            startDate: DateTime.now().subtract(const Duration(days: 1)),
            endDate: DateTime.now().add(const Duration(days: 5)),
            isActive: true,
            products: [
              {'id': 1, 'selling_price': '3250000.0'},
            ],
          ),
        },
      );
      final alertsProv = _TestInventoryAlertsProvider(
        statusByProduct: {3: 'out_of_stock'},
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: pos),
            ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _TestSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(
                create: (_) => LocalTerminalProvider()),
            ChangeNotifierProvider<CustomerProvider>(
                create: (_) => _TestCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(
                create: (_) => _TestCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<OfferProvider>.value(value: offerProv),
            ChangeNotifierProvider<QuoteProvider>(
                create: (_) => _TestQuoteProvider()),
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => _TestAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
                value: alertsProv),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Adaptador 55000 * 1.15 se formatea exacto sin ',00' tanto en Acceso Rápido como en Carrito
      expect(find.text('\$63.250'), findsWidgets);
      expect(find.textContaining('63.250,00'), findsNothing);

      // PS5 en Tarjeta + Oferta Semanal cobra $2.990.000 y muestra chip unificado
      expect(find.text('\$2.990.000'), findsWidgets);
      expect(find.text('💳 Tarjeta s/ Oferta (+15%)'), findsOneWidget);

      // En Acceso Rápido, PS5 tacha el precio regular $3.250.000 (nunca stale priceCard $3.055.250)
      expect(find.text('\$3.250.000'), findsWidgets);
      expect(find.text('\$3.055.250'), findsNothing);

      // Orden de chips compactos en Monitor: stock crítico con cantidad y etiqueta Tarjeta
      expect(find.text('💳 Tarjeta'), findsWidgets);
      expect(find.textContaining('🔴 Crítico: 1 u'), findsOneWidget);
      expect(find.text('IVA 10.5%'), findsOneWidget);
      expect(find.text('IVA 21%'), findsWidgets);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Orden recuperada (#127) muestra Precio pactado + Costo sin falsa Oferta y distingue Vence Xd',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pos = _buildPosProvider();
      pos.recallOrderToCart({
        'id': 127,
        'shipping_cost': '0',
        'price_list': 'base',
        'items': [
          {
            'product_id': 1,
            'product_name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
            'quantity': '1',
            'unit_price': '2080000',
            'unit_cost_price': '2450000', // costo ajustado distinto al catálogo
            'iva_rate': '10.5',
            'product': {
              'id': 1,
              'name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
              'internal_code': '00001',
              'cost_price': '2500000',
              'selling_price': '3250000',
              'iva_rate': '10.5',
              'stock': '8',
              'min_stock': '2',
              'is_sold_by_weight': false,
            },
          },
          {
            'product_id': 3,
            'product_name': 'Monitor Curvo Samsung 24',
            'quantity': '1',
            'unit_price': '231000',
            'product': {
              'id': 3,
              'name': 'Monitor Curvo Samsung 24',
              'internal_code': '00003',
              'cost_price': '150000',
              'selling_price': '231000',
              'iva_rate': '21',
              'stock': '10',
              'min_stock': '2',
              'is_sold_by_weight': false,
            },
          },
        ],
      });

      final catalogProv = _TestCatalogProvider([ps5, monitor]);
      final alertsProv = _TestInventoryAlertsProvider(
        expAlerts: const [
          {
            'product_id': 3,
            'alert_level': 'critical',
            'stage_code': 'near_expiry',
            'days_until_expiry': 2,
            'expiration_date': '2026-11-15',
          },
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: pos),
            ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _TestSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(
                create: (_) => LocalTerminalProvider()),
            ChangeNotifierProvider<CustomerProvider>(
                create: (_) => _TestCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(
                create: (_) => _TestCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<OfferProvider>(
                create: (_) => _TestOfferProvider()),
            ChangeNotifierProvider<QuoteProvider>(
                create: (_) => _TestQuoteProvider()),
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => _TestAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
                value: alertsProv),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('📋 Precio pactado'), findsOneWidget);
      expect(find.text('✏️ Costo'), findsOneWidget);
      expect(find.textContaining('🏷️ Oferta'), findsNothing);
      expect(find.textContaining('Oferta Semanal'), findsNothing);
      expect(find.textContaining('Precio/Costo ajustado'), findsNothing);
      expect(find.text('⏰ Vence 2d'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'ProductFormDialog advierte priceCard fijo desactualizado y permite limpiarlo al guardar',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProv = _TestCatalogProvider([ps5]);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _TestSettingsProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SupplierProvider>(
                create: (_) => _TestSupplierProvider()),
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => _TestAuthProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ProductFormDialog(
                provider: catalogProv,
                product: ps5,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Precio Tarjeta fijo (\$3.055.250) menor al Precio Venta'),
        findsOneWidget,
      );

      final clearCheckbox =
          find.text('Limpiar precio Tarjeta fijo al guardar (usar % global)');
      await tester.ensureVisible(clearCheckbox);
      await tester.tap(clearCheckbox);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastUpdateData, isNotNull);
      expect(catalogProv.lastUpdateData!.containsKey('price_card'), isTrue);
      expect(catalogProv.lastUpdateData!['price_card'], isNull);
    });
  });
}
