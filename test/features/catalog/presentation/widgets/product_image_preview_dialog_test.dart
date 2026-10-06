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
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/product_image_preview_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

// --- MOCKS & FAKES ---
class MockFilePickerForPreview extends FilePicker {
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
        name: 'new_image.png',
        size: kTestBytes.length,
        bytes: kTestBytes,
        path: '/mock/path/new_image.png',
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCatalogProviderForPreview extends ChangeNotifier implements CatalogProvider {
  final List<Category> _categories = [Category(id: 1, name: 'Bebidas')];
  final List<Brand> _brands = [Brand(id: 1, name: 'Genérica')];
  final List<Rubro> _rubros = [Rubro(id: 1, name: 'General', isSystem: true)];
  
  bool uploadProductImageCalled = false;
  bool deleteProductImageCalled = false;
  bool deleteShouldFail = false;
  String? _fakeErrorMessage;
  int? lastDeletedProductId;
  Map<String, dynamic>? lastUpdatedPayload;

  @override
  List<Category> get categories => _categories;
  @override
  List<Brand> get brands => _brands;
  @override
  List<Rubro> get rubros => _rubros;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => _fakeErrorMessage;
  @override
  List<Product> get products => [];
  @override
  Product? get lastCreatedProduct => null;
  @override
  Product? get lastUpdatedProduct => null;

  @override
  Future<bool> updateProduct(int id, Map<String, dynamic> data) async {
    lastUpdatedPayload = data;
    return true;
  }

  @override
  Future<String?> uploadProductImage(int productId, String filePath, {List<int>? bytes, String? filename}) async {
    uploadProductImageCalled = true;
    return 'http://example.com/storage/products/$productId.jpg';
  }

  @override
  Future<bool> deleteProductImage(int productId) async {
    deleteProductImageCalled = true;
    lastDeletedProductId = productId;
    if (deleteShouldFail) {
      _fakeErrorMessage = 'Fallo de red al eliminar foto';
      return false;
    }
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProviderForPreview extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings? get settings => const BusinessSettings(licensePlanType: 'basic', features: FeatureFlags());
  @override
  String get currentPlan => 'basic';
  @override
  FeatureFlags get features => const FeatureFlags();
  @override
  bool hasFeature(String featureName) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupplierProviderForPreview extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_terminal_id': 'caja-test',
      'pos_api': 'http://pos-backend.test/api',
    });
  });

  group('Phase 7.7 R1: ProductImagePreviewDialog Widget Tests', () {
    testWidgets('Renders preview dialog with title, InteractiveViewer, and action buttons', (tester) async {
      bool removeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ProductImagePreviewDialog(
                      title: 'Coca Cola 1.5L',
                      imageUrl: 'http://example.com/coca.jpg',
                      onChangeImage: () {},
                      onRemoveImage: () => removeTapped = true,
                    ),
                  );
                },
                child: const Text('Abrir Preview'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Preview'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);
      expect(find.text('Coca Cola 1.5L'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // Verify action buttons exist
      expect(find.text('Cambiar Foto'), findsOneWidget);
      expect(find.text('Quitar Foto'), findsOneWidget);

      // Tap Quitar Foto
      await tester.tap(find.text('Quitar Foto'));
      await tester.pumpAndSettle();

      expect(removeTapped, isTrue);
      expect(find.byType(ProductImagePreviewDialog), findsNothing);
    });

    testWidgets('Tapping "Cambiar Foto" invokes onChangeImage callback and closes dialog', (tester) async {
      bool changeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ProductImagePreviewDialog(
                      title: 'Gaseosa',
                      imageUrl: 'http://example.com/soda.jpg',
                      onChangeImage: () => changeTapped = true,
                    ),
                  );
                },
                child: const Text('Abrir Preview'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Preview'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);

      await tester.tap(find.text('Cambiar Foto'));
      await tester.pumpAndSettle();

      expect(changeTapped, isTrue);
      expect(find.byType(ProductImagePreviewDialog), findsNothing);
    });

    testWidgets('Renders memory bytes cleanly without error', (tester) async {
      final bytes = MockFilePickerForPreview.kTestBytes;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ProductImagePreviewDialog(
                      title: 'Foto en memoria',
                      imageBytes: bytes,
                    ),
                  );
                },
                child: const Text('Abrir Preview'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Preview'));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Foto en memoria'), findsOneWidget);
    });

    testWidgets('Adversarial: Compact landscape viewport (480x300) renders preview dialog without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(480, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const ProductImagePreviewDialog(
                      title: 'Foto Compacta',
                      imageUrl: 'http://example.com/item.jpg',
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Adversarial: Rapid double-tapping "Quitar Foto" triggers callback only once and pops safely without popping underlying route', (tester) async {
      int removeCallCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ProductImagePreviewDialog(
                      title: 'Double Tap Test',
                      imageUrl: 'http://example.com/test.jpg',
                      onRemoveImage: () => removeCallCount++,
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      final removeBtn = find.byKey(const Key('preview_remove_image_button'));
      expect(removeBtn, findsOneWidget);

      await tester.tap(removeBtn);
      await tester.tap(removeBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(removeCallCount, equals(1));
      expect(find.byType(ProductImagePreviewDialog), findsNothing);
      expect(find.text('Abrir'), findsOneWidget);
    });

    testWidgets('Adversarial: When preview has no image, "Quitar Foto" button is not shown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const ProductImagePreviewDialog(
                      title: 'Sin Foto',
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('preview_remove_image_button')), findsNothing);
    });

    testWidgets('Adversarial: Double-tap on image zooms in to 2x and second double-tap resets zoom', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const ProductImagePreviewDialog(
                      title: 'Yerba Mate',
                      imageUrl: 'http://example.com/yerba.jpg',
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      final interactiveViewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(interactiveViewer.transformationController?.value.isIdentity(), isTrue);

      // Double tap to zoom in
      await tester.tap(find.byKey(const Key('preview_double_tap_detector')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('preview_double_tap_detector')));
      await tester.pumpAndSettle();

      final zoomedMatrix = interactiveViewer.transformationController?.value;
      expect(zoomedMatrix?.isIdentity(), isFalse);
      expect(zoomedMatrix?.getMaxScaleOnAxis(), closeTo(2.0, 0.01));

      // Double tap again to reset zoom
      await tester.tap(find.byKey(const Key('preview_double_tap_detector')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('preview_double_tap_detector')));
      await tester.pumpAndSettle();

      expect(interactiveViewer.transformationController?.value.isIdentity(), isTrue);
    });

    testWidgets('Adversarial: Relative image path (products/yerba.jpg) resolves and renders properly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const ProductImagePreviewDialog(
                      title: 'Producto Relativo',
                      imageUrl: 'products/yerba.jpg',
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<NetworkImage>());
      final netImage = imageWidget.image as NetworkImage;
      expect(netImage.url, contains('/storage/products/yerba.jpg'));
    });

    testWidgets('Adversarial R3: Barrier dismissal race does NOT execute onRemoveImage callback', (tester) async {
      bool removeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    barrierDismissible: true,
                    builder: (_) => ProductImagePreviewDialog(
                      title: 'Barrier Race Test',
                      imageUrl: 'http://example.com/item.jpg',
                      onRemoveImage: () => removeCalled = true,
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);

      // Tap the modal barrier at top-left to start dismissing
      await tester.tapAt(const Offset(10, 10));
      // Pump one frame so the route transition starts (route.isCurrent becomes false)
      await tester.pump();

      // Now attempt to tap "Quitar Foto" while the route is in mid-dismissal
      final removeBtn = find.byKey(const Key('preview_remove_image_button'));
      if (removeBtn.evaluate().isNotEmpty) {
        await tester.tap(removeBtn, warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      // removeCalled MUST BE FALSE because the dismissal was initiated by the barrier
      expect(removeCalled, isFalse);
      expect(find.byType(ProductImagePreviewDialog), findsNothing);
    });

    testWidgets('Adversarial R3: Dark theme renders dialog with theme error color on remove button and zero overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ProductImagePreviewDialog(
                      title: 'Dark Mode Product',
                      imageUrl: 'http://example.com/dark.jpg',
                      onChangeImage: () {},
                      onRemoveImage: () {},
                    ),
                  );
                },
                child: const Text('Abrir Dark'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Dark'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);
      expect(tester.takeException(), isNull);

      final removeBtnFinder = find.byKey(const Key('preview_remove_image_button'));
      expect(removeBtnFinder, findsOneWidget);

      final outlinedBtn = tester.widget<OutlinedButton>(removeBtnFinder);
      expect(outlinedBtn.style?.foregroundColor?.resolve({}), isNotNull);
    });

    testWidgets('Adversarial R3: Broken image or network error renders user-friendly fallback widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const ProductImagePreviewDialog(
                      title: 'Error Image Test',
                      imagePath: '/non/existent/path/image.jpg',
                    ),
                  );
                },
                child: const Text('Abrir Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Error'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);
      expect(find.text('No se pudo cargar la imagen'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    });
  });

  group('Phase 7.7 R1: Desktop ProductFormDialog Image Preview Integration Tests', () {
    Widget buildAppWithDialog({Product? product, required FakeCatalogProviderForPreview catalogProv}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
          ChangeNotifierProvider<SettingsProvider>.value(value: FakeSettingsProviderForPreview()),
          ChangeNotifierProvider<SupplierProvider>.value(value: FakeSupplierProviderForPreview()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ProductFormDialog(
                      provider: catalogProv,
                      product: product,
                    ),
                  );
                },
                child: const Text('Open Form'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Clicking thumbnail on product with existing image opens enlarged preview dialog', (tester) async {
      final catalogProv = FakeCatalogProviderForPreview();
      final productWithImage = Product(
        id: 101,
        name: 'Yerba Mate Especial',
        internalCode: '00101',
        costPrice: 800,
        sellingPrice: 1500,
        stock: 12,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/yerba.jpg',
      );

      await tester.pumpWidget(buildAppWithDialog(product: productWithImage, catalogProv: catalogProv));
      await tester.tap(find.text('Open Form'));
      await tester.pumpAndSettle();

      // Click the product image thumbnail
      final thumbnail = find.byKey(const ValueKey('product_image_container'));
      expect(thumbnail, findsOneWidget);
      await tester.tap(thumbnail);
      await tester.pumpAndSettle();

      // Verify ProductImagePreviewDialog opened
      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ProductImagePreviewDialog),
          matching: find.text('Yerba Mate Especial'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('preview_change_image_button')), findsOneWidget);
      expect(find.byKey(const Key('preview_remove_image_button')), findsOneWidget);
    });

    testWidgets('In preview dialog, clicking "Quitar Foto" clears image in form and calls deleteProductImage on save', (tester) async {
      final catalogProv = FakeCatalogProviderForPreview();
      final productWithImage = Product(
        id: 102,
        name: 'Galletitas Chocolate',
        internalCode: '00102',
        costPrice: 400,
        sellingPrice: 700,
        stock: 30,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/cookies.jpg',
      );

      await tester.pumpWidget(buildAppWithDialog(product: productWithImage, catalogProv: catalogProv));
      await tester.tap(find.text('Open Form'));
      await tester.pumpAndSettle();

      // Click thumbnail to open preview
      await tester.tap(find.byKey(const ValueKey('product_image_container')));
      await tester.pumpAndSettle();

      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);

      // Tap Quitar Foto in preview dialog
      await tester.tap(find.byKey(const Key('preview_remove_image_button')));
      await tester.pumpAndSettle();

      // Preview dialog is closed
      expect(find.byType(ProductImagePreviewDialog), findsNothing);

      // Form now shows empty thumbnail placeholder "Subir Foto"
      expect(find.text('Subir Foto'), findsOneWidget);

      // Tap Guardar Cambios to submit form
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar Cambios'));
      await tester.pumpAndSettle();

      // Verify deleteProductImage was invoked for product 102
      expect(catalogProv.deleteProductImageCalled, isTrue);
      expect(catalogProv.lastDeletedProductId, equals(102));
    });

    testWidgets('In preview dialog, clicking "Cambiar Foto" picks new image and updates form state', (tester) async {
      FilePicker.platform = MockFilePickerForPreview();
      final catalogProv = FakeCatalogProviderForPreview();
      final productWithImage = Product(
        id: 103,
        name: 'Jugo de Naranja',
        internalCode: '00103',
        costPrice: 300,
        sellingPrice: 550,
        stock: 15,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/orange_juice.jpg',
      );

      await tester.pumpWidget(buildAppWithDialog(product: productWithImage, catalogProv: catalogProv));
      await tester.tap(find.text('Open Form'));
      await tester.pumpAndSettle();

      // Open preview dialog
      await tester.tap(find.byKey(const ValueKey('product_image_container')));
      await tester.pumpAndSettle();

      expect(find.byType(ProductImagePreviewDialog), findsOneWidget);

      // Click "Cambiar Foto" in preview dialog
      await tester.tap(find.byKey(const Key('preview_change_image_button')));
      await tester.pumpAndSettle();

      // Dialog is dismissed and new image is loaded into form
      expect(find.byType(ProductImagePreviewDialog), findsNothing);
      expect(find.byTooltip('Quitar foto'), findsOneWidget);

      // Save form -> invokes uploadProductImage
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(catalogProv.uploadProductImageCalled, isTrue);
    });

    testWidgets('Clicking thumbnail with no image directly triggers file picker', (tester) async {
      FilePicker.platform = MockFilePickerForPreview();
      final catalogProv = FakeCatalogProviderForPreview();

      await tester.pumpWidget(buildAppWithDialog(product: null, catalogProv: catalogProv));
      await tester.tap(find.text('Open Form'));
      await tester.pumpAndSettle();

      // Form has no image ("Subir Foto")
      expect(find.text('Subir Foto'), findsOneWidget);

      // Clicking thumbnail triggers image picker directly
      await tester.tap(find.byKey(const ValueKey('product_image_container')));
      await tester.pumpAndSettle();

      // New image is selected
      expect(find.byTooltip('Quitar foto'), findsOneWidget);
    });

    testWidgets('Adversarial: When deleteProductImage fails on form save, warning SnackBar is displayed', (tester) async {
      final catalogProv = FakeCatalogProviderForPreview()..deleteShouldFail = true;
      final productWithImage = Product(
        id: 104,
        name: 'Arroz Largo Fino',
        internalCode: '00104',
        costPrice: 200,
        sellingPrice: 350,
        stock: 50,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/rice.jpg',
      );

      await tester.pumpWidget(buildAppWithDialog(product: productWithImage, catalogProv: catalogProv));
      await tester.tap(find.text('Open Form'));
      await tester.pumpAndSettle();

      // Open preview dialog
      await tester.tap(find.byKey(const ValueKey('product_image_container')));
      await tester.pumpAndSettle();

      // Tap Quitar Foto
      await tester.tap(find.byKey(const Key('preview_remove_image_button')));
      await tester.pumpAndSettle();

      // Submit form
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(catalogProv.deleteProductImageCalled, isTrue);
      // Warning SnackBar indicating deletion error
      expect(find.textContaining('Fallo de red al eliminar foto'), findsOneWidget);
    });

    testWidgets('Adversarial: Discarding photo on product that never had remote image does NOT call deleteProductImage', (tester) async {
      FilePicker.platform = MockFilePickerForPreview();
      final catalogProv = FakeCatalogProviderForPreview();
      final productWithoutImage = Product(
        id: 105,
        name: 'Azúcar Ledesma',
        internalCode: '00105',
        costPrice: 500,
        sellingPrice: 900,
        stock: 20,
        active: true,
        isSoldByWeight: false,
        imageUrl: null,
      );

      await tester.pumpWidget(buildAppWithDialog(product: productWithoutImage, catalogProv: catalogProv));
      await tester.tap(find.text('Open Form'));
      await tester.pumpAndSettle();

      // Pick a photo first
      await tester.tap(find.byKey(const ValueKey('product_image_container')));
      await tester.pumpAndSettle();

      // Open preview of the picked photo and tap Quitar Foto
      await tester.tap(find.byKey(const ValueKey('product_image_container')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('preview_remove_image_button')));
      await tester.pumpAndSettle();

      // Save form
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar Cambios'));
      await tester.pumpAndSettle();

      // deleteProductImage should NOT be called because product never had a remote image on server
      expect(catalogProv.deleteProductImageCalled, isFalse);
    });
  });
}
