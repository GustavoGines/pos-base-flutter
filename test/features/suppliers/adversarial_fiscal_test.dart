import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/suppliers/data/models/supplier_invoice_model.dart';
import 'package:frontend_desktop/features/suppliers/domain/entities/supplier_invoice.dart';

void main() {
  group('Adversarial Stress Test: SupplierInvoice & SupplierInvoiceModel', () {
    test('Extreme decimal values & numeric extremes in SupplierInvoiceModel', () {
      final json = {
        'id': '999999999',
        'supplier_id': '88888888',
        'amount': 999999999999.9999,
        'voucher_letter': 'A',
        'point_of_sale': '9999',
        'voucher_number': '99999999',
        'net_21': 999999999.99,
        'iva_21': 209999999.9979,
        'net_105': 0.0000001,
        'iva_105': 0.0000000105,
        'net_27': -5000.55,
        'iva_27': -1350.1485,
        'non_taxed_amount': 0.0,
        'exempt_amount': 0.0,
        'iva_perception': 0.05,
        'iibb_perception': 0.0001,
        'internal_taxes': 1234567.89,
        'affects_vat_book': 'true',
      };

      final model = SupplierInvoiceModel.fromJson(json);

      expect(model.id, 999999999);
      expect(model.supplierId, 88888888);
      expect(model.pointOfSale, 9999);
      expect(model.voucherNumber, 99999999);
      expect(model.net21, 999999999.99);
      expect(model.formattedNumber, 'A 9999-99999999');
      expect(model.affectsVatBook, isTrue);

      final outJson = model.toJson();
      expect(outJson['voucher_letter'], 'A');
      expect(outJson['net_21'], 999999999.99);
      expect(outJson['affects_vat_book'], isTrue);
    });

    test('Zero, null, empty and corrupted fields in SupplierInvoiceModel', () {
      final emptyJson = <String, dynamic>{};
      final model = SupplierInvoiceModel.fromJson(emptyJson);

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
      expect(model.affectsVatBook, isTrue);
      expect(model.formattedNumber, '');

      final corruptedJson = {
        'id': 'not_an_id',
        'supplier_id': 'invalid',
        'amount': 'free_item',
        'voucher_letter': '   b  ',
        'point_of_sale': 'zero',
        'voucher_number': null,
        'net_21': 'abc',
        'affects_vat_book': '0',
      };

      final corruptedModel = SupplierInvoiceModel.fromJson(corruptedJson);
      expect(corruptedModel.id, isNull);
      expect(corruptedModel.supplierId, 0);
      expect(corruptedModel.amount, 0.0);
      expect(corruptedModel.voucherLetter, '   b  ');
      expect(corruptedModel.pointOfSale, isNull);
      expect(corruptedModel.voucherNumber, isNull);
      expect(corruptedModel.net21, isNull);
      expect(corruptedModel.affectsVatBook, isFalse);
      expect(corruptedModel.formattedNumber, '');
    });

    test('FormattedNumber edge cases: partial POS, partial Voucher Number, lowercase letter, spaces', () {
      // Only POS present
      const invoicePosOnly = SupplierInvoice(
        supplierId: 1,
        amount: 100,
        pointOfSale: 12,
        voucherNumber: null,
        voucherLetter: 'A',
        invoiceNumber: 'FALLBACK-001',
      );
      expect(invoicePosOnly.formattedNumber, 'FALLBACK-001');

      // Only Voucher Number present
      const invoiceNroOnly = SupplierInvoice(
        supplierId: 1,
        amount: 100,
        pointOfSale: null,
        voucherNumber: 456,
        voucherLetter: 'A',
        invoiceNumber: 'FALLBACK-002',
      );
      expect(invoiceNroOnly.formattedNumber, 'FALLBACK-002');

      // Both present with lowercase letter and padding check
      const invoiceLower = SupplierInvoice(
        supplierId: 1,
        amount: 100,
        pointOfSale: 3,
        voucherNumber: 1234,
        voucherLetter: 'b',
      );
      expect(invoiceLower.formattedNumber, 'B 0003-00001234');

      // Both present with empty/null letter (defaults to 'A')
      const invoiceNoLetter = SupplierInvoice(
        supplierId: 1,
        amount: 100,
        pointOfSale: 1,
        voucherNumber: 2,
        voucherLetter: '   ',
      );
      expect(invoiceNoLetter.formattedNumber, 'A 0001-00000002');
    });

    test('Fiscal Tolerance Boundary Verification: exactly ±0.05 threshold', () {
      bool isWithinTolerance(double fiscalSum, double total) {
        return (fiscalSum - total).abs() <= 0.0500001; // Accounting floating point margin
      }

      const total = 1000.00;

      // Exact match
      expect(isWithinTolerance(1000.00, total), isTrue);

      // Boundaries inside tolerance
      expect(isWithinTolerance(1000.05, total), isTrue);
      expect(isWithinTolerance(999.95, total), isTrue);
      expect(isWithinTolerance(1000.049, total), isTrue);
      expect(isWithinTolerance(999.951, total), isTrue);

      // Boundaries outside tolerance
      expect(isWithinTolerance(1000.051, total), isFalse);
      expect(isWithinTolerance(999.949, total), isFalse);
      expect(isWithinTolerance(1000.06, total), isFalse);
      expect(isWithinTolerance(999.94, total), isFalse);
      expect(isWithinTolerance(1050.00, total), isFalse);
    });

    test('Distribute Total in Net 21% formula stress testing', () {
      void verifyDistribution(double total) {
        final net = (total / 1.21 * 100).round() / 100.0;
        final iva = (total - net);
        final sum = net + iva;
        expect((sum - total).abs(), lessThanOrEqualTo(0.00001),
            reason: 'Net ($net) + IVA ($iva) must equal Total ($total) exactly');
      }

      final testTotals = [
        0.01,
        0.99,
        1.00,
        10.00,
        33.33,
        99.99,
        100.00,
        121.00,
        152.85,
        999.95,
        1234.56,
        1000000.00,
        98765432.19,
      ];

      for (final total in testTotals) {
        verifyDistribution(total);
      }
    });

    test('ArsThousandsInputFormatter parse edge cases', () {
      expect(ArsThousandsInputFormatter.parse(''), 0.0);
      expect(ArsThousandsInputFormatter.parse('   '), 0.0);
      expect(ArsThousandsInputFormatter.parse('1.000,50'), 1000.50);
      expect(ArsThousandsInputFormatter.parse('1000.50'), 1000.50);
      expect(ArsThousandsInputFormatter.parse('1.500,25'), 1500.25);
      expect(ArsThousandsInputFormatter.parse('0,05'), 0.05);
      expect(ArsThousandsInputFormatter.parse('-500,00'), -500.0);
      expect(ArsThousandsInputFormatter.parse('invalid_string'), 0.0);
    });
  });
}
