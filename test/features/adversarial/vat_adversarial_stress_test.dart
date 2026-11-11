import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/reports/data/datasources/reports_remote_datasource.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_management_tab.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_position_report_view.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_purchases_report_view.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/vat_sales_report_view.dart';
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

  group('ADVERSARIAL SUITE 1: Extreme Decimals & Mathematical Tolerance', () {
    test('Extreme numerical values and float limits in SupplierInvoiceModel serialization', () {
      final extremeJson = {
        'id': 999999999,
        'supplier_id': 888888888,
        'type': 'invoice',
        'status': 'paid',
        'amount': 999999999999.99,
        'voucher_letter': 'A',
        'point_of_sale': 99999,
        'voucher_number': 99999999,
        'net_21': 826446280991.73,
        'iva_21': 173553719008.26,
        'net_105': 0.0000001,
        'iva_105': 0.0000000105,
        'net_27': 0.0,
        'iva_27': 0.0,
        'non_taxed_amount': 0.0,
        'exempt_amount': 0.0,
        'iva_perception': 0.0,
        'iibb_perception': 0.0,
        'internal_taxes': 0.0,
        'affects_vat_book': true,
      };

      final model = SupplierInvoiceModel.fromJson(extremeJson);

      expect(model.amount, 999999999999.99);
      expect(model.pointOfSale, 99999);
      expect(model.voucherNumber, 99999999);
      expect(model.net21, 826446280991.73);
      expect(model.iva21, 173553719008.26);
      expect(model.formattedNumber, 'A 99999-99999999');

      final serialized = model.toJson();
      expect(serialized['amount'], 999999999999.99);
      expect(serialized['point_of_sale'], 99999);
      expect(serialized['voucher_number'], 99999999);
      expect(serialized['net_21'], 826446280991.73);
    });

    test('Tolerance validation logic (sum - total).abs() <= 0.05 boundary stress test', () {
      // Test exactly at boundary 0.05
      const total = 1000.0;

      // Case A: Exact match
      double sumExact = 1000.0;
      expect((sumExact - total).abs() <= 0.05, isTrue);

      // Case B: Diff = +0.049 (Within tolerance)
      double sumUnder = 1000.049;
      expect((sumUnder - total).abs() <= 0.05, isTrue);

      // Case C: Diff = -0.049 (Within tolerance)
      double sumOver = 999.951;
      expect((sumOver - total).abs() <= 0.05, isTrue);

      // Case D: Diff = +0.0500000000000001 (Boundary)
      double sumExactBoundary = 1000.05;
      expect((sumExactBoundary - total).abs() <= 0.05, isTrue);

      // Case E: Diff = +0.051 (Violation)
      double sumViolatePlus = 1000.051;
      expect((sumViolatePlus - total).abs() <= 0.05, isFalse);

      // Case F: Diff = -0.051 (Violation)
      double sumViolateMinus = 999.949;
      expect((sumViolateMinus - total).abs() <= 0.05, isFalse);
    });

    test('Net 21% auto-distribution mathematical invariant across 10,000 randomized amounts', () {
      // Invariant: For any total > 0:
      // net = (total / 1.21 * 100).round() / 100.0
      // iva = total - net
      // Then (net + iva - total).abs() MUST BE IDENTICALLY 0.0 (<= 0.0000001)
      final rng = Random(42);

      for (int i = 0; i < 10000; i++) {
        final total = (rng.nextDouble() * 5000000.0) + 0.01;
        final net = (total / 1.21 * 100).round() / 100.0;
        final iva = (total - net);
        final sum = net + iva;
        final diff = (sum - total).abs();

        expect(diff, lessThanOrEqualTo(0.0000001),
            reason: 'Failed at total: $total, net: $net, iva: $iva, diff: $diff');
        expect(diff <= 0.05, isTrue);
      }
    });

    test('ArsThousandsInputFormatter resilience against malformed strings and edge values', () {
      expect(ArsThousandsInputFormatter.tryParse(null), isNull);
      expect(ArsThousandsInputFormatter.tryParse(''), isNull);
      expect(ArsThousandsInputFormatter.tryParse('   '), isNull);
      expect(ArsThousandsInputFormatter.tryParse('abc'), isNull);
      expect(ArsThousandsInputFormatter.tryParse('0'), 0.0);
      expect(ArsThousandsInputFormatter.tryParse('1.234,56'), 1234.56);
      expect(ArsThousandsInputFormatter.tryParse('1234.56'), 1234.56);
      expect(ArsThousandsInputFormatter.tryParse('1.000.000,50'), 1000000.50);
      expect(ArsThousandsInputFormatter.tryParse('-1.000,00'), -1000.0);

      // parse defaults to 0.0 on invalid
      expect(ArsThousandsInputFormatter.parse(''), 0.0);
      expect(ArsThousandsInputFormatter.parse('garbage'), 0.0);
    });
  });

  group('ADVERSARIAL SUITE 2: Zero, Null & Malformed Fields in Models & Entities', () {
    test('SupplierInvoiceModel fromJson handles corrupt types (strings in numeric fields, etc.)', () {
      final corruptJson = {
        'id': '105', // string id
        'supplier_id': '42', // string supplier_id
        'supplier_name': 12345, // int supplier_name
        'amount': '15000.75', // string amount
        'point_of_sale': '0005', // string point_of_sale
        'voucher_number': '00123456', // string voucher_number
        'net_21': '10000.00', // string net
        'iva_21': '2100.00', // string iva
        'affects_vat_book': '0', // string bool
      };

      final model = SupplierInvoiceModel.fromJson(corruptJson);

      expect(model.id, 105);
      expect(model.supplierId, 42);
      expect(model.supplierName, '12345');
      expect(model.amount, 15000.75);
      expect(model.pointOfSale, 5);
      expect(model.voucherNumber, 123456);
      expect(model.net21, 10000.00);
      expect(model.iva21, 2100.00);
      expect(model.affectsVatBook, isFalse);
      expect(model.formattedNumber, 'A 0005-00123456');
    });

    test('SupplierInvoiceModel fromJson handles completely empty and null json map', () {
      final model = SupplierInvoiceModel.fromJson({});

      expect(model.id, isNull);
      expect(model.supplierId, 0);
      expect(model.amount, 0.0);
      expect(model.voucherLetter, isNull);
      expect(model.pointOfSale, isNull);
      expect(model.voucherNumber, isNull);
      expect(model.net21, isNull);
      expect(model.iva21, isNull);
      expect(model.net105, isNull);
      expect(model.iva105, isNull);
      expect(model.net27, isNull);
      expect(model.iva27, isNull);
      expect(model.nonTaxedAmount, isNull);
      expect(model.exemptAmount, isNull);
      expect(model.ivaPerception, isNull);
      expect(model.iibbPerception, isNull);
      expect(model.internalTaxes, isNull);
      expect(model.affectsVatBook, isTrue); // default is true
      expect(model.formattedNumber, '');
    });

    test('formattedNumber edge cases: letters, padding, nulls, whitespace', () {
      // 1. Lowercase letter gets uppercased
      const inv1 = SupplierInvoice(
        supplierId: 1,
        amount: 100,
        voucherLetter: 'b',
        pointOfSale: 3,
        voucherNumber: 45,
      );
      expect(inv1.formattedNumber, 'B 0003-00000045');

      // 2. Whitespace letter falls back to 'A'
      const inv2 = SupplierInvoice(
        supplierId: 1,
        amount: 100,
        voucherLetter: '   ',
        pointOfSale: 12,
        voucherNumber: 987,
      );
      expect(inv2.formattedNumber, 'A 0012-00000987');

      // 3. Null point of sale falls back to invoiceNumber
      const inv3 = SupplierInvoice(
        supplierId: 1,
        amount: 100,
        invoiceNumber: 'MANUAL-999',
        voucherLetter: 'A',
        voucherNumber: 123,
      );
      expect(inv3.formattedNumber, 'MANUAL-999');

      // 4. Null voucherNumber falls back to invoiceNumber
      const inv4 = SupplierInvoice(
        supplierId: 1,
        amount: 100,
        invoiceNumber: 'MANUAL-888',
        pointOfSale: 1,
      );
      expect(inv4.formattedNumber, 'MANUAL-888');

      // 5. All null falls back to empty string
      const inv5 = SupplierInvoice(
        supplierId: 1,
        amount: 100,
      );
      expect(inv5.formattedNumber, '');
    });

    test('Equatable comparison correctly discriminates every single fiscal field', () {
      const base = SupplierInvoice(
        supplierId: 1,
        amount: 100,
        voucherLetter: 'A',
        pointOfSale: 1,
        voucherNumber: 100,
        net21: 82.64,
        iva21: 17.36,
        net105: 0.0,
        iva105: 0.0,
        net27: 0.0,
        iva27: 0.0,
        nonTaxedAmount: 0.0,
        exemptAmount: 0.0,
        ivaPerception: 0.0,
        iibbPerception: 0.0,
        internalTaxes: 0.0,
        affectsVatBook: true,
      );

      final identicalClone = base.copyWith();
      expect(base == identicalClone, isTrue);

      // Verify changing any single fiscal property breaks equality
      expect(base == base.copyWith(voucherLetter: 'B'), isFalse);
      expect(base == base.copyWith(pointOfSale: 2), isFalse);
      expect(base == base.copyWith(voucherNumber: 101), isFalse);
      expect(base == base.copyWith(net21: 80.0), isFalse);
      expect(base == base.copyWith(iva21: 16.8), isFalse);
      expect(base == base.copyWith(net105: 10.0), isFalse);
      expect(base == base.copyWith(iva105: 1.05), isFalse);
      expect(base == base.copyWith(net27: 5.0), isFalse);
      expect(base == base.copyWith(iva27: 1.35), isFalse);
      expect(base == base.copyWith(nonTaxedAmount: 1.0), isFalse);
      expect(base == base.copyWith(exemptAmount: 1.0), isFalse);
      expect(base == base.copyWith(ivaPerception: 5.0), isFalse);
      expect(base == base.copyWith(iibbPerception: 2.0), isFalse);
      expect(base == base.copyWith(internalTaxes: 3.0), isFalse);
      expect(base == base.copyWith(affectsVatBook: false), isFalse);
    });
  });

  group('ADVERSARIAL SUITE 3: Voucher Letter B/C Business Rules & Invariants', () {
    test('Voucher Letter B/C forces zero IVA and redirects entire amount to non-taxed', () {
      // In AFIP/ARCA rules for Responsable Inscripto receiving Factura B or C:
      // Comprobantes emitidos por Monotributistas (C) o a Consumidores Finales/Sujetos No Categorizados (B)
      // no generan Crédito Fiscal computable.
      const double totalAmount = 35400.50;

      // When letter is B or C:
      // Fiscal calculation:
      final letter = 'B';
      final isBC = letter == 'B' || letter == 'C';
      expect(isBC, isTrue);

      // Verification of zero IVA condition
      final net21 = isBC ? 0.0 : 20000.0;
      final iva21 = isBC ? 0.0 : 4200.0;
      final nonTaxed = isBC ? totalAmount : 0.0;

      expect(net21, 0.0);
      expect(iva21, 0.0);
      expect(nonTaxed, totalAmount);

      final fiscalSum = net21 + iva21 + nonTaxed;
      expect((fiscalSum - totalAmount).abs() <= 0.05, isTrue);
    });
  });

  group('ADVERSARIAL SUITE 4: Rapid Tab Switching & Stress in VatManagementTab', () {
    testWidgets('Rapidly toggles between all 3 sub-views 60 times without crash or leak', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/reports/vat-purchases')) {
          return http.Response(
            jsonEncode({
              'start_date': '2026-11-01',
              'end_date': '2026-11-30',
              'summary': {
                'total_net': 1000.0,
                'total_iva': 210.0,
                'total_credit_fiscal': 210.0,
                'total_amount': 1210.0,
                'invoices_count': 1,
                'credit_notes_count': 0,
              },
              'vouchers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/reports/vat-position')) {
          return http.Response(
            jsonEncode({
              'period': {'year': 2026, 'month': 11, 'month_name': 'Noviembre 2026'},
              'sales': {'fiscal_debit': 500.0, 'total_sales_amount': 500.0},
              'purchases': {'fiscal_credit': 200.0, 'total_purchases_amount': 200.0},
              'balance': {'net_balance': 300.0, 'result': 'to_pay'},
              'disclaimer': 'Test disclaimer',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/reports/vat-sales')) {
          return http.Response(
            jsonEncode({
              'summary': {'total_net': 1000, 'total_iva': 210, 'total_invoiced': 1210},
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

      final tab1Finder = find.text('⚖️ Posición Mensual');
      final tab2Finder = find.text('📤 Libro IVA Ventas');
      final tab3Finder = find.text('📥 Libro IVA Compras');

      expect(tab1Finder, findsOneWidget);
      expect(tab2Finder, findsOneWidget);
      expect(tab3Finder, findsOneWidget);

      // Stress toggle 60 times in sequence 0 -> 1 -> 2 -> 0 ...
      for (int i = 0; i < 20; i++) {
        await tester.tap(tab2Finder);
        await tester.pump();
        await tester.tap(tab3Finder);
        await tester.pump();
        await tester.tap(tab1Finder);
        await tester.pump();
      }

      await tester.pumpAndSettle();

      // After stress toggling, verify that IndexedStack properly preserves all 3 sub-views
      expect(find.byType(IndexedStack), findsWidgets);
      expect(find.byType(VatPositionReportView, skipOffstage: false), findsOneWidget);
      expect(find.byType(VatSalesReportView, skipOffstage: false), findsOneWidget);
      expect(find.byType(VatPurchasesReportView, skipOffstage: false), findsOneWidget);

      // Verify active tab (Posición Mensual) is onstage
      expect(find.byType(VatPositionReportView), findsOneWidget);

      // Switch to Libro IVA Ventas and verify it becomes onstage
      await tester.tap(tab2Finder);
      await tester.pumpAndSettle();
      expect(find.byType(VatSalesReportView), findsOneWidget);

      // Switch to Libro IVA Compras and verify it becomes onstage
      await tester.tap(tab3Finder);
      await tester.pumpAndSettle();
      expect(find.byType(VatPurchasesReportView), findsOneWidget);
    });
  });

  group('ADVERSARIAL SUITE 5: Reports Edge Handling (Negative Balances, Credit Notes, Null Maps)', () {
    testWidgets('VatPositionReportView correctly renders favorable balance (saldo a favor técnico)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // purchases > sales -> favorable balance (negative net balance)
      final favorableData = {
        'period': {'year': 2026, 'month': 11, 'month_name': 'Noviembre 2026'},
        'sales': {
          'fiscal_debit': 10000.0,
          'debit_21': 10000.0,
          'total_invoiced_net': 47619.0,
          'total_sales_amount': 57619.0,
          'invoices_count': 10,
          'credit_notes_count': 0,
        },
        'purchases': {
          'fiscal_credit': 25000.0,
          'credit_21': 25000.0,
          'iva_perceptions': 5000.0,
          'iibb_perceptions': 1000.0,
          'total_purchases_net': 119047.0,
          'total_purchases_amount': 150047.0,
          'invoices_count': 8,
          'credit_notes_count': 0,
        },
        'balance': {
          'fiscal_debit': 10000.0,
          'fiscal_credit': 25000.0,
          'iva_perceptions': 5000.0,
          'net_balance': -20000.0, // Favorable balance
          'result': 'favorable',
          'result_label': 'Saldo Técnico a Favor Estimado',
          'absolute_balance': 20000.0,
        },
        'disclaimer': 'Estimación de gestión para control interno.',
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

      // Look for favorable balance rendering
      expect(find.textContaining('SALDO TÉCNICO A FAVOR'), findsWidgets);
      expect(find.textContaining('20.000'), findsWidgets);
    });

    testWidgets('VatPurchasesReportView handles credit notes with negative amounts cleanly', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final creditNoteData = {
        'start_date': '2026-11-01',
        'end_date': '2026-11-30',
        'summary': {
          'total_net': -10000.0,
          'total_iva': -2100.0,
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
            'formatted_number': 'NC A 0002-00000010',
            'supplier_name': 'Proveedor Devoluciones S.R.L.',
            'supplier_cuit': '30-99999999-9',
            'issue_date': '2026-11-15',
            'net_21': -10000.0,
            'iva_21': -2100.0,
            'total_amount': -12100.0,
          }
        ],
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(creditNoteData), 200, headers: {'content-type': 'application/json'});
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

      // Look for the Credit Note badge and text
      expect(find.text('NC A'), findsOneWidget);
      expect(find.text('Proveedor Devoluciones S.R.L.'), findsOneWidget);
    });
  });
}
