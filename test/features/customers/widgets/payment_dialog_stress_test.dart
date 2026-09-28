import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/presentation/widgets/payment_dialog.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';

class FakeCustomerProvider extends ChangeNotifier implements CustomerProvider {
  final List<Map<String, dynamic>> _pendingSales = [];
  @override
  List<Map<String, dynamic>> get pendingSales => _pendingSales;

  bool registerPaymentResult = true;
  bool shouldThrow = false;
  int registerPaymentCallCount = 0;

  @override
  Future<void> fetchPendingSales(int customerId) async {}

  @override
  Future<bool> registerPayment({
    required int customerId,
    double? amount,
    String? paymentMethod,
    List<Map<String, dynamic>>? payments,
    String description = '',
    List<int> saleIds = const [],
    dynamic checkDetails,
    int? cashShiftId,
    bool isRefund = false,
  }) async {
    registerPaymentCallCount++;
    if (shouldThrow) {
      throw Exception('Simulated network timeout');
    }
    return registerPaymentResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings? get settings => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
  @override
  CashRegisterShift? get currentShift => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeCustomerProvider fakeCustomerProvider;
  late FakeSettingsProvider fakeSettingsProvider;
  late FakeCashRegisterProvider fakeCashRegisterProvider;
  late Customer testCustomer;

  setUp(() {
    fakeCustomerProvider = FakeCustomerProvider();
    fakeSettingsProvider = FakeSettingsProvider();
    fakeCashRegisterProvider = FakeCashRegisterProvider();
    testCustomer = Customer(
      id: 42,
      name: 'Empresa Test S.A.',
      documentNumber: '30-12345678-9',
      creditLimit: 50000.0,
      balance: 15000.0,
      isActive: true,
    );
  });

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CustomerProvider>.value(value: fakeCustomerProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: fakeSettingsProvider),
        ChangeNotifierProvider<CashRegisterProvider>.value(value: fakeCashRegisterProvider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PaymentDialog(
            customer: testCustomer,
            isRefund: false,
          ),
        ),
      ),
    );
  }

  group('PaymentDialog Concurrency, Disposal & Lock Stress Tests', () {
    testWidgets('Removing a line does not cause "used after being disposed" errors', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Initially 1 line
      expect(find.text('Agregar Método'), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);

      // Add a second payment line
      await tester.tap(find.text('Agregar Método'));
      await tester.pumpAndSettle();

      // Now 2 lines exist, remove buttons should be visible (one per line)
      expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(2));

      // Remove the first line
      final firstRemoveBtn = find.byIcon(Icons.remove_circle_outline).first;
      await tester.tap(firstRemoveBtn);
      await tester.pumpAndSettle();

      // Verify that after removal, exactly 1 line remains and no remove buttons remain
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);

      // Verify typing into the remaining line's controller works and triggers rebuild cleanly without disposal errors
      final amountField = find.byType(TextFormField).first;
      await tester.enterText(amountField, '9999.00');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('registerPayment failure (returns false) releases submission lock', (tester) async {
      fakeCustomerProvider.registerPaymentResult = false; // Simulate API failure

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Click "Confirmar Pago"
      final confirmBtn = find.text('Confirmar Pago');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pump(); // Start submission

      // After async call completes, pump and settle
      await tester.pumpAndSettle();

      // Confirm registerPayment was called
      expect(fakeCustomerProvider.registerPaymentCallCount, equals(1));

      // Submission lock MUST be released: "Confirmar Pago" button must be visible and re-enabled
      expect(find.text('Confirmar Pago'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Ensure no exceptions occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets('registerPayment exception (throws error) releases submission lock and shows SnackBar', (tester) async {
      fakeCustomerProvider.shouldThrow = true; // Simulate network exception

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Click "Confirmar Pago"
      final confirmBtn = find.text('Confirmar Pago');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pump(); // Start submission

      // Wait for catch block and finally block to execute
      await tester.pumpAndSettle();

      // Confirm registerPayment was called
      expect(fakeCustomerProvider.registerPaymentCallCount, equals(1));

      // SnackBar with error message must be shown
      expect(find.textContaining('Simulated network timeout'), findsOneWidget);

      // Submission lock MUST be released: "Confirmar Pago" button must be re-enabled
      expect(find.text('Confirmar Pago'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Ensure no unhandled framework exceptions
      expect(tester.takeException(), isNull);
    });
  });
}
