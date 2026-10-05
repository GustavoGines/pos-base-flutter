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

class ConfigurableMockFilePicker extends FilePicker {
  FilePickerResult? nextResult;

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
    return nextResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdversarialCatalogRepository implements CatalogRepository {
  List<Product> products = [];
  Map<String, dynamic>? lastCreatedPayload;
  Map<String, dynamic>? lastUpdatedPayload;
  int? lastUploadedProductId;
  String? lastUploadedPath;
  List<int>? lastUploadedBytes;
  String? lastUploadedFilename;
  bool shouldFailImageUpload = false;

  @override
  Future<Product> createProduct(Map<String, dynamic> data) async {
    lastCreatedPayload = data;
    final p = Product(
      id: 555,
      name: data['name'] ?? '',
      barcode: data['barcode'],
      internalCode: data['internal_code'] ?? '00555',
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
    lastUpdatedPayload = data;
    final idx = products.indexWhere((p) => p.id == id);
    if (idx != -1) {
      final updated = products[idx].copyWith(
        name: data['name'] as String?,
        costPrice: (data['cost_price'] as num?)?.toDouble(),
        sellingPrice: (data['selling_price'] as num?)?.toDouble(),
        stock: (data['stock'] as num?)?.toDouble(),
        category: data['category_id'] == null ? null : products[idx].category,
        clearCategory: data['category_id'] == null,
        brand: data['brand_id'] == null ? null : products[idx].brand,
        clearBrand: data['brand_id'] == null,
        supplier: data['supplier_id'] == null ? null : products[idx].supplier,
        clearSupplier: data['supplier_id'] == null,
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
    if (shouldFailImageUpload) {
      throw Exception('Server 500: Upload payload corrupted or disk full');
    }
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
  Future<List<Brand>> getBrands() async => [Brand(id: 1, name: 'Arcor')];

  @override
  Future<List<Rubro>> getRubros() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  FeatureFlags get features => const FeatureFlags(suppliers: true, multiRubro: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [Supplier(id: 1, name: 'Distribuidora Mayorista', balance: 0.0, isActive: true)];
  @override
  Future<void> fetchSuppliers({String? search}) async {}
  @override
  bool get isLoading => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestPosProvider extends ChangeNotifier implements PosProvider {
  List<Product> mockProducts = [];
  @override
  Future<List<Product>> search(String query) async {
    return mockProducts.where((p) => (p.barcode?.contains(query) ?? false) || p.internalCode.contains(query) || p.name.toLowerCase().contains(query.toLowerCase())).toList();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  bool hasPermission(String permission) => true;
  @override
  bool get isAdmin => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockPicker = ConfigurableMockFilePicker();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
    FilePicker.platform = mockPicker;
  });

  Widget buildMobileApp({required CatalogProvider catalogProvider, PosProvider? posProvider}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: TestSettingsProvider()),
        ChangeNotifierProvider<SupplierProvider>.value(value: TestSupplierProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: TestAuthProvider()),
        ChangeNotifierProvider<PosProvider>.value(value: posProvider ?? TestPosProvider()),
      ],
      child: const MaterialApp(
        home: MobileAuditScreen(),
      ),
    );
  }

  final sample1x1Png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  group('Adversarial Mobile Product Form Image Upload (R3 QA)', () {
    testWidgets('Adversarial 1: Unsupported file extension is rejected with error SnackBar', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'malicious_script.pdf',
          size: 1024,
          bytes: Uint8List.fromList([1, 2, 3]),
          path: '/downloads/malicious_script.pdf',
        ),
      ]);

      final repo = AdversarialCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider));
      await tester.pump();

      // Open new product form
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Tap pick image
      await tester.tap(find.byKey(const Key('mobile_pick_image_button')));
      await tester.pumpAndSettle();

      // Verify rejection error snackbar
      expect(find.textContaining('Formato no soportado'), findsOneWidget);
      // Image was NOT accepted
      expect(find.text('Subir Foto'), findsOneWidget);
    });

    testWidgets('Adversarial 2: Image > 2MB is rejected with size limit SnackBar', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'huge_photo.jpg',
          size: 3 * 1024 * 1024, // 3MB
          bytes: Uint8List(100),
          path: '/downloads/huge_photo.jpg',
        ),
      ]);

      final repo = AdversarialCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider));
      await tester.pump();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mobile_pick_image_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('supera los 2MB permitidos'), findsOneWidget);
      expect(find.text('Subir Foto'), findsOneWidget);
    });

    testWidgets('Adversarial 3: Discarding selected image clears staging and prevents upload on save', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'valid_photo.png',
          size: sample1x1Png.length,
          bytes: sample1x1Png,
          path: '/photos/valid_photo.png',
        ),
      ]);

      final repo = AdversarialCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider));
      await tester.pump();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Pick photo
      await tester.tap(find.byKey(const Key('mobile_pick_image_button')));
      await tester.pumpAndSettle();

      expect(find.text('Cambiar Foto'), findsOneWidget);
      expect(find.byTooltip('Descartar foto'), findsOneWidget);

      // Now tap discard button
      await tester.tap(find.byTooltip('Descartar foto'));
      await tester.pumpAndSettle();

      // Button reverted to Seleccionar Foto
      expect(find.text('Seleccionar Foto'), findsOneWidget);
      expect(find.byTooltip('Descartar foto'), findsNothing);

      // Save product
      await tester.enterText(find.widgetWithText(TextField, 'Nombre del producto'), 'Producto Sin Foto');
      await tester.enterText(find.widgetWithText(TextField, 'Venta (\$)'), '150');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Verify created but upload was NOT called
      expect(repo.lastCreatedPayload?['name'], 'Producto Sin Foto');
      expect(repo.lastUploadedProductId, isNull);
    });

    testWidgets('Adversarial 4: Image upload failure displays warning SnackBar to user', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'failing_photo.png',
          size: sample1x1Png.length,
          bytes: sample1x1Png,
          path: '/photos/failing_photo.png',
        ),
      ]);

      final repo = AdversarialCatalogRepository()..shouldFailImageUpload = true;
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider));
      await tester.pump();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mobile_pick_image_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Nombre del producto'), 'Producto Error Foto');
      await tester.enterText(find.widgetWithText(TextField, 'Venta (\$)'), '300');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Warning snackbar rendered notifying user of image failure
      expect(find.textContaining('Producto guardado, pero no se pudo subir la foto'), findsOneWidget);
    });

    testWidgets('Adversarial 5: Editing existing product replaces image and immediately syncs in-memory view', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final existingProduct = Product(
        id: 777,
        name: 'Galletitas Chocolinas',
        barcode: '7790001',
        internalCode: 'GAL-777',
        costPrice: 800,
        sellingPrice: 1500,
        stock: 50,
        imageUrl: 'http://example.com/chocolinas_old.jpg',
        active: true,
        isSoldByWeight: false,
      );

      final repo = AdversarialCatalogRepository()..products = [existingProduct];
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      provider.products.add(existingProduct);
      final posProvider = TestPosProvider()..mockProducts = [existingProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider, posProvider: posProvider));
      await tester.pump();

      // Search for product
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '7790001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      // Tap edit
      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      expect(find.text('Editar Producto'), findsOneWidget);

      // Stage new photo
      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'chocolinas_hd.png',
          size: sample1x1Png.length,
          bytes: sample1x1Png,
          path: '/photos/chocolinas_hd.png',
        ),
      ]);
      await tester.tap(find.byKey(const Key('mobile_pick_image_button')));
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Verify upload was performed for product 777
      expect(repo.lastUploadedProductId, 777);
      expect(repo.lastUploadedFilename, 'chocolinas_hd.png');
      expect(find.text('Producto modificado exitosamente'), findsOneWidget);

      // Verify that in-memory product has the updated imageUrl
      final updatedInMemory = provider.products.firstWhere((p) => p.id == 777);
      expect(updatedInMemory.imageUrl, 'http://example.com/storage/products/777.jpg');
    });

    testWidgets('Adversarial 6: User canceling picker returns null without crashing or modifying state', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockPicker.nextResult = null; // canceled

      final repo = AdversarialCatalogRepository();
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider));
      await tester.pump();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mobile_pick_image_button')));
      await tester.pumpAndSettle();

      // State is completely intact
      expect(find.text('Seleccionar Foto'), findsOneWidget);
      expect(find.text('Nuevo Producto'), findsOneWidget);
    });

    testWidgets('Adversarial 7: Editing scanned product NOT in CatalogProvider.products updates view immediately without reverting', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final scannedOnlyProduct = Product(
        id: 888,
        name: 'Alfajor Havanna 70% Cacao',
        barcode: '7798888',
        internalCode: 'HAV-888',
        costPrice: 900,
        sellingPrice: 1600,
        stock: 30,
        imageUrl: 'http://example.com/havanna_old.jpg',
        active: true,
        isSoldByWeight: false,
      );

      final repo = AdversarialCatalogRepository()..products = [scannedOnlyProduct];
      // Note: provider.products is NOT populated, mimicking real mobile audit startup
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = TestPosProvider()..mockProducts = [scannedOnlyProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider, posProvider: posProvider));
      await tester.pump();

      // Search and scan product
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '7798888');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      // Verify product loaded with initial price 1600
      expect(find.text('Alfajor Havanna 70% Cacao'), findsOneWidget);

      // Tap edit
      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      // Update price to 2400 and stage new photo
      await tester.enterText(find.widgetWithText(TextField, 'Venta (\$)'), '2400');
      await tester.pump();

      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'havanna_new.png',
          size: sample1x1Png.length,
          bytes: sample1x1Png,
          path: '/photos/havanna_new.png',
        ),
      ]);
      await tester.tap(find.byKey(const Key('mobile_pick_image_button')));
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Verify modification success
      expect(find.text('Producto modificado exitosamente'), findsOneWidget);

      // Verify that scanned product view in memory is updated to 2400 and NOT reverted
      expect(find.widgetWithText(TextField, '2400'), findsOneWidget);
      expect(repo.lastUploadedProductId, 888);
      expect(repo.lastUploadedFilename, 'havanna_new.png');
    });

    testWidgets('Adversarial 8: Relative imageUrl resolves properly and renders in both edit dialog and scanned view', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final relativeImgProduct = Product(
        id: 999,
        name: 'Jugo Bagley Naranja',
        barcode: '7799999',
        internalCode: 'JUG-999',
        costPrice: 500,
        sellingPrice: 1000,
        stock: 15,
        imageUrl: 'products/bagley.jpg', // Relative path
        active: true,
        isSoldByWeight: false,
      );

      final repo = AdversarialCatalogRepository()..products = [relativeImgProduct];
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = TestPosProvider()..mockProducts = [relativeImgProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider, posProvider: posProvider));
      await tester.pump();

      // Search product
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '7799999');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      // Scanned view renders ClipRRect with Image.network using resolved url
      expect(find.byType(ClipRRect), findsOneWidget);

      // Open edit dialog
      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      // In edit dialog, Cambiar Foto should be displayed because relative url was resolved
      expect(find.text('Cambiar Foto'), findsOneWidget);

      // Close dialog
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar').last);
      await tester.pumpAndSettle();
    });

    testWidgets('Adversarial 9: Decimal selling and cost prices (e.g. 19.99 and 12.50) are preserved without integer truncation on dialog open and save', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final decimalProduct = Product(
        id: 1234,
        name: 'Turron de Mani',
        barcode: '7791234',
        internalCode: 'TUR-1234',
        costPrice: 12.50,
        sellingPrice: 19.99,
        stock: 45,
        active: true,
        isSoldByWeight: false,
      );

      final repo = AdversarialCatalogRepository()..products = [decimalProduct];
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = TestPosProvider()..mockProducts = [decimalProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider, posProvider: posProvider));
      await tester.pump();

      // Search product
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '7791234');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      // Open edit dialog
      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      // Verify that decimal cost (12.5) and price (19.99) are NOT truncated to 12 and 19
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextField, '19.99')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextField, '12.5')), findsOneWidget);

      // Save without changes
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Verify update payload preserved the exact decimals
      expect(repo.lastUpdatedPayload?['selling_price'], 19.99);
      expect(repo.lastUpdatedPayload?['cost_price'], 12.50);

      // Verify on-screen price is 19.99, not 19
      expect(find.descendant(of: find.byType(MobileAuditScreen), matching: find.widgetWithText(TextFormField, '19.99')), findsOneWidget);
    });

    testWidgets('Adversarial 10: Comma decimals (e.g. "250,50") in quick price update parse accurately', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final product = Product(
        id: 2345,
        name: 'Caramelos Sugus',
        barcode: '7792345',
        internalCode: 'SUG-2345',
        costPrice: 100.0,
        sellingPrice: 200.0,
        stock: 50,
        active: true,
        isSoldByWeight: false,
      );

      final repo = AdversarialCatalogRepository()..products = [product];
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = TestPosProvider()..mockProducts = [product];

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider, posProvider: posProvider));
      await tester.pump();

      // Search product
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '7792345');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      // Quick price update with comma
      final quickPriceField = find.widgetWithText(TextFormField, '200');
      await tester.enterText(quickPriceField, '250,50');
      await tester.pump();

      await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.save));
      await tester.pumpAndSettle();

      // Verify quick update saved 250.5, not 0.0
      expect(repo.lastUpdatedPayload?['selling_price'], 250.5);
      expect(find.widgetWithText(TextFormField, '250.5'), findsOneWidget);
    });

    testWidgets('Adversarial 11: Comma decimals (e.g. "110,75" and "310,25") in edit dialog parse accurately', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final product = Product(
        id: 2346,
        name: 'Chicle Beldent',
        barcode: '7792346',
        internalCode: 'BEL-2346',
        costPrice: 100.0,
        sellingPrice: 200.0,
        stock: 50,
        active: true,
        isSoldByWeight: false,
      );

      final repo = AdversarialCatalogRepository()..products = [product];
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = TestPosProvider()..mockProducts = [product];

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider, posProvider: posProvider));
      await tester.pump();

      // Search product
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '7792346');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      // Open edit dialog
      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      final costField = find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextField, 'Costo (\$)'));
      await tester.enterText(costField, '110,75');
      final priceField = find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextField, 'Venta (\$)'));
      await tester.enterText(priceField, '310,25');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Verify dialog saved exact parsed decimals
      expect(repo.lastUpdatedPayload?['cost_price'], 110.75);
      expect(repo.lastUpdatedPayload?['selling_price'], 310.25);
    });

    testWidgets('Adversarial 12: Unsetting category, brand, and supplier in edit dialog cleanly clears relations', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final product = Product(
        id: 3456,
        name: 'Gaseosa Manaos Cola',
        barcode: '7793456',
        internalCode: 'MAN-3456',
        costPrice: 400.0,
        sellingPrice: 800.0,
        stock: 20,
        category: Category(id: 1, name: 'Bebidas'),
        brand: Brand(id: 1, name: 'Arcor'),
        supplier: Supplier(id: 1, name: 'Distribuidora Mayorista', balance: 0.0, isActive: true),
        active: true,
        isSoldByWeight: false,
      );

      final repo = AdversarialCatalogRepository()..products = [product];
      final provider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      // Preload categories and brands
      await provider.loadMetadata();
      final posProvider = TestPosProvider()..mockProducts = [product];

      await tester.pumpWidget(buildMobileApp(catalogProvider: provider, posProvider: posProvider));
      await tester.pump();

      // Search product
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '7793456');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      // Open edit dialog
      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      // Unset category: tap dropdown and choose 'Sin Categoría'
      final catDropdown = find.widgetWithText(DropdownButtonFormField<int?>, 'Bebidas');
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin Categoría').last);
      await tester.pumpAndSettle();

      // Unset brand: tap dropdown and choose 'Sin Marca'
      final brandDropdown = find.widgetWithText(DropdownButtonFormField<int?>, 'Arcor');
      await tester.tap(brandDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin Marca').last);
      await tester.pumpAndSettle();

      // Unset supplier: tap dropdown and choose 'Sin Proveedor'
      final supDropdown = find.widgetWithText(DropdownButtonFormField<int?>, 'Distribuidora Mayorista');
      await tester.tap(supDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin Proveedor').last);
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Verify payload unsets relationships with null IDs
      expect(repo.lastUpdatedPayload?['category_id'], isNull);
      expect(repo.lastUpdatedPayload?['brand_id'], isNull);
      expect(repo.lastUpdatedPayload?['supplier_id'], isNull);
    });
  });
}
