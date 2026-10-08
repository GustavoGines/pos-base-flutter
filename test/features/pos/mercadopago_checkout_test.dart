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

// â”€â”€â”€ FAKE PROVIDERS & MOCKS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class FakePosProvider extends ChangeNotifier implements PosProvider {
  final List<PaymentMethod> _paymentMethods;
  final List<CartItem> _cart = [];
  final bool _isLoading = false;
  List<Map<String, dynamic>>? lastProcessedPayments;

  FakePosProvider({required List<PaymentMethod> paymentMethods})
      : _paymentMethods = paymentMethods;

  @override
  List<PaymentMethod> get paymentMethods => _paymentMethods;

  @override
  List<CartItem> get cart => _cart;

  @override
  bool get isLoading => _isLoading;

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
    double? iibbPerceptionAmount, double? iibbPerceptionRate, required List<Map<String, dynamic>> payments,
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
    lastProcessedPayments = payments;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _businessSettings = const BusinessSettings(
    companyName: 'POS Mercado Pago Test',
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
  String get terminalId => 'caja-1';

  @override
  String get printerFormat => 'thermal_80';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Cajero Test'};

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
  Future<void> fetchCriticalAlerts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// â”€â”€â”€ HELPERS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

final testPaymentMethods = [
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

Widget buildTestCheckoutDialog({
  required FakePosProvider posProvider,
  ApiClient? apiClient,
  double total = 2500.0,
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

Future<void> configureTestScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

// â”€â”€â”€ TEST SUITE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auto_print_receipt': false,
      'show_preview_receipt': false,
      'pos_api': 'http://pos.test/api',
    });
  });

  group('PaymentLine Unit Tests (Mercado Pago fields & logic)', () {
    test('PaymentLine initializes with mpPaid=false and null MP identifiers', () {
      final line = PaymentLine(
        method: testPaymentMethods[1], // mercadopago_qr
        initialAmount: 1500.0,
      );

      expect(line.mpPaid, isFalse);
      expect(line.mpPaymentId, isNull);
      expect(line.mpOrderId, isNull);
      expect(line.mpExternalReference, isNull);
      expect(line.amount, equals(1500.0));
      expect(line.total, equals(1500.0));
    });

    test('updateMethod clears MP fields when switching away from Mercado Pago', () {
      final line = PaymentLine(
        method: testPaymentMethods[1], // mercadopago_qr
        initialAmount: 1000.0,
      );
      line.mpPaid = true;
      line.mpPaymentId = 'MP-PAY-123';
      line.mpOrderId = 'MP-ORD-456';
      line.mpExternalReference = 'POS-EXT-789';

      expect(line.mpPaid, isTrue);

      // Cambiar a Efectivo
      line.updateMethod(testPaymentMethods[0]);

      expect(line.method?.code, equals('efectivo'));
      expect(line.mpPaid, isFalse);
      expect(line.mpPaymentId, isNull);
      expect(line.mpOrderId, isNull);
      expect(line.mpExternalReference, isNull);
    });

    test('updateMethod clears MP fields when switching between different MP methods', () {
      final line = PaymentLine(
        method: testPaymentMethods[1], // mercadopago_qr
        initialAmount: 1000.0,
      );
      line.mpPaid = true;
      line.mpPaymentId = 'MP-PAY-QR-123';

      // Cambiar de QR a Point
      line.updateMethod(testPaymentMethods[2]); // mercadopago_point

      expect(line.method?.code, equals('mercadopago_point'));
      expect(line.mpPaid, isFalse);
      expect(line.mpPaymentId, isNull);
    });

    test('Payload mapping correctly includes MP fields when mpPaid is true', () {
      final line = PaymentLine(
        method: testPaymentMethods[1],
        initialAmount: 2000.0,
      );
      line.mpPaid = true;
      line.mpPaymentId = '999888777';
      line.mpOrderId = 'ORD-555';
      line.mpExternalReference = 'POS-REF-333';

      final payload = {
        'payment_method_id': line.method!.id,
        'base_amount': line.amount,
        'surcharge_amount': line.surcharge,
        'total_amount': line.total,
        if (line.mpPaid) ...{
          'mp_payment_id': line.mpPaymentId,
          'mp_order_id': line.mpOrderId,
          'reference_id': line.mpExternalReference,
        },
      };

      expect(payload['payment_method_id'], equals(2));
      expect(payload['total_amount'], equals(2000.0));
      expect(payload['mp_payment_id'], equals('999888777'));
      expect(payload['mp_order_id'], equals('ORD-555'));
      expect(payload['reference_id'], equals('POS-REF-333'));
    });

    test('Payload mapping omits MP fields when mpPaid is false', () {
      final line = PaymentLine(
        method: testPaymentMethods[1],
        initialAmount: 2000.0,
      );
      line.mpPaid = false;
      line.mpPaymentId = 'ignored_id';

      final payload = {
        'payment_method_id': line.method!.id,
        'base_amount': line.amount,
        'surcharge_amount': line.surcharge,
        'total_amount': line.total,
        if (line.mpPaid) ...{
          'mp_payment_id': line.mpPaymentId,
          'mp_order_id': line.mpOrderId,
          'reference_id': line.mpExternalReference,
        },
      };

      expect(payload.containsKey('mp_payment_id'), isFalse);
      expect(payload.containsKey('mp_order_id'), isFalse);
      expect(payload.containsKey('reference_id'), isFalse);
    });
  });

  group('CheckoutDialog Widget Tests (Mercado Pago UI & Guarding)', () {
    testWidgets('Selecting mercadopago_qr displays "Generar QR Mercado Pago" and disables CONFIRMAR PAGO until paid',
        (WidgetTester tester) async {
      await configureTestScreen(tester);
      final posProvider = FakePosProvider(paymentMethods: testPaymentMethods);

      await tester.pumpWidget(
        buildTestCheckoutDialog(posProvider: posProvider, total: 3500.0),
      );
      await tester.pumpAndSettle();

      // Al inicio estÃ¡ seleccionado Efectivo, confirmar pago estÃ¡ habilitado
      final confirmBtnInitial = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtnInitial.onPressed, isNotNull);

      // Cambiar mÃ©todo a "Mercado Pago QR"
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();

      // 1. Verificar que aparece el botÃ³n "Generar QR Mercado Pago"
      expect(find.text('Generar QR Mercado Pago'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner), findsAtLeastNWidgets(1));

      // 2. Verificar que CONFIRMAR PAGO estÃ¡ estrictamente DESHABILITADO (_canSubmit == false)
      final confirmBtnAfterMp = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtnAfterMp.onPressed, isNull);
    });

    testWidgets('Selecting mercadopago_point displays "Enviar a Posnet FÃ­sico" and disables CONFIRMAR PAGO until paid',
        (WidgetTester tester) async {
      await configureTestScreen(tester);
      final posProvider = FakePosProvider(paymentMethods: testPaymentMethods);

      await tester.pumpWidget(
        buildTestCheckoutDialog(posProvider: posProvider, total: 4200.0),
      );
      await tester.pumpAndSettle();

      // Cambiar mÃ©todo a "Mercado Pago Point"
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mercado Pago Point').last);
      await tester.pumpAndSettle();

      // 1. Verificar que aparece el botÃ³n "Enviar a Posnet FÃ­sico"
      expect(find.text('Enviar a Posnet FÃ­sico'), findsOneWidget);
      expect(find.byIcon(Icons.point_of_sale), findsAtLeastNWidgets(1));

      // 2. Verificar que CONFIRMAR PAGO estÃ¡ estrictamente DESHABILITADO (_canSubmit == false)
      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNull);
    });

    testWidgets('When mpPaid is true, CONFIRMAR PAGO is enabled, chip is rendered, and payload contains MP IDs',
        (WidgetTester tester) async {
      await configureTestScreen(tester);
      final posProvider = FakePosProvider(paymentMethods: testPaymentMethods);

      await tester.pumpWidget(
        buildTestCheckoutDialog(posProvider: posProvider, total: 5000.0),
      );
      await tester.pumpAndSettle();

      // Cambiar a Mercado Pago QR
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();

      // Interceptar y simular confirmaciÃ³n de pago
      final dynamic state = tester.state(find.byType(CheckoutDialog));
      final line = state.paymentLines.first as PaymentLine;
      state.confirmMpPaymentForTesting(
        line,
        mpPaymentId: 'MP-TEST-9988',
        mpOrderId: 'ORD-TEST-7766',
        externalReference: 'POS-REF-5544',
      );
      await tester.pumpAndSettle();

      // 1. Verificar que se renderiza el chip de Pago Aprobado con tilde verde
      expect(find.text('Pago Aprobado (ID: MP-TEST-9988)'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsAtLeastNWidgets(1));

      // 2. Verificar que CONFIRMAR PAGO ahora estÃ¡ HABILITADO
      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNotNull);

      // 3. Presionar CONFIRMAR PAGO y verificar que el payload incluye los campos de MP
      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      await tester.pumpAndSettle();

      expect(posProvider.lastProcessedPayments, isNotNull);
      final payment = posProvider.lastProcessedPayments!.first;
      expect(payment['payment_method_id'], equals(2));
      expect(payment['total_amount'], equals(5000.0));
      expect(payment['mp_payment_id'], equals('MP-TEST-9988'));
      expect(payment['mp_order_id'], equals('ORD-TEST-7766'));
      expect(payment['reference_id'], equals('POS-REF-5544'));
    });

    testWidgets('Posnet Point with mpPaid=true enables CONFIRMAR PAGO and sends point IDs in payload',
        (WidgetTester tester) async {
      await configureTestScreen(tester);
      final posProvider = FakePosProvider(paymentMethods: testPaymentMethods);

      await tester.pumpWidget(
        buildTestCheckoutDialog(posProvider: posProvider, total: 3000.0),
      );
      await tester.pumpAndSettle();

      // Cambiar a Mercado Pago Point
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago Point').last);
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(CheckoutDialog));
      final line = state.paymentLines.first as PaymentLine;
      state.confirmMpPaymentForTesting(
        line,
        mpPaymentId: 'POINT-PAY-1122',
        mpOrderId: 'POINT-INTENT-3344',
        externalReference: 'POS-POINT-REF-5566',
      );
      await tester.pumpAndSettle();

      // 1. Chip visible
      expect(find.text('Pago Aprobado (ID: POINT-PAY-1122)'), findsOneWidget);

      // 2. BotÃ³n habilitado
      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'),
      );
      expect(confirmBtn.onPressed, isNotNull);

      // 3. Procesar venta
      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      await tester.pumpAndSettle();

      expect(posProvider.lastProcessedPayments, isNotNull);
      final payment = posProvider.lastProcessedPayments!.first;
      expect(payment['payment_method_id'], equals(3));
      expect(payment['mp_payment_id'], equals('POINT-PAY-1122'));
      expect(payment['mp_order_id'], equals('POINT-INTENT-3344'));
      expect(payment['reference_id'], equals('POS-POINT-REF-5566'));
    });

    testWidgets('Tapping "Generar QR Mercado Pago" opens MercadoPagoQrDialog',
        (WidgetTester tester) async {
      await configureTestScreen(tester);
      final posProvider = FakePosProvider(paymentMethods: testPaymentMethods);

      final client = ApiClient(
        MockClient((request) async {
          if (request.url.path.contains('create-order')) {
            return http.Response(
              '{"success": true, "qr_data": "00020126...testqr", "external_reference": "POS-QR-99", "order_id": "ORD-QR-88"}',
              200,
            );
          }
          if (request.url.path.contains('status')) {
            return http.Response(
              '{"status": "pending"}',
              200,
            );
          }
          if (request.url.path.contains('cancel-order')) {
            return http.Response('{"success": true}', 200);
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      await tester.pumpWidget(
        buildTestCheckoutDialog(
          posProvider: posProvider,
          apiClient: client,
          total: 3500.0,
        ),
      );
      await tester.pumpAndSettle();

      // Cambiar a Mercado Pago QR
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago QR').last);
      await tester.pumpAndSettle();

      // Presionar botÃ³n Generar QR
      await tester.tap(find.text('Generar QR Mercado Pago'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(MercadoPagoQrDialog), findsOneWidget);
      expect(
        find.text('EscaneÃ¡ con Mercado Pago o cualquier billetera interoperable'),
        findsOneWidget,
      );

      // Cancelar diÃ¡logo para limpiar timers
      await tester.tap(find.text('Cancelar Cobro QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('Tapping "Enviar a Posnet FÃ­sico" opens PosnetWaitingDialog',
        (WidgetTester tester) async {
      await configureTestScreen(tester);
      final posProvider = FakePosProvider(paymentMethods: testPaymentMethods);

      final client = ApiClient(
        MockClient((request) async {
          if (request.url.path.contains('create-point-intent')) {
            return http.Response(
              '{"success": true, "payment_intent_id": "INTENT-99", "external_reference": "POS-POINT-99"}',
              200,
            );
          }
          if (request.url.path.contains('status')) {
            return http.Response(
              '{"status": "pending"}',
              200,
            );
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      await tester.pumpWidget(
        buildTestCheckoutDialog(
          posProvider: posProvider,
          apiClient: client,
          total: 3500.0,
        ),
      );
      await tester.pumpAndSettle();

      // Cambiar a Mercado Pago Point
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mercado Pago Point').last);
      await tester.pumpAndSettle();

      // Presionar botÃ³n Enviar a Posnet FÃ­sico
      await tester.tap(find.text('Enviar a Posnet FÃ­sico'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PosnetWaitingDialog), findsOneWidget);
      expect(find.text('Esperando tarjeta en el Posnet...'), findsOneWidget);

      // Cancelar diÃ¡logo para limpiar timers
      await tester.tap(find.text('Cancelar OperaciÃ³n'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}

