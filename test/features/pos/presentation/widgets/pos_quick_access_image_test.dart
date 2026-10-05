import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_access_view.dart';

void main() {
  final productWithImage = Product(
    id: 1,
    name: 'Gaseosa Pomelo 2.25L',
    barcode: '7791234567890',
    internalCode: 'GAS-001',
    costPrice: 200,
    sellingPrice: 450,
    stock: 30,
    active: true,
    isSoldByWeight: false,
    salesCount: 15,
    imageUrl: 'http://pos-backend.test/storage/products/1.jpg',
  );

  final unitProductNoImage = Product(
    id: 2,
    name: 'Galletitas de Agua',
    barcode: '7791234567891',
    internalCode: 'GAL-002',
    costPrice: 80,
    sellingPrice: 150,
    stock: 50,
    active: true,
    isSoldByWeight: false,
    imageUrl: null,
  );

  final weighedProductNoImage = Product(
    id: 3,
    name: 'Manzanas Rojas',
    internalCode: 'MAN-003',
    costPrice: 500,
    sellingPrice: 900,
    stock: 20.5,
    active: true,
    isSoldByWeight: true,
    imageUrl: null,
  );

  Widget buildTestApp({
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

  group('Milestone 2: POS Quick Access View Image and Fallback Tests', () {
    testWidgets('Mode "list": Renders 44x44 CachedNetworkImage for product with image, and fallback icons for items without image', (tester) async {
      await tester.pumpWidget(buildTestApp(
        products: [productWithImage, unitProductNoImage, weighedProductNoImage],
        viewMode: 'list',
      ));
      await tester.pump();

      // CachedNetworkImage is rendered for product with image
      final imageFinder = find.byType(CachedNetworkImage);
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<CachedNetworkImage>(imageFinder);
      expect(image.width, 44.0);
      expect(image.height, 44.0);

      // Fallback icon for unit product
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);

      // Fallback icon for weighed product
      expect(find.byIcon(Icons.scale_rounded), findsOneWidget);
    });

    testWidgets('Mode "compact": Renders 24x24 CachedNetworkImage for product with image, and fallback icon for item without image', (tester) async {
      await tester.pumpWidget(buildTestApp(
        products: [productWithImage, unitProductNoImage],
        viewMode: 'compact',
      ));
      await tester.pump();

      final imageFinder = find.byType(CachedNetworkImage);
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<CachedNetworkImage>(imageFinder);
      expect(image.width, 24.0);
      expect(image.height, 24.0);

      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });

    testWidgets('Mode "grid_medium": Renders expanded CachedNetworkImage with BoxFit.cover for product with image, and fallback icon for item without image', (tester) async {
      await tester.pumpWidget(buildTestApp(
        products: [productWithImage, weighedProductNoImage],
        viewMode: 'grid_medium',
      ));
      await tester.pump();

      final imageFinder = find.byType(CachedNetworkImage);
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<CachedNetworkImage>(imageFinder);
      expect(image.width, double.infinity);
      expect(image.height, double.infinity);
      expect(image.fit, BoxFit.cover);

      expect(find.byIcon(Icons.scale_rounded), findsOneWidget);
    });

    testWidgets('Mode "grid_large": Renders expanded CachedNetworkImage with BoxFit.cover for product with image, and fallback icon for item without image', (tester) async {
      await tester.pumpWidget(buildTestApp(
        products: [productWithImage, unitProductNoImage, weighedProductNoImage],
        viewMode: 'grid_large',
      ));
      await tester.pump();

      final imageFinder = find.byType(CachedNetworkImage);
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<CachedNetworkImage>(imageFinder);
      expect(image.width, double.infinity);
      expect(image.height, double.infinity);
      expect(image.fit, BoxFit.cover);

      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
      expect(find.byIcon(Icons.scale_rounded), findsOneWidget);
    });

    testWidgets('Tapping product item fires onSelectProduct callback', (tester) async {
      Product? selected;
      await tester.pumpWidget(buildTestApp(
        products: [productWithImage],
        viewMode: 'list',
        onSelect: (p) => selected = p,
      ));
      await tester.pump();

      await tester.tap(find.text('Gaseosa Pomelo 2.25L'));
      await tester.pump();

      expect(selected, isNotNull);
      expect(selected!.id, 1);
    });

    testWidgets('Layout responsiveness: Zero RenderFlex overflow in all 4 modes on compact 800x600 screen', (tester) async {
      final products = [productWithImage, unitProductNoImage, weighedProductNoImage];
      const modes = ['list', 'compact', 'grid_medium', 'grid_large'];

      for (final mode in modes) {
        await tester.pumpWidget(buildTestApp(
          products: products,
          viewMode: mode,
          viewport: const Size(800, 600),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'Failed on mode: $mode');
      }
    });
  });
}
