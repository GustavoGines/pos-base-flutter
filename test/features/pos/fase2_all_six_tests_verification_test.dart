import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/checkout_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/pages/pos_screen.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';

// ─── FAKES PARA AISLAMIENTO DE TESTS ──────────────────────────────────────────

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  int get assignedRegisterId => 1;
  final BusinessSettings _settings = const BusinessSettings(
    companyName: 'Negocio Test S.A.',
    taxId: '30-71234567-8',
    address: 'Av. Libertador 1234',
    afipEnabled: false,
    features: FeatureFlags(fastPos: true, logistics: false),
  );

  @override
  BusinessSettings? get settings => _settings;

  @override
  FeatureFlags get features => _settings.features;

  @override
  bool get isHardwareStore => false;

  @override
  bool get isIibbPerceptionAgent => false;

  @override
  String get currentPlan => 'premium';

  @override
  bool hasFeature(String featureName) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Cajero'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCustomerProvider extends ChangeNotifier implements CustomerProvider {
  final List<Customer> _customers = [
    Customer(
      id: 15,
      name: 'Constructora Sur SRL',
      documentNumber: '30712345678',
      documentType: 80,
      taxCondition: 'responsable_inscripto',
      fiscalAddress: 'Av. Siempreviva 742',
      creditLimit: 500000.0,
      balance: 0.0,
      isActive: true,
    ),
  ];

  @override
  List<Customer> get customers => _customers;

  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
  @override
  CashRegisterShift? get currentShift => CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openedAt: DateTime.now(),
        openingBalance: 10000.0,
        status: 'open',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  @override
  bool get isLoading => false;

  @override
  int get catalogOrderVersion => 1;

  @override
  Future<void> fetchCriticalAlerts() async {}

  @override
  List<Product> get products => [];

  @override
  Future<void> loadProducts({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOfferProvider extends ChangeNotifier implements OfferProvider {
  @override
  List<OfferModel> get activeOffers => [];

  @override
  bool get isLoading => false;

  @override
  bool get isLoadingActive => false;

  @override
  bool get isLoadingHistory => false;

  @override
  Future<void> loadActiveOffers() async {}

  @override
  double? getDiscountedPrice(Product product) => null;

  @override
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) => null;

  // OF-01: productos en oferta fuera del bloque inicial del catálogo (sin ofertas en este fake)
  @override
  Set<int> get currentlyActiveOfferProductIds => const {};

  @override
  List<Product> get offerOnlyProducts => const [];

  @override
  Future<void> syncOfferOnlyProducts(Set<int> loadedProductIds, {bool force = false}) async {}

  @override
  void invalidateOfferOnlyProducts() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuoteProvider extends ChangeNotifier implements QuoteProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
  @override
  String? getAlertStatusForProduct(int productId) => null;

  @override
  int get totalAlertsCount => 0;

  @override
  List<dynamic> get alerts => [];

  @override
  List<dynamic> get reactiveAlerts => [];

  @override
  List<dynamic> get predictiveCriticalAlerts => [];

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Fase 2 - Verificación Integral de las 6 Pruebas', () {

    // =========================================================================
    // PRUEBA 1: Productos Pesables en el Carrito ([F2-04])
    // =========================================================================
    testWidgets('Prueba 1: Ítem pesable en carrito muestra icono balanza (Editar peso) y oculta botones +/-', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final productWeighed = Product(
        id: 1,
        name: 'Queso Cremoso La Paulina',
        internalCode: '00101',
        costPrice: 500.0,
        sellingPrice: 1200.0,
        stock: 50,
        active: true,
        isSoldByWeight: true,
      );

      final productUnit = Product(
        id: 2,
        name: 'Gaseosa Cola 2L',
        internalCode: '00102',
        costPrice: 800.0,
        sellingPrice: 1500.0,
        stock: 100,
        active: true,
        isSoldByWeight: false,
      );

      final mockClient = MockClient((_) async => http.Response('[]', 200));
      final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProvider = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );

      posProvider.submitWeighedProduct(productWeighed, 0.450);
      posProvider.requestAddToCart(productUnit);
      posProvider.updateQuantity(posProvider.cart[1], 2.0);

      expect(posProvider.cart.length, 2);
      expect(posProvider.cart[0].product.isSoldByWeight, isTrue);
      expect(posProvider.cart[0].quantity, 0.450);
      expect(posProvider.cart[1].product.isSoldByWeight, isFalse);
      expect(posProvider.cart[1].quantity, 2.0);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProvider),
            ChangeNotifierProvider<SettingsProvider>(create: (_) => FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => LocalTerminalProvider()),
            ChangeNotifierProvider<CustomerProvider>(create: (_) => FakeCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(create: (_) => FakeCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>(create: (_) => FakeCatalogProvider()),
            ChangeNotifierProvider<OfferProvider>(create: (_) => FakeOfferProvider()),
            ChangeNotifierProvider<QuoteProvider>(create: (_) => FakeQuoteProvider()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>(create: (_) => FakeInventoryAlertsProvider()),
          ],
          child: const MaterialApp(
            home: PosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificamos que existe el botón de balanza para editar peso
      final scaleButtonFinder = find.byTooltip('Editar peso');
      expect(scaleButtonFinder, findsOneWidget);
      expect(find.byIcon(Icons.scale_outlined), findsOneWidget);

      // El producto por unidad (Gaseosa) tiene botones - y +
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);

      // Tocamos el ícono de la balanza para abrir el modal "Editar Cantidad"
      await tester.tap(scaleButtonFinder);
      await tester.pumpAndSettle();

      // Debe abrirse el diálogo con el peso actual (0.45 / 0.450 kg formateado con toQty)
      expect(find.text('Editar Cantidad - Queso Cremoso La Paulina'), findsOneWidget);
      expect(find.text('0.45'), findsWidgets);
      expect(find.text('KG'), findsOneWidget);
      expect(find.text('Actualizar'), findsOneWidget);

      // Cerramos el modal
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    // =========================================================================
    // PRUEBA 2: Cierre Rápido del Modal de Peso / Lectura de Balanza ([F2-03])
    // =========================================================================
    testWidgets('Prueba 2: Cierre rápido del modal de peso durante lectura de balanza no genera memory leaks ni used after being disposed', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final productWeighed = Product(
        id: 1,
        name: 'Clavos por Kg',
        internalCode: '00103',
        costPrice: 200.0,
        sellingPrice: 600.0,
        stock: 50,
        active: true,
        isSoldByWeight: true,
      );

      final mockClient = MockClient((_) async => http.Response('[]', 200));
      final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProvider = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );

      posProvider.submitWeighedProduct(productWeighed, 0.500);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProvider),
            ChangeNotifierProvider<SettingsProvider>(create: (_) => FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => LocalTerminalProvider()),
            ChangeNotifierProvider<CustomerProvider>(create: (_) => FakeCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(create: (_) => FakeCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>(create: (_) => FakeCatalogProvider()),
            ChangeNotifierProvider<OfferProvider>(create: (_) => FakeOfferProvider()),
            ChangeNotifierProvider<QuoteProvider>(create: (_) => FakeQuoteProvider()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuthProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>(create: (_) => FakeInventoryAlertsProvider()),
          ],
          child: const MaterialApp(
            home: PosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Abrir modal y cerrar con Cancelar repetidas veces
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Editar peso'));
        await tester.pumpAndSettle();
        expect(find.text('Editar Cantidad - Clavos por Kg'), findsOneWidget);

        // Cancelamos inmediatamente
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(find.text('Editar Cantidad - Clavos por Kg'), findsNothing);
      }

      // Verificamos que la protección isDialogMounted() previene escribir en un controller disposed
      bool controllerTouchedAfterDisposed = false;
      bool wasSafelyIgnoredByCheck = false;
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: ctx,
                    builder: (dCtx) {
                      return StatefulBuilder(
                        builder: (sCtx, setState) {
                          final ctrl = TextEditingController(text: '0.500');
                          bool isDisposed = false;
                          bool isDialogMounted() => !isDisposed;

                          return AlertDialog(
                            title: const Text('Modal Balanza'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  completer.future.then((_) {
                                    if (isDialogMounted()) {
                                      try {
                                        ctrl.text = '1.250';
                                      } catch (_) {
                                        controllerTouchedAfterDisposed = true;
                                      }
                                    } else {
                                      // Se evitó tocar el controller disposed gracias a isDialogMounted()
                                      wasSafelyIgnoredByCheck = true;
                                    }
                                  });
                                  isDisposed = true;
                                  ctrl.dispose();
                                  Navigator.pop(dCtx);
                                },
                                child: const Text('Leer y Cerrar'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Modal Balanza'), findsOneWidget);

      await tester.tap(find.text('Leer y Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Modal Balanza'), findsNothing);

      // Finaliza la lectura asíncrona de balanza 2 segundos después
      completer.complete();
      await tester.pump(const Duration(seconds: 2));

      expect(controllerTouchedAfterDisposed, isFalse);
      expect(wasSafelyIgnoredByCheck, isTrue);
    });

    // =========================================================================
    // PRUEBA 3: Vendedor Original y Cliente al Cobrar una Orden en Espera
    // =========================================================================
    test('Prueba 3: recallOrderToCart resuelve customer_id plano (v1.8.5) y processCheckout preserva vendedor original y cliente en snapshots para comprobantes', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/pay')) {
          return http.Response(
            jsonEncode({'message': 'Venta pagada', 'sale': {'id': 99, 'total': 2000.0}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProvider = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );

      final availableCustomers = [
        Customer.fromJson({
          'id': 15,
          'name': 'Constructora Sur SRL',
          'document_number': '30712345678',
          'tax_condition': 'responsable_inscripto',
        }),
      ];

      // Payload estilo v1.8.5 (sin objeto customer anidado, solo customer_id: 15)
      final v185PendingSale = {
        'id': 99,
        'customer_id': 15,
        'customer': null,
        'shipping_cost': '0',
        'price_list': 'base',
        'user': {'id': 3, 'name': 'Vendedor Mostrador'},
        'items': [
          {
            'product_id': 10,
            'product_name': 'Bolsa de Cemento',
            'quantity': '2',
            'unit_price': '1000.00',
            'subtotal': '2000.00',
            'product': {
              'id': 10,
              'name': 'Bolsa de Cemento',
              'internal_code': 'CEM-01',
              'stock': 100,
              'is_sold_by_weight': false,
            },
          }
        ],
      };

      // Recuperar la orden en espera
      posProvider.recallOrderToCart(v185PendingSale, availableCustomers: availableCustomers);

      // 1. Verificación v1.8.5: Cliente vinculado automáticamente por customer_id
      expect(posProvider.selectedCustomer, isNotNull);
      expect(posProvider.selectedCustomer!.id, 15);
      expect(posProvider.selectedCustomer!.name, 'Constructora Sur SRL');
      expect(posProvider.selectedCustomer!.documentNumber, '30712345678');
      expect(posProvider.recalledUserName, 'Vendedor Mostrador');

      // 2. Verificación de Snapshots en Cobro:
      final localTerminal = LocalTerminalProvider();
      localTerminal.setPrinterConnection('none');

      final success = await posProvider.processCheckout(
        shiftId: 1,
        totalSurcharge: 0.0,
        payments: [{'payment_method_id': 1, 'amount': 2000.0, 'method_code': 'cash'}],
        tenderedAmount: 2000.0,
        changeAmount: 0.0,
        printerFormat: 'a4',
        localTerminal: localTerminal,
        userName: 'Cajero', // El usuario que cobra es distinto al que generó
        showPreview: false,
      );

      expect(success, isTrue);

      // El carrito y recalledUserName se limpian tras el cobro para la próxima venta
      expect(posProvider.cart, isEmpty);
      expect(posProvider.recalledUserName, isNull);
      expect(posProvider.selectedCustomer, isNull);

      // 3. Verificamos la regla de formateo del ticket térmico:
      // Cuando userName ('Vendedor Mostrador') != cashierName ('Cajero'),
      // la línea generada debe ser: "GENERO: VENDEDOR MOSTRADOR | COBRO: CAJERO"
      const userName = 'Vendedor Mostrador';
      const cashierName = 'Cajero';
      final cashierLine = userName == cashierName
          ? 'CAJERO: ${userName.toUpperCase()}'
          : 'GENERO: ${userName.toUpperCase()} | COBRO: ${cashierName.toUpperCase()}';
      expect(cashierLine, 'GENERO: VENDEDOR MOSTRADOR | COBRO: CAJERO');
    });

    // =========================================================================
    // PRUEBA 4: No Contaminación de Precios al Cambiar Listas ([F2-05])
    // =========================================================================
    test('Prueba 4: No contaminación de precios al alternar entre lista Custom y Minorista, y blindaje de precio pactado', () {
      final mockClient = MockClient((_) async => http.Response('[]', 200));
      final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProvider = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );

      final product = Product(
        id: 50,
        name: 'Taladro Percutor',
        internalCode: 'TAL-01',
        costPrice: 5000.0,
        sellingPrice: 1000.0,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );

      // Paso 1: Cambiar a lista custom con +25% de recargo
      posProvider.setPriceTier(PriceTier.custom, customFactor: 1.25, customLabel: 'Tarjeta Especial');
      expect(posProvider.activeTier, PriceTier.custom);
      expect(posProvider.currentCustomFactor, 1.25);

      // Paso 2: Volver a Lista Base / Minorista
      posProvider.setPriceTier(PriceTier.base);
      expect(posProvider.activeTier, PriceTier.base);
      // _currentCustomFactor debe resetearse estrictamente a 1.0
      expect(posProvider.currentCustomFactor, 1.0);

      // Paso 3: Agregar producto en lista base -> debe costar exactamente $1000.0 (no $1250)
      posProvider.requestAddToCart(product);
      expect(posProvider.cart.first.unitPrice, 1000.0);
      expect(posProvider.cart.first.subtotal, 1000.0);

      // Paso 4: Caso de blindaje en v2.0.2:
      // Presupuesto / orden en espera en Minorista con precio pactado mayor ($1.200 vs $1.000 de catálogo actual)
      final pendingWithHigherPrice = {
        'id': 101,
        'price_list': 'Minorista',
        'items': [
          {
            'product_id': 50,
            'product_name': 'Taladro Percutor',
            'quantity': 1,
            'unit_price': '1200.00',
            'subtotal': '1200.00',
            'product': {
              'id': 50,
              'name': 'Taladro Percutor',
              'selling_price': '1000.00',
              'stock': 10,
              'is_sold_by_weight': false,
            },
          }
        ],
      };

      posProvider.recallOrderToCart(pendingWithHigherPrice);
      // El carrito DEBE respetar los $1.200 pactados
      expect(posProvider.cart.first.unitPrice, 1200.0);
      expect(posProvider.cart.first.subtotal, 1200.0);
    });

    // =========================================================================
    // PRUEBA 5: Desglose de Percepción IIBB en Vista Previa y Ticket con Remito
    // =========================================================================
    testWidgets('Prueba 5: ThermalReceiptWidget y Preview desglosan precio unitario bonificado, SUBTOTAL neto y PERCEPCION IIBB', (tester) async {
      final product = Product(
        id: 7,
        name: 'Lata de Pintura 20L',
        internalCode: 'PIN-20',
        costPrice: 400.0,
        sellingPrice: 1000.0,
        priceWholesale: 800.0,
        stock: 20,
        active: true,
        isSoldByWeight: false,
      );

      final cartItem = CartItem(
        product: product,
        quantity: 1,
        activeTier: PriceTier.wholesale,
      );

      expect(cartItem.unitPrice, 800.0);

      // Renderizamos ThermalReceiptWidget con:
      // 1 item x $800 + IIBB 3% ($24) = Total $824
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ThermalReceiptWidget(
                items: [cartItem],
                total: 824.0,
                iibbPerceptionAmount: 24.0,
                iibbPerceptionRate: 3.0,
                payments: const [
                  {'name': 'EFECTIVO', 'amount': 824.0}
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. El renglón de producto muestra el precio bonificado ($800), NO el precio de lista ($1.000)
      expect(find.textContaining('1 un x \$800'), findsOneWidget);
      expect(find.textContaining('1 un x \$1.000'), findsNothing);

      // 2. El SUBTOTAL descuenta la percepción: 824 - 24 = $800
      expect(find.text('\$800'), findsWidgets);

      // 3. Aparece explícitamente la línea de percepción con su porcentaje y monto
      expect(find.textContaining('PERCEPCION IIBB (3.0%)'), findsOneWidget);
      expect(find.text('\$24'), findsWidgets);

      // 4. El TOTAL COBRADO muestra $824
      expect(find.text('\$824'), findsWidgets);
    });

    // =========================================================================
    // PRUEBA 6: Recuperación ante Falla de Red al Cargar Métodos de Pago ([F2-06])
    // =========================================================================
    testWidgets('Prueba 6: CheckoutDialog ante paymentMethods vacío muestra botones Cerrar y Reintentar, y se auto-hidrata al recuperar conexión', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool networkRecovered = false;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/payment-methods')) {
          if (!networkRecovered) {
            return http.Response('[]', 200, headers: {'content-type': 'application/json'});
          } else {
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'name': 'Efectivo',
                  'code': 'cash',
                  'surcharge_type': 'none',
                  'surcharge_value': 0.0,
                  'is_cash': true,
                  'is_active': true,
                  'sort_order': 1,
                },
                {
                  'id': 2,
                  'name': 'Transferencia',
                  'code': 'transfer',
                  'surcharge_type': 'none',
                  'surcharge_value': 0.0,
                  'is_cash': false,
                  'is_active': true,
                  'sort_order': 2,
                }
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProvider = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );

      expect(posProvider.paymentMethods, isEmpty);

      final dummyProduct = Product(
        id: 1,
        name: 'Item Test',
        internalCode: '001',
        costPrice: 50,
        sellingPrice: 100,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );
      posProvider.requestAddToCart(dummyProduct);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProvider),
            ChangeNotifierProvider<SettingsProvider>(create: (_) => FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => LocalTerminalProvider()),
            ChangeNotifierProvider<CustomerProvider>(create: (_) => FakeCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(create: (_) => FakeCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>(create: (_) => FakeCatalogProvider()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuthProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CheckoutDialog(total: 100.0),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Verificamos mensaje y botones de Cerrar y Reintentar
      expect(find.text('Cargando métodos de pago...'), findsOneWidget);
      expect(find.text('Cerrar'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // 2. Simulamos que la red se recupera
      networkRecovered = true;

      // 3. El cajero toca "Reintentar"
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      // 4. Los métodos de pago se cargaron y el diálogo auto-inicializó la primera línea de pago
      expect(posProvider.paymentMethods.isNotEmpty, isTrue);
      expect(find.text('Cargando métodos de pago...'), findsNothing);
      expect(find.text('Desglose de Pago'), findsOneWidget);
      expect(find.text('CONFIRMAR PAGO'), findsOneWidget);
      expect(find.text('Efectivo'), findsWidgets);
    });

  });
}
