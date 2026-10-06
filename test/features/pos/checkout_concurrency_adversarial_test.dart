import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/entities/payment_method.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/checkout_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/mercadopago_qr_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/posnet_waiting_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// ─── MOCKS & FAKES ──────────────────────────────────────────────────────────

class AdversarialFakePosProvider extends ChangeNotifier implements PosProvider {
  final List<PaymentMethod> _paymentMethods;
  final List<CartItem> _cart = [];
  bool _isLoading = false;
  List<Map<String, dynamic>>? lastProcessedPayments;
  int processCheckoutCallCount = 0;

  AdversarialFakePosProvider({required List<PaymentMethod> paymentMethods})
      : _paymentMethods = paymentMethods;

  @override
  List<PaymentMethod> get paymentMethods => _paymentMethods;

  @override
  List<CartItem> get cart => _cart;

  @override
  bool get isLoading => _isLoading;

  void setIsLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  @override
  String? get printerWarning => null;

  @override
  String? get errorMessage => null;

  @override
  Customer? get lastSelectedCustomer => null;

  @override
  bool get currentRequiresDispatch => false;

  @override
  String get currentFulfillmentStatus => 'pending';

  @override
  double get shippingCost => 0.0;

  @override
  double get lastUsedShippingCost => 0.0;

  @override
  void setShippingCost(double cost) {
    notifyListeners();
  }

  @override
  void setLastSelectedCustomer(Customer? customer) {}

  @override
  void setCurrentLogistics(bool requiresDispatch, String fulfillmentStatus) {}

  @override
  void setPriceTier(
    PriceTier tier, {
    double? wholesaleFactor,
    double? cardFactor,
    double? customFactor,
    String? customLabel,
  }) {}

  @override
  PriceTier get activeTier => PriceTier.base;

  @override
  double get currentCustomFactor => 1.0;

  @override
  Future<bool> updatePaymentMethodSurcharge(int id, double newPct) async {
    notifyListeners();
    return true;
  }

