import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/sale.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/checkout_dialog.dart';

import 'providers/pos_provider_test.mocks.dart';

void main() {
  group('PosProvider IIBB Perception Math & State Tests', () {
    late PosProvider provider;
    late MockProcessSaleUseCase mockProcessSaleUseCase;
    late MockSearchProductsUseCase mockSearchProductsUseCase;
    late MockPosRepository mockPosRepository;

    final product1 = Product(
      id: 1,
      name: 'Yerba Mate 1Kg',
      internalCode: 'P01',
      costPrice: 800,
      sellingPrice: 1210.0, // Incluye 21% IVA -> Neto $1000, IVA $210
      stock: 50,
      active: true,
      isSoldByWeight: false,
    );

    final customerWithPerception = Customer(
      id: 10,
      name: 'Distribuidora Mayorista SA',
      documentNumber: '30500010912',
      documentType: 80,
      taxCondition: 'responsable_inscripto',
      fiscalAddress: 'Av. Corrientes 500',
      creditLimit: 50000.0,
      balance: 0.0,
      isActive: true,
      appliesIibbPerception: true,
      iibbPerceptionRate: 3.5, // 3.5%
    );

    final customerWithoutPerception = Customer(
      id: 11,
      name: 'Kiosco El Paso',
      documentNumber: '20123456786',
      documentType: 80,
      taxCondition: 'monotributo',
      fiscalAddress: 'Calle Falsa 123',
      creditLimit: 10000.0,
      balance: 0.0,
      isActive: true,
      appliesIibbPerception: false,
      iibbPerceptionRate: null,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockProcessSaleUseCase = MockProcessSaleUseCase();
      mockSearchProductsUseCase = MockSearchProductsUseCase();
      mockPosRepository = MockPosRepository();

      when(mockPosRepository.fetchPaymentMethods()).thenAnswer((_) async => []);

      provider = PosProvider(
        processSaleUseCase: mockProcessSaleUseCase,
        searchProductsUseCase: mockSearchProductsUseCase,
        repository: mockPosRepository,
      );
    });

    test('Perception is 0.0 when business is NOT perception agent', () {
      provider.setIsIibbPerceptionAgent(false);
      provider.requestAddToCart(product1);
      provider.selectCustomer(customerWithPerception);

      expect(provider.appliesIibbPerception, isFalse);
      expect(provider.iibbPerceptionAmount, 0.0);
      expect(provider.cartTotal, 1210.0);
    });

    test('Perception is 0.0 when customer does not apply perception', () {
      provider.setIsIibbPerceptionAgent(true);
      provider.requestAddToCart(product1);
      provider.selectCustomer(customerWithoutPerception);

      expect(provider.appliesIibbPerception, isFalse);
      expect(provider.iibbPerceptionAmount, 0.0);
      expect(provider.cartTotal, 1210.0);
    });

    test('Perception applies genuine AFIP WSFEv1 math when agent & customer qualify', () {
      provider.setIsIibbPerceptionAgent(true);
      provider.requestAddToCart(product1);
      provider.selectCustomer(customerWithPerception);

      expect(provider.appliesIibbPerception, isTrue);
      expect(provider.iibbPerceptionRate, 3.5);

      // Math verification:
      // Subtotal = 1210.0
      // Net = round(1210.0 / 1.21, 2) = 1000.0
      // IVA = round(1210.0 - 1000.0, 2) = 210.0
      // Perception = round(1000.0 * 0.035, 2) = 35.0
      // Total = 1210.0 + 35.0 = 1245.0
      expect(provider.netSubtotal, 1000.0);
      expect(provider.cartNetSubtotal, 1000.0);
      expect(provider.ivaAmount, 210.0);
      expect(provider.cartIvaAmount, 210.0);
      expect(provider.iibbPerceptionAmount, 35.0);
      expect(provider.cartIibbPerceptionAmount, 35.0);
      expect(provider.cartTotal, 1245.0);
    });

    test('Adding multiple items scales perception proportionately', () {
      provider.setIsIibbPerceptionAgent(true);
      provider.selectCustomer(customerWithPerception);

      // Add 2 units of Yerba ($1210 x 2 = $2420)
      provider.requestAddToCart(product1);
      provider.requestAddToCart(product1);

      expect(provider.cartSubtotal, 2420.0);
      expect(provider.netSubtotal, 2000.0);
      expect(provider.ivaAmount, 420.0);
      expect(provider.iibbPerceptionAmount, 70.0); // 3.5% of 2000
      expect(provider.cartTotal, 2490.0); // 2420 + 70
    });

    test('Dynamically changes when customer is switched or cleared', () {
      provider.setIsIibbPerceptionAgent(true);
      provider.requestAddToCart(product1);

      // Initial: No customer
      expect(provider.appliesIibbPerception, isFalse);
      expect(provider.iibbPerceptionAmount, 0.0);
      expect(provider.cartTotal, 1210.0);

      // Step 1: Select perception customer
      provider.selectCustomer(customerWithPerception);
      expect(provider.appliesIibbPerception, isTrue);
      expect(provider.iibbPerceptionAmount, 35.0);
      expect(provider.cartTotal, 1245.0);

      // Step 2: Switch to non-perception customer
      provider.selectCustomer(customerWithoutPerception);
      expect(provider.appliesIibbPerception, isFalse);
      expect(provider.iibbPerceptionAmount, 0.0);
      expect(provider.cartTotal, 1210.0);

      // Step 3: Switch back and clearCart
      provider.selectCustomer(customerWithPerception);
      expect(provider.iibbPerceptionAmount, 35.0);

      provider.clearCart();
      expect(provider.cart.isEmpty, isTrue);
      expect(provider.selectedCustomer, isNull);
      expect(provider.iibbPerceptionAmount, 0.0);
      expect(provider.cartTotal, 0.0);
    });

    test('Checkout forwards iibbPerceptionAmount & iibbPerceptionRate to usecase', () async {
      provider.setIsIibbPerceptionAgent(true);
      provider.requestAddToCart(product1);
      provider.selectCustomer(customerWithPerception);

      final dummyShift = CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openedAt: DateTime.now(),
        openingBalance: 5000.0,
        status: 'open',
      );

      final dummySale = Sale(
        id: 101,
        total: 1245.0,
        paymentMethod: 'efectivo',
        shift: dummyShift,
        iibbPerceptionAmount: 35.0,
        iibbPerceptionRate: 3.5,
      );

      when(mockProcessSaleUseCase.call(
        total: anyNamed('total'),
        totalSurcharge: anyNamed('totalSurcharge'),
        iibbPerceptionAmount: anyNamed('iibbPerceptionAmount'),
        iibbPerceptionRate: anyNamed('iibbPerceptionRate'),
        payments: anyNamed('payments'),
        tenderedAmount: anyNamed('tenderedAmount'),
        changeAmount: anyNamed('changeAmount'),
        shiftId: anyNamed('shiftId'),
        items: anyNamed('items'),
        userId: anyNamed('userId'),
        customerId: anyNamed('customerId'),
        quoteId: anyNamed('quoteId'),
        status: anyNamed('status'),
        requiresDispatch: anyNamed('requiresDispatch'),
        fulfillmentStatus: anyNamed('fulfillmentStatus'),
        checkDetails: anyNamed('checkDetails'),
        deliveryAddress: anyNamed('deliveryAddress'),
        shippingCost: anyNamed('shippingCost'),
        priceList: anyNamed('priceList'),
      )).thenAnswer((_) async => dummySale);

      final mockTerminal = FakeTestTerminalProvider();

      final success = await provider.processCheckout(
        shiftId: 1,
        totalSurcharge: 0.0,
        payments: [{'payment_method_id': 1, 'amount': 1245.0}],
        tenderedAmount: 1245.0,
        changeAmount: 0.0,
        printerFormat: 'thermal_80',
        localTerminal: mockTerminal,
        iibbPerceptionAmount: 35.0,
        iibbPerceptionRate: 3.5,
      );

      expect(provider.errorMessage, isNull);
      expect(success, isTrue);
      verify(mockProcessSaleUseCase.call(
        total: 1245.0,
        totalSurcharge: 0.0,
        iibbPerceptionAmount: 35.0,
        iibbPerceptionRate: 3.5,
        payments: anyNamed('payments'),
        tenderedAmount: anyNamed('tenderedAmount'),
        changeAmount: anyNamed('changeAmount'),
        shiftId: 1,
        items: anyNamed('items'),
        userId: anyNamed('userId'),
        customerId: anyNamed('customerId'),
        quoteId: anyNamed('quoteId'),
        status: anyNamed('status'),
        requiresDispatch: anyNamed('requiresDispatch'),
        fulfillmentStatus: anyNamed('fulfillmentStatus'),
        checkDetails: anyNamed('checkDetails'),
        deliveryAddress: anyNamed('deliveryAddress'),
        shippingCost: anyNamed('shippingCost'),
        priceList: anyNamed('priceList'),
      )).called(1);
    });
  });

  group('CheckoutDialog IIBB Perception UI Tests', () {
    final customerWithPerception = Customer(
      id: 20,
      name: 'Comercial del Norte SA',
      documentNumber: '30500010912',
      documentType: 80,
      taxCondition: 'responsable_inscripto',
      fiscalAddress: 'Av. Libertador 1000',
      creditLimit: 50000.0,
      balance: 0.0,
      isActive: true,
      appliesIibbPerception: true,
      iibbPerceptionRate: 3.0,
    );

    testWidgets('CheckoutDialog shows Percep. IIBB row when customer applies perception', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockProcessSaleUseCase = MockProcessSaleUseCase();
      final mockSearchProductsUseCase = MockSearchProductsUseCase();
      final mockPosRepository = MockPosRepository();

      when(mockPosRepository.fetchPaymentMethods()).thenAnswer((_) async => [
            {
              'id': 1,
              'name': 'Efectivo',
              'code': 'efectivo',
              'surcharge_type': 'none',
              'surcharge_value': 0.0,
              'is_cash': true,
              'is_active': true,
              'sort_order': 1,
            },
          ]);

      final posProvider = PosProvider(
        processSaleUseCase: mockProcessSaleUseCase,
        searchProductsUseCase: mockSearchProductsUseCase,
        repository: mockPosRepository,
      );

      posProvider.setIsIibbPerceptionAgent(true);
      posProvider.selectCustomer(customerWithPerception);

      final settingsProvider = FakeSettingsProviderWithPerception();
      final apiClient = ApiClient(
        MockClient((request) async => http.Response('{"success": true}', 200)),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
            ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => FakeTestTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => FakeTestAuthProvider()),
            ChangeNotifierProvider<CustomerProvider>(create: (_) => FakeTestCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>(create: (_) => FakeTestCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>(create: (_) => FakeTestCatalogProvider()),
            Provider<ApiClient>.value(value: apiClient),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CheckoutDialog(
                total: 1210.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Gran Total must be: 1210.0 + round(1000.0 * 0.03, 2) = 1210 + 30 = 1240.0
      expect(find.text('Percep. IIBB (3.0%)'), findsOneWidget);
      expect(find.text('Gran Total'), findsOneWidget);
    });
  });
}

// ── Test doubles for widgets ────────────────────────────────────────────────

class FakeTestTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get terminalId => 'term-1';
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get lockedPriceTier => 'none';
  @override
  double get posSplitRatio => 0.5;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Cajero'};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestCustomerProvider extends ChangeNotifier implements CustomerProvider {
  @override
  List<Customer> get customers => [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchCustomers({String? search}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
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

class FakeTestCatalogProvider extends ChangeNotifier implements CatalogProvider {
  @override
  Future<void> fetchCriticalAlerts() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProviderWithPerception extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings = const BusinessSettings(
    companyName: 'Empresa Mayorista SA',
    taxId: '30-50001091-2',
    address: 'Av. Corrientes 100',
    afipEnabled: true,
    isIibbPerceptionAgent: true,
    defaultIibbPerceptionRate: 3.0,
  );

  @override
  BusinessSettings? get settings => _settings;
  @override
  String get currentPlan => 'premium';
  @override
  bool hasFeature(String featureName) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
