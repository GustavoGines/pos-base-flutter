import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_access_view.dart';
import 'package:frontend_desktop/features/pos/presentation/pages/pos_screen.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// ─── MOCK SETTINGS PROVIDER ─────────────────────────────────────────────────

class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings? _settings;

  MockSettingsProvider({BusinessSettings? initialSettings}) {
    _settings = initialSettings ??
        const BusinessSettings(
          companyName: 'Supermercado Test',
          logoUrl: 'http://pos.test/storage/branding/logo.png',
          licensePlanType: 'premium',
          features: FeatureFlags(suppliers: true, multiRubro: true),
        );
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
  FeatureFlags get features =>
      _settings?.features ?? const FeatureFlags(suppliers: true, multiRubro: true);
  @override
  bool hasFeature(String featureName) => true;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─── TEST PRODUCTS FACTORY ──────────────────────────────────────────────────

Product createProduct({
  required int id,
  required String name,
  String? imageUrl,
  bool isSoldByWeight = false,
  double price = 100.0,
  int salesCount = 0,
}) {
  return Product(
    id: id,
    name: name,
    internalCode: 'PRD-$id',
    barcode: '779000000$id',
    costPrice: price * 0.7,
    sellingPrice: price,
    stock: 50,
    active: true,
    isSoldByWeight: isSoldByWeight,
    salesCount: salesCount,
    imageUrl: imageUrl,
  );
}

// ─── HARNESS BUILDERS ───────────────────────────────────────────────────────

Widget buildQuickAccessApp({
  required List<Product> products,
  required String viewMode,
  ValueChanged<Product>? onSelect,
  Size viewport = const Size(1024, 768),
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(size: viewport),
        child: SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: PosQuickAccessCatalogView(
            products: products,
            viewMode: viewMode,
            onSelectProduct: onSelect,
          ),
        ),
      ),
    ),
  );
}

