import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/sales_history/domain/entities/sale_record.dart';

void main() {
  group('SaleRecord & SaleItemRecord Savings & Reprint Tests', () {
    test('parses product.selling_price, offers, tendered_amount and change_amount correctly', () {
      final json = {
        'id': 79,
        'total': '2155120.00',
        'shipping_cost': '0.00',
        'total_surcharge': '0.00',
        'tendered_amount': '1200000.00',
        'change_amount': '44880.00',
        'status': 'completed',
        'created_at': '2026-10-30T21:25:05.000000Z',
        'items': [
          {
            'id': 105,
            'sale_id': 79,
            'product_id': 267,
            'product_name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
            'quantity': '1.000',
            'unit_price': '2155120.00',
            'subtotal': '2155120.00',
            'iva_rate': '21.00',
            'product': {
              'id': 267,
              'name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
              'internal_code': 'G3-1455',
              'selling_price': '2693900.00',
              'is_sold_by_weight': false,
              'offers': [
                {
                  'id': 3,
                  'name': 'PLAY 5 OFF',
                  'period_type': 'weekly',
                  'discount_percentage': '20.00',
                }
              ],
            },
          }
        ],
        'payments': [
          {
            'id': 1,
            'payment_method_id': 1,
            'base_amount': '1155120.00',
            'surcharge_amount': '0.00',
            'total_amount': '1155120.00',
            'payment_method': {
              'id': 1,
              'name': 'Efectivo',
              'code': 'efectivo',
              'is_cash': true,
            }
          },
          {
            'id': 2,
            'payment_method_id': 2,
            'base_amount': '1000000.00',
            'surcharge_amount': '0.00',
            'total_amount': '1000000.00',
            'payment_method': {
              'id': 2,
              'name': 'Cuenta Corriente',
              'code': 'cuenta_corriente',
              'is_cash': false,
            }
          }
        ],
      };

      final sale = SaleRecord.fromJson(json);

      expect(sale.id, equals(79));
      expect(sale.total, equals(2155120.0));
      expect(sale.tenderedAmount, equals(1200000.0));
      expect(sale.changeAmount, equals(44880.0));
      expect(sale.hasSavings, isTrue);
      expect(sale.totalSavings, closeTo(538780.0, 0.01));
      expect(sale.subtotalList, closeTo(2693900.0, 0.01));

      final item = sale.items.first;
      expect(item.regularPrice, equals(2693900.0));
      expect(item.unitPrice, equals(2155120.0));
      expect(item.hasDiscount, isTrue);
      expect(item.discountSavings, closeTo(538780.0, 0.01));
      expect(item.discountLabel, equals('Oferta Semanal'));
    });
  });
}
