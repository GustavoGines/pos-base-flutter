import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/expense_analysis_tab.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_api': 'http://localhost/api',
    });
  });

  testWidgets('ExpenseAnalysisTab renders without assertion crash or overflow on narrow screen (< 950px)',
      (WidgetTester tester) async {
    final mockHttpClient = MockClient((request) async {
      if (request.url.path.contains('expenses-analysis')) {
        return http.Response(
          jsonEncode({
            'total_expenses': 125000.50,
            'by_category': [
              {
                'category': 'Pago a Proveedor',
                'amount': 100000.00,
                'transactions': 3,
                'percentage': 80.0,
                'movements': [
                  {
                    'id': 1,
                    'amount': 100000.00,
                    'description': 'Pago a Distribuidora',
                    'date': '2026-09-28T01:00:00Z',
                  }
                ],
              },
              {
                'category': 'Servicios',
                'amount': 25000.50,
                'transactions': 1,
                'percentage': 20.0,
                'movements': [
                  {
                    'id': 2,
                    'amount': 25000.50,
                    'description': 'Luz y Gas',
                    'date': '2026-09-28T02:00:00Z',
                  }
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not found', 404);
    });

    final apiClient = ApiClient(mockHttpClient);

    // Set screen size to 850x700 (which triggers isStacked = maxWidth < 950)
    tester.view.physicalSize = const Size(850, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: apiClient),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ExpenseAnalysisTab(),
          ),
        ),
      ),
    );

    // Wait for the async _fetchData() to complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify widgets rendered properly
    expect(find.text('Distribución de Gastos'), findsOneWidget);
    expect(find.text('GASTO TOTAL DEL PERÍODO'), findsOneWidget);
    expect(find.text('Desglose por Categoría'), findsOneWidget);
    expect(find.text('Pago a Proveedor'), findsOneWidget);
    expect(find.text('Servicios'), findsOneWidget);

    // Verify filter bar controls rendered on 850x700
    expect(find.text('Incluir Pagos a Proveedores'), findsOneWidget);
    expect(find.byKey(const Key('switch_include_suppliers')), findsOneWidget);
    expect(find.byKey(const Key('dropdown_payment_method')), findsOneWidget);
    expect(find.text('Monto Mínimo'), findsOneWidget);
    expect(find.byKey(const Key('textfield_min_amount')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Narrow screen (<950px) must not overflow');
  });

  testWidgets('ExpenseAnalysisTab renders without assertion crash or overflow on wide screen (>= 950px)',
      (WidgetTester tester) async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'total_expenses': 50000.0,
          'by_category': [
            {
              'category': 'Alquiler',
              'amount': 50000.0,
              'transactions': 1,
              'percentage': 100.0,
              'movements': [],
            }
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiClient = ApiClient(mockHttpClient);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: apiClient),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ExpenseAnalysisTab(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Distribución de Gastos'), findsOneWidget);
    expect(find.text('Alquiler'), findsOneWidget);

    // Verify filter bar controls rendered on 1400x900
    expect(find.text('Incluir Pagos a Proveedores'), findsOneWidget);
    expect(find.byKey(const Key('switch_include_suppliers')), findsOneWidget);
    expect(find.byKey(const Key('dropdown_payment_method')), findsOneWidget);
    expect(find.text('Monto Mínimo'), findsOneWidget);
    expect(find.byKey(const Key('textfield_min_amount')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Wide desktop screen must not overflow');
  });

  testWidgets('ExpenseAnalysisTab renders without crash or overflow on compact screen (450x700)',
      (WidgetTester tester) async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'total_expenses': 50000.0,
          'by_category': [
            {
              'category': 'Alquiler',
              'amount': 50000.0,
              'transactions': 1,
              'percentage': 100.0,
              'movements': [],
            }
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiClient = ApiClient(mockHttpClient);

    tester.view.physicalSize = const Size(450, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: apiClient),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ExpenseAnalysisTab(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Distribución de Gastos'), findsOneWidget);
    expect(find.text('Alquiler'), findsOneWidget);

    // Verify filter bar controls rendered on 450x700
    expect(find.text('Incluir Pagos a Proveedores'), findsOneWidget);
    expect(find.byKey(const Key('switch_include_suppliers')), findsOneWidget);
    expect(find.byKey(const Key('dropdown_payment_method')), findsOneWidget);
    expect(find.text('Monto Mínimo'), findsOneWidget);
    expect(find.byKey(const Key('textfield_min_amount')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Compact screen should not throw or overflow');
  });

  testWidgets('ExpenseAnalysisTab renders cleanly on ultra-compact mobile screen (360x640) with adapted radii',
      (WidgetTester tester) async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'total_expenses': 85000.0,
          'by_category': [
            {
              'category': 'Distribuidora Mayorista de Mercadería Extra Larga',
              'amount': 60000.0,
              'transactions': 4,
              'percentage': 70.6,
              'movements': [
                {
                  'id': 10,
                  'amount': 60000.0,
                  'description': 'Mercadería quincenal con detalle largo',
                  'date': '2026-09-28T03:00:00Z',
                }
              ],
            },
            {
              'category': 'Mantenimiento y Reparaciones',
              'amount': 25000.0,
              'transactions': 1,
              'percentage': 29.4,
              'movements': [],
            }
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiClient = ApiClient(mockHttpClient);

    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: apiClient),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ExpenseAnalysisTab(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Distribución de Gastos'), findsOneWidget);
    expect(find.text('GASTO TOTAL DEL PERÍODO'), findsOneWidget);
    expect(find.text('Distribuidora Mayorista de Mercadería Extra Larga'), findsOneWidget);

    // Verify filter bar controls rendered on 360x640
    expect(find.text('Incluir Pagos a Proveedores'), findsOneWidget);
    expect(find.byKey(const Key('switch_include_suppliers')), findsOneWidget);
    expect(find.byKey(const Key('dropdown_payment_method')), findsOneWidget);
    expect(find.text('Monto Mínimo'), findsOneWidget);
    expect(find.byKey(const Key('textfield_min_amount')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Ultra-compact screen 360x640 should render without overflow');
  });

  testWidgets('Filter bar user interactions trigger fetchData with accurate query params',
      (WidgetTester tester) async {
    final recordedRequests = <http.Request>[];

    final mockHttpClient = MockClient((request) async {
      recordedRequests.add(request);
      return http.Response(
        jsonEncode({
          'total_expenses': 50000.0,
          'by_category': [],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiClient = ApiClient(mockHttpClient);

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: apiClient),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ExpenseAnalysisTab(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Initial request verification
    expect(recordedRequests.length, 1);
    final initialUrl = recordedRequests.first.url;
    expect(initialUrl.queryParameters['include_suppliers'], 'true');
    expect(initialUrl.queryParameters.containsKey('payment_method'), isFalse);
    expect(initialUrl.queryParameters.containsKey('min_amount'), isFalse);

    // 2. Toggle switch to exclude suppliers
    await tester.tap(find.byKey(const Key('switch_include_suppliers')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(recordedRequests.length, 2);
    final toggleUrl = recordedRequests.last.url;
    expect(toggleUrl.queryParameters['include_suppliers'], 'false');

    // 3. Select payment method "Efectivo" ('cash')
    await tester.tap(find.byKey(const Key('dropdown_payment_method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Efectivo').last);
    await tester.pumpAndSettle();

    expect(recordedRequests.length, 3);
    final paymentUrl = recordedRequests.last.url;
    expect(paymentUrl.queryParameters['include_suppliers'], 'false');
    expect(paymentUrl.queryParameters['payment_method'], 'cash');

    // 4. Enter min amount "1500" with debounce
    await tester.enterText(find.byKey(const Key('textfield_min_amount')), '1500');
    await tester.pump();
    // Before debounce expiration (e.g. 200ms), no new request is dispatched
    await tester.pump(const Duration(milliseconds: 200));
    expect(recordedRequests.length, 3);

    // After debounce expires (another 350ms -> 550ms total)
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 100));
    expect(recordedRequests.length, 4);
    final minAmountUrl = recordedRequests.last.url;
    expect(minAmountUrl.queryParameters['include_suppliers'], 'false');
    expect(minAmountUrl.queryParameters['payment_method'], 'cash');
    expect(minAmountUrl.queryParameters['min_amount'], '1500');

    // 5. Clear min amount using clear button
    expect(find.byKey(const Key('button_clear_min_amount')), findsOneWidget);
    await tester.tap(find.byKey(const Key('button_clear_min_amount')));
    await tester.pumpAndSettle();

    expect(recordedRequests.length, 5);
    final clearedUrl = recordedRequests.last.url;
    expect(clearedUrl.queryParameters.containsKey('min_amount'), isFalse);
    expect(clearedUrl.queryParameters['payment_method'], 'cash');

    // 6. Enter min amount and submit immediately (onSubmitted)
    await tester.enterText(find.byKey(const Key('textfield_min_amount')), '2500');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(recordedRequests.length, 6);
    final submittedUrl = recordedRequests.last.url;
    expect(submittedUrl.queryParameters['min_amount'], '2500');
  });

  testWidgets('Export actions forward all active filters in query parameters',
      (WidgetTester tester) async {
    final recordedExportRequests = <http.Request>[];

    final mockHttpClient = MockClient((request) async {
      if (request.url.path.contains('/export') || request.url.path.contains('/pdf')) {
        recordedExportRequests.add(request);
        return http.Response('Mock export binary', 400); // 400 stops file I/O while capturing URL
      }
      return http.Response(
        jsonEncode({
          'total_expenses': 75000.0,
          'by_category': [],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiClient = ApiClient(mockHttpClient);

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: apiClient),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ExpenseAnalysisTab(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Toggle switch off
    await tester.tap(find.byKey(const Key('switch_include_suppliers')));
    await tester.pumpAndSettle();

    // Select Transferencia ('transfer')
    await tester.tap(find.byKey(const Key('dropdown_payment_method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transferencia').last);
    await tester.pumpAndSettle();

    // Enter min amount 3000
    await tester.enterText(find.byKey(const Key('textfield_min_amount')), '3000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Trigger Excel export
    await tester.tap(find.text('Exportar Excel'));
    await tester.pumpAndSettle();

    expect(recordedExportRequests.length, 1);
    final excelUrl = recordedExportRequests.first.url;
    expect(excelUrl.path, contains('/reports/expenses-analysis/export'));
    expect(excelUrl.queryParameters['include_suppliers'], 'false');
    expect(excelUrl.queryParameters['payment_method'], 'transfer');
    expect(excelUrl.queryParameters['min_amount'], '3000');

    // Trigger PDF export
    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    expect(recordedExportRequests.length, 2);
    final pdfUrl = recordedExportRequests.last.url;
    expect(pdfUrl.path, contains('/reports/expenses-analysis/pdf'));
    expect(pdfUrl.queryParameters['include_suppliers'], 'false');
    expect(pdfUrl.queryParameters['payment_method'], 'transfer');
    expect(pdfUrl.queryParameters['min_amount'], '3000');
  });
}

