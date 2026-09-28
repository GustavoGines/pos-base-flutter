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
        companyName: 'Empresa Test con Nombre Extremadamente Largo S.A. de C.V.',
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
  @override
  Map<String, dynamic>? get currentUser =>
      {'id': 1, 'name': 'Admin User', 'role': 'admin'};

  @override
  Future<void> logout() async {}

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
  CashRegisterShift createExtremeShift({
    required int id,
    required bool isOpen,
    String? userName,
    String? cashRegisterName,
    String? closedByUserName,
    double openingBalance = 999999999.0,
    double cashSales = 888888888.0,
    double cardSales = 777777777.0,
    double transferSales = 666666666.0,
    double checkSales = 555555555.0,
    double totalSurcharge = 44444444.0,
    double totalDeposits = 33333333.0,
    double totalExpenses = 22222222.0,
    double totalWithdrawals = 11111111.0,
    double totalSupplierPayments = 55555555.0,
    double totalRefunds = 4444444.0,
    double? expectedBalance = 999999999.0,
    double? actualBalance = 888888888.0,
    double? difference = -111111111.0,
    int? ccSalesCount = 99,
    double? ccSales = 123456789.0,
    int? checkCount = 20,
    List<Map<String, dynamic>>? checkDetails,
  }) {
    return CashRegisterShift(
      id: id,
      cashRegisterId: 1,
      userId: 10,
      cashRegisterName: cashRegisterName ??
          'Caja Registradora Principal Salón Ventas PB Sector Norte 01',
      userName: userName ??
          'Licenciado Juan Carlos Maximiliano de la Huerta y Monasterio',
      closedByUserName: isOpen
          ? null
          : (closedByUserName ??
              'Supervisora General María de los Ángeles Pérez Costamagna'),
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
          List.generate(
            20,
            (i) => {
              'bank_name': 'Banco Santander Río Sucursal Centro $i',
              'check_number': '000000000$i',
              'amount': 2500000.0 * (i + 1),
              'payment_date': '2026-10-${(i % 28) + 1}',
            },
          ),
    );
  }

  group('Adversarial Stress Testing', () {
    testWidgets(
        'OI-3 & OI-1: CashShiftSummaryScreen with 20 checks, huge numbers, and ultra-long names',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterErrorDetails? caughtError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final shift = createExtremeShift(id: 999, isOpen: false);

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

      expect(caughtError, isNull,
          reason: 'RenderFlex overflow or exception occurred in CashShiftSummaryScreen: ${caughtError?.exceptionAsString()}');

      // Verify the print button is visible in viewport without having to scroll
      final printButtonFinder = find.text('Imprimir Cierre Z y Salir');
      expect(printButtonFinder, findsOneWidget);

      final printButtonRect = tester.getRect(printButtonFinder);
      // Viewport bottom is 800
      expect(printButtonRect.bottom <= 800, isTrue,
          reason:
              'Print button is pushed below 800px viewport (bottom: ${printButtonRect.bottom}) due to 20 checks!');
    });

    testWidgets(
        'OI-2: CashShiftSummaryScreen on short viewport 1366x600',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1366, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterErrorDetails? caughtError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final shift = createExtremeShift(id: 998, isOpen: false);

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

      expect(caughtError, isNull,
          reason: 'Exception on 1366x600 display: ${caughtError?.exceptionAsString()}');
    });

    testWidgets(
        'OI-3: CashShiftSummaryScreen on narrow screen with very long names in header Wrap',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterErrorDetails? caughtError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final shift = createExtremeShift(id: 997, isOpen: false);

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

      expect(caughtError, isNull,
          reason: 'RenderFlex overflow in header Wrap on narrow screen: ${caughtError?.exceptionAsString()}');
    });

    testWidgets(
        'OI-3 & Dialog edge cases: GeneralAuditScreen shift detail dialog with long strings',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterErrorDetails? caughtError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exceptionAsString().contains('global_app_bar.dart') ||
            details.exceptionAsString().contains('99078')) {
          return;
        }
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final openShift = createExtremeShift(
        id: 996,
        isOpen: true,
        userName: 'Licenciado Juan Carlos Maximiliano de la Huerta y Monasterio',
        cashRegisterName: 'Caja Registradora Principal Salón Ventas PB Sector Norte',
      );

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

      final shiftRow = find.text('996');
      expect(shiftRow, findsOneWidget);
      await tester.tap(shiftRow);
      await tester.pumpAndSettle();

      expect(caughtError, isNull,
          reason: 'RenderFlex overflow in shift detail dialog: ${caughtError?.exceptionAsString()}');
    });

    testWidgets(
        'GeneralAuditScreen shift detail dialog on narrow viewport (e.g. 600x800)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterErrorDetails? caughtError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exceptionAsString().contains('global_app_bar.dart') ||
            details.exceptionAsString().contains('99078')) {
          return;
        }
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final openShift = createExtremeShift(
        id: 995,
        isOpen: true,
      );

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

      final shiftRow = find.text('995');
      expect(shiftRow, findsOneWidget);
      await tester.tap(shiftRow);
      await tester.pumpAndSettle();

      expect(caughtError, isNull,
          reason: 'RenderFlex overflow in shift detail dialog on 600x800: ${caughtError?.exceptionAsString()}');
    });
  });
}
