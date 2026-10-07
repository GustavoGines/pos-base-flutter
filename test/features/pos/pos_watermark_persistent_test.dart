import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

// ─── SAMPLE MODELS & HELPERS ────────────────────────────────────────────────

class CartItemModel {
  final Product product;
  final double quantity;
  final double unitPrice;

  CartItemModel({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });
}

final Product testProduct1 = Product(
  id: 101,
  name: 'Coca Cola 2.25L',
  internalCode: 'COC-101',
  barcode: '7790895000450',
  sellingPrice: 2500.0,
  costPrice: 1800.0,
  stock: 24,
  active: true,
  isSoldByWeight: false,
  imageUrl: 'http://pos.test/storage/products/coca.png',
);

final Product testProduct2 = Product(
  id: 102,
  name: 'Manzanas Red',
  internalCode: 'MAN-102',
  barcode: '200102000000',
  sellingPrice: 1500.0,
  costPrice: 900.0,
  stock: 50,
  active: true,
  isSoldByWeight: true,
  imageUrl: null,
);

/// Harness for Cart Panel Items Area mirroring pos_screen.dart
Widget buildCartPanelHarness({
  required List<CartItemModel> items,
  required SettingsProvider settingsProvider,
  void Function(CartItemModel item)? onTapItem,
  void Function(CartItemModel item)? onDeleteItem,
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
                      if (items.isEmpty)
                        const Center(
                          child: Text(
                            'El carrito está vacío',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return ListTile(
                              key: ValueKey('cart_item_${item.product.id}'),
                              title: Text(item.product.name),
                              subtitle: Text(
                                  '${item.quantity} x \$${item.unitPrice.toStringAsFixed(2)}'),
                              trailing: IconButton(
                                key: ValueKey('delete_item_${item.product.id}'),
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => onDeleteItem?.call(item),
                              ),
                              onTap: () => onTapItem?.call(item),
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

/// Harness for Catalog Dynamic Area mirroring pos_screen.dart
Widget buildCatalogGridHarness({
  required List<Product> displayItems,
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
                          viewMode: 'grid_medium',
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

void main() {
  group('R1: Persistent PosWatermarkLogo in Cart Panel', () {
    testWidgets('Watermark (size 260) is present when cart is EMPTY', (tester) async {
      final mockSettings = MockSettingsProvider();

      await tester.pumpWidget(buildCartPanelHarness(
        items: [],
        settingsProvider: mockSettings,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);

      // Verify empty cart message
      expect(find.text('El carrito está vacío'), findsOneWidget);

      // Verify PosWatermarkLogo exists in the tree
      final watermarkFinder = find.byType(PosWatermarkLogo);
      expect(watermarkFinder, findsOneWidget);

      final watermarkWidget = tester.widget<PosWatermarkLogo>(watermarkFinder);
      expect(watermarkWidget.size, 260.0);
    });

    testWidgets('Watermark (size 260) REMAINS in widget tree when cart is POPULATED with items', (tester) async {
      final mockSettings = MockSettingsProvider();
      final cartItems = [
        CartItemModel(product: testProduct1, quantity: 2, unitPrice: 2500.0),
        CartItemModel(product: testProduct2, quantity: 1.5, unitPrice: 1500.0),
      ];

      await tester.pumpWidget(buildCartPanelHarness(
        items: cartItems,
        settingsProvider: mockSettings,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);

      // Verify cart items are rendered
      expect(find.text('Coca Cola 2.25L'), findsOneWidget);
      expect(find.text('Manzanas Red'), findsOneWidget);
      expect(find.text('El carrito está vacío'), findsNothing);

      // Verify PosWatermarkLogo is STILL rendered behind the items
      final watermarkFinder = find.byType(PosWatermarkLogo);
      expect(watermarkFinder, findsOneWidget);

      final watermarkWidget = tester.widget<PosWatermarkLogo>(watermarkFinder);
      expect(watermarkWidget.size, 260.0);
    });

    testWidgets('Tapping cart item and delete button passes through without interference from watermark', (tester) async {
      final mockSettings = MockSettingsProvider();
      CartItemModel? tappedItem;
      CartItemModel? deletedItem;

      final cartItems = [
        CartItemModel(product: testProduct1, quantity: 1, unitPrice: 2500.0),
      ];

      await tester.pumpWidget(buildCartPanelHarness(
        items: cartItems,
        settingsProvider: mockSettings,
        onTapItem: (item) => tappedItem = item,
        onDeleteItem: (item) => deletedItem = item,
      ));
      await tester.pump();

      // Tap on the item row
      await tester.tap(find.byKey(const ValueKey('cart_item_101')));
      await tester.pump();
      expect(tappedItem, isNotNull);
      expect(tappedItem!.product.name, 'Coca Cola 2.25L');

      // Tap on the delete button
      await tester.tap(find.byKey(const ValueKey('delete_item_101')));
      await tester.pump();
      expect(deletedItem, isNotNull);
      expect(deletedItem!.product.id, 101);
    });
  });

  group('R1: Persistent PosWatermarkLogo in Catalog Grid', () {
    testWidgets('Watermark (size 360) is present when catalog is EMPTY', (tester) async {
      final mockSettings = MockSettingsProvider();

      await tester.pumpWidget(buildCatalogGridHarness(
        displayItems: [],
        settingsProvider: mockSettings,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('No hay productos en el catálogo.'), findsOneWidget);

      final watermarkFinder = find.byType(PosWatermarkLogo);
      expect(watermarkFinder, findsOneWidget);

      final watermarkWidget = tester.widget<PosWatermarkLogo>(watermarkFinder);
      expect(watermarkWidget.size, 360.0);
    });

    testWidgets('Watermark (size 360) REMAINS in widget tree when catalog HAS products', (tester) async {
      final mockSettings = MockSettingsProvider();
      final List<Product> products = [testProduct1, testProduct2];

      await tester.pumpWidget(buildCatalogGridHarness(
        displayItems: products,
        settingsProvider: mockSettings,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Coca Cola 2.25L'), findsOneWidget);
      expect(find.text('Manzanas Red'), findsOneWidget);
      expect(find.text('No hay productos en el catálogo.'), findsNothing);

      // PosWatermarkLogo must be persistent behind catalog cards
      final watermarkFinder = find.byType(PosWatermarkLogo);
      expect(watermarkFinder, findsOneWidget);

      final watermarkWidget = tester.widget<PosWatermarkLogo>(watermarkFinder);
      expect(watermarkWidget.size, 360.0);
    });

    testWidgets('Tapping product card in catalog triggers onSelectProduct without watermark blocking', (tester) async {
      final mockSettings = MockSettingsProvider();
      Product? selectedProduct;
      final List<Product> products = [testProduct1, testProduct2];

      await tester.pumpWidget(buildCatalogGridHarness(
        displayItems: products,
        settingsProvider: mockSettings,
        onSelectProduct: (p) => selectedProduct = p,
      ));
      await tester.pump();

      // Tap on first product card
      await tester.tap(find.text('Coca Cola 2.25L'));
      await tester.pump();

      expect(selectedProduct, isNotNull);
      expect(selectedProduct!.id, 101);
    });
  });

  group('R1: Layout Responsiveness & Overflow Immunity (320x480 up to 1920x1080)', () {
    final testResolutions = [
      const Size(320, 480),   // Extreme low resolution / mobile
      const Size(768, 1024),  // Tablet portrait
      const Size(1920, 1080), // Full HD Desktop
    ];

    testWidgets('Populated Cart Panel renders with 0 RenderFlex overflows across resolutions', (tester) async {
      final mockSettings = MockSettingsProvider();
      final cartItems = [
        CartItemModel(product: testProduct1, quantity: 3, unitPrice: 2500.0),
        CartItemModel(product: testProduct2, quantity: 2.5, unitPrice: 1500.0),
      ];

      for (final res in testResolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildCartPanelHarness(
          items: cartItems,
          settingsProvider: mockSettings,
          size: Size(res.width, res.height),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow detected at resolution ${res.width}x${res.height}');
        expect(find.byType(PosWatermarkLogo), findsOneWidget);
      }
    });

    testWidgets('Populated Catalog Grid renders with 0 RenderFlex overflows across resolutions', (tester) async {
      final mockSettings = MockSettingsProvider();
      final List<Product> products = [testProduct1, testProduct2];

      for (final res in testResolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildCatalogGridHarness(
          displayItems: products,
          settingsProvider: mockSettings,
          size: Size(res.width, res.height),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow detected at resolution ${res.width}x${res.height}');
        expect(find.byType(PosWatermarkLogo), findsOneWidget);
      }
    });

    testWidgets('PosWatermarkLogo wraps Opacity 0.1 and IgnorePointer to guarantee touch passthrough', (tester) async {
      final mockSettings = MockSettingsProvider();

      await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
        value: mockSettings,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PosWatermarkLogo(size: 260),
            ),
          ),
        ),
      ));
      await tester.pump();

      // Ensure IgnorePointer is root of PosWatermarkLogo
      expect(
        find.descendant(
          of: find.byType(PosWatermarkLogo),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );

      // Ensure Opacity is 0.1
      final opacityFinder = find.descendant(
        of: find.byType(PosWatermarkLogo),
        matching: find.byType(Opacity),
      );
      expect(opacityFinder, findsOneWidget);
      final opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, 0.1);

      // Ensure FittedBox with scaleDown protects against overflows
      final fittedBoxFinder = find.descendant(
        of: find.byType(PosWatermarkLogo),
        matching: find.byType(FittedBox),
      );
      expect(fittedBoxFinder, findsOneWidget);
      final fittedBoxWidget = tester.widget<FittedBox>(fittedBoxFinder);
      expect(fittedBoxWidget.fit, BoxFit.scaleDown);
    });
  });
}
