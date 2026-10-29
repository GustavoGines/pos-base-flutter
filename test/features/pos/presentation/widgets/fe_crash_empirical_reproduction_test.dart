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

class MockPosProvider extends ChangeNotifier implements PosProvider {
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
      name: 'Cuenta Corriente',
      code: 'cuenta_corriente',
      surchargeType: 'none',
      surchargeValue: 0.0,
      isCash: false,
      isActive: true,
      sortOrder: 6,
    ),
    PaymentMethod(
      id: 3,
      name: 'Cheque Diferido',
      code: 'cheque',
      surchargeType: 'none',
      surchargeValue: 0.0,
      isCash: false,
      isActive: true,
      sortOrder: 7,
    ),
    PaymentMethod(
      id: 4,
      name: 'Tarjeta Débito',
      code: 'debito',
      surchargeType: 'none',
      surchargeValue: 0.0,
      isCash: false,
      isActive: true,
      sortOrder: 4,
    ),
  ];

  @override
  List<PaymentMethod> get paymentMethods => _methods;

  @override
  List<CartItem> get cart => [];

  @override
  double get cartTotal => 1500.0;

  @override
  double get cartSubtotal => 1500.0;

  @override
  double get shippingCost => 0.0;

  @override
  double get lastUsedShippingCost => 0.0;

  @override
  bool get currentRequiresDispatch => false;

  @override
  String get currentFulfillmentStatus => 'pending';

  Customer? _selectedCustomer;
  @override
  Customer? get selectedCustomer => _selectedCustomer;

  @override
  void selectCustomer(Customer? customer, {bool? isPerceptionAgent}) {
    _selectedCustomer = customer;
  }

  @override
  Customer? get lastSelectedCustomer => _selectedCustomer;

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

  @override
  double calculateIibbPerceptionAmount({BusinessSettings? settings, Customer? customer, double extraAmount = 0.0, double? overrideTotal}) => 0.0;

  @override
  bool checkAppliesIibbPerception({BusinessSettings? settings, Customer? customer}) => false;

  @override
  double get iibbPerceptionAmount => 0.0;

  @override
  double get iibbPerceptionRate => 0.0;

  @override
  Map<String, dynamic>? get pendingFiscalInvoiceData => null;

  @override
  void setPendingFiscalInvoiceData(Map<String, dynamic>? data) {}

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
    dynamic checkDetails, double? iibbPerceptionAmount, double? iibbPerceptionRate,
    String? deliveryAddress,
    String? clientTransactionId,
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final bool enableLogistics;
  final bool enableCurrentAccounts;
  final bool enableChecks;

  MockSettingsProvider({
    this.enableLogistics = true,
    this.enableCurrentAccounts = false,
    this.enableChecks = false,
  });

  @override
  int get assignedRegisterId => 1;

  @override
  BusinessSettings? get settings => BusinessSettings(
        companyName: 'Test Comercio',
        taxId: '30-50001091-2',
        address: 'Av. Test 123',
        afipEnabled: false,
        features: FeatureFlags(
          fastPos: true,
          logistics: enableLogistics,
          currentAccounts: enableCurrentAccounts,
          checks: enableChecks,
        ),
      );

  @override
  String get currentPlan => 'basic';

  @override
  bool hasFeature(String featureName) {
    if (featureName == 'logistics') return enableLogistics;
    if (featureName == 'current_accounts') return enableCurrentAccounts;
    if (featureName == 'checks') return enableChecks;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  bool get autoOpenCashDrawer => false;
  @override
  String get scaleComPort => '';
  @override
  String get terminalId => 'caja-1';
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get lockedPriceTier => 'none';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Tester'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCustomerProvider extends ChangeNotifier implements CustomerProvider {
  @override
  List<Customer> get customers => [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchCustomers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
  @override
  CashRegisterShift? get currentShift => CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openedAt: DateTime.now(),
        openingBalance: 1000.0,
        status: 'open',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCatalogProvider extends ChangeNotifier implements CatalogProvider {
  @override
  Future<void> fetchCriticalAlerts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildHarness({
  required MockPosProvider posProvider,
  required MockSettingsProvider settingsProvider,
  double total = 1500.0,
}) {
  final apiClient = ApiClient(
    MockClient((request) async => http.Response('{"success": true}', 200)),
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PosProvider>.value(value: posProvider),
      ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
      ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => MockLocalTerminalProvider()),
      ChangeNotifierProvider<AuthProvider>(create: (_) => MockAuthProvider()),
      ChangeNotifierProvider<CustomerProvider>(create: (_) => MockCustomerProvider()),
      ChangeNotifierProvider<CashRegisterProvider>(create: (_) => MockCashRegisterProvider()),
      ChangeNotifierProvider<CatalogProvider>(create: (_) => MockCatalogProvider()),
      Provider<ApiClient>.value(value: apiClient),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CheckoutDialog(total: total),
      ),
    ),
  );
}

