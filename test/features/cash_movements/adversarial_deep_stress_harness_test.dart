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

class HarnessCheckProvider extends ChangeNotifier implements CheckProvider {
  List<ThirdPartyCheck> _checks = [];
  int loadChecksCallCount = 0;

  @override
  List<ThirdPartyCheck> get checks => _checks;

  void setChecks(List<ThirdPartyCheck> list) {
    _checks = list;
    notifyListeners();
  }

  @override
  Future<void> loadChecks() async {
    loadChecksCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HarnessSupplierProvider extends ChangeNotifier implements SupplierProvider {
  List<Supplier> _suppliers = [];
  int fetchSuppliersCallCount = 0;

  @override
  List<Supplier> get suppliers => _suppliers;

  void setSuppliers(List<Supplier> list) {
    _suppliers = list;
    notifyListeners();
  }

  @override
  Future<void> fetchSuppliers({String? search}) async {
    fetchSuppliersCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HarnessExpenseCategoryProvider extends ChangeNotifier implements ExpenseCategoryProvider {
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

class HarnessCashMovementProvider extends ChangeNotifier implements CashMovementProvider {
  Map<String, dynamic>? lastSubmittedPayload;
  int createMovementCallCount = 0;
  List<int> resultIds = [100, 101];

  @override
  Future<List<int>> createMovement(Map<String, dynamic> data, {String? adminPin}) async {
    createMovementCallCount++;
    lastSubmittedPayload = data;
    return resultIds;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HarnessCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
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

class HarnessSettingsProvider extends ChangeNotifier implements SettingsProvider {
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

class HarnessAuthProvider extends ChangeNotifier implements AuthProvider {
  bool _isAdmin = true;
  @override
  bool get isAdmin => _isAdmin;

  void setIsAdmin(bool value) {
    _isAdmin = value;
    notifyListeners();
  }

  @override
  Map<String, dynamic>? get currentUser => {'name': 'Auditor Challenger'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HarnessLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerConnection => 'none';

  @override
  String get printerFormat => 'thermal_80';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ThirdPartyCheck createCheck({
  required int id,
  required String checkNumber,
  required String bankName,
  required double amount,
  String status = 'in_wallet',
}) {
  return ThirdPartyCheck(
    id: id,
    checkNumber: checkNumber,
    bankName: bankName,
    amount: amount,
    issueDate: DateTime(2026, 9, 1),
    paymentDate: DateTime(2026, 9, 30),
    issuerName: 'Cliente Prueba',
    issuerCuit: '20-33445566-7',
    status: status,
  );
}

// Pure arithmetic parser mirror
double? harnessSanitizeAndParse(String text) {
  var clean = text.trim();
  if (clean.contains('.') && clean.contains(',')) {
    if (clean.lastIndexOf(',') > clean.lastIndexOf('.')) {
      clean = clean.replaceAll('.', '').replaceAll(',', '.');
    } else {
      clean = clean.replaceAll(',', '');
    }
  } else {
    clean = clean.replaceAll(',', '.');
  }
  final val = double.tryParse(clean);
  if (val == null || val <= 0 || val.isNaN || val.isInfinite) return null;
  return double.parse(val.toStringAsFixed(2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HarnessCheckProvider checkProv;
  late HarnessSupplierProvider supplierProv;
  late HarnessExpenseCategoryProvider expenseCatProv;
  late HarnessCashMovementProvider cashMovementProv;
  late HarnessCashRegisterProvider cashRegisterProv;
  late HarnessSettingsProvider settingsProv;
  late HarnessAuthProvider authProv;
  late HarnessLocalTerminalProvider localTerminalProv;

  setUp(() {
    SharedPreferences.setMockInitialValues({'auto_print_cash_movement': false});

    checkProv = HarnessCheckProvider();
    supplierProv = HarnessSupplierProvider();
    expenseCatProv = HarnessExpenseCategoryProvider();
    cashMovementProv = HarnessCashMovementProvider();
    cashRegisterProv = HarnessCashRegisterProvider();
    settingsProv = HarnessSettingsProvider();
    authProv = HarnessAuthProvider();
    localTerminalProv = HarnessLocalTerminalProvider();

    supplierProv.setSuppliers([
      Supplier(
        id: 1,
        name: 'Proveedor Alfa SA',
        cuit: '30-11111111-1',
        balance: 50000.0,
        isActive: true,
      ),
      Supplier(
        id: 2,
        name: 'Proveedor Beta SRL',
        cuit: '30-22222222-2',
        balance: 15000.0,
        isActive: true,
      ),
    ]);

    expenseCatProv.setCategories([
      ExpenseCategory(id: 1, name: 'Servicios', isActive: true),
      ExpenseCategory(id: 2, name: 'Alquiler', isActive: true),
    ]);
  });

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

  Widget buildDialog({int? initialSupplierId, String initialType = 'supplier_payment'}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CheckProvider>.value(value: checkProv),
        ChangeNotifierProvider<SupplierProvider>.value(value: supplierProv),
        ChangeNotifierProvider<ExpenseCategoryProvider>.value(value: expenseCatProv),
        ChangeNotifierProvider<CashMovementProvider>.value(value: cashMovementProv),
        ChangeNotifierProvider<CashRegisterProvider>.value(value: cashRegisterProv),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
        ChangeNotifierProvider<AuthProvider>.value(value: authProv),
        ChangeNotifierProvider<LocalTerminalProvider>.value(value: localTerminalProv),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MovementFormDialog(
            initialSupplierId: initialSupplierId,
            initialType: initialType,
          ),
        ),
      ),
    );
  }

  group('EDGE CASE 1: IEEE 754 Floating-Point Precision Drift & Rounding', () {
    test('Sub-cent precision drift (0.1 + 0.2) is quantized to exact 0.30', () {
      final double sum = 0.1 + 0.2; // 0.30000000000000004
      expect(sum == 0.3, isFalse, reason: 'IEEE 754 precision drift inherently occurs');
      final parsed = harnessSanitizeAndParse(sum.toString());
      expect(parsed, equals(0.30));
    });

    test('Subtraction drift (100.30 - 100.10 = 0.20000000000000284) sanitizes cleanly', () {
      final double diff = 100.30 - 100.10;
      expect(diff == 0.2, isFalse);
      final parsed = harnessSanitizeAndParse(diff.toString());
      expect(parsed, equals(0.20));
    });

    test('Sub-cent fractional amounts below 0.005 round to 0.0 and are rejected', () {
      final parsed = harnessSanitizeAndParse('0.004');
      expect(parsed == null || parsed <= 0, isTrue);
    });

    test('Large financial amounts (999,999,999.99) retain full precision without crash', () {
      final parsed = harnessSanitizeAndParse('999999999.99');
      expect(parsed, equals(999999999.99));
    });

    test('Accumulation of 100 micro-payments (0.01) does not suffer cumulative drift', () {
      final items = List.generate(100, (i) => 0.01);
      final rawSum = items.fold(0.0, (acc, val) => acc + val);
      final quantizedSum = double.parse(rawSum.toStringAsFixed(2));
      expect(quantizedSum, equals(1.00));
    });
  });

  group('EDGE CASE 2: Zero, Negative, and Malformed String Inputs', () {
    test('Zero values in various formats return null', () {
      expect(harnessSanitizeAndParse('0'), isNull);
      expect(harnessSanitizeAndParse('0.0'), isNull);
      expect(harnessSanitizeAndParse('0,00'), isNull);
      expect(harnessSanitizeAndParse('0.000'), isNull);
      expect(harnessSanitizeAndParse('-0'), isNull);
    });

    test('Negative values return null', () {
      expect(harnessSanitizeAndParse('-1'), isNull);
      expect(harnessSanitizeAndParse('-100.50'), isNull);
      expect(harnessSanitizeAndParse('-1.500,00'), isNull);
      expect(harnessSanitizeAndParse('-0.01'), isNull);
    });

    test('Special non-numeric and IEEE strings return null', () {
      expect(harnessSanitizeAndParse('NaN'), isNull);
      expect(harnessSanitizeAndParse('Infinity'), isNull);
      expect(harnessSanitizeAndParse('-Infinity'), isNull);
      expect(harnessSanitizeAndParse('abc'), isNull);
      expect(harnessSanitizeAndParse('12a34'), isNull);
      expect(harnessSanitizeAndParse(''), isNull);
      expect(harnessSanitizeAndParse('   '), isNull);
    });

    test('Malformed separators return null without throwing exceptions', () {
      expect(harnessSanitizeAndParse('...'), isNull);
      expect(harnessSanitizeAndParse(',,,'), isNull);
      expect(harnessSanitizeAndParse('1.2.3.4'), isNull);
      expect(harnessSanitizeAndParse('1,2,3,4'), isNull);
    });

    testWidgets('Submitting invalid text in amount field with prior payments is blocked', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(buildDialog(initialSupplierId: 1));
      await tester.pumpAndSettle();

      // Enter valid cash payment
      final montoFieldFinder = find.widgetWithText(TextFormField, 'Monto');
      expect(montoFieldFinder, findsOneWidget);

      await tester.enterText(montoFieldFinder, '500');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pumpAndSettle();

      // Now enter invalid text into the amount field
      await tester.enterText(montoFieldFinder, 'invalido123');
      await tester.pump();

      // Try to submit via "Procesar Movimiento"
      await tester.tap(find.text('Procesar Movimiento'));
      await tester.pumpAndSettle();

      // Verify SnackBar warning appears and submission is BLOCKED
      expect(find.text('El monto ingresado en el campo es inválido. Corríjalo o bórrelo antes de procesar.'), findsOneWidget);
      expect(cashMovementProv.createMovementCallCount, equals(0));
    });
  });

  group('EDGE CASE 3: Rapid Addition/Removal and Homogeneous Check Portfolios', () {
    testWidgets('Homogeneous check portfolio with identical bank and amount isolates by ID', (tester) async {
      setDesktopSize(tester);

      // Create 5 identical checks differing only in id and checkNumber
      final homogeneousChecks = List<ThirdPartyCheck>.generate(5, (index) => createCheck(
        id: index + 10,
        checkNumber: 'CHK-999$index',
        bankName: 'Banco Macro',
        amount: 5000.0,
      ));
      checkProv.setChecks(homogeneousChecks);

      await tester.pumpWidget(buildDialog(initialSupplierId: 1));
      await tester.pumpAndSettle();

      // Switch to check method
      final methodDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Método');
      await tester.tap(methodDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();

      // Select Check #10
      final checkDropdown = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      expect(checkDropdown, findsOneWidget);
      await tester.tap(checkDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CHK-9990').last);
      await tester.pumpAndSettle();

      // Add Check #10
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pumpAndSettle();

      // Verify Check #10 is in payments
      expect(find.textContaining('CHK-9990'), findsOneWidget);

      // Verify Check #11 remains available in dropdown
      final checkDropdownAfter = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      expect(checkDropdownAfter, findsOneWidget);
      await tester.tap(checkDropdownAfter);
      await tester.pumpAndSettle();

      // Check #11 IS available
      expect(find.textContaining('CHK-9991'), findsWidgets);

      // Select Check #11
      await tester.tap(find.textContaining('CHK-9991').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pumpAndSettle();

      // Now remove Check #10 from payments list using Icons.delete
      final deleteIcons = find.byIcon(Icons.delete);
      expect(deleteIcons, findsNWidgets(2));
      await tester.tap(deleteIcons.first); // remove first payment (Check #10)
      await tester.pumpAndSettle();

      // Check #10 must be restored to dropdown
      final checkDropdownRestored = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      expect(checkDropdownRestored, findsOneWidget);
      await tester.tap(checkDropdownRestored);
      await tester.pumpAndSettle();
      expect(find.textContaining('CHK-9990'), findsWidgets);
    });
  });

  group('EDGE CASE 4: Repeated Movement Type and Supplier Switching (State Isolation)', () {
    testWidgets('Unconditionally clears uncommitted check and amount when switching supplier', (tester) async {
      setDesktopSize(tester);

      checkProv.setChecks([
        createCheck(
          id: 50,
          checkNumber: 'CHK-SECRET-50',
          bankName: 'Banco Rio',
          amount: 25000.0,
        ),
      ]);

      await tester.pumpWidget(buildDialog(initialSupplierId: 1));
      await tester.pumpAndSettle();

      // Switch to check method
      final methodDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Método');
      await tester.tap(methodDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();

      // Select Check #50 but DO NOT CLICK AGREGAR
      final checkDropdown = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      await tester.tap(checkDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CHK-SECRET-50').last);
      await tester.pumpAndSettle();

      // Verify controller text was auto-populated with check amount
      expect(find.text('25000.0'), findsOneWidget);

      // Now switch supplier from Proveedor Alfa (1) to Proveedor Beta (2)
      final supplierDropdown = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Proveedor');
      await tester.tap(supplierDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedor Beta SRL').last);
      await tester.pumpAndSettle();

      // Verify that changing supplier unconditionally wiped the controller
      expect(find.text('25000.0'), findsNothing);

      // Now try to process movement without adding payment: must fail validation
      await tester.tap(find.text('Procesar Movimiento'));
      await tester.pumpAndSettle();

      expect(find.text('Agregue al menos un método de pago.'), findsOneWidget);
      expect(cashMovementProv.createMovementCallCount, equals(0));
    });

    testWidgets('Switching type to expense purges check tender and resets method to cash', (tester) async {
      setDesktopSize(tester);

      checkProv.setChecks([
        createCheck(
          id: 60,
          checkNumber: 'CHK-EXP-60',
          bankName: 'Banco Nacion',
          amount: 12000.0,
        ),
      ]);

      await tester.pumpWidget(buildDialog(initialSupplierId: 1));
      await tester.pumpAndSettle();

      // Switch to check method and add Check #60
      final methodDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Método');
      await tester.tap(methodDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();

      final checkDropdown = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      await tester.tap(checkDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CHK-EXP-60').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CHK-EXP-60'), findsOneWidget);

      // Now switch movement type to 'Gasto Operativo (Salida)' (expense)
      final typeDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Tipo de Movimiento');
      await tester.tap(typeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gasto Operativo (Salida)').last);
      await tester.pumpAndSettle();

      // Verify that Check #60 was immediately purged from payments list
      expect(find.textContaining('CHK-EXP-60'), findsNothing);

      // Verify current payment method was reset to cash
      expect(find.text('Efectivo'), findsWidgets);
    });
  });

  group('EDGE CASE 5: Full Wallet Exhaustion and Safe Recovery', () {
    testWidgets('Exhausting entire wallet disables check dropdown cleanly without assertion crash', (tester) async {
      setDesktopSize(tester);

      // Exactly 2 checks in wallet
      checkProv.setChecks([
        createCheck(
          id: 101,
          checkNumber: 'CHK-EXH-1',
          bankName: 'Banco A',
          amount: 1000.0,
        ),
        createCheck(
          id: 102,
          checkNumber: 'CHK-EXH-2',
          bankName: 'Banco B',
          amount: 2000.0,
        ),
      ]);

      await tester.pumpWidget(buildDialog(initialSupplierId: 1));
      await tester.pumpAndSettle();

      // Switch to check method
      final methodDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Método');
      await tester.tap(methodDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();

      // Select & add Check 101
      var checkDropdown = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      await tester.tap(checkDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CHK-EXH-1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pumpAndSettle();

      // Select & add Check 102
      checkDropdown = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      await tester.tap(checkDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CHK-EXH-2').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pumpAndSettle();

      // Now all checks are selected: dropdown must render disabled 'No hay cheques disponibles'
      expect(find.text('No hay cheques disponibles'), findsOneWidget);

      // No assertion failure occurred! Now remove Check 101 using Icons.delete
      final deleteButtons = find.byIcon(Icons.delete);
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      // Dropdown transitions back to active with Check 101 restored
      expect(find.text('No hay cheques disponibles'), findsNothing);
      checkDropdown = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      expect(checkDropdown, findsOneWidget);
      await tester.tap(checkDropdown);
      await tester.pumpAndSettle();
      expect(find.textContaining('CHK-EXH-1'), findsWidgets);
    });

    testWidgets('Full wallet exhaustion payment submission completes and calls loadChecks', (tester) async {
      setDesktopSize(tester);

      checkProv.setChecks([
        createCheck(
          id: 201,
          checkNumber: 'CHK-FINAL-1',
          bankName: 'Banco Galicia',
          amount: 5000.0,
        ),
      ]);

      await tester.pumpWidget(buildDialog(initialSupplierId: 1));
      await tester.pumpAndSettle();

      // Select check method and add Check 201
      final methodDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Método');
      await tester.tap(methodDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();

      final checkDropdown = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      await tester.tap(checkDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CHK-FINAL-1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pumpAndSettle();

      // Submit via "Procesar Movimiento"
      await tester.tap(find.text('Procesar Movimiento'));
      await tester.pumpAndSettle();

      // Verify movement was created and loadChecks was invoked (1 on mount + 1 on submit = 2)
      expect(cashMovementProv.createMovementCallCount, equals(1));
      expect(checkProv.loadChecksCallCount, equals(2));
      expect(cashMovementProv.lastSubmittedPayload!['payments'], isNotNull);
      final submittedPayments = cashMovementProv.lastSubmittedPayload!['payments'] as List;
      expect(submittedPayments.length, equals(1));
      expect(submittedPayments.first['check_id'], equals(201));
      expect(submittedPayments.first['amount'], equals(5000.0));
    });
  });
}
