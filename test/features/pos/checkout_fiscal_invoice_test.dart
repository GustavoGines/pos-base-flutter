import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// ─── FAKES FOR TEST ISOLATION ────────────────────────────────────────────────

class FakeFiscalPosProvider extends ChangeNotifier implements PosProvider {
  final List<PaymentMethod> _methods = [
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
      name: 'Tarjeta Débito',
      code: 'debito',
      surchargeType: 'none',
      surchargeValue: 0.0,
      isCash: false,
      isActive: true,
      sortOrder: 2,
    ),
  ];

  @override
  List<PaymentMethod> get paymentMethods => _methods;

  @override
  List<CartItem> get cart => [];

  @override
  double get cartTotal => 1500.0;

  @override
  double get shippingCost => 0.0;

  @override
  double get lastUsedShippingCost => 0.0;

  @override
  bool get currentRequiresDispatch => false;

  @override
  String get currentFulfillmentStatus => 'pending';

  @override
  Customer? get lastSelectedCustomer => null;

  @override
  PriceTier get activeTier => PriceTier.base;

  @override
  double get currentCustomFactor => 1.0;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  String? get printerWarning => null;

  Map<String, dynamic>? capturedFiscalInvoiceData;
  List<Map<String, dynamic>>? capturedPayments;

  @override
  Map<String, dynamic>? get pendingFiscalInvoiceData => capturedFiscalInvoiceData;

  @override
  void setPendingFiscalInvoiceData(Map<String, dynamic>? data) {
    capturedFiscalInvoiceData = data;
  }

  @override
  void setShippingCost(double cost) {}

  @override
  void setCurrentLogistics(bool requires, String status) {}

  @override
  void setLastSelectedCustomer(Customer? customer) {}

  @override
  void setPriceTier(PriceTier tier, {double? wholesaleFactor, double? cardFactor, double? customFactor, String? customLabel}) {}

  @override
  Future<bool> updatePaymentMethodSurcharge(int id, double newPercentage) async => true;

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
    capturedPayments = payments;
    return true;
  }

  @override
  Future<bool> payPendingSale({
    required int saleId,
    required double saleTotal,
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    required int shiftId,
    required LocalTerminalProvider localTerminal,
    String? userName,
    BusinessSettings? settings,
    int? userId,
    List<CartItem>? items,
    bool showPreview = true,
    double shippingCost = 0.0,
    dynamic checkDetails,
  }) async {
    capturedPayments = payments;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings = const BusinessSettings(
    companyName: 'Comercio Fiscal Test',
    taxId: '30-50001091-2',
    address: 'Av. Libertador 1234, CABA',
    features: FeatureFlags(fastPos: true, logistics: false),
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

class FakeLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get terminalId => 'caja-1';

  @override
  String get printerFormat => 'thermal_80';

  @override
  String get lockedPriceTier => 'none';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Operador Fiscal'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCustomerProvider extends ChangeNotifier implements CustomerProvider {
  final List<Customer> _customers = [
    Customer(
      id: 10,
      name: 'Empresa SA',
      documentNumber: '30500010912',
      documentType: 80,
      taxCondition: 'responsable_inscripto',
      fiscalAddress: 'Av. Corrientes 500, CABA',
      creditLimit: 100000.0,
      balance: 0.0,
      isActive: true,
    ),
    Customer(
      id: 20,
      name: 'Juan Pérez',
      documentNumber: '35123456',
      documentType: 96,
      taxCondition: 'consumidor_final',
      creditLimit: 0.0,
      balance: 0.0,
      isActive: true,
    ),
  ];

  @override
  List<Customer> get customers => _customers;

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchCustomers({String? search}) async {}

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
  Future<void> fetchCriticalAlerts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─── TEST HARNESS ────────────────────────────────────────────────────────────

Widget buildFiscalTestApp({
  required FakeFiscalPosProvider posProvider,
  FakeCustomerProvider? customerProvider,
  double total = 1500.0,
}) {
  final apiClient = ApiClient(
    MockClient((request) async => http.Response('{"success": true}', 200)),
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PosProvider>.value(value: posProvider),
      ChangeNotifierProvider<SettingsProvider>(create: (_) => FakeSettingsProvider()),
      ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => FakeLocalTerminalProvider()),
      ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuthProvider()),
      ChangeNotifierProvider<CustomerProvider>(create: (_) => customerProvider ?? FakeCustomerProvider()),
      ChangeNotifierProvider<CashRegisterProvider>(create: (_) => FakeCashRegisterProvider()),
      ChangeNotifierProvider<CatalogProvider>(create: (_) => FakeCatalogProvider()),
      Provider<ApiClient>.value(value: apiClient),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CheckoutDialog(total: total),
      ),
    ),
  );
}

// ─── TESTS ───────────────────────────────────────────────────────────────────

