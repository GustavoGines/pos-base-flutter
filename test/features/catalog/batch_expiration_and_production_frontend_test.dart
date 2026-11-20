import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_batch_model.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/data/models/production_order_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/expired_batches_sweep_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/print_labels_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/product_batches_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/production_orders_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/stock_adjustment_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/data/offer_repository.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_offers_dialog.dart';
import 'package:frontend_desktop/features/pos/utils/batch_barcode_helper.dart';
import 'package:frontend_desktop/features/reports/data/datasources/inventory_alerts_datasource.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/inventory_alerts_widget.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Lotes, Vencimientos y Producción — Frontend Tests', () {
    test('ProductModel.fromJson hidrata flags de lotes, receta propia e ingredientes multi-nivel', () {
      final model = ProductModel.fromJson({
        'id': 42,
        'name': 'Chocotorta Clásica',
        'internal_code': '00042',
        'cost_price': 4500,
        'selling_price': 9800,
        'stock': 6,
        'active': true,
        'is_sold_by_weight': false,
        'track_batches': true,
        'lot_deduction_policy': 'fifo',
        'allow_sell_expired': false,
        'has_production_recipe': true,
        'recipe_yield_quantity': '6.000',
        'vencimiento_dias': 4,
        'expiration_date': '2026-11-20T00:00:00.000000Z',
        'recipe_items': [
          {
            'id': 1,
            'parent_product_id': 42,
            'ingredient_product_id': 11,
            'quantity': '1.500',
            'waste_pct': '5.00',
            'ingredient': {
              'id': 11,
              'name': 'Crema Pastelera (Semi-elaborado)',
              'internal_code': '00011',
              'cost_price': 2000,
              'stock': 8,
              'unit_type': 'kg',
              'is_sold_by_weight': true,
              'track_batches': true,
            },
          },
        ],
      });

      expect(model.trackBatches, isTrue);
      expect(model.lotDeductionPolicy, 'fifo');
      expect(model.allowSellExpired, isFalse);
      expect(model.hasProductionRecipe, isTrue);
      expect(model.recipeYieldQuantity, 6.0);
      expect(model.expirationDate, '2026-11-20');
      expect(model.recipeIngredients, isNotNull);
      expect(model.recipeIngredients!.length, 1);
      expect(model.recipeIngredients!.first['ingredient_product_id'], 11);
      expect(model.recipeIngredients!.first['name'], 'Crema Pastelera (Semi-elaborado)');
      expect(model.recipeIngredients!.first['quantity'], 1.5);
      expect(model.recipeIngredients!.first['waste_pct'], 5.0);
      expect(model.recipeIngredients!.first['track_batches'], isTrue);
    });

    test('ProductModel.fromJson conserva defaults compatibles v1.8.5 ante payload legado', () {
      final legacy = ProductModel.fromJson({
        'id': 7,
        'name': 'Gaseosa 500ml',
        'internal_code': '00007',
        'cost_price': 800,
        'selling_price': 1600,
        'stock': 24,
        'active': 1,
        'is_sold_by_weight': 0,
      });

      expect(legacy.trackBatches, isFalse);
      expect(legacy.lotDeductionPolicy, 'fefo');
      expect(legacy.allowSellExpired, isFalse);
      expect(legacy.hasProductionRecipe, isFalse);
      expect(legacy.recipeYieldQuantity, 1.0);
      expect(legacy.recipeIngredients, isNull);
    });

    test('ProductBatchesResponse & ProductionOrderModel parsean lotes, reservas y consumos', () {
      final batchesRes = ProductBatchesResponse.fromJson({
        'product_id': 42,
        'product_name': 'Chocotorta',
        'track_batches': true,
        'lot_deduction_policy': 'fefo',
        'allow_sell_expired': false,
        'stock': 5,
        'expiration_date': '2026-11-18',
        'batches': [
          {
            'id': 10,
            'product_id': 42,
            'batch_code': 'OP-001',
            'source_type': 'production_order',
            'production_order_id': 3,
            'manufactured_at': '2026-11-15',
            'expiration_date': '2026-11-18',
            'days_until_expiry': 2,
            'is_expired': false,
            'initial_quantity': 6,
            'remaining_quantity': 5,
            'reserved_quantity': 1,
            'available_to_sell': 4,
            'unit_cost': 3200.5,
            'status': 'active',
          },
          {
            'id': 11,
            'product_id': 42,
            'batch_code': 'DEFICIT-AUTO',
            'source_type': 'deficit_auto',
            'is_expired': false,
            'initial_quantity': -2,
            'remaining_quantity': -2,
            'reserved_quantity': 0,
            'available_to_sell': 0,
            'status': 'deficit',
          },
        ],
      });

      expect(batchesRes.batches.length, 2);
      expect(batchesRes.batches[0].isActive, isTrue);
      expect(batchesRes.batches[0].availableToSell, 4.0);
      expect(batchesRes.batches[0].unitCost, 3200.5);
      expect(batchesRes.batches[1].isDeficit, isTrue);
      expect(batchesRes.batches[1].remainingQuantity, -2.0);

      final order = ProductionOrderModel.fromJson({
        'id': 3,
        'order_number': 'OP-20261115-001',
        'product_id': 42,
        'quantity_produced': 6,
        'total_cost': 19203,
        'unit_cost': 3200.5,
        'status': 'completed',
        'product': {'id': 42, 'name': 'Chocotorta', 'unit_type': 'un'},
        'produced_batch': {
          'id': 10,
          'batch_code': 'OP-001',
          'expiration_date': '2026-11-18',
          'remaining_quantity': 5,
          'status': 'active',
        },
        'consumptions': [
          {
            'id': 91,
            'ingredient_product_id': 11,
            'batch_id': 5,
            'quantity_used': 1.5,
            'unit_cost': 2000,
            'subtotal_cost': 3000,
            'ingredient': {'id': 11, 'name': 'Crema', 'unit_type': 'kg'},
            'batch': {'id': 5, 'batch_code': 'FAC-019', 'expiration_date': '2026-11-17'},
          },
        ],
      });

      expect(order.orderNumber, 'OP-20261115-001');
      expect(order.producedBatchCode, 'OP-001');
      expect(order.consumptions.first.ingredientName, 'Crema');
      expect(order.consumptions.first.batchCode, 'FAC-019');
    });

    test('BatchBarcodeHelper codifica y decodifica etiquetas térmicas L#<id> y L#<id>#W#<gramos>', () {
      expect(BatchBarcodeHelper.encode(batchId: 42), 'L#42');
      expect(BatchBarcodeHelper.encode(batchId: 42, weightGrams: 500), 'L#42#W#500');
      expect(BatchBarcodeHelper.encode(batchId: 42, weightGrams: 375.5), 'L#42#W#375.5');

      final unit = BatchBarcodeHelper.parse('L#42');
      expect(unit, isNotNull);
      expect(unit!.batchId, 42);
      expect(unit.weightKg, isNull);

      final weighed = BatchBarcodeHelper.parse('l#88#W#750');
      expect(weighed, isNotNull);
      expect(weighed!.batchId, 88);
      expect(weighed.weightGrams, 750.0);
      expect(weighed.weightKg, closeTo(0.75, 0.0001));

      expect(BatchBarcodeHelper.parse('PRES-00012'), isNull);
      expect(BatchBarcodeHelper.parse('7791234567890'), isNull);
      expect(BatchBarcodeHelper.parse('L#abc'), isNull);
      expect(BatchBarcodeHelper.parse(''), isNull);
    });

    test('CartItem.toSalePayload envía batch_id solo cuando corresponde', () {
      final product = Product(
        id: 10,
        name: 'Tarta Frutilla',
        internalCode: '00010',
        costPrice: 1000,
        sellingPrice: 2500,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );

      final withBatch = CartItem(
        product: product,
        batchId: 77,
        batchCode: 'LOT-77',
        batchExpirationDate: '2026-11-20',
      );
      expect(withBatch.toSalePayload()['batch_id'], 77);

      final withoutBatch = CartItem(product: product);
      expect(withoutBatch.toSalePayload().containsKey('batch_id'), isFalse);
    });

    test('PosProvider separa ítems del mismo producto cuando pertenecen a lotes distintos y scanBatch URL-encodea #', () async {
      SharedPreferences.setMockInitialValues({});
      Uri? capturedUri;
      final mockClient = MockClient((req) async {
        capturedUri = req.url;
        if (req.url.path.endsWith('/pos/batches/scan')) {
          return http.Response(
            jsonEncode({
              'product': {
                'id': 10,
                'name': 'Tarta',
                'internal_code': '00010',
                'cost_price': 1000,
                'selling_price': 2500,
                'stock': 10,
                'active': true,
                'is_sold_by_weight': false,
                'track_batches': true,
              },
              'batch': {'id': 42, 'batch_code': 'LOT-42'},
              'can_sell': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final pos = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );

      final res = await pos.scanBatch('L#42');
      expect(capturedUri, isNotNull);
      expect(capturedUri!.queryParameters['code'], 'L#42');
      expect(capturedUri!.toString(), contains('L%2342'));
      expect(res['batch']['id'], 42);

      final prod = Product(
        id: 10,
        name: 'Tarta',
        internalCode: '00010',
        costPrice: 1000,
        sellingPrice: 2500,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );

      expect(pos.requestAddToCartWithPromo(prod, batchId: 1, batchCode: 'LOT-1'), isTrue);
      expect(pos.requestAddToCartWithPromo(prod, batchId: 1, batchCode: 'LOT-1'), isTrue);
      expect(pos.requestAddToCartWithPromo(prod, batchId: 2, batchCode: 'LOT-2'), isTrue);

      expect(pos.cart.length, 2);
      expect(pos.cart[0].batchId, 1);
      expect(pos.cart[0].quantity, 2.0);
      expect(pos.cart[1].batchId, 2);
      expect(pos.cart[1].quantity, 1.0);

      pos.setAuthorizedExpiredBatchPin('1234');
      expect(pos.authorizedExpiredBatchPin, '1234');
      pos.clearCart();
      expect(pos.authorizedExpiredBatchPin, isNull);
    });

    test('InventoryAlertsProvider carga deficit_alerts y envía batch_id al posponer alerta', () async {
      Map<String, dynamic>? snoozePayload;
      final mockClient = MockClient((req) async {
        if (req.url.path.endsWith('/inventory/alerts')) {
          return http.Response(
            jsonEncode({
              'alerts': [],
              'expiration_alerts': [
                {
                  'alert_type': 'expiration',
                  'alert_level': 'critical',
                  'product_id': 42,
                  'batch_id': 55,
                  'batch_code': 'LOT-55',
                  'product_name': 'Chocotorta',
                  'days_until_expiry': 1,
                  'expiry_stage_label': 'Último día',
                  'expiration_date': '2026-11-16',
                  'current_stock': 3,
                },
              ],
              'deficit_alerts': [
                {
                  'alert_type': 'deficit',
                  'product_id': 43,
                  'product_name': 'Medialuna',
                  'batch_code': 'DEFICIT-1',
                  'deficit_quantity': 6,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.endsWith('/snooze')) {
          snoozePayload = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('{}', 200);
      });

      final ds = InventoryAlertsDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final prov = InventoryAlertsProvider(dataSource: ds);

      await prov.fetchAlerts();
      expect(prov.expirationAlerts.length, 1);
      expect(prov.deficitAlerts.length, 1);
      expect(prov.totalAlertsCount, 2);
      expect(prov.getAlertStatusForProduct(43), 'deficit');

      final ok = await prov.snoozeExpirationAlert(
        42,
        action: 'snooze_days',
        days: 1,
        batchId: 55,
      );
      expect(ok, isTrue);
      expect(snoozePayload, isNotNull);
      expect(snoozePayload!['batch_id'], 55);
      expect(snoozePayload!['action'], 'snooze_days');
    });

    testWidgets('ProductBatchesDialog & ProductionOrdersDialog renderizan sin overflow en viewport compacto', (tester) async {
      tester.view.physicalSize = const Size(820, 680);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prod = Product(
        id: 42,
        name: 'Chocotorta Entera',
        internalCode: '00042',
        costPrice: 4000,
        sellingPrice: 9500,
        stock: 6,
        active: true,
        isSoldByWeight: false,
        trackBatches: true,
        hasProductionRecipe: true,
        recipeYieldQuantity: 6,
      );
      final fakeProvider = _FakeBatchCatalogProvider(prod);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductBatchesDialog(provider: fakeProvider, product: prod),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Lotes y Vencimientos: Chocotorta Entera'), findsOneWidget);
      expect(find.text('LOT-A'), findsOneWidget);
      expect(find.text('DÉFICIT'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionOrdersDialog(provider: fakeProvider, initialProduct: prod),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Producción Propia'), findsOneWidget);
      expect(find.text('Nueva Elaboración'), findsOneWidget);
      expect(find.text('Registrar e Imprimir L#'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('CatalogRemoteDataSourceImpl consume endpoints de planilla matutina, split freezer->vitrina y barrido de vencidos', () async {
      final calls = <String>[];
      final mockClient = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}?${req.url.query}');
        if (req.url.path.endsWith('/batches/expired')) {
          return http.Response(
            jsonEncode({
              'expired_count': 1,
              'expiring_today_count': 1,
              'batches': [
                {'id': 9, 'batch_code': 'MIG-1', 'remaining_quantity': 4},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.endsWith('/batches/9/split')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['quantity'], 2.0);
          return http.Response(
            jsonEncode({
              'batch': {'id': 15, 'product_id': 42, 'batch_code': 'MIG-1-V1'},
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.endsWith('/batches/write-off-expired')) {
          return http.Response(
            jsonEncode({'written_off_count': 1, 'total_cost_lost': 2400}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.endsWith('/production-orders/batch')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect((body['items'] as List).length, 2);
          return http.Response(
            jsonEncode({
              'total_orders': 2,
              'orders': [
                {
                  'id': 1,
                  'order_number': 'OP-001',
                  'product_id': 42,
                  'quantity_produced': 6,
                  'total_cost': 6000,
                  'unit_cost': 1000,
                  'status': 'completed',
                },
              ],
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      });

      final ds = CatalogRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: mockClient,
      );

      final expired = await ds.fetchExpiredBatches(includeToday: true);
      expect(expired['expired_count'], 1);

      final splitRes = await ds.splitBatch(9, quantity: 2.0, expirationDate: '2026-11-22');
      expect((splitRes['batch'] as Map)['batch_code'], 'MIG-1-V1');

      final sweepRes = await ds.writeOffExpiredBatches(includeToday: true);
      expect(sweepRes['written_off_count'], 1);

      final batchOrdersRes = await ds.createBatchProductionOrders({
        'items': [
          {'product_id': 42, 'quantity_produced': 6},
          {'product_id': 43, 'quantity_produced': 12},
        ],
      });
      expect(batchOrdersRes['total_orders'], 2);
      expect((batchOrdersRes['orders'] as List).first, isA<ProductionOrderModel>());
      expect(calls, containsAll([
        'GET /api/batches/expired?include_today=1',
        'POST /api/batches/9/split?',
        'POST /api/batches/write-off-expired?',
        'POST /api/production-orders/batch?',
      ]));
    });

    testWidgets('Planilla Matutina, Pasar a Vitrina, Barrido de Vencidos y PrintLabels precargado renderizan sin overflow', (tester) async {
      tester.view.physicalSize = const Size(820, 680);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prod = Product(
        id: 42,
        name: 'Chocotorta Entera',
        internalCode: '00042',
        costPrice: 4000,
        sellingPrice: 9500,
        stock: 6,
        active: true,
        isSoldByWeight: false,
        trackBatches: true,
        vencimientoDias: 4,
        hasProductionRecipe: true,
        recipeYieldQuantity: 6,
      );
      final fakeProvider = _FakeBatchCatalogProvider(prod);

      // 1. Modo Planilla Rápida Matutina + botones rápidos +1 / +6 / +12
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionOrdersDialog(provider: fakeProvider),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Planilla Rápida Matutina'));
      await tester.pumpAndSettle();
      expect(find.text('Solo con receta (1)'), findsOneWidget);

      await tester.tap(find.text('+6'));
      await tester.pumpAndSettle();
      expect(find.text('1 producto(s) con cantidad cargada'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 2. ProductBatchesDialog muestra botón Pasar a Vitrina y abre modal de Split
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductBatchesDialog(provider: fakeProvider, product: prod),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pasar a Vitrina (Dividir Lote)'));
      await tester.pumpAndSettle();
      expect(find.text('Pasar a Vitrina (Dividir Lote)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 3. ExpiredBatchesSweepDialog lista vencidos y actualiza totales
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExpiredBatchesSweepDialog(provider: fakeProvider),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Barrido de Lotes Vencidos (Cierre del Día)'), findsOneWidget);
      expect(find.textContaining('Medialunas del Día'), findsOneWidget);
      expect(find.text('Confirmar Baja (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 4. PrintLabelsDialog precarga initialQuantities y alterna con "1 por lote/bandeja"
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>(create: (_) => _FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => LocalTerminalProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PrintLabelsDialog(
                products: [prod],
                initialQuantities: const {42: 6},
                batchByProductId: const {
                  42: ProductBatchModel(
                    id: 1,
                    productId: 42,
                    batchCode: 'OP-001',
                    sourceType: 'production_order',
                    isExpired: false,
                    initialQuantity: 6,
                    remainingQuantity: 6,
                    reservedQuantity: 0,
                    availableToSell: 6,
                    status: 'active',
                  ),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Imprimir 6 etiquetas'), findsOneWidget);
      final leftListScrollable = find
          .descendant(
            of: find.descendant(
              of: find.byType(PrintLabelsDialog),
              matching: find.byType(ListView),
            ).first,
            matching: find.byType(Scrollable),
          )
          .first;
      final batchBarcodeTile = find.widgetWithText(
        CheckboxListTile,
        'Código de barras por lote (L#)',
      );
      await tester.scrollUntilVisible(
        batchBarcodeTile,
        120.0,
        scrollable: leftListScrollable,
      );
      expect(batchBarcodeTile, findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(batchBarcodeTile).value,
        isFalse,
      );
      await tester.tap(batchBarcodeTile);
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(batchBarcodeTile).value,
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.text('1 por lote/bandeja'),
        -120.0,
        scrollable: leftListScrollable,
      );
      await tester.tap(find.text('1 por lote/bandeja'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Imprimir 1 etiqueta'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Buscar "torta" en Producción Propia encuentra productos remotos fuera de página 1 y sin receta previa', (tester) async {
      tester.view.physicalSize = const Size(900, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final page1Prod = Product(
        id: 1,
        name: 'Aceite Girasol 900ml',
        internalCode: '00001',
        costPrice: 1500,
        sellingPrice: 2200,
        stock: 20,
        active: true,
        isSoldByWeight: false,
        hasProductionRecipe: true,
      );
      final remoteTorta = Product(
        id: 2561,
        name: 'TORTA MATILDA',
        internalCode: '02561',
        costPrice: 8000,
        sellingPrice: 18500,
        stock: 2,
        active: true,
        isSoldByWeight: false,
        hasProductionRecipe: false,
        vencimientoDias: 4,
      );

      final fakeProvider = _FakeBatchCatalogProvider(
        page1Prod,
        remoteMatches: [remoteTorta],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionOrdersDialog(provider: fakeProvider),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Abrir selector de producto terminado a producir
      await tester.tap(find.text('Aceite Girasol 900ml'));
      await tester.pumpAndSettle();

      // Escribir "torta" en el buscador del picker -> dispara onRemoteSearch tras debounce
      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar por nombre, código o barras...'),
        'torta',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('TORTA MATILDA'), findsOneWidget);
      await tester.tap(find.text('TORTA MATILDA'));
      await tester.pumpAndSettle();

      expect(find.text('TORTA MATILDA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Planilla Rápida Matutina permite definir días de validez por producto y envía vencimiento_dias + expiration_date al backend',
      (tester) async {
        tester.view.physicalSize = const Size(980, 740);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final medialuna = Product(
          id: 501,
          name: 'Medialunas Manteca x Docena',
          internalCode: '00501',
          costPrice: 1200,
          sellingPrice: 3600,
          stock: 4,
          active: true,
          isSoldByWeight: false,
          hasProductionRecipe: true,
          recipeYieldQuantity: 1,
          vencimientoDias: null,
        );
        final fakeProvider = _FakeBatchCatalogProvider(medialuna);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProductionOrdersDialog(provider: fakeProvider),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Planilla Rápida Matutina'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Sin vto. (elegir fecha)'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('batch_validity_501')),
          '5',
        );
        await tester.pumpAndSettle();

        final expectedShort =
            DateFormat('dd/MM').format(DateTime.now().add(const Duration(days: 5)));
        expect(find.textContaining('Vence: $expectedShort (5d)'), findsOneWidget);

        await tester.tap(find.text('+6'));
        await tester.pumpAndSettle();
        expect(find.text('Registrar Horneada (1)'), findsOneWidget);

        await tester.tap(find.text('Registrar Horneada (1)'));
        await tester.pumpAndSettle();

        expect(fakeProvider.lastBatchPayload, isNotNull);
        final items = fakeProvider.lastBatchPayload!['items'] as List;
        expect(items.length, 1);
        final sent = items.first as Map<String, dynamic>;
        expect(sent['product_id'], 501);
        expect(sent['quantity_produced'], 6.0);
        expect(sent['vencimiento_dias'], 5);
        expect(
          sent['expiration_date'],
          DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 5))),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Lector USB (Enter) y celular Android (RemoteScannerService) funcionan en Producción Individual, Planilla Matutina y SearchableSelectField',
      (tester) async {
        tester.view.physicalSize = const Size(980, 740);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final page1 = Product(
          id: 1,
          name: 'Budín Base',
          internalCode: '00001',
          costPrice: 1000,
          sellingPrice: 2000,
          stock: 10,
          active: true,
          isSoldByWeight: false,
          hasProductionRecipe: true,
        );
        final remoteTorta = Product(
          id: 2561,
          name: 'TORTA MATILDA',
          internalCode: '02561',
          barcode: '7799990002561',
          costPrice: 8000,
          sellingPrice: 18500,
          stock: 2,
          active: true,
          isSoldByWeight: false,
          hasProductionRecipe: false,
          vencimientoDias: 4,
        );
        final remoteChocolate = Product(
          id: 902,
          name: 'Chocolate Cobertura Semiamargo',
          internalCode: '00902',
          barcode: '7790001112223',
          costPrice: 4500,
          sellingPrice: 6000,
          stock: 5,
          active: true,
          isSoldByWeight: false,
        );

        final fakeProvider = _FakeBatchCatalogProvider(
          page1,
          remoteMatches: [remoteTorta, remoteChocolate],
        );
        final scanner = RemoteScannerService(autoConnect: false);
        addTearDown(scanner.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider<RemoteScannerService>.value(
            value: scanner,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: ElevatedButton(
                      onPressed: () => showDialog<void>(
                        context: ctx,
                        builder: (_) => ProductionOrdersDialog(provider: fakeProvider),
                      ),
                      child: const Text('Abrir Producción'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Abrir Producción'));
        await tester.pumpAndSettle();

        // 1. Escaneo desde celular Android en Producción Individual -> selecciona TORTA MATILDA remota
        expect(scanner.handleIncomingBarcode('7799990002561'), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('TORTA MATILDA'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(const ValueKey('single_validity_days_field'))).controller?.text,
          '4',
        );

        // 2. "+ Agregar insumo" abre SearchableSelectField directo; escaneo Android agrega Chocolate Cobertura
        await tester.tap(find.text('Agregar insumo'));
        await tester.pumpAndSettle();
        expect(scanner.handleIncomingBarcode('7790001112223'), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Chocolate Cobertura Semiamargo'), findsOneWidget);

        // 3. Planilla Rápida Matutina: escaneo Android (+1) y USB Enter en campo de búsqueda (+1)
        await tester.tap(find.text('Planilla Rápida Matutina'));
        await tester.pumpAndSettle();

        expect(scanner.handleIncomingBarcode('7799990002561'), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('1 producto(s) con cantidad cargada'), findsOneWidget);

        final batchFilterField = find.widgetWithText(
          TextField,
          'Buscar / barras...',
        );
        await tester.enterText(batchFilterField, '7799990002561');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.textContaining('+1 un cargado para "TORTA MATILDA"'), findsWidgets);
        expect(find.text('2'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Planilla Matutina actualiza todos los productos al cambiar de 5d a 7d o ingresar fecha/días globales y permite ajuste individual por fila',
      (tester) async {
        tester.view.physicalSize = const Size(980, 740);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final balcarce = Product(
          id: 2564,
          name: 'Torta Balcarce',
          internalCode: '02564',
          costPrice: 7000,
          sellingPrice: 17000,
          stock: 6,
          active: true,
          isSoldByWeight: false,
          hasProductionRecipe: true,
          vencimientoDias: 5,
        );
        final matilda = Product(
          id: 2561,
          name: 'TORTA MATILDA',
          internalCode: '02561',
          costPrice: 8000,
          sellingPrice: 18500,
          stock: 6,
          active: true,
          isSoldByWeight: false,
          hasProductionRecipe: true,
          vencimientoDias: 5,
        );

        final fakeProvider = _FakeBatchCatalogProvider(
          balcarce,
          extraInitialProducts: [matilda],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProductionOrdersDialog(provider: fakeProvider),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Planilla Rápida Matutina'));
        await tester.pumpAndSettle();

        // Inicialmente ambos muestran 5d
        expect(find.textContaining('(5d)'), findsNWidgets(2));

        // Tocar 5d y luego cambiar a 7d -> debe actualizar ambos productos a 7d
        await tester.tap(find.text('5d'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('7d'));
        await tester.pumpAndSettle();

        expect(find.textContaining('(7d)'), findsNWidgets(2));
        expect(
          tester.widget<TextField>(find.byKey(const ValueKey('batch_global_validity_days_field'))).controller?.text,
          '7',
        );
        final expected7d = DateFormat('dd/MM/yy').format(DateTime.now().add(const Duration(days: 7)));
        expect(find.text('Vence: $expected7d'), findsOneWidget);

        // Escribir manualmente 10 días globales -> actualiza ambos y botón de fecha global
        await tester.enterText(
          find.byKey(const ValueKey('batch_global_validity_days_field')),
          '10',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('(10d)'), findsNWidgets(2));
        final expected10d = DateFormat('dd/MM/yy').format(DateTime.now().add(const Duration(days: 10)));
        expect(find.text('Vence: $expected10d'), findsOneWidget);

        // Ajuste individual solo en TORTA MATILDA (3 días) sin modificar Torta Balcarce (10 días)
        await tester.enterText(
          find.byKey(const ValueKey('batch_validity_2561')),
          '3',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('(3d)'), findsOneWidget);
        expect(find.textContaining('(10d)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Planilla Matutina conserva franja de cargados al cambiar de búsqueda y muestra cargados arriba de todo al limpiar el buscador',
      (tester) async {
        tester.view.physicalSize = const Size(980, 740);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final tortaMatilda = Product(
          id: 2561,
          name: 'TORTA MATILDA',
          internalCode: '02561',
          costPrice: 8000,
          sellingPrice: 18500,
          stock: 6,
          active: true,
          isSoldByWeight: false,
          hasProductionRecipe: false,
        );
        final tartaFrutilla = Product(
          id: 3001,
          name: 'Tarta de Frutilla',
          internalCode: '03001',
          costPrice: 5000,
          sellingPrice: 12000,
          stock: 3,
          active: true,
          isSoldByWeight: false,
          hasProductionRecipe: true,
        );
        final pastafrola = Product(
          id: 3002,
          name: 'Pastafrola Membrillo',
          internalCode: '03002',
          costPrice: 3500,
          sellingPrice: 8500,
          stock: 4,
          active: true,
          isSoldByWeight: false,
          hasProductionRecipe: false,
        );

        final fakeProvider = _FakeBatchCatalogProvider(
          tartaFrutilla,
          extraInitialProducts: [tortaMatilda, pastafrola],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProductionOrdersDialog(provider: fakeProvider),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Planilla Rápida Matutina'));
        await tester.pumpAndSettle();

        final searchField = find.widgetWithText(TextField, 'Buscar / barras...');

        // 1. Buscar TORTA (sin receta), cargar +1 y asignar 7d
        await tester.enterText(searchField, 'TORTA');
        await tester.pumpAndSettle();
        await tester.tap(find.text('+1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('7d'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('batch_selected_strip')), findsOneWidget);
        expect(find.textContaining('TORTA MATILDA: 1 un • 7d'), findsOneWidget);

        // 2. Buscar Tarta, cargar +6 y asignar 3d (NO pisa el 7d de TORTA MATILDA)
        await tester.enterText(searchField, 'Tarta');
        await tester.pumpAndSettle();
        await tester.tap(find.text('+6'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('3d'));
        await tester.pumpAndSettle();

        expect(find.textContaining('TORTA MATILDA: 1 un • 7d'), findsOneWidget);
        expect(find.textContaining('Tarta de Frutilla: 6 un • 3d'), findsOneWidget);

        // 3. Dejar buscador en blanco -> ambos cargados quedan visibles juntos arriba de todo
        await tester.enterText(searchField, '');
        await tester.pumpAndSettle();

        expect(find.text('TORTA MATILDA'), findsOneWidget);
        expect(find.text('Tarta de Frutilla'), findsOneWidget);
        expect(find.text('Pastafrola Membrillo'), findsNothing);
        expect(find.text('CARGADO'), findsNWidgets(2));
        expect(find.byKey(const ValueKey('batch_only_selected_chip')), findsOneWidget);

        // 4. Tocar filtro Cargados (2) mantiene ambos visibles sin error
        await tester.tap(find.byKey(const ValueKey('batch_only_selected_chip')));
        await tester.pumpAndSettle();
        expect(find.text('TORTA MATILDA'), findsOneWidget);
        expect(find.text('Tarta de Frutilla'), findsOneWidget);
        expect(find.text('2 producto(s) con cantidad cargada'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Campanita: alerta vencida oculta umbral, permite merma sin lote y crea Liquidación con fecha futura sincronizada en caja POS',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});

        final pastExpDate = DateFormat('yyyy-MM-dd').format(
          DateTime.now().subtract(const Duration(days: 4)),
        );
        final pastExpDisplay = DateFormat('dd/MM/yyyy').format(
          DateTime.now().subtract(const Duration(days: 4)),
        );
        final monitor = Product(
          id: 777,
          name: 'Monitor Xiaomi A27i P27FBA-RAGL de 27 pulgadas Full HD 16:9 100Hz',
          internalCode: 'PROD-2156',
          costPrice: 150000,
          sellingPrice: 100000,
          stock: 3,
          active: true,
          isSoldByWeight: false,
          expirationDate: pastExpDate,
        );

        final alertsClient = MockClient((req) async {
          if (req.url.path.endsWith('/inventory/alerts')) {
            return http.Response(
              jsonEncode({
                'alerts': [],
                'expiration_alerts': [
                  {
                    'alert_type': 'expiration',
                    'alert_level': 'critical',
                    'product_id': 777,
                    'batch_id': null,
                    'product_name': monitor.name,
                    'days_until_expiry': -4,
                    'expiry_stage_label': 'Vencido',
                    'expiration_date': pastExpDate,
                    'current_stock': 3,
                  },
                ],
                'deficit_alerts': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200);
        });

        final alertsProv = InventoryAlertsProvider(
          dataSource: InventoryAlertsDataSource(
            baseUrl: 'http://localhost/api',
            client: alertsClient,
          ),
        );
        final fakeOfferRepo = _FakeOfferRepository();
        final offerProv = OfferProvider(repository: fakeOfferRepo);
        final posDs = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: alertsClient);
        final posRepo = PosRepositoryImpl(remoteDataSource: posDs);
        final posProv = PosProvider(
          processSaleUseCase: ProcessSaleUseCase(posRepo),
          searchProductsUseCase: SearchProductsUseCase(posRepo),
          repository: posRepo,
          remoteDataSource: posDs,
        );
        expect(posProv.requestAddToCartWithPromo(monitor), isTrue);
        expect(posProv.cart.first.unitPrice, 100000.0);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<InventoryAlertsProvider>.value(value: alertsProv),
              ChangeNotifierProvider<OfferProvider>.value(value: offerProv),
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<CatalogProvider>(
                create: (_) => _FakeBatchCatalogProvider(monitor),
              ),
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _FakeSettingsProvider(),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
                  child: InventoryAlertsWidget(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Abrir la campanita
        await tester.tap(find.byIcon(Icons.notifications_active));
        await tester.pumpAndSettle();

        expect(find.text('Vencido'), findsOneWidget);

        // 2. Abrir menú de acciones de la alerta vencida
        await tester.tap(find.byIcon(Icons.snooze));
        await tester.pumpAndSettle();

        expect(find.text('Registrar Merma / Dar de baja stock'), findsOneWidget);
        expect(find.text('Actualizar fecha de vencimiento'), findsOneWidget);
        expect(find.textContaining('Silenciar hasta'), findsNothing);

        // 3. Elegir Crear Oferta de Liquidación (%)
        await tester.tap(find.text('Crear Oferta de Liquidación (%)'));
        await tester.pumpAndSettle();

        expect(find.text('Crear Oferta de Liquidación'), findsOneWidget);
        expect(
          find.textContaining('La fecha registrada ($pastExpDisplay) ya pasó'),
          findsOneWidget,
        );
        expect(find.textContaining(pastExpDisplay), findsNWidgets(1)); // Solo en el aviso, NO como fecha fin
        final suggestedEnd = DateFormat('dd/MM/yyyy').format(
          DateTime.now().add(const Duration(days: 3)),
        );
        expect(find.text('Válida hasta: $suggestedEnd'), findsOneWidget);

        // 4. Publicar Oferta y verificar vigencia futura + aplicación inmediata en caja
        await tester.tap(find.text('Publicar Oferta'));
        await tester.pumpAndSettle();

        expect(fakeOfferRepo.createdEndDate, isNotNull);
        expect(fakeOfferRepo.createdEndDate!.isAfter(DateTime.now()), isTrue);
        expect(posProv.cart.first.unitPrice, 70000.0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosQuickOffersDialog no genera RenderFlex overflow en Historial ni Activas con nombres largos',
      (tester) async {
        tester.view.physicalSize = const Size(920, 680);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});

        const longName =
            'Liquidación "Monitor Xiaomi A27i P27FBA-RAGL de 27 pulgadas Full HD 16:9 100Hz 6 ms com DisplayPort HDMI"';
        final sampleMonitor = Product(
          id: 777,
          name: 'Monitor Xiaomi A27i 27 pulgadas',
          internalCode: 'PROD-2156',
          costPrice: 150000,
          sellingPrice: 292820,
          stock: 3,
          active: true,
          isSoldByWeight: false,
        );
        final activeLong = OfferModel(
          id: 1,
          name: longName,
          type: 'percentage',
          discountPercentage: 30,
          periodType: 'custom',
          startDate: DateTime.now().subtract(const Duration(hours: 1)),
          endDate: DateTime.now().add(const Duration(days: 3)),
          isActive: true,
          products: [
            {'id': 777, 'name': sampleMonitor.name, 'selling_price': '292820', 'cost_price': '150000'},
          ],
        );
        final expiredLong = OfferModel(
          id: 2,
          name: longName,
          type: 'percentage',
          discountPercentage: 30,
          periodType: 'custom',
          startDate: DateTime.now().subtract(const Duration(days: 4)),
          endDate: DateTime.now().subtract(const Duration(days: 1)),
          isActive: true,
          products: [
            {'id': 777, 'name': sampleMonitor.name, 'selling_price': '292820', 'cost_price': '150000'},
          ],
        );

        final fakeOfferRepo = _FakeOfferRepository(
          initialActive: [activeLong],
          initialAll: [expiredLong, activeLong],
        );
        final offerProv = OfferProvider(repository: fakeOfferRepo);
        final mockClient = MockClient((_) async => http.Response('[]', 200));
        final posDs = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
        final posRepo = PosRepositoryImpl(remoteDataSource: posDs);
        final posProv = PosProvider(
          processSaleUseCase: ProcessSaleUseCase(posRepo),
          searchProductsUseCase: SearchProductsUseCase(posRepo),
          repository: posRepo,
          remoteDataSource: posDs,
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<OfferProvider>.value(value: offerProv),
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<CatalogProvider>(
                create: (_) => _FakeBatchCatalogProvider(sampleMonitor),
              ),
              ChangeNotifierProvider<SupplierProvider>(
                create: (_) => _FakeSupplierProvider(),
              ),
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _FakeSettingsProvider(),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: PosQuickOffersDialog(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Liquidación'), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Historial y Catálogo'));
        await tester.pumpAndSettle();
        expect(find.text('🔴 Vencida'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Campanita con lote: muestra 10 opciones compactas, adapta stage=7 y quitar vto limpia PosProvider',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});

        final soonExp = DateFormat('yyyy-MM-dd').format(
          DateTime.now().add(const Duration(days: 2)),
        );
        final cake = Product(
          id: 888,
          name: 'Torta Rogel Loteada',
          internalCode: 'PROD-888',
          costPrice: 5000,
          sellingPrice: 12000,
          stock: 4,
          active: true,
          isSoldByWeight: false,
          trackBatches: true,
          vencimientoDias: 4,
          expirationDate: soonExp,
        );

        String? capturedSnoozeAction;
        final alertsClient = MockClient((req) async {
          if (req.url.path.endsWith('/inventory/alerts')) {
            return http.Response(
              jsonEncode({
                'alerts': [],
                'expiration_alerts': [
                  {
                    'alert_type': 'expiration',
                    'alert_level': 'warning',
                    'stage': 7,
                    'stage_code': 'warning_7d',
                    'product_id': 888,
                    'batch_id': 55,
                    'batch_code': 'LOT-55',
                    'product_name': cake.name,
                    'days_until_expiry': 2,
                    'expiry_stage_label': 'Próximo',
                    'expiration_date': soonExp,
                    'current_stock': 4,
                  },
                ],
                'deficit_alerts': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path.endsWith('/snooze')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            capturedSnoozeAction = body['action']?.toString();
            return http.Response(
              jsonEncode({
                'message': 'Fecha de vencimiento quitada del producto.',
                'product': {
                  'id': 888,
                  'name': cake.name,
                  'internal_code': 'PROD-888',
                  'cost_price': 5000,
                  'selling_price': 12000,
                  'stock': 4,
                  'active': true,
                  'is_sold_by_weight': false,
                  'track_batches': true,
                  'vencimiento_dias': 4,
                  'expiration_date': null,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200);
        });

        final alertsProv = InventoryAlertsProvider(
          dataSource: InventoryAlertsDataSource(
            baseUrl: 'http://localhost/api',
            client: alertsClient,
          ),
        );
        final fakeOfferRepo = _FakeOfferRepository();
        final offerProv = OfferProvider(repository: fakeOfferRepo);
        final posDs = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: alertsClient);
        final posRepo = PosRepositoryImpl(remoteDataSource: posDs);
        final posProv = PosProvider(
          processSaleUseCase: ProcessSaleUseCase(posRepo),
          searchProductsUseCase: SearchProductsUseCase(posRepo),
          repository: posRepo,
          remoteDataSource: posDs,
        );
        expect(posProv.requestAddToCartWithPromo(cake), isTrue);
        expect(posProv.cart.first.product.expirationDate, soonExp);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<InventoryAlertsProvider>.value(value: alertsProv),
              ChangeNotifierProvider<OfferProvider>.value(value: offerProv),
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<CatalogProvider>(
                create: (_) => _FakeBatchCatalogProvider(cake),
              ),
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _FakeSettingsProvider(),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
                  child: InventoryAlertsWidget(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.notifications_active));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.snooze));
        await tester.pumpAndSettle();

        expect(find.text('Registrar Merma / Dar de baja lote'), findsOneWidget);
        expect(find.text('Transformar / Re-elaborar en receta'), findsOneWidget);
        expect(find.text('Crear Oferta de Liquidación (%)'), findsOneWidget);
        expect(find.text('Actualizar fecha de vencimiento'), findsOneWidget);
        expect(find.text('Silenciar hasta aviso crítico'), findsOneWidget);
        expect(find.text('Posponer por 1 día'), findsOneWidget);
        expect(find.text('Posponer por 3 días'), findsOneWidget);
        expect(find.text('Gestionar lotes del producto'), findsOneWidget);
        expect(find.text('Editar producto en Catálogo'), findsOneWidget);
        expect(find.text('Lote vendido / Quitar fecha vto.'), findsOneWidget);

        await tester.tap(find.text('Lote vendido / Quitar fecha vto.'));
        await tester.pumpAndSettle();
        expect(find.text('Quitar fecha de vencimiento'), findsOneWidget);

        await tester.tap(find.text('Quitar fecha'));
        await tester.pumpAndSettle();

        expect(capturedSnoozeAction, 'clear_expiration');
        expect(posProv.cart.first.product.expirationDate, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ProductionOrdersDialog en Transformación con fallback muestra banner origen y permite búsqueda remota',
      (tester) async {
        tester.view.physicalSize = const Size(980, 740);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final sourceCake = Product(
          id: 50,
          name: 'Bizcochuelo Vainilla',
          internalCode: '00050',
          costPrice: 2000,
          sellingPrice: 4500,
          stock: 6,
          active: true,
          isSoldByWeight: false,
          trackBatches: true,
        );
        final remoteDest = Product(
          id: 51,
          name: 'Torta Tres Leches Especial',
          internalCode: '00051',
          costPrice: 3500,
          sellingPrice: 9500,
          stock: 1,
          active: true,
          isSoldByWeight: false,
        );

        final fakeProvider = _FakeBatchCatalogProvider(
          sourceCake,
          remoteMatches: [remoteDest],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProductionOrdersDialog(
                provider: fakeProvider,
                filterIngredientProductId: sourceCake.id,
                initialExplicitBatchId: 55,
                initialExplicitBatchCode: 'LOT-55',
                initialExplicitBatchAvailableQty: 4,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Re-elaboración desde Bizcochuelo Vainilla • Lote LOT-55 (Disp: 4 un)'),
          findsOneWidget,
        );

        await tester.tap(find.byIcon(Icons.arrow_drop_down));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Buscar por nombre, código o barras...'),
          'Tres Leches',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.text('Torta Tres Leches Especial'), findsOneWidget);
        await tester.tap(find.text('Torta Tres Leches Especial'));
        await tester.pumpAndSettle();

        expect(find.text('Bizcochuelo Vainilla'), findsOneWidget);
        expect(find.textContaining('Disponible: 4 un'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'StockAdjustmentDialog en producto sin lotes muestra aviso de auto-activación y botón quitar vencimiento',
      (tester) async {
        tester.view.physicalSize = const Size(900, 740);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final sugar = Product(
          id: 901,
          name: 'Azúcar Ledesma 1kg',
          internalCode: '81201',
          costPrice: 900,
          sellingPrice: 1800,
          stock: 10,
          active: true,
          isSoldByWeight: false,
          trackBatches: false,
          vencimientoDias: 90,
        );
        final fakeProvider = _FakeBatchCatalogProvider(sugar);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChangeNotifierProvider<CatalogProvider>.value(
                value: fakeProvider,
                child: StockAdjustmentDialog(provider: fakeProvider, product: sugar),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Al guardar con lote o vencimiento, este producto activará el control por lotes automáticamente'),
          findsOneWidget,
        );
        expect(find.byTooltip('Quitar vencimiento'), findsOneWidget);

        await tester.tap(find.byTooltip('Quitar vencimiento'));
        await tester.pumpAndSettle();
        expect(find.text('Vencimiento (opc)'), findsOneWidget);
        expect(find.textContaining('activará el control por lotes'), findsNothing);

        await tester.enterText(
          find.widgetWithText(TextField, 'Código de Lote (opc.)'),
          'LED-2026',
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('activará el control por lotes automáticamente'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _FakeBatchCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final Product sample;
  final List<Product> extraInitialProducts;
  final List<Product> remoteMatches;
  Map<String, dynamic>? lastBatchPayload;
  _FakeBatchCatalogProvider(
    this.sample, {
    this.extraInitialProducts = const [],
    this.remoteMatches = const [],
  });

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  List<Product> get products => [sample, ...extraInitialProducts];

  @override
  Product? get lastUpdatedProduct => null;

  @override
  void syncProductSnapshot(Product updatedProduct) {}

  @override
  Future<Product?> resolveProductById(int productId) async {
    for (final p in [sample, ...extraInitialProducts, ...remoteMatches]) {
      if (p.id == productId) return p;
    }
    return null;
  }

  @override
  Future<List<Product>> searchProductsRemote(
    String query, {
    int perPage = 40,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [sample];
    final pool = [sample, ...remoteMatches];
    return pool
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.internalCode.toLowerCase().contains(q) ||
              (p.barcode?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> createBatchProductionOrders(
    Map<String, dynamic> payload,
  ) async {
    lastBatchPayload = payload;
    final items = (payload['items'] as List?) ?? const [];
    final orders = <ProductionOrderModel>[];
    for (int i = 0; i < items.length; i++) {
      final item = Map<String, dynamic>.from(items[i] as Map);
      orders.add(
        ProductionOrderModel(
          id: i + 1,
          orderNumber: 'OP-TEST-00${i + 1}',
          productId: (item['product_id'] as num).toInt(),
          productName: sample.name,
          unitType: sample.unitType,
          quantityProduced: (item['quantity_produced'] as num).toDouble(),
          totalCost: 1000,
          unitCost: 1000,
          status: 'completed',
          consumptions: const [],
          producedBatchId: 100 + i,
          producedBatchCode: 'OP-TEST-00${i + 1}',
          producedBatchExpiration: item['expiration_date']?.toString(),
        ),
      );
    }
    return {'total_orders': orders.length, 'orders': orders};
  }

  @override
  Future<List<Product>> fetchAllActiveProductsForProduction() async => [sample, ...extraInitialProducts];

  @override
  Future<ProductBatchesResponse> fetchProductBatches(
    int productId, {
    bool includeClosed = true,
  }) async {
    return const ProductBatchesResponse(
      productId: 42,
      productName: 'Chocotorta Entera',
      trackBatches: true,
      lotDeductionPolicy: 'fefo',
      allowSellExpired: false,
      stock: 6,
      expirationDate: '2026-11-18',
      batches: [
        ProductBatchModel(
          id: 1,
          productId: 42,
          batchCode: 'LOT-A',
          sourceType: 'production_order',
          expirationDate: '2026-11-18',
          daysUntilExpiry: 2,
          isExpired: false,
          initialQuantity: 8,
          remainingQuantity: 8,
          reservedQuantity: 1,
          availableToSell: 7,
          unitCost: 4000,
          status: 'active',
        ),
        ProductBatchModel(
          id: 2,
          productId: 42,
          batchCode: 'DEF-1',
          sourceType: 'deficit_auto',
          isExpired: false,
          initialQuantity: -2,
          remainingQuantity: -2,
          reservedQuantity: 0,
          availableToSell: 0,
          status: 'deficit',
        ),
      ],
    );
  }

  @override
  Future<Map<String, dynamic>> fetchProductionOrders({
    int page = 1,
    int? productId,
    String? status,
    String? search,
  }) async =>
      {'data': <ProductionOrderModel>[], 'current_page': 1, 'last_page': 1, 'total': 0};

  @override
  Future<Map<String, dynamic>> fetchWasteReport({
    String? startDate,
    String? endDate,
  }) async =>
      {
        'total_events': 0,
        'total_units_lost': 0,
        'total_cost_lost': 0,
        'movements': <dynamic>[],
      };

  @override
  Future<Map<String, dynamic>> fetchExpiredBatches({bool includeToday = true}) async =>
      {
        'expired_count': 1,
        'expiring_today_count': 0,
        'batches': [
          {
            'id': 9,
            'product_id': 42,
            'product_name': 'Medialunas del Día',
            'batch_code': 'MED-AYER',
            'unit_type': 'un',
            'remaining_quantity': 6,
            'unit_cost': 250,
            'expiration_date': '2026-11-17',
            'days_overdue': 1,
            'expires_today': false,
          },
        ],
      };

  @override
  List<Category> get categories => const [];

  @override
  List<Brand> get brands => const [];

  @override
  Future<void> loadMetadata({bool force = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings? get settings => const BusinessSettings(
        companyName: 'Test POS',
        features: FeatureFlags(fastPos: true, predictiveAlerts: false),
      );

  @override
  FeatureFlags get features => const FeatureFlags(fastPos: true, predictiveAlerts: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOfferRepository implements OfferRepository {
  final List<OfferModel> initialActive;
  final List<OfferModel> initialAll;
  DateTime? createdStartDate;
  DateTime? createdEndDate;

  _FakeOfferRepository({
    this.initialActive = const [],
    this.initialAll = const [],
  });

  @override
  Future<List<Product>> getProductsByIds(List<int> ids) async => const [];

  @override
  Future<List<OfferModel>> getActiveOffers() async => List.from(initialActive);

  @override
  Future<List<OfferModel>> getAllOffers({String? status, String? search}) async =>
      List.from(initialAll);

  @override
  Future<OfferModel> createOffer({
    required String name,
    String? description,
    required String type,
    double? discountPercentage,
    double? discountAmount,
    required String periodType,
    List<String>? daysOfWeek,
    DateTime? startDate,
    DateTime? endDate,
    required List<Map<String, dynamic>> products,
  }) async {
    createdStartDate = startDate;
    createdEndDate = endDate;
    return OfferModel(
      id: 99,
      name: name,
      description: description,
      type: type,
      discountPercentage: discountPercentage,
      discountAmount: discountAmount,
      periodType: periodType,
      daysOfWeek: daysOfWeek,
      startDate: startDate,
      endDate: endDate,
      isActive: true,
      products: products
          .map(
            (p) => {
              'id': p['product_id'],
              'name': 'Producto en Liquidación',
              'selling_price': '100000',
              'cost_price': '50000',
            },
          )
          .toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
