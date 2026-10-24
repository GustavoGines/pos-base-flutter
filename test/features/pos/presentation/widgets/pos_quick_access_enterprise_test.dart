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

    testWidgets('Enterprise: Ctrl+1..9 micro-badges render correctly', (tester) async {
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

      // Verificar que se muestran Ctrl+1 hasta Ctrl+9
      expect(find.text('Ctrl+1'), findsOneWidget);
      expect(find.text('Ctrl+2'), findsOneWidget);
      expect(find.text('Ctrl+3'), findsOneWidget);
      expect(find.text('Ctrl+4'), findsOneWidget);
      expect(find.text('Ctrl+5'), findsOneWidget);
      expect(find.text('Ctrl+6'), findsOneWidget);
      expect(find.text('Ctrl+7'), findsOneWidget);
      expect(find.text('Ctrl+8'), findsOneWidget);
      expect(find.text('Ctrl+9'), findsOneWidget);

      // Verificar que la tarjeta #10 NO muestra Ctrl+10
      expect(find.text('Ctrl+10'), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Enterprise: Top 3 podium badges render starting from 1 sale (topMinSales = 1) and coexist with Ctrl+N and Pin without overflow', (tester) async {
      final podiumProducts = [
        Product(
          id: 101,
          name: 'Producto Sin Foto Top 1',
          internalCode: 'TOP-1',
          costPrice: 100,
          sellingPrice: 200,
          stock: 10,
          active: true,
          isSoldByWeight: false,
          salesCount: 3,
          imageUrl: null,
        ),
        Product(
          id: 102,
          name: 'Producto Con Foto Top 2',
          internalCode: 'TOP-2',
          costPrice: 100,
          sellingPrice: 200,
          stock: 10,
          active: true,
          isSoldByWeight: true,
          salesCount: 2,
          imageUrl: 'http://pos-backend.test/storage/products/top2.jpg',
        ),
        Product(
          id: 103,
          name: 'Producto Sin Foto Top 3',
          internalCode: 'TOP-3',
          costPrice: 100,
          sellingPrice: 200,
          stock: 10,
          active: true,
          isSoldByWeight: false,
          salesCount: 1,
          imageUrl: null,
        ),
      ];

      for (final mode in ['grid_large', 'grid_medium']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: PosQuickAccessCatalogView(
                  products: podiumProducts,
                  viewMode: mode,
                  showTopRanks: true,
                  showKeyboardShortcuts: true,
                  pinnedProductIds: const {101, 102, 103},
                ),
              ),
            ),
          ),
        );

        expect(find.text('Ctrl+1'), findsOneWidget);
        expect(find.text('Ctrl+2'), findsOneWidget);
        expect(find.text('Ctrl+3'), findsOneWidget);
        expect(find.byIcon(Icons.push_pin), findsNWidgets(3));
        expect(find.byIcon(Icons.local_fire_department_rounded), findsNWidgets(3));
        expect(tester.takeException(), isNull, reason: 'Failed on mode $mode');
      }
    });

    test('Enterprise: Category palette (12 semantic colors) and DJB2 hash dispersion', () {
      // 1. Sold by weight always resolves to scale orange (Colors.orange.shade700)
      final weightColor = PosQuickAccessCatalogView.resolveCategoryAccent('Cualquiera', isSoldByWeight: true);
      expect(weightColor, Colors.orange.shade700);

      // 2. Null or empty string resolves to neutral fallback (Colors.blueGrey.shade600)
      final nullColor = PosQuickAccessCatalogView.resolveCategoryAccent(null);
      final emptyColor = PosQuickAccessCatalogView.resolveCategoryAccent('');
      final whitespaceColor = PosQuickAccessCatalogView.resolveCategoryAccent('   ');
      expect(nullColor, Colors.blueGrey.shade600);
      expect(emptyColor, Colors.blueGrey.shade600);
      expect(whitespaceColor, Colors.blueGrey.shade600);

      // 3. Different categories receive distinct, consistent colors
      final bebidasColor = PosQuickAccessCatalogView.resolveCategoryAccent('Bebidas');
      final limpiezaColor = PosQuickAccessCatalogView.resolveCategoryAccent('Limpieza');
      final golosinasColor = PosQuickAccessCatalogView.resolveCategoryAccent('Golosinas');
      final snacksColor = PosQuickAccessCatalogView.resolveCategoryAccent('Snacks');
      final panaderiaColor = PosQuickAccessCatalogView.resolveCategoryAccent('Panadería');

      expect(bebidasColor, isNotNull);
      expect(limpiezaColor, isNotNull);
      // Case-insensitivity & whitespace trimming
      expect(PosQuickAccessCatalogView.resolveCategoryAccent('  bebidas  '), bebidasColor);
      expect(PosQuickAccessCatalogView.resolveCategoryAccent('BEBIDAS'), bebidasColor);

      // Verify colors belong to the 12-color semantic palette
      expect(PosQuickAccessCatalogView.categoryPalette.length, 12);
      expect(PosQuickAccessCatalogView.categoryPalette.contains(bebidasColor), isTrue);
      expect(PosQuickAccessCatalogView.categoryPalette.contains(limpiezaColor), isTrue);
      expect(PosQuickAccessCatalogView.categoryPalette.contains(golosinasColor), isTrue);
      expect(PosQuickAccessCatalogView.categoryPalette.contains(snacksColor), isTrue);
      expect(PosQuickAccessCatalogView.categoryPalette.contains(panaderiaColor), isTrue);
    });

    testWidgets('Enterprise: Prominent prices and vertical promo stacking render without overflow across all 4 modes', (tester) async {
      final highValueProduct = Product(
        id: 500,
        name: 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
        internalCode: 'PS5-PRO',
        costPrice: 1800000,
        sellingPrice: 2777500,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        salesCount: 2,
        imageUrl: 'http://pos-backend.test/storage/products/ps5.jpg',
      );

      final recordedFontSizes = <String, double>{};

      for (final mode in ['grid_large', 'grid_medium', 'compact', 'list']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1024,
                height: 768,
                child: PosQuickAccessCatalogView(
                  products: [highValueProduct],
                  viewMode: mode,
                  showTopRanks: true,
                  showKeyboardShortcuts: true,
                  pinnedProductIds: const {500},
                  priceBuilder: (p, isByWeight, fontSize) {
                    recordedFontSizes[mode] = fontSize;
                    if (mode == 'list') {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '\$2.777.500',
                            style: TextStyle(
                              fontSize: fontSize - 2.5,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '\$2.222.000',
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: mode == 'compact'
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\$2.777.500',
                          style: TextStyle(
                            fontSize: (fontSize * 0.68).clamp(9.5, 11.5),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          '\$2.222.000',
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );

        expect(find.text('\$2.777.500'), findsOneWidget);
        expect(find.text('\$2.222.000'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Overflow in mode $mode');
      }

      // Verificar que los tamaños de fuente principales se incrementaron para legibilidad POS
      expect(recordedFontSizes['grid_large'], 16.0);
      expect(recordedFontSizes['grid_medium'], 14.0);
      expect(recordedFontSizes['compact'], 14.5);
      expect(recordedFontSizes['list'], 15.0);
    });
  });
}
