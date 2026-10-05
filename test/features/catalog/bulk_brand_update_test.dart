import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:frontend_desktop/features/catalog/data/repositories/catalog_repository_impl.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';

// --- MOCK REPOSITORY & PROVIDERS ---

class FakeCatalogRepository implements CatalogRepository {
  List<int>? lastIds;
  int? lastCategoryId;
  bool? lastClearCategory;
  int? lastBrandId;
  bool? lastClearBrand;
  bool? lastActive;
  int? lastSupplierId;
  bool? lastClearSupplier;
  bool shouldFail = false;

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
    if (shouldFail) {
      throw Exception('Database update error');
    }
    lastIds = ids;
    lastCategoryId = categoryId;
    lastClearCategory = clearCategory;
    lastBrandId = brandId;
    lastClearBrand = clearBrand;
    lastActive = active;
    lastSupplierId = supplierId;
    lastClearSupplier = clearSupplier;

    return {
      'message': 'Se actualizaron exitosamente ${ids.length} productos.',
      'updated_count': ids.length,
      'affected_ids': ids,
    };
  }

  @override
  Future<List<Brand>> getBrands() async => [
        Brand(id: 1, name: 'Arcor'),
        Brand(id: 2, name: 'Coca-Cola'),
      ];

  @override
  Future<List<Category>> getCategories() async => [
        Category(id: 1, name: 'Bebidas'),
        Category(id: 2, name: 'Golosinas'),
      ];

  @override
  Future<Map<String, dynamic>> getProducts({int page = 1, String? search, String? sortBy, String? sortDirection, int? perPage}) async => {
        'data': <Product>[],
        'current_page': 1,
        'last_page': 1,
        'total': 0,
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings? get settings => const BusinessSettings(
        licensePlanType: 'premium',
        features: FeatureFlags(suppliers: true, multiRubro: true),
      );
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => 'premium';
  @override
  FeatureFlags get features => const FeatureFlags(suppliers: true, multiRubro: true);
  @override
  bool hasFeature(String featureName) => true;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [];
  @override
  bool get isLoading => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  group('CatalogRemoteDataSourceImpl Bulk Update Tests', () {
    test('bulkUpdateProducts sends POST to /catalog/bulk-update with brand_id', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'message': 'Se actualizaron exitosamente 2 productos.',
            'updated_count': 2,
            'affected_ids': [1, 2],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = CatalogRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: mockClient,
      );

      final result = await dataSource.bulkUpdateProducts(
        [1, 2],
        brandId: 10,
      );

      expect(result['updated_count'], 2);
      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.url.path, '/api/catalog/bulk-update');
      expect(capturedRequest.headers['content-type'], 'application/json');

      final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(payload['product_ids'], [1, 2]);
      expect(payload['brand_id'], 10);
      expect(payload.containsKey('category_id'), isFalse);
    });

    test('bulkUpdateProducts sends brand_id: null when clearBrand is true', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'message': 'Se actualizaron exitosamente 1 productos.',
            'updated_count': 1,
            'affected_ids': [5],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = CatalogRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: mockClient,
      );

      final result = await dataSource.bulkUpdateProducts(
        [5],
        clearBrand: true,
      );

      expect(result['updated_count'], 1);
      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.url.path, '/api/catalog/bulk-update');

      final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(payload['product_ids'], [5]);
      expect(payload.containsKey('brand_id'), isTrue);
      expect(payload['brand_id'], isNull);
    });

    test('bulkUpdateProducts sends category_id: null when clearCategory is true', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'message': 'Se actualizaron exitosamente 1 productos.',
            'updated_count': 1,
            'affected_ids': [5],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = CatalogRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: mockClient,
      );

      final result = await dataSource.bulkUpdateProducts(
        [5],
        clearCategory: true,
      );

      expect(result['updated_count'], 1);
      final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(payload.containsKey('category_id'), isTrue);
      expect(payload['category_id'], isNull);
    });

    test('bulkUpdateProducts throws Exception on HTTP 400 or 500 error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Uno o más productos no existen.'}),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = CatalogRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: mockClient,
      );

      expect(
        () => dataSource.bulkUpdateProducts([999], brandId: 1),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CatalogRepositoryImpl Bulk Update Propagation Tests', () {
    test('CatalogRepositoryImpl forwards brandId and clearBrand to RemoteDataSource', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'message': 'OK', 'updated_count': 3, 'affected_ids': [1, 2, 3]}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = CatalogRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repository = CatalogRepositoryImpl(remoteDataSource: dataSource);

      final response = await repository.bulkUpdateProducts(
        [1, 2, 3],
        brandId: 4,
        clearBrand: false,
      );

      expect(response['updated_count'], 3);
      final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(payload['brand_id'], 4);
    });
  });

  group('CatalogProvider Bulk Update Brand Tests', () {
    test('bulkUpdateProducts propagates brandId to repository and reloads products', () async {
      final fakeRepo = FakeCatalogRepository();
      final getProductsUseCase = GetProductsUseCase(fakeRepo);
      final provider = CatalogProvider(
        getProductsUseCase: getProductsUseCase,
        repository: fakeRepo,
      );

      final msg = await provider.bulkUpdateProducts(
        [10, 20],
        brandId: 2,
        clearBrand: false,
      );

      expect(msg, contains('Se actualizaron exitosamente 2 productos.'));
      expect(fakeRepo.lastIds, [10, 20]);
      expect(fakeRepo.lastBrandId, 2);
      expect(fakeRepo.lastClearBrand, false);
      expect(provider.isLoading, false);
      expect(provider.errorMessage, isNull);
    });

    test('bulkUpdateProducts propagates clearBrand to repository', () async {
      final fakeRepo = FakeCatalogRepository();
      final getProductsUseCase = GetProductsUseCase(fakeRepo);
      final provider = CatalogProvider(
        getProductsUseCase: getProductsUseCase,
        repository: fakeRepo,
      );

      final msg = await provider.bulkUpdateProducts(
        [10],
        brandId: null,
        clearBrand: true,
      );

      expect(msg, contains('Se actualizaron exitosamente 1 productos.'));
      expect(fakeRepo.lastBrandId, isNull);
      expect(fakeRepo.lastClearBrand, true);
    });

    test('bulkUpdateProducts captures error message when repository throws', () async {
      final fakeRepo = FakeCatalogRepository()..shouldFail = true;
      final getProductsUseCase = GetProductsUseCase(fakeRepo);
      final provider = CatalogProvider(
        getProductsUseCase: getProductsUseCase,
        repository: fakeRepo,
      );

      final msg = await provider.bulkUpdateProducts([1], brandId: 1);
      expect(msg, isNull);
      expect(provider.errorMessage, contains('Database update error'));
      expect(provider.isLoading, false);
    });
  });

  group('CatalogScreen Batch Menu UI Tests', () {
    final sampleProducts = [
      Product(
        id: 101,
        name: 'Gaseosa Cola 2L',
        barcode: '7791234567890',
        internalCode: 'GAS-001',
        costPrice: 500,
        sellingPrice: 1000,
        stock: 50,
        active: true,
        isSoldByWeight: false,
      ),
      Product(
        id: 102,
        name: 'Alfajor Triple',
        barcode: '7791234567891',
        internalCode: 'ALF-002',
        costPrice: 200,
        sellingPrice: 400,
        stock: 30,
        active: true,
        isSoldByWeight: false,
      ),
    ];

    Widget buildTestScreen({required CatalogProvider catalogProvider}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
          ChangeNotifierProvider<SettingsProvider>.value(value: FakeSettingsProvider()),
          ChangeNotifierProvider<SupplierProvider>.value(value: FakeSupplierProvider()),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CatalogScreen(),
          ),
        ),
      );
    }

    testWidgets('Selecting a product displays Lote dropdown with Asignar Marca option', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeCatalogRepository();
      final getProductsUseCase = GetProductsUseCase(fakeRepo);
      final provider = CatalogProvider(
        getProductsUseCase: getProductsUseCase,
        repository: fakeRepo,
      );

      // Seed provider with products
      await tester.pumpWidget(buildTestScreen(catalogProvider: provider));
      await tester.pump();

      // Initially no batch button is shown
      expect(find.textContaining('Lote ('), findsNothing);

      // Now set products in provider
      provider.products.addAll(sampleProducts);
      provider.notifyListeners();
      await tester.pump();

      // Find row checkbox and tap it to select product
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsWidgets);

      // Tap the second checkbox (first row item)
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      // Verify the Lote badge button appeared
      expect(find.text('Lote (1)'), findsOneWidget);

      // Tap the Lote popup menu button
      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      // Verify bulk menu items are present
      expect(find.text('Asignar Marca'), findsOneWidget);
      expect(find.byIcon(Icons.branding_watermark_outlined), findsAtLeastNWidgets(1));
      expect(find.text('Asignar Categoría'), findsOneWidget);
      expect(find.text('Asignar Proveedor'), findsOneWidget);
      expect(find.text('Generar Presupuesto'), findsOneWidget);
      // R1: Standalone Quitar options are cleaned up from main menu
      expect(find.text('Quitar Categoría'), findsNothing);
      expect(find.text('Quitar Marca'), findsNothing);
      expect(find.text('Quitar Proveedor'), findsNothing);
    });

    testWidgets('R2: Asignar Marca dialog has — Quitar Marca — option that unsets brand via bulk update', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeCatalogRepository();
      final getProductsUseCase = GetProductsUseCase(fakeRepo);
      final provider = CatalogProvider(
        getProductsUseCase: getProductsUseCase,
        repository: fakeRepo,
      );

      await tester.pumpWidget(buildTestScreen(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll(sampleProducts);
      provider.notifyListeners();
      await tester.pump();

      // Select first product
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      // Open Lote menu
      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      // Tap Asignar Marca
      await tester.tap(find.text('Asignar Marca'));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Asignar Marca en Lote'), findsOneWidget);

      // Open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      // Verify — Quitar Marca — is the first option
      expect(find.text('— Quitar Marca —'), findsWidgets);

      // Select — Quitar Marca —
      await tester.tap(find.text('— Quitar Marca —').last);
      await tester.pumpAndSettle();

      // Tap Asignar button
      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      // Verify repository was called with brandId: null and clearBrand: true
      expect(fakeRepo.lastClearBrand, isTrue);
      expect(fakeRepo.lastBrandId, isNull);
      expect(fakeRepo.lastIds, [101]);
    });

    testWidgets('Tapping "Generar Presupuesto" clears bulk selection and processes quote items', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeCatalogRepository();
      final getProductsUseCase = GetProductsUseCase(fakeRepo);
      final provider = CatalogProvider(
        getProductsUseCase: getProductsUseCase,
        repository: fakeRepo,
      );
      await tester.pumpWidget(buildTestScreen(catalogProvider: provider));
      await tester.pumpAndSettle();

      provider.products.addAll(sampleProducts);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      expect(find.text('Lote (1)'), findsOneWidget);

      await tester.tap(find.text('Lote (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Generar Presupuesto'), findsOneWidget);
      await tester.tap(find.text('Generar Presupuesto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Selection is cleared
      expect(find.text('Lote (1)'), findsNothing);
    });
  });
}
