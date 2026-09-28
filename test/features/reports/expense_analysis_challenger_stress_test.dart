import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  Map<String, dynamic> sampleMockData({
    double totalExpenses = 150000.75,
    bool includeSupplier = true,
  }) {
    final categories = <Map<String, dynamic>>[];
    if (includeSupplier) {
      categories.add({
        'category': 'Pago a Proveedor',
        'amount': 90000.0,
        'transactions': 2,
        'percentage': 60.0,
        'movements': [
          {
            'id': 1,
            'amount': 50000.0,
            'description': 'Distribuidora Central S.A.',
            'date': '2026-09-28T04:00:00Z',
          },
          {
            'id': 2,
            'amount': 40000.0,
            'description': 'Lácteos y Bebidas Mayorista SRL',
            'date': '2026-09-28T05:00:00Z',
          },
        ],
      });
    }
    categories.add({
      'category': 'Servicios Públicos e Impuestos Comunales',
      'amount': 60000.75,
      'transactions': 1,
      'percentage': includeSupplier ? 40.0 : 100.0,
      'movements': [
        {
          'id': 3,
          'amount': 60000.75,
          'description': 'Electricidad EPEC y Agua',
          'date': '2026-09-28T06:00:00Z',
        }
      ],
    });

    return {
      'total_expenses': includeSupplier ? totalExpenses : 60000.75,
      'by_category': categories,
    };
  }

  group('Adversarial Stress Objective 1: Layout across extreme screen resolutions', () {
    final resolutions = <String, Size>{
      'Ultra-compact mobile (320x480)': const Size(320, 480),
      'Standard mobile (360x640)': const Size(360, 640),
      'Foldable / Small tablet (450x700)': const Size(450, 700),
      'Compact desktop / Stacked mode (850x700)': const Size(850, 700),
      'Wide desktop / Full mode (1400x900)': const Size(1400, 900),
    };

    for (final entry in resolutions.entries) {
      testWidgets('Renders cleanly on ${entry.key} with ZERO RenderFlex overflow',
          (WidgetTester tester) async {
        final mockHttpClient = MockClient((request) async {
          return http.Response(
            jsonEncode(sampleMockData()),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final apiClient = ApiClient(mockHttpClient);

        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FlutterErrorDetails? capturedDetails;
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          capturedDetails = details;
        };

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
        await tester.pump(const Duration(milliseconds: 150));
        FlutterError.onError = originalOnError;

        // Essential controls must be rendered
        expect(find.byKey(const Key('switch_include_suppliers')), findsOneWidget);
        expect(find.byKey(const Key('dropdown_payment_method')), findsOneWidget);
        expect(find.byKey(const Key('textfield_min_amount')), findsOneWidget);

        if (capturedDetails != null) {
          for (final d in capturedDetails!.informationCollector!()) {
            if (d.value is RenderFlex) {
              final rf = d.value as RenderFlex;
              RenderBox? child = rf.firstChild;
              while (child != null) {
                final childData = child.parentData as FlexParentData;
                debugPrint('CHILD: ${child.runtimeType}, size: ${child.hasSize ? child.size : "no size"}, flex: ${childData.flex}, fit: ${childData.fit}');
                child = childData.nextSibling;
              }
            }
          }
        }

        if (capturedDetails != null) {
          expect(capturedDetails?.exception, isNull,
              reason: 'Resolution ${entry.key} produced layout error: ${capturedDetails?.exception}');
        }
        final exception = tester.takeException();
        expect(exception, isNull,
            reason: 'Resolution ${entry.key} must produce zero layout overflows or exceptions');
      });
    }

    testWidgets('Stress test: Large currency amounts on 360x640 mobile screen',
        (WidgetTester tester) async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'total_expenses': 15000000.50,
            'by_category': [
              {
                'category': 'Distribuidora',
                'amount': 15000000.50,
                'transactions': 10,
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
      await tester.pump(const Duration(milliseconds: 150));

      final exception = tester.takeException();
      if (exception is FlutterError) {
        debugPrint('360x640 LARGE AMOUNT OVERFLOW: ${exception.toStringDeep()}');
      }
      expect(exception, isNull, reason: 'Large amounts on 360x640 must not overflow');
    });

    testWidgets('Filter bar and empty state renders on ultra-narrow 320x480 without overflow',
        (WidgetTester tester) async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'total_expenses': 0.0, 'by_category': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockHttpClient);

      tester.view.physicalSize = const Size(320, 480);
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
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('No hay gastos registrados'), findsNWidgets(2));
      expect(find.byKey(const Key('switch_include_suppliers')), findsOneWidget);
      expect(find.byKey(const Key('dropdown_payment_method')), findsOneWidget);
      expect(find.byKey(const Key('textfield_min_amount')), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'Filter bar and empty state on 320x480 must not overflow');
    });

    testWidgets('Renders extreme numeric values on 320x480 without overflow',
        (WidgetTester tester) async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'total_expenses': 987654321098.75,
            'by_category': [
              {
                'category': 'Gasto con Nombre Excesivamente Largo para Provocar Truncamiento y Overflow',
                'amount': 987654321098.75,
                'transactions': 9999,
                'percentage': 100.0,
                'movements': [
                  {
                    'id': 999,
                    'amount': 987654321098.75,
                    'description': 'Descripción kilométrica para estresar el ListView en 320x480',
                    'date': '2026-09-28T09:00:00Z',
                  }
                ],
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockHttpClient);

      tester.view.physicalSize = const Size(320, 480);
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
      await tester.pump(const Duration(milliseconds: 150));

      expect(tester.takeException(), isNull,
          reason: 'Extreme numbers and long strings on 320x480 must not cause overflow');
    });
  });

  group('Adversarial Stress Objective 2: Rapid text entry and debounce cancellation', () {
    testWidgets('Cancels in-flight debounce on rapid successive keystrokes',
        (WidgetTester tester) async {
      final recordedRequests = <http.Request>[];

      final mockHttpClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response(
          jsonEncode({'total_expenses': 1000.0, 'by_category': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockHttpClient);

      tester.view.physicalSize = const Size(1000, 800);
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

      // Initial request fired on initState
      expect(recordedRequests.length, 1);

      final minAmountField = find.byKey(const Key('textfield_min_amount'));

      // Simulate rapid typing: 1 -> 15 -> 150 -> 1500 with 100ms intervals
      await tester.enterText(minAmountField, '1');
      await tester.pump(const Duration(milliseconds: 100));
      expect(recordedRequests.length, 1, reason: 'Debounce should not fire at 100ms');

      await tester.enterText(minAmountField, '15');
      await tester.pump(const Duration(milliseconds: 100));
      expect(recordedRequests.length, 1, reason: 'Debounce should not fire at 200ms');

      await tester.enterText(minAmountField, '150');
      await tester.pump(const Duration(milliseconds: 100));
      expect(recordedRequests.length, 1, reason: 'Debounce should not fire at 300ms');

      await tester.enterText(minAmountField, '1500');
      await tester.pump(const Duration(milliseconds: 100));
      expect(recordedRequests.length, 1, reason: 'Debounce should not fire at 400ms');

      // Now wait for debounce to elapse (500ms from the last keystroke)
      // At 300ms after last keystroke:
      await tester.pump(const Duration(milliseconds: 300));
      expect(recordedRequests.length, 1, reason: 'Debounce 500ms not yet elapsed since last keystroke');

      // Another 250ms (total 550ms after last keystroke)
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 50));

      // Exactly ONE new request should have been dispatched with the final value
      expect(recordedRequests.length, 2, reason: 'Only the final debounced keystroke triggers a request');
      expect(recordedRequests.last.url.queryParameters['min_amount'], '1500');
    });

    testWidgets('onSubmitted cancels pending debounce timer and prevents duplicate dispatch',
        (WidgetTester tester) async {
      final recordedRequests = <http.Request>[];

      final mockHttpClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response(
          jsonEncode({'total_expenses': 5000.0, 'by_category': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockHttpClient);

      tester.view.physicalSize = const Size(1000, 800);
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
      expect(recordedRequests.length, 1); // initial

      final minAmountField = find.byKey(const Key('textfield_min_amount'));

      // Enter text
      await tester.enterText(minAmountField, '7500');
      await tester.pump(const Duration(milliseconds: 100));
      expect(recordedRequests.length, 1);

      // Hit submit (Enter/Done) immediately at 100ms
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Request dispatched immediately
      expect(recordedRequests.length, 2);
      expect(recordedRequests.last.url.queryParameters['min_amount'], '7500');

      // Now advance clock past 500ms debounce interval to verify NO duplicate request fires
      await tester.pump(const Duration(milliseconds: 600));
      expect(recordedRequests.length, 2, reason: 'Debounce timer must have been cancelled by onSubmitted');
    });

    testWidgets('Clear button cancels pending debounce timer and fetches immediately',
        (WidgetTester tester) async {
      final recordedRequests = <http.Request>[];

      final mockHttpClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response(
          jsonEncode({'total_expenses': 0.0, 'by_category': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockHttpClient);

      tester.view.physicalSize = const Size(1000, 800);
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
      expect(recordedRequests.length, 1);

      final minAmountField = find.byKey(const Key('textfield_min_amount'));
      await tester.enterText(minAmountField, '4200');
      await tester.pump(const Duration(milliseconds: 150));
      expect(recordedRequests.length, 1);

      // Tap clear button before debounce fires
      final clearButton = find.byKey(const Key('button_clear_min_amount'));
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Cleared request dispatched immediately without min_amount
      expect(recordedRequests.length, 2);
      expect(recordedRequests.last.url.queryParameters.containsKey('min_amount'), isFalse);

      // Advance clock past 500ms to confirm no delayed request fires
      await tester.pump(const Duration(milliseconds: 600));
      expect(recordedRequests.length, 2, reason: 'Pending debounce timer must be cancelled by clear button');
    });
  });

  group('Adversarial Stress Objective 3: Numeric text input filtering', () {
    testWidgets('Rejects alphabetic and symbol characters during input, allowing only valid numbers',
        (WidgetTester tester) async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'total_expenses': 0.0, 'by_category': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockHttpClient);

      tester.view.physicalSize = const Size(1000, 800);
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

      final minAmountFinder = find.byKey(const Key('textfield_min_amount'));
      final textField = tester.widget<TextField>(minAmountFinder);

      expect(textField.inputFormatters, isNotNull);
      expect(textField.inputFormatters!.isNotEmpty, isTrue);

      final formatter = textField.inputFormatters!.first;

      // 1. Rejects pure non-numeric text
      final lettersOnly = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'abcDEF'),
      );
      expect(lettersOnly.text, '', reason: 'Letters must be completely rejected');

      // 2. Rejects symbols
      final symbolsOnly = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '@#\$%^&*()'),
      );
      expect(symbolsOnly.text, '', reason: 'Symbols must be completely rejected');

      // 3. Allows valid decimal number
      final decimalNumber = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '1250.75'),
      );
      expect(decimalNumber.text, '1250.75', reason: 'Valid decimal number must be preserved');

      // 4. Interactive keystroke test in TextField:
      // Try typing non-numeric 'xyz'
      await tester.enterText(minAmountFinder, 'xyz');
      await tester.pump();
      expect(textField.controller?.text, '', reason: 'Non-numeric input must not appear in text field');

      // Enter valid numbers '2500'
      await tester.enterText(minAmountFinder, '2500');
      await tester.pump();
      expect(textField.controller?.text, '2500', reason: 'Numeric input must be accepted');

      // Enter numbers with decimals '2500.50'
      await tester.enterText(minAmountFinder, '2500.50');
      await tester.pump();
      expect(textField.controller?.text, '2500.50', reason: 'Valid decimal input must be accepted');
    });
  });

  group('Adversarial Stress Objective 4: Export URL query parameter generation', () {
    testWidgets('Generates accurate export URLs when all filters are active vs cleared',
        (WidgetTester tester) async {
      final capturedExportUrls = <Uri>[];

      final mockHttpClient = MockClient((request) async {
        if (request.url.path.contains('/export') || request.url.path.contains('/pdf')) {
          capturedExportUrls.add(request.url);
          return http.Response('Mock export binary payload', 400); // 400 avoids disk writes
        }
        return http.Response(
          jsonEncode({'total_expenses': 25000.0, 'by_category': []}),
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

      // State 1: Default/Cleared filters
      // Trigger Excel export with default state
      await tester.tap(find.text('Exportar Excel'));
      await tester.pumpAndSettle();

      expect(capturedExportUrls.length, 1);
      final defaultExcelUri = capturedExportUrls.first;
      expect(defaultExcelUri.queryParameters['include_suppliers'], 'true');
      expect(defaultExcelUri.queryParameters.containsKey('payment_method'), isFalse);
      expect(defaultExcelUri.queryParameters.containsKey('min_amount'), isFalse);

      // Trigger PDF export with default state
      await tester.tap(find.text('Generar PDF'));
      await tester.pumpAndSettle();

      expect(capturedExportUrls.length, 2);
      final defaultPdfUri = capturedExportUrls.last;
      expect(defaultPdfUri.queryParameters['include_suppliers'], 'true');
      expect(defaultPdfUri.queryParameters.containsKey('payment_method'), isFalse);
      expect(defaultPdfUri.queryParameters.containsKey('min_amount'), isFalse);

      // State 2: Active filters
      // 1. Exclude suppliers
      await tester.tap(find.byKey(const Key('switch_include_suppliers')));
      await tester.pumpAndSettle();

      // 2. Select Cheque ('check')
      await tester.tap(find.byKey(const Key('dropdown_payment_method')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();

      // 3. Enter min_amount '4500.50'
      await tester.enterText(find.byKey(const Key('textfield_min_amount')), '4500.50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Trigger Excel with active filters
      await tester.tap(find.text('Exportar Excel'));
      await tester.pumpAndSettle();

      expect(capturedExportUrls.length, 3);
      final activeExcelUri = capturedExportUrls.last;
      expect(activeExcelUri.queryParameters['include_suppliers'], 'false');
      expect(activeExcelUri.queryParameters['payment_method'], 'check');
      expect(activeExcelUri.queryParameters['min_amount'], '4500.50');

      // Trigger PDF with active filters
      await tester.tap(find.text('Generar PDF'));
      await tester.pumpAndSettle();

      expect(capturedExportUrls.length, 4);
      final activePdfUri = capturedExportUrls.last;
      expect(activePdfUri.queryParameters['include_suppliers'], 'false');
      expect(activePdfUri.queryParameters['payment_method'], 'check');
      expect(activePdfUri.queryParameters['min_amount'], '4500.50');

      // State 3: Reset / Cleared again
      // 1. Re-enable suppliers
      await tester.tap(find.byKey(const Key('switch_include_suppliers')));
      await tester.pumpAndSettle();

      // 2. Reset payment method to Todos (null)
      await tester.tap(find.byKey(const Key('dropdown_payment_method')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos').last);
      await tester.pumpAndSettle();

      // 3. Clear min_amount via clear button
      await tester.tap(find.byKey(const Key('button_clear_min_amount')));
      await tester.pumpAndSettle();

      // Trigger Excel export after clearing
      await tester.tap(find.text('Exportar Excel'));
      await tester.pumpAndSettle();

      expect(capturedExportUrls.length, 5);
      final clearedExcelUri = capturedExportUrls.last;
      expect(clearedExcelUri.queryParameters['include_suppliers'], 'true');
      expect(clearedExcelUri.queryParameters.containsKey('payment_method'), isFalse);
      expect(clearedExcelUri.queryParameters.containsKey('min_amount'), isFalse);
    });
  });
}
