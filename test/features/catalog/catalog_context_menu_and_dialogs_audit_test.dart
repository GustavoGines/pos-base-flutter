import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/presentation/widgets/searchable_select_field.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_batch_model.dart';
import 'package:frontend_desktop/features/catalog/data/models/production_order_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/print_labels_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/production_orders_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/stock_adjustment_dialog.dart';
import 'package:frontend_desktop/features/catalog/utils/product_share_helper.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _AuditCatalogRepository implements CatalogRepository {
  List<Product> seededProducts = const [];

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
      'data': List<Product>.from(seededProducts),
      'current_page': 1,
      'last_page': 1,
      'total': seededProducts.length,
    };
  }

  @override
  Future<List<Category>> getCategories() async => [
        Category(id: 1, name: 'Electricidad'),
        Category(id: 2, name: 'Pastelería'),
      ];

  @override
  Future<List<Brand>> getBrands() async => [
        Brand(id: 1, name: 'Genérica'),
      ];

  @override
  Future<List<Rubro>> getRubros() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuditCatalogProvider extends CatalogProvider {
  Completer<List<Product>>? pendingProductionFetch;
  final List<Product> productionProducts;

  _AuditCatalogProvider({
    required _AuditCatalogRepository repository,
    this.productionProducts = const [],
  }) : super(
          getProductsUseCase: GetProductsUseCase(repository),
          repository: repository,
        );

  @override
  Future<List<Product>> fetchAllActiveProductsForProduction() async {
    if (pendingProductionFetch != null) {
      return pendingProductionFetch!.future;
    }
    return productionProducts;
  }

  @override
  Future<Map<String, dynamic>> fetchProductionOrders({
    int page = 1,
    int? productId,
    String? status,
    String? search,
  }) async =>
      {
        'data': <ProductionOrderModel>[],
        'current_page': 1,
        'last_page': 1,
        'total': 0,
      };

  @override
  Future<Map<String, dynamic>> fetchWasteReport({
    String? startDate,
    String? endDate,
  }) async =>
      {
        'total_events': 0,
        'total_units_lost': 0,
        'total_cost_lost': 0,
        'movements': <dynamic>[],
      };

  @override
  Future<ProductBatchesResponse> fetchProductBatches(
    int productId, {
    bool includeClosed = true,
  }) async =>
      ProductBatchesResponse(
        productId: productId,
        productName: 'Producto',
        trackBatches: false,
        lotDeductionPolicy: 'fefo',
        allowSellExpired: false,
        stock: 10,
        batches: const [],
      );
}

