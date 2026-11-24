import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_price_lookup_dialog.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/presentation/screens/suppliers_screen.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _RecordingCatalogRepository implements CatalogRepository {
  List<Product> seededProducts = [];
  int? lastGetProductsSupplierId;
  String? lastGetProductsSortBy;
  final List<Map<String, dynamic>> createdPayloads = [];
  int _nextId = 100;

  @override
  Future<Map<String, dynamic>> getProducts({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
    int? categoryId,
    int? brandId,
    int? supplierId,
    bool? active,
  }) async {
    lastGetProductsSupplierId = supplierId;
    lastGetProductsSortBy = sortBy;

    final filtered = supplierId != null
        ? seededProducts
            .where((p) => p.supplier?.id == supplierId)
            .toList()
        : List<Product>.from(seededProducts);

    return {
      'data': filtered,
      'current_page': page,
      'last_page': 1,
      'total': filtered.length,
    };
  }

  @override
  Future<Product> createProduct(Map<String, dynamic> productData) async {
    createdPayloads.add(Map<String, dynamic>.from(productData));
    final id = _nextId++;
    final created = ProductModel(
      id: id,
      name: productData['name']?.toString() ?? 'Producto $id',
      barcode: productData['barcode']?.toString(),
      internalCode: productData['internal_code']?.toString() ??
          id.toString().padLeft(5, '0'),
      costPrice: (productData['cost_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (productData['selling_price'] as num?)?.toDouble() ?? 0.0,
      stock: (productData['stock'] as num?)?.toDouble() ?? 0.0,
      active: productData['active'] != false,
      isSoldByWeight: productData['is_sold_by_weight'] == true,
      isCombo: productData['is_combo'] == true,
      isService: productData['is_service'] == true,
      unitType: productData['unit_type']?.toString() ?? 'un',
      supplierSku: productData['supplier_sku']?.toString(),
      storageLocation: productData['storage_location']?.toString(),
      technicalSpec: productData['technical_spec']?.toString(),
      purchasePackageName: productData['purchase_package_name']?.toString(),
      conversionFactor:
          (productData['conversion_factor'] as num?)?.toDouble(),
      calcConfig: productData['calc_config'] is Map
          ? Map<String, dynamic>.from(productData['calc_config'] as Map)
          : null,
    );
    seededProducts.add(created);
    return created;
  }

  @override
  Future<List<Category>> getCategories() async =>
      [Category(id: 1, name: 'Electricidad')];

  @override
  Future<List<Brand>> getBrands() async => [Brand(id: 1, name: 'Kalop')];

  @override
  Future<List<Rubro>> getRubros() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings _settings;

  _FakeSettingsProvider({required String businessType})
      : _settings = BusinessSettings(
          businessType: businessType,
          licensePlanType: 'premium',
          features: FeatureFlags(
            quotes: true,
            suppliers: true,
            multiRubro: true,
            batchExpiration: businessType == 'retail',
            production: businessType == 'retail',
          ),
        );

  void setBusinessType(String businessType) {
    _settings = _settings.copyWith(
      businessType: businessType,
      features: FeatureFlags(
        quotes: true,
        suppliers: true,
        multiRubro: true,
        batchExpiration: businessType == 'retail',
        production: businessType == 'retail',
      ),
    );
    notifyListeners();
  }

  @override
  BusinessSettings? get settings => _settings;

  @override
  bool get isHardwareStore => _settings.isHardwareStore;

  @override
  FeatureFlags get features => _settings.features;

  @override
  int get assignedRegisterId => 1;

  @override
  String get currentPlan => 'premium';

  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  bool get isLicenseActive => true;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  List<String> get allowedAddons => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  final List<Supplier> _suppliers = [
    Supplier(
      id: 7,
      name: 'Corralón Norte SA',
      balance: 0.0,
      isActive: true,
    ),
    Supplier(
      id: 8,
      name: 'Distribuidora Sur',
      balance: 1500.0,
      isActive: true,
    ),
  ];

  @override
  List<Supplier> get suppliers => _suppliers;

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchSuppliers({String? search}) async {}

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  final bool allowAllPermissions;

  _FakeAuthProvider({this.allowAllPermissions = true});

  @override
  Map<String, dynamic>? get currentUser => allowAllPermissions
      ? {'id': 1, 'name': 'Admin', 'role': 'admin'}
      : {'id': 2, 'name': 'Operador', 'role': 'cashier'};

  @override
  bool get isAdmin => allowAllPermissions;

  @override
  bool hasPermission(String permission) => allowAllPermissions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
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

class _FakePosProvider extends ChangeNotifier implements PosProvider {
  final List<Product> remotePosProducts;

  _FakePosProvider({this.remotePosProducts = const []});

  @override
  List<CartItem> get cart => const [];

  @override
  double get wholesaleFactor => 0.9;

  @override
  double get cardFactor => 1.1;

  @override
  double get currentCustomFactor => 1.0;

  @override
  String? get customTierLabel => null;

  @override
  CardSurchargeOnOffersMode get cardSurchargeOnOffersMode =>
      CardSurchargeOnOffersMode.values.first;

  @override
  DiscountTierOnOffersMode get discountTierOnOffersMode =>
      DiscountTierOnOffersMode.values.first;

  @override
  void syncActiveOffers(List<dynamic> activeOffers) {}

  @override
  Future<List<Product>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return remotePosProducts.where((p) {
      return p.active &&
          (p.name.toLowerCase().contains(q) ||
              (p.barcode?.toLowerCase().contains(q) ?? false) ||
              p.internalCode.toLowerCase().contains(q) ||
              (p.supplierSku?.toLowerCase().contains(q) ?? false) ||
              (p.technicalSpec?.toLowerCase().contains(q) ?? false));
    }).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOfferProvider extends ChangeNotifier implements OfferProvider {
  @override
  List<OfferModel> get activeOffers => const [];

  @override
  List<OfferModel> get allOffers => const [];

  @override
  bool get isLoadingActive => false;

  @override
  Future<void> loadActiveOffers() async {}

  @override
  Future<void> loadAllOffers({String? status, String? search}) async {}

  @override
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) =>
      null;

  @override
  double? getDiscountedPrice(Product product) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  group('Fase 1 - Modelos, Unidades y Escáner', () {
    test('ProductModel hidrata campos ferreteros y etiquetas reales por unidad',
        () {
      final model = ProductModel.fromJson({
        'id': 50,
        'name': 'Cable Subterráneo',
        'internal_code': '00050',
        'cost_price': '1200.00',
        'selling_price': '1950.00',
        'stock': '12.500',
        'active': true,
        'is_sold_by_weight': true,
        'unit_type': 'mt',
        'supplier_sku': 'BRE-4021',
        'storage_location': 'Pasillo 2 - Gaveta B4',
        'technical_spec': '2x2.5mm Violeta',
        'purchase_package_name': 'Rollo 100m',
        'conversion_factor': '100.000',
        'calc_config': {
          'type': 'paint',
          'yield_m2_per_liter': 10,
        },
      });

      expect(model.supplierSku, 'BRE-4021');
      expect(model.storageLocation, 'Pasillo 2 - Gaveta B4');
      expect(model.technicalSpec, '2x2.5mm Violeta');
      expect(model.purchasePackageName, 'Rollo 100m');
      expect(model.conversionFactor, 100.0);
      expect(model.unitShortLabel, 'mt');
      expect(model.isDiscreteUnit, isFalse);
      expect(model.isMetricOrLiquidUnit, isTrue);
      expect(
        model.stock.toUnitStockDisplay(
          isSoldByWeight: model.isSoldByWeight,
          weightUnit: model.unitShortLabel,
        ),
        '12.5 mt',
      );
      expect(Product.shortLabelFor('m2'), 'm²');
      expect(Product.shortLabelFor('m3'), 'm³');
      expect(Product.shortLabelFor('bolsa'), 'bolsa');
      expect(Product.discreteUnitTypes.contains('bolsa'), isTrue);
      expect(Product.discreteUnitTypes.contains('rollo'), isTrue);
    });

    test(
        'RemoteScannerService.findExactProductMatch prioriza barcode > PLU > supplierSku',
        () {
      final bySku = Product(
        id: 1,
        name: 'Bulón Hexagonal',
        internalCode: '00010',
        supplierSku: 'BUL-12',
        costPrice: 100,
        sellingPrice: 180,
        stock: 50,
        active: true,
        isSoldByWeight: false,
      );
      final byPlu = Product(
        id: 2,
        name: 'Tornillo',
        internalCode: 'BUL-12',
        costPrice: 80,
        sellingPrice: 140,
        stock: 20,
        active: true,
        isSoldByWeight: false,
      );

      expect(
        RemoteScannerService.findExactProductMatch([bySku], ' bul-12 ')?.id,
        1,
      );
      expect(
        RemoteScannerService.findExactProductMatch([bySku, byPlu], 'BUL-12')?.id,
        2,
      );
    });

    test(
        'CatalogProvider mantiene supplierId en catálogo y lo ignora cuando sortBy es vacío (POS)',
        () async {
      final repo = _RecordingCatalogRepository();
      repo.seededProducts = [
        Product(
          id: 1,
          name: 'Cemento Loma Negra 50kg',
          internalCode: '00001',
          costPrice: 7000,
          sellingPrice: 10500,
          stock: 40,
          active: true,
          isSoldByWeight: false,
          unitType: 'bolsa',
          supplier: Supplier(
            id: 7,
            name: 'Corralón Norte SA',
            balance: 0,
            isActive: true,
          ),
        ),
        Product(
          id: 2,
          name: 'Ladrillo Hueco 12',
          internalCode: '00002',
          costPrice: 400,
          sellingPrice: 650,
          stock: 500,
          active: true,
          isSoldByWeight: false,
          supplier: Supplier(
            id: 8,
            name: 'Distribuidora Sur',
            balance: 0,
            isActive: true,
          ),
        ),
      ];

      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await catalogProv.setSupplierFilter(7, supplierName: 'Corralón Norte SA');
      expect(repo.lastGetProductsSupplierId, 7);
      expect(catalogProv.filterSupplierId, 7);
      expect(catalogProv.filterSupplierName, 'Corralón Norte SA');
      expect(catalogProv.products.length, 1);

      // Carga rápida del POS (sortBy: '') nunca debe quedar filtrada por proveedor.
      await catalogProv.loadProducts(page: 1, search: '', sortBy: '', perPage: 500);
      expect(repo.lastGetProductsSupplierId, isNull);
      expect(catalogProv.sortBy, '');
      expect(catalogProv.products.length, 2);

      await catalogProv.setSupplierFilter(null);
      expect(catalogProv.filterSupplierId, isNull);
      expect(catalogProv.filterSupplierName, isNull);
    });
  });

  group('Fase 1 - UI Adaptativa Catálogo, Proveedores y POS', () {
    testWidgets(
        'CatalogScreen en Ferretería oculta Bal./VTO., muestra Cód. Prov./Ubicación/Unidad y banner de proveedor',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = _RecordingCatalogRepository();
      repo.seededProducts = [
        Product(
          id: 1,
          name: 'Cable Unipolar 2.5mm',
          internalCode: '00001',
          costPrice: 500,
          sellingPrice: 890,
          stock: 18,
          active: true,
          isSoldByWeight: true,
          unitType: 'mt',
          supplierSku: 'KAL-25',
          storageLocation: 'Estante C1',
          technicalSpec: '2.5mm IRAM',
          supplier: Supplier(
            id: 7,
            name: 'Corralón Norte SA',
            balance: 0,
            isActive: true,
          ),
        ),
      ];

      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      await catalogProv.setSupplierFilter(
        7,
        supplierName: 'Corralón Norte SA',
        reload: false,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(businessType: 'hardware_store'),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _FakeLocalTerminalProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: CatalogScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // Columnas adaptativas de Ferretería
      expect(find.text('Cód. Prov.'), findsOneWidget);
      expect(find.text('Ubicación'), findsOneWidget);
      expect(find.text('Unidad'), findsOneWidget);
      expect(find.text('Bal.'), findsNothing);
      expect(find.text('VTO.'), findsNothing);

      // Datos mostrados por fila
      expect(find.text('KAL-25'), findsOneWidget);
      expect(find.text('Estante C1'), findsOneWidget);
      expect(find.text('2.5mm IRAM'), findsOneWidget);
      expect(find.text('18 mt'), findsOneWidget);

      // Banner de filtro por proveedor y limpieza
      expect(find.textContaining('Corralón Norte SA'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('catalog_clear_supplier_filter_btn')),
      );
      await tester.pumpAndSettle();
      expect(catalogProv.filterSupplierId, isNull);
    });

    testWidgets(
        'ProductFormDialog adapta campos a Ferretería, desacopla unidades discretas/corte y soporta Guardar y Crear Otro',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = _RecordingCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(businessType: 'hardware_store'),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _FakeLocalTerminalProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ProductFormDialog(
                provider: catalogProv,
                initialSupplierId: 7,
                initialSupplierName: 'Corralón Norte SA',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Etiquetas de rubro Ferretería visibles, vencimientos/receta ocultos
      expect(find.text('Artículo / Material'), findsOneWidget);
      expect(find.text('Servicio / Flete'), findsOneWidget);
      expect(find.text('Kit / Fracción'), findsOneWidget);
      expect(find.text('Permite fraccionar'), findsOneWidget);
      expect(find.text('Venta p/peso'), findsNothing);
      expect(
        find.text('Control de Vencimiento y Alertas (Opcional)'),
        findsNothing,
      );
      expect(
        find.text('Calculadora Rápida F7 (Maderas / Chapas / Pintura)'),
        findsOneWidget,
      );

      // Encender "Permite fraccionar" estando en Unidades NO fuerza kg en Ferretería
      // y actualiza el banner explicativo reactivo
      expect(
        find.byKey(const ValueKey('product_fractional_explanation_banner')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Venta por unidad entera:'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('product_fractional_switch')),
      );
      await tester.tap(find.byKey(const ValueKey('product_fractional_switch')));
      await tester.pumpAndSettle();
      expect(find.text('Kilogramos'), findsNothing);
      expect(find.text('Unidades'), findsOneWidget);
      expect(
        find.textContaining('Fraccionable / Corte activo:'),
        findsOneWidget,
      );

      // Cambiar unidad a Metros (mt) sí deja fractional ON, y Bolsa lo apaga
      await tester.tap(find.byKey(const ValueKey('unit_type_wide_un')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Metros (mt)').last);
      await tester.pumpAndSettle();
      SwitchListTile fracSwitch = tester.widget(
        find.byKey(const ValueKey('product_fractional_switch')),
      );
      expect(fracSwitch.value, isTrue);

      await tester.tap(find.byKey(const ValueKey('unit_type_wide_mt')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bolsa').last);
      await tester.pumpAndSettle();
      fracSwitch = tester.widget(
        find.byKey(const ValueKey('product_fractional_switch')),
      );
      expect(fracSwitch.value, isFalse);

      // Volvemos a Metros (mt) para guardar y probar Guardar y Crear Otro
      await tester.tap(find.byKey(const ValueKey('unit_type_wide_bolsa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Metros (mt)').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre del Artículo / Material *'),
        'Tirante Pino 2" x 2" x 3.00m',
      );
      await tester.pumpAndSettle();

      // Abrir Configurar F7 y verificar que "Auto-detectar medidas" aparece y funciona al 1er clic
      await tester.ensureVisible(find.text('Configurar F7'));
      await tester.tap(find.text('Configurar F7'));
      await tester.pumpAndSettle();
      final autoDetectBtn = find.byKey(const ValueKey('f7_auto_detect_btn'));
      expect(autoDetectBtn, findsOneWidget);
      await tester.ensureVisible(autoDetectBtn);
      await tester.pumpAndSettle();
      await tester.tap(autoDetectBtn);
      await tester.pumpAndSettle();
      expect(
        find.text('Calculadora F7 · Machimbre / Maderas'),
        findsOneWidget,
      );
      expect(find.text('2"'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre del Artículo / Material *'),
        'Cable Taller 3x1.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('product_supplier_sku_field')),
        'CAB-315',
      );
      await tester.enterText(
        find.byKey(const ValueKey('product_storage_location_field')),
        'Estantería B2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('product_technical_spec_field')),
        '3x1.5mm',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Precio Venta *'),
        '1850',
      );

      final saveAnotherBtn = find.byKey(
        const Key('product_save_and_create_another_btn'),
      );
      expect(saveAnotherBtn, findsOneWidget);
      await tester.tap(saveAnotherBtn);
      await tester.pumpAndSettle();

      // El producto se creó con campos ferreteros y el modal siguió abierto para el siguiente
      expect(repo.createdPayloads.length, 1);
      final sent = repo.createdPayloads.first;
      expect(sent['name'], 'Cable Taller 3x1.5');
      expect(sent['supplier_sku'], 'CAB-315');
      expect(sent['storage_location'], 'Estantería B2');
      expect(sent['technical_spec'], '3x1.5mm');
      expect(sent['unit_type'], 'mt');
      expect(sent['is_sold_by_weight'], isTrue);
      expect(sent['supplier_id'], 7);

      expect(find.byType(ProductFormDialog), findsOneWidget);
      expect(find.text('Guardar y Crear Otro (1)'), findsOneWidget);
      // El nombre quedó limpio para cargar el próximo ítem manteniendo unidad mt
      expect(find.text('Cable Taller 3x1.5'), findsNothing);
      expect(find.byKey(const ValueKey('unit_type_wide_mt')), findsOneWidget);
    });

    testWidgets(
        'Modo Retail mantiene Bal./VTO., Venta p/peso, Vencimientos y Guardar y Crear Otro sin F7',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = _RecordingCatalogRepository()
        ..seededProducts = [
          Product(
            id: 1,
            name: 'Gaseosa Cola 2.25L',
            internalCode: '00001',
            costPrice: 1200,
            sellingPrice: 1900,
            stock: 24,
            active: true,
            isSoldByWeight: false,
            unitType: 'un',
          ),
        ];
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(businessType: 'retail'),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _FakeLocalTerminalProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: CatalogScreen()),
                  Builder(
                    builder: (ctx) => ElevatedButton(
                      onPressed: () => showDialog(
                        context: ctx,
                        builder: (_) => ProductFormDialog(provider: catalogProv),
                      ),
                      child: const Text('AbrirFormularioRetail'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tabla Retail conserva Bal. y VTO. y oculta columnas exclusivas ferreteras
      expect(find.text('Bal.'), findsOneWidget);
      expect(find.text('VTO.'), findsOneWidget);
      expect(find.text('Cód. Prov.'), findsNothing);
      expect(find.text('Ubicación'), findsNothing);

      await tester.tap(find.text('AbrirFormularioRetail'));
      await tester.pumpAndSettle();

      expect(find.text('Producto Físico'), findsOneWidget);
      expect(find.text('Venta p/peso'), findsOneWidget);
      expect(
        find.text('Control de Vencimiento y Alertas (Opcional)'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('product_supplier_sku_field')), findsOneWidget);
      expect(
        find.byKey(const Key('product_save_and_create_another_btn')),
        findsOneWidget,
      );
      expect(
        find.text('Calculadora Rápida F7 (Maderas / Chapas / Pintura)'),
        findsNothing,
      );
    });

    testWidgets(
        'PosPriceLookupDialog busca por supplierSku/technicalSpec y muestra ubicación y unidad real',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final wire = Product(
        id: 77,
        name: 'Cable Subterráneo 4mm',
        internalCode: '00077',
        supplierSku: 'BRE-4021',
        storageLocation: 'Pasillo 4 - B2',
        technicalSpec: '4mm IRAM',
        costPrice: 1200,
        sellingPrice: 2100,
        stock: 35,
        active: true,
        isSoldByWeight: true,
        unitType: 'mt',
      );

      final repo = _RecordingCatalogRepository()..seededProducts = [wire];
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      await catalogProv.loadProducts();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(
              value: _FakePosProvider(remotePosProducts: [wire]),
            ),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<OfferProvider>.value(
              value: _FakeOfferProvider(),
            ),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(businessType: 'hardware_store'),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: PosPriceLookupDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'BRE-4021');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Cable Subterráneo 4mm'), findsWidgets);
      expect(find.textContaining('Cód. Prov: BRE-4021'), findsOneWidget);
      expect(find.text('Ubic: Pasillo 4 - B2'), findsOneWidget);
      expect(find.text('4mm IRAM'), findsOneWidget);
      expect(find.textContaining('/mt'), findsOneWidget);
      expect(find.text('35 mt'), findsOneWidget);
    });

    testWidgets(
        'SuppliersScreen abre Catálogo pre-filtrado al pulsar Catálogo del Proveedor y exige PIN si falta permiso',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _RecordingCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      // 1. Usuario sin permiso manage_catalog debe recibir el diálogo de PIN
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(businessType: 'hardware_store'),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _FakeLocalTerminalProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(allowAllPermissions: false),
            ),
          ],
          child: MaterialApp(
            routes: {
              '/catalog': (_) => const Scaffold(
                    body: Text('CatalogRouteOpened'),
                  ),
            },
            home: const SuppliersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final restrictedCatalogBtn =
          find.byTooltip('Catálogo del Proveedor').first;
      await tester.tap(restrictedCatalogBtn);
      await tester.pumpAndSettle();

      expect(find.text('CatalogRouteOpened'), findsNothing);
      expect(find.text('Acceso Restringido'), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar (Esc)'));
      await tester.pumpAndSettle();

      // 2. Usuario autorizado abre Catálogo pre-filtrado
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(businessType: 'hardware_store'),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _FakeLocalTerminalProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(),
            ),
          ],
          child: MaterialApp(
            routes: {
              '/catalog': (_) => const Scaffold(
                    body: Text('CatalogRouteOpened'),
                  ),
            },
            home: const SuppliersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final catalogBtn = find.byTooltip('Catálogo del Proveedor').first;
      await tester.tap(catalogBtn);
      await tester.pumpAndSettle();

      expect(find.text('CatalogRouteOpened'), findsOneWidget);
      expect(catalogProv.filterSupplierId, isNotNull);
      expect(catalogProv.filterSupplierName, isNotNull);
    });
  });
}
