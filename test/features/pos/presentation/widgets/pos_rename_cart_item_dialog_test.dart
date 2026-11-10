import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_rename_cart_item_dialog.dart';

void main() {
  Product buildCatalogProduct({
    int id = 10,
    String name = 'Coca Cola 2.25L',
    double sellingPrice = 1400.0,
    double costPrice = 1000.0,
    String? barcode = '7790895000997',
  }) {
    return Product(
      id: id,
      name: name,
      internalCode: 'CC225',
      barcode: barcode,
      sellingPrice: sellingPrice,
      costPrice: costPrice,
      stock: 20,
      active: true,
      isSoldByWeight: false,
    );
  }

  group('CartItem manual price, cost & lot subtotal overrides', () {
    test('manualUnitPrice overrides unitPrice both upwards and downwards', () {
      final product = buildCatalogProduct(sellingPrice: 1400.0, costPrice: 1000.0);
      final item = CartItem(product: product, quantity: 2);

      expect(item.unitPrice, 1400.0);
      expect(item.subtotal, 2800.0);
      expect(item.hasManualPriceOverride, isFalse);

      // Suba manual en mostrador (ej. $1600): no debe generar recargo fantasma (surchargeAmount = 0)
      item.manualUnitPrice = 1600.0;
      expect(item.unitPrice, 1600.0);
      expect(item.subtotal, 3200.0);
      expect(item.effectiveRegularUnitPrice, 1600.0);
      expect(item.regularSubtotal, 3200.0);
      expect(item.surchargeAmount, 0.0);
      expect(item.hasSurcharge, isFalse);
      expect(item.hasManualPriceOverride, isTrue);

      // Baja manual en mostrador (ej. $1200): sí se muestra como ahorro/atención sobre los $1400 de lista
      item.manualUnitPrice = 1200.0;
      expect(item.unitPrice, 1200.0);
      expect(item.subtotal, 2400.0);
      expect(item.effectiveRegularUnitPrice, 1400.0);
      expect(item.hasDiscount, isTrue);
      expect(item.discountSavings, 400.0);
    });

    test('manualSubtotal preserves exact indivisible lot total (3 for \$10.000) without \$0.01 loss', () {
      final product = buildCatalogProduct(sellingPrice: 3500.0, costPrice: 2000.0);
      final item = CartItem(
        product: product,
        quantity: 3,
        manualUnitPrice: 3333.33,
        manualSubtotal: 10000.0,
      );

      expect(item.unitPrice, 3333.33);
      expect(item.subtotal, 10000.0);
      expect(item.discountSavings, 500.0);
      final payload = item.toSalePayload();
      expect(payload['unit_price'], 3333.33);
      expect(payload['subtotal'], 10000.0);
    });

    test('toSalePayload includes custom_cost_price only when manualCostPrice is set on catalog product', () {
      final product = buildCatalogProduct(sellingPrice: 1400.0, costPrice: 1000.0);
      final item = CartItem(product: product, quantity: 1);

      final defaultPayload = item.toSalePayload();
      expect(defaultPayload.containsKey('custom_cost_price'), isFalse);
      expect(defaultPayload['cost_price'], 1000.0);

      item.manualCostPrice = 1150.0;
      final overriddenPayload = item.toSalePayload();
      expect(overriddenPayload['custom_cost_price'], 1150.0);
      expect(overriddenPayload['cost_price'], 1150.0);
    });
  });

  group('PosRenameCartItemDialog - Costo como Ancla, Descuentos, Cantidad & Barcode', () {
    testWidgets(
      'Caso A (Costo como Ancla): editar solo Precio de Venta recalcula % Margen y mantiene Costo intacto',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final product = buildCatalogProduct(sellingPrice: 1400.0, costPrice: 1000.0);
        final cartItem = CartItem(product: product);
        PosRenameCartItemResult? dialogResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    dialogResult = await PosRenameCartItemDialog.show(
                      context,
                      item: cartItem,
                    );
                  },
                  child: const Text('Abrir Modal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Modal'));
        await tester.pumpAndSettle();

        // Al iniciar: Venta = 1.400, Total Línea = 1.400, Costo = 1.000, Margen = 40%
        expect(find.widgetWithText(TextFormField, '1.400'), findsNWidgets(2));
        expect(find.widgetWithText(TextFormField, '1.000'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '40'), findsOneWidget);

        // El usuario escribe 1600 en Precio Unit. ($) -> se formatea automáticamente a 1.600
        final sellingField = find.widgetWithText(TextFormField, '1.400').first;
        await tester.enterText(sellingField, '1600');
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextFormField, '1.600'), findsNWidgets(2));
        // El Costo sigue clavado en 1.000 y el Margen pasa a 60%
        expect(find.widgetWithText(TextFormField, '1.000'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '60'), findsOneWidget);

        // Confirmar (Solo esta venta por defecto)
        await tester.tap(find.text('Aplicar en Comprobante (Enter)'));
        await tester.pumpAndSettle();

        expect(dialogResult, isNotNull);
        expect(dialogResult!.newUnitPrice, 1600.0);
        expect(dialogResult!.sellingPriceChanged, isTrue);
        expect(dialogResult!.costPriceChanged, isFalse);
        expect(dialogResult!.newCostPrice, isNull);
        expect(dialogResult!.updateCatalogInDb, isFalse);
      },
    );

    testWidgets(
      'Caso B + Switch BD: editar Costo con margen actualiza Precio de Venta y activa guardado en Catálogo',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final product = buildCatalogProduct(sellingPrice: 1400.0, costPrice: 1000.0);
        final cartItem = CartItem(product: product);
        PosRenameCartItemResult? dialogResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    dialogResult = await PosRenameCartItemDialog.show(
                      context,
                      item: cartItem,
                    );
                  },
                  child: const Text('Abrir Modal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Modal'));
        await tester.pumpAndSettle();

        // El usuario cambia Costo de 1.000 a 1200 -> se formatea a 1.200 y con 40% de margen, Precio Venta sube a 1.680
        final costField = find.widgetWithText(TextFormField, '1.000');
        await tester.enterText(costField, '1200');
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextFormField, '1.200'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '1.680'), findsNWidgets(2));

        // Activar el switch "💾 Actualizar precio/costo permanentemente en el Catálogo (BD)"
        await tester.tap(
          find.textContaining('Actualizar precio/costo permanentemente en el Catálogo'),
        );
        await tester.pumpAndSettle();

        // El botón principal cambia a "Aplicar y Guardar en BD (Enter)"
        expect(find.text('Aplicar y Guardar en BD (Enter)'), findsOneWidget);

        await tester.tap(find.text('Aplicar y Guardar en BD (Enter)'));
        await tester.pumpAndSettle();

        expect(dialogResult, isNotNull);
        expect(dialogResult!.updateCatalogInDb, isTrue);
        expect(dialogResult!.sellingPriceChanged, isTrue);
        expect(dialogResult!.costPriceChanged, isTrue);
        expect(dialogResult!.newUnitPrice, 1680.0);
        expect(dialogResult!.newCostPrice, 1200.0);
      },
    );

    testWidgets(
      'Puntos 1 y 6: cambiar cantidad a 3 y pactar Total Línea en \$10.000 calcula ahorro y retiene manualSubtotal exacto',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final product = buildCatalogProduct(sellingPrice: 3500.0, costPrice: 2000.0);
        final cartItem = CartItem(product: product, quantity: 1);
        PosRenameCartItemResult? dialogResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    dialogResult = await PosRenameCartItemDialog.show(
                      context,
                      item: cartItem,
                    );
                  },
                  child: const Text('Abrir Modal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Modal'));
        await tester.pumpAndSettle();

        // Subir cantidad a 3 tocando dos veces el botón '+'
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        // El Total Línea pasa a 3 * 3.500 = 10.500
        final subtotalField = find.widgetWithText(TextFormField, '10.500');
        expect(subtotalField, findsOneWidget);

        // El cajero escribe 10000 en Total Línea ($) ("Llevo 3, ¿me los dejás en $10.000?")
        await tester.enterText(subtotalField, '10000');
        await tester.pumpAndSettle();

        // Muestra el ahorro de $500 para el cliente
        expect(find.textContaining('El cliente ahorra \$500'), findsOneWidget);

        await tester.tap(find.text('Aplicar en Comprobante (Enter)'));
        await tester.pumpAndSettle();

        expect(dialogResult, isNotNull);
        expect(dialogResult!.newQuantity, 3.0);
        expect(dialogResult!.newUnitPrice, 3333.33);
        expect(dialogResult!.newManualSubtotal, 10000.0);
        expect(dialogResult!.updateCatalogInDb, isFalse);
      },
    );

    testWidgets(
      'Punto 2A: pistolear código de barras nuevo captura el Enter del láser sin cerrar el diálogo y lo retorna al confirmar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final product = buildCatalogProduct(barcode: null);
        final cartItem = CartItem(product: product, quantity: 1);
        PosRenameCartItemResult? dialogResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    dialogResult = await PosRenameCartItemDialog.show(
                      context,
                      item: cartItem,
                    );
                  },
                  child: const Text('Abrir Modal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Modal'));
        await tester.pumpAndSettle();

        // Abrir el editor de código de barras
        await tester.tap(find.text('Pistolear código nuevo'));
        await tester.pumpAndSettle();

        final barcodeField = find.widgetWithText(
          TextFormField,
          'Escanear o escribir Código de Barras (se guarda en BD)',
        );
        expect(barcodeField, findsOneWidget);

        // Simular escaneo del lector láser + Enter automático del lector
        await tester.enterText(barcodeField, '7791234567890');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        // El diálogo NO se cerró prematuramente, sino que muestra confirmación de captura
        expect(find.textContaining('Código capturado por el lector'), findsOneWidget);
        expect(dialogResult, isNull);

        // Ahora sí confirmar con el botón principal
        await tester.tap(find.text('Aplicar y Guardar en BD (Enter)'));
        await tester.pumpAndSettle();

        expect(dialogResult, isNotNull);
        expect(dialogResult!.barcodeChanged, isTrue);
        expect(dialogResult!.newBarcode, '7791234567890');
      },
    );
  });
}
