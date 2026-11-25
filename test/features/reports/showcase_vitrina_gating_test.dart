import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/presentation/widgets/plan_upgrade_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/premium_showcase_card.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/checks/domain/entities/third_party_check.dart';
import 'package:frontend_desktop/features/checks/presentation/providers/check_provider.dart';
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
import 'package:frontend_desktop/features/reports/data/datasources/inventory_alerts_datasource.dart';
import 'package:frontend_desktop/features/reports/data/datasources/reports_remote_datasource.dart';
import 'package:frontend_desktop/features/reports/presentation/pages/reports_screen.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/inventory_alerts_widget.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_management_tab.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_purchases_report_view.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_sales_report_view.dart';
import 'package:frontend_desktop/features/settings/data/models/business_settings_model.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  _FakeSettingsProvider(this._settings);

  @override
  int get assignedRegisterId => 1;
  @override
  BusinessSettings? get settings => _settings;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => _settings.licensePlanType ?? 'basic';
  @override
  FeatureFlags get features => _settings.features;
  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);
  @override
  bool get isLicenseActive => true;
  @override
  bool get isHardwareStore => _settings.isHardwareStore;
  @override
  bool get isIibbPerceptionAgent => false;
  @override
  List<String> get allowedAddons => _settings.licenseFeatures;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser =>
      const {'id': 1, 'name': 'Admin Vitrina', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  bool get autoOpenCashDrawer => false;
  @override
  String get scaleComPort => '';
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';
  @override
  String get lockedPriceTier => 'none';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCheckProvider extends ChangeNotifier implements CheckProvider {
  @override
  List<ThirdPartyCheck> get checks => const [];
  @override
  Future<void> loadChecks() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  final List<dynamic> _reactiveAlerts;
  _FakeInventoryAlertsProvider({List<dynamic> reactiveAlerts = const []})
      : _reactiveAlerts = reactiveAlerts;

  @override
  List<dynamic> get alerts => const [];
  @override
  List<dynamic> get reactiveAlerts => _reactiveAlerts;
  @override
  List<dynamic> get expirationAlerts => const [];
  @override
  List<dynamic> get deficitAlerts => const [];
  @override
  List<dynamic> get predictiveCriticalAlerts => const [];
  @override
  int get totalAlertsCount => _reactiveAlerts.length;
  @override
  bool get isLoading => false;
  @override
  String? get error => null;
  @override
  String? getAlertStatusForProduct(int productId) => null;
  @override
  Future<void> fetchAlerts({int threshold = 7}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Product> _products;
  _FakeCatalogProvider({List<Product> products = const []})
      : _products = products;

  @override
  List<Product> get products => _products;
  @override
  List<Category> get categories => const [];
  @override
  List<Brand> get brands => const [];
  @override
  List<Rubro> get rubros => const [];
  @override
  List<Product> get criticalAlerts => const [];
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
  Future<void> prefetchCategories(List<int> categoryIds) async {}
  @override
  void invalidateQuickAccessExtraCaches() {}
  @override
  bool get isLoading => false;
  @override
  int get currentPage => 1;
  @override
  int get lastPage => 1;
  @override
  bool get hasNextPage => false;
  @override
  bool get hasPrevPage => false;
  @override
  String get sortBy => 'name';
  @override
  String get sortDirection => 'asc';
  @override
  String? get errorMessage => null;
  @override
  int get catalogOrderVersion => 1;
  @override
  Future<void> loadMetadata({bool force = false}) async {}
  @override
  Future<void> loadBrands() async {}
  @override
  Future<void> fetchCriticalAlerts() async {}
  @override
  Future<void> loadProducts({
    int page = 1,
    String? search,
    int? categoryId,
    int? brandId,
    int? supplierId,
    String? sortBy,
    String? sortDirection,
    bool? activeOnly,
    int? rubroId,
    int? perPage,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchSuppliers({String? search}) async {}

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

class _FakeCashRegisterProvider extends ChangeNotifier
    implements CashRegisterProvider {
  @override
  CashRegisterShift? get currentShift => CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openedAt: DateTime.now(),
        openingBalance: 10000,
        status: 'open',
      );

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
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) =>
      null;
  @override
  Set<int> get currentlyActiveOfferProductIds => const {};
  @override
  List<Product> get offerOnlyProducts => const [];
  @override
  Future<void> syncOfferOnlyProducts(
    Set<int> loadedProductIds, {
    bool force = false,
  }) async {}
  @override
  void invalidateOfferOnlyProducts() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeQuoteProvider extends ChangeNotifier implements QuoteProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PosProvider _buildPosProvider() {
  final client = MockClient((req) async {
    if (req.url.path.contains('/products')) {
      return http.Response('{"data":[]}', 200);
    }
    return http.Response('[]', 200);
  });
  final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: client);
  final repo = PosRepositoryImpl(remoteDataSource: ds);
  return PosProvider(
    processSaleUseCase: ProcessSaleUseCase(repo),
    searchProductsUseCase: SearchProductsUseCase(repo),
    repository: repo,
    remoteDataSource: ds,
  );
}

ReportsProvider _buildReportsProvider() {
  final client = MockClient((req) async {
    if (req.url.path.contains('/reports/monthly-balance')) {
      return http.Response(
        jsonEncode({
          'months': [
            {
              'period': '2026-11',
              'label': 'Nov 2026',
              'total_revenue': 85000,
              'total_cost': 60000,
              'total_profit': 25000,
              'margin_pct': 29.4,
            },
          ],
          'totals': {
            'total_revenue': 85000,
            'total_cost': 60000,
            'total_profit': 25000,
            'avg_margin_pct': 29.4,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (req.url.path.contains('/reports/vat-sales')) {
      return http.Response(
        jsonEncode({
          'summary': {
            'total_net': 20000,
            'total_iva': 4200,
            'net_21': 20000,
            'iva_21': 4200,
            'net_105': 0,
            'iva_105': 0,
            'net_fiscal_total': 24200,
            'total_invoiced': 24200,
            'total_credit_notes': 0,
          },
          'vouchers': [],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({
        'previous_period': {'revenue': 50000, 'profit': 15000},
        'daily_evolution': [
          {'date': '2026-11-24', 'daily_revenue': 85000},
        ],
        'data': [
          {
            'category_name': 'Almacén',
            'items_sold': 10,
            'total_revenue': 85000,
            'total_profit': 25000,
            'revenue_with_cost': 85000,
            'items_with_cost': 10,
            'total_items': 10,
            'products': [],
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return ReportsProvider(
    dataSource: ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: client),
    balanceDataSource: InventoryAlertsDataSource(baseUrl: 'http://localhost/api', client: client),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_api': 'http://localhost/api',
      'disable_pusher': true,
    });
  });

  group('Efecto Vitrina — Plan Básico vs Premium y Aislamiento por Rubro', () {
    testWidgets('1. GlobalAppBar permite ingresar a /reports en Plan Básico sin candado', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsProv = _FakeSettingsProvider(
        const BusinessSettings(
          companyName: 'Super Básico',
          licensePlanType: 'basic',
          features: FeatureFlags(fastPos: true, advancedReports: false),
        ),
      );

      var navigatedToReports = false;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: _FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: _FakeInventoryAlertsProvider()),
          ],
          child: MaterialApp(
            routes: {
              '/reports': (_) {
                navigatedToReports = true;
                return const Scaffold(body: Text('Reports Target'));
              },
            },
            home: const Scaffold(
              appBar: GlobalAppBar(currentRoute: '/pos'),
              body: SizedBox.shrink(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Finanzas'));
      await tester.pumpAndSettle();
      expect(find.text('Reportes Gerenciales'), findsOneWidget);

      await tester.tap(find.text('Reportes Gerenciales'));
      await tester.pumpAndSettle();

      expect(navigatedToReports, isTrue);
      expect(find.byType(PlanUpgradeDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2. ReportsScreen en Plan Básico habilita Reportes Generales (con Ganancia/Margen/Exportaciones) y Balance Mensual, dejando en vitrina PRO Rubro/Gastos/Consumo', (tester) async {
      for (final viewport in [const Size(1366, 768), const Size(960, 720)]) {
        await tester.binding.setSurfaceSize(viewport);

        final settingsProv = _FakeSettingsProvider(
          const BusinessSettings(
            licensePlanType: 'basic',
            features: FeatureFlags(
              advancedReports: true,
              expenses: false,
              currentAccounts: false,
              multiRubro: false,
            ),
          ),
        );
        final reportsProv = _buildReportsProvider();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
              ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
              ChangeNotifierProvider<CheckProvider>.value(value: _FakeCheckProvider()),
              ChangeNotifierProvider<InventoryAlertsProvider>.value(value: _FakeInventoryAlertsProvider()),
              ChangeNotifierProvider<LocalTerminalProvider>.value(value: LocalTerminalProvider()),
              ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
            ],
            child: MaterialApp(
              key: ValueKey('reports_app_$viewport'),
              home: const ReportsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(reportsProv.error, isNull, reason: 'ReportsProvider error: ${reportsProv.error}');
        expect(reportsProv.reportData, isNotEmpty);
        expect(find.text('Facturación Total'), findsOneWidget);
        expect(find.text('Ganancia Neta'), findsOneWidget);
        expect(find.text('Margen Promedio'), findsOneWidget);
        expect(find.text('\$85.000'), findsWidgets);
        expect(find.text('\$25.000'), findsWidgets);
        expect(find.text('Exportar Excel'), findsOneWidget);
        expect(find.text('Generar PDF'), findsOneWidget);
        expect(find.text('Balance Mensual'), findsOneWidget);
        expect(find.text('Análisis de Gastos'), findsOneWidget);
        expect(find.text('Consumo Interno'), findsOneWidget);

        // Por Rubro sigue bloqueado con PRO cuando multiRubro == false
        await tester.tap(find.text('Por Rubro'));
        await tester.pumpAndSettle();
        expect(find.byType(PlanUpgradeDialog), findsOneWidget);
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();

        // Pestaña Balance Mensual habilitada en Básico con nota sutil de Gastos PRO
        await tester.tap(find.text('Balance Mensual'));
        await tester.pumpAndSettle();
        expect(find.byType(PremiumShowcaseCard), findsNothing);
        expect(find.byKey(const ValueKey('monthly_balance_expenses_pro_hint')), findsOneWidget);

        // Análisis de Gastos muestra vitrina PremiumShowcaseCard
        await tester.tap(find.text('Análisis de Gastos'));
        await tester.pumpAndSettle();
        expect(find.byType(PremiumShowcaseCard), findsOneWidget);
        expect(find.text('Análisis Inteligente de Gastos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('3. VatManagementTab en Básico RI habilita Libro IVA Ventas + Excel/PDF contador, dejando Libro IVA Digital (PREMIUM) y Posición/Compras en vitrina', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsProv = _FakeSettingsProvider(
        const BusinessSettings(
          licensePlanType: 'basic',
          taxCondition: 'IVA Responsable Inscripto',
          features: FeatureFlags(
            arcaAfip: true,
            suppliers: false,
            advancedReports: true,
          ),
        ),
      );
      final reportsProv = _buildReportsProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
          ],
          child: const MaterialApp(home: Scaffold(body: VatManagementTab())),
        ),
      );
      await tester.pumpAndSettle();

      // Inicia automáticamente en Libro IVA Ventas con Excel y PDF habilitados
      expect(find.byType(VatSalesReportView), findsOneWidget);
      expect(find.text('Exportar Excel Contador'), findsOneWidget);
      expect(find.text('Exportar PDF'), findsOneWidget);
      expect(find.text('Libro IVA Digital'), findsOneWidget);
      // En VatSalesReportView básico solo Libro IVA Digital lleva el pill PREMIUM
      expect(
        find.descendant(
          of: find.byType(VatSalesReportView),
          matching: find.text('PREMIUM'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Libro IVA Digital'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanUpgradeDialog), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      // Posición Mensual y Libro IVA Compras muestran PremiumShowcaseCard (sin montar VatPurchasesReportView)
      await tester.tap(find.text('⚖️ Posición Mensual'));
      await tester.pumpAndSettle();
      expect(find.text('Posición Mensual de IVA (F. 2002)'), findsOneWidget);

      await tester.tap(find.text('📥 Libro IVA Compras'));
      await tester.pumpAndSettle();
      expect(find.text('Libro IVA Compras y Crédito Fiscal'), findsOneWidget);
      expect(find.byType(VatPurchasesReportView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. InventoryAlertsWidget muestra banner de Alertas Predictivas IA (PRO) en Básico', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsProv = _FakeSettingsProvider(
        const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(predictiveAlerts: false),
        ),
      );
      final alertsProv = _FakeInventoryAlertsProvider(
        reactiveAlerts: const [
          {
            'alert_type': 'low_stock',
            'product_id': 1,
            'product_name': 'Fideos Tallarines 500g',
            'internal_code': 'FID-1',
            'current_stock': 2,
            'is_sold_by_weight': false,
          },
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: alertsProv),
            ChangeNotifierProvider<CatalogProvider>.value(value: _FakeCatalogProvider()),
            ChangeNotifierProvider<OfferProvider>.value(value: _FakeOfferProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: InventoryAlertsWidget(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.notifications_active));
      await tester.pumpAndSettle();

      expect(find.text('🧠 Activá Alertas Predictivas con IA (PRO) 🔒'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. CatalogScreen muestra Producción 🔒 ADDON solo en retail/butcher, lo oculta en hardware/apparel/tech/general y muestra Proveedor 🔒 PRO', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Future<void> pumpCatalogFor(String businessType) async {
        final settingsProv = _FakeSettingsProvider(
          BusinessSettings(
            licensePlanType: 'basic',
            businessType: businessType,
            features: const FeatureFlags(
              suppliers: false,
              production: false,
            ),
          ),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<CatalogProvider>.value(value: _FakeCatalogProvider()),
              ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
              ChangeNotifierProvider<SupplierProvider>.value(value: _FakeSupplierProvider()),
              ChangeNotifierProvider<LocalTerminalProvider>.value(value: _FakeLocalTerminalProvider()),
              ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
              ChangeNotifierProvider<InventoryAlertsProvider>.value(value: _FakeInventoryAlertsProvider()),
            ],
            child: MaterialApp(
              key: ValueKey('catalog_$businessType'),
              home: Scaffold(body: CatalogScreen(key: ValueKey('catalog_screen_$businessType'))),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      for (final foodType in ['retail', 'butcher']) {
        await pumpCatalogFor(foodType);
        expect(
          find.byKey(const ValueKey('catalog_locked_production_addon_btn')),
          findsOneWidget,
          reason: 'Debe mostrar Producción 🔒 ADDON en $foodType',
        );
        // Botón Rubros bloqueado con PRO en Básico y abre PlanUpgradeDialog con WhatsApp
        final rubrosBtn = find.byKey(const ValueKey('catalog_rubros_btn'));
        expect(rubrosBtn, findsOneWidget);
        expect(
          find.descendant(of: rubrosBtn, matching: find.text('PRO')),
          findsOneWidget,
          reason: 'Rubros debe mostrarse bloqueado PRO en Básico ($foodType)',
        );
        await tester.tap(rubrosBtn);
        await tester.pumpAndSettle();
        expect(find.byType(PlanUpgradeDialog), findsOneWidget);
        expect(find.textContaining('+54 9 3704 36-7202'), findsOneWidget);
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('catalog_toggle_filters_btn')));
        await tester.pumpAndSettle();
        final lockedSupplierFinder =
            find.byKey(const ValueKey('catalog_locked_supplier_filter'));
        expect(
          lockedSupplierFinder,
          findsOneWidget,
          reason: 'Debe mostrar Proveedor 🔒 PRO en $foodType',
        );
        final decorator = tester.widget<InputDecorator>(
          find.descendant(
            of: lockedSupplierFinder,
            matching: find.byType(InputDecorator),
          ),
        );
        expect(decorator.isEmpty, isFalse,
            reason: 'isEmpty debe ser false para que la etiqueta Proveedor flote sin superponerse');
        expect(decorator.decoration.labelText, 'Proveedor');
        expect(tester.takeException(), isNull);
      }

      for (final nonFoodType in ['hardware_store', 'apparel', 'tech', 'general']) {
        await pumpCatalogFor(nonFoodType);
        expect(
          find.byKey(const ValueKey('catalog_locked_production_addon_btn')),
          findsNothing,
          reason: 'Nunca debe mostrar Producción en $nonFoodType',
        );
        final rubrosBtn = find.byKey(const ValueKey('catalog_rubros_btn'));
        expect(rubrosBtn, findsOneWidget);
        expect(
          find.descendant(of: rubrosBtn, matching: find.text('PRO')),
          findsOneWidget,
          reason: 'Rubros debe mostrarse bloqueado PRO en Básico ($nonFoodType)',
        );
        await tester.tap(rubrosBtn);
        await tester.pumpAndSettle();
        expect(find.byType(PlanUpgradeDialog), findsOneWidget);
        expect(find.textContaining('+54 9 3704 36-7202'), findsOneWidget);
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('catalog_toggle_filters_btn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('catalog_locked_supplier_filter')),
          findsOneWidget,
          reason: 'Debe mostrar Proveedor 🔒 PRO en $nonFoodType',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('5b. CatalogScreen muestra Proveedor bloqueado PRO tanto en Clasificación Rápida individual como en selección por Lote múltiple', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sampleProducts = [
        Product(
          id: 101,
          name: 'Canelones de Verdura y Ricota x2',
          internalCode: 'ROT-101',
          costPrice: 12000,
          sellingPrice: 28500,
          stock: 15,
          active: true,
          isSoldByWeight: false,
        ),
        Product(
          id: 102,
          name: 'Sorrentinos de Jamón y Queso x12',
          internalCode: 'ROT-102',
          costPrice: 14000,
          sellingPrice: 31000,
          stock: 10,
          active: true,
          isSoldByWeight: false,
        ),
      ];

      final settingsProv = _FakeSettingsProvider(
        const BusinessSettings(
          licensePlanType: 'basic',
          businessType: 'retail',
          features: FeatureFlags(
            suppliers: false,
            multiRubro: false,
          ),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(
              value: _FakeCatalogProvider(products: sampleProducts),
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<SupplierProvider>.value(value: _FakeSupplierProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: _FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: _FakeInventoryAlertsProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CatalogScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Acción rápida individual (menú ⋮ -> Clasificación rápida) muestra caja Proveedor bloqueada PRO
      await tester.tap(find.byKey(const ValueKey('catalog_row_actions_101')));
      await tester.pumpAndSettle();
      expect(find.text('Clasificación rápida (Cat. / Marca / Prov.)'), findsOneWidget);

      await tester.tap(find.text('Clasificación rápida (Cat. / Marca / Prov.)'));
      await tester.pumpAndSettle();

      final quickLockedSup =
          find.byKey(const ValueKey('quick_classify_locked_supplier_field'));
      expect(quickLockedSup, findsOneWidget);
      await tester.tap(quickLockedSup);
      await tester.pumpAndSettle();
      expect(find.byType(PlanUpgradeDialog), findsOneWidget);
      expect(find.textContaining('+54 9 3704 36-7202'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // 2. Selección por lote múltiple (seleccionar todos -> menú contextual y botón Lote (2)) muestra Asignar Proveedor PRO
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('Lote (2)'), findsOneWidget);

      // Menú contextual de lote (⋮ sobre fila con 2 seleccionados)
      await tester.tap(find.byKey(const ValueKey('catalog_row_actions_101')));
      await tester.pumpAndSettle();
      expect(find.text('Asignar Proveedor'), findsOneWidget);
      await tester.tap(find.text('Asignar Proveedor'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanUpgradeDialog), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      // Menú superior Lote (2)
      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Asignar Proveedor'), findsOneWidget);
      await tester.tap(find.text('Asignar Proveedor'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanUpgradeDialog), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('6. PosScreen muestra indicador Lista de Precios 🔒 PRO cuando multiplePrices es false y lo oculta cuando es true', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Future<void> pumpPos(bool multiplePrices) async {
        final settingsProv = _FakeSettingsProvider(
          BusinessSettings(
            licensePlanType: multiplePrices ? 'premium' : 'basic',
            businessType: 'retail',
            features: FeatureFlags(
              fastPos: true,
              multiplePrices: multiplePrices,
            ),
          ),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: _buildPosProvider()),
              ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
              ChangeNotifierProvider<LocalTerminalProvider>.value(value: LocalTerminalProvider()),
              ChangeNotifierProvider<CustomerProvider>.value(value: _FakeCustomerProvider()),
              ChangeNotifierProvider<CashRegisterProvider>.value(value: _FakeCashRegisterProvider()),
              ChangeNotifierProvider<CatalogProvider>.value(value: _FakeCatalogProvider()),
              ChangeNotifierProvider<OfferProvider>.value(value: _FakeOfferProvider()),
              ChangeNotifierProvider<QuoteProvider>.value(value: _FakeQuoteProvider()),
              ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
              ChangeNotifierProvider<InventoryAlertsProvider>.value(value: _FakeInventoryAlertsProvider()),
            ],
            child: const MaterialApp(home: PosScreen()),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpPos(false);
      expect(find.byKey(const ValueKey('pos_locked_price_tiers_indicator')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pos_locked_price_tiers_indicator')));
      await tester.pumpAndSettle();
      expect(find.byType(PlanUpgradeDialog), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await pumpPos(true);
      expect(find.byKey(const ValueKey('pos_locked_price_tiers_indicator')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('7. PosScreen bloquea la Billetera de Gastos en Plan Básico con PlanUpgradeDialog y muestra soporte oficial', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsProv = _FakeSettingsProvider(
        const BusinessSettings(
          licensePlanType: 'basic',
          businessType: 'hardware_store',
          features: FeatureFlags(
            fastPos: true,
            expenses: false,
            quotes: true,
            logistics: true,
            multiplePrices: true,
          ),
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: _buildPosProvider()),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: LocalTerminalProvider()),
            ChangeNotifierProvider<CustomerProvider>.value(value: _FakeCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: _FakeCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(value: _FakeCatalogProvider()),
            ChangeNotifierProvider<OfferProvider>.value(value: _FakeOfferProvider()),
            ChangeNotifierProvider<QuoteProvider>.value(value: _FakeQuoteProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: _FakeInventoryAlertsProvider()),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final walletBtn = find.byKey(const ValueKey('pos_appbar_wallet_btn'));
      expect(walletBtn, findsOneWidget);
      await tester.tap(walletBtn);
      await tester.pumpAndSettle();

      expect(find.byType(PlanUpgradeDialog), findsOneWidget);
      expect(find.text('Gestión de Gastos y Movimientos de Caja'), findsOneWidget);
      expect(find.textContaining('+54 9 3704 36-7202'), findsOneWidget);
      expect(find.text('Registrar Movimiento de Caja'), findsNothing);

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('8. Calculadora F7 habilitada en Ferretería Plan Básico incluso con fallback business_type', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final modelFromFallback = BusinessSettingsModel.fromJson({
        'app_plan': 'basic',
        'business_type': 'hardware_store',
        'license_features_dict': json.encode({
          'fast_pos': true,
          'quotes': true,
          'logistics': true,
          'multiple_prices': true,
        }),
      });
      expect(modelFromFallback.businessType, 'hardware_store');
      expect(modelFromFallback.canUseHardwareCalculator, isTrue);

      final settingsProv = _FakeSettingsProvider(modelFromFallback);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: _buildPosProvider()),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: LocalTerminalProvider()),
            ChangeNotifierProvider<CustomerProvider>.value(value: _FakeCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: _FakeCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(value: _FakeCatalogProvider()),
            ChangeNotifierProvider<OfferProvider>.value(value: _FakeOfferProvider()),
            ChangeNotifierProvider<QuoteProvider>.value(value: _FakeQuoteProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: _FakeInventoryAlertsProvider()),
          ],
          child: const MaterialApp(home: PosScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Calculadora (F7)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
