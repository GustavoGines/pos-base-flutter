import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
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

// ─────────────────────────────────────────────────────────────────────────────
// TEST HELPERS & FACTORIES
// ─────────────────────────────────────────────────────────────────────────────

Product createTestProduct({
  required int id,
  required String name,
  String internalCode = '00001',
  double costPrice = 10,
  double sellingPrice = 20,
  double stock = 5,
  bool active = true,
  bool isSoldByWeight = false,
  String? imageUrl,
  Category? category,
  Brand? brand,
  Supplier? supplier,
}) {
  return Product(
    id: id,
    name: name,
    internalCode: internalCode,
    costPrice: costPrice,
    sellingPrice: sellingPrice,
    stock: stock,
    active: active,
    isSoldByWeight: isSoldByWeight,
    imageUrl: imageUrl,
    category: category,
    brand: brand,
    supplier: supplier,
  );
}

Supplier createTestSupplier({
  required int id,
  required String name,
  double balance = 0.0,
  bool isActive = true,
}) {
  return Supplier(
    id: id,
    name: name,
    balance: balance,
    isActive: isActive,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TEST DOUBLES & MOCKS
// ─────────────────────────────────────────────────────────────────────────────

class MockCatalogRepository implements CatalogRepository {
  List<int>? lastIds;
  int? lastCategoryId;
  bool? lastClearCategory;
  int? lastBrandId;
  bool? lastClearBrand;
  int? lastSupplierId;
  bool? lastClearSupplier;
  bool? lastActive;

  final List<Category> mockCategories = [
    Category(id: 1, name: 'Bebidas'),
    Category(id: 2, name: 'Golosinas'),
    Category(id: 3, name: 'Limpieza'),
  ];

  final List<Brand> mockBrands = [
    Brand(id: 10, name: 'Coca-Cola'),
    Brand(id: 20, name: 'Arcor'),
    Brand(id: 30, name: 'Unilever'),
  ];

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
    lastIds = ids;
    lastCategoryId = categoryId;
    lastClearCategory = clearCategory;
    lastBrandId = brandId;
    lastClearBrand = clearBrand;
    lastSupplierId = supplierId;
    lastClearSupplier = clearSupplier;
    lastActive = active;

    return {
      'message': 'Se actualizaron exitosamente ${ids.length} productos.',
      'updated_count': ids.length,
      'affected_ids': ids,
    };
  }

  @override
  Future<List<Brand>> getBrands() async => mockBrands;

  @override
  Future<List<Category>> getCategories() async => mockCategories;

  @override
  Future<List<Rubro>> getRubros() async => [];

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

class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings? get settings => const BusinessSettings(
        licensePlanType: 'premium',
        features: FeatureFlags(quotes: true, suppliers: true, multiRubro: true),
      );
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => 'premium';
  @override
  FeatureFlags get features => const FeatureFlags(quotes: true, suppliers: true, multiRubro: true);
  @override
  bool hasFeature(String featureName) => true;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSupplierProvider extends ChangeNotifier implements SupplierProvider {
  List<Supplier> _suppliers = [
    Supplier(id: 100, name: 'Distribuidora Quilmes', balance: 0.0, isActive: true),
    Supplier(id: 200, name: 'Mayorista Vital', balance: 0.0, isActive: true),
  ];

  @override
  List<Supplier> get suppliers => _suppliers;
  set suppliers(List<Supplier> val) {
    _suppliers = val;
    notifyListeners();
  }

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
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

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  Widget buildCatalogApp({
    required CatalogProvider catalogProvider,
    SupplierProvider? supplierProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: MockSettingsProvider()),
        ChangeNotifierProvider<SupplierProvider>.value(value: supplierProvider ?? MockSupplierProvider()),
        ChangeNotifierProvider<LocalTerminalProvider>.value(value: MockLocalTerminalProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: MockAuthProvider()),
        ChangeNotifierProvider<InventoryAlertsProvider>.value(value: MockInventoryAlertsProvider()),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: CatalogScreen(),
        ),
      ),
    );
  }

  Widget buildProductFormApp({
    Product? product,
    required CatalogProvider catalogProvider,
    SupplierProvider? supplierProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: MockSettingsProvider()),
        ChangeNotifierProvider<SupplierProvider>.value(value: supplierProvider ?? MockSupplierProvider()),
        ChangeNotifierProvider<LocalTerminalProvider>.value(value: MockLocalTerminalProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: MockAuthProvider()),
        ChangeNotifierProvider<InventoryAlertsProvider>.value(value: MockInventoryAlertsProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showDialog(
                  context: ctx,
                  builder: (_) => ProductFormDialog(
                    provider: catalogProvider,
                    product: product,
                  ),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );
  }

  group('R4: Product Form "Quitar Foto" Circular Badge', () {
    testWidgets('Renders circular red badge at top-right with tooltip "Quitar foto" on product with image', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      final product = createTestProduct(
        id: 99,
        name: 'Galletitas Chocolinas',
        internalCode: '00099',
        imageUrl: 'http://example.com/chocolinas.png',
      );

      await tester.pumpWidget(buildProductFormApp(product: product, catalogProvider: provider));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify the badge exists with tooltip 'Quitar foto'
      final badgeFinder = find.byTooltip('Quitar foto');
      expect(badgeFinder, findsOneWidget);

      // Verify it is an IconButton with red background and white close icon
      final iconBtnFinder = find.widgetWithIcon(IconButton, Icons.close);
      expect(iconBtnFinder, findsOneWidget);
      final iconBtn = tester.widget<IconButton>(iconBtnFinder);
      expect(iconBtn.tooltip, 'Quitar foto');
      final bg = iconBtn.style?.backgroundColor?.resolve({});
      expect(bg, Colors.red.shade600);

      final icon = iconBtn.icon as Icon;
      expect(icon.icon, Icons.close);
      expect(icon.color, Colors.white);
    });

    testWidgets('Tapping the circular badge clears the image and removes the badge from the form', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      final product = createTestProduct(
        id: 99,
        name: 'Galletitas Chocolinas',
        internalCode: '00099',
        imageUrl: 'http://example.com/chocolinas.png',
      );

      await tester.pumpWidget(buildProductFormApp(product: product, catalogProvider: provider));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Quitar foto'), findsOneWidget);

      // Tap the badge
      await tester.tap(find.byTooltip('Quitar foto'));
      await tester.pumpAndSettle();

      // Badge must now be gone, and "Subir Foto" placeholder is visible
      expect(find.byTooltip('Quitar foto'), findsNothing);
      expect(find.text('Subir Foto'), findsOneWidget);
    });

    testWidgets('Badge is NOT rendered when product has no image', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      final product = createTestProduct(
        id: 100,
        name: 'Sin Foto Producto',
        internalCode: '00100',
        imageUrl: null,
      );

      await tester.pumpWidget(buildProductFormApp(product: product, catalogProvider: provider));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Quitar foto'), findsNothing);
      expect(find.text('Subir Foto'), findsOneWidget);
    });

    testWidgets('Responsive: ProductFormDialog renders without RenderFlex overflow at 320x480', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      final product = createTestProduct(
        id: 99,
        name: 'Producto Móvil Angosto',
        internalCode: '00099',
        imageUrl: 'http://example.com/mobile.png',
      );

      await tester.pumpWidget(buildProductFormApp(product: product, catalogProvider: provider));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Quitar foto'), findsOneWidget);

      // Tap badge to ensure tap interaction works at 320x480
      await tester.tap(find.byTooltip('Quitar foto'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Quitar foto'), findsNothing);
    });
  });

  group('R4: Bulk Category Dialog Defaults', () {
    testWidgets('Preselects "— Quitar Categoría —" (-1) when selected products have NO category', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      await provider.loadMetadata();

      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', category: null);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', category: null);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      // Select both products
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      // Open Lote menu
      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      // Open Asignar Categoría dialog
      await tester.tap(find.text('Asignar Categoría'));
      await tester.pumpAndSettle();

      // Verify the dropdown has "— Quitar Categoría —" preselected
      expect(find.text('— Quitar Categoría —'), findsOneWidget);

      // Immediately tap Asignar without changing dropdown
      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      // Repository should have been called with clearCategory: true and categoryId: null
      expect(repo.lastClearCategory, isTrue);
      expect(repo.lastCategoryId, isNull);
      expect(repo.lastIds, [1, 2]);
    });

    testWidgets('Preselects "— Quitar Categoría —" (-1) when selected products have MIXED categories', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      await provider.loadMetadata();

      final cat1 = Category(id: 1, name: 'Bebidas');
      final cat2 = Category(id: 2, name: 'Golosinas');
      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', category: cat1);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', category: cat2);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Categoría'));
      await tester.pumpAndSettle();

      // With mixed categories, defaults to -1 ("— Quitar Categoría —")
      expect(find.text('— Quitar Categoría —'), findsOneWidget);
    });

    testWidgets('Preselects shared category ID when all selected products share the SAME category', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      await provider.loadMetadata();

      final sharedCat = Category(id: 1, name: 'Bebidas');
      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', category: sharedCat);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', category: sharedCat);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Categoría'));
      await tester.pumpAndSettle();

      // Preselects 'Bebidas'
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Bebidas')), findsOneWidget);

      // Tap Asignar
      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      expect(repo.lastCategoryId, 1);
      expect(repo.lastClearCategory, isFalse);
      expect(repo.lastIds, [1, 2]);
    });

    testWidgets('Gracefully falls back to -1 when shared category ID does NOT exist in provider categories', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      await provider.loadMetadata();

      // Category 999 does not exist in repo.mockCategories
      final orphanCat = Category(id: 999, name: 'Categoría Fantasma');
      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', category: orphanCat);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', category: orphanCat);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Categoría'));
      await tester.pumpAndSettle();

      // No crash / assertion error, falls back safely to -1
      expect(tester.takeException(), isNull);
      expect(find.text('— Quitar Categoría —'), findsOneWidget);
    });
  });

  group('R4: Bulk Brand Dialog Defaults', () {
    testWidgets('Preselects "— Quitar Marca —" (-1) when selected products have NO brand', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      await provider.loadBrands();

      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', brand: null);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', brand: null);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Marca'));
      await tester.pumpAndSettle();

      expect(find.text('— Quitar Marca —'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      expect(repo.lastClearBrand, isTrue);
      expect(repo.lastBrandId, isNull);
      expect(repo.lastIds, [1, 2]);
    });

    testWidgets('Preselects "— Quitar Marca —" (-1) when selected products have MIXED brands', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      await provider.loadBrands();

      final b1 = Brand(id: 10, name: 'Coca-Cola');
      final b2 = Brand(id: 20, name: 'Arcor');
      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', brand: b1);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', brand: b2);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Marca'));
      await tester.pumpAndSettle();

      expect(find.text('— Quitar Marca —'), findsOneWidget);
    });

    testWidgets('Preselects shared brand ID when all selected products share the SAME brand', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      await provider.loadBrands();

      final sharedBrand = Brand(id: 10, name: 'Coca-Cola');
      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', brand: sharedBrand);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', brand: sharedBrand);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Marca'));
      await tester.pumpAndSettle();

      // Preselects 'Coca-Cola'
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Coca-Cola')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      expect(repo.lastBrandId, 10);
      expect(repo.lastClearBrand, isFalse);
      expect(repo.lastIds, [1, 2]);
    });

    testWidgets('Gracefully falls back to -1 when shared brand ID does NOT exist in provider brands', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      await provider.loadBrands();

      final orphanBrand = Brand(id: 999, name: 'Marca Fantasma');
      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', brand: orphanBrand);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', brand: orphanBrand);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Marca'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('— Quitar Marca —'), findsOneWidget);
    });
  });

  group('R4: Bulk Supplier Dialog Defaults', () {
    testWidgets('Preselects "— Quitar Proveedor —" (-1) when selected products have NO supplier', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', supplier: null);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', supplier: null);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Proveedor'));
      await tester.pumpAndSettle();

      expect(find.text('— Quitar Proveedor —'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      expect(repo.lastClearSupplier, isTrue);
      expect(repo.lastSupplierId, isNull);
      expect(repo.lastIds, [1, 2]);
    });

    testWidgets('Preselects "— Quitar Proveedor —" (-1) when selected products have MIXED suppliers', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      final s1 = createTestSupplier(id: 100, name: 'Distribuidora Quilmes');
      final s2 = createTestSupplier(id: 200, name: 'Mayorista Vital');
      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', supplier: s1);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', supplier: s2);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Proveedor'));
      await tester.pumpAndSettle();

      expect(find.text('— Quitar Proveedor —'), findsOneWidget);
    });

    testWidgets('Preselects shared supplier ID when all selected products share the SAME supplier', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      final sharedSupplier = createTestSupplier(id: 100, name: 'Distribuidora Quilmes');
      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', supplier: sharedSupplier);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', supplier: sharedSupplier);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Proveedor'));
      await tester.pumpAndSettle();

      // Preselects 'Distribuidora Quilmes'
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Distribuidora Quilmes')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      expect(repo.lastSupplierId, 100);
      expect(repo.lastClearSupplier, isFalse);
      expect(repo.lastIds, [1, 2]);
    });

    testWidgets('Gracefully falls back to -1 when shared supplier ID does NOT exist in suppliers list', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      final orphanSup = createTestSupplier(id: 999, name: 'Proveedor Fantasma');
      final p1 = createTestProduct(id: 1, name: 'Item 1', internalCode: '00001', supplier: orphanSup);
      final p2 = createTestProduct(id: 2, name: 'Item 2', internalCode: '00002', supplier: orphanSup);
      await tester.pumpWidget(buildCatalogApp(catalogProvider: provider));
      await tester.pump();

      provider.products.addAll([p1, p2]);
      provider.notifyListeners();
      await tester.pump();

      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lote (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar Proveedor'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('— Quitar Proveedor —'), findsOneWidget);
    });
  });
}