  @override
  Future<bool> processCheckout({
    required int shiftId,
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    required String printerFormat,
    required LocalTerminalProvider localTerminal,
    int? userId,
    int? customerId,
    String? userName,
    BusinessSettings? settings,
    bool showPreview = true,
    bool requiresDispatch = false,
    String fulfillmentStatus = 'pending',
    dynamic checkDetails,
    String? deliveryAddress,
  }) async {
    processCheckoutCallCount++;
    lastProcessedPayments = payments;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _businessSettings = const BusinessSettings(
    companyName: 'Challenger POS Store',
    features: FeatureFlags(fastPos: true),
  );

  @override
  BusinessSettings? get settings => _businessSettings;

  @override
  String get currentPlan => 'premium';

  @override
  bool hasFeature(String featureName) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  String get terminalId => 'caja-challenger-1';

  @override
  String get printerFormat => 'thermal_80';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 99, 'name': 'Adversarial Tester'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCustomerProvider extends ChangeNotifier implements CustomerProvider {
  @override
  List<Customer> get customers => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCashRegisterProvider extends ChangeNotifier
    implements CashRegisterProvider {
  @override
  CashRegisterShift? get currentShift => CashRegisterShift(
        id: 10,
        cashRegisterId: 1,
        userId: 99,
        openedAt: DateTime.now(),
        openingBalance: 50000.0,
        status: 'open',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  @override
  Future<void> fetchCriticalAlerts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─── FIXTURES & HELPERS ──────────────────────────────────────────────────────

final adversarialMethods = [
  PaymentMethod(
    id: 1,
    name: 'Efectivo',
    code: 'efectivo',
    surchargeType: 'none',
    surchargeValue: 0.0,
    isCash: true,
    isActive: true,
    sortOrder: 1,
  ),
  PaymentMethod(
    id: 2,
    name: 'Mercado Pago QR',
    code: 'mercadopago_qr',
    surchargeType: 'none',
    surchargeValue: 0.0,
    isCash: false,
    isActive: true,
    sortOrder: 2,
  ),
  PaymentMethod(
    id: 3,
    name: 'Mercado Pago Point',
    code: 'mercadopago_point',
    surchargeType: 'none',
    surchargeValue: 0.0,
    isCash: false,
    isActive: true,
    sortOrder: 3,
  ),
];

Widget buildAdversarialCheckoutApp({
  required AdversarialFakePosProvider posProvider,
  ApiClient? apiClient,
  double total = 3000.0,
}) {
  final client = apiClient ??
      ApiClient(
        MockClient((request) async {
          return http.Response('{"success": true}', 200);
        }),
      );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PosProvider>.value(value: posProvider),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => FakeSettingsProvider(),
      ),
      ChangeNotifierProvider<LocalTerminalProvider>(
        create: (_) => FakeLocalTerminalProvider(),
      ),
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => FakeAuthProvider(),
      ),
      ChangeNotifierProvider<CustomerProvider>(
        create: (_) => FakeCustomerProvider(),
      ),
      ChangeNotifierProvider<CashRegisterProvider>(
        create: (_) => FakeCashRegisterProvider(),
      ),
      ChangeNotifierProvider<CatalogProvider>(
        create: (_) => FakeCatalogProvider(),
      ),
      Provider<ApiClient>.value(value: client),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CheckoutDialog(total: total),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auto_print_receipt': false,
      'show_preview_receipt': false,
      'pos_api': 'http://pos.test/api',
    });
  });

  group('Adversarial Challenge: Payment Bypass Attempts (mpPaid == false)', () {
    testWidgets('Bypass Attempt 1: Single QR line unpaid cannot submit (button disabled, 0 checkout calls)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 2500.0),
      );
      await tester.pumpAndSettle();

      // Switch to Mercado Pago QR
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();

      // Verify button state
      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNull,
          reason: 'CONFIRMAR PAGO button must be disabled when mpPaid is false');

      // Attempt bypass tap on disabled button
      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(posProvider.processCheckoutCallCount, equals(0),
          reason: 'No backend checkout call should be made when payment is unapproved');
      expect(posProvider.lastProcessedPayments, isNull);
    });

    testWidgets('Bypass Attempt 2: Single Point line unpaid cannot submit (button disabled, 0 checkout calls)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 4000.0),
      );
      await tester.pumpAndSettle();

      // Switch to Mercado Pago Point
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago Point').last);
      await tester.pumpAndSettle();

      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(posProvider.processCheckoutCallCount, equals(0));
      expect(posProvider.lastProcessedPayments, isNull);
    });

    testWidgets('Bypass Attempt 3: Split payment with cash + unapproved MP QR blocks entire checkout',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 5000.0),
      );
      await tester.pumpAndSettle();

      // Line 1 is Cash. Set amount to 2000.0
      final dynamic state = tester.state(find.byType(CheckoutDialog));
      final line1 = state.paymentLines.first as PaymentLine;
      line1.controller.text = '2000.0';
      await tester.pumpAndSettle();

      // Add Line 2 for the remaining 3000.0
      await tester.tap(find.text('Completar con otro método'));
      await tester.pumpAndSettle();

      expect(state.paymentLines.length, equals(2));
      final line2 = state.paymentLines[1] as PaymentLine;

      // Set line 2 to Mercado Pago QR
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();

      // Total balance is fully covered (2000 + 3000 = 5000), but Line 2 is MP and mpPaid == false
      expect(line2.mpPaid, isFalse);
      expect(state.paymentLines[0].amount + state.paymentLines[1].amount, equals(5000.0));

      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNull,
          reason: 'Checkout must remain blocked when any MP line in split payment is unapproved');

      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(posProvider.processCheckoutCallCount, equals(0));
    });
  });

  group('Adversarial Challenge: State Transitions (approval flips mpPaid and enables submission)', () {
    testWidgets('State Transition 1: Simulated QR approval transitions mpPaid=true, enables button, sends MP payload',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 3200.0),
      );
      await tester.pumpAndSettle();

      // Select QR
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();

      // Initially disabled
      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO')).onPressed,
        isNull,
      );

      // Simulate payment approval transition
      final dynamic state = tester.state(find.byType(CheckoutDialog));
      final line = state.paymentLines.first as PaymentLine;
      state.confirmMpPaymentForTesting(
        line,
        mpPaymentId: 'MP-PAY-APPROVED-101',
        mpOrderId: 'MP-ORD-APPROVED-202',
        externalReference: 'POS-REF-APPROVED-303',
      );
      await tester.pumpAndSettle();

      // Verify state transition
      expect(line.mpPaid, isTrue);
      expect(line.mpPaymentId, equals('MP-PAY-APPROVED-101'));
      expect(line.mpOrderId, equals('MP-ORD-APPROVED-202'));
      expect(line.mpExternalReference, equals('POS-REF-APPROVED-303'));

      // Verify UI reflects approval: Green chip visible, button enabled
      expect(find.text('Pago Aprobado (ID: MP-PAY-APPROVED-101)'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsAtLeastNWidgets(1));

      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNotNull,
          reason: 'Button must enable upon payment approval');

      // Submit checkout
      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      await tester.pumpAndSettle();

      expect(posProvider.processCheckoutCallCount, equals(1));
      expect(posProvider.lastProcessedPayments, isNotNull);
      final payment = posProvider.lastProcessedPayments!.first;
      expect(payment['payment_method_id'], equals(2));
      expect(payment['base_amount'], equals(3200.0));
      expect(payment['total_amount'], equals(3200.0));
      expect(payment['mp_payment_id'], equals('MP-PAY-APPROVED-101'));
      expect(payment['mp_order_id'], equals('MP-ORD-APPROVED-202'));
      expect(payment['reference_id'], equals('POS-REF-APPROVED-303'));
    });

    testWidgets('State Transition 2: Simulated Point approval transitions mpPaid=true, enables button, sends MP payload',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 1850.0),
      );
      await tester.pumpAndSettle();

      // Select Point
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago Point').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO')).onPressed,
        isNull,
      );

      final dynamic state = tester.state(find.byType(CheckoutDialog));
      final line = state.paymentLines.first as PaymentLine;
      state.confirmMpPaymentForTesting(
        line,
        mpPaymentId: 'POINT-PAY-555',
        mpOrderId: 'POINT-INTENT-777',
        externalReference: 'POS-POINT-REF-999',
      );
      await tester.pumpAndSettle();

      expect(line.mpPaid, isTrue);
      expect(find.text('Pago Aprobado (ID: POINT-PAY-555)'), findsOneWidget);

      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      await tester.pumpAndSettle();

      expect(posProvider.processCheckoutCallCount, equals(1));
      final payment = posProvider.lastProcessedPayments!.first;
      expect(payment['payment_method_id'], equals(3));
      expect(payment['mp_payment_id'], equals('POINT-PAY-555'));
      expect(payment['mp_order_id'], equals('POINT-INTENT-777'));
      expect(payment['reference_id'], equals('POS-POINT-REF-999'));
    });
  });

  group('Adversarial Challenge: Method Switching Attack (tampering and privilege leak prevention)', () {
    testWidgets('Method Switching Attack 1: Approved QR switched to Cash wipes all MP identifiers from payload',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 4500.0),
      );
      await tester.pumpAndSettle();

      // 1. Select QR
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();

      // 2. Mark QR as approved
      final dynamic state = tester.state(find.byType(CheckoutDialog));
      final line = state.paymentLines.first as PaymentLine;
      state.confirmMpPaymentForTesting(
        line,
        mpPaymentId: 'QR-TAMPER-SECRET-ID',
        mpOrderId: 'QR-TAMPER-ORD',
        externalReference: 'QR-TAMPER-REF',
      );
      await tester.pumpAndSettle();
      expect(line.mpPaid, isTrue);
      expect(line.mpPaymentId, equals('QR-TAMPER-SECRET-ID'));

      // 3. Attack: Switch dropdown from QR back to Efectivo (Cash)
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Efectivo').last);
      await tester.pumpAndSettle();

      // 4. Verify PaymentLine cleanly wiped all MP fields
      expect(line.method?.code, equals('efectivo'));
      expect(line.mpPaid, isFalse, reason: 'Switching method must reset mpPaid to false');
      expect(line.mpPaymentId, isNull, reason: 'Switching method must clean mpPaymentId');
      expect(line.mpOrderId, isNull, reason: 'Switching method must clean mpOrderId');
      expect(line.mpExternalReference, isNull, reason: 'Switching method must clean mpExternalReference');

      // 5. Submit cash payment
      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNotNull);
      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      await tester.pumpAndSettle();

      // 6. Verify payload does NOT leak any MP fields to backend
      expect(posProvider.lastProcessedPayments, isNotNull);
      final payment = posProvider.lastProcessedPayments!.first;
      expect(payment['payment_method_id'], equals(1));
      expect(payment.containsKey('mp_payment_id'), isFalse,
          reason: 'Cash payment must NEVER leak mp_payment_id');
      expect(payment.containsKey('mp_order_id'), isFalse,
          reason: 'Cash payment must NEVER leak mp_order_id');
      expect(payment.containsKey('reference_id'), isFalse,
          reason: 'Cash payment must NEVER leak reference_id');
    });

    testWidgets('Method Switching Attack 2: Approved QR switched to Point wipes IDs and instantly re-locks submission',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 6000.0),
      );
      await tester.pumpAndSettle();

      // 1. Select QR and approve it
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(CheckoutDialog));
      final line = state.paymentLines.first as PaymentLine;
      state.confirmMpPaymentForTesting(
        line,
        mpPaymentId: 'QR-APPROVAL-BEFORE-SWITCH',
        mpOrderId: 'QR-ORD-BEFORE-SWITCH',
        externalReference: 'QR-REF-BEFORE-SWITCH',
      );
      await tester.pumpAndSettle();

      // Button is enabled for QR
      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO')).onPressed,
        isNotNull,
      );

      // 2. Attack: Switch dropdown from QR to Point (attempting to piggyback QR approval onto Posnet)
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago Point').last);
      await tester.pumpAndSettle();

      // 3. Verify IDs wiped and button RE-LOCKED
      expect(line.method?.code, equals('mercadopago_point'));
      expect(line.mpPaid, isFalse, reason: 'Piggyback attack prevented: mpPaid must reset to false');
      expect(line.mpPaymentId, isNull);
      expect(line.mpOrderId, isNull);
      expect(line.mpExternalReference, isNull);

      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNull,
          reason: 'Switching to Point must re-lock checkout until Point approval is received');

      // Button to initiate Point payment is present
      expect(find.text('Enviar a Posnet Físico'), findsOneWidget);
    });

    testWidgets('Method Switching Attack 3: Approved Point switched to QR wipes IDs and instantly re-locks submission',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 3800.0),
      );
      await tester.pumpAndSettle();

      // 1. Select Point and approve it
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago Point').last);
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(CheckoutDialog));
      final line = state.paymentLines.first as PaymentLine;
      state.confirmMpPaymentForTesting(
        line,
        mpPaymentId: 'POINT-APPROVAL-BEFORE-SWITCH',
        mpOrderId: 'POINT-ORD-BEFORE-SWITCH',
        externalReference: 'POINT-REF-BEFORE-SWITCH',
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO')).onPressed,
        isNotNull,
      );

      // 2. Attack: Switch dropdown from Point to QR
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();

      // 3. Verify IDs wiped and button RE-LOCKED
      expect(line.method?.code, equals('mercadopago_qr'));
      expect(line.mpPaid, isFalse);
      expect(line.mpPaymentId, isNull);
      expect(line.mpOrderId, isNull);
      expect(line.mpExternalReference, isNull);

      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNull);
      expect(find.text('Generar QR Mercado Pago'), findsOneWidget);
    });
  });

  group('Adversarial Challenge: Standard POS Viewport Compliance (1280x900 & 1024x768)', () {
    testWidgets('Desktop Viewport 1280x900: CheckoutDialog renders with 0 overflow across all states',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 3500.0),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Switch to QR
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Approve QR
      final dynamic state = tester.state(find.byType(CheckoutDialog));
      final line = state.paymentLines.first as PaymentLine;
      state.confirmMpPaymentForTesting(line, mpPaymentId: 'MP-DESKTOP-101');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Desktop Viewport 1280x900: MercadoPagoQrDialog renders with 0 overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient(
        MockClient((request) async {
          if (request.url.path.contains('create-order')) {
            return http.Response(
              '{"success": true, "qr_data": "00020126440014AR.COM.MP.QR011000000000005204000053030325802AR5914MERCADO PAGO6007CORDOBA", "external_reference": "POS-REF-DESK-01", "order_id": "ORD-DESK-01"}',
              200,
            );
          }
          if (request.url.path.contains('cancel-order')) {
            return http.Response('{"success": true}', 200);
          }
          return http.Response('{"status": "pending"}', 200);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MercadoPagoQrDialog(
              amount: 2500.0,
              terminalId: 'caja-1',
              client: client,
              baseUrl: 'http://pos.test/api',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Mercado Pago QR'), findsOneWidget);

      await tester.tap(find.text('Cancelar Cobro QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('Desktop Viewport 1280x900: PosnetWaitingDialog renders with 0 overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient(
        MockClient((request) async {
          if (request.url.path.contains('create-point-intent')) {
            return http.Response(
              '{"success": true, "payment_intent_id": "INTENT-DESK-01", "external_reference": "POS-POINT-DESK-01"}',
              200,
            );
          }
          return http.Response('{"status": "pending"}', 200);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosnetWaitingDialog(
              amount: 1400.0,
              description: 'Venta Escritorio',
              client: client,
              baseUrl: 'http://pos.test/api',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Esperando tarjeta en el Posnet...'), findsOneWidget);

      await tester.tap(find.text('Cancelar Operación'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('Adversarial Challenge: Low Screen Constraint Defect Verification (320x480 & 360x640)', () {
    testWidgets('Constraint Defect 1: CheckoutDialog at 320x480 violates 0-overflow guarantee',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = AdversarialFakePosProvider(paymentMethods: adversarialMethods);
      await tester.pumpWidget(
        buildAdversarialCheckoutApp(posProvider: posProvider, total: 1500.0),
      );
      await tester.pumpAndSettle();

      // The 320x480 viewport constraint is strictly tested against 0 overflow
      expect(tester.takeException(), isNull,
          reason: 'CheckoutDialog must render with 0 RenderFlex overflow at 320x480');
    });

    testWidgets('Constraint Defect 2: MercadoPagoQrDialog at 360x640 violates 0-overflow guarantee (missing SingleChildScrollView)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient(
        MockClient((request) async {
          if (request.url.path.contains('create-order')) {
            return http.Response(
              '{"success": true, "qr_data": "00020126440014AR.COM.MP.QR011000000000005204000053030325802AR5914MERCADO PAGO6007CORDOBA", "external_reference": "POS-REF-MINI-01", "order_id": "ORD-MINI-01"}',
              200,
            );
          }
          if (request.url.path.contains('cancel-order')) {
            return http.Response('{"success": true}', 200);
          }
          return http.Response('{"status": "pending"}', 200);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MercadoPagoQrDialog(
              amount: 1999.99,
              terminalId: 'caja-1',
              client: client,
              baseUrl: 'http://pos.test/api',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull,
          reason: 'MercadoPagoQrDialog must render without overflow at 360x640');

      await tester.tap(find.text('Cancelar Cobro QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('Constraint Defect 3: PosnetWaitingDialog at 360x640 violates 0-overflow guarantee (missing SingleChildScrollView)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = ApiClient(
        MockClient((request) async {
          if (request.url.path.contains('create-point-intent')) {
            return http.Response(
              '{"success": true, "payment_intent_id": "INTENT-MINI-01", "external_reference": "POS-POINT-MINI-01"}',
              200,
            );
          }
          return http.Response('{"status": "pending"}', 200);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosnetWaitingDialog(
              amount: 850.50,
              description: 'Venta reducida',
              client: client,
              baseUrl: 'http://pos.test/api',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull,
          reason: 'PosnetWaitingDialog must render without overflow at 360x640');

      await tester.tap(find.text('Cancelar Operación'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
