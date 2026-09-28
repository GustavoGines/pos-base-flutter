import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/pages/cash_shift_summary_screen.dart';
import 'package:frontend_desktop/features/reports/presentation/pages/general_audit_screen.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/auth/domain/repositories/auth_repository.dart';
import 'package:frontend_desktop/features/auth/data/datasources/auth_remote_datasource.dart';

class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final bool _isPremium;
  final bool _hasChecks;

  MockSettingsProvider({bool isPremium = true, bool hasChecks = true})
      : _isPremium = isPremium,
        _hasChecks = hasChecks;

  @override
  String get currentPlan => _isPremium ? 'premium' : 'basic';

  @override
  BusinessSettings get settings => BusinessSettings(
        companyName: 'Empresa Test',
        taxId: '30-11223344-5',
        features: FeatureFlags(checks: _hasChecks),
      );

  @override
  FeatureFlags get features => FeatureFlags(checks: _hasChecks);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockInventoryAlertsProvider extends ChangeNotifier
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

class MockLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  final ApiClient? _apiClient;
  final AuthRepository _repo;

  MockAuthProvider({http.Client? client})
      : _apiClient = client != null ? ApiClient(client) : null,
        _repo = AuthRepository(
          remoteDataSource: AuthRemoteDataSource(
            baseUrl: 'http://localhost:8000/api',
            client: client ?? http.Client(),
          ),
        );

  @override
  ApiClient? get apiClient => _apiClient;

  @override
  AuthRepository get repository => _repo;

  @override
  Map<String, dynamic>? get currentUser =>
      {'id': 1, 'name': 'Admin User', 'role': 'admin'};

  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCashRegisterProvider extends ChangeNotifier
    implements CashRegisterProvider {
  final List<CashRegisterShift> _shiftsHistory;

  MockCashRegisterProvider({List<CashRegisterShift>? shiftsHistory})
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
  CashRegisterShift makeShift({
    required int id,
    required bool isOpen,
    int checkCount = 0,
    List<Map<String, dynamic>>? checkDetails,
  }) {
    return CashRegisterShift(
      id: id,
      cashRegisterId: 1,
      userId: 1,
      cashRegisterName: 'Caja Principal',
      userName: 'Juan Perez',
      closedByUserName: isOpen ? null : 'Maria Lopez',
      openingBalance: 10000.0,
      status: isOpen ? 'open' : 'closed',
      openedAt: DateTime(2026, 9, 28, 8, 0),
      closedAt: isOpen ? null : DateTime(2026, 9, 28, 16, 0),
      cashSales: 50000.0,
      cardSales: 20000.0,
      transferSales: 10000.0,
      checkSales: 5000.0,
      totalSales: 85000.0,
      totalSurcharge: 1200.0,
      totalDeposits: 2000.0,
      totalExpenses: 1500.0,
      totalWithdrawals: 1000.0,
      totalSupplierPayments: 3000.0,
      totalRefunds: 500.0,
      expectedBalance: 56000.0,
      actualBalance: 56000.0,
      difference: 0.0,
      ccSalesCount: 3,
      ccSales: 15000.0,
      checkCount: checkCount,
      checkDetails: checkDetails,
    );
  }

  group('Review Round 2 Adversarial Stress Tests', () {
    testWidgets(
        'Attack 1: Stock Movements tab header overflow on 600x800 viewport',
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

      final client = MockClient((request) async {
        if (request.url.path.contains('/audit/stock')) {
          return http.Response(
            json.encode({
              'data': [
                {
                  'type': 'in',
                  'created_at': '2026-09-28T12:00:00Z',
                  'user': {'name': 'Admin'},
                  'product': {'name': 'Producto Prueba', 'is_sold_by_weight': false},
                  'quantity': 10,
                  'notes': 'Ingreso test',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CashRegisterProvider>.value(
                value: MockCashRegisterProvider(shiftsHistory: [makeShift(id: 1, isOpen: true)])),
            ChangeNotifierProvider<AuthProvider>.value(
                value: MockAuthProvider(client: client)),
            ChangeNotifierProvider<SettingsProvider>.value(
                value: MockSettingsProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
                value: MockInventoryAlertsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: MockLocalTerminalProvider()),
          ],
          child: const MaterialApp(
            home: GeneralAuditScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Tab 2: Movimientos de Stock
      await tester.tap(find.text('Movimientos de Stock'));
      await tester.pumpAndSettle();

      expect(caughtError, isNull,
          reason: 'RenderFlex overflow in Stock Movements tab header: ${caughtError?.exceptionAsString()}');
    });

    testWidgets(
        'Attack 2: CashShiftSummaryScreen with 1.25x Windows Font Scale',
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

      final shift = makeShift(
        id: 2,
        isOpen: false,
        checkCount: 15,
        checkDetails: List.generate(
          15,
          (i) => {
            'bank_name': 'Banco Santander Sucursal Centro $i',
            'check_number': '1234567$i',
            'amount': 150000.0 * (i + 1),
            'payment_date': '2026-10-20',
          },
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
                value: MockSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: MockLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(
                value: MockAuthProvider()),
          ],
          child: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.25),
              size: Size(1280, 800),
            ),
            child: MaterialApp(
              home: CashShiftSummaryScreen(closedShift: shift),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(caughtError, isNull,
          reason: 'Error with textScaler 1.25: ${caughtError?.exceptionAsString()}');

      // Verify print button visibility on standard desktop height
      final printBtn = find.text('Imprimir Cierre Z y Salir');
      expect(printBtn, findsOneWidget);
      final printBtnRect = tester.getRect(printBtn);
      expect(printBtnRect.bottom <= 800, isTrue,
          reason: 'Print button bottom is ${printBtnRect.bottom}, should be <= 800');
    });

    testWidgets(
        'Attack 3: GeneralAuditScreen dialog with API sales returning data Map format and null dates',
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
        if (details.exceptionAsString().contains('global_app_bar.dart') ||
            details.exceptionAsString().contains('99078')) {
          return;
        }
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      // Backend returns Laravel standard resource format: {"data": [...]}
      final client = MockClient((request) async {
        if (request.url.path.contains('/sales')) {
          return http.Response(
            json.encode({
              'data': [
                {
                  'id': 1001,
                  'total': '15500.50',
                  'total_surcharge': '500.00',
                  'price_list': 'Mayorista Especial',
                  'status': 'completed',
                  'created_at': '2026-09-28T10:15:00Z',
                },
                {
                  'id': 1002,
                  'total': '8200.00',
                  'total_surcharge': null,
                  'price_list': null,
                  'status': 'voided',
                  'created_at': null, // edge case: null created_at
                },
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200);
      });

      final openShift = makeShift(id: 10, isOpen: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CashRegisterProvider>.value(
                value: MockCashRegisterProvider(shiftsHistory: [openShift])),
            ChangeNotifierProvider<AuthProvider>.value(
                value: MockAuthProvider(client: client)),
            ChangeNotifierProvider<SettingsProvider>.value(
                value: MockSettingsProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
                value: MockInventoryAlertsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: MockLocalTerminalProvider()),
          ],
          child: const MaterialApp(
            home: GeneralAuditScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open shift detail dialog
      final shiftRow = find.text('10');
      expect(shiftRow, findsOneWidget);
      await tester.tap(shiftRow);
      await tester.pumpAndSettle();

      expect(caughtError, isNull,
          reason: 'Error opening shift detail dialog with sales: ${caughtError?.exceptionAsString()}');

      // Verify sales appear in the dialog
      expect(find.text('Venta #1001'), findsOneWidget);
      expect(find.text('Venta #1002'), findsOneWidget);
    });

    testWidgets(
        'Attack 4: CashShiftSummaryScreen on 1024x768 (standard touch POS monitor)',
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
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final shift = makeShift(
        id: 4,
        isOpen: false,
        checkCount: 5,
        checkDetails: List.generate(
          5,
          (i) => {
            'bank_name': 'Banco Nacion $i',
            'check_number': '9988$i',
            'amount': 25000.0,
            'payment_date': '2026-10-15',
          },
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
                value: MockSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: MockLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(
                value: MockAuthProvider()),
          ],
          child: MaterialApp(
            home: CashShiftSummaryScreen(closedShift: shift),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(caughtError, isNull);

      final printBtn = find.text('Imprimir Cierre Z y Salir');
      expect(printBtn, findsOneWidget);
      final printBtnRect = tester.getRect(printBtn);
      // On 1024x768, print button should be visible directly in viewport without scrolling!
      expect(printBtnRect.bottom <= 768, isTrue,
          reason:
              'Print button is pushed below 768px viewport (bottom: ${printBtnRect.bottom}) on standard 1024x768 POS monitor');
    });

    testWidgets(
        'Attack 5: Extreme null/zero shift in CashShiftSummaryScreen',
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

      // Bare minimal shift: all optional fields null
      final bareShift = CashRegisterShift(
        id: 777,
        cashRegisterId: 1,
        userId: 1,
        openingBalance: 0.0,
        status: 'closed',
        openedAt: DateTime(2026, 9, 28, 8, 0),
        closedAt: DateTime(2026, 9, 28, 16, 0),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
                value: MockSettingsProvider(isPremium: false, hasChecks: false)),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: MockLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(
                value: MockAuthProvider()),
          ],
          child: MaterialApp(
            home: CashShiftSummaryScreen(closedShift: bareShift),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(caughtError, isNull,
          reason: 'Error rendering bare minimal shift: ${caughtError?.exceptionAsString()}');
      expect(find.text('SOBRANTE:'), findsOneWidget);
      expect(find.text('Imprimir Cierre Z y Salir'), findsOneWidget);
    });

    testWidgets(
        'Attack 6: Rapid open and close of GeneralAuditScreen shift detail dialog',
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
        if (details.exceptionAsString().contains('global_app_bar.dart') ||
            details.exceptionAsString().contains('99078')) {
          return;
        }
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final openShift = makeShift(id: 888, isOpen: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CashRegisterProvider>.value(
                value: MockCashRegisterProvider(shiftsHistory: [openShift])),
            ChangeNotifierProvider<AuthProvider>.value(
                value: MockAuthProvider()),
            ChangeNotifierProvider<SettingsProvider>.value(
                value: MockSettingsProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
                value: MockInventoryAlertsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: MockLocalTerminalProvider()),
          ],
          child: const MaterialApp(
            home: GeneralAuditScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Cycle 1: Open and Close
      await tester.tap(find.text('888'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle del Turno #888'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle del Turno #888'), findsNothing);

      // Cycle 2: Open and Close again
      await tester.tap(find.text('888'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle del Turno #888'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle del Turno #888'), findsNothing);

      expect(caughtError, isNull,
          reason: 'Error in rapid open-close cycles: ${caughtError?.exceptionAsString()}');
    });

    testWidgets(
        'Attack 7: GeneralAuditScreen dialog with large font scale (1.3x) without overflow',
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
        if (details.exceptionAsString().contains('global_app_bar.dart') ||
            details.exceptionAsString().contains('99078')) {
          return;
        }
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final openShift = makeShift(
        id: 999,
        isOpen: true,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CashRegisterProvider>.value(
                value: MockCashRegisterProvider(shiftsHistory: [openShift])),
            ChangeNotifierProvider<AuthProvider>.value(
                value: MockAuthProvider()),
            ChangeNotifierProvider<SettingsProvider>.value(
                value: MockSettingsProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
                value: MockInventoryAlertsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(
                value: MockLocalTerminalProvider()),
          ],
          child: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.3),
              size: Size(1280, 800),
            ),
            child: const MaterialApp(
              home: GeneralAuditScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('999'));
      await tester.pumpAndSettle();

      expect(caughtError, isNull,
          reason: 'RenderFlex overflow in dialog with 1.3x font scale: ${caughtError?.exceptionAsString()}');
      expect(find.text('Detalle del Turno #999'), findsOneWidget);
    });
  });
}
