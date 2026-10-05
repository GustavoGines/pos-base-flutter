import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/mobile/presentation/screens/mobile_audit_screen.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';

class MockFilePicker extends FilePicker {
  static final Uint8List kTransparent1x1Png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult([
      PlatformFile(
        name: 'alfajor_mock.png',
        size: kTransparent1x1Png.length,
        bytes: kTransparent1x1Png,
        path: '/mock/images/alfajor_mock.png',
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCatalogRepo implements CatalogRepository {
  List<Product> products = [];
  Map<String, dynamic>? lastCreatedPayload;
  int? lastUploadedProductId;
  String? lastUploadedPath;
  List<int>? lastUploadedBytes;
  String? lastUploadedFilename;

  @override
  Future<Product> createProduct(Map<String, dynamic> data) async {
    lastCreatedPayload = data;
    final p = Product(
      id: 999,
      name: data['name'] ?? '',
      barcode: data['barcode'],
      internalCode: data['internal_code'] ?? '00999',
      costPrice: (data['cost_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (data['selling_price'] as num?)?.toDouble() ?? 0.0,
      stock: (data['stock'] as num?)?.toDouble() ?? 0.0,
      active: true,
      isSoldByWeight: data['is_sold_by_weight'] ?? false,
    );
    products.insert(0, p);
    return p;
  }

  @override
  Future<Product> updateProduct(int id, Map<String, dynamic> data) async {
    final idx = products.indexWhere((p) => p.id == id);
    if (idx != -1) {
      final updated = products[idx].copyWith(
        name: data['name'] as String?,
        costPrice: (data['cost_price'] as num?)?.toDouble(),
        sellingPrice: (data['selling_price'] as num?)?.toDouble(),
        stock: (data['stock'] as num?)?.toDouble(),
      );
      products[idx] = updated;
      return updated;
    }
    return Product(
      id: id,
      name: data['name'] ?? '',
      internalCode: '00001',
      costPrice: 0,
      sellingPrice: 0,
      stock: 0,
      active: true,
      isSoldByWeight: false,
    );
  }

  @override
  Future<String> uploadProductImage(int productId, String filePath, {List<int>? bytes, String? filename}) async {
    lastUploadedProductId = productId;
    lastUploadedPath = filePath;
    lastUploadedBytes = bytes;
    lastUploadedFilename = filename;
    return 'http://example.com/storage/products/$productId.jpg';
  }

  @override
  Future<Map<String, dynamic>> getProducts({int page = 1, String? search, String? sortBy, String? sortDirection, int? perPage}) async => {
    'data': products,
    'current_page': 1,
    'last_page': 1,
    'total': products.length,
  };

  @override
  Future<List<Category>> getCategories() async => [Category(id: 1, name: 'Bebidas')];

  @override
  Future<List<Brand>> getBrands() async => [Brand(id: 1, name: 'Coca-Cola')];

  @override
  Future<List<Rubro>> getRubros() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  FeatureFlags get features => const FeatureFlags(suppliers: true, multiRubro: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [Supplier(id: 1, name: 'Distribuidora Central', balance: 0.0, isActive: true)];
  @override
  Future<void> fetchSuppliers({String? search}) async {}
  @override
  bool get isLoading => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPosProvider extends ChangeNotifier implements PosProvider {
  List<Product> mockProducts = [];
  @override
  Future<List<Product>> search(String query) async {
    return mockProducts.where((p) => (p.barcode?.contains(query) ?? false) || p.internalCode.contains(query) || p.name.toLowerCase().contains(query.toLowerCase())).toList();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  bool hasPermission(String permission) => true;
  @override
  bool get isAdmin => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  Widget buildMobileApp({required CatalogProvider catalogProvider, PosProvider? posProvider}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: MockSettingsProvider()),
        ChangeNotifierProvider<SupplierProvider>.value(value: MockSupplierProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: MockAuthProvider()),
        ChangeNotifierProvider<PosProvider>.value(value: posProvider ?? MockPosProvider()),
      ],
      child: const MaterialApp(
        home: MobileAuditScreen(),
      ),
    );
  }

  group('POS Mobile Product Form Image Upload (R3)', () {
    testWidgets('Opening new product form displays image picker section with selection button', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepo();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider));
      await tester.pump();

      // Tap floating action button to create new product
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify dialog opened
      expect(find.text('Nuevo Producto'), findsOneWidget);

      // Verify Image Picker section is present (R3)
      expect(find.text('Foto del Producto'), findsOneWidget);
      expect(find.byKey(const Key('mobile_product_image_picker')), findsOneWidget);
      expect(find.byKey(const Key('mobile_pick_image_button')), findsOneWidget);
      expect(find.text('Seleccionar Foto'), findsOneWidget);
      expect(find.text('Cámara o galería'), findsOneWidget);
      expect(find.text('Subir Foto'), findsOneWidget);
    });

    testWidgets('Submitting new product successfully creates product and closes form', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepo();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider));
      await tester.pump();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Enter name and price
      await tester.enterText(find.widgetWithText(TextField, 'Nombre del producto'), 'Alfajor Glaseado');
      await tester.enterText(find.widgetWithText(TextField, 'Venta (\$)'), '500');
      await tester.pump();

      // Tap Guardar
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog should close
      expect(find.text('Nuevo Producto'), findsNothing);
      expect(repo.lastCreatedPayload?['name'], 'Alfajor Glaseado');
    });

    testWidgets('Scanned product card with image URL renders image thumbnail', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final sampleProduct = Product(
        id: 42,
        name: 'Yerba Mate Playadito 1kg',
        barcode: '7791234567890',
        internalCode: 'YER-001',
        costPrice: 1500,
        sellingPrice: 2800,
        stock: 20,
        imageUrl: 'http://example.com/playadito.jpg',
        active: true,
        isSoldByWeight: false,
      );

      final repo = MockCatalogRepo()..products = [sampleProduct];
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      final posProvider = MockPosProvider()..mockProducts = [sampleProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider, posProvider: posProvider));
      await tester.pump();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '7791234567890');
      await tester.pump();
      final searchButton = find.widgetWithIcon(IconButton, Icons.search);
      await tester.tap(searchButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify image thumbnail is rendered
      expect(find.byType(ClipRRect), findsOneWidget);

      // Verify edit button is available
      expect(find.byTooltip('Editar detalles'), findsOneWidget);
      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify edit dialog opened
      expect(find.text('Editar Producto'), findsOneWidget);
      expect(find.byKey(const Key('mobile_product_image_picker')), findsOneWidget);
      expect(find.byKey(const Key('mobile_pick_image_button')), findsOneWidget);
      expect(find.text('Cambiar Foto'), findsOneWidget);
    });

    testWidgets('Picking image and saving new product calls uploadProductImage', (tester) async {
      FilePicker.platform = MockFilePicker();
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = MockCatalogRepo();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider));
      await tester.pump();

      // Open new product form
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Seleccionar Foto'), findsOneWidget);

      // Pick image via mock FilePicker
      await tester.tap(find.byKey(const Key('mobile_pick_image_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // After picking, button should change to 'Cambiar Foto' and discard button appears
      expect(find.text('Cambiar Foto'), findsOneWidget);
      expect(find.byTooltip('Descartar foto'), findsOneWidget);

      // Fill in details and save
      await tester.enterText(find.widgetWithText(TextField, 'Nombre del producto'), 'Alfajor Triple Mock');
      await tester.enterText(find.widgetWithText(TextField, 'Venta (\$)'), '1200');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify that uploadProductImage was called on repository
      expect(repo.lastUploadedProductId, 999);
      expect(repo.lastUploadedFilename, 'alfajor_mock.png');
      expect(repo.lastUploadedPath, '/mock/images/alfajor_mock.png');
      expect(repo.lastUploadedBytes, isNotNull);
    });
  });
}
