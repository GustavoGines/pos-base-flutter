import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/cash_movements/presentation/widgets/movement_form_dialog.dart';
import 'package:frontend_desktop/features/cash_movements/providers/cash_movement_provider.dart';
import 'package:frontend_desktop/features/cash_movements/providers/expense_category_provider.dart';
import 'package:frontend_desktop/features/cash_movements/models/expense_category_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/checks/presentation/providers/check_provider.dart';
import 'package:frontend_desktop/features/checks/domain/entities/third_party_check.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class FakeCheckProvider extends ChangeNotifier implements CheckProvider {
  List<ThirdPartyCheck> _checks = [];
  @override
  List<ThirdPartyCheck> get checks => _checks;

  void setChecks(List<ThirdPartyCheck> list) {
    _checks = list;
    notifyListeners();
  }

  @override
  Future<void> loadChecks() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  List<Supplier> _suppliers = [];
  @override
  List<Supplier> get suppliers => _suppliers;

  void setSuppliers(List<Supplier> list) {
    _suppliers = list;
    notifyListeners();
  }

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeExpenseCategoryProvider extends ChangeNotifier implements ExpenseCategoryProvider {
  List<ExpenseCategory> _categories = [];
  @override
  List<ExpenseCategory> get categories => _categories;
  @override
  bool get isLoading => false;

  void setCategories(List<ExpenseCategory> list) {
    _categories = list;
    notifyListeners();
  }

  @override
  Future<void> fetchCategories() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCashMovementProvider extends ChangeNotifier implements CashMovementProvider {
  Map<String, dynamic>? lastSubmittedPayload;
  int createMovementCallCount = 0;
  List<int> resultIds = [1];

  @override
  Future<List<int>> createMovement(Map<String, dynamic> data, {String? adminPin}) async {
    createMovementCallCount++;
    lastSubmittedPayload = data;
    return resultIds;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
  CashRegisterShift? _currentShift;
  @override
  CashRegisterShift? get currentShift => _currentShift;

  void setShift(CashRegisterShift? shift) {
    _currentShift = shift;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings? _settings = const BusinessSettings();
  @override
  BusinessSettings? get settings => _settings;

  void setSettings(BusinessSettings? settings) {
    _settings = settings;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  bool _isAdmin = true;
  @override
  bool get isAdmin => _isAdmin;

  void setIsAdmin(bool value) {
    _isAdmin = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerConnection => 'none';

  @override
  String get printerFormat => 'thermal_80';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Test Helpers ───────────────────────────────────────────────────────────

void setDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('RenderFlex overflowed')) {
      return;
    }
    originalOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalOnError);
}

Widget buildTestDialog({
  required FakeCheckProvider fakeCheckProvider,
  required FakeSupplierProvider fakeSupplierProvider,
  required FakeExpenseCategoryProvider fakeExpenseCategoryProvider,
  required FakeCashMovementProvider fakeCashMovementProvider,
  required FakeCashRegisterProvider fakeCashRegisterProvider,
  required FakeSettingsProvider fakeSettingsProvider,
  required FakeAuthProvider fakeAuthProvider,
  required FakeLocalTerminalProvider fakeLocalTerminalProvider,
  int? initialSupplierId,
  String? initialType,
  String? initialCategory,
  double? initialAmount,
  String? helperText,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<CheckProvider>.value(value: fakeCheckProvider),
      ChangeNotifierProvider<SupplierProvider>.value(value: fakeSupplierProvider),
      ChangeNotifierProvider<ExpenseCategoryProvider>.value(value: fakeExpenseCategoryProvider),
      ChangeNotifierProvider<CashMovementProvider>.value(value: fakeCashMovementProvider),
      ChangeNotifierProvider<CashRegisterProvider>.value(value: fakeCashRegisterProvider),
      ChangeNotifierProvider<SettingsProvider>.value(value: fakeSettingsProvider),
      ChangeNotifierProvider<AuthProvider>.value(value: fakeAuthProvider),
      ChangeNotifierProvider<LocalTerminalProvider>.value(value: fakeLocalTerminalProvider),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: MovementFormDialog(
          initialSupplierId: initialSupplierId,
          initialType: initialType,
          initialCategory: initialCategory,
          initialAmount: initialAmount,
          helperText: helperText,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CHALLENGE 1: Mixed Payment Edge Cases & Debt Settlement Arithmetic', () {
    test('Cash + Check exactly equals debt produces 0.0 debt balance', () {
      const supplierDebt = 85000.0;
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
        PaymentItem(method: 'cash', amount: 35000.0),
      ];

      final totalPaid = payments.fold(0.0, (sum, p) => sum + p.amount);
      final remainingDebt = supplierDebt - totalPaid;

      expect(totalPaid, 85000.0);
      expect(remainingDebt, 0.0);
    });

    test('Cash + Check underpays debt leaves positive remaining debt', () {
      const supplierDebt = 85000.0;
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
        PaymentItem(method: 'cash', amount: 20000.0),
      ];

      final totalPaid = payments.fold(0.0, (sum, p) => sum + p.amount);
      final remainingDebt = supplierDebt - totalPaid;

      expect(totalPaid, 70000.0);
      expect(remainingDebt, 15000.0);
      expect(remainingDebt > 0, isTrue);
    });

    test('Overpayment challenge: Check exceeds debt drives balance negative with no cash drawer return', () {
      const supplierDebt = 30000.0;
      const checkAmount = 50000.0; // Fixed nominal carton amount

      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: checkAmount, checkId: 101),
      ];

      final totalPaid = payments.fold(0.0, (sum, p) => sum + p.amount);
      final supplierNewBalance = supplierDebt - totalPaid;

      // Demonstrates flaw V-03:
      // The supplier balance drops to -$20,000 (store has phantom credit),
      // but physical change given back by vendor is not captured in shift cash drawer!
      expect(supplierNewBalance, -20000.0);
      expect(supplierNewBalance < 0, isTrue);
    });

    test('Multi-tender precision: Cash + Check + Transfer handles arbitrary fractional splits', () {
      const supplierDebt = 123456.78;
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.00, checkId: 101),
        PaymentItem(method: 'transfer', amount: 43456.70),
        PaymentItem(method: 'cash', amount: 30000.08),
      ];

      final totalPaid = payments.fold(0.0, (sum, p) => sum + p.amount);
      final roundedTotal = double.parse(totalPaid.toStringAsFixed(2));

      expect(roundedTotal, supplierDebt);
    });
  });

  group('CHALLENGE 2: Floating-Point Precision & Rounding Stress Test', () {
    test('Demonstrates IEEE 754 precision drift in naive floating-point sum (0.1 + 0.2 != 0.3)', () {
      const p1 = 0.1;
      const p2 = 0.2;
      final naiveSum = p1 + p2;

      // Direct comparison fails in naive arithmetic
      expect(naiveSum == 0.3, isFalse);
      expect(naiveSum, 0.30000000000000004);

      // Quantized string rounding fixes it
      final safeSum = double.parse(naiveSum.toStringAsFixed(2));
      expect(safeSum, 0.3);
    });

    test('Stress test: "Pagar Restante" remaining balance calculation under precision drift', () {
      // Suppose supplier debt is 100.30 and cash payment of 100.10 was added
      const debt = 100.30;
      final payments = [PaymentItem(method: 'cash', amount: 100.10)];
      final listSum = payments.fold(0.0, (sum, item) => sum + item.amount);
      final remaining = debt - listSum;

      // In IEEE 754: 100.30 - 100.10 = 0.20000000000000284
      expect(remaining, isNot(equals(0.20)));
      expect(remaining, 0.20000000000000284);

      // Verify that remaining % 1 is affected by precision
      // For instance, remaining = 1.0000000000000002
      const driftedInt = 1.0000000000000002;
      expect(driftedInt % 1 == 0, isFalse);

      // Remediation must quantize remaining before modulo or string format:
      final sanitizedRemaining = double.parse(remaining.toStringAsFixed(2));
      expect(sanitizedRemaining, 0.20);
    });

    test('Defensive parser: _sanitizeAndParse handles 2-decimal truncation correctly', () {
      double? sanitizeAndParse(String text) {
        final clean = text.trim().replaceAll(',', '.');
        final val = double.tryParse(clean);
        if (val == null || val <= 0 || val.isNaN || val.isInfinite) return null;
        return double.parse(val.toStringAsFixed(2));
      }

      expect(sanitizeAndParse('0.10'), 0.10);
      expect(sanitizeAndParse('0.20'), 0.20);
      expect(sanitizeAndParse('0.300000000004'), 0.30);
      expect(sanitizeAndParse('123.456'), 123.46); // Rounds to 2 decimal places
      expect(sanitizeAndParse('0'), isNull);
      expect(sanitizeAndParse('-0.01'), isNull);
    });
  });

  group('CHALLENGE 3: State Transitions — Switching Suppliers & Unsaved Controller Leak', () {
    test('Adversarial finding in proposed patch: If _payments is empty, changing supplier leaves _paymentAmountController and _currentCheckId dirty', () {
      // In REMEDIATION_REPORT.md Patch 1 (lines 840-849):
      // onChanged: (val) => setState(() {
      //   if (val != _selectedSupplierId) {
      //     _selectedSupplierId = val;
      //     if (_payments.isNotEmpty) {
      //       _payments.clear();
      //       _paymentAmountController.clear();
      //       _currentCheckId = null;
      //     }
      //   }
      // })

      int? selectedSupplierId = 1;
      final payments = <PaymentItem>[]; // User has NOT tapped "Agregar" yet
      int? currentCheckId = 101;
      String controllerText = '50000.0';

      // Operator changes dropdown from Supplier 1 to Supplier 2:
      final newSupplierId = 2;
      if (newSupplierId != selectedSupplierId) {
        selectedSupplierId = newSupplierId;
        // BUG IN REMEDIATION_REPORT SPECIFICATION:
        // Because payments.isNotEmpty is FALSE, cleanup is bypassed!
        if (payments.isNotEmpty) {
          payments.clear();
          controllerText = '';
          currentCheckId = null;
        }
      }

      // CRITICAL LEAK CONFIRMED:
      // Even though supplier changed to 2, checkId 101 and controllerText '50000.0'
      // are STILL PRESERVED!
      expect(selectedSupplierId, 2);
      expect(currentCheckId, 101);
      expect(controllerText, '50000.0');

      // Now, when the user clicks "Procesar Movimiento", _submit() auto-add executes:
      // pendingAmount = 50000.0 > 0
      // Check #101 is silently bound to Supplier 2 without operator realizing!
      final autoAddedItem = PaymentItem(
        method: 'check',
        amount: double.parse(controllerText),
        checkId: currentCheckId,
      );
      payments.add(autoAddedItem);

      expect(payments.length, 1);
      expect(payments.first.checkId, 101);
      // Check 101 intended for Supplier 1 was submitted to Supplier 2!
    });

    test('Correct defensive fix: unconditionally clear pending controllers on supplier switch', () {
      int? selectedSupplierId = 1;
      final payments = <PaymentItem>[];
      int? currentCheckId = 101;
      String controllerText = '50000.0';

      void safeSupplierChanged(int? newSupplierId) {
        if (newSupplierId != selectedSupplierId) {
          selectedSupplierId = newSupplierId;
          payments.clear();
          controllerText = '';
          currentCheckId = null; // Unconditional wipe
        }
      }

      safeSupplierChanged(2);

      expect(selectedSupplierId, 2);
      expect(payments.isEmpty, isTrue);
      expect(currentCheckId, isNull);
      expect(controllerText, isEmpty);
    });
  });

  group('CHALLENGE 4: State Transitions — Switching Movement Type Retains Checks in Payments', () {
    test('Adversarial finding in proposed patch: Changing type to "expense" preserves queued check payments', () {
      // In REMEDIATION_REPORT.md Patch 1 (lines 828-836):
      // onChanged: (val) => setState(() {
      //   _type = val!;
      //   if (_type != 'supplier_payment') {
      //     _selectedSupplierId = null;
      //   }
      //   ...
      // })
      // Note: _payments is NEVER cleared when switching type!

      String movementType = 'supplier_payment';
      int? selectedSupplierId = 1;
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
      ];

      // Cashier switches dropdown to 'expense'
      final newType = 'expense';
      movementType = newType;
      if (movementType != 'supplier_payment') {
        selectedSupplierId = null;
      }

      // CRITICAL LEAK CONFIRMED:
      // An expense is queued with a CHECK payment method!
      expect(movementType, 'expense');
      expect(selectedSupplierId, isNull);
      expect(payments.length, 1);
      expect(payments.first.method, 'check');
      expect(payments.first.checkId, 101);

      // When submitted to backend, CashMovementController creates an expense movement
      // and marks the check as 'endorsed', with supplier_id = NULL!
      final payload = {
        'type': movementType,
        'supplier_id': selectedSupplierId,
        'payments': payments.map((p) => {
          'amount': p.amount,
          'payment_method': p.method,
          'check_id': p.checkId,
        }).toList(),
      };

      expect(payload['type'], 'expense');
      expect(payload['supplier_id'], isNull);
      expect(payload['payments'], isNotEmpty);
      expect((payload['payments'] as List).first['payment_method'], 'check');
    });

    test('Correct defensive fix: purge check payments or clear all payments when switching away from supplier_payment', () {
      String movementType = 'supplier_payment';
      int? selectedSupplierId = 1;
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
      ];

      void safeTypeChanged(String newType) {
        if (newType != movementType) {
          movementType = newType;
          if (movementType != 'supplier_payment') {
            selectedSupplierId = null;
            // Purge check payments because checks are strictly prohibited for operational expenses
            payments.removeWhere((p) => p.method == 'check');
          }
        }
      }

      safeTypeChanged('expense');

      expect(movementType, 'expense');
      expect(selectedSupplierId, isNull);
      expect(payments.isEmpty, isTrue); // Cleaned!
    });
  });

  group('CHALLENGE 5: Comma vs Dot & Locale Decimal Separators', () {
    test('Adversarial finding in proposed patch: Thousand separators fail _sanitizeAndParse', () {
      // In REMEDIATION_REPORT.md Patch 1 (lines 688-693):
      // double? _sanitizeAndParse(String text) {
      //   final clean = text.trim().replaceAll(',', '.');
      //   final val = double.tryParse(clean);
      //   ...
      // }

      double? sanitizeAndParse(String text) {
        final clean = text.trim().replaceAll(',', '.');
        final val = double.tryParse(clean);
        if (val == null || val <= 0 || val.isNaN || val.isInfinite) return null;
        return double.parse(val.toStringAsFixed(2));
      }

      // Single comma decimal works:
      expect(sanitizeAndParse('1234,56'), 1234.56);
      expect(sanitizeAndParse('1234.56'), 1234.56);

      // BUT input with thousand dot and comma decimal fails:
      // "1.234,56" -> replaceAll(',', '.') -> "1.234.56" -> double.tryParse returns null!
      expect(sanitizeAndParse('1.234,56'), isNull);

      // And input with US thousand comma fails:
      // "1,234.56" -> "1.234.56" -> double.tryParse returns null!
      expect(sanitizeAndParse('1,234.56'), isNull);
    });

    test('Remediation: Hardened _sanitizeAndParse handles Argentine dots and US commas', () {
      double? sanitizeAndParse(String text) {
        var clean = text.trim();
        if (clean.contains('.') && clean.contains(',')) {
          if (clean.lastIndexOf(',') > clean.lastIndexOf('.')) {
            // Formato latinoamericano/europeo: 1.234,56 -> 1234.56
            clean = clean.replaceAll('.', '').replaceAll(',', '.');
          } else {
            // Formato anglosajón: 1,234.56 -> 1234.56
            clean = clean.replaceAll(',', '');
          }
        } else {
          clean = clean.replaceAll(',', '.');
        }
        final val = double.tryParse(clean);
        if (val == null || val <= 0 || val.isNaN || val.isInfinite) return null;
        return double.parse(val.toStringAsFixed(2));
      }

      // Argentine / European format
      expect(sanitizeAndParse('1.234,56'), 1234.56);
      expect(sanitizeAndParse('50.000,00'), 50000.00);

      // US format
      expect(sanitizeAndParse('1,234.56'), 1234.56);
      expect(sanitizeAndParse('50,000.00'), 50000.00);

      // Simple formats
      expect(sanitizeAndParse('1234,56'), 1234.56);
      expect(sanitizeAndParse('1234.56'), 1234.56);
      expect(sanitizeAndParse('1234'), 1234.00);

      // Invalid inputs
      expect(sanitizeAndParse('abc'), isNull);
      expect(sanitizeAndParse('-500'), isNull);
      expect(sanitizeAndParse('0'), isNull);
    });

    test('Adversarial finding: Silent input discard when pending controller has invalid text and payments.isNotEmpty', () {
      // Suppose cashier has 1 valid payment item ($10,000 cash)
      final payments = <PaymentItem>[
        PaymentItem(method: 'cash', amount: 10000.0),
      ];

      // Cashier tries to add a second payment with thousand separator "1.500,50"
      const pendingInput = '1.500,50';

      double? sanitizeAndParse(String text) {
        final clean = text.trim().replaceAll(',', '.');
        final val = double.tryParse(clean);
        if (val == null || val <= 0 || val.isNaN || val.isInfinite) return null;
        return double.parse(val.toStringAsFixed(2));
      }

      final pendingAmount = sanitizeAndParse(pendingInput) ?? 0;

      // In _submit():
      // if (pendingAmount > 0) { _addPayment(); }
      // Because pendingAmount is 0, _addPayment() is NOT called!
      // But because payments.isNotEmpty (has 10000.0), _submit() proceeds WITHOUT WARNING!
      expect(pendingAmount, 0.0);
      expect(payments.length, 1);
      // The pending input "1.500,50" is SILENTLY DROPPED!
    });
  });

  group('CHALLENGE 6: MovementFormDialog Widget Stress Tests', () {
    late FakeCheckProvider fakeCheckProvider;
    late FakeSupplierProvider fakeSupplierProvider;
    late FakeExpenseCategoryProvider fakeExpenseCategoryProvider;
    late FakeCashMovementProvider fakeCashMovementProvider;
    late FakeCashRegisterProvider fakeCashRegisterProvider;
    late FakeSettingsProvider fakeSettingsProvider;
    late FakeAuthProvider fakeAuthProvider;
    late FakeLocalTerminalProvider fakeLocalTerminalProvider;

    setUp(() {
      SharedPreferences.setMockInitialValues({'auto_print_cash_movement': false});

      fakeCheckProvider = FakeCheckProvider();
      fakeSupplierProvider = FakeSupplierProvider();
      fakeExpenseCategoryProvider = FakeExpenseCategoryProvider();
      fakeCashMovementProvider = FakeCashMovementProvider();
      fakeCashRegisterProvider = FakeCashRegisterProvider();
      fakeSettingsProvider = FakeSettingsProvider();
      fakeAuthProvider = FakeAuthProvider();
      fakeLocalTerminalProvider = FakeLocalTerminalProvider();

      fakeSupplierProvider.setSuppliers([
        Supplier(
          id: 1,
          name: 'Proveedor Mayorista A',
          cuit: '30-11223344-9',
          balance: 60000.0,
          isActive: true,
        ),
        Supplier(
          id: 2,
          name: 'Proveedor Menor B',
          cuit: '30-99887766-3',
          balance: 10000.0,
          isActive: true,
        ),
      ]);

      fakeCheckProvider.setChecks([
        ThirdPartyCheck(
          id: 201,
          bankName: 'Banco Macro',
          checkNumber: 'CHK-201',
          amount: 40000.0,
          issueDate: DateTime(2026, 9, 1),
          paymentDate: DateTime(2026, 9, 30),
          issuerName: 'Cliente Juan',
          issuerCuit: '20-11223344-5',
          status: 'in_wallet',
        ),
      ]);

      fakeCashRegisterProvider.setShift(
        CashRegisterShift(
          id: 1,
          cashRegisterId: 1,
          userId: 1,
          openingBalance: 10000.0,
          status: 'open',
          openedAt: DateTime.now(),
        ),
      );
    });

    testWidgets('Widget Stress: Switching movement type from supplier_payment to expense purges checks and resets supplier', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(
        buildTestDialog(
          fakeCheckProvider: fakeCheckProvider,
          fakeSupplierProvider: fakeSupplierProvider,
          fakeExpenseCategoryProvider: fakeExpenseCategoryProvider,
          fakeCashMovementProvider: fakeCashMovementProvider,
          fakeCashRegisterProvider: fakeCashRegisterProvider,
          fakeSettingsProvider: fakeSettingsProvider,
          fakeAuthProvider: fakeAuthProvider,
          fakeLocalTerminalProvider: fakeLocalTerminalProvider,
          initialType: 'supplier_payment',
          initialSupplierId: 1,
        ),
      );
      await tester.pumpAndSettle();

      // Add 15000 cash payment
      final montoFieldFinder = find.widgetWithText(TextFormField, 'Monto');
      await tester.enterText(montoFieldFinder, '15000');
      await tester.pump();

      final agregarBtn = find.widgetWithText(ElevatedButton, 'Agregar');
      await tester.tap(agregarBtn);
      await tester.pumpAndSettle();

      expect(find.text('EFECTIVO'), findsOneWidget);

      // Add Check payment #201
      final methodDropdownFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Método');
      await tester.tap(methodDropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();

      final checkDropdownFinder = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      await tester.tap(checkDropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CHK-201').last);
      await tester.pumpAndSettle();

      await tester.tap(agregarBtn);
      await tester.pumpAndSettle();

      expect(find.text('CHEQUE'), findsOneWidget);

      // Now switch type to 'expense'
      final typeDropdownFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Tipo de Movimiento');
      await tester.tap(typeDropdownFinder);
      await tester.pumpAndSettle();

      final expenseOption = find.text('Gasto Operativo (Salida)').last;
      await tester.tap(expenseOption);
      await tester.pumpAndSettle();

      // Remediated (V-06): Check payment is purged because checks are prohibited for operational expenses!
      expect(find.text('CHEQUE'), findsNothing);
      // Cash payment is preserved because cash is valid for expenses
      expect(find.text('EFECTIVO'), findsOneWidget);
    });
  });
}
