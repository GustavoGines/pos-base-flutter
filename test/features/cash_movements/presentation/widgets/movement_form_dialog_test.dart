import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';

import 'package:frontend_desktop/features/cash_movements/presentation/widgets/movement_form_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/ticket_preview_dialog.dart';
import 'package:frontend_desktop/features/cash_movements/services/cash_movement_pdf_service.dart';
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

  @override
  int? get activeRegisterId => _currentShift?.cashRegisterId ?? 1;

  void setShift(CashRegisterShift? shift) {
    _currentShift = shift;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  int get assignedRegisterId => 1;
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

  @override
  Map<String, dynamic>? get currentUser => const {'id': 1, 'name': 'Admin'};

  void setIsAdmin(bool value) {
    _isAdmin = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  bool get autoOpenCashDrawer => false;
  @override
  String get scaleComPort => '';
  @override
  String get printerConnection => 'none';

  @override
  String get printerFormat => 'thermal_80';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        name: 'Distribuidora Norte SA',
        cuit: '30-11223344-9',
        balance: 15000.0,
        isActive: true,
      ),
      Supplier(
        id: 2,
        name: 'Lácteos del Sur SRL',
        cuit: '30-99887766-3',
        balance: 50000.0,
        isActive: true,
      ),
    ]);

    fakeCheckProvider.setChecks([
      ThirdPartyCheck(
        id: 101,
        bankName: 'Banco Santander',
        checkNumber: '8877001',
        amount: 50000.0,
        issueDate: DateTime(2026, 9, 1),
        paymentDate: DateTime(2026, 9, 30),
        issuerName: 'Cliente Juan',
        issuerCuit: '20-11223344-5',
        status: 'in_wallet',
      ),
      ThirdPartyCheck(
        id: 102,
        bankName: 'Banco Galicia',
        checkNumber: '8877002',
        amount: 25000.0,
        issueDate: DateTime(2026, 9, 5),
        paymentDate: DateTime(2026, 10, 5),
        issuerName: 'Cliente Pedro',
        issuerCuit: '20-99887766-5',
        status: 'in_wallet',
      ),
    ]);

    fakeCashRegisterProvider.setShift(
      CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openingBalance: 5000.0,
        status: 'open',
        openedAt: DateTime.now(),
      ),
    );
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

  Widget buildTestDialog({
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

  group('MovementFormDialog Widget Remediations & Verification Tests', () {
    testWidgets('Pre-populates cash payment item when initialAmount > 0 (Initial Cash Trap)', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(
        buildTestDialog(
          initialType: 'supplier_payment',
          initialSupplierId: 1,
          initialAmount: 20000.0,
        ),
      );
      await tester.pumpAndSettle();

      // Verify that Cash payment row is auto-created in _payments list
      expect(find.text('EFECTIVO'), findsOneWidget);
      final formattedAmount = '\$${20000.0.toCurrency()}';
      expect(find.text(formattedAmount), findsWidgets);

      // Verify trash icon can remove it
      final deleteIconFinder = find.byIcon(Icons.delete);
      expect(deleteIconFinder, findsOneWidget);
      await tester.tap(deleteIconFinder);
      await tester.pumpAndSettle();

      // Cash row is now removed
      expect(find.text('EFECTIVO'), findsNothing);
    });

    testWidgets('Remediation: Pagar Restante is blocked for checks and check preserves face-value', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(
        buildTestDialog(
          initialType: 'supplier_payment',
          initialSupplierId: 1, // Supplier 1 debt is $15,000
        ),
      );
      await tester.pumpAndSettle();

      // Verify supplier debt is displayed
      expect(find.text('Deuda Actual'), findsOneWidget);

      // Switch method dropdown from 'Efectivo' to 'Cheque'
      final methodDropdownFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Método');
      expect(methodDropdownFinder, findsOneWidget);

      await tester.tap(methodDropdownFinder);
      await tester.pumpAndSettle();

      // Select 'Cheque'
      final chequeItemFinder = find.text('Cheque').last;
      await tester.tap(chequeItemFinder);
      await tester.pumpAndSettle();

      // Now the check dropdown is visible: 'Seleccionar Cheque en Cartera'
      final checkDropdownFinder = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      expect(checkDropdownFinder, findsOneWidget);

      await tester.tap(checkDropdownFinder);
      await tester.pumpAndSettle();

      // Select Check #101 ($50,000)
      final checkItemFinder = find.textContaining('8877001').last;
      await tester.tap(checkItemFinder);
      await tester.pumpAndSettle();

      // Controller text was populated with 50.000
      expect(find.text('50.000'), findsOneWidget);

      // Tap "Pagar Total" / "Pagar Restante" button
      final pagarTotalFinder = find.widgetWithText(TextButton, 'Pagar Total');
      expect(pagarTotalFinder, findsOneWidget);
      await tester.tap(pagarTotalFinder);
      await tester.pumpAndSettle();

      // Remediated: Warning SnackBar appears, controller text is NOT overwritten to debt amount!
      expect(find.text('El monto de un cheque no puede modificarse.'), findsOneWidget);
      expect(find.text('50.000'), findsOneWidget);

      // Tap "Agregar"
      final agregarBtnFinder = find.widgetWithText(ElevatedButton, 'Agregar');
      await tester.tap(agregarBtnFinder);
      await tester.pumpAndSettle();

      // Remediated: Check is added with its nominal face value $50.000!
      expect(find.text('CHEQUE'), findsOneWidget);
      final formattedFaceValue = '\$${50000.0.toCurrency()}';
      expect(find.text(formattedFaceValue), findsWidgets);
    });

    testWidgets('Remediation: Comma-decimal "150,50" parses correctly and payment is added', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(
        buildTestDialog(
          initialType: 'supplier_payment',
          initialSupplierId: 1,
        ),
      );
      await tester.pumpAndSettle();

      // Find Monto text field
      final montoFieldFinder = find.widgetWithText(TextFormField, 'Monto');
      expect(montoFieldFinder, findsOneWidget);

      // Enter Argentine format decimal "150,50"
      await tester.enterText(montoFieldFinder, '150,50');
      await tester.pump();

      // Tap "Agregar"
      final agregarBtnFinder = find.widgetWithText(ElevatedButton, 'Agregar');
      await tester.tap(agregarBtnFinder);
      await tester.pumpAndSettle();

      // Remediated: Payment of $150,50 is successfully added to payments list!
      expect(find.text('EFECTIVO'), findsOneWidget);
      final formattedAmount = '\$${150.50.toCurrency()}';
      expect(find.text(formattedAmount), findsWidgets);
      expect(find.text('Ingrese un monto válido.'), findsNothing);
    });

    testWidgets('Remediation: Payments and controllers are cleared when supplier changes', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(
        buildTestDialog(
          initialType: 'supplier_payment',
          initialSupplierId: 1, // Supplier 1
        ),
      );
      await tester.pumpAndSettle();

      // Enter 5000 cash payment
      final montoFieldFinder = find.widgetWithText(TextFormField, 'Monto');
      await tester.enterText(montoFieldFinder, '5000');
      await tester.pump();

      final agregarBtnFinder = find.widgetWithText(ElevatedButton, 'Agregar');
      await tester.tap(agregarBtnFinder);
      await tester.pumpAndSettle();

      // Payment is added for Supplier 1
      expect(find.text('EFECTIVO'), findsOneWidget);
      final formattedFiveThousand = '\$${5000.0.toCurrency()}';
      expect(find.text(formattedFiveThousand), findsWidgets);

      // Change supplier dropdown to Supplier 2
      final supplierDropdownFinder = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Proveedor');
      await tester.tap(supplierDropdownFinder);
      await tester.pumpAndSettle();

      final supplier2Option = find.text('Lácteos del Sur SRL').last;
      await tester.tap(supplier2Option);
      await tester.pumpAndSettle();

      // Remediated: Payment list is cleared upon changing supplier!
      expect(find.text('EFECTIVO'), findsNothing);
      expect(find.text(formattedFiveThousand), findsNothing);
    });

    testWidgets('Remediation: Selected check is filtered out from availableChecks and duplicate checks cannot be added', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(
        buildTestDialog(
          initialType: 'supplier_payment',
          initialSupplierId: 1,
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Cheque
      final methodDropdownFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Método');
      await tester.tap(methodDropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();

      // Select Check #101
      final checkDropdownFinder = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      await tester.tap(checkDropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('8877001').last);
      await tester.pumpAndSettle();

      // Add Check #101
      final agregarBtn = find.widgetWithText(ElevatedButton, 'Agregar');
      await tester.tap(agregarBtn);
      await tester.pumpAndSettle();

      expect(find.text('CHEQUE'), findsOneWidget);

      // In remediated dialog, Check #101 is filtered out of availableChecks:
      // Open dropdown again:
      await tester.tap(checkDropdownFinder);
      await tester.pumpAndSettle();

      // Check #102 is present in the dropdown items:
      expect(find.widgetWithText(DropdownMenuItem<int>, 'Nº 8877002 (\$ 25.000) - Banco Galicia'), findsWidgets);
      // But Check #101 is NOT present in any DropdownMenuItem:
      expect(find.widgetWithText(DropdownMenuItem<int>, 'Nº 8877001 (\$ 50.000) - Banco Santander'), findsNothing);

      // Close dropdown by selecting Check #102
      await tester.tap(find.textContaining('8877002').last);
      await tester.pumpAndSettle();

      // Still only 1 CHEQUE payment row in list
      expect(find.text('CHEQUE'), findsOneWidget);
    });

    testWidgets('Remediation: V-03 overpayment with check prompts confirmation dialog for cash vuelto', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(
        buildTestDialog(
          initialType: 'supplier_payment',
          initialSupplierId: 1, // Supplier 1 debt is $15,000
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Cheque
      final methodDropdownFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Método');
      await tester.tap(methodDropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();

      // Select Check #101 ($50,000 > debt $15,000 -> change is $35,000)
      final checkDropdownFinder = find.widgetWithText(DropdownButtonFormField<int>, 'Seleccionar Cheque en Cartera');
      await tester.tap(checkDropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('8877001').last);
      await tester.pumpAndSettle();

      // Add Check #101
      final agregarBtn = find.widgetWithText(ElevatedButton, 'Agregar');
      await tester.tap(agregarBtn);
      await tester.pumpAndSettle();

      // Tap "Procesar Movimiento"
      final submitBtn = find.text('Procesar Movimiento');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Remediated V-03: Confirmation dialog appears with vuelto amount
      expect(find.text('Vuelto de Proveedor por Cheque'), findsOneWidget);
      expect(find.textContaining('supera la deuda actual'), findsOneWidget);
      expect(find.text('\$35.000'), findsOneWidget);

      // Confirm dialog
      final confirmBtn = find.widgetWithText(ElevatedButton, 'Confirmar e Ingresar Vuelto');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Movement was submitted
      expect(fakeCashMovementProvider.createMovementCallCount, 1);
    });

    testWidgets('Remediation: Guard prevents silent input discard on invalid amount submit', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(
        buildTestDialog(
          initialType: 'supplier_payment',
          initialSupplierId: 1,
        ),
      );
      await tester.pumpAndSettle();

      // Add valid cash payment first
      final montoFieldFinder = find.widgetWithText(TextFormField, 'Monto');
      await tester.enterText(montoFieldFinder, '5000');
      await tester.pump();

      final agregarBtn = find.widgetWithText(ElevatedButton, 'Agregar');
      await tester.tap(agregarBtn);
      await tester.pumpAndSettle();

      expect(find.text('EFECTIVO'), findsOneWidget);

      // Now enter invalid amount (0) in text field without clicking Agregar
      await tester.enterText(montoFieldFinder, '0');
      await tester.pump();

      // Click "Procesar Movimiento"
      final submitBtn = find.text('Procesar Movimiento');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Should show error SnackBar and NOT submit
      expect(find.text('El monto ingresado en el campo es inválido. Corríjalo o bórrelo antes de procesar.'), findsOneWidget);
      expect(fakeCashMovementProvider.createMovementCallCount, 0);
    });

    testWidgets('Owner Funds (Fondos Propios / Bolsillo): defaults to owner_funds for supplier_payment and submits funding_source + payment_method cleanly', (tester) async {
      setDesktopSize(tester);
      fakeCashRegisterProvider.setShift(null);

      await tester.pumpWidget(
        buildTestDialog(
          initialType: 'supplier_payment',
          initialSupplierId: 1,
          initialAmount: 15000.0,
        ),
      );
      await tester.pumpAndSettle();

      // Banner de operación con caja cerrada visible y pago pre-cargado como EFECTIVO de Fondos Propios / Bolsillo
      expect(find.textContaining('Operando con caja cerrada'), findsOneWidget);
      expect(find.text('EFECTIVO'), findsOneWidget);
      expect(find.text('Fondos Propios / Bolsillo'), findsOneWidget);

      final submitBtn = find.text('Procesar Movimiento');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(fakeCashMovementProvider.createMovementCallCount, 1);
      expect(fakeCashMovementProvider.lastSubmittedPayload?['cash_shift_id'], isNull);
      final payments = fakeCashMovementProvider.lastSubmittedPayload?['payments'] as List?;
      expect(payments, isNotNull);
      expect(payments!.first['payment_method'], 'cash');
      expect(payments.first['funding_source'], 'owner_funds');
      expect(payments.first['amount'], 15000.0);
    });

    test('CashMovementPdfService formats currency with leading dollar sign and hyphenates CUIT', () async {
      expect(CashMovementPdfService.formatCurrency(123187.24), '\$ 123.187,24');
      expect(CashMovementPdfService.formatCurrency(0), '\$ 0,00');
      expect(CashMovementPdfService.formatCuit('20396063299'), '20-39606329-9');
      expect(CashMovementPdfService.formatCuit('27-38829149-7'), '27-38829149-7');

      const mockSettings = BusinessSettings(
        companyName: 'DEV4U',
        address: 'Av. 25 de Mayo 123',
        phone: '3704123456',
        taxId: '20396063299',
        taxCondition: 'responsable_inscripto',
        iibb: '909-123456-1',
      );

      final pdfBytes = await CashMovementPdfService.generateSupplierPdfBytesForTest(
        type: 'supplier_payment',
        supplierName: '180 Pasteleria',
        supplierCuit: '27388291497',
        totalAmount: 123187.24,
        balanceBefore: 123187.24,
        payments: const [
          {'payment_method': 'cash', 'funding_source': 'owner_funds', 'amount': 123187.24}
        ],
        businessName: 'DEV4U',
        businessTaxId: '20396063299',
        businessSettings: mockSettings,
        movementIds: const [16],
        cashierName: 'ADMINISTRADOR',
      );
      expect(pdfBytes, isNotEmpty);

      final genericPdfBytes = await CashMovementPdfService.generateGenericPdfBytesForTest(
        type: 'expense',
        category: 'Flete',
        totalAmount: 4500.0,
        payments: const [
          {'payment_method': 'cash', 'funding_source': 'cash_register', 'amount': 4500.0}
        ],
        businessName: 'DEV4U',
        businessTaxId: '20396063299',
        businessSettings: mockSettings,
        movementIds: const [17],
        cashierName: 'ADMINISTRADOR',
        paperSize: 'letter',
      );
      expect(genericPdfBytes, isNotEmpty);

      final lines80 = CashMovementPdfService.buildSupplierPaymentTicketLines(
        type: 'supplier_payment',
        supplierName: '180 Pasteleria',
        supplierCuit: '27388291497',
        totalAmount: 123187.24,
        balanceBefore: 123187.24,
        payments: const [
          {'payment_method': 'cash', 'funding_source': 'owner_funds', 'amount': 123187.24}
        ],
        businessName: 'DEV4U',
        businessTaxId: '20396063299',
        movementIds: const [16],
        cashierName: 'ADMINISTRADOR',
        is58mm: false,
      );
      expect(lines80.any((l) => l.text.contains('180 PASTELERIA')), isTrue);
      expect(lines80.any((l) => l.text == 'CUENTA AL DIA' && l.rightText == '\$0'), isTrue);

      final lines58 = CashMovementPdfService.buildGenericMovementTicketLines(
        type: 'expense',
        category: 'Flete',
        totalAmount: 4500.0,
        payments: const [
          {'payment_method': 'cash', 'funding_source': 'cash_register', 'amount': 4500.0}
        ],
        businessName: 'DEV4U',
        movementIds: const [17],
        is58mm: true,
      );
      expect(lines58.any((l) => l.text == 'PAGO:' && l.rightText == 'EFECTIVO (CAJA)'), isTrue);
    });

    testWidgets('Thermal Preview (58mm/80mm) opens when print checkbox is checked, and skips preview when unchecked', (tester) async {
      setDesktopSize(tester);

      await tester.pumpWidget(
        buildTestDialog(
          initialType: 'supplier_payment',
          initialSupplierId: 1,
          initialAmount: 15000.0,
        ),
      );
      await tester.pumpAndSettle();

      // Checkbox is always visible even when printerConnection == 'none'
      final printCheckbox = find.text('Imprimir / Ver comprobante al registrar');
      expect(printCheckbox, findsOneWidget);
      expect(find.text('Solo registrar movimiento (sin abrir vista previa ni imprimir)'), findsOneWidget);

      // Enable print checkbox
      await tester.tap(printCheckbox);
      await tester.pumpAndSettle();
      expect(find.textContaining('Al guardar podrás elegir Ticket Térmico (58/80mm)'), findsOneWidget);

      // Submit movement -> PrintFormatSelector appears (CircularProgressIndicator is active on background button, so use pump)
      await tester.tap(find.text('Procesar Movimiento'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Ticket\nTérmico'), findsOneWidget);
      await tester.tap(find.text('Ticket\nTérmico'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // TicketPreviewDialog opens with 58mm and 80mm chips!
      expect(find.text('Vista Previa — Pago a Proveedor'), findsOneWidget);
      expect(find.text('58mm'), findsOneWidget);
      expect(find.text('80mm'), findsOneWidget);
      expect(find.text('Imprimir'), findsOneWidget);
      expect(find.text('(80mm)'), findsOneWidget);

      // Switch to 58mm in preview
      await tester.tap(find.text('58mm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('(58mm)'), findsOneWidget);

      // Close preview
      await tester.tap(
        find.descendant(
          of: find.byType(TicketPreviewDialog),
          matching: find.text('Cancelar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeCashMovementProvider.createMovementCallCount, 1);
    });
  });
}
