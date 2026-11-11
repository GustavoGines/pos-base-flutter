import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/reports/data/datasources/reports_remote_datasource.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_position_report_view.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_purchases_report_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'pos_api': 'http://localhost/api'});
  });

  group('VatPositionReportView Adversarial Edge Cases', () {
    testWidgets('Edge Case 1: All Zeroes (0 sales, 0 purchases) renders cleanly without crash or NaN',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final zeroData = {
        'period': {'year': 2026, 'month': 11, 'month_name': 'Noviembre 2026'},
        'sales': {
          'fiscal_debit': 0.0,
          'debit_21': 0.0,
          'debit_105': 0.0,
          'debit_27': 0.0,
          'total_invoiced_net': 0.0,
          'total_sales_amount': 0.0,
          'invoices_count': 0,
          'credit_notes_count': 0,
        },
        'purchases': {
          'fiscal_credit': 0.0,
          'credit_21': 0.0,
          'credit_105': 0.0,
          'credit_27': 0.0,
          'iva_perceptions': 0.0,
          'iibb_perceptions': 0.0,
          'total_purchases_net': 0.0,
          'total_purchases_amount': 0.0,
          'invoices_count': 0,
          'credit_notes_count': 0,
        },
        'balance': {
          'fiscal_debit': 0.0,
          'fiscal_credit': 0.0,
          'iva_perceptions': 0.0,
          'net_balance': 0.0,
          'result': 'favorable',
          'result_label': 'SALDO TÉCNICO A FAVOR ESTIMADO',
          'absolute_balance': 0.0,
        },
        'disclaimer': 'Estimación de gestión...',
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(zeroData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReportsProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VatPositionReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SALDO TÉCNICO A FAVOR ESTIMADO'), findsOneWidget);
      expect(find.text('\$0'), findsWidgets);
      expect(find.text('0 fac. · 0 NC'), findsNWidgets(2));
    });

    testWidgets('Edge Case 2: Negative Balance (Crédito > Débito -> Saldo a Favor)', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final favorableData = {
        'period': {'year': 2026, 'month': 11, 'month_name': 'Noviembre 2026'},
        'sales': {
          'fiscal_debit': 10000.0,
          'debit_21': 10000.0,
          'debit_105': 0.0,
          'debit_27': 0.0,
          'total_invoiced_net': 47619.05,
          'total_sales_amount': 57619.05,
          'invoices_count': 5,
          'credit_notes_count': 0,
        },
        'purchases': {
          'fiscal_credit': 50000.0,
          'credit_21': 45000.0,
          'credit_105': 5000.0,
          'credit_27': 0.0,
          'iva_perceptions': 5000.0,
          'iibb_perceptions': 2000.0,
          'total_purchases_net': 225000.0,
          'total_purchases_amount': 282000.0,
          'invoices_count': 12,
          'credit_notes_count': 1,
        },
        'balance': {
          'fiscal_debit': 10000.0,
          'fiscal_credit': 50000.0,
          'iva_perceptions': 5000.0,
          'net_balance': -45000.0,
          'result': 'favorable',
          'result_label': 'SALDO TÉCNICO A FAVOR ESTIMADO',
          'absolute_balance': 45000.0,
        },
        'disclaimer': 'Estimación de gestión...',
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(favorableData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReportsProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VatPositionReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SALDO TÉCNICO A FAVOR ESTIMADO'), findsOneWidget);
      // Hero card displays absolute formatted amount
      expect(find.text('\$45.000'), findsWidgets);
    });

    testWidgets('Edge Case 3: Positive Balance (Débito > Crédito -> Saldo a Pagar)', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final toPayData = {
        'period': {'year': 2026, 'month': 11, 'month_name': 'Noviembre 2026'},
        'sales': {
          'fiscal_debit': 80000.0,
          'debit_21': 80000.0,
          'debit_105': 0.0,
          'debit_27': 0.0,
          'total_invoiced_net': 380952.38,
          'total_sales_amount': 460952.38,
          'invoices_count': 25,
          'credit_notes_count': 0,
        },
        'purchases': {
          'fiscal_credit': 20000.0,
          'credit_21': 20000.0,
          'credit_105': 0.0,
          'credit_27': 0.0,
          'iva_perceptions': 2000.0,
          'iibb_perceptions': 1000.0,
          'total_purchases_net': 95238.10,
          'total_purchases_amount': 118238.10,
          'invoices_count': 6,
          'credit_notes_count': 0,
        },
        'balance': {
          'fiscal_debit': 80000.0,
          'fiscal_credit': 20000.0,
          'iva_perceptions': 2000.0,
          'net_balance': 58000.0,
          'result': 'to_pay',
          'result_label': 'SALDO ESTIMADO A PAGAR (ARCA / AFIP)',
          'absolute_balance': 58000.0,
        },
        'disclaimer': 'Estimación de gestión...',
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(toPayData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReportsProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VatPositionReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SALDO ESTIMADO A PAGAR (ARCA / AFIP)'), findsOneWidget);
      expect(find.text('\$58.000'), findsWidgets);
    });

    testWidgets('Edge Case 4: Large Numbers (\$100,000,000+) format cleanly without layout overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final massiveData = {
        'period': {'year': 2026, 'month': 11, 'month_name': 'Noviembre 2026'},
        'sales': {
          'fiscal_debit': 210000000.0,
          'debit_21': 210000000.0,
          'debit_105': 0.0,
          'debit_27': 0.0,
          'total_invoiced_net': 1000000000.0,
          'total_sales_amount': 1210000000.0,
          'invoices_count': 1542,
          'credit_notes_count': 12,
        },
        'purchases': {
          'fiscal_credit': 105000000.0,
          'credit_21': 105000000.0,
          'credit_105': 0.0,
          'credit_27': 0.0,
          'iva_perceptions': 5000000.0,
          'iibb_perceptions': 2000000.0,
          'total_purchases_net': 500000000.0,
          'total_purchases_amount': 612000000.0,
          'invoices_count': 450,
          'credit_notes_count': 5,
        },
        'balance': {
          'fiscal_debit': 210000000.0,
          'fiscal_credit': 105000000.0,
          'iva_perceptions': 5000000.0,
          'net_balance': 100000000.0,
          'result': 'to_pay',
          'result_label': 'SALDO ESTIMADO A PAGAR (ARCA / AFIP)',
          'absolute_balance': 100000000.0,
        },
        'disclaimer': 'Estimación de gestión...',
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(massiveData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReportsProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VatPositionReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('\$100.000.000'), findsWidgets);
      expect(find.text('\$210.000.000'), findsWidgets);
      expect(find.text('SALDO ESTIMADO A PAGAR (ARCA / AFIP)'), findsOneWidget);
    });

    testWidgets('Edge Case 5: Missing map keys / null fields degrade gracefully without exception',
        (tester) async {
      final incompleteData = {
        'period': null,
        'sales': null,
        'purchases': null,
        'balance': null,
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(incompleteData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReportsProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VatPositionReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('\$0'), findsWidgets);
    });
  });

  group('VatPurchasesReportView Adversarial Edge Cases', () {
    testWidgets('Edge Case 1: Empty vouchers list renders dedicated empty state', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final emptyData = {
        'start_date': '2026-11-01',
        'end_date': '2026-11-30',
        'summary': {
          'total_net': 0.0,
          'total_iva': 0.0,
          'total_net_21': 0.0,
          'total_iva_21': 0.0,
          'total_net_105': 0.0,
          'total_iva_105': 0.0,
          'total_net_27': 0.0,
          'total_iva_27': 0.0,
          'total_non_taxed': 0.0,
          'total_exempt': 0.0,
          'total_iva_perception': 0.0,
          'total_iibb_perception': 0.0,
          'total_internal_taxes': 0.0,
          'total_credit_fiscal': 0.0,
          'total_amount': 0.0,
          'invoices_count': 0,
          'credit_notes_count': 0,
        },
        'vouchers': [],
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(emptyData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReportsProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VatPurchasesReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('No se registran compras fiscales en este período.'), findsOneWidget);
    });

    testWidgets('Edge Case 2: Credit Notes with negative amounts render in red and with NC badge',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final ncData = {
        'start_date': '2026-11-01',
        'end_date': '2026-11-30',
        'summary': {
          'total_net': -10000.0,
          'total_iva': -2100.0,
          'total_net_21': -10000.0,
          'total_iva_21': -2100.0,
          'total_net_105': 0.0,
          'total_iva_105': 0.0,
          'total_net_27': 0.0,
          'total_iva_27': 0.0,
          'total_non_taxed': 0.0,
          'total_exempt': 0.0,
          'total_iva_perception': 0.0,
          'total_iibb_perception': 0.0,
          'total_internal_taxes': 0.0,
          'total_credit_fiscal': -2100.0,
          'total_amount': -12100.0,
          'invoices_count': 0,
          'credit_notes_count': 1,
        },
        'vouchers': [
          {
            'id': 99,
            'kind': 'credit_note',
            'voucher_letter': 'A',
            'formatted_number': 'NC A 0002-00000099',
            'supplier_name': 'Mayorista Andino',
            'supplier_cuit': '30-98765432-1',
            'issue_date': '2026-11-12',
            'net_21': -10000.0,
            'iva_21': -2100.0,
            'net_105': 0.0,
            'iva_105': 0.0,
            'net_27': 0.0,
            'iva_27': 0.0,
            'non_taxed_amount': 0.0,
            'exempt_amount': 0.0,
            'iva_perception': 0.0,
            'iibb_perception': 0.0,
            'internal_taxes': 0.0,
            'total_amount': -12100.0,
          },
        ],
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(ncData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReportsProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VatPurchasesReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('NC A 0002-00000099'), findsOneWidget);
      expect(find.text('Mayorista Andino'), findsOneWidget);

      // Verify the badge shows 'NC A'
      expect(find.text('NC A'), findsOneWidget);

      // Verify negative total formatted in KPI card and DataTable
      expect(find.text('-\$12.100'), findsNWidgets(2));
    });

    testWidgets('Edge Case 3: Filter mismatch renders "No se encontraron comprobantes..."',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final oneInvoiceData = {
        'start_date': '2026-11-01',
        'end_date': '2026-11-30',
        'summary': {
          'total_net': 1000.0,
          'total_iva': 210.0,
          'total_amount': 1210.0,
          'invoices_count': 1,
          'credit_notes_count': 0,
        },
        'vouchers': [
          {
            'id': 1,
            'kind': 'invoice',
            'voucher_letter': 'A',
            'formatted_number': 'A 0001-00000001',
            'supplier_name': 'Proveedor Solo Factura',
            'total_amount': 1210.0,
          },
        ],
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(oneInvoiceData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReportsProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VatPurchasesReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on 'Notas de Crédito' filter
      await tester.tap(find.text('Notas de Crédito'));
      await tester.pumpAndSettle();

      expect(find.text('No se encontraron comprobantes con los filtros seleccionados.'), findsOneWidget);
    });
  });
}
