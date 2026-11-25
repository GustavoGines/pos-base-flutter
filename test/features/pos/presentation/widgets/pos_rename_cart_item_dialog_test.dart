import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_rename_cart_item_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class _RenameFakeSettingsProvider extends ChangeNotifier
    implements SettingsProvider {
  final BusinessSettings _settings;

  _RenameFakeSettingsProvider({
    required String businessType,
    List<String> secondaryBusinessTypes = const [],
    String planType = 'basic',
    bool multiRubro = false,
    String taxCondition = 'monotributo',
  }) : _settings = BusinessSettings(
          businessType: businessType,
          secondaryBusinessTypes: secondaryBusinessTypes,
          licenseStatus: 'active',
          licensePlanType: planType,
          taxCondition: taxCondition,
          features: FeatureFlags(
            fastPos: true,
            multiRubro: multiRubro,
          ),
        );

  @override
  BusinessSettings? get settings => _settings;

  @override
  bool get isHardwareStore => _settings.isHardwareStore;

  @override
  FeatureFlags get features => _settings.features;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RenameFakeCatalogProvider extends ChangeNotifier
    implements CatalogProvider {
  final List<Rubro> _rubros;
  _RenameFakeCatalogProvider({List<Rubro> rubros = const []}) : _rubros = rubros;

  @override
  List<Rubro> get rubros => _rubros;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

        // Expandir Zona 2 ("Corregir en catálogo (BD)") y activar el switch de actualización en BD
        final zone2Header = find.text('Corregir en catálogo (BD)');
        await tester.ensureVisible(zone2Header);
        await tester.tap(zone2Header);
        await tester.pumpAndSettle();

        final saveDbToggle = find.textContaining(
          'Actualizar precio/costo permanentemente en el Catálogo',
        );
        await tester.ensureVisible(saveDbToggle);
        await tester.tap(saveDbToggle);
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

        // Expandir Zona 2 ("Corregir en catálogo (BD)") y abrir el editor de código de barras
        final zone2Header = find.text('Corregir en catálogo (BD)');
        await tester.ensureVisible(zone2Header);
        await tester.tap(zone2Header);
        await tester.pumpAndSettle();

        final scanBtn = find.text('Pistolear código nuevo');
        await tester.ensureVisible(scanBtn);
        await tester.tap(scanBtn);
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

    testWidgets(
      'Lenguaje claro de stock (sin Kardex + Mín. alerta) y fracciones universales ÷ 16 / 1/16',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final product = Product(
          id: 77,
          name: 'Torta Matilda',
          internalCode: '00077',
          barcode: null,
          sellingPrice: 2000.0,
          costPrice: 1200.0,
          stock: -3.0,
          minStock: 5.0,
          active: true,
          isSoldByWeight: false,
        );
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

        // Abrir selector de fracciones 1/x: debe mostrar "1 entero" y divisor personalizado
        await tester.tap(find.text('1/x'));
        await tester.pumpAndSettle();
        expect(find.text('1 entero'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('rename_custom_parts_input')), '16');
        await tester.tap(find.byKey(const Key('rename_apply_custom_parts_btn')));
        await tester.pumpAndSettle();

        // 1/16 = 0.0625 -> 0.0625 * $2.000 = $125 exactos
        expect(find.widgetWithText(TextFormField, '0.0625'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '125'), findsWidgets);

        // Escritura directa de fracción "1/8" -> 0.125 -> $250, y luego volver a "1/16" -> 0.0625
        final qtyField = find.widgetWithText(TextFormField, '0.0625');
        await tester.enterText(qtyField, '1/8');
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextFormField, '250'), findsWidgets);

        await tester.enterText(find.widgetWithText(TextFormField, '1/8'), '1/16');
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextFormField, '125'), findsWidgets);

        // Expandir Zona 2 y verificar lenguaje claro (sin "Kardex") y mínimo de alerta visible
        final zone2Header = find.text('Corregir en catálogo (BD)');
        await tester.ensureVisible(zone2Header);
        await tester.tap(zone2Header);
        await tester.pumpAndSettle();

        expect(find.textContaining('Mín. alerta:'), findsOneWidget);

        final stockField = find.widgetWithText(TextFormField, '-3');
        await tester.ensureVisible(stockField);
        await tester.enterText(stockField, '10');
        await tester.pumpAndSettle();

        expect(find.textContaining('Kardex:'), findsNothing);
        expect(find.textContaining('Ajuste de inventario:'), findsOneWidget);

        await tester.tap(find.text('Aplicar y Guardar en BD (Enter)'));
        await tester.pumpAndSettle();

        expect(dialogResult, isNotNull);
        expect(dialogResult!.newQuantity, closeTo(0.0625, 0.00001));
        expect(dialogResult!.newShelfStockBeforeSale, 10.0);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('PosRenameCartItemDialog - Aislamiento estricto por Rubro y Plan', () {
    final hwRubro = Rubro(
      id: 1,
      name: 'Ferretería y Pinturería',
      verticalType: 'hardware_store',
    );
    final apparelRubro = Rubro(
      id: 2,
      name: 'Indumentaria',
      verticalType: 'apparel',
    );
    final paintDemoProduct = Product(
      id: 201,
      name: 'Pintura Látex Exterior Lavable Alba 20L',
      internalCode: 'HW201',
      sellingPrice: 89500,
      costPrice: 58000,
      stock: 12,
      active: true,
      isSoldByWeight: false,
      unitType: 'un',
      calcConfig: const {'type': 'paint', 'liters': 20.0, 'yield_m2_l': 10.0},
      category: Category(
        id: 11,
        name: 'Pinturas',
        rubroId: 1,
        rubro: hwRubro,
      ),
    );
    final shirtProduct = Product(
      id: 202,
      name: 'Remera Oversize Algodón',
      internalCode: 'IND202',
      sellingPrice: 18000,
      costPrice: 9500,
      stock: 25,
      active: true,
      isSoldByWeight: false,
      unitType: 'un',
      category: Category(
        id: 22,
        name: 'Remeras',
        rubroId: 2,
        rubro: apparelRubro,
      ),
    );

    Future<void> pumpDialogForVertical(
      WidgetTester tester, {
      required Product product,
      required String businessType,
      bool multiRubro = false,
      String planType = 'basic',
    }) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
              value: _RenameFakeSettingsProvider(
                businessType: businessType,
                planType: planType,
                multiRubro: multiRubro,
              ),
            ),
            ChangeNotifierProvider<CatalogProvider>.value(
              value: _RenameFakeCatalogProvider(
                rubros: [hwRubro, apparelRubro],
              ),
            ),
            ChangeNotifierProvider<LocalTerminalProvider>(
              create: (_) => LocalTerminalProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PosRenameCartItemDialog(
                item: CartItem(product: product, quantity: 1),
                onOpenHardwareCalculator: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Plan Básico: Indumentaria, Minimercado, Carnicería, Tecnología y Bazar JAMÁS muestran "Recalcular por m² / Medidas" aunque el producto demo tenga calcConfig',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final vertical in const [
          'apparel',
          'retail',
          'butcher',
          'tech',
          'general',
        ]) {
          await pumpDialogForVertical(
            tester,
            product: paintDemoProduct,
            businessType: vertical,
            multiRubro: false,
            planType: 'basic',
          );

          expect(
            find.text('Recalcular por m² / Medidas'),
            findsNothing,
            reason:
                'Rubro $vertical en Plan Básico no debe mostrar calculadora ferretera m²',
          );

          // Fracciones rápidas 1/x: ocultas para unidad entera en apparel/tech/general; visibles en retail/butcher
          if (vertical == 'retail' || vertical == 'butcher') {
            expect(
              find.byKey(const Key('rename_quick_fractions_toggle_btn')),
              findsOneWidget,
              reason: 'Rubro $vertical debe conservar 1/x para porciones',
            );
          } else {
            expect(
              find.byKey(const Key('rename_quick_fractions_toggle_btn')),
              findsNothing,
              reason:
                  'Rubro $vertical con unidad entera (un) no debe mostrar porciones 1/x',
            );
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );

    testWidgets(
      'Plan Básico Ferretería SÍ muestra "Recalcular por m² / Medidas" y "Fracción rápida" en 1/x; Tecnología muestra 1/x solo en cables por metro (mt)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await pumpDialogForVertical(
          tester,
          product: paintDemoProduct,
          businessType: 'hardware_store',
          multiRubro: false,
          planType: 'basic',
        );

        expect(find.text('Recalcular por m² / Medidas'), findsOneWidget);
        expect(
          find.byKey(const Key('rename_quick_fractions_toggle_btn')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('rename_quick_fractions_toggle_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Fracción rápida:'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // Cable UTP por metro (unitType: 'mt') en Tecnología Básico -> habilita 1/x pero sin m²
        final cableMt = shirtProduct.copyWith(
          name: 'Cable UTP Cat6 Exterior',
          unitType: 'mt',
          clearCategory: true,
        );
        await pumpDialogForVertical(
          tester,
          product: cableMt,
          businessType: 'tech',
          multiRubro: false,
          planType: 'basic',
        );
        expect(find.text('Recalcular por m² / Medidas'), findsNothing);
        expect(
          find.byKey(const Key('rename_quick_fractions_toggle_btn')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Plan PRO Multi-Rubro: habilita "Recalcular por m² / Medidas" y 1/x en ítems de Ferretería y los oculta en ítems de Indumentaria',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // 1. Ítem de Ferretería en tienda PRO Multi-Rubro (incluso con rubro primario retail)
        await pumpDialogForVertical(
          tester,
          product: paintDemoProduct,
          businessType: 'retail',
          multiRubro: true,
          planType: 'premium',
        );
        expect(find.text('Recalcular por m² / Medidas'), findsOneWidget);
        expect(
          find.byKey(const Key('rename_quick_fractions_toggle_btn')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // 2. Ítem de Indumentaria en tienda PRO Multi-Rubro (incluso con rubro primario hardware_store)
        await pumpDialogForVertical(
          tester,
          product: shirtProduct,
          businessType: 'hardware_store',
          multiRubro: true,
          planType: 'premium',
        );
        expect(find.text('Recalcular por m² / Medidas'), findsNothing);
        expect(
          find.byKey(const Key('rename_quick_fractions_toggle_btn')),
          findsNothing,
        );
      },
    );
  });
}
