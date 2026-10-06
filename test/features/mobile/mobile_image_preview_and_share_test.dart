import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/product_image_preview_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/mobile/presentation/screens/mobile_audit_screen.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';

// --- MOCKS & FAKES ---
class MockFilePickerForMobile extends FilePicker {
  static final Uint8List kTestBytes = base64Decode(
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
        name: 'new_mobile_photo.png',
        size: kTestBytes.length,
        bytes: kTestBytes,
        path: '/mock/new_mobile_photo.png',
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCatalogRepositoryForMobile implements CatalogRepository {
  List<Product> products = [];
  bool uploadCalled = false;
  bool deleteCalled = false;
  bool deleteShouldThrow = false;
  int? deletedProductId;
  Map<String, dynamic>? lastUpdatedPayload;

  @override
  Future<Product> updateProduct(int id, Map<String, dynamic> data) async {
    lastUpdatedPayload = data;
    final idx = products.indexWhere((p) => p.id == id);
    if (idx != -1) {
      final updated = products[idx].copyWith(
        name: data['name'] as String?,
        costPrice: (data['cost_price'] as num?)?.toDouble(),
        sellingPrice: (data['selling_price'] as num?)?.toDouble(),
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
    uploadCalled = true;
    return 'http://example.com/storage/products/$productId.jpg';
  }

  @override
  Future<void> deleteProductImage(int productId) async {
    deleteCalled = true;
    deletedProductId = productId;
    if (deleteShouldThrow) {
      throw Exception('Error del servidor al borrar imagen');
    }
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

class FakeSettingsProviderForMobile extends ChangeNotifier implements SettingsProvider {
  @override
  FeatureFlags get features => const FeatureFlags(suppliers: false, multiRubro: false);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupplierProviderForMobile extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [];
  @override
  Future<void> fetchSuppliers({String? search}) async {}
  @override
  bool get isLoading => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePosProviderForMobile extends ChangeNotifier implements PosProvider {
  List<Product> mockProducts = [];
  @override
  Future<List<Product>> search(String query) async {
    return mockProducts.where((p) => (p.barcode?.contains(query) ?? false) || p.internalCode.contains(query) || p.name.toLowerCase().contains(query.toLowerCase())).toList();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProviderForMobile extends ChangeNotifier implements AuthProvider {
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

  Widget buildMobileApp({required CatalogProvider catalogProvider, required PosProvider posProvider}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: FakeSettingsProviderForMobile()),
        ChangeNotifierProvider<SupplierProvider>.value(value: FakeSupplierProviderForMobile()),
        ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProviderForMobile()),
        ChangeNotifierProvider<PosProvider>.value(value: posProvider),
      ],
      child: const MaterialApp(
        home: MobileAuditScreen(),
      ),
    );
  }

  final testProduct = Product(
    id: 55,
    name: 'Galletitas Oreo',
    barcode: '762230000001',
    internalCode: 'ORE01',
    costPrice: 500,
    sellingPrice: 950,
    stock: 40,
    imageUrl: 'http://example.com/oreo.jpg',
    active: true,
    isSoldByWeight: false,
  );

  group('Phase 7.7 R2: Mobile Product Form Image Preview UX', () {
    testWidgets('Tapping image thumbnail in mobile form opens ProductImagePreviewDialog', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = FakeCatalogRepositoryForMobile()..products = [testProduct];
      final catalogProvider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = FakePosProviderForMobile()..mockProducts = [testProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: catalogProvider, posProvider: posProvider));
      await tester.pump();

      // Search product
      await tester.enterText(find.byType(TextField).first, '762230000001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      // Open edit dialog
      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      // Mobile product image picker thumbnail is visible
      final thumbnail = find.byKey(const Key('mobile_product_image_picker'));
      expect(thumbnail, findsOneWidget);

      // Tap thumbnail -> opens enlarged preview dialog
      await tester.tap(thumbnail);
      await tester.pumpAndSettle();

      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);
      expect(find.byKey(const Key('preview_change_image_button')), findsOneWidget);
      expect(find.byKey(const Key('preview_remove_image_button')), findsOneWidget);
    });

    testWidgets('In mobile preview, tapping "Quitar Foto" updates form state and deletes image on save', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = FakeCatalogRepositoryForMobile()..products = [testProduct];
      final catalogProvider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = FakePosProviderForMobile()..mockProducts = [testProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: catalogProvider, posProvider: posProvider));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '762230000001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      // Tap thumbnail -> opens preview
      await tester.tap(find.byKey(const Key('mobile_product_image_picker')));
      await tester.pumpAndSettle();

      // Tap "Quitar Foto" in preview
      await tester.tap(find.byKey(const Key('preview_remove_image_button')));
      await tester.pumpAndSettle();

      // Preview is dismissed and form thumbnail shows empty placeholder "Subir Foto"
      expect(find.byType(ProductImagePreviewDialog), findsNothing);
      expect(find.text('Subir Foto'), findsOneWidget);

      // Save mobile form
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalled, isTrue);
      expect(repo.deletedProductId, equals(55));
    });

    testWidgets('In mobile preview, tapping "Cambiar Foto" selects new image and uploads on save', (tester) async {
      FilePicker.platform = MockFilePickerForMobile();
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = FakeCatalogRepositoryForMobile()..products = [testProduct];
      final catalogProvider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = FakePosProviderForMobile()..mockProducts = [testProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: catalogProvider, posProvider: posProvider));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '762230000001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      // Tap thumbnail -> opens preview
      await tester.tap(find.byKey(const Key('mobile_product_image_picker')));
      await tester.pumpAndSettle();

      // Tap "Cambiar Foto" in preview
      await tester.tap(find.byKey(const Key('preview_change_image_button')));
      await tester.pumpAndSettle();

      // Preview is dismissed, discard icon is available
      expect(find.byType(ProductImagePreviewDialog), findsNothing);
      expect(find.byTooltip('Descartar foto'), findsOneWidget);

      // Save form
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(repo.uploadCalled, isTrue);
    });
  });

  group('Phase 7.7 R3: Mobile Product Sharing', () {
    testWidgets('Scanned product result view has functional Share button that triggers ProductShareHelper', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = FakeCatalogRepositoryForMobile()..products = [testProduct];
      final catalogProvider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = FakePosProviderForMobile()..mockProducts = [testProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: catalogProvider, posProvider: posProvider));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '762230000001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      // Check Share button exists in scanned product view
      final shareButton = find.byKey(const Key('mobile_share_button'));
      expect(shareButton, findsOneWidget);
      expect(find.byTooltip('Compartir'), findsOneWidget);

      // Tapping it invokes ProductShareHelper without crashing
      await tester.tap(shareButton);
      await tester.pump();
    });

    testWidgets('Tapping thumbnail in scanned product result view opens enlarged preview dialog', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = FakeCatalogRepositoryForMobile()..products = [testProduct];
      final catalogProvider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = FakePosProviderForMobile()..mockProducts = [testProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: catalogProvider, posProvider: posProvider));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '762230000001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      final thumbnailFinder = find.byKey(const Key('mobile_scanned_image_preview'));
      expect(thumbnailFinder, findsOneWidget);

      await tester.tap(thumbnailFinder);
      await tester.pumpAndSettle();

      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ProductImagePreviewDialog),
          matching: find.text('Galletitas Oreo'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Mobile edit dialog has Share button in title when editing existing product', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = FakeCatalogRepositoryForMobile()..products = [testProduct];
      final catalogProvider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = FakePosProviderForMobile()..mockProducts = [testProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: catalogProvider, posProvider: posProvider));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '762230000001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      // Check Share button in dialog title
      expect(find.byKey(const Key('product_share_button')), findsOneWidget);
      expect(find.byTooltip('Compartir producto'), findsOneWidget);
    });

    testWidgets('Adversarial: When removing photo directly from scanned product preview fails, error SnackBar is displayed', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = FakeCatalogRepositoryForMobile()
        ..products = [testProduct]
        ..deleteShouldThrow = true;
      final catalogProvider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = FakePosProviderForMobile()..mockProducts = [testProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: catalogProvider, posProvider: posProvider));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '762230000001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      final thumbnailFinder = find.byKey(const Key('mobile_scanned_image_preview'));
      expect(thumbnailFinder, findsOneWidget);

      await tester.tap(thumbnailFinder);
      await tester.pumpAndSettle();

      final removeBtn = find.byKey(const Key('preview_remove_image_button'));
      expect(removeBtn, findsOneWidget);
      await tester.tap(removeBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Error del servidor al borrar imagen'), findsOneWidget);
    });

    testWidgets('Adversarial: When deleteProductImage fails during mobile form save, warning SnackBar is displayed', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = FakeCatalogRepositoryForMobile()
        ..products = [testProduct]
        ..deleteShouldThrow = true;
      final catalogProvider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = FakePosProviderForMobile()..mockProducts = [testProduct];

      await tester.pumpWidget(buildMobileApp(catalogProvider: catalogProvider, posProvider: posProvider));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '762230000001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mobile_product_image_picker')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('preview_remove_image_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalled, isTrue);
      expect(find.textContaining('Error del servidor al borrar imagen'), findsOneWidget);
    });

    testWidgets('Adversarial: Discarding photo on mobile product that had NO remote image does NOT call deleteProductImage on save', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      FilePicker.platform = MockFilePickerForMobile();
      final productWithoutImage = testProduct.copyWith(imageUrl: null, clearImageUrl: true);
      final repo = FakeCatalogRepositoryForMobile()..products = [productWithoutImage];
      final catalogProvider = CatalogProvider(getProductsUseCase: GetProductsUseCase(repo), repository: repo);
      final posProvider = FakePosProviderForMobile()..mockProducts = [productWithoutImage];

      await tester.pumpWidget(buildMobileApp(catalogProvider: catalogProvider, posProvider: posProvider));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '762230000001');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar detalles'));
      await tester.pumpAndSettle();

      // Pick photo
      await tester.tap(find.byKey(const Key('mobile_product_image_picker')));
      await tester.pumpAndSettle();

      // Open preview dialog and tap Quitar Foto
      await tester.tap(find.byKey(const Key('mobile_product_image_picker')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('preview_remove_image_button')));
      await tester.pumpAndSettle();

      // Save form
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // deleteProductImage must NOT be called
      expect(repo.deleteCalled, isFalse);
    });
  });
}
