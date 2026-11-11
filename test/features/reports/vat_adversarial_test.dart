import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/reports/data/datasources/reports_remote_datasource.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_management_tab.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_position_report_view.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_purchases_report_view.dart';
import 'package:frontend_desktop/features/suppliers/data/models/supplier_invoice_model.dart';
import 'package:frontend_desktop/features/suppliers/domain/entities/supplier_invoice.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'pos_api': 'http://localhost/api'});
  });

  group('Adversarial Stress Test: SupplierInvoice & Model Resilience', () {
    test('handles completely null, empty, or unexpected data types without crashing', () {
      final crazyJson = <String, dynamic>{
        'id': '999999',
        'supplier_id': '888',
        'supplier': {'name': 'Super Long Corporate Supplier Name S.A. Commercial Distribution Enterprise'},
        'type': null,
        'status': null,
        'amount': '1234567.89',
        'invoice_number': null,
        'issue_date': 'invalid-date-string-here',
        'due_date': 'also-invalid',
        'voucher_letter': 'a', // lowercase letter
        'point_of_sale': '0004',
        'voucher_number': '00012345',
        'net_21': '1000000.50',
        'iva_21': '210000.11',
        'net_105': 0,
        'iva_105': '0.00',
        'net_27': null,
        'iva_27': null,
        'non_taxed_amount': 'invalid_num',
        'exempt_amount': null,
        'iva_perception': -500.0, // negative perception
        'iibb_perception': 'null',
        'internal_taxes': null,
        'affects_vat_book': 'false', // string false
      };

      final model = SupplierInvoiceModel.fromJson(crazyJson);

      expect(model.id, 999999);
      expect(model.supplierId, 888);
      expect(model.supplierName, contains('Super Long Corporate'));
      expect(model.amount, 1234567.89);
      expect(model.issueDate, isNull);
      expect(model.dueDate, isNull);
      expect(model.pointOfSale, 4);
      expect(model.voucherNumber, 12345);
      expect(model.net21, 1000000.50);
      expect(model.iva21, 210000.11);
      expect(model.nonTaxedAmount, isNull);
      expect(model.ivaPerception, -500.0);
      expect(model.iibbPerception, isNull);
      expect(model.affectsVatBook, isFalse);
      expect(model.formattedNumber, 'A 0004-00012345');
    });

    test('formattedNumber behavior under boundary combinations', () {
      // 1. Neither POS nor Number
      const inv1 = SupplierInvoice(supplierId: 1, amount: 100);
      expect(inv1.formattedNumber, '');

      // 2. POS present, number null
      const inv2 = SupplierInvoice(supplierId: 1, amount: 100, pointOfSale: 1);
      expect(inv2.formattedNumber, '');

      // 3. Number present, POS null
      const inv3 = SupplierInvoice(supplierId: 1, amount: 100, voucherNumber: 42);
      expect(inv3.formattedNumber, '');

      // 4. Fallback to legacy invoiceNumber
      const inv4 = SupplierInvoice(supplierId: 1, amount: 100, invoiceNumber: 'LEGACY-0099');
      expect(inv4.formattedNumber, 'LEGACY-0099');

      // 5. Letter is null or whitespace
      const inv5 = SupplierInvoice(supplierId: 1, amount: 100, pointOfSale: 3, voucherNumber: 77, voucherLetter: '   ');
      expect(inv5.formattedNumber, 'A 0003-00000077');
    });
  });

  group('Adversarial Layout Stress Test: Compact Screen 1024x768 & 800x600', () {
    final heavyPurchasesData = {
      'start_date': '2026-11-01',
      'end_date': '2026-11-30',
      'summary': {
        'total_net': 99999999.99,
        'total_iva': 21000000.00,
        'total_net_21': 80000000.00,
        'total_iva_21': 16800000.00,
        'total_net_105': 15000000.00,
        'total_iva_105': 1575000.00,
        'total_net_27': 4999999.99,
        'total_iva_27': 1350000.00,
        'total_non_taxed': 500000.00,
        'total_exempt': 250000.00,
        'total_iva_perception': 1200000.00,
        'total_iibb_perception': 800000.00,
        'total_internal_taxes': 300000.00,
        'total_credit_fiscal': 21000000.00,
        'total_amount': 122299999.99,
        'invoices_count': 450,
        'credit_notes_count': 32,
      },
      'vouchers': [
        {
          'id': 101,
          'kind': 'invoice',
          'voucher_letter': 'A',
          'formatted_number': 'A 9999-99999999',
          'supplier_name': 'Distribuidora Mayorista Hiper Ultra Larga con Razón Social Gigante S.A.',
          'supplier_cuit': '30-99999999-9',
          'issue_date': '2026-11-01',
          'net_21': 50000000.0,
          'iva_21': 10500000.0,
          'net_105': 10000000.0,
          'iva_105': 1050000.0,
          'net_27': 5000000.0,
          'iva_27': 1350000.0,
          'non_taxed_amount': 500000.0,
          'exempt_amount': 250000.0,
          'iva_perception': 1200000.0,
          'iibb_perception': 800000.0,
          'internal_taxes': 300000.0,
          'total_amount': 65900000.0,
        },
        {
          'id': 102,
          'kind': 'credit_note',
          'voucher_letter': 'A',
          'formatted_number': 'NC A 0001-00000888',
          'supplier_name': 'Distribuidora Mayorista Hiper Ultra Larga S.A.',
          'supplier_cuit': '30-99999999-9',
          'issue_date': '2026-11-02',
          'net_21': -10000000.0,
          'iva_21': -2100000.0,
          'net_105': 0.0,
          'iva_105': 0.0,
          'net_27': 0.0,
          'iva_27': 0.0,
          'non_taxed_amount': 0.0,
          'exempt_amount': 0.0,
          'iva_perception': 0.0,
          'iibb_perception': 0.0,
          'internal_taxes': 0.0,
          'total_amount': -12100000.0,
        },
      ],
    };

    final favorablePositionData = {
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
        'fiscal_credit': 80000.0,
        'credit_21': 60000.0,
        'credit_105': 20000.0,
        'credit_27': 0.0,
        'iva_perceptions': 15000.0,
        'iibb_perceptions': 8000.0,
        'total_purchases_net': 350000.0,
        'total_purchases_amount': 445000.0,
        'invoices_count': 25,
        'credit_notes_count': 2,
      },
      'balance': {
        'fiscal_debit': 10000.0,
        'fiscal_credit': 80000.0,
        'iva_perceptions': 15000.0,
        'net_balance': -85000.0, // Saldo a Favor del Contribuyente
        'result': 'favorable',
        'result_label': 'Saldo Técnico a Favor del Contribuyente',
        'absolute_balance': 85000.0,
      },
      'disclaimer': 'Estimación de gestión para control interno.',
    };

    testWidgets('VatPurchasesReportView renders at 1024x768 without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(heavyPurchasesData), 200, headers: {'content-type': 'application/json'});
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
      expect(find.text('CRÉDITO FISCAL TOTAL (A DESCONTAR)'), findsOneWidget);
      expect(find.text('TOTAL COMPRAS FACTURADAS'), findsOneWidget);
    });

    testWidgets('VatPositionReportView renders Saldo a Favor at 1024x768 without overflow', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterErrorDetails? caughtDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caughtDetails = details;
        originalOnError?.call(details);
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(favorablePositionData), 200, headers: {'content-type': 'application/json'});
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

      if (caughtDetails != null) {
        // ignore: avoid_print
        print('EXACT OVERFLOW DETAILS:\n${caughtDetails!.toString()}');
      }
      expect(caughtDetails, isNull);
      expect(find.text('SALDO TÉCNICO A FAVOR ESTIMADO'), findsOneWidget);
      expect(find.text('AVISO LEGAL Y DE CONTROL DE GESTIÓN'), findsOneWidget);
    });

    testWidgets('VatManagementTab toggles between all sub-views at 800x600 without overflow', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/vat-purchases')) {
          return http.Response(jsonEncode(heavyPurchasesData), 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.contains('/vat-position')) {
          return http.Response(jsonEncode(favorablePositionData), 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.contains('/vat-sales')) {
          return http.Response(
            jsonEncode({'summary': {'total_net': 1000}, 'vouchers': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
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
      expect(tester.takeException(), isNull);

      // Switch to purchases
      await tester.tap(find.text('📥 Libro IVA Compras'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch to position
      await tester.tap(find.text('⚖️ Posición Mensual'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
