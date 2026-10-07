import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_access_view.dart';
import 'package:frontend_desktop/features/pos/presentation/pages/pos_screen.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

// ─── MOCKS & FAKES ──────────────────────────────────────────────────────────

class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings? _settings;

  MockSettingsProvider({BusinessSettings? initialSettings}) {
    _settings = initialSettings ??
        const BusinessSettings(
          companyName: 'Supermercado Test',
          logoUrl: 'http://pos.test/storage/logo.png',
          licensePlanType: 'premium',
          features: FeatureFlags(suppliers: true, multiRubro: true),
        );
  }

  void setSettings(BusinessSettings? newSettings) {
    _settings = newSettings;
    notifyListeners();
  }

  @override
  BusinessSettings? get settings => _settings;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => _settings?.licensePlanType ?? 'premium';
  @override
  FeatureFlags get features => _settings?.features ?? const FeatureFlags(suppliers: true, multiRubro: true);
  @override
  bool hasFeature(String featureName) => true;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCatalogRepoForR2 implements CatalogRepository {
  @override
  Future<List<Brand>> getBrands() async => [Brand(id: 1, name: 'Marca 1')];
  @override
  Future<List<Category>> getCategories() async => [Category(id: 1, name: 'Cat 1')];
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

class FakeSupplierProviderForR2 extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchSuppliers({String? search}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─── TEST PRODUCTS ──────────────────────────────────────────────────────────

final regularProductWithImage = Product(
  id: 201,
  name: 'Gaseosa Cola 2.25L',
  barcode: '7791234567890',
  internalCode: 'GAS01',
  costPrice: 500.0,
  sellingPrice: 1200.0,
  stock: 40.0,
  active: true,
  isSoldByWeight: false,
  imageUrl: 'http://pos.test/storage/products/cola.png',
  salesCount: 150,
);

final extremeProductStress = Product(
  id: 202,
  name: 'Cerveza Artesanal Imperial Extra Stout Edición Especial Doble Lúpulo Botella de Vidrio Premium 1000ml',
  barcode: '7799999999999',
  internalCode: 'CERV99',
  costPrice: 500000.0,
  sellingPrice: 999999999.0,
  stock: 9999.0,
  active: true,
  isSoldByWeight: false,
  imageUrl: 'http://pos.test/storage/products/extreme.png',
  salesCount: 99999,
);

final weighedProduct = Product(
  id: 203,
  name: 'Manzanas Rojas Seleccionadas Extra Jugosas',
  internalCode: 'MANZ01',
  costPrice: 800.0,
  sellingPrice: 1500.0,
  stock: 120.5,
  active: true,
  isSoldByWeight: true,
  imageUrl: 'http://pos.test/storage/products/apples.png',
  salesCount: 300,
);

final productWithoutImage = Product(
  id: 204,
  name: 'Galletitas Dulces Sin Foto',
  internalCode: 'GAL01',
  costPrice: 200.0,
  sellingPrice: 400.0,
  stock: 20.0,
  active: true,
  isSoldByWeight: false,
  imageUrl: null,
);

final productWithEmptyImage = Product(
  id: 205,
  name: 'Alfajor Sin Foto Url Vacia',
  internalCode: 'ALF01',
  costPrice: 150.0,
  sellingPrice: 300.0,
  stock: 10.0,
  active: true,
  isSoldByWeight: false,
  imageUrl: '',
);

// ─── MAIN TEST SUITE ────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildQuickAccessApp({
    required List<Product> products,
    required String viewMode,
    required Size size,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: size),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: PosQuickAccessCatalogView(
              products: products,
              viewMode: viewMode,
            ),
          ),
        ),
      ),
    );
  }

  group('R2 Adversarial: POS Quick Access Grid Cards Layout & Overflows Stress', () {
    const resolutions = [
      Size(320, 480),   // Compact mobile portrait
      Size(768, 1024),  // Tablet portrait
      Size(1920, 1080), // Desktop Full HD
    ];

    for (final res in resolutions) {
      testWidgets('Resolution ${res.width.toInt()}x${res.height.toInt()}: grid_medium renders with 0 RenderFlex overflows', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildQuickAccessApp(
          products: [
            regularProductWithImage,
            extremeProductStress,
            weighedProduct,
            productWithoutImage,
            productWithEmptyImage,
          ],
          viewMode: 'grid_medium',
          size: res,
        ));
        await tester.pump();

        // Must not throw any RenderFlex overflow exception
        expect(tester.takeException(), isNull);

        // CachedNetworkImage should be present for items with image
        final images = find.byType(CachedNetworkImage);
        expect(images, findsWidgets);

        // Verify CachedNetworkImage fit is BoxFit.contain and width/height are double.infinity
        final firstImage = tester.widget<CachedNetworkImage>(images.first);
        expect(firstImage.fit, BoxFit.contain);
        expect(firstImage.width, double.infinity);
        expect(firstImage.height, double.infinity);

        // Fallback icons should be present for products without image
        expect(find.byIcon(Icons.inventory_2_outlined), findsWidgets);
      });

      testWidgets('Resolution ${res.width.toInt()}x${res.height.toInt()}: grid_large renders with 0 RenderFlex overflows', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildQuickAccessApp(
          products: [
            regularProductWithImage,
            extremeProductStress,
            weighedProduct,
            productWithoutImage,
            productWithEmptyImage,
          ],
          viewMode: 'grid_large',
          size: res,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);

        final images = find.byType(CachedNetworkImage);
        expect(images, findsWidgets);

        final firstImage = tester.widget<CachedNetworkImage>(images.first);
        expect(firstImage.fit, BoxFit.contain);
        expect(firstImage.width, double.infinity);
        expect(firstImage.height, double.infinity);
      });
    }

    testWidgets('POS Grid Card fallback icons render cleanly for weighed vs unit products without images', (tester) async {
      await tester.pumpWidget(buildQuickAccessApp(
        products: [
          productWithoutImage,
          Product(
            id: 206,
            name: 'Pera Sin Foto',
            internalCode: 'PERA01',
            costPrice: 400.0,
            sellingPrice: 800.0,
            stock: 15.0,
            active: true,
            isSoldByWeight: true,
            imageUrl: null,
          ),
        ],
        viewMode: 'grid_medium',
        size: const Size(800, 600),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Unit product gets inventory icon
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
      // Weighed product gets scale icon
      expect(find.byIcon(Icons.scale_rounded), findsOneWidget);
    });
  });

  group('R2 Adversarial: ProductFormDialog UX & Responsive Layout Stress', () {
    Widget buildDialogTestApp({
      required Size size,
      Product? product,
    }) {
      final fakeRepo = FakeCatalogRepoForR2();
      final catalogProvider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(fakeRepo),
        repository: fakeRepo,
      );

      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
          ChangeNotifierProvider<SettingsProvider>(create: (_) => MockSettingsProvider()),
          ChangeNotifierProvider<SupplierProvider>(create: (_) => FakeSupplierProviderForR2()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(size: size),
              child: Builder(
                builder: (ctx) => Center(
                  child: ProductFormDialog(
                    provider: catalogProvider,
                    product: product,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Compact Viewport 320x480: ProductFormDialog renders vertical column without horizontal overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDialogTestApp(size: const Size(320, 480)));
      await tester.pump();

      // Zero RenderFlex overflows
      expect(tester.takeException(), isNull);

      // In compact viewport (< 450), image container width is 80x80
      final imageBoxFinder = find.byKey(const ValueKey('product_image_container'));
      expect(imageBoxFinder, findsOneWidget);

      final containerWidget = tester.widget<Container>(imageBoxFinder);
      expect(containerWidget.constraints?.maxWidth, 80.0);

      // Form fields are present and accessible
      expect(find.text('Nombre del Producto *'), findsOneWidget);
      expect(find.text('PLU (Interno) *'), findsOneWidget);
    });

    testWidgets('Wide Viewport 1920x1080: ProductFormDialog renders side-by-side row (image picker on left) without overflow', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDialogTestApp(size: const Size(1920, 1080)));
      await tester.pump();

      expect(tester.takeException(), isNull);

      final imageBoxFinder = find.byKey(const ValueKey('product_image_container'));
      expect(imageBoxFinder, findsOneWidget);

      // Verify layout: Image picker container is to the left of the Name field
      final imageBoxTopLeft = tester.getTopLeft(imageBoxFinder);
      final nameFieldTopLeft = tester.getTopLeft(find.widgetWithText(TextFormField, 'Nombre del Producto *'));

      // The image picker X coordinate must be to the left of the Name field X coordinate
      expect(imageBoxTopLeft.dx, lessThan(nameFieldTopLeft.dx));

      // Title shows "Nuevo Producto"
      expect(find.text('Nuevo Producto'), findsOneWidget);
    });

    testWidgets('Editing existing product shows existing photo and details side-by-side without overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDialogTestApp(
        size: const Size(1280, 800),
        product: regularProductWithImage,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Editar Producto'), findsOneWidget);
      expect(find.text('Gaseosa Cola 2.25L'), findsOneWidget);

      final imageBoxFinder = find.byKey(const ValueKey('product_image_container'));
      expect(imageBoxFinder, findsOneWidget);
      final imageBoxTopLeft = tester.getTopLeft(imageBoxFinder);
      final nameFieldTopLeft = tester.getTopLeft(find.text('Gaseosa Cola 2.25L'));
      expect(imageBoxTopLeft.dx, lessThan(nameFieldTopLeft.dx));
    });
  });

  group('R2 Adversarial: PosWatermarkLogo & Touch Passthrough Stress', () {
    Widget buildWatermarkApp({
      required SettingsProvider settingsProvider,
      double size = 180,
      Widget? backgroundAction,
    }) {
      return ChangeNotifierProvider<SettingsProvider>.value(
        value: settingsProvider,
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              alignment: Alignment.center,
              children: [
                if (backgroundAction != null) backgroundAction,
                PosWatermarkLogo(size: size),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('PosWatermarkLogo renders store icon fallback with 0.1 opacity when logoUrl is null', (tester) async {
      final mockSettings = MockSettingsProvider(
        initialSettings: const BusinessSettings(
          companyName: 'Comercio Sin Logo',
          logoUrl: null,
          logoPath: null,
        ),
      );

      await tester.pumpWidget(buildWatermarkApp(settingsProvider: mockSettings));
      await tester.pump();

      expect(tester.takeException(), isNull);

      final opacityFinder = find.byType(Opacity);
      expect(opacityFinder, findsOneWidget);
      final opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, 0.1);

      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('PosWatermarkLogo renders store icon fallback when logoUrl is empty string', (tester) async {
      final mockSettings = MockSettingsProvider(
        initialSettings: const BusinessSettings(
          companyName: 'Comercio Logo Vacio',
          logoUrl: '',
          logoPath: '',
        ),
      );

      await tester.pumpWidget(buildWatermarkApp(settingsProvider: mockSettings));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    });

    testWidgets('PosWatermarkLogo renders CachedNetworkImage when logoUrl is present', (tester) async {
      final mockSettings = MockSettingsProvider(
        initialSettings: const BusinessSettings(
          companyName: 'Comercio Con Logo',
          logoUrl: 'http://pos.test/storage/branding/logo.png',
        ),
      );

      await tester.pumpWidget(buildWatermarkApp(settingsProvider: mockSettings));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final cachedFinder = find.byType(CachedNetworkImage);
      expect(cachedFinder, findsOneWidget);

      final cached = tester.widget<CachedNetworkImage>(cachedFinder);
      expect(cached.fit, BoxFit.contain);
      expect(cached.imageUrl, 'http://pos.test/storage/branding/logo.png');
    });

    testWidgets('PosWatermarkLogo uses IgnorePointer: touches pass through to underlying buttons without obstruction', (tester) async {
      bool buttonClicked = false;
      final mockSettings = MockSettingsProvider(
        initialSettings: const BusinessSettings(
          companyName: 'Comercio Watermark',
          logoUrl: 'http://pos.test/storage/branding/logo.png',
        ),
      );

      await tester.pumpWidget(buildWatermarkApp(
        settingsProvider: mockSettings,
        size: 200,
        backgroundAction: ElevatedButton(
          key: const Key('covered_button'),
          onPressed: () => buttonClicked = true,
          child: const Text('Boton Detras'),
        ),
      ));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(PosWatermarkLogo),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );

      // Tap precisely at the center of the watermark (touches pass through to underlying button)
      await tester.tap(find.byType(PosWatermarkLogo), warnIfMissed: false);
      await tester.pump();

      // The button underneath must receive the click event!
      expect(buttonClicked, isTrue);
    });

    testWidgets('Empty POS Cart watermark layout renders cleanly at 320x480, 768x1024, 1920x1080 with 0 overflows', (tester) async {
      final resolutions = [
        const Size(320, 480),
        const Size(768, 1024),
        const Size(1920, 1080),
      ];

      final mockSettings = MockSettingsProvider(
        initialSettings: const BusinessSettings(
          companyName: 'Test Market',
          logoUrl: 'http://pos.test/storage/branding/logo.png',
        ),
      );

      for (final res in resolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ChangeNotifierProvider<SettingsProvider>.value(
            value: mockSettings,
            child: const MaterialApp(
              home: Scaffold(
                body: Stack(
                  alignment: Alignment.center,
                  children: [
                    PosWatermarkLogo(size: 160),
                    Center(
                      child: Text('El carrito está vacío', style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('El carrito está vacío'), findsOneWidget);
        expect(find.byType(PosWatermarkLogo), findsOneWidget);
      }
    });

    testWidgets('Empty POS Catalog Grid watermark layout renders cleanly at 320x480, 768x1024, 1920x1080 with 0 overflows', (tester) async {
      final resolutions = [
        const Size(320, 480),
        const Size(768, 1024),
        const Size(1920, 1080),
      ];

      final mockSettings = MockSettingsProvider(
        initialSettings: const BusinessSettings(
          companyName: 'Test Market',
          logoUrl: 'http://pos.test/storage/branding/logo.png',
        ),
      );

      for (final res in resolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ChangeNotifierProvider<SettingsProvider>.value(
            value: mockSettings,
            child: const MaterialApp(
              home: Scaffold(
                body: Stack(
                  alignment: Alignment.center,
                  children: [
                    PosWatermarkLogo(size: 240),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 56, color: Colors.grey),
                          SizedBox(height: 12),
                          Text(
                            'No hay productos en el catálogo.',
                            style: TextStyle(color: Colors.grey, fontSize: 15),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('No hay productos en el catálogo.'), findsOneWidget);
        expect(find.byType(PosWatermarkLogo), findsOneWidget);
      }
    });
  });
}
