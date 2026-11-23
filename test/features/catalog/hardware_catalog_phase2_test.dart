import 'dart:convert';
import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart'
    show ProductFormDialog;
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/catalog_import_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/supplier_quick_grid_dialog.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/presentation/widgets/supplier_invoice_form_dialog.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _Phase2CatalogRepository implements CatalogRepository {
  final List<Map<String, dynamic>> createdPayloads = [];
  int _nextId = 300;
  List<Product> stubProducts = [];
  void Function()? onBeforeCreateProduct;

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
      'data': List<Product>.from(stubProducts),
      'current_page': page,
      'last_page': 1,
      'total': stubProducts.length,
    };
  }

  @override
  Future<Product> createProduct(Map<String, dynamic> productData) async {
    onBeforeCreateProduct?.call();
    createdPayloads.add(Map<String, dynamic>.from(productData));
    final id = _nextId++;
    return ProductModel(
      id: id,
      name: productData['name']?.toString() ?? 'Producto $id',
      barcode: productData['barcode']?.toString(),
      internalCode: id.toString().padLeft(5, '0'),
      costPrice: (productData['cost_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (productData['selling_price'] as num?)?.toDouble() ?? 0.0,
      stock: (productData['stock'] as num?)?.toDouble() ?? 0.0,
      active: true,
      isSoldByWeight: productData['is_sold_by_weight'] == true,
      unitType: productData['unit_type']?.toString() ?? 'un',
      supplierSku: productData['supplier_sku']?.toString(),
      storageLocation: productData['storage_location']?.toString(),
      technicalSpec: productData['technical_spec']?.toString(),
    );
  }

  @override
  Future<List<Category>> getCategories() async =>
      [Category(id: 1, name: 'Ferretería')];

  @override
  Future<List<Brand>> getBrands() async => [Brand(id: 2, name: 'Stanley')];

  @override
  Future<List<Rubro>> getRubros() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyImportCatalogProvider extends ChangeNotifier
    implements CatalogProvider {
  int? lastImportSupplierId;
  double? lastImportMarginPercent;
  String? lastImportFilename;

  @override
  int? get filterSupplierId => null;

  @override
  String? get filterSupplierName => null;

  @override
  Future<Map<String, dynamic>> importProducts({
    required List<int> fileBytes,
    required String filename,
    int? defaultSupplierId,
    double? defaultMarginPercent,
  }) async {
    lastImportFilename = filename;
    lastImportSupplierId = defaultSupplierId;
    lastImportMarginPercent = defaultMarginPercent;
    return {
      'created_count': 1,
      'updated_count': 0,
      'failed_count': 0,
      'errors': const [],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  _FakeSettingsProvider({
    String businessType = 'hardware_store',
    String taxCondition = 'monotributo',
  }) : _settings = BusinessSettings(
          businessType: businessType,
          taxCondition: taxCondition,
          licensePlanType: 'premium',
          features: const FeatureFlags(
            quotes: true,
            suppliers: true,
            multiRubro: true,
            batchExpiration: false,
            production: false,
          ),
        );

  @override
  BusinessSettings? get settings => _settings;

  @override
  bool get isResponsableInscripto => _settings.isResponsableInscripto;

  @override
  FeatureFlags get features => _settings.features;

  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  bool get isLicenseActive => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  int? lastSupplierId;
  Map<String, dynamic>? lastInvoicePayload;

  final List<Supplier> _suppliers = [
    Supplier(
      id: 7,
      name: 'Corralón Norte SA',
      balance: 0,
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
  Future<bool> createInvoice(int supplierId, Map<String, dynamic> data) async {
    lastSupplierId = supplierId;
    lastInvoicePayload = Map<String, dynamic>.from(data);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosProvider extends ChangeNotifier implements PosProvider {
  final List<Product> products;

  _FakePosProvider({this.products = const []});

  @override
  Future<List<Product>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return products.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.internalCode.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false) ||
          (p.supplierSku?.toLowerCase().contains(q) ?? false) ||
          (p.technicalSpec?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  void syncUpdatedCatalogProduct(Product product) {}

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

class _FakeApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyPinApiClient extends _FakeApiClient {
  String? activePinDuringCall;
  final List<String?> capturedPins = [];

  @override
  Future<T> withAdminPin<T>(String pin, Future<T> Function() action) async {
    final prev = activePinDuringCall;
    activePinDuringCall = pin;
    capturedPins.add(pin);
    try {
      return await action();
    } finally {
      activePinDuringCall = prev;
    }
  }
}

class _FakeLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  String get scaleComPort => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDropItem implements DropItem {
  @override
  final String name;
  final Uint8List _bytes;

  _FakeDropItem({required this.name, required Uint8List bytes}) : _bytes = bytes;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  group('Fase 2 - Compras y Carga Masiva por Proveedor', () {
    test(
        'CatalogRemoteDataSourceImpl.importProducts envía default_supplier_id y default_margin_percent',
        () async {
      late http.BaseRequest capturedRequest;
      final mockClient = MockClient.streaming((request, bodyStream) async {
        capturedRequest = request;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'created_count': 2,
                'updated_count': 0,
                'failed_count': 0,
                'errors': [],
              }),
            ),
          ),
          200,
        );
      });

      final ds = CatalogRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: mockClient,
      );

      final result = await ds.importProducts(
        utf8.encode('nombre,costo\nTornillo,100\n'),
        'lista.csv',
        defaultSupplierId: 7,
        defaultMarginPercent: 45.0,
      );

      expect(result['created_count'], 2);
      expect(capturedRequest, isA<http.MultipartRequest>());
      final multipart = capturedRequest as http.MultipartRequest;
      expect(multipart.fields['default_supplier_id'], '7');
      expect(multipart.fields['default_margin_percent'], '45.0');
    });

    testWidgets(
        'SupplierInvoiceFormDialog busca por supplierSku y convierte Bulto/Rollo con preview en vivo',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final cable = Product(
        id: 41,
        name: 'Cable Unipolar 2.5mm',
        internalCode: '00041',
        supplierSku: 'CAB-100',
        technicalSpec: '2.5mm IRAM',
        purchasePackageName: 'Rollo',
        conversionFactor: 100,
        unitType: 'mt',
        isSoldByWeight: true,
        costPrice: 1000,
        sellingPrice: 1500,
        stock: 50,
        active: true,
      );

      final fakeSupplier = _FakeSupplierProvider();
      final repo = _Phase2CatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(taxCondition: 'monotributo'),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(value: fakeSupplier),
            ChangeNotifierProvider<PosProvider>.value(
              value: _FakePosProvider(products: [cable]),
            ),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
            Provider<ApiClient>.value(value: _FakeApiClient()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SupplierInvoiceFormDialog(
                supplierId: 7,
                supplierName: 'Corralón Norte SA',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Buscar por supplier_sku
      await tester.enterText(
        find.byType(TextField).first,
        'CAB-100',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cód. Prov: CAB-100'), findsOneWidget);
      expect(find.textContaining('Rollo x100 mt'), findsOneWidget);

      await tester.tap(find.text('Cable Unipolar 2.5mm'));
      await tester.pumpAndSettle();

      // Selector explícito de modo Unidad base vs Rollo
      final pkgModeFinder =
          find.byKey(const ValueKey('invoice_item_pkg_mode_41_0'));
      final unitModeFinder =
          find.byKey(const ValueKey('invoice_item_unit_mode_41_0'));
      expect(unitModeFinder, findsOneWidget);
      expect(pkgModeFinder, findsOneWidget);

      await tester.tap(pkgModeFinder);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('invoice_item_qty_41_0')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('invoice_item_cost_41_0')),
        '120000',
      );
      await tester.pumpAndSettle();

      // Preview en vivo de stock entrante y costo unitario base
      expect(find.textContaining('Entran +200 mt al stock'), findsOneWidget);
      expect(find.textContaining('/ mt'), findsOneWidget);

      await tester.ensureVisible(find.text('CONFIRMAR CARGA'));
      await tester.tap(find.text('CONFIRMAR CARGA'));
      await tester.pumpAndSettle();

      expect(fakeSupplier.lastSupplierId, 7);
      expect(fakeSupplier.lastInvoicePayload, isNotNull);
      final items = fakeSupplier.lastInvoicePayload!['items'] as List;
      expect(items.length, 1);
      final line = items.first as Map<String, dynamic>;
      expect(line['product_id'], 41);
      expect(line['quantity'], 200.0);
      expect(line['unit_cost'], 1200.0);
      expect(line['subtotal'], 240000.0);
    });

    testWidgets(
        'CatalogImportDialog envía proveedor por defecto y % margen al importar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final spyCatalog = _SpyImportCatalogProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: spyCatalog),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CatalogImportDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('import_default_supplier_dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Corralón Norte SA').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('import_default_margin_field')),
        '45',
      );
      await tester.pumpAndSettle();

      // Simular soltar archivo CSV en el DropTarget
      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragDone?.call(
        DropDoneDetails(
          files: [
            _FakeDropItem(
              name: 'lista_corralon.csv',
              bytes: Uint8List.fromList(utf8.encode('nombre,costo\nClavo,100\n')),
            ),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('import_catalog_submit_btn')),
      );
      await tester.pumpAndSettle();

      expect(spyCatalog.lastImportFilename, 'lista_corralon.csv');
      expect(spyCatalog.lastImportSupplierId, 7);
      expect(spyCatalog.lastImportMarginPercent, 45.0);
    });

    testWidgets(
        'SupplierQuickGridDialog calcula PVP por margen y guarda múltiples artículos en lote',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _Phase2CatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _FakeLocalTerminalProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SupplierQuickGridDialog(
                provider: catalogProv,
                initialSupplierId: 7,
                initialSupplierName: 'Corralón Norte SA',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fijar margen sugerido 50%
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_default_margin_field')),
        '50',
      );
      await tester.pumpAndSettle();

      // Fila 0
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_sku_0')),
        'SKU-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_name_0')),
        'Pinza Universal',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_spec_0')),
        '8"',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_cost_0')),
        '2000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_stock_0')),
        '10',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_location_0')),
        'Estante A1',
      );
      await tester.pumpAndSettle();

      // Fila 1 con unidad metros (mt)
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_sku_1')),
        'SKU-02',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_name_1')),
        'Soga Trenzada',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('quick_grid_unit_1')),
      );
      await tester.tap(find.byKey(const ValueKey('quick_grid_unit_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('mt').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_cost_1')),
        '100',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_stock_1')),
        '50',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('quick_grid_submit_btn')),
      );
      await tester.tap(find.byKey(const ValueKey('quick_grid_submit_btn')));
      await tester.pumpAndSettle();

      expect(repo.createdPayloads.length, 2);

      final first = repo.createdPayloads[0];
      expect(first['supplier_sku'], 'SKU-01');
      expect(first['name'], 'Pinza Universal');
      expect(first['technical_spec'], '8"');
      expect(first['storage_location'], 'Estante A1');
      expect(first['cost_price'], 2000.0);
      expect(first['selling_price'], 3000.0);
      expect(first['stock'], 10.0);
      expect(first['supplier_id'], 7);
      expect(first['unit_type'], 'un');
      expect(first['is_sold_by_weight'], isFalse);

      final second = repo.createdPayloads[1];
      expect(second['supplier_sku'], 'SKU-02');
      expect(second['name'], 'Soga Trenzada');
      expect(second['cost_price'], 100.0);
      expect(second['selling_price'], 150.0);
      expect(second['stock'], 50.0);
      expect(second['unit_type'], 'mt');
      expect(second['is_sold_by_weight'], isTrue);
    });

    testWidgets(
        'SupplierQuickGridDialog rechaza en cliente PVP < Costo sin enviar lotes parciales',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _Phase2CatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _FakeLocalTerminalProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SupplierQuickGridDialog(
                provider: catalogProv,
                initialSupplierId: 7,
                initialSupplierName: 'Corralón Norte SA',
                alreadyAuthorized: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Se muestra aviso de alta de catálogo sin comprobante/deuda
      expect(
        find.textContaining('no registra factura ni deuda en Cuenta Corriente'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_name_0')),
        'Martillo Galponero',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_cost_0')),
        '5000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_price_0')),
        '3500',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('quick_grid_submit_btn')),
      );
      await tester.tap(find.byKey(const ValueKey('quick_grid_submit_btn')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('El PVP no puede ser menor al costo'), findsOneWidget);
      expect(repo.createdPayloads, isEmpty);
    });

    testWidgets(
        'ProductFormDialog con lockInitialStockToZero fija stock en 0 y evita doble contabilización en facturas',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _Phase2CatalogRepository();
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _FakeLocalTerminalProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ProductFormDialog(
                provider: catalogProv,
                initialSupplierId: 7,
                initialSupplierName: 'Corralón Norte SA',
                initialName: 'Enduido 4L',
                lockInitialStockToZero: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Stock inicial (0 por comprobante)'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Precio Venta *'),
        '12500',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crear Producto'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(repo.createdPayloads.length, 1);
      expect(repo.createdPayloads.first['stock'], 0.0);
      expect(repo.createdPayloads.first['supplier_id'], 7);
    });

    test(
        'CatalogProvider activa fallback local v1.8.5 si llegan otros proveedores y loadProductsWithoutSupplierFilter limpia filtro',
        () async {
      final repo = _Phase2CatalogRepository();
      final supA = Supplier(
        id: 7,
        name: 'Corralón Norte SA',
        balance: 0,
        isActive: true,
      );
      final supB = Supplier(
        id: 9,
        name: 'Otro Proveedor',
        balance: 0,
        isActive: true,
      );
      repo.stubProducts = [
        ProductModel(
          id: 1,
          name: 'Cemento Loma Negra',
          internalCode: '00001',
          costPrice: 5000,
          sellingPrice: 7000,
          stock: 10,
          isSoldByWeight: false,
          active: true,
          supplier: supA,
        ),
        ProductModel(
          id: 2,
          name: 'Pintura Látex',
          internalCode: '00002',
          costPrice: 8000,
          sellingPrice: 11000,
          stock: 5,
          isSoldByWeight: false,
          active: true,
          supplier: supB,
        ),
      ];

      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await catalogProv.setSupplierFilter(
        7,
        supplierName: 'Corralón Norte SA',
      );

      expect(catalogProv.supplierFilterFallbackActive, isTrue);
      expect(catalogProv.products.length, 1);
      expect(catalogProv.products.first.id, 1);

      await catalogProv.loadProductsWithoutSupplierFilter();
      expect(catalogProv.filterSupplierId, isNull);
      expect(catalogProv.supplierFilterFallbackActive, isFalse);
      expect(catalogProv.products.length, 2);
    });

    testWidgets(
        'SupplierQuickGridDialog envía authorizedAdminPin vía ApiClient.withAdminPin cuando alreadyAuthorized es true',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final spyApiClient = _SpyPinApiClient();
      final List<String?> pinStatesDuringCreate = [];
      final repo = _Phase2CatalogRepository()
        ..onBeforeCreateProduct = () {
          pinStatesDuringCreate.add(spyApiClient.activePinDuringCall);
        };
      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: spyApiClient),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _FakeSettingsProvider(),
            ),
            ChangeNotifierProvider<SupplierProvider>.value(
              value: _FakeSupplierProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(),
            ),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _FakeInventoryAlertsProvider(),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _FakeLocalTerminalProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SupplierQuickGridDialog(
                provider: catalogProv,
                initialSupplierId: 7,
                initialSupplierName: 'Corralón Norte SA',
                alreadyAuthorized: true,
                authorizedAdminPin: '4321',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_name_0')),
        'Caño PVC 110mm',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick_grid_price_0')),
        '8500',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('quick_grid_submit_btn')),
      );
      await tester.tap(find.byKey(const ValueKey('quick_grid_submit_btn')));
      await tester.pumpAndSettle();

      expect(repo.createdPayloads.length, 1);
      expect(spyApiClient.capturedPins, ['4321']);
      expect(pinStatesDuringCreate, ['4321']);
      expect(spyApiClient.activePinDuringCall, isNull);
    });

    test(
        'Product resuelve sufijos reales de unidad para ferretería y balanza retail',
        () {
      final cable = Product(
        id: 1,
        name: 'Cable 2.5mm',
        internalCode: '00001',
        costPrice: 500,
        sellingPrice: 900,
        stock: 100,
        active: true,
        isSoldByWeight: true,
        unitType: 'mt',
      );
      final machimbre = Product(
        id: 2,
        name: 'Machimbre Pino',
        internalCode: '00002',
        costPrice: 3000,
        sellingPrice: 5000,
        stock: 40,
        active: true,
        isSoldByWeight: true,
        unitType: 'm2',
      );
      final retailKg = Product(
        id: 3,
        name: 'Queso Cremoso',
        internalCode: '00003',
        costPrice: 4000,
        sellingPrice: 6500,
        stock: 12,
        active: true,
        isSoldByWeight: true,
        unitType: 'un',
      );

      expect(cable.effectiveQuantityUnitLabel, 'mt');
      expect(cable.effectiveReceiptUnitSuffix, 'mt');
      expect(cable.effectiveAsciiReceiptUnitSuffix, 'mt');

      expect(machimbre.effectiveQuantityUnitLabel, 'm²');
      expect(machimbre.effectiveReceiptUnitSuffix, 'm²');
      expect(machimbre.effectiveAsciiReceiptUnitSuffix, 'm2');

      expect(retailKg.effectiveQuantityUnitLabel, 'Kg');
      expect(retailKg.effectiveReceiptUnitSuffix, 'kg');
      expect(retailKg.effectiveAsciiReceiptUnitSuffix, 'kg');
    });

    testWidgets(
        'ThermalReceiptWidget muestra mt/m² para productos fraccionables ferreteros y kg para balanza retail',
        (tester) async {
      final items = [
        CartItem(
          product: Product(
            id: 10,
            name: 'Cable Subterraneo',
            internalCode: 'CAB01',
            costPrice: 1000,
            sellingPrice: 1500,
            stock: 100,
            active: true,
            isSoldByWeight: true,
            unitType: 'mt',
          ),
          quantity: 2.5,
        ),
        CartItem(
          product: Product(
            id: 11,
            name: 'Clavos Sueltos',
            internalCode: 'CLA01',
            costPrice: 800,
            sellingPrice: 1200,
            stock: 50,
            active: true,
            isSoldByWeight: true,
            unitType: 'un',
          ),
          quantity: 1.5,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ThermalReceiptWidget(
                paperWidth: ThermalPaperWidth.mm80,
                businessSettings: BusinessSettings(
                  companyName: 'Ferretería Test',
                  taxId: '30-11111111-1',
                ),
                items: items,
                payments: const [
                  {'name': 'EFECTIVO', 'amount': 5550.0},
                ],
                total: 5550.0,
                saleNumber: '00001',
                cashierName: 'Caja 1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('2.5 mt x'), findsOneWidget);
      expect(find.textContaining('1.5 kg x'), findsOneWidget);
    });
  });
}