void main() {
  group('AfipModulo11 Unit Tests', () {
    test('Validates official Modulo 11 CUIT with multiplier algorithm', () {
      // CUITs oficiales reales válidos
      expect(AfipModulo11.isValid('30-50001091-2'), isTrue);
      expect(AfipModulo11.validateCuit('30500010912'), isTrue);
      expect(AfipModulo11.isValid('20-12345678-6'), isTrue);
      expect(AfipModulo11.validateCuit('20123456786'), isTrue);
      expect(AfipModulo11.isValid('27-23456789-1'), isTrue);
      expect(AfipModulo11.validateCuit('27234567891'), isTrue);
      expect(AfipModulo11.isValid('33-69345023-9'), isTrue);
      expect(AfipModulo11.validateCuit('33693450239'), isTrue);
    });

    test('Rejects invalid CUIT (wrong check digit, wrong length, wrong prefix)', () {
      expect(AfipModulo11.isValid('20-12345678-9'), isFalse);
      expect(AfipModulo11.validateCuit('20123456789'), isFalse);
      expect(AfipModulo11.isValid('20-12345678-4'), isFalse); // Dígito verificador incorrecto (espera 6)
      expect(AfipModulo11.isValid('123456'), isFalse);
      expect(AfipModulo11.isValid('99-12345678-0'), isFalse); // Prefijo 99 inválido para CUIT
      expect(AfipModulo11.isValid(null), isFalse);
      expect(AfipModulo11.isValid(''), isFalse);
    });

    test('Validates Argentine DNI format correctly', () {
      expect(AfipModulo11.validateDni('35123456'), isTrue);
      expect(AfipModulo11.validateDni('8123456'), isTrue);
      expect(AfipModulo11.validateDni('12345'), isFalse); // < 7 dígitos
      expect(AfipModulo11.validateDni('999999999'), isFalse); // > 8 dígitos
      expect(AfipModulo11.validateDni(null), isFalse);
    });
  });

  group('CheckoutDialog Fiscal Invoicing Widget Tests', () {
    testWidgets('Initializes in Ticket Común mode without fiscal controls displayed', (tester) async {
      final posProvider = FakeFiscalPosProvider();
      await tester.pumpWidget(buildFiscalTestApp(posProvider: posProvider));
      await tester.pumpAndSettle();

      // Verifica el toggle de comprobante
      expect(find.byKey(const Key('fiscal_mode_segmented_button')), findsOneWidget);
      expect(find.text('Ticket Común'), findsOneWidget);
      expect(find.text('Factura Fiscal ARCA'), findsOneWidget);

      // Los controles de Factura Fiscal están ocultos inicialmente
      expect(find.byKey(const Key('voucher_type_segmented_button')), findsNothing);
      expect(find.byKey(const Key('fiscal_doc_number_field')), findsNothing);

      // Botón confirmar pago está habilitado en modo común
      final submitBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      expect(submitBtn.onPressed, isNotNull);
    });

    testWidgets('Toggling to Factura Fiscal ARCA reveals voucher selector (A, B, C)', (tester) async {
      final posProvider = FakeFiscalPosProvider();
      await tester.pumpWidget(buildFiscalTestApp(posProvider: posProvider));
      await tester.pumpAndSettle();

      // Tap en Factura Fiscal ARCA
      await tester.tap(find.text('Factura Fiscal ARCA'));
      await tester.pumpAndSettle();

      // Ahora el selector de comprobante y los campos fiscales son visibles
      expect(find.byKey(const Key('voucher_type_segmented_button')), findsOneWidget);
      expect(find.text('Factura A'), findsOneWidget);
      expect(find.text('Factura B'), findsOneWidget);
      expect(find.text('Factura C'), findsOneWidget);
      expect(find.byKey(const Key('fiscal_doc_number_field')), findsOneWidget);
      expect(find.byKey(const Key('fiscal_receiver_name_field')), findsOneWidget);
    });

    testWidgets('Selecting Factura A mandates valid CUIT and Responsable Inscripto', (tester) async {
      final posProvider = FakeFiscalPosProvider();
      await tester.pumpWidget(buildFiscalTestApp(posProvider: posProvider));
      await tester.pumpAndSettle();

      // Activar Factura Fiscal
      await tester.tap(find.text('Factura Fiscal ARCA'));
      await tester.pumpAndSettle();

      // Seleccionar Factura A
      await tester.tap(find.text('Factura A'));
      await tester.pumpAndSettle();

      // Botón debe estar deshabilitado porque CUIT está vacío y nombre está vacío
      var submitBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      expect(submitBtn.onPressed, isNull);

      // Ingresar CUIT inválido
      await tester.enterText(find.byKey(const Key('fiscal_doc_number_field')), '20-12345678-9');
      await tester.enterText(find.byKey(const Key('fiscal_receiver_name_field')), 'Empresa Falsa SA');
      await tester.pumpAndSettle();

      // Feedback en tiempo real muestra error de Módulo 11
      expect(find.byKey(const Key('cuit_invalid_feedback')), findsOneWidget);
      expect(find.text('CUIT/CUIL inválido (falla Módulo 11)'), findsOneWidget);

      submitBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      expect(submitBtn.onPressed, isNull);

      // Ingresar CUIT válido
      await tester.enterText(find.byKey(const Key('fiscal_doc_number_field')), '30-50001091-2');
      await tester.pumpAndSettle();

      // Feedback muestra éxito de Módulo 11
      expect(find.byKey(const Key('cuit_valid_feedback')), findsOneWidget);
      expect(find.text('CUIT/CUIL válido (Módulo 11 OK)'), findsOneWidget);

      // Ahora el botón debe estar habilitado
      submitBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      expect(submitBtn.onPressed, isNotNull);
    });

    testWidgets('Submitting checkout in fiscal mode constructs and passes fiscalPayload', (tester) async {
      final posProvider = FakeFiscalPosProvider();
      await tester.pumpWidget(buildFiscalTestApp(posProvider: posProvider));
      await tester.pumpAndSettle();

      // Activar Factura Fiscal
      await tester.tap(find.text('Factura Fiscal ARCA'));
      await tester.pumpAndSettle();

      // Seleccionar Factura A y completar datos
      await tester.tap(find.text('Factura A'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('fiscal_doc_number_field')), '30-50001091-2');
      await tester.enterText(find.byKey(const Key('fiscal_receiver_name_field')), 'Banco Nación SA');
      await tester.enterText(find.byKey(const Key('fiscal_receiver_address_field')), 'Bartolomé Mitre 326, CABA');
      await tester.pumpAndSettle();

      // Confirmar pago
      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      await tester.pumpAndSettle();

      // Verificar payload capturado en el provider
      expect(posProvider.capturedFiscalInvoiceData, isNotNull);
      final payload = posProvider.capturedFiscalInvoiceData!;
      expect(payload['voucher_type'], equals(1));
      expect(payload['doc_type'], equals(80));
      expect(payload['doc_number'], equals('30500010912'));
      expect(payload['receiver_name'], equals('Banco Nación SA'));
      expect(payload['receiver_tax_condition'], equals('responsable_inscripto'));
      expect(payload['receiver_address'], equals('Bartolomé Mitre 326, CABA'));
    });

    testWidgets('Factura B allows Consumidor Final and passes voucher_type 6', (tester) async {
      final posProvider = FakeFiscalPosProvider();
      await tester.pumpWidget(buildFiscalTestApp(posProvider: posProvider));
      await tester.pumpAndSettle();

      // Activar Factura Fiscal
      await tester.tap(find.text('Factura Fiscal ARCA'));
      await tester.pumpAndSettle();

      // Factura B viene seleccionada por defecto (o seleccionamos B)
      await tester.tap(find.text('Factura B'));
      await tester.pumpAndSettle();

      // Ingresar DNI y nombre
      await tester.enterText(find.byKey(const Key('fiscal_doc_number_field')), '35123456');
      await tester.enterText(find.byKey(const Key('fiscal_receiver_name_field')), 'Consumidor Final Regular');
      await tester.pumpAndSettle();

      // Confirmar pago
      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      await tester.pumpAndSettle();

      expect(posProvider.capturedFiscalInvoiceData, isNotNull);
      final payload = posProvider.capturedFiscalInvoiceData!;
      expect(payload['voucher_type'], equals(6));
      expect(payload['doc_number'], equals('35123456'));
      expect(payload['receiver_name'], equals('Consumidor Final Regular'));
    });

    testWidgets('Zero RenderFlex overflow at compact resolution Size(320, 480)', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = FakeFiscalPosProvider();
      await tester.pumpWidget(buildFiscalTestApp(posProvider: posProvider));
      await tester.pumpAndSettle();

      // Activar Factura Fiscal en pantalla pequeña
      await tester.tap(find.text('Factura Fiscal ARCA'));
      await tester.pumpAndSettle();

      // Cambiar entre vouchers
      await tester.tap(find.text('Factura A'));
      await tester.pumpAndSettle();

      // Ingresar texto
      await tester.enterText(find.byKey(const Key('fiscal_doc_number_field')), '30-50001091-2');
      await tester.pumpAndSettle();

      // Verificar que ningún error de overflow fue capturado
      expect(tester.takeException(), isNull);
    });

    testWidgets('Zero RenderFlex overflow at desktop resolution Size(1280, 900)', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = FakeFiscalPosProvider();
      await tester.pumpWidget(buildFiscalTestApp(posProvider: posProvider));
      await tester.pumpAndSettle();

      // Activar Factura Fiscal
      await tester.tap(find.text('Factura Fiscal ARCA'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Factura C'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
