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

class FakeResponsivePosProvider extends ChangeNotifier implements PosProvider {
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
      surchargeType: 'percentage',
      surchargeValue: 5.0,
      isCash: false,
      isActive: true,
      sortOrder: 2,
    ),
    PaymentMethod(
      id: 3,
      name: 'Cuenta Corriente',
      code: 'cuenta_corriente',
      surchargeType: 'none',
      surchargeValue: 0.0,
      isCash: false,
      isActive: true,
      sortOrder: 3,
    ),
    PaymentMethod(
      id: 4,
      name: 'Cheque',
      code: 'cheque',
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
  double get cartTotal => 2500.0;

  @override
  double get shippingCost => 0.0;

  @override
  double get lastUsedShippingCost => 0.0;

  @override
  bool get currentRequiresDispatch => true;

  @override
  String get currentFulfillmentStatus => 'pending';

  @override
  bool get isLoading => false;

  Map<String, dynamic>? _pendingData;

  @override
  Map<String, dynamic>? get pendingFiscalInvoiceData => _pendingData;

  @override
  void setPendingFiscalInvoiceData(Map<String, dynamic>? data) {
    _pendingData = data;
  }

  @override
  double calculateIibbPerceptionAmount({BusinessSettings? settings, Customer? customer, double extraAmount = 0.0, double? overrideTotal}) => 0.0;

  @override
  bool checkAppliesIibbPerception({BusinessSettings? settings, Customer? customer}) => false;

  @override
  double get iibbPerceptionAmount => 0.0;

  @override
  double get iibbPerceptionRate => 0.0;

  @override
  Customer? get selectedCustomer => null;

  @override
  Customer? get lastSelectedCustomer => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeResponsiveSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings = const BusinessSettings(
    features: FeatureFlags(
      currentAccounts: false, // Locked -> shows Pro badge
      checks: false,          // Locked -> shows Pro badge
      logistics: true,        // Shows dispatch option
    ),
  );

  @override
  BusinessSettings? get settings => _settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminal extends ChangeNotifier implements LocalTerminalProvider {
  @override
  bool get autoOpenCashDrawer => false;
  @override
  String get terminalId => 'caja-1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Cajero Responsive'};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCustomer extends ChangeNotifier implements CustomerProvider {
  @override
  List<Customer> get customers => [];
  @override
  bool get isLoading => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCashRegister extends ChangeNotifier implements CashRegisterProvider {
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

class FakeCatalog extends ChangeNotifier implements CatalogProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildTestApp({required Size size}) {
  final apiClient = ApiClient(MockClient((_) async => http.Response('{}', 200)));

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PosProvider>(create: (_) => FakeResponsivePosProvider()),
      ChangeNotifierProvider<SettingsProvider>(create: (_) => FakeResponsiveSettingsProvider()),
      ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => FakeLocalTerminal()),
      ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuth()),
      ChangeNotifierProvider<CustomerProvider>(create: (_) => FakeCustomer()),
      ChangeNotifierProvider<CashRegisterProvider>(create: (_) => FakeCashRegister()),
      ChangeNotifierProvider<CatalogProvider>(create: (_) => FakeCatalog()),
      Provider<ApiClient>.value(value: apiClient),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const Scaffold(
          body: CheckoutDialog(total: 2500.0),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('FE-CRASH-01: Checkout dialog renders without overflow on narrow tablet viewport (768x1024)', (tester) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestApp(size: const Size(768, 1024)));
    await tester.pumpAndSettle();

    expect(find.byType(CheckoutDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FE-CRASH-02: Checkout dialog with logistics dispatch renders without overflow on 800x600', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestApp(size: const Size(800, 600)));
    await tester.pumpAndSettle();

    expect(find.byType(CheckoutDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