void main() {
  group('Empirical Verification of FE-CRASH-01 and FE-CRASH-02', () {

    testWidgets('FE-CRASH-02: Logistics shipping cost row overflow at 768x1024 or 800x600', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = MockPosProvider();
      final settingsProvider = MockSettingsProvider(enableLogistics: true);

      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };

      try {
        await tester.pumpWidget(buildHarness(
          posProvider: posProvider,
          settingsProvider: settingsProvider,
        ));
        await tester.pumpAndSettle();

        // Verificar switch de logística
        final logisticsToggle = find.text('Enviar a Logística (Armar Pedido)');
        expect(logisticsToggle, findsOneWidget);

        // Click en switch para activar despacho
        await tester.tap(logisticsToggle);
        await tester.pumpAndSettle();

        // Verificar si la fila de 'Flete / Envío:' existe
        expect(find.text('Flete / Envío:'), findsOneWidget);

        // Inspeccionar errores capturados de overflow
        final overflowErrors = errors.where((e) =>
          e.toString().contains('RenderFlex overflowed') ||
          e.toString().contains('A RenderFlex overflowed')
        ).toList();

        debugPrint('FE-CRASH-02 Captured overflow errors count: ${overflowErrors.length}');
        for (var err in overflowErrors) {
          debugPrint('FE-CRASH-02 Error: ${err.exceptionAsString()}');
        }
        expect(overflowErrors, isEmpty, reason: 'No deben existir RenderFlex overflows en logística');
      } finally {
        FlutterError.onError = originalOnError;
      }
    });

    testWidgets('FE-CRASH-01: Payment method dropdown overflow at narrow resolutions (768x1024 and 412x915)', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = MockPosProvider();
      final settingsProvider = MockSettingsProvider(
        enableLogistics: false,
        enableCurrentAccounts: false,
        enableChecks: false,
      );

      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };

      try {
        await tester.pumpWidget(buildHarness(
          posProvider: posProvider,
          settingsProvider: settingsProvider,
        ));
        await tester.pumpAndSettle();

        // Agregar una segunda línea de pago para estrechar aún más el espacio disponible
        final addLineButton = find.text('AGREGAR MEDIO DE PAGO (F4)');
        if (addLineButton.evaluate().isNotEmpty) {
          await tester.tap(addLineButton);
          await tester.pumpAndSettle();
        }

        // Abrir el dropdown de método de pago
        final dropdownFinder = find.byType(DropdownButtonFormField<PaymentMethod>);
        if (dropdownFinder.evaluate().isNotEmpty) {
          await tester.tap(dropdownFinder.first);
          await tester.pumpAndSettle();
        }

        final overflowErrors = errors.where((e) =>
          e.toString().contains('RenderFlex overflowed') ||
          e.toString().contains('A RenderFlex overflowed')
        ).toList();

        debugPrint('FE-CRASH-01 (768x1024) Captured overflow errors count: ${overflowErrors.length}');
        for (var err in overflowErrors) {
          debugPrint('FE-CRASH-01 Error: ${err.exceptionAsString()}');
        }
        expect(overflowErrors, isEmpty, reason: 'No deben existir RenderFlex overflows en métodos de pago (768x1024)');
      } finally {
        FlutterError.onError = originalOnError;
      }
    });

    testWidgets('FE-CRASH-01: Payment method dropdown overflow at mobile resolution 412x915', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = MockPosProvider();
      final settingsProvider = MockSettingsProvider(
        enableLogistics: false,
        enableCurrentAccounts: false,
        enableChecks: false,
      );

      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };

      try {
        await tester.pumpWidget(buildHarness(
          posProvider: posProvider,
          settingsProvider: settingsProvider,
        ));
        await tester.pumpAndSettle();

        final overflowErrors = errors.where((e) =>
          e.toString().contains('RenderFlex overflowed') ||
          e.toString().contains('A RenderFlex overflowed')
        ).toList();

        debugPrint('FE-CRASH-01 (412x915) Captured overflow errors count: ${overflowErrors.length}');
        for (var err in overflowErrors) {
          debugPrint('FE-CRASH-01 (412x915) Error: ${err.exceptionAsString()}');
        }
        expect(overflowErrors, isEmpty, reason: 'No deben existir RenderFlex overflows en métodos de pago (412x915)');
      } finally {
        FlutterError.onError = originalOnError;
      }
    });

    testWidgets('FE-CRASH-02: Logistics shipping cost row overflow at 800x600', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final posProvider = MockPosProvider();
      final settingsProvider = MockSettingsProvider(enableLogistics: true);

      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };

      try {
        await tester.pumpWidget(buildHarness(
          posProvider: posProvider,
          settingsProvider: settingsProvider,
        ));
        await tester.pumpAndSettle();

        final logisticsToggle = find.text('Enviar a Logística (Armar Pedido)');
        expect(logisticsToggle, findsOneWidget);

        await tester.ensureVisible(logisticsToggle);
        await tester.tap(logisticsToggle);
        await tester.pumpAndSettle();

        final overflowErrors = errors.where((e) =>
          e.toString().contains('RenderFlex overflowed') ||
          e.toString().contains('A RenderFlex overflowed')
        ).toList();

        debugPrint('FE-CRASH-02 (800x600) Captured overflow errors count: ${overflowErrors.length}');
        for (var err in overflowErrors) {
          debugPrint('FE-CRASH-02 (800x600) Error: ${err.exceptionAsString()}');
        }
        expect(overflowErrors, isEmpty, reason: 'No deben existir RenderFlex overflows en logística (800x600)');
      } finally {
        FlutterError.onError = originalOnError;
      }
    });
  });
}