class _AuditSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  _AuditSettingsProvider({required String businessType})
      : _settings = BusinessSettings(
          companyName: 'Test Audit POS',
          businessType: businessType,
          licensePlanType: 'premium',
          features: const FeatureFlags(
            quotes: true,
            suppliers: true,
            multiRubro: true,
            batchExpiration: true,
            production: true,
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
  List<String> get allowedAddons => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuditSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => const [];

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuditLocalTerminalProvider extends ChangeNotifier
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

class _AuditAuthProvider extends ChangeNotifier implements AuthProvider {
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

class _AuditInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => const [];

  @override
  int get totalAlertsCount => 0;

  @override
  List<dynamic> get reactiveAlerts => const [];

  @override
  List<dynamic> get predictiveCriticalAlerts => const [];

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  group('Auditoría de menú contextual y modales de Catálogo', () {
    testWidgets(
      'ProductionOrdersDialog preselecciona inmediatamente un initialProduct inactivo en POS y lo mantiene tras cargar catálogo',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 820);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio);

        final inactiveAlfajor = Product(
          id: 2573,
          name: 'Alfajores de Maicena x12',
          internalCode: '00006',
          costPrice: 3200,
          sellingPrice: 8500,
          stock: 15,
          active: false,
          isSoldByWeight: false,
          unitType: 'caja',
        );
        final activeProduct = Product(
          id: 2576,
          name: 'Brownie con Nueces',
          internalCode: '00009',
          costPrice: 6500,
          sellingPrice: 16000,
          stock: 9,
          active: true,
          isSoldByWeight: false,
          unitType: 'un',
          hasProductionRecipe: true,
        );

        final repo = _AuditCatalogRepository()
          ..seededProducts = [inactiveAlfajor, activeProduct];
        final pendingFetch = Completer<List<Product>>();
        final provider = _AuditCatalogProvider(
          repository: repo,
          productionProducts: [activeProduct],
        )..pendingProductionFetch = pendingFetch;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProductionOrdersDialog(
                provider: provider,
                initialProduct: inactiveAlfajor,
              ),
            ),
          ),
        );

        // Desde el primer frame debe figurar seleccionado aunque aún esté cargando
        await tester.pump();
        expect(find.text('Alfajores de Maicena x12'), findsOneWidget);
        expect(find.text('Cant. a producir (caja) *'), findsOneWidget);

        // Completar la carga asíncrona con productos que no incluyen al inactivo
        pendingFetch.complete([activeProduct]);
        await tester.pumpAndSettle();

        expect(find.text('Alfajores de Maicena x12'), findsOneWidget);
        expect(
          find.textContaining('Costo unitario del lote resultante: \$3.200 / caja'),
          findsOneWidget,
        );

        // Al abrir el picker debe figurar en la lista con etiqueta "Inactivo en POS"
        await tester.tap(find.byType(SearchableSelectField<int>));
        await tester.pumpAndSettle();
        expect(find.textContaining('Inactivo en POS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'CatalogScreen en modo Ferretería oculta Producción/Lotes y muestra unidad real en encabezado del menú contextual',
      (tester) async {
        tester.view.physicalSize = const Size(1500, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio);

        final cable = Product(
          id: 3001,
          name: 'Cable Unipolar 2.5mm Rollo',
          internalCode: 'HW301',
          supplierSku: 'PRY-25',
          costPrice: 1500,
          sellingPrice: 2800,
          stock: 25,
          active: true,
          isSoldByWeight: true,
          unitType: 'mt',
          storageLocation: 'Pasillo 2',
          technicalSpec: '2.5mm IRAM',
        );

        final repo = _AuditCatalogRepository()..seededProducts = [cable];
        final provider = _AuditCatalogProvider(repository: repo);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<CatalogProvider>.value(value: provider),
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) =>
                    _AuditSettingsProvider(businessType: 'hardware_store'),
              ),
              ChangeNotifierProvider<SupplierProvider>(
                create: (_) => _AuditSupplierProvider(),
              ),
              ChangeNotifierProvider<LocalTerminalProvider>(
                create: (_) => _AuditLocalTerminalProvider(),
              ),
              ChangeNotifierProvider<AuthProvider>(
                create: (_) => _AuditAuthProvider(),
              ),
              ChangeNotifierProvider<InventoryAlertsProvider>(
                create: (_) => _AuditInventoryAlertsProvider(),
              ),
            ],
            child: const MaterialApp(
              home: CatalogScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Barra superior: botón "Producción" oculto en Ferretería
        expect(find.text('Producción'), findsNothing);

        // Clic derecho sobre la fila del producto
        final rowCenter = tester.getCenter(find.text('Cable Unipolar 2.5mm Rollo'));
        await tester.tapAt(rowCenter, buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        // Encabezado muestra la unidad real "25 mt" y no "Kg" ni "un."
        expect(find.textContaining('Stock: 25 mt'), findsOneWidget);
        // Opciones exclusivas de Retail/Gastronomía ocultas en Ferretería
        expect(find.text('Lotes y vencimientos'), findsNothing);
        expect(find.text('Elaborar / Hornear ahora'), findsNothing);
        // Las opciones válidas de Ferretería siguen presentes
        expect(find.text('Editar producto'), findsOneWidget);
        expect(find.text('Ajustar stock'), findsOneWidget);
        expect(find.text('Imprimir etiqueta'), findsOneWidget);
        expect(find.text('Compartir ficha (WhatsApp)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'StockAdjustmentDialog en modo Ferretería oculta lotes y usa unidad real mt en lugar de Kg',
      (tester) async {
        tester.view.physicalSize = const Size(980, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio);

        final cable = Product(
          id: 3002,
          name: 'Cable Subterráneo 4mm',
          internalCode: 'HW302',
          costPrice: 3000,
          sellingPrice: 5200,
          stock: 40,
          active: true,
          isSoldByWeight: true,
          unitType: 'mt',
        );
        final repo = _AuditCatalogRepository()..seededProducts = [cable];
        final provider = _AuditCatalogProvider(repository: repo);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<CatalogProvider>.value(value: provider),
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) =>
                    _AuditSettingsProvider(businessType: 'hardware_store'),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: StockAdjustmentDialog(
                  provider: provider,
                  product: cable,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Stock actual: 40.000 mt'), findsOneWidget);
        expect(find.textContaining('Kg'), findsNothing);
        expect(find.text('Ver Lotes'), findsNothing);
        expect(find.text('Código de Lote (opc.)'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PrintLabelsDialog desacopla balanza en gramos para Ferretería / metros y la mantiene en Retail kg',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio);

        final cableMt = Product(
          id: 3003,
          name: 'Manguera Riego 1/2',
          internalCode: 'HW303',
          costPrice: 700,
          sellingPrice: 1200,
          stock: 100,
          active: true,
          isSoldByWeight: true,
          unitType: 'mt',
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) =>
                    _AuditSettingsProvider(businessType: 'hardware_store'),
              ),
              ChangeNotifierProvider<LocalTerminalProvider>(
                create: (_) => _AuditLocalTerminalProvider(),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: PrintLabelsDialog(
                  key: const ValueKey('hardware_labels'),
                  products: [cableMt],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Peso:'), findsNothing);
        expect(find.text('gr'), findsNothing);
        final envTileHardware = tester.widget<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, 'Imprimir ENV y VTO'),
        );
        expect(envTileHardware.value, isFalse);

        // Desmontar el árbol anterior para recrear SettingsProvider en modo retail
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // Ahora en Retail con producto de balanza kg
        final cheeseKg = Product(
          id: 3004,
          name: 'Queso Cremoso',
          internalCode: 'RT304',
          costPrice: 4000,
          sellingPrice: 6500,
          stock: 12,
          active: true,
          isSoldByWeight: true,
          unitType: 'kg',
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _AuditSettingsProvider(businessType: 'retail'),
              ),
              ChangeNotifierProvider<LocalTerminalProvider>(
                create: (_) => _AuditLocalTerminalProvider(),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: PrintLabelsDialog(
                  key: const ValueKey('retail_labels'),
                  products: [cheeseKg],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Peso:'), findsOneWidget);
        expect(find.text('gr'), findsOneWidget);
        final leftListScrollable = find
            .descendant(
              of: find.descendant(
                of: find.byType(PrintLabelsDialog),
                matching: find.byType(ListView),
              ).first,
              matching: find.byType(Scrollable),
            )
            .first;
        final envTileRetailFinder =
            find.widgetWithText(CheckboxListTile, 'Imprimir ENV y VTO');
        await tester.scrollUntilVisible(
          envTileRetailFinder,
          120.0,
          scrollable: leftListScrollable,
        );
        final envTileRetail =
            tester.widget<CheckboxListTile>(envTileRetailFinder);
        expect(envTileRetail.value, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );

    test(
      'ProductShareHelper incluye medida técnica y unidad métrica para Ferretería, manteniendo Retail x peso',
      () {
        final hardwareCable = Product(
          id: 3005,
          name: 'Cable Taller 2x1.5mm',
          internalCode: 'HW305',
          costPrice: 1200,
          sellingPrice: 2100,
          stock: 50,
          active: true,
          isSoldByWeight: true,
          unitType: 'mt',
          technicalSpec: '2.5mm x 100m',
        );

        final retailMeat = Product(
          id: 3006,
          name: 'Carne Picada Especial',
          internalCode: 'RT306',
          costPrice: 5000,
          sellingPrice: 8200,
          stock: 10,
          active: true,
          isSoldByWeight: true,
          unitType: 'kg',
        );

        final hardwareText =
            ProductShareHelper.formatProductShareText(hardwareCable);
        expect(hardwareText, contains('- Medida: 2.5mm x 100m'));
        expect(hardwareText, contains('- Venta por mt'));
        expect(hardwareText, isNot(contains('- Producto por peso')));

        final retailText =
            ProductShareHelper.formatProductShareText(retailMeat);
        expect(retailText, contains('- Producto por peso'));
        expect(retailText, isNot(contains('- Medida:')));
      },
    );
  });
}
