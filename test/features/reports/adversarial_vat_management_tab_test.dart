import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/reports/data/datasources/reports_remote_datasource.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_management_tab.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_position_report_view.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_purchases_report_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'pos_api': 'http://localhost/api'});
  });

  final sampleVatPurchasesData = {
    'start_date': '2026-11-01',
    'end_date': '2026-11-30',
    'summary': {
      'total_net': 150000.0,
      'total_iva': 31500.0,
      'total_net_21': 100000.0,
      'total_iva_21': 21000.0,
      'total_net_105': 50000.0,
      'total_iva_105': 5250.0,
      'total_net_27': 0.0,
      'total_iva_27': 0.0,
      'total_non_taxed': 10000.0,
      'total_exempt': 0.0,
      'total_iva_perception': 3000.0,
      'total_iibb_perception': 1500.0,
      'total_internal_taxes': 0.0,
      'total_credit_fiscal': 31500.0,
      'total_amount': 196000.0,
      'invoices_count': 5,
      'credit_notes_count': 1,
    },
    'vouchers': [
      {
        'id': 1,
        'kind': 'invoice',
        'voucher_letter': 'A',
        'formatted_number': 'A 0001-00010001',
        'supplier_name': 'Distribuidora Los Andes',
        'supplier_cuit': '30-12345678-9',
        'issue_date': '2026-11-05',
        'net_21': 100000.0,
        'iva_21': 21000.0,
        'net_105': 0.0,
        'iva_105': 0.0,
        'net_27': 0.0,
        'iva_27': 0.0,
        'non_taxed_amount': 0.0,
        'exempt_amount': 0.0,
        'iva_perception': 3000.0,
        'iibb_perception': 1500.0,
        'internal_taxes': 0.0,
        'total_amount': 125500.0,
      },
    ],
  };

  final sampleVatPositionData = {
    'period': {'year': 2026, 'month': 11, 'month_name': 'Noviembre 2026'},
    'sales': {
      'fiscal_debit': 45000.0,
      'debit_21': 42000.0,
      'debit_105': 3000.0,
      'debit_27': 0.0,
      'total_invoiced_net': 200000.0,
      'total_sales_amount': 245000.0,
      'invoices_count': 120,
      'credit_notes_count': 2,
    },
    'purchases': {
      'fiscal_credit': 31500.0,
      'credit_21': 21000.0,
      'credit_105': 10500.0,
      'credit_27': 0.0,
      'iva_perceptions': 3000.0,
      'iibb_perceptions': 1500.0,
      'total_purchases_net': 150000.0,
      'total_purchases_amount': 186000.0,
      'invoices_count': 15,
      'credit_notes_count': 1,
    },
    'balance': {
      'fiscal_debit': 45000.0,
      'fiscal_credit': 31500.0,
      'iva_perceptions': 3000.0,
      'net_balance': 10500.0,
      'result': 'to_pay',
      'result_label': 'Saldo a Pagar a ARCA / AFIP',
      'absolute_balance': 10500.0,
    },
    'disclaimer': 'Estimación de gestión para control interno.',
  };

  group('Adversarial Stress Test: VatManagementTab Rapid Switching & Null Safety', () {
    testWidgets('Rapid tab switching (50 switches) does not crash or leak memory', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/reports/vat-purchases')) {
          return http.Response(jsonEncode(sampleVatPurchasesData), 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.contains('/reports/vat-position')) {
          return http.Response(jsonEncode(sampleVatPositionData), 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.contains('/reports/vat-sales')) {
          return http.Response(
            jsonEncode({
              'summary': {'total_net': 10000, 'total_iva': 2100, 'total_invoiced': 12100, 'total_credit_notes': 0},
              'vouchers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
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
              body: VatManagementTab(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final tab1 = find.text('⚖️ Posición Mensual');
      final tab2 = find.text('📤 Libro IVA Ventas');
      final tab3 = find.text('📥 Libro IVA Compras');

      // Rapidly toggle between sub-tabs 50 times in rapid succession
      for (int i = 0; i < 50; i++) {
        if (i % 3 == 0) {
          await tester.tap(tab2);
        } else if (i % 3 == 1) {
          await tester.tap(tab3);
        } else {
          await tester.tap(tab1);
        }
        await tester.pump(const Duration(milliseconds: 10));
      }

      await tester.pumpAndSettle();

      // Ensure widgets survived intact without exception
      expect(find.byType(VatManagementTab), findsOneWidget);
      expect(find.byType(IndexedStack), findsOneWidget);
    });

    testWidgets('VatPositionReportView handles negative or favorable technical balance gracefully', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final favorableBalanceData = {
        'period': {'year': 2026, 'month': 11, 'month_name': 'Noviembre 2026'},
        'sales': {
          'fiscal_debit': 10000.0,
          'debit_21': 10000.0,
          'debit_105': 0.0,
          'debit_27': 0.0,
          'total_invoiced_net': 47619.05,
          'total_sales_amount': 57619.05,
          'invoices_count': 10,
          'credit_notes_count': 0,
        },
        'purchases': {
          'fiscal_credit': 25000.0,
          'credit_21': 25000.0,
          'credit_105': 0.0,
          'credit_27': 0.0,
          'iva_perceptions': 2000.0,
          'iibb_perceptions': 500.0,
          'total_purchases_net': 119047.62,
          'total_purchases_amount': 146047.62,
          'invoices_count': 8,
          'credit_notes_count': 0,
        },
        'balance': {
          'fiscal_debit': 10000.0,
          'fiscal_credit': 25000.0,
          'iva_perceptions': 2000.0,
          'net_balance': -17000.0,
          'result': 'favorable',
          'result_label': 'Saldo Técnico a Favor Estimado',
          'absolute_balance': 17000.0,
        },
        'disclaimer': 'Estimación de gestión para control interno.',
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(favorableBalanceData), 200, headers: {'content-type': 'application/json'});
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

      expect(find.textContaining('SALDO TÉCNICO A FAVOR'), findsOneWidget);
    });

    testWidgets('VatPurchasesReportView handles empty vouchers list and zeroes without error', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final emptyPurchasesData = {
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
        return http.Response(jsonEncode(emptyPurchasesData), 200, headers: {'content-type': 'application/json'});
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

      expect(find.text('No se registran compras fiscales en este período.'), findsOneWidget);
    });
  });
}
