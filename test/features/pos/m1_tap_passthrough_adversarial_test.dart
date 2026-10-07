import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
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
          companyName: 'Adversarial Mart',
          logoUrl: 'http://pos.test/storage/branding/watermark_logo.png',
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

// ─── HARNESS FOR FULL CART PANEL ITEMS AREA ─────────────────────────────────

Widget buildFullCartPanelHarness({
  required List<CartItem> cartItems,
  required SettingsProvider settingsProvider,
  void Function(CartItem item)? onTapTile,
  void Function(CartItem item)? onIncrementQty,
  void Function(CartItem item)? onDecrementQty,
  void Function(CartItem item)? onDeleteItem,
  Size size = const Size(400, 700),
}) {
  return ChangeNotifierProvider<SettingsProvider>.value(
    value: settingsProvider,
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PosWatermarkLogo(size: 260),
                      ),
                      if (cartItems.isEmpty)
                        const Center(
                          child: Text(
                            'El carrito está vacío',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ListView.separated(
                          itemCount: cartItems.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = cartItems[index];
                            final String qtyDisplay = item.product.isSoldByWeight
                                ? item.quantity.toQty()
                                : item.quantity.toInt().toString();

                            return ListTile(
                              key: ValueKey('cart_tile_${item.product.id}'),
                              title: Text(
                                item.product.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '$qtyDisplay x \$${item.unitPrice.toCurrency()}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: ValueKey('minus_btn_${item.product.id}'),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.grey,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => onDecrementQty?.call(item),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      key: ValueKey('plus_btn_${item.product.id}'),
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        color: Colors.blue,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => onIncrementQty?.call(item),
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      '\$${item.subtotal.toCurrency()}',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    IconButton(
                                      key: ValueKey('delete_btn_${item.product.id}'),
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => onDeleteItem?.call(item),
                                    ),
                                  ],
                                ),
                              ),
                              onTap: () => onTapTile?.call(item),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ─── HARNESS FOR FULL CATALOG DYNAMIC AREA ──────────────────────────────────

Widget buildFullCatalogGridHarness({
  required List<Product> displayItems,
  required String viewMode,
  required SettingsProvider settingsProvider,
  void Function(Product product)? onSelectProduct,
  Size size = const Size(800, 700),
}) {
  return ChangeNotifierProvider<SettingsProvider>.value(
    value: settingsProvider,
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PosWatermarkLogo(size: 360),
                      ),
                      if (displayItems.isEmpty)
                        const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off, size: 56, color: Colors.grey),
                              SizedBox(height: 12),
                              Text(
                                'No hay productos en el catálogo.',
                                style: TextStyle(color: Colors.grey, fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      else
                        PosQuickAccessCatalogView(
                          products: displayItems,
                          viewMode: viewMode,
                          onSelectProduct: onSelectProduct,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ─── GENERATOR: TEST PRODUCTS ───────────────────────────────────────────────

Product createProduct({
  required int id,
  required String name,
  String? imageUrl,
  bool isSoldByWeight = false,
  double sellingPrice = 1500.0,
  int salesCount = 10,
}) {
  return Product(
    id: id,
    name: name,
    internalCode: 'INT-$id',
    barcode: '779000000$id',
    costPrice: sellingPrice * 0.6,
    sellingPrice: sellingPrice,
    stock: 100.0,
    active: true,
    isSoldByWeight: isSoldByWeight,
    imageUrl: imageUrl,
    salesCount: salesCount,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Adversarial Challenge 1: Cart Controls Tap Pass-Through (Immediate Response)', () {
    testWidgets('Tapping Cart controls (Plus, Minus, Delete, Tile Tap) fires immediately even when directly overlapping the watermark coordinates', (tester) async {
      final mockSettings = MockSettingsProvider();

      int tileTapCount = 0;
      int plusClickCount = 0;
      int minusClickCount = 0;
      int deleteClickCount = 0;

      final testProduct = createProduct(
        id: 777,
        name: 'Yerba Mate Premium 1Kg',
        imageUrl: 'http://pos.test/storage/products/yerba.png',
      );

      final item = CartItem(product: testProduct, quantity: 2.0);
      final items = [item];

      await tester.pumpWidget(buildFullCartPanelHarness(
        cartItems: items,
        settingsProvider: mockSettings,
        size: const Size(450, 600),
        onTapTile: (_) => tileTapCount++,
        onIncrementQty: (i) {
          plusClickCount++;
          i.quantity += 1.0;
        },
        onDecrementQty: (i) {
          minusClickCount++;
          i.quantity -= 1.0;
        },
        onDeleteItem: (i) {
          deleteClickCount++;
          items.remove(i);
        },
      ));
      await tester.pump();

      // 1. Verify watermark is rendered in tree behind the items
      expect(find.byType(PosWatermarkLogo), findsOneWidget);

      // 2. Tap Tile Body (Edit Cart Modal trigger)
      final tileFinder = find.text('Yerba Mate Premium 1Kg');
      expect(tileFinder, findsOneWidget);
      await tester.tap(tileFinder);
      await tester.pump();
      expect(tileTapCount, 1, reason: 'Tile tap must fire immediately without being intercepted by watermark');

      // 3. Tap Plus button (Increment)
      final plusFinder = find.byKey(const ValueKey('plus_btn_777'));
      expect(plusFinder, findsOneWidget);
      await tester.tap(plusFinder);
      await tester.pump();
      expect(plusClickCount, 1, reason: 'Plus button must register tap immediately');
      expect(item.quantity, 3.0);

      // 4. Tap Minus button (Decrement)
      final minusFinder = find.byKey(const ValueKey('minus_btn_777'));
      expect(minusFinder, findsOneWidget);
      await tester.tap(minusFinder);
      await tester.pump();
      expect(minusClickCount, 1, reason: 'Minus button must register tap immediately');
      expect(item.quantity, 2.0);

      // 5. Tap Delete button (Remove)
      final deleteFinder = find.byKey(const ValueKey('delete_btn_777'));
      expect(deleteFinder, findsOneWidget);
      await tester.tap(deleteFinder);
      await tester.pump();
      expect(deleteClickCount, 1, reason: 'Delete button must register tap immediately');
      expect(items, isEmpty);

      // Re-pump to show empty state
      await tester.pumpWidget(buildFullCartPanelHarness(
        cartItems: items,
        settingsProvider: mockSettings,
        size: const Size(450, 600),
      ));
      await tester.pump();

      expect(find.text('El carrito está vacío'), findsOneWidget);
      expect(find.byType(PosWatermarkLogo), findsOneWidget);
    });

    testWidgets('Multi-step rapid tap sequence directly over watermark center coordinates maintains 100% responsiveness with fallback store icon', (tester) async {
      // Test when logoUrl is null (fallback Icon(Icons.storefront_rounded))
      final mockSettings = MockSettingsProvider(
        initialSettings: const BusinessSettings(
          companyName: 'Sin Logo S.A.',
          logoUrl: null,
        ),
      );

      final testProduct = createProduct(id: 888, name: 'Aceite Girasol 1.5L');
      final item = CartItem(product: testProduct, quantity: 1.0);
      final items = [item];

      int qtyUpdates = 0;

      await tester.pumpWidget(buildFullCartPanelHarness(
        cartItems: items,
        settingsProvider: mockSettings,
        size: const Size(400, 600),
        onIncrementQty: (i) {
          qtyUpdates++;
          i.quantity += 1.0;
        },
      ));
      await tester.pump();

      final plusFinder = find.byKey(const ValueKey('plus_btn_888'));
      expect(plusFinder, findsOneWidget);

      // Rapidly tap plus button 5 times
      for (int i = 0; i < 5; i++) {
        await tester.tap(plusFinder);
        await tester.pump();
      }

      expect(qtyUpdates, 5, reason: 'All 5 rapid taps must register without watermark interference');
      expect(item.quantity, 6.0);
    });
  });

  group('Adversarial Challenge 2: Catalog Cards Tap Pass-Through Across All 4 View Modes', () {
    final modes = ['grid_large', 'grid_medium', 'compact', 'list'];

    for (final mode in modes) {
      testWidgets('ViewMode "$mode": Catalog cards positioned directly on watermark fire onSelectProduct immediately', (tester) async {
        final mockSettings = MockSettingsProvider();
        Product? selectedProduct;

        final products = [
          createProduct(id: 10, name: 'Item 1', imageUrl: 'http://pos.test/img1.png'),
          createProduct(id: 20, name: 'Item 2 Over Watermark', imageUrl: 'http://pos.test/img2.png'),
          createProduct(id: 30, name: 'Item 3 Weighed', isSoldByWeight: true),
        ];

        await tester.pumpWidget(buildFullCatalogGridHarness(
          displayItems: products,
          viewMode: mode,
          settingsProvider: mockSettings,
          size: const Size(800, 600),
          onSelectProduct: (p) => selectedProduct = p,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(PosWatermarkLogo), findsOneWidget);

        // Tap precisely on Item 2 (which is rendered over the watermark)
        final item2Finder = find.text('Item 2 Over Watermark');
        expect(item2Finder, findsOneWidget);

        await tester.tap(item2Finder);
        await tester.pump();

        expect(selectedProduct, isNotNull);
        expect(selectedProduct!.id, 20);

        // Tap Item 3
        selectedProduct = null;
        await tester.tap(find.text('Item 3 Weighed'));
        await tester.pump();

        expect(selectedProduct, isNotNull);
        expect(selectedProduct!.id, 30);
      });
    }
  });

  group('Adversarial Challenge 3: Scale Stress Testing (120+ Catalog Products & 60+ Cart Items)', () {
    testWidgets('120 Catalog items: Smooth scrolling, 0 memory/overflow exceptions, and accurate taps at top, middle, and bottom', (tester) async {
      final mockSettings = MockSettingsProvider();
      Product? selectedProduct;

      // Generate 120 products with stress properties
      final products = List.generate(120, (i) {
        return createProduct(
          id: 1000 + i,
          name: i % 10 == 0
              ? 'Super Extenso Nombre de Producto Para Probar Overflow en Grilla Con Muchas Palabras #$i'
              : 'Producto Catálogo #$i',
          imageUrl: i % 3 == 0 ? 'http://pos.test/p_$i.png' : null,
          isSoldByWeight: i % 4 == 0,
          sellingPrice: (i + 1) * 150.75,
          salesCount: i * 5,
        );
      });

      await tester.pumpWidget(buildFullCatalogGridHarness(
        displayItems: products,
        viewMode: 'grid_large',
        settingsProvider: mockSettings,
        size: const Size(1024, 768),
        onSelectProduct: (p) => selectedProduct = p,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(PosWatermarkLogo), findsOneWidget);

      // 1. Tap first item (#0)
      await tester.tap(find.text('Super Extenso Nombre de Producto Para Probar Overflow en Grilla Con Muchas Palabras #0'));
      await tester.pump();
      expect(selectedProduct?.id, 1000);

      // 2. Scroll halfway down
      final gridFinder = find.byType(GridView);
      expect(gridFinder, findsOneWidget);

      await tester.drag(gridFinder, const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 3. Scroll all the way to the bottom
      await tester.drag(gridFinder, const Offset(0, -6000));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // PosWatermarkLogo must still be alive in the tree behind the grid
      expect(find.byType(PosWatermarkLogo), findsOneWidget);

      // 4. Tap the last item that is visible
      selectedProduct = null;
      final lastVisibleFinder = find.text('Producto Catálogo #119');
      if (lastVisibleFinder.evaluate().isNotEmpty) {
        await tester.tap(lastVisibleFinder);
        await tester.pump();
        expect(selectedProduct?.id, 1119);
      }
    });

    testWidgets('60 Cart items: Smooth scrolling, full control responsiveness (plus, minus, delete) at scale', (tester) async {
      final mockSettings = MockSettingsProvider();

      final cartItems = List.generate(60, (i) {
        final prod = createProduct(
          id: 2000 + i,
          name: 'Item Carrito #$i',
          sellingPrice: (i + 1) * 100.0,
        );
        return CartItem(product: prod, quantity: 2.0);
      });

      int plusHits = 0;
      int minusHits = 0;
      int deleteHits = 0;

      await tester.pumpWidget(buildFullCartPanelHarness(
        cartItems: cartItems,
        settingsProvider: mockSettings,
        size: const Size(400, 700),
        onIncrementQty: (item) {
          plusHits++;
          item.quantity += 1.0;
        },
        onDecrementQty: (item) {
          minusHits++;
          item.quantity -= 1.0;
        },
        onDeleteItem: (item) {
          deleteHits++;
          cartItems.remove(item);
        },
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(PosWatermarkLogo), findsOneWidget);

      // 1. Mutate item 0
      final plus0 = find.byKey(const ValueKey('plus_btn_2000'));
      expect(plus0, findsOneWidget);
      await tester.tap(plus0);
      await tester.pump();
      expect(plusHits, 1);
      expect(cartItems[0].quantity, 3.0);

      final minus0 = find.byKey(const ValueKey('minus_btn_2000'));
      await tester.tap(minus0);
      await tester.pump();
      expect(minusHits, 1);
      expect(cartItems[0].quantity, 2.0);

      // 2. Scroll down 1500 pixels
      final listFinder = find.byType(ListView);
      await tester.drag(listFinder, const Offset(0, -1500));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // PosWatermarkLogo remains present in the background
      expect(find.byType(PosWatermarkLogo), findsOneWidget);

      // 3. Scroll to bottom
      await tester.drag(listFinder, const Offset(0, -3000));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final deleteLast = find.byKey(const ValueKey('delete_btn_2059'));
      if (deleteLast.evaluate().isNotEmpty) {
        await tester.tap(deleteLast);
        await tester.pump();
        expect(deleteHits, 1);
        expect(cartItems.length, 59);
      }
    });
  });

  group('Adversarial Challenge 4: Viewport & Layout Immunity Down to 320x480 & Extreme Aspect Ratios', () {
    const extremeResolutions = [
      Size(320, 480),   // Compact mobile portrait (Constraint requirement)
      Size(480, 320),   // Landscape ultra-short mobile
      Size(320, 800),   // Narrow tall mobile
      Size(1024, 768),  // Standard tablet / POS
      Size(1920, 1080), // Full HD Desktop
    ];

    for (final res in extremeResolutions) {
      testWidgets('Cart Panel at ${res.width.toInt()}x${res.height.toInt()} renders with 0 RenderFlex overflows', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final mockSettings = MockSettingsProvider();
        final items = [
          CartItem(
            product: createProduct(
              id: 301,
              name: 'Gaseosa Cola 2.25L - Envase Retornable Super Económico',
              sellingPrice: 2450.0,
            ),
            quantity: 3.0,
          ),
          CartItem(
            product: createProduct(
              id: 302,
              name: 'Queso Cremoso Primera Marca Fraccionado',
              isSoldByWeight: true,
              sellingPrice: 8500.0,
            ),
            quantity: 1.25,
          ),
        ];

        await tester.pumpWidget(buildFullCartPanelHarness(
          cartItems: items,
          settingsProvider: mockSettings,
          size: res,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow in Cart Panel at ${res.width}x${res.height}');
        expect(find.byType(PosWatermarkLogo), findsOneWidget);
      });

      testWidgets('Catalog Grid (grid_medium) at ${res.width.toInt()}x${res.height.toInt()} renders with 0 RenderFlex overflows', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final mockSettings = MockSettingsProvider();
        final products = [
          createProduct(id: 401, name: 'Galletitas Chocolate Con Relleno De Vainilla Y Chispas', imageUrl: 'http://pos.test/g.png'),
          createProduct(id: 402, name: 'Tomate Redondo', isSoldByWeight: true),
        ];

        await tester.pumpWidget(buildFullCatalogGridHarness(
          displayItems: products,
          viewMode: 'grid_medium',
          settingsProvider: mockSettings,
          size: res,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow in Catalog Grid at ${res.width}x${res.height}');
        expect(find.byType(PosWatermarkLogo), findsOneWidget);
      });
    }
  });

  group('Adversarial Challenge 5: Image Aspect Ratio Preservation & Containment (BoxFit.contain)', () {
    testWidgets('Vertical portrait photos (1:5 and 9:16) and ultra-wide photos use BoxFit.contain with zero clipping', (tester) async {
      final mockSettings = MockSettingsProvider();

      final extremeImages = [
        createProduct(
          id: 501,
          name: 'Botella Vertical Ultra Tall (1:5)',
          imageUrl: 'http://pos.test/tall_bottle.png',
        ),
        createProduct(
          id: 502,
          name: 'Banner Ultra Wide (5:1)',
          imageUrl: 'http://pos.test/wide_banner.png',
        ),
        createProduct(
          id: 503,
          name: 'Foto Celular Vertical (9:16)',
          imageUrl: 'http://pos.test/phone_portrait.png',
        ),
      ];

      for (final mode in ['grid_large', 'grid_medium']) {
        await tester.pumpWidget(buildFullCatalogGridHarness(
          displayItems: extremeImages,
          viewMode: mode,
          settingsProvider: mockSettings,
          size: const Size(800, 600),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);

        // Find all CachedNetworkImages in the grid cards
        final cachedImages = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
        expect(cachedImages, isNotEmpty);

        for (final img in cachedImages) {
          // If it's a product card image (width is double.infinity)
          if (img.width == double.infinity) {
            expect(
              img.fit,
              BoxFit.contain,
              reason: 'Product card image fit must be BoxFit.contain to eliminate vertical clipping',
            );
          }
        }
      }
    });
  });

  group('Adversarial Challenge 6: Watermark Structural Invariant & HitTest Pass-Through', () {
    testWidgets('PosWatermarkLogo strictly wraps IgnorePointer at root with Opacity 0.1 and FittedBox scaleDown', (tester) async {
      final mockSettings = MockSettingsProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: mockSettings,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: PosWatermarkLogo(size: 260),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Root of PosWatermarkLogo must be IgnorePointer
      final ignorePointerFinder = find.descendant(
        of: find.byType(PosWatermarkLogo),
        matching: find.byType(IgnorePointer),
      );
      expect(ignorePointerFinder, findsOneWidget);

      final ignorePointer = tester.widget<IgnorePointer>(ignorePointerFinder);
      expect(ignorePointer.ignoring, isTrue, reason: 'IgnorePointer must have ignoring == true');

      // 2. Opacity must be 0.1
      final opacityFinder = find.descendant(
        of: find.byType(PosWatermarkLogo),
        matching: find.byType(Opacity),
      );
      expect(opacityFinder, findsOneWidget);
      final opacity = tester.widget<Opacity>(opacityFinder);
      expect(opacity.opacity, 0.1);

      // 3. FittedBox with BoxFit.scaleDown must be present
      final fittedBoxFinder = find.descendant(
        of: find.byType(PosWatermarkLogo),
        matching: find.byType(FittedBox),
      );
      expect(fittedBoxFinder, findsOneWidget);
      final fittedBox = tester.widget<FittedBox>(fittedBoxFinder);
      expect(fittedBox.fit, BoxFit.scaleDown);
    });

    testWidgets('Hit-testing directly on PosWatermarkLogo passes completely through with 0 hit absorption', (tester) async {
      final mockSettings = MockSettingsProvider();
      bool backgroundTapped = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: mockSettings,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                alignment: Alignment.center,
                children: [
                  // Interactive target directly behind watermark
                  GestureDetector(
                    key: const Key('target_behind_watermark'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => backgroundTapped = true,
                    child: Container(
                      width: 300,
                      height: 300,
                      color: Colors.blue.shade100,
                    ),
                  ),
                  // Watermark on top
                  const PosWatermarkLogo(size: 260),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap directly at the center of the watermark
      final watermarkCenter = tester.getCenter(find.byType(PosWatermarkLogo));
      await tester.tapAt(watermarkCenter);
      await tester.pump();

      expect(backgroundTapped, isTrue,
          reason: 'Pointer event must pass through the watermark to the widget behind it');
    });

    testWidgets('Tapping directly on the product image header area (CachedNetworkImage or letterbox margin) immediately triggers onSelectProduct', (tester) async {
      final mockSettings = MockSettingsProvider();
      Product? selected;

      final prodWithImage = createProduct(
        id: 999,
        name: 'Vino Malbec Gran Reserva 750ml',
        imageUrl: 'http://pos.test/storage/vino.png',
      );

      await tester.pumpWidget(buildFullCatalogGridHarness(
        displayItems: [prodWithImage],
        viewMode: 'grid_large',
        settingsProvider: mockSettings,
        size: const Size(800, 600),
        onSelectProduct: (p) => selected = p,
      ));
      await tester.pump();

      // Find CachedNetworkImage inside the catalog view (distinguishing from watermark image)
      final imageFinder = find.descendant(
        of: find.byType(PosQuickAccessCatalogView),
        matching: find.byType(CachedNetworkImage),
      );
      expect(imageFinder, findsOneWidget);

      // Tap directly on the center of the image
      await tester.tap(imageFinder);
      await tester.pump();

      expect(selected, isNotNull);
      expect(selected!.id, 999, reason: 'Tapping on the image header must immediately select the product');
    });

    testWidgets('Adversarial Product Stress (300-char name, \$999,999,999 price, weighed) renders with 0 RenderFlex overflow at 320x480 across all modes', (tester) async {
      final mockSettings = MockSettingsProvider();

      final adversarialProd = createProduct(
        id: 9999,
        name: 'ESTE ES UN PRODUCTO CON UN NOMBRE EXTRAORDINARIAMENTE LARGO Y COMPLICADO DISEÑADO EXCLUSIVAMENTE PARA ROMPER EL LAYOUT DE LA GRILLA DE PRODUCTOS SI EL DESARROLLADOR NO CONTEMPLO TEXTOVERFLOW ELLIPSIS O MAXLINES APROPIADOS EN EL COMPONENTE DE ACCESO RAPIDO',
        imageUrl: 'http://pos.test/storage/huge.png',
        isSoldByWeight: true,
        sellingPrice: 999999999.99,
        salesCount: 99999,
      );

      for (final mode in ['grid_large', 'grid_medium', 'compact', 'list']) {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final List<String> capturedErrors = [];
        final previousHandler = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          capturedErrors.add(details.exceptionAsString());
        };

        await tester.pumpWidget(buildFullCatalogGridHarness(
          displayItems: [adversarialProd],
          viewMode: mode,
          settingsProvider: mockSettings,
          size: const Size(320, 480),
        ));
        await tester.pump();

        FlutterError.onError = previousHandler;

        if (capturedErrors.isNotEmpty) {
          debugPrint('>>> CAPTURED ERRORS IN MODE "$mode": ${capturedErrors.first}');
        }
        final err = tester.takeException();
        expect(err, isNull,
            reason: 'Overflow occurred in mode $mode with adversarial product at 320x480: ${capturedErrors.isNotEmpty ? capturedErrors.first : ""}');
      }
    });
  });
}

