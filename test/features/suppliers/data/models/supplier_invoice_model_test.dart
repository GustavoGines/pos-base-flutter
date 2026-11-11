import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/suppliers/data/models/supplier_invoice_model.dart';
import 'package:frontend_desktop/features/suppliers/domain/entities/supplier_invoice.dart';

void main() {
  group('SupplierInvoice & SupplierInvoiceModel Fiscal Tests', () {
    test('fromJson deserializes all 15 fiscal fields properly', () {
      final json = {
        'id': 42,
        'supplier_id': 7,
        'supplier_name': 'Distribuidora Central S.A.',
        'type': 'invoice',
        'status': 'pending',
        'amount': 152850.50,
        'invoice_number': '0001-00045678',
        'voucher_letter': 'A',
        'point_of_sale': 1,
        'voucher_number': 45678,
        'net_21': 100000.0,
        'iva_21': 21000.0,
        'net_105': 20000.0,
        'iva_105': 2100.0,
        'net_27': 5000.0,
        'iva_27': 1350.0,
        'non_taxed_amount': 1500.0,
        'exempt_amount': 900.0,
        'iva_perception': 1000.0,
        'iibb_perception': 0.50,
        'internal_taxes': 0.0,
        'affects_vat_book': true,
      };

      final model = SupplierInvoiceModel.fromJson(json);

      expect(model.id, 42);
      expect(model.supplierId, 7);
      expect(model.voucherLetter, 'A');
      expect(model.pointOfSale, 1);
      expect(model.voucherNumber, 45678);
      expect(model.net21, 100000.0);
      expect(model.iva21, 21000.0);
      expect(model.net105, 20000.0);
      expect(model.iva105, 2100.0);
      expect(model.net27, 5000.0);
      expect(model.iva27, 1350.0);
      expect(model.nonTaxedAmount, 1500.0);
      expect(model.exemptAmount, 900.0);
      expect(model.ivaPerception, 1000.0);
      expect(model.iibbPerception, 0.50);
      expect(model.internalTaxes, 0.0);
      expect(model.affectsVatBook, isTrue);
      expect(model.formattedNumber, 'A 0001-00045678');
    });

    test('toJson serializes fiscal fields with snake_case keys', () {
      const invoice = SupplierInvoiceModel(
        id: 10,
        supplierId: 3,
        amount: 1210.0,
        voucherLetter: 'A',
        pointOfSale: 2,
        voucherNumber: 99,
        net21: 1000.0,
        iva21: 210.0,
        affectsVatBook: true,
      );

      final json = invoice.toJson();

      expect(json['voucher_letter'], 'A');
      expect(json['point_of_sale'], 2);
      expect(json['voucher_number'], 99);
      expect(json['net_21'], 1000.0);
      expect(json['iva_21'], 210.0);
      expect(json['affects_vat_book'], isTrue);
    });

    test('formattedNumber falls back to legacy invoiceNumber when pointOfSale is null', () {
      const invoice = SupplierInvoice(
        supplierId: 1,
        amount: 500.0,
        invoiceNumber: 'FAC-LEGACY-001',
      );

      expect(invoice.formattedNumber, 'FAC-LEGACY-001');
    });

    test('backward compatibility: null fiscal fields parse gracefully', () {
      final json = {
        'id': 1,
        'supplier_id': 2,
        'amount': 2500.0,
      };

      final model = SupplierInvoiceModel.fromJson(json);

      expect(model.voucherLetter, isNull);
      expect(model.pointOfSale, isNull);
      expect(model.voucherNumber, isNull);
      expect(model.net21, isNull);
      expect(model.affectsVatBook, isTrue);
      expect(model.formattedNumber, '');
    });

    test('copyWith properly overrides fiscal fields', () {
      const original = SupplierInvoice(
        supplierId: 1,
        amount: 1000.0,
        voucherLetter: 'B',
        nonTaxedAmount: 1000.0,
      );

      final updated = original.copyWith(
        voucherLetter: 'A',
        net21: 826.45,
        iva21: 173.55,
        nonTaxedAmount: 0.0,
      );

      expect(updated.voucherLetter, 'A');
      expect(updated.net21, 826.45);
      expect(updated.iva21, 173.55);
      expect(updated.nonTaxedAmount, 0.0);
      expect(original.voucherLetter, 'B');
    });
  });
}
