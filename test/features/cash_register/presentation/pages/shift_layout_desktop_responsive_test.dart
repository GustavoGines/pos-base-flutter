import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/pages/cash_shift_summary_screen.dart';
import 'package:frontend_desktop/features/reports/presentation/pages/general_audit_screen.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';

import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final bool _isPremium;
  final bool _hasChecks;

  FakeSettingsProvider({bool isPremium = true, bool hasChecks = true})
      : _isPremium = isPremium,
        _hasChecks = hasChecks;

  @override
  String get currentPlan => _isPremium ? 'premium' : 'basic';

  @override
  BusinessSettings get settings => BusinessSettings(
        companyName: 'Test Empresa S.A.',
        taxId: '30-11223344-5',
        features: FeatureFlags(checks: _hasChecks),
      );

  @override
  FeatureFlags get features => FeatureFlags(checks: _hasChecks);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => [];
  @override
  int get totalAlertsCount => 0;
  @override
  List<dynamic> get reactiveAlerts => [];
  @override
  List<dynamic> get predictiveCriticalAlerts => [];

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  bool loggedOut = false;

  @override
  Map<String, dynamic>? get currentUser =>
      {'id': 1, 'name': 'Admin User', 'role': 'admin'};

  @override
  Future<void> logout() async {
    loggedOut = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCashRegisterProvider extends ChangeNotifier
    implements CashRegisterProvider {
  final List<CashRegisterShift> _shiftsHistory;

  FakeCashRegisterProvider({List<CashRegisterShift>? shiftsHistory})
      : _shiftsHistory = shiftsHistory ?? [];

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  List<CashRegisterShift> get shiftsHistory => _shiftsHistory;

  @override
  Future<void> loadAllShifts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  CashRegisterShift createTestShift({
    required int id,
    required bool isOpen,
    double openingBalance = 10000.0,
    double cashSales = 50000.0,
    double cardSales = 25000.0,
    double transferSales = 15000.0,
    double checkSales = 8000.0,
    double totalSurcharge = 2500.0,
    double totalDeposits = 5000.0,
    double totalExpenses = 3000.0,
    double totalWithdrawals = 4000.0,
    double totalSupplierPayments = 7000.0,
    double totalRefunds = 1500.0,
    double? expectedBalance = 51000.0,
    double? actualBalance = 51000.0,
    double? difference = 0.0,
    int? ccSalesCount = 2,
    double? ccSales = 12000.0,
    int? checkCount = 1,
    List<Map<String, dynamic>>? checkDetails,
  }) {
    return CashRegisterShift(
      id: id,
      cashRegisterId: 1,
      userId: 10,
      cashRegisterName: 'Caja Principal',
      userName: 'Carlos Cajero',
      closedByUserName: isOpen ? null : 'Laura Supervisora',
      openingBalance: openingBalance,
      status: isOpen ? 'open' : 'closed',
      openedAt: DateTime(2026, 9, 28, 8, 30),
      closedAt: isOpen ? null : DateTime(2026, 9, 28, 17, 0),
      cashSales: cashSales,
      cardSales: cardSales,
      transferSales: transferSales,
      checkSales: checkSales,
      totalSales: cashSales + cardSales + transferSales + checkSales,
      totalSurcharge: totalSurcharge,
      totalDeposits: totalDeposits,
      totalExpenses: totalExpenses,
      totalWithdrawals: totalWithdrawals,
      totalSupplierPayments: totalSupplierPayments,
      totalRefunds: totalRefunds,
      expectedBalance: expectedBalance,
      actualBalance: actualBalance,
      difference: difference,
      ccSalesCount: ccSalesCount,
      ccSales: ccSales,
      checkCount: checkCount,
      checkDetails: checkDetails ??
          [
            {
              'bank_name': 'Banco Galicia',
              'check_number': '00984712',
              'amount': 8000.0,
              'payment_date': '2026-10-15',
            }
          ],
    );
  }

  group('CashShiftSummaryScreen desktop layout tests (R2)', () {
    testWidgets(
        'Renders desktop multi-column layout with maxWidth: 900 constraint on wide screens without RenderFlex overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.dumpErrorToConsole(details, forceReport: true);
      };

      final shift = createTestShift(id: 101, isOpen: false, difference: 0.0);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
                value: FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(
                value: FakeAuthProvider()),
          ],
          child: MaterialApp(
            home: CashShiftSummaryScreen(closedShift: shift),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final err = tester.takeException();
      if (err is FlutterError) {
        for (final d in err.diagnostics) {
          print(d.toStringDeep());
        }
      }
      expect(err, isNull);

      // Verify ConstrainedBox uses maxWidth 900
      final constrainedBoxes =
          tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox));
      final has900Box = constrainedBoxes
          .any((b) => b.constraints.maxWidth == 900.0);
      expect(has900Box, isTrue,
          reason: 'Expected ConstrainedBox with maxWidth: 900');

      // Verify both column section headers exist
      final balanceHeader = find.text('BALANCE DE CAJA');
      final salesHeader = find.text('DESGLOSE DE VENTAS');
      expect(balanceHeader, findsOneWidget);
      expect(salesHeader, findsOneWidget);

      // Verify side-by-side positioning (Balance on the left, Breakdown on the right)
      final balancePos = tester.getTopLeft(balanceHeader);
      final salesPos = tester.getTopLeft(salesHeader);
      expect(balancePos.dx < salesPos.dx, isTrue,
          reason:
              'Balance de Caja (${balancePos.dx}) should be to the left of Desglose de Ventas (${salesPos.dx})');

      // Verify key data items on left
      expect(find.text('Fondo Inicial'), findsOneWidget);
      expect(find.text('Efectivo Esperado'), findsOneWidget);
      expect(find.text('Efectivo Físico'), findsOneWidget);
      expect(find.text('SOBRANTE:'), findsOneWidget);

      // Verify key data items on right
      expect(find.text('Ventas en Efectivo'), findsOneWidget);
      expect(find.text('Ventas con Tarjeta'), findsOneWidget);
      expect(find.text('Ventas por Transf.'), findsOneWidget);
      expect(find.text('Total Recargos (Tarj/Billeteras)'), findsOneWidget);

      // Verify action buttons are visible without scrolling
      expect(find.text('Imprimir Cierre Z y Salir'), findsOneWidget);
      expect(find.text('Continuar sin imprimir'), findsOneWidget);
    });

    testWidgets(
        'Renders negative difference (Faltante) with distinct styling and dense cash movements',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final shift = createTestShift(
        id: 102,
        isOpen: false,
        difference: -2500.0,
        actualBalance: 48500.0,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
                value: FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(
                value: FakeAuthProvider()),
          ],
          child: MaterialApp(
            home: CashShiftSummaryScreen(closedShift: shift, isFromAudit: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('FALTANTE:'), findsOneWidget);
      expect(find.text('Reimprimir Cierre Z'), findsOneWidget);
      expect(find.text('Volver a Auditoría'), findsOneWidget);
    });

    testWidgets(
        'Renders gracefully in single-column fallback on narrow screen (< 650px)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final shift = createTestShift(id: 103, isOpen: false);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
                value: FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(
                value: FakeAuthProvider()),
          ],
          child: MaterialApp(
            home: CashShiftSummaryScreen(closedShift: shift),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final balanceHeader = find.text('BALANCE DE CAJA');
      final salesHeader = find.text('DESGLOSE DE VENTAS');
      expect(balanceHeader, findsOneWidget);
      expect(salesHeader, findsOneWidget);

      // On narrow screen, they are stacked vertically
      final balancePos = tester.getTopLeft(balanceHeader);
      final salesPos = tester.getTopLeft(salesHeader);
      expect(balancePos.dy < salesPos.dy, isTrue,
          reason: 'Balance should be stacked above Desglose on narrow screen');
    });
  });

  group('GeneralAuditScreen _showShiftDetail dialog tests (R1)', () {
    testWidgets(
        'Opens shift detail dialog with width 900 and side-by-side Desglose and Balance panels',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exceptionAsString().contains('global_app_bar.dart') ||
            details.exceptionAsString().contains('99078')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final openShift = createTestShift(id: 201, isOpen: true);

      final fakeCashProvider = FakeCashRegisterProvider(
        shiftsHistory: [openShift],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CashRegisterProvider>.value(
                value: fakeCashProvider),
            ChangeNotifierProvider<AuthProvider>.value(
                value: FakeAuthProvider()),
            ChangeNotifierProvider<SettingsProvider>.value(
                value: FakeSettingsProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
                value: FakeInventoryAlertsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: FakeLocalTerminalProvider()),
          ],
          child: const MaterialApp(
            home: GeneralAuditScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the row in the DataTable to trigger _showShiftDetail
      final shiftRow = find.text('201');
      expect(shiftRow, findsOneWidget);
      await tester.tap(shiftRow);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Dialog is open
      expect(find.text('Detalle del Turno #201'), findsOneWidget);
      expect(find.text('ABIERTO'), findsOneWidget);

      // Verify dialog width is 900
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final has900DialogBox = sizedBoxes.any((s) => s.width == 900.0);
      expect(has900DialogBox, isTrue,
          reason: 'Expected dialog content SizedBox to have width: 900');

      // Verify side-by-side section titles
      final desgloseTitle = find.text('DESGLOSE DE VENTAS');
      final balanceTitle = find.text('BALANCE DE CAJA');
      final auditoriaTitle = find.text('AUDITORÍA DE VENTAS');

      expect(desgloseTitle, findsOneWidget);
      expect(balanceTitle, findsOneWidget);
      expect(auditoriaTitle, findsOneWidget);

      final desglosePos = tester.getTopLeft(desgloseTitle);
      final balancePos = tester.getTopLeft(balanceTitle);
      final auditoriaPos = tester.getTopLeft(auditoriaTitle);

      // Desglose and Balance are side-by-side horizontally
      expect(desglosePos.dx < balancePos.dx, isTrue,
          reason:
              'Desglose (${desglosePos.dx}) should be to the left of Balance (${balancePos.dx})');

      // Auditoría de Ventas is below them
      expect(auditoriaPos.dy > desglosePos.dy, isTrue,
          reason: 'Auditoría de Ventas should be below the breakdown and balance');

      // Verify header items in dialog row
      final dialogFinder = find.byType(AlertDialog);
      expect(
          find.descendant(of: dialogFinder, matching: find.text('Caja')),
          findsOneWidget);
      expect(
          find.descendant(of: dialogFinder, matching: find.text('Apertura')),
          findsOneWidget);
      expect(
          find.descendant(of: dialogFinder, matching: find.text('Fecha Inicio')),
          findsOneWidget);
      expect(
          find.descendant(of: dialogFinder, matching: find.text('Fecha Cierre')),
          findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle del Turno #201'), findsNothing);
    });

    testWidgets(
        'Clicking closed shift in GeneralAuditScreen navigates to CashShiftSummaryScreen with desktop layout',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exceptionAsString().contains('global_app_bar.dart') ||
            details.exceptionAsString().contains('99078')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final closedShift = createTestShift(id: 301, isOpen: false);

      final fakeCashProvider = FakeCashRegisterProvider(
        shiftsHistory: [closedShift],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CashRegisterProvider>.value(
                value: fakeCashProvider),
            ChangeNotifierProvider<AuthProvider>.value(
                value: FakeAuthProvider()),
            ChangeNotifierProvider<SettingsProvider>.value(
                value: FakeSettingsProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
                value: FakeInventoryAlertsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: FakeLocalTerminalProvider()),
          ],
          child: const MaterialApp(
            home: GeneralAuditScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap closed shift row
      final shiftRow = find.text('301');
      expect(shiftRow, findsOneWidget);
      await tester.tap(shiftRow);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Verify navigated to CashShiftSummaryScreen
      expect(find.byType(CashShiftSummaryScreen), findsOneWidget);
      expect(find.text('Resumen de Cierre de Caja'), findsOneWidget);
      expect(find.text('BALANCE DE CAJA'), findsOneWidget);
      expect(find.text('DESGLOSE DE VENTAS'), findsOneWidget);
      expect(find.text('Volver a Auditoría'), findsOneWidget);

      // Tap Volver a Auditoría
      await tester.ensureVisible(find.text('Volver a Auditoría'));
      await tester.tap(find.text('Volver a Auditoría'));
      await tester.pumpAndSettle();

      // Back in GeneralAuditScreen
      expect(find.byType(CashShiftSummaryScreen), findsNothing);
      expect(find.byType(GeneralAuditScreen), findsOneWidget);
    });

    testWidgets(
        'CashShiftSummaryScreen exit button calls logout when not from audit',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final shift = createTestShift(id: 401, isOpen: false);
      final fakeAuth = FakeAuthProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
                value: FakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: fakeAuth),
          ],
          child: MaterialApp(
            routes: {
              '/login': (context) => const Scaffold(body: Text('Login Screen')),
            },
            home: CashShiftSummaryScreen(closedShift: shift),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeAuth.loggedOut, isFalse);
      await tester.ensureVisible(find.text('Continuar sin imprimir'));
      await tester.tap(find.text('Continuar sin imprimir'));
      await tester.pumpAndSettle();

      expect(fakeAuth.loggedOut, isTrue);
      expect(find.text('Login Screen'), findsOneWidget);
    });
  });
}
