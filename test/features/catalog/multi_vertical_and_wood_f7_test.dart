import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/print_labels_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/product_f7_calc_config_panel.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/supplier_quick_grid_dialog.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/services/hardware_calculator_engine.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_hardware_calculator_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_access_view.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _TestCatalogRepository implements CatalogRepository {
  final List<Category> categories;
  final List<Rubro> rubros;
  final List<Map<String, dynamic>> createdPayloads = [];
  int _nextId = 500;

  _TestCatalogRepository({
    this.categories = const [],
    this.rubros = const [],
  });

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
    return {
      'data': <Product>[],
      'current_page': 1,
      'last_page': 1,
      'total': 0,
    };
  }

  @override
  Future<Product> createProduct(Map<String, dynamic> productData) async {
    createdPayloads.add(Map<String, dynamic>.from(productData));
    final id = _nextId++;
    return ProductModel(
      id: id,
      name: productData['name']?.toString() ?? 'Producto $id',
      internalCode: id.toString().padLeft(5, '0'),
      costPrice: (productData['cost_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (productData['selling_price'] as num?)?.toDouble() ?? 0.0,
      stock: (productData['stock'] as num?)?.toDouble() ?? 0.0,
      active: productData['active'] != false,
      isSoldByWeight: productData['is_sold_by_weight'] == true,
      unitType: productData['unit_type']?.toString() ?? 'un',
      technicalSpec: productData['technical_spec']?.toString(),
      calcConfig: productData['calc_config'] is Map
          ? Map<String, dynamic>.from(productData['calc_config'] as Map)
          : null,
    );
  }

  @override
  Future<List<Category>> getCategories() async => categories;

  @override
  Future<List<Brand>> getBrands() async => const [];

  @override
  Future<List<Rubro>> getRubros() async => rubros;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  _FakeSettingsProvider({
    required String businessType,
    List<String> secondaryBusinessTypes = const [],
    bool multiRubro = false,
    bool batchExpiration = false,
    bool production = false,
  }) : _settings = BusinessSettings(
          businessType: businessType,
          secondaryBusinessTypes: secondaryBusinessTypes,
          licensePlanType: 'premium',
          features: FeatureFlags(
            quotes: true,
            suppliers: true,
            multiRubro: multiRubro,
            batchExpiration: batchExpiration,
            production: production,
          ),
        );

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
  @override
  List<Supplier> get suppliers => [
        Supplier(
          id: 7,
          name: 'Maderera Norte',
          balance: 0.0,
          isActive: true,
        ),
      ];

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  final String _scaleComPort;

  _FakeLocalTerminalProvider({String scaleComPort = ''})
      : _scaleComPort = scaleComPort;

  @override
  String get scaleComPort => _scaleComPort;

  @override
  String get printerNameOrIp => '';

  @override
  String get mpPointDeviceId => '';

  @override
  bool get autoOpenCashDrawer => false;

  @override
  String get printerFormat => 'thermal_80';

  @override
  String get printerConnection => 'none';

  @override
  String get pdfPaperSize => 'a4';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCashRegisterProvider extends ChangeNotifier
    implements CashRegisterProvider {
  @override
  List<CashRegister>? get availableRegisters => const [];

  @override
  CashRegisterShift? get currentShift => null;

  @override
  int? get activeRegisterId => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
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

class _FakeInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosProvider extends ChangeNotifier implements PosProvider {
  @override
  List<CartItem> get cart => const [];

  @override
  PriceTier get activeTier => PriceTier.base;

  @override
  String? get customTierLabel => null;

  @override
  double get currentCustomFactor => 1.0;

  @override
  double get wholesaleFactor => 1.0;

  @override
  double get cardFactor => 1.0;

  @override
  CardSurchargeOnOffersMode get cardSurchargeOnOffersMode =>
      CardSurchargeOnOffersMode.surchargeOnOffer;

  @override
  DiscountTierOnOffersMode get discountTierOnOffersMode =>
      DiscountTierOnOffersMode.bestPriceWins;

  @override
  bool get ignoreProductFixedPrices => false;

  @override
  void syncUpdatedCatalogProduct(Product product) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOfferProvider extends ChangeNotifier implements OfferProvider {
  @override
  double? getDiscountedPrice(Product product) => null;

  @override
  void syncUpdatedProduct(Product product) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpFormDialog(
  WidgetTester tester, {
  required CatalogProvider catalogProv,
  required _FakeSettingsProvider settingsProv,
}) async {
  final supplierProv = _FakeSupplierProvider();
  final localTerminal = _FakeLocalTerminalProvider();
  final authProv = _FakeAuthProvider();
  final alertsProv = _FakeInventoryAlertsProvider();
  addTearDown(() {
    supplierProv.dispose();
    localTerminal.dispose();
    authProv.dispose();
    alertsProv.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
        ChangeNotifierProvider<SupplierProvider>.value(value: supplierProv),
        ChangeNotifierProvider<LocalTerminalProvider>.value(
          value: localTerminal,
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: authProv),
        ChangeNotifierProvider<InventoryAlertsProvider>.value(
          value: alertsProv,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ProductFormDialog(provider: catalogProv),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  group('HardwareCalculatorEngine — F7 Maderas 3D y Presets 10"/12"', () {
    test('incluye presets de 10" y 12" en woodInchPresets', () {
      final keys =
          HardwareCalculatorEngine.woodInchPresets.map((p) => p.key).toList();
      expect(keys, containsAll(['1', '2', '3', '4', '5', '6', '8', '10', '12']));
    });

    test(
        'Madera Lapacho con "1\\" / 4m" detecta espesor y largo con warning sin inventar ancho en Quick Grid',
        () {
      final analysis = HardwareCalculatorEngine.analyzeProductText(
        name: 'Madera Lapacho',
        technicalSpec: '1" / 4m',
      );
      expect(analysis.detectedThicknessLabel, '1"');
      expect(analysis.missingWidthWarning, isTrue);
      expect(analysis.config['type'], 'wood');
      expect(analysis.config['length_m'], closeTo(4.0, 0.001));

      final quickGridInferred = HardwareCalculatorEngine.tryInferExplicitConfig(
        name: 'Madera Lapacho',
        technicalSpec: '1" / 4m',
      );
      expect(quickGridInferred, isNull);
    });

    test(
        'Tabla Lapacho con "1\\" x 6\\" x 4m" detecta 6" nominal (0.1524m) x 4m sin warning',
        () {
      final analysis = HardwareCalculatorEngine.analyzeProductText(
        name: 'Tabla Lapacho',
        technicalSpec: '1" x 6" x 4m',
      );
      expect(analysis.missingWidthWarning, isFalse);
      expect(analysis.detectedThicknessLabel, '1"');
      expect(analysis.config['type'], 'wood');
      expect(analysis.config['inch_preset'], '6');
      expect(analysis.config['nominal_width_m'], closeTo(0.1524, 0.0001));
      expect(analysis.config['length_m'], closeTo(4.0, 0.001));

      final explicitCfg = HardwareCalculatorEngine.tryInferExplicitConfig(
        name: 'Tabla Lapacho',
        technicalSpec: '1" x 6" x 4m',
      );
      expect(explicitCfg, isNotNull);
      expect(explicitCfg!['inch_preset'], '6');
      expect(explicitCfg['length_m'], closeTo(4.0, 0.001));
    });
  });

  group('BusinessVerticalProfile — Perfiles, Polirrubro y Multi-Rubro', () {
    test('define capacidades y etiquetas por cada vertical comercial', () {
      final apparel = BusinessVerticalProfile.fromType('apparel');
      expect(apparel.specFieldLabel, 'Talle / Color');
      expect(apparel.showFractionSwitchInForm, isFalse);
      expect(apparel.canUseScaleWeight, isFalse);
      expect(apparel.canUseHardwareCalculator, isFalse);

      final tech = BusinessVerticalProfile.fromType('tech');
      expect(tech.specFieldLabel, 'Modelo / Especificación');
      expect(tech.showFractionSwitchInForm, isFalse);

      final butcher = BusinessVerticalProfile.fromType('butcher');
      expect(butcher.defaultUnitType, 'kg');
      expect(butcher.defaultSoldByWeight, isTrue);
      expect(butcher.canUseScaleWeight, isTrue);

      final general = BusinessVerticalProfile.fromType('general');
      expect(general.specFieldLabel, 'Variante / Presentación');
      expect(general.showFractionSwitchInForm, isFalse);

      final hw = BusinessVerticalProfile.fromType('hardware_store');
      expect(hw.canUseHardwareCalculator, isTrue);
      expect(hw.canUseScaleWeight, isFalse);

      final retail = BusinessVerticalProfile.fromType('retail');
      expect(retail.canUseScaleWeight, isTrue);
      expect(retail.canUseHardwareCalculator, isFalse);

      final mixed = BusinessVerticalProfile.fromType(
        'retail',
        secondaryTypes: const ['hardware_store'],
      );
      expect(mixed.canUseScaleWeight, isTrue);
      expect(mixed.canUseHardwareCalculator, isTrue);
    });

    test('forCategoryRubro cambia el perfil operativo en multi_rubro', () {
      final retail = BusinessVerticalProfile.fromType('retail');
      final carneProfile = retail.forCategoryRubro(
        Rubro(id: 2, name: 'Carnicería'),
      );
      expect(carneProfile.primaryType, BusinessVerticalProfile.butcher);
      expect(carneProfile.defaultUnitType, 'kg');
      expect(carneProfile.defaultSoldByWeight, isTrue);
    });
  });

  group('F7 Panel y Asistente 📏 en Form y Grilla Rápida', () {
    testWidgets(
        'ProductF7CalcConfigPanel muestra f7_missing_width_warning para "1\\" / 4m" y se limpia con "1\\" x 6\\" x 4m"',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final nameCtrl = TextEditingController(text: 'Madera Lapacho');
      final specCtrl = TextEditingController(text: '1" / 4m');
      addTearDown(() {
        nameCtrl.dispose();
        specCtrl.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProductF7CalcConfigPanel(
                calcConfig: null,
                productNameHint: nameCtrl.text,
                productNameListenable: nameCtrl,
                technicalSpecHint: specCtrl.text,
                technicalSpecListenable: specCtrl,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Configurar F7'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('f7_auto_detect_btn')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('f7_missing_width_warning')),
        findsOneWidget,
      );
      final lengthField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Largo tabla (m)'),
      );
      expect(lengthField.controller?.text, '4');

      nameCtrl.text = 'Tabla Lapacho';
      specCtrl.text = '1" x 6" x 4m';
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('f7_auto_detect_btn')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('f7_missing_width_warning')),
        findsNothing,
      );
      final nomField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Ancho nominal (cm)'),
      );
      final lengthField2 = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Largo tabla (m)'),
      );
      expect(nomField.controller?.text, '15.24');
      expect(lengthField2.controller?.text, '4');
    });

    testWidgets(
        'ProductFormDialog abre HardwareDimensionHelperDialog y aplica "1\\" × 6\\" × 4.00m" y F7',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _TestCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      final settingsProv = _FakeSettingsProvider(businessType: 'hardware_store');
      addTearDown(() {
        catalogProv.dispose();
        settingsProv.dispose();
      });

      await _pumpFormDialog(
        tester,
        catalogProv: catalogProv,
        settingsProv: settingsProv,
      );

      final dimBtn = find.byKey(const ValueKey('hardware_dimension_helper_btn'));
      await tester.ensureVisible(dimBtn);
      await tester.tap(dimBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dim_helper_thick_1"')));
      await tester.tap(find.byKey(const ValueKey('dim_helper_inch_6')));
      final len4Finder = find.byKey(const ValueKey('dim_helper_len_4'));
      await tester.ensureVisible(len4Finder);
      await tester.tap(len4Finder);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dim_helper_apply_btn')));
      await tester.pumpAndSettle();

      final specField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Medida / Especificación'),
      );
      expect(specField.controller?.text, '1" × 6" × 4.00m');
      expect(find.text('Calculadora F7 · Machimbre / Maderas'), findsOneWidget);
    });

    testWidgets(
        'SupplierQuickGridDialog aplica asistente 📏 y envía calc_config completo al guardar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _TestCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      final settingsProv = _FakeSettingsProvider(businessType: 'hardware_store');
      final supplierProv = _FakeSupplierProvider();
      final localTerminal = _FakeLocalTerminalProvider();
      final authProv = _FakeAuthProvider();
      final alertsProv = _FakeInventoryAlertsProvider();
      final posProv = _FakePosProvider();
      final offerProv = _FakeOfferProvider();
      addTearDown(() {
        catalogProv.dispose();
        settingsProv.dispose();
        supplierProv.dispose();
        localTerminal.dispose();
        authProv.dispose();
        alertsProv.dispose();
        posProv.dispose();
        offerProv.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<SupplierProvider>.value(value: supplierProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: localTerminal,
            ),
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: alertsProv,
            ),
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<OfferProvider>.value(value: offerProv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SupplierQuickGridDialog(
                provider: catalogProv,
                initialSupplierId: 7,
                initialSupplierName: 'Maderera Norte',
                alreadyAuthorized: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('quick_grid_dim_helper_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dim_helper_thick_1"')));
      await tester.tap(find.byKey(const ValueKey('dim_helper_inch_6')));
      final len4Finder = find.byKey(const ValueKey('dim_helper_len_4'));
      await tester.ensureVisible(len4Finder);
      await tester.tap(len4Finder);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dim_helper_apply_btn')));
      await tester.pumpAndSettle();

      final specTextField = tester.widget<TextField>(
        find.byKey(const ValueKey('quick_grid_spec_0')),
      );
      expect(specTextField.controller?.text, '1" × 6" × 4.00m');

      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_name_0')),
        'Tabla Lapacho',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_price_0')),
        '15000',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('quick_grid_submit_btn')),
      );
      await tester.tap(find.byKey(const ValueKey('quick_grid_submit_btn')));
      await tester.pumpAndSettle();

      expect(repo.createdPayloads.length, 1);
      final sent = repo.createdPayloads.single;
      expect(sent['technical_spec'], '1" × 6" × 4.00m');
      expect(sent['calc_config'], isA<Map>());
      final cfg = sent['calc_config'] as Map;
      expect(cfg['type'], 'wood');
      expect(cfg['inch_preset'], '6');
      expect(cfg['length_m'], closeTo(4.0, 0.001));
    });
  });

  group('Multi-Vertical UI — Adaptación de Ficha y Etiquetas', () {
    testWidgets(
        'apparel muestra Talle / Color y oculta fraccionamiento y vencimientos',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _TestCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      final settingsProv = _FakeSettingsProvider(
        businessType: 'apparel',
        batchExpiration: false,
        production: false,
      );
      addTearDown(() {
        catalogProv.dispose();
        settingsProv.dispose();
      });

      await _pumpFormDialog(
        tester,
        catalogProv: catalogProv,
        settingsProv: settingsProv,
      );

      expect(find.text('Talle / Color'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('product_fractional_switch')),
        findsNothing,
      );
      expect(
        find.text('Control de Vencimiento y Alertas (Opcional)'),
        findsNothing,
      );
    });

    testWidgets(
        'tech muestra Modelo / Especificación y oculta fraccionamiento y vencimientos',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _TestCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      final settingsProv = _FakeSettingsProvider(
        businessType: 'tech',
        batchExpiration: false,
        production: false,
      );
      addTearDown(() {
        catalogProv.dispose();
        settingsProv.dispose();
      });

      await _pumpFormDialog(
        tester,
        catalogProv: catalogProv,
        settingsProv: settingsProv,
      );

      expect(find.text('Modelo / Especificación'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('product_fractional_switch')),
        findsNothing,
      );
      expect(
        find.text('Control de Vencimiento y Alertas (Opcional)'),
        findsNothing,
      );
    });

    testWidgets(
        'butcher inicia producto nuevo en kg y venta por peso activa',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _TestCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      final settingsProv = _FakeSettingsProvider(
        businessType: 'butcher',
        batchExpiration: true,
      );
      addTearDown(() {
        catalogProv.dispose();
        settingsProv.dispose();
      });

      await _pumpFormDialog(
        tester,
        catalogProv: catalogProv,
        settingsProv: settingsProv,
      );

      expect(find.byKey(const ValueKey('unit_type_wide_kg')), findsOneWidget);
      final fracSwitch = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('product_fractional_switch')),
      );
      expect(fracSwitch.value, isTrue);
    });

    testWidgets(
        'retail con multi_rubro cambia unidad de un -> kg al elegir categoría de Rubro Carnicería',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final kioscoRubro = Rubro(
        id: 1,
        name: 'Kiosco',
        verticalType: 'retail',
      );
      final carneRubro = Rubro(
        id: 2,
        name: 'Carnicería',
        verticalType: 'butcher',
      );
      final repo = _TestCatalogRepository(
        rubros: [kioscoRubro, carneRubro],
        categories: [
          Category(id: 10, name: 'Golosinas', rubroId: 1, rubro: kioscoRubro),
          Category(id: 11, name: 'Cortes Vacunos', rubroId: 2, rubro: carneRubro),
        ],
      );
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      await catalogProv.loadMetadata();
      await catalogProv.loadRubros();

      final settingsProv = _FakeSettingsProvider(
        businessType: 'retail',
        multiRubro: true,
        batchExpiration: true,
      );
      addTearDown(() {
        catalogProv.dispose();
        settingsProv.dispose();
      });

      await _pumpFormDialog(
        tester,
        catalogProv: catalogProv,
        settingsProv: settingsProv,
      );

      expect(find.byKey(const ValueKey('unit_type_wide_un')), findsOneWidget);
      var fracSwitch = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('product_fractional_switch')),
      );
      expect(fracSwitch.value, isFalse);

      // Abrir SearchableSelectField de Categoría y seleccionar Cortes Vacunos (Carnicería)
      final catSelector = find.text('Categoría');
      await tester.ensureVisible(catSelector);
      await tester.tap(catSelector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cortes Vacunos'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('unit_type_wide_kg')), findsOneWidget);
      fracSwitch = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('product_fractional_switch')),
      );
      expect(fracSwitch.value, isTrue);
    });

    testWidgets(
        'PrintLabelsDialog muestra technicalSpec debajo del nombre del producto',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsProv = _FakeSettingsProvider(businessType: 'apparel');
      final localTerminal = _FakeLocalTerminalProvider();
      addTearDown(() {
        settingsProv.dispose();
        localTerminal.dispose();
      });

      final tshirt = Product(
        id: 701,
        name: 'Remera Oversize',
        internalCode: '00701',
        costPrice: 5000,
        sellingPrice: 12000,
        stock: 10,
        active: true,
        isSoldByWeight: false,
        unitType: 'un',
        technicalSpec: 'Talle XL · Negro',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: localTerminal,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PrintLabelsDialog(products: [tshirt]),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Remera Oversize'), findsOneWidget);
      expect(find.text('Talle XL · Negro'), findsOneWidget);
    });
  });

  group('Phase-2 Polish — Unidades, Ticket Details, Apparel 👕 y F7 Mostrador',
      () {
    test(
        'Madera Lapacho fraccionable con calcConfig resuelve un./un mientras pesable legado conserva Kg/kg',
        () {
      final lapacho = Product(
        id: 801,
        name: 'Madera Lapacho',
        internalCode: '00801',
        costPrice: 24000,
        sellingPrice: 36930,
        stock: 15,
        active: true,
        isSoldByWeight: true,
        unitType: 'un',
        calcConfig: {'type': 'wood', 'inch_preset': '6', 'length_m': 4.0},
      );
      expect(
        lapacho.isDiscreteFractionalItem(businessUsesScaleWeight: false),
        isTrue,
      );
      expect(lapacho.effectiveQuantityUnitLabel, 'un.');
      expect(lapacho.effectiveReceiptUnitSuffix, 'un');

      final costilla = Product(
        id: 802,
        name: 'Costilla Novillo',
        internalCode: '00802',
        costPrice: 6000,
        sellingPrice: 9500,
        stock: 25,
        active: true,
        isSoldByWeight: true,
        unitType: 'un',
        category: Category(
          id: 50,
          name: 'Cortes Vacunos',
          rubroId: 5,
          rubro: Rubro(id: 5, name: 'Carnicería', verticalType: 'butcher'),
        ),
      );
      expect(
        costilla.isDiscreteFractionalItem(businessUsesScaleWeight: false),
        isFalse,
      );
      expect(costilla.effectiveQuantityUnitLabel, 'Kg');
      expect(costilla.effectiveReceiptUnitSuffix, 'kg');

      expect(Product.discreteUnitTypes, contains('docena'));
      expect(Product.shortLabelFor('docena'), 'doc.');
    });

    test(
        'Product.resolveEffectiveReceiptDetails deduplica case-insensitive y sanitiza ASCII para ESC/POS',
        () {
      expect(
        Product.resolveEffectiveReceiptDetails(
          displayName: 'Madera Lapacho 1" x 6" x 4m',
          technicalSpec: '1" × 6" × 4m',
        ),
        isNull,
      );

      expect(
        Product.resolveEffectiveReceiptDetails(
          displayName: 'Remera Algodón',
          technicalSpec: 'Talle XL · Negro',
          customDetails: 'talle xl - negro',
        ),
        'talle xl - negro',
      );

      expect(
        Product.resolveEffectiveReceiptDetails(
          displayName: 'Madera Lapacho',
          technicalSpec: '1" × 6" · 4.00m',
          asciiOnly: true,
        ),
        '1" x 6" - 4.00m',
      );

      expect(
        Product.resolveEffectiveReceiptDetails(
          displayName: 'Buzo Básico',
          technicalSpec: 'Talle Único · Negro',
          asciiOnly: true,
        ),
        'Talle Unico - Negro',
      );
    });

    testWidgets(
        'ApparelVariantHelperDialog (👕) funciona en ProductFormDialog manteniendo edición libre',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _TestCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      final settingsProv = _FakeSettingsProvider(businessType: 'apparel');
      addTearDown(() {
        catalogProv.dispose();
        settingsProv.dispose();
      });

      await _pumpFormDialog(
        tester,
        catalogProv: catalogProv,
        settingsProv: settingsProv,
      );

      final btn = find.byKey(const ValueKey('apparel_variant_helper_btn'));
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('apparel_size_XL')));
      await tester.tap(find.byKey(const ValueKey('apparel_color_Negro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apparel_helper_apply_btn')));
      await tester.pumpAndSettle();

      var specField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('product_technical_spec_field')),
      );
      expect(specField.controller?.text, 'Talle XL - Negro');

      await tester.tap(btn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apparel_size_Único')));
      await tester.tap(find.byKey(const ValueKey('apparel_color_Blanco')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apparel_helper_apply_btn')));
      await tester.pumpAndSettle();

      specField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('product_technical_spec_field')),
      );
      expect(specField.controller?.text, 'Talle Único - Blanco');

      await tester.enterText(
        find.byKey(const ValueKey('product_technical_spec_field')),
        'Especial Boutique XL',
      );
      await tester.pumpAndSettle();
      specField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('product_technical_spec_field')),
      );
      expect(specField.controller?.text, 'Especial Boutique XL');
    });

    testWidgets(
        'PosHardwareCalculatorDialog muestra pos_f7_missing_width_warning para "1\\" / 4m" y se limpia al elegir 6"',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _TestCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      final settingsProv = _FakeSettingsProvider(businessType: 'hardware_store');
      final posProv = _FakePosProvider();
      final offerProv = _FakeOfferProvider();
      final localTerminal = _FakeLocalTerminalProvider();
      addTearDown(() {
        catalogProv.dispose();
        settingsProv.dispose();
        posProv.dispose();
        offerProv.dispose();
        localTerminal.dispose();
      });

      final woodWithoutWidth = Product(
        id: 850,
        name: 'Madera Lapacho',
        internalCode: '00850',
        costPrice: 20000,
        sellingPrice: 36930,
        stock: 10,
        active: true,
        isSoldByWeight: true,
        unitType: 'un',
        technicalSpec: '1" / 4m',
        calcConfig: null,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<OfferProvider>.value(value: offerProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: localTerminal,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PosHardwareCalculatorDialog(
                initialProduct: woodWithoutWidth,
                target: HardwareCalculatorTarget.pos,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('pos_f7_missing_width_warning')),
        findsOneWidget,
      );

      final chip6Finder = find.byKey(const ValueKey('pos_f7_wood_inch_6'));
      await tester.ensureVisible(chip6Finder);
      await tester.tap(chip6Finder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('pos_f7_missing_width_warning')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('pos_f7_wood_inch_6')), findsOneWidget);
    });

    testWidgets(
        'ThermalReceiptWidget en 58mm imprime technicalSpec sin duplicar y usa "un" para tablas fraccionables',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsProv = _FakeSettingsProvider(
        businessType: 'retail',
        secondaryBusinessTypes: const ['hardware_store', 'apparel'],
      );
      addTearDown(settingsProv.dispose);

      final tshirt = CartItem(
        product: Product(
          id: 901,
          name: 'Remera Oversize',
          internalCode: '00901',
          costPrice: 5000,
          sellingPrice: 12000,
          stock: 10,
          active: true,
          isSoldByWeight: false,
          unitType: 'un',
          technicalSpec: 'Talle XL - Negro',
        ),
        quantity: 1,
      );

      final lapacho = CartItem(
        product: Product(
          id: 902,
          name: 'Madera Lapacho',
          internalCode: '00902',
          costPrice: 20000,
          sellingPrice: 36930,
          stock: 20,
          active: true,
          isSoldByWeight: true,
          unitType: 'un',
          technicalSpec: '1" × 6" × 4.00m',
          calcConfig: {'type': 'wood', 'inch_preset': '6', 'length_m': 4.0},
        ),
        quantity: 2.5,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProv,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ThermalReceiptWidget(
                  paperWidth: ThermalPaperWidth.mm58,
                  items: [tshirt, lapacho],
                  total: 104325,
                  payments: const [
                    {'name': 'Efectivo', 'amount': 104325},
                  ],
                  businessSettings: settingsProv.settings,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('* Talle XL - Negro'), findsOneWidget);
      expect(find.text('* 1" × 6" × 4.00m'), findsOneWidget);
      expect(find.textContaining('2.5 un x'), findsOneWidget);
      expect(find.textContaining('2.5 kg'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'ThermalReceiptWidget en 80mm imprime technicalSpec deduplicado y usa "un" para maderas fraccionables',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(440, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settingsProv = _FakeSettingsProvider(
        businessType: 'retail',
        secondaryBusinessTypes: const ['hardware_store', 'apparel'],
      );
      addTearDown(settingsProv.dispose);

      final tshirt = CartItem(
        product: Product(
          id: 903,
          name: 'Remera Oversize',
          internalCode: '00903',
          costPrice: 5000,
          sellingPrice: 12000,
          stock: 10,
          active: true,
          isSoldByWeight: false,
          unitType: 'un',
          technicalSpec: 'Talle Único - Blanco',
        ),
        quantity: 1,
      );

      final alreadyInNameWood = CartItem(
        product: Product(
          id: 904,
          name: 'Tabla Pino 1" x 6" x 4.00m',
          internalCode: '00904',
          costPrice: 8000,
          sellingPrice: 14000,
          stock: 12,
          active: true,
          isSoldByWeight: true,
          unitType: 'un',
          technicalSpec: '1" × 6" × 4.00m',
          calcConfig: {'type': 'wood', 'inch_preset': '6', 'length_m': 4.0},
        ),
        quantity: 1.5,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProv,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ThermalReceiptWidget(
                  paperWidth: ThermalPaperWidth.mm80,
                  items: [tshirt, alreadyInNameWood],
                  total: 33000,
                  payments: const [
                    {'name': 'Efectivo', 'amount': 33000},
                  ],
                  businessSettings: settingsProv.settings,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('* Talle Único - Blanco'), findsOneWidget);
      // Deduplicado case/symbol-insensitive porque ya figura en "Tabla Pino 1" x 6" x 4.00m"
      expect(find.text('* 1" × 6" × 4.00m'), findsNothing);
      expect(find.textContaining('1.5 un x'), findsOneWidget);
      expect(find.textContaining('1.5 kg'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'SupplierQuickGridDialog en apparel aplica asistente 👕 ("Talle XL - Negro" y "Talle Único - Blanco") y guarda unidad docena',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _TestCatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      final settingsProv = _FakeSettingsProvider(businessType: 'apparel');
      final supplierProv = _FakeSupplierProvider();
      final localTerminal = _FakeLocalTerminalProvider();
      final authProv = _FakeAuthProvider();
      final alertsProv = _FakeInventoryAlertsProvider();
      final posProv = _FakePosProvider();
      final offerProv = _FakeOfferProvider();
      addTearDown(() {
        catalogProv.dispose();
        settingsProv.dispose();
        supplierProv.dispose();
        localTerminal.dispose();
        authProv.dispose();
        alertsProv.dispose();
        posProv.dispose();
        offerProv.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<SupplierProvider>.value(value: supplierProv),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: localTerminal,
            ),
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: alertsProv,
            ),
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<OfferProvider>.value(value: offerProv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SupplierQuickGridDialog(
                provider: catalogProv,
                initialSupplierId: 7,
                initialSupplierName: 'Maderera Norte',
                alreadyAuthorized: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // En apparel NO debe existir columna Frac. ni botón de maderas 📏
      expect(find.byKey(const ValueKey('quick_grid_dim_helper_0')), findsNothing);
      expect(
        find.byKey(const ValueKey('quick_grid_apparel_helper_0')),
        findsOneWidget,
      );

      // Fila 0: elegir "Talle XL - Negro"
      await tester.tap(find.byKey(const ValueKey('quick_grid_apparel_helper_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apparel_size_XL')));
      await tester.tap(find.byKey(const ValueKey('apparel_color_Negro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apparel_helper_apply_btn')));
      await tester.pumpAndSettle();

      final spec0 = tester.widget<TextField>(
        find.byKey(const ValueKey('quick_grid_spec_0')),
      );
      expect(spec0.controller?.text, 'Talle XL - Negro');

      // Fila 1: elegir "Talle Único - Blanco" y unidad "docena"
      await tester.tap(find.byKey(const ValueKey('quick_grid_apparel_helper_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apparel_size_Único')));
      await tester.tap(find.byKey(const ValueKey('apparel_color_Blanco')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apparel_helper_apply_btn')));
      await tester.pumpAndSettle();

      final spec1 = tester.widget<TextField>(
        find.byKey(const ValueKey('quick_grid_spec_1')),
      );
      expect(spec1.controller?.text, 'Talle Único - Blanco');

      await tester.tap(find.byKey(const ValueKey('quick_grid_unit_dd_1_un')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('doc.').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_name_0')),
        'Remera Algodón',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_price_0')),
        '14500',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_name_1')),
        'Pack Medias Deportivas',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_price_1')),
        '18000',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('quick_grid_submit_btn')),
      );
      await tester.tap(find.byKey(const ValueKey('quick_grid_submit_btn')));
      await tester.pumpAndSettle();

      expect(repo.createdPayloads.length, 2);
      expect(repo.createdPayloads[0]['technical_spec'], 'Talle XL - Negro');
      expect(repo.createdPayloads[0]['unit_type'], 'un');
      expect(repo.createdPayloads[0]['is_sold_by_weight'], isFalse);

      expect(repo.createdPayloads[1]['technical_spec'], 'Talle Único - Blanco');
      expect(repo.createdPayloads[1]['unit_type'], 'docena');
      expect(repo.createdPayloads[1]['is_sold_by_weight'], isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'PosQuickAccessCatalogView en los 4 modos muestra "/un." y "📏 Fracc." en Madera Lapacho (nunca /Kg ni ⚖️) y Talle/Color en Indumentaria',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final posProv = _FakePosProvider();
      addTearDown(posProv.dispose);

      final lapacho = Product(
        id: 950,
        name: 'Madera Lapacho',
        internalCode: '00950',
        costPrice: 20000,
        sellingPrice: 36930,
        stock: 15,
        active: true,
        isSoldByWeight: true,
        unitType: 'un',
        technicalSpec: '1" × 6" × 4.00m',
        calcConfig: {'type': 'wood', 'inch_preset': '6', 'length_m': 4.0},
      );

      final remera = Product(
        id: 951,
        name: 'Remera Oversize',
        internalCode: '00951',
        costPrice: 6000,
        sellingPrice: 15000,
        stock: 8,
        active: true,
        isSoldByWeight: false,
        unitType: 'un',
        technicalSpec: 'Talle XL - Negro',
      );

      for (final mode in const ['list', 'compact', 'grid_medium', 'grid_large']) {
        await tester.pumpWidget(
          ChangeNotifierProvider<PosProvider>.value(
            value: posProv,
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 900,
                  height: 700,
                  child: PosQuickAccessCatalogView(
                    products: [lapacho, remera],
                    viewMode: mode,
                    canUseScaleWeight: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('/un.'),
          findsOneWidget,
          reason: 'Modo $mode debe mostrar /un. para Madera Lapacho',
        );
        expect(
          find.byIcon(Icons.straighten_rounded),
          findsOneWidget,
          reason: 'Modo $mode debe usar ícono de regla (no balanza) en Madera Lapacho',
        );
        expect(
          find.byIcon(Icons.scale_rounded),
          findsNothing,
          reason: 'Modo $mode jamás debe mostrar ícono de balanza en Madera Lapacho',
        );
        if (mode == 'list') {
          expect(
            find.text('📏 Fracc.'),
            findsOneWidget,
            reason: 'Modo list debe mostrar badge 📏 Fracc. para Madera Lapacho',
          );
        } else if (mode == 'grid_medium' || mode == 'grid_large') {
          expect(
            find.text('Fracc.'),
            findsOneWidget,
            reason: 'Modo $mode debe mostrar pill Fracc. junto al ícono de regla',
          );
          expect(
            find.text('Por Peso'),
            findsNothing,
            reason: 'Modo $mode jamás debe mostrar "Por Peso" en Madera Lapacho',
          );
        }
        expect(
          find.textContaining('/Kg'),
          findsNothing,
          reason: 'Modo $mode jamás debe mostrar /Kg en Madera Lapacho',
        );
        expect(
          find.textContaining('⚖️'),
          findsNothing,
          reason: 'Modo $mode jamás debe mostrar ⚖️ en Madera Lapacho',
        );
        expect(
          find.text('Talle XL - Negro'),
          findsOneWidget,
          reason: 'Modo $mode debe mostrar technicalSpec de indumentaria',
        );
        expect(
          find.text('1" × 6" × 4.00m'),
          findsOneWidget,
          reason: 'Modo $mode debe mostrar technicalSpec de madera',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'showTerminalPeripheralsDialog en Indumentaria muestra "Posnet Point" y oculta Balanza Serie (y en Retail muestra "Balanza y Point")',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final apparelSettings = _FakeSettingsProvider(businessType: 'apparel');
      final retailSettings = _FakeSettingsProvider(businessType: 'retail');
      final localTerminal = _FakeLocalTerminalProvider(scaleComPort: '');
      final cashProv = _FakeCashRegisterProvider();
      addTearDown(() {
        apparelSettings.dispose();
        retailSettings.dispose();
        localTerminal.dispose();
        cashProv.dispose();
      });

      // 1. Indumentaria (sin balanza): Tab 1 no muestra Balanza Serie y Tab 3 dice "Posnet Point"
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
              value: apparelSettings,
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: localTerminal,
            ),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: cashProv),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      showTerminalPeripheralsDialog(ctx, initialTab: 0),
                  child: const Text('Abrir Periféricos'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir Periféricos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.widgetWithText(Tab, 'Posnet Point'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Balanza y Point'), findsNothing);
      expect(find.text('Balanza Serie'), findsNothing);

      await tester.tap(find.widgetWithText(Tab, 'Posnet Point'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.text('Balanza Electrónica (Cable Serie / USB-COM)'),
        findsNothing,
      );
      expect(
        find.text('Posnet Mercado Pago Point (Opcional por Caja)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Cerrar modal antes de probar Retail
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 2. Retail (con balanza): Tab 1 muestra Balanza Serie y Tab 3 dice "Balanza y Point"
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
              value: retailSettings,
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: localTerminal,
            ),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: cashProv),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      showTerminalPeripheralsDialog(ctx, initialTab: 0),
                  child: const Text('Abrir Periféricos Retail'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir Periféricos Retail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.widgetWithText(Tab, 'Balanza y Point'), findsOneWidget);
      expect(find.text('Balanza Serie'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'Balanza y Point'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.text('Balanza Electrónica (Cable Serie / USB-COM)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    });
  });
}
