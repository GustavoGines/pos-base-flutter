import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_access_view.dart';

void main() {
  group('POS Quick Access Enterprise Tests', () {
    final productWithoutImage = Product(
      id: 1,
      name: 'AEROLIGHT FLIP 1.06 LITROS - AZUL',
      barcode: '7791234567890',
      internalCode: 'AER-001',
      costPrice: 200,
      sellingPrice: 450,
      stock: 30,
      active: true,
      isSoldByWeight: false,
      salesCount: 15,
      imageUrl: null,
    );

    final productWithImage = Product(
      id: 2,
      name: 'Gaseosa Pomelo 2.25L',
      barcode: '7791234567891',
      internalCode: 'GAS-002',
      costPrice: 80,
      sellingPrice: 150,
      stock: 50,
      active: true,
      isSoldByWeight: false,
      salesCount: 10,
      imageUrl: 'http://pos-backend.test/storage/products/2.jpg',
    );

    testWidgets('Enterprise: Renders 3 lines without truncation in no-image cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: PosQuickAccessCatalogView(
                products: [productWithoutImage],
                viewMode: 'grid_large',
              ),
            ),
          ),
        ),
      );

      expect(find.text('AEROLIGHT FLIP 1.06 LITROS - AZUL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Enterprise: Zero RenderFlex overflow across resolutions 800x600 to 1920x1080', (tester) async {
      final products = [productWithoutImage, productWithImage];
      const resolutions = [
        Size(800, 600),
        Size(1024, 768),
        Size(1280, 900),
        Size(1920, 1080),
      ];

      for (final res in resolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(size: res),
                child: SizedBox(
                  width: res.width,
                  height: res.height,
                  child: PosQuickAccessCatalogView(
                    products: products,
                    viewMode: 'grid_large',
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow at resolution ${res.width.toInt()}x${res.height.toInt()}',
        );
      }
    });

    testWidgets('Enterprise: Pinned products indicator renders correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: PosQuickAccessCatalogView(
                products: [productWithoutImage],
                viewMode: 'grid_large',
                pinnedProductIds: {1},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Enterprise: Alt+1..9 micro-badges render correctly', (tester) async {
      final products = List.generate(10, (i) => Product(
        id: i + 1,
        name: 'Producto ${i + 1}',
        barcode: '779123456789$i',
        internalCode: 'PRO-${i + 1}',
        costPrice: 100.0 + i.toDouble(),
        sellingPrice: 200.0 + i.toDouble(),
        stock: 30,
        active: true,
        isSoldByWeight: false,
        salesCount: 10 + i,
        imageUrl: i % 2 == 0 ? 'http://pos-backend.test/storage/products/$i.jpg' : null,
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: PosQuickAccessCatalogView(
                products: products,
                viewMode: 'grid_large',
                showKeyboardShortcuts: true,
              ),
            ),
          ),
        ),
      );

      // Verificar que se muestran Alt+1 hasta Alt+9
      expect(find.text('Alt+1'), findsOneWidget);
      expect(find.text('Alt+2'), findsOneWidget);
      expect(find.text('Alt+3'), findsOneWidget);
      expect(find.text('Alt+4'), findsOneWidget);
      expect(find.text('Alt+5'), findsOneWidget);
      expect(find.text('Alt+6'), findsOneWidget);
      expect(find.text('Alt+7'), findsOneWidget);
      expect(find.text('Alt+8'), findsOneWidget);
      expect(find.text('Alt+9'), findsOneWidget);

      // Verificar que la tarjeta #10 NO muestra Alt+10
      expect(find.text('Alt+10'), findsNothing);

      expect(tester.takeException(), isNull);
    });
  });
}
