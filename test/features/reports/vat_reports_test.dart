import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/reports/data/datasources/reports_remote_datasource.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_management_tab.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_position_report_view.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_purchases_report_view.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_sales_report_view.dart';
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
      {
        'id': 2,
        'kind': 'credit_note',
        'voucher_letter': 'A',
        'formatted_number': 'NC A 0001-00000005',
        'supplier_name': 'Distribuidora Los Andes',
        'supplier_cuit': '30-12345678-9',
        'issue_date': '2026-11-10',
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
    'disclaimer': 'Estimación de gestión para control interno. No reemplaza la declaración jurada mensual F. 2002 de ARCA/AFIP.',
  };

  group('ReportsRemoteDataSource Vat Purchases & Position Unit Tests', () {
    test('getVatPurchases queries the correct endpoint and returns parsed JSON', () async {
      String? requestedUrl;
      final mockClient = MockClient((request) async {
        requestedUrl = request.url.toString();
        return http.Response(jsonEncode(sampleVatPurchasesData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final result = await dataSource.getVatPurchases('2026-11-01', '2026-11-30', voucherType: 'A');

      expect(requestedUrl, contains('/reports/vat-purchases'));
      expect(requestedUrl, contains('start_date=2026-11-01'));
      expect(requestedUrl, contains('end_date=2026-11-30'));
      expect(requestedUrl, contains('voucher_type=A'));
      expect(result['summary']['total_credit_fiscal'], 31500.0);
    });

    test('getVatPosition queries endpoint with year and month', () async {
      String? requestedUrl;
      final mockClient = MockClient((request) async {
        requestedUrl = request.url.toString();
        return http.Response(jsonEncode(sampleVatPositionData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final result = await dataSource.getVatPosition(2026, 11);

      expect(requestedUrl, contains('/reports/vat-position'));
      expect(requestedUrl, contains('year=2026'));
      expect(requestedUrl, contains('month=11'));
      expect(result['balance']['net_balance'], 10500.0);
    });

    test('downloadVatPurchasesExcel and downloadVatPurchasesPdf fetch bytes', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes([10, 20, 30, 40], 200);
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final excelBytes = await dataSource.downloadVatPurchasesExcel('2026-11-01', '2026-11-30');
      expect(excelBytes, [10, 20, 30, 40]);

      final pdfBytes = await dataSource.downloadVatPurchasesPdf('2026-11-01', '2026-11-30');
      expect(pdfBytes, [10, 20, 30, 40]);
    });
  });

  group('ReportsProvider Vat State Management Unit Tests', () {
    test('fetchVatPurchases loads summary and vouchers into state', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleVatPurchasesData), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await provider.fetchVatPurchases();

      expect(provider.vatPurchasesSummary['total_credit_fiscal'], 31500.0);
      expect(provider.vatPurchasesVouchers.length, 2);
      expect(provider.vatPurchasesError, isNull);
    });

    test('fetchVatPosition loads sales, purchases, balance and period into state', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleVatPositionData), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      provider.setVatPositionPeriod(2026, 11);
      await provider.fetchVatPosition();

      expect(provider.vatPositionYear, 2026);
      expect(provider.vatPositionMonth, 11);
      expect(provider.vatPositionData['balance']['result'], 'to_pay');
    });

    test('filters and search queries update state', () {
      final mockClient = MockClient((request) async => http.Response('{}', 200));
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      provider.setVatPurchasesFilter('NC');
      expect(provider.vatPurchasesFilter, 'NC');

      provider.setVatPurchasesSearchQuery('Los Andes');
      expect(provider.vatPurchasesSearchQuery, 'Los Andes');
    });
  });

  group('VatManagementTab Widget & Navigation Tests', () {
    testWidgets('VatManagementTab renders sub-view buttons and switches indexed stack', (tester) async {
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

      // Sub-view buttons exist
      expect(find.text('⚖️ Posición Mensual'), findsOneWidget);
      expect(find.text('📤 Libro IVA Ventas'), findsOneWidget);
      expect(find.text('📥 Libro IVA Compras'), findsOneWidget);

      // Initially shows Posición Mensual (index 0)
      expect(find.byType(VatPositionReportView), findsOneWidget);

      // Tap Libro IVA Compras (index 2)
      await tester.tap(find.text('📥 Libro IVA Compras'));
      await tester.pumpAndSettle();

      expect(find.byType(VatPurchasesReportView), findsOneWidget);

      // Tap Libro IVA Ventas (index 1)
      await tester.tap(find.text('📤 Libro IVA Ventas'));
      await tester.pumpAndSettle();

      expect(find.byType(VatSalesReportView), findsOneWidget);
    });

    testWidgets('VatPurchasesReportView separates NO GRAV. / EX. from PERCEP. / OTROS and badges historical S/D',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final historicalData = {
        'start_date': '2026-11-01',
        'end_date': '2026-11-30',
        'summary': {
          'total_net': 0.0,
          'total_iva': 0.0,
          'total_non_taxed': 410000.0,
          'total_exempt': 0.0,
          'total_iva_perception': 0.0,
          'total_iibb_perception': 0.0,
          'total_internal_taxes': 0.0,
          'total_credit_fiscal': 0.0,
          'total_amount': 410000.0,
          'invoices_count': 1,
          'credit_notes_count': 0,
        },
        'vouchers': [
          {
            'id': 5,
            'kind': 'invoice',
            'voucher_letter': 'S/D',
            'is_historical': true,
            'formatted_number': 'S/N',
            'supplier_name': '180 Pasteleria',
            'supplier_cuit': '27388291497',
            'issue_date': '2026-11-05T10:00:00.000Z',
            'net_21': 0.0,
            'iva_21': 0.0,
            'non_taxed_amount': 410000.0,
            'exempt_amount': 0.0,
            'iva_perception': 0.0,
            'iibb_perception': 0.0,
            'internal_taxes': 0.0,
            'credit_fiscal': 0.0,
            'total_amount': 410000.0,
          },
        ],
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(historicalData), 200, headers: {'content-type': 'application/json'});
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

      expect(find.text('NO GRAV. / EX.'), findsOneWidget);
      expect(find.text('PERCEP. / OTROS'), findsOneWidget);
      expect(find.text('COMP. S/D'), findsOneWidget);
      expect(find.text('FAC A'), findsNothing);
    });
  });
}