Widget buildWatermarkedCatalogHarness({
  required List<Product> products,
  required String viewMode,
  ValueChanged<Product>? onSelect,
  Size viewport = const Size(1024, 768),
  SettingsProvider? settingsProvider,
}) {
  final provider = settingsProvider ?? MockSettingsProvider();
  return ChangeNotifierProvider<SettingsProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: viewport),
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: PosWatermarkLogo(size: 360),
                ),
                PosQuickAccessCatalogView(
                  products: products,
                  viewMode: viewMode,
                  onSelectProduct: onSelect,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Adversarial Challenge 1: Mathematical & Geometry Verification (BoxFit.contain vs BoxFit.cover)', () {
    test('1:10 Tall Vertical Image: BoxFit.contain guarantees 100% uncropped display and preserves aspect ratio', () {
      const inputSize = Size(100, 1000); // 1:10 aspect ratio
      const outputBox = Size(180, 100);  // Card header viewport

      // Evaluate BoxFit.contain
      final containSizes = applyBoxFit(BoxFit.contain, inputSize, outputBox);

      // In contain mode:
      // - sourceSize MUST equal inputSize (100% visible, 0% cropped)
      expect(containSizes.source, equals(inputSize));
      expect(containSizes.destination.width, closeTo(10.0, 0.001));
      expect(containSizes.destination.height, closeTo(100.0, 0.001));

      // Destination aspect ratio must precisely match source aspect ratio
      final inputRatio = inputSize.width / inputSize.height;
      final destRatio = containSizes.destination.width / containSizes.destination.height;
      expect(destRatio, closeTo(inputRatio, 0.0001));

      // Contrast with BoxFit.cover
      final coverSizes = applyBoxFit(BoxFit.cover, inputSize, outputBox);
      expect(coverSizes.source.width, closeTo(100.0, 0.001));
      // In cover mode, source height is cropped down to 55.55px (94.4% cropped!)
      expect(coverSizes.source.height, closeTo(55.555, 0.01));
      expect(coverSizes.source.height, lessThan(inputSize.height * 0.1));
    });

    test('10:1 Wide Panoramic Image: BoxFit.contain guarantees 100% uncropped display and preserves aspect ratio', () {
      const inputSize = Size(1000, 100); // 10:1 aspect ratio
      const outputBox = Size(180, 100);  // Card header viewport

      final containSizes = applyBoxFit(BoxFit.contain, inputSize, outputBox);

      // Source is 100% uncropped
      expect(containSizes.source, equals(inputSize));
      expect(containSizes.destination.width, closeTo(180.0, 0.001));
      expect(containSizes.destination.height, closeTo(18.0, 0.001));

      final inputRatio = inputSize.width / inputSize.height;
      final destRatio = containSizes.destination.width / containSizes.destination.height;
      expect(destRatio, closeTo(inputRatio, 0.0001));
    });

    test('1:1 Square Image: BoxFit.contain preserves symmetry without distortion or clipping', () {
      const inputSize = Size(500, 500); // 1:1 square
      const outputBox = Size(180, 120);

      final containSizes = applyBoxFit(BoxFit.contain, inputSize, outputBox);

      expect(containSizes.source, equals(inputSize));
      expect(containSizes.destination.width, closeTo(120.0, 0.001));
      expect(containSizes.destination.height, closeTo(120.0, 0.001));
      expect(containSizes.destination.width, equals(containSizes.destination.height));
    });

    test('Extreme 1:100 needle and 100:1 ribbon aspect ratios preserve geometry under BoxFit.contain', () {
      const needleSize = Size(10, 1000);
      const ribbonSize = Size(1000, 10);
      const outputBox = Size(150, 150);

      final needleFitted = applyBoxFit(BoxFit.contain, needleSize, outputBox);
      expect(needleFitted.source, equals(needleSize));
      expect(needleFitted.destination.height, equals(150.0));
      expect(needleFitted.destination.width, closeTo(1.5, 0.001));

      final ribbonFitted = applyBoxFit(BoxFit.contain, ribbonSize, outputBox);
      expect(ribbonFitted.source, equals(ribbonSize));
      expect(ribbonFitted.destination.width, equals(150.0));
      expect(ribbonFitted.destination.height, closeTo(1.5, 0.001));
    });
  });

  group('Adversarial Challenge 2: Widget Tree Property Assertions (grid_medium & grid_large)', () {
    final extremeProducts = [
      createProduct(id: 1, name: 'Vertical 1:10', imageUrl: 'http://pos.test/img/tall_vertical.jpg'),
      createProduct(id: 2, name: 'Panoramic 10:1', imageUrl: 'http://pos.test/img/wide_panoramic.jpg'),
      createProduct(id: 3, name: 'Square 1:1', imageUrl: 'http://pos.test/img/square.jpg'),
      createProduct(id: 4, name: 'Weighed Item', imageUrl: 'http://pos.test/img/weighed.jpg', isSoldByWeight: true),
    ];

    testWidgets('grid_medium: All CachedNetworkImages have BoxFit.contain, width double.infinity, height double.infinity', (tester) async {
      await tester.pumpWidget(buildQuickAccessApp(
        products: extremeProducts,
        viewMode: 'grid_medium',
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);

      final imageFinders = find.byType(CachedNetworkImage);
      expect(imageFinders, findsNWidgets(4));

      for (int i = 0; i < 4; i++) {
        final imageWidget = tester.widget<CachedNetworkImage>(imageFinders.at(i));
        expect(imageWidget.fit, equals(BoxFit.contain),
            reason: 'Item $i in grid_medium MUST use BoxFit.contain');
        expect(imageWidget.width, equals(double.infinity));
        expect(imageWidget.height, equals(double.infinity));
      }
    });

    testWidgets('grid_large: All CachedNetworkImages have BoxFit.contain, width double.infinity, height double.infinity', (tester) async {
      await tester.pumpWidget(buildQuickAccessApp(
        products: extremeProducts,
        viewMode: 'grid_large',
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);

      final imageFinders = find.byType(CachedNetworkImage);
      expect(imageFinders, findsNWidgets(4));

      for (int i = 0; i < 4; i++) {
        final imageWidget = tester.widget<CachedNetworkImage>(imageFinders.at(i));
        expect(imageWidget.fit, equals(BoxFit.contain),
            reason: 'Item $i in grid_large MUST use BoxFit.contain');
        expect(imageWidget.width, equals(double.infinity));
        expect(imageWidget.height, equals(double.infinity));
      }
    });

    testWidgets('Unspecified/Fallback viewMode defaults to grid_large with BoxFit.contain', (tester) async {
      await tester.pumpWidget(buildQuickAccessApp(
        products: extremeProducts.sublist(0, 2),
        viewMode: 'non_existent_mode_xyz',
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);

      final imageFinders = find.byType(CachedNetworkImage);
      expect(imageFinders, findsNWidgets(2));
      final imageWidget = tester.widget<CachedNetworkImage>(imageFinders.first);
      expect(imageWidget.fit, equals(BoxFit.contain));
    });
  });

  group('Adversarial Challenge 3: Boundary Edge Cases in URLs (null, empty, whitespace, malformed)', () {
    final edgeCaseProducts = [
      createProduct(id: 10, name: 'Null URL', imageUrl: null, isSoldByWeight: false),
      createProduct(id: 11, name: 'Weighed Null URL', imageUrl: null, isSoldByWeight: true),
      createProduct(id: 12, name: 'Empty String URL', imageUrl: '', isSoldByWeight: false),
      createProduct(id: 13, name: 'Whitespace URL', imageUrl: '   ', isSoldByWeight: false),
      createProduct(id: 14, name: 'Local File URL without host', imageUrl: 'file:///images/prod.jpg', isSoldByWeight: false),
      createProduct(id: 15, name: 'Scheme-less URL', imageUrl: 'not_a_url_at_all', isSoldByWeight: false),
      createProduct(id: 16, name: 'Relative URL', imageUrl: '/storage/products/item.jpg', isSoldByWeight: false),
      createProduct(id: 17, name: 'Valid Public URL with Query & Fragment', imageUrl: 'https://cdn.example.com/item.png?v=2#details', isSoldByWeight: false),
    ];

    testWidgets('Only valid absolute HTTP/HTTPS URIs instantiate CachedNetworkImage; all invalid/null URLs safely fallback to icons', (tester) async {
      await tester.pumpWidget(buildQuickAccessApp(
        products: edgeCaseProducts,
        viewMode: 'grid_large',
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);

      // Only 1 product has a valid authority & scheme (id: 17)
      final imageFinder = find.byType(CachedNetworkImage);
      expect(imageFinder, findsOneWidget);
      final validImage = tester.widget<CachedNetworkImage>(imageFinder);
      expect(validImage.imageUrl, 'https://cdn.example.com/item.png?v=2#details');
      expect(validImage.fit, BoxFit.contain);

      // Unit fallbacks (6 items: 10, 12, 13, 14, 15, 16)
      expect(find.byIcon(Icons.inventory_2_outlined), findsNWidgets(6));

      // Weighed fallback (1 item: 11)
      expect(find.byIcon(Icons.scale_rounded), findsOneWidget);
    });
  });

  group('Adversarial Challenge 4: View Mode Switching & Rapid Transitions', () {
    final testProducts = [
      createProduct(id: 1, name: 'Product Alpha', imageUrl: 'http://pos.test/alpha.png'),
      createProduct(id: 2, name: 'Product Beta', imageUrl: null, isSoldByWeight: true),
      createProduct(id: 3, name: 'Product Gamma', imageUrl: 'http://pos.test/gamma.png'),
    ];

    const allModes = ['list', 'compact', 'grid_medium', 'grid_large'];

    testWidgets('Rapidly cycling through all view modes with POPULATED catalog produces zero exceptions or layout tears', (tester) async {
      for (final mode in allModes) {
        await tester.pumpWidget(buildQuickAccessApp(
          products: testProducts,
          viewMode: mode,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'Failed during transition to mode: $mode');

        // All 3 product names must be rendered
        expect(find.text('Product Alpha'), findsOneWidget);
        expect(find.text('Product Beta'), findsOneWidget);
        expect(find.text('Product Gamma'), findsOneWidget);
      }

      // Reverse cycle
      for (final mode in allModes.reversed) {
        await tester.pumpWidget(buildQuickAccessApp(
          products: testProducts,
          viewMode: mode,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Rapidly cycling through all view modes with EMPTY catalog produces zero exceptions', (tester) async {
      for (final mode in allModes) {
        await tester.pumpWidget(buildQuickAccessApp(
          products: [],
          viewMode: mode,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'Failed during empty transition to mode: $mode');
        expect(find.byType(CachedNetworkImage), findsNothing);
      }
    });

    testWidgets('Single product catalog transitions cleanly across all 4 modes', (tester) async {
      final single = [testProducts.first];
      for (final mode in allModes) {
        await tester.pumpWidget(buildQuickAccessApp(
          products: single,
          viewMode: mode,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Product Alpha'), findsOneWidget);
      }
    });
  });

  group('Adversarial Challenge 5: Watermark Stack Coexistence & Tap Responsiveness under Extreme Images', () {
    final extremeProducts = [
      createProduct(id: 101, name: 'Tall 1:10 Item', imageUrl: 'http://pos.test/tall.png'),
      createProduct(id: 102, name: 'Wide 10:1 Item', imageUrl: 'http://pos.test/wide.png'),
    ];

    testWidgets('Watermark is present behind cards and taps on extreme aspect ratio cards trigger onSelectProduct', (tester) async {
      Product? selected;
      await tester.pumpWidget(buildWatermarkedCatalogHarness(
        products: extremeProducts,
        viewMode: 'grid_large',
        onSelect: (p) => selected = p,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);

      // PosWatermarkLogo exists in stack
      expect(find.byType(PosWatermarkLogo), findsOneWidget);

      // Tap on first card
      await tester.tap(find.text('Tall 1:10 Item'));
      await tester.pump();

      expect(selected, isNotNull);
      expect(selected!.id, 101);

      // Tap on second card
      await tester.tap(find.text('Wide 10:1 Item'));
      await tester.pump();

      expect(selected!.id, 102);
    });

    testWidgets('Zero RenderFlex overflows across 6 viewport resolutions from 320x480 to 1920x1080 with extreme products', (tester) async {
      const resolutions = [
        Size(320, 480),   // Extreme low mobile
        Size(360, 640),   // Standard mobile
        Size(768, 1024),  // Tablet
        Size(1024, 768),  // Low-res POS terminal
        Size(1280, 900),  // Standard desktop POS
        Size(1920, 1080), // Full HD POS
      ];

      for (final res in resolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        for (final mode in ['grid_medium', 'grid_large', 'compact', 'list']) {
          await tester.pumpWidget(buildWatermarkedCatalogHarness(
            products: extremeProducts,
            viewMode: mode,
            viewport: res,
          ));
          await tester.pump();

          expect(
            tester.takeException(),
            isNull,
            reason: 'Overflow in mode $mode at resolution ${res.width.toInt()}x${res.height.toInt()}',
          );
        }
      }
    });
  });

  group('Adversarial Challenge 6: Stress Test with 60 Mixed Extreme Items', () {
    testWidgets('Stress test: 60 items with alternating extreme aspect ratios, null URLs, weights, and sales badges render cleanly', (tester) async {
      final bigList = List.generate(60, (index) {
        final mod = index % 5;
        String? url;
        if (mod == 0) url = 'http://pos.test/img/tall_$index.jpg';
        if (mod == 1) url = 'http://pos.test/img/wide_$index.jpg';
        if (mod == 2) url = 'http://pos.test/img/square_$index.jpg';
        if (mod == 3) url = null;
        if (mod == 4) url = '';

        return createProduct(
          id: 1000 + index,
          name: 'Item Stress #$index',
          imageUrl: url,
          isSoldByWeight: index % 3 == 0,
          salesCount: (index % 4 == 0) ? 25 : 0,
          price: (index + 1) * 50.0,
        );
      });

      await tester.pumpWidget(buildWatermarkedCatalogHarness(
        products: bigList,
        viewMode: 'grid_medium',
        viewport: const Size(1280, 900),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);

      // Scroll down through grid
      await tester.drag(find.byType(GridView), const Offset(0, -600));
      await tester.pump();

      expect(tester.takeException(), isNull);

      // Scroll up
      await tester.drag(find.byType(GridView), const Offset(0, 600));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
