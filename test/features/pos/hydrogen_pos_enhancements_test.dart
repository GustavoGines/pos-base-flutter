import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/repositories/pos_repository.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_item_dialog.dart';

class _FakePosRepository implements PosRepository {
  @override
  Future<List<Map<String, dynamic>>> fetchPaymentMethods() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Hydrogen Fase 2-4 - Fracciones, Combos y Redondeo al Centavo', () {
    late PosProvider posProvider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      final repo = _FakePosRepository();
      posProvider = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
      );
    });

    test('toUnitStockDisplay formatea enteros, Kg y fracciones culinarias sin redondear hacia arriba', () {
      expect(2.0.toUnitStockDisplay(), '2 u');
      expect(0.0.toUnitStockDisplay(), '0 u');
      expect(1.875.toUnitStockDisplay(), '1 u + 7/8');
      expect(0.125.toUnitStockDisplay(), '1/8 u');
      expect(0.167.toUnitStockDisplay(), '1/6 u');
      expect(1.875.toUnitStockDisplay(isSoldByWeight: true), '1.875 kg');
    });

    test('CartItem.toSalePayload serializa combo_ingredients limpios (id y quantity) solo en combos con ingredientes', () {
      final quickCombo = Product(
        id: 0,
        name: 'Promo Porción + Café',
        internalCode: 'COMBO-POS',
        costPrice: 2500.0,
        sellingPrice: 6000.0,
        stock: 0.0,
        active: true,
        isSoldByWeight: false,
        isCombo: true,
        comboIngredients: [
          {
            'id': 10,
            'name': 'Torta Chocotorta',
            'quantity': 0.125,
            'cost_price': 1800.0,
            'selling_price': 4500.0,
            'stock': 1.875,
          },
          {
            'id': 20,
            'name': 'Café con Leche',
            'quantity': 1.0,
            'cost_price': 700.0,
            'selling_price': 2500.0,
            'stock': 50.0,
          },
        ],
      );

      final comboItem = CartItem(
        product: quickCombo,
        quantity: 1.0,
        isTemporary: true,
      );

      final payload = comboItem.toSalePayload();
      expect(payload['is_combo'], isTrue);
      expect(payload['combo_ingredients'], [
        {'id': 10, 'quantity': 0.125},
        {'id': 20, 'quantity': 1.0},
      ]);

      final regularProduct = Product(
        id: 30,
        name: 'Medialuna',
        internalCode: 'MED-1',
        costPrice: 100.0,
        sellingPrice: 500.0,
        stock: 24.0,
        active: true,
        isSoldByWeight: false,
      );
      final regularPayload = CartItem(product: regularProduct, quantity: 2.0).toSalePayload();
      expect(regularPayload.containsKey('combo_ingredients'), isFalse);
    });

    test('PosProvider bloquea venta de 2 unidades enteras cuando el stock es 1.875 pero permite 1 entera o porción 0.125', () {
      final torta = Product(
        id: 10,
        name: 'Torta Chocotorta',
        internalCode: 'TOR-1',
        costPrice: 8000.0,
        sellingPrice: 24000.0,
        stock: 1.875,
        active: true,
        isSoldByWeight: false,
      );

      expect(posProvider.maxWholeUnitsAvailable(torta), 1);

      // No permite vender 2 unidades enteras
      expect(
        posProvider.validateUnitStockConstraint(torta, 2.0),
        isNotNull,
      );

      // Permite vender 1 unidad entera
      expect(
        posProvider.validateUnitStockConstraint(torta, 1.0),
        isNull,
      );

      // Agregamos 1 unidad entera al carrito; quedan 0.875 (0 enteras, pero sí 0.125)
      final added = posProvider.requestAddToCartWithPromo(torta);
      expect(added, isTrue);
      expect(posProvider.cart.single.quantity, 1.0);

      // Intentar sumar otra unidad entera sobre la línea existente (total 2.0) debe fallar
      expect(
        posProvider.validateUnitStockConstraint(
          torta,
          2.0,
          excludingItem: posProvider.cart.single,
        ),
        isNotNull,
      );

      // Permitir porción fraccionaria dentro del saldo restante 0.875
      expect(
        posProvider.validateUnitStockConstraint(
          torta,
          1.125,
          excludingItem: posProvider.cart.single,
        ),
        isNull,
      );

      // Producto en 0 sin control entero estricto mantiene comportamiento histórico (no bloquea unidad)
      final sinStock = Product(
        id: 99,
        name: 'Sin Stock Cargado',
        internalCode: 'SS-1',
        costPrice: 100.0,
        sellingPrice: 500.0,
        stock: 0.0,
        active: true,
        isSoldByWeight: false,
      );
      expect(posProvider.validateUnitStockConstraint(sinStock, 1.0), isNull);
    });

    test('applyAgreedTotalRounding prorratea en centavos exactos y respeta tolerancia SaleService', () {
      final itemA = Product(
        id: 1,
        name: 'Producto A',
        internalCode: 'A',
        costPrice: 5000.0,
        sellingPrice: 8476.92,
        stock: 10.0,
        active: true,
        isSoldByWeight: false,
      );
      final itemB = Product(
        id: 2,
        name: 'Producto B',
        internalCode: 'B',
        costPrice: 1000.0,
        sellingPrice: 1500.0,
        stock: 10.0,
        active: true,
        isSoldByWeight: false,
      );
      final itemC = Product(
        id: 3,
        name: 'Porción C',
        internalCode: 'C',
        costPrice: 500.0,
        sellingPrice: 3976.93,
        stock: 5.0,
        active: true,
        isSoldByWeight: false,
      );

      posProvider.addQuickOrTemporaryItem(
        CartItem(product: itemA, quantity: 3.0),
      );
      posProvider.addQuickOrTemporaryItem(
        CartItem(product: itemB, quantity: 2.0),
      );
      posProvider.addQuickOrTemporaryItem(
        CartItem(product: itemC, quantity: 1.5),
      );

      // Target pactado exacto: $32.000,00
      const target = 32000.00;
      posProvider.applyAgreedTotalRounding(target);

      expect(posProvider.cartSubtotal, closeTo(target, 0.00001));

      int sumCents = 0;
      for (final item in posProvider.cart) {
        sumCents += (item.subtotal * 100).round();
        final expectedCalc = item.unitPrice * item.quantity;
        final tolerance = math.max(0.05, 0.02 * item.quantity);
        expect(
          (item.subtotal - expectedCalc).abs(),
          lessThanOrEqualTo(tolerance),
        );
      }
      expect(sumCents, 3200000);
    });

    testWidgets(
      'PosQuickItemDialog transiciona suavemente entre Producto, Servicio y Combo sin overflows',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PosQuickItemDialog(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Producto Rápido en Mostrador'), findsOneWidget);

        // Cambiar a Servicio / Honorario y muestrear mitad de transición
        await tester.tap(find.text('Servicio / Honorario'));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpAndSettle();
        expect(find.text('Servicio / Honorario en Mostrador'), findsOneWidget);
        expect(find.textContaining('Modalidad Servicio / Honorario'), findsOneWidget);

        // Cambiar a Combo / Promoción y muestrear mitad de transición
        await tester.tap(find.text('Combo / Promoción'));
        await tester.pump(const Duration(milliseconds: 140));
        await tester.pumpAndSettle();
        expect(find.text('Combo / Oferta Rápida en Mostrador'), findsOneWidget);
        expect(find.textContaining('Ingredientes para descuento de stock'), findsOneWidget);

        // Volver a Producto Rápido para validar colapso limpio del panel de combo
        await tester.tap(find.text('Producto Rápido'));
        await tester.pump(const Duration(milliseconds: 140));
        await tester.pumpAndSettle();
        expect(find.text('Producto Rápido en Mostrador'), findsOneWidget);
      },
    );
  });
}
