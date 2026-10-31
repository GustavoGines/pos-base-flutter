import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/utils/a4_split_pdf_service.dart';
import 'package:frontend_desktop/features/logistics/services/delivery_note_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A4SplitPdfService — Comprobante No Fiscal (X) & Split Remito (A4 y Letter)', () {
    Map<String, dynamic> buildSampleSale({int itemCount = 3, bool isFiscal = false}) {
      return {
        'id': 452,
        'created_at': '2026-10-30T14:30:00.000000Z',
        'total': itemCount * 1500.50 + 500.0,
        'shipping_cost': 500.0,
        'surcharge_amount': 150.25,
        'iibb_perception_amount': 45.0,
        'tendered_amount': (itemCount * 1500.50) + 1000.0,
        'change_amount': 350.0,
        'requires_dispatch': true,
        'delivery_address': 'Av. Siempreviva 742, CABA',
        'customer_name': 'Constructora del Sur SRL',
        'customer': {
          'name': 'Constructora del Sur SRL',
          'document_number': '30712345678',
          'tax_condition': 'IVA Responsable Inscripto',
          'address': 'Av. Siempreviva 742, CABA',
        },
        'electronic_invoice': isFiscal
            ? {
                'voucher_letter': 'B',
                'voucher_type': 6,
                'formatted_number': '00001-00000452',
                'cae': '74382910492819',
                'cae_expiration': '2026-11-09T03:00:00.000000Z',
                'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=eyJ2ZXIiOjF9',
                'net_amount': 3720.25,
                'iva_amount': 781.25,
              }
            : null,
        'items': List.generate(
          itemCount,
          (i) => {
            'id': i + 1,
            'product_name': 'Cemento Portland Normal 50Kg Lote #${i + 1}',
            'quantity': i % 2 == 0 ? 2.0 : 1.5,
            'unit_price': 1500.50,
            'subtotal': (i % 2 == 0 ? 2.0 : 1.5) * 1500.50,
            'product': {
              'name': 'Cemento Portland Normal 50Kg Lote #${i + 1}',
              'internal_code': 'CEM-${(i + 1).toString().padLeft(3, '0')}',
              'is_sold_by_weight': i % 2 != 0,
            },
          },
        ),
        'payments': [
          {
            'amount': (itemCount * 1500.50) / 2,
            'payment_method': {'name': 'Efectivo'},
          },
          {
            'amount': (itemCount * 1500.50) / 2 + 650.25,
            'payment_method': {'name': 'Transferencia Bancaria'},
          },
        ],
      };
    }

    test('generateA4SingleReceipt generates valid PDF on A4 and Letter for small order (3 items)', () async {
      final sale = buildSampleSale(itemCount: 3);

      final bytesA4 = await A4SplitPdfService.generateA4SingleReceipt(
        sale: sale,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42, Buenos Aires',
        phone: '011-4555-9999',
        cuit: '30-71234567-8',
        taxCondition: 'IVA Responsable Inscripto',
        iibb: '901-123456-7',
        activityStartDate: '01/03/2020',
        vendorName: 'Carlos Gómez',
        paperSize: 'a4',
      );
      expect(bytesA4, isNotEmpty);

      final bytesLetter = await A4SplitPdfService.generateA4SingleReceipt(
        sale: sale,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42, Buenos Aires',
        phone: '011-4555-9999',
        cuit: '30-71234567-8',
        taxCondition: 'IVA Responsable Inscripto',
        iibb: '901-123456-7',
        activityStartDate: '01/03/2020',
        vendorName: 'Carlos Gómez',
        paperSize: 'letter',
      );
      expect(bytesLetter, isNotEmpty);
    });

    test('generateA4SingleReceipt paginates 45 items smoothly without TooManyPagesException on A4 and Letter', () async {
      final largeSale = buildSampleSale(itemCount: 45);

      final bytesA4 = await A4SplitPdfService.generateA4SingleReceipt(
        sale: largeSale,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42, Buenos Aires',
        phone: '011-4555-9999',
        cuit: '30-71234567-8',
        vendorName: 'Carlos Gómez',
        paperSize: 'a4',
      );
      expect(bytesA4, isNotEmpty);

      final bytesLetter = await A4SplitPdfService.generateA4SingleReceipt(
        sale: largeSale,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42, Buenos Aires',
        phone: '011-4555-9999',
        cuit: '30-71234567-8',
        vendorName: 'Carlos Gómez',
        paperSize: 'letter',
      );
      expect(bytesLetter, isNotEmpty);
    });

    test('generateA4SplitReceiptAndDispatch works in Split mode (<=5 items) and MultiPage mode (>5 items)', () async {
      final smallSale = buildSampleSale(itemCount: 4);
      final smallNote = {
        'id': 88,
        'status': 'pending',
        'items': smallSale['items'],
      };

      final splitBytes = await A4SplitPdfService.generateA4SplitReceiptAndDispatch(
        sale: smallSale,
        deliveryNote: smallNote,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42',
        phone: '011-4555-9999',
        cuit: '30-71234567-8',
        vendorName: 'Carlos Gómez',
        paperSize: 'a4',
      );
      expect(splitBytes, isNotEmpty);

      final largeSale = buildSampleSale(itemCount: 25);
      final largeNote = {
        'id': 89,
        'status': 'pending',
        'items': largeSale['items'],
      };

      final multiPageBytes = await A4SplitPdfService.generateA4SplitReceiptAndDispatch(
        sale: largeSale,
        deliveryNote: largeNote,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42',
        phone: '011-4555-9999',
        cuit: '30-71234567-8',
        vendorName: 'Carlos Gómez',
        paperSize: 'letter',
      );
      expect(multiPageBytes, isNotEmpty);
    });
  });

  group('DeliveryNotePdfService — Remitos (R) y Órdenes de Retiro (X) en A4 y Letter', () {
    Map<String, dynamic> buildSampleDeliveryNote({int itemCount = 3, String status = 'pending'}) {
      return {
        'id': 125,
        'status': status,
        'created_at': '2026-10-30T15:00:00.000000Z',
        'sale': {
          'id': 452,
          'delivery_address': 'Av. Belgrano 1250, Piso 2',
          'customer': {
            'name': 'Obras Civiles Argentinas SA',
            'document_number': '30-65432198-7',
          },
        },
        'items': List.generate(
          itemCount,
          (i) => {
            'id': i + 1,
            'quantity_purchased': 10.0,
            'quantity_delivered': status == 'pending' ? 0.0 : (status == 'partial' ? 4.0 : 10.0),
            'product': {
              'name': 'Hierro Torsionado 8mm Barra 12m #${i + 1}',
              'internal_code': 'HIE-${(i + 1).toString().padLeft(3, '0')}',
              'is_sold_by_weight': false,
            },
          },
        ),
      };
    }

    test('generates Orden de Retiro (pending) and Remito de Despacho (partial/delivered) in Split mode on A4 and Letter', () async {
      final pendingNote = buildSampleDeliveryNote(itemCount: 3, status: 'pending');
      final pendingBytes = await DeliveryNotePdfService.generatePdf(
        note: pendingNote,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42',
        businessPhone: '011-4555-9999',
        businessTaxId: '30-71234567-8',
        vendorName: 'Vendedor 1',
        dispatcherName: 'Depósito Central',
        paperSize: 'a4',
      );
      expect(pendingBytes, isNotEmpty);

      final dispatchNote = buildSampleDeliveryNote(itemCount: 4, status: 'partial');
      final dispatchBytes = await DeliveryNotePdfService.generatePdf(
        note: dispatchNote,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42',
        businessPhone: '011-4555-9999',
        businessTaxId: '30-71234567-8',
        deliveredNow: {1: 3.0, 2: 6.0},
        vendorName: 'Vendedor 1',
        dispatcherName: 'Depósito Central',
        paperSize: 'letter',
      );
      expect(dispatchBytes, isNotEmpty);
    });

    test('paginates large wholesale Remito (30 items) smoothly on A4 and Letter', () async {
      final wholesaleNote = buildSampleDeliveryNote(itemCount: 30, status: 'delivered');
      final bytesA4 = await DeliveryNotePdfService.generatePdf(
        note: wholesaleNote,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42',
        businessPhone: '011-4555-9999',
        businessTaxId: '30-71234567-8',
        vendorName: 'Vendedor 1',
        dispatcherName: 'Depósito Central',
        paperSize: 'a4',
      );
      expect(bytesA4, isNotEmpty);

      final bytesLetter = await DeliveryNotePdfService.generatePdf(
        note: wholesaleNote,
        businessName: 'Corralón El Constructor SA',
        businessAddress: 'Ruta 3 Km 42',
        businessPhone: '011-4555-9999',
        businessTaxId: '30-71234567-8',
        vendorName: 'Vendedor 1',
        dispatcherName: 'Depósito Central',
        paperSize: 'letter',
      );
      expect(bytesLetter, isNotEmpty);
    });

    test('generateA4SingleReceipt correctly processes sales with offers and discounts', () async {
      final saleWithOffers = {
        'id': 75,
        'created_at': '2026-10-30T17:19:00.000000Z',
        'total': 2155120.0,
        'subtotal_list': 2693900.0,
        'discount_amount': 538780.0,
        'discount_label': 'Oferta Semanal',
        'items': [
          {
            'product_name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
            'quantity': 1.0,
            'unit_price': 2155120.0,
            'regular_price': 2693900.0,
            'subtotal': 2155120.0,
            'discount_amount': 538780.0,
            'discount_label': 'Oferta Semanal',
            'has_discount': true,
            'product': {
              'name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
              'internal_code': 'G3-1455',
              'selling_price': 2693900.0,
            },
          },
        ],
        'payments': [
          {'name': 'Efectivo', 'amount': 2155120.0},
        ],
        'tendered_amount': 2155120.0,
        'change_amount': 0.0,
      };

      final pdfBytes = await A4SplitPdfService.generateA4SingleReceipt(
        sale: saleWithOffers,
        businessName: 'DEV4U',
        businessAddress: 'Jujuy 152',
        phone: '3704787285',
        cuit: '20-39606329-9',
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('renders business logo in left emitter header across SingleReceipt, SplitReceiptAndDispatch, and DeliveryNote (A4 & Letter)', () async {
      final Uint8List sampleLogo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      final sale = {
        'id': 80,
        'created_at': '2026-10-30T20:30:00.000000Z',
        'total': 2155120.0,
        'subtotal_list': 2693900.0,
        'discount_amount': 538780.0,
        'requires_dispatch': true,
        'items': List.generate(
          5,
          (i) => {
            'id': i + 1,
            'product_name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB #${i + 1}',
            'quantity': 1.0,
            'unit_price': 2155120.0,
            'regular_price': 2693900.0,
            'discount_amount': 538780.0,
            'discount_label': 'Oferta Semanal',
            'subtotal': 2155120.0,
            'product': {
              'name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB #${i + 1}',
              'internal_code': 'PS5-00${i + 1}',
              'is_sold_by_weight': false,
              'selling_price': 2693900.0,
            },
          },
        ),
        'payments': [
          {'name': 'Efectivo', 'amount': 2155120.0},
        ],
        'tendered_amount': 2155120.0,
        'change_amount': 0.0,
      };
      final note = {
        'id': 80,
        'status': 'delivered',
        'sale': sale,
        'items': (sale['items'] as List)
            .map((it) => {
                  ...it as Map<String, dynamic>,
                  'quantity_purchased': 1.0,
                  'quantity_delivered': 1.0,
                })
            .toList(),
      };

      for (final size in ['a4', 'letter']) {
        final singleBytes = await A4SplitPdfService.generateA4SingleReceipt(
          sale: sale,
          businessName: 'DEV4U',
          businessAddress: 'Jujuy 152',
          phone: '3704787285',
          cuit: '20-39606329-9',
          taxCondition: 'IVA Responsable Inscripto',
          iibb: '20-39606329-9',
          activityStartDate: '20/03/2022',
          paperSize: size,
          logoBytes: sampleLogo,
        );
        expect(singleBytes, isNotEmpty);

        final splitBytes = await A4SplitPdfService.generateA4SplitReceiptAndDispatch(
          sale: sale,
          deliveryNote: note,
          businessName: 'DEV4U',
          businessAddress: 'Jujuy 152',
          phone: '3704787285',
          cuit: '20-39606329-9',
          taxCondition: 'IVA Responsable Inscripto',
          iibb: '20-39606329-9',
          activityStartDate: '20/03/2022',
          paperSize: size,
          logoBytes: sampleLogo,
        );
        expect(splitBytes, isNotEmpty);

        final remitoBytes = await DeliveryNotePdfService.generatePdf(
          note: note,
          businessName: 'DEV4U',
          businessAddress: 'Jujuy 152',
          businessPhone: '3704787285',
          businessTaxId: '20-39606329-9',
          paperSize: size,
          logoBytes: sampleLogo,
        );
        expect(remitoBytes, isNotEmpty);
      }
    });
  });
}
