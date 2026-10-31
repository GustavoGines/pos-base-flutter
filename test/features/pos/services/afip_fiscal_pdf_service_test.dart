import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:frontend_desktop/core/utils/afip_fiscal_pdf_service.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'afip_fiscal_pdf_adversarial_test.dart' as adversarial_pdf;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  adversarial_pdf.main();

  group('Milestone M2: AfipFiscalPdfService - AFIP RG 1415 & 4892 Classical Layout Tests', () {
    const testCae = '74382910492819';
    const testExpiration = '2026-10-17';
    const testFormattedExpiration = '17/10/2026';
    const testQrUrl = 'https://www.afip.gob.ar/fe/qr/?p=eyJ2ZXIiOjEsImZlY2hhIjoiMjAyNi0xMC0wNyJ9';

    final sampleBusinessSettings = const BusinessSettings(
      companyName: 'Supermercado Central S.A.',
      taxId: '30-71458923-9',
      address: 'Av. Corrientes 1234, CABA',
      phone: '011-4567-8900',
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: Factura A (Voucher Letter 'A', 'COD. 01', CAE, QR Code & Net Breakdown)
    // ─────────────────────────────────────────────────────────────────────────
    test('Factura A: verifies presence of "A", "COD. 01", CAE number, and QR code pw.BarcodeWidget', () async {
      final sale = {
        'id': 101,
        'created_at': '2026-10-07T12:00:00Z',
        'items': [
          {
            'product_name': 'Insumo Industrial A',
            'quantity': 2,
            'unit_price': 6050.0, // 5000 neto + 21% IVA = 6050
            'subtotal': 12100.0,
            'iva_rate': 21.0,
            'net_amount': 10000.0,
          },
        ],
        'total': 12100.0,
      };

      final electronicInvoice = {
        'voucher_type': 1,
        'voucher_letter': 'A',
        'point_of_sale': 1,
        'voucher_number': 124,
        'formatted_number': '00001-00000124',
        'cae': testCae,
        'cae_expiration': testExpiration,
        'doc_type': 80,
        'doc_number': '30-99887766-5',
        'receiver_name': 'Comercializadora Mayorista S.R.L.',
        'receiver_address': 'Calle Falsa 456, Rosario',
        'receiver_tax_condition': 'IVA Responsable Inscripto',
        'net_amount': 10000.0,
        'iva_amount': 2100.0,
        'total_amount': 12100.0,
        'iva_breakdown': [
          {'id': 5, 'base_imp': 10000.0, 'importe': 2100.0},
        ],
        'qr_data': testQrUrl,
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleBusinessSettings,
        paperSize: 'a4',
        compress: false,
      );

      // 1. AST Node Inspection: Text nodes
      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

      expect(plainTexts.contains('A'), isTrue, reason: 'Voucher letter box must display "A"');
      expect(plainTexts.contains('COD. 01'), isTrue, reason: 'Voucher letter box must display "COD. 01"');
      expect(plainTexts.any((t) => t.contains('FACTURA A')), isTrue, reason: 'Header title must be "FACTURA A"');
      expect(plainTexts.any((t) => t.contains('00001-00000124')), isTrue, reason: 'Formatted number must be present');
      expect(plainTexts.any((t) => t.contains(testCae)), isTrue, reason: 'CAE must be present in text');
      expect(plainTexts.any((t) => t.contains(testFormattedExpiration)), isTrue, reason: 'CAE expiration must be present in text');
      expect(plainTexts.any((t) => t.contains('Comprobante Autorizado por AFIP (RG 4892)')), isTrue,
          reason: 'AFIP RG 4892 legend must be present');

      // Table & Totals discrimination for Factura A
      expect(plainTexts.contains('PRECIO UNIT. (NETO)'), isTrue, reason: 'Factura A must show Net Unit Price header');
      expect(plainTexts.contains('% IVA'), isTrue, reason: 'Factura A must show % IVA aliquot header');
      expect(plainTexts.contains('SUBTOTAL NETO'), isTrue, reason: 'Factura A must show Subtotal Neto header');
      expect(plainTexts.any((t) => t.contains('Subtotal Neto Gravado:')), isTrue, reason: 'Totals must show Net Amount');
      expect(plainTexts.any((t) => t.contains('IVA 21%:')), isTrue, reason: 'Totals must show IVA 21% breakdown');

      // 2. AST Node Inspection: Barcode nodes
      final barcodeWidgets = AfipFiscalPdfService.findWidgets<pw.BarcodeWidget>(doc);
      expect(barcodeWidgets.length, equals(1), reason: 'Document must contain exactly 1 QR barcode widget');
      final qrWidget = barcodeWidgets.first;
      expect(qrWidget.barcode.name, equals('QR-Code'));
      expect(qrWidget.dataString, equals(testQrUrl));

      // 3. Uncompressed Binary Byte Inspection
      final pdfBytes = await doc.save();
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
      final decodedPdf = latin1.decode(pdfBytes);
      expect(decodedPdf.contains(testCae), isTrue, reason: 'Raw PDF stream must contain CAE');
      expect(decodedPdf.contains('COD.'), isTrue, reason: 'Raw PDF stream must contain COD.');
      expect(decodedPdf.contains('FACTURA'), isTrue, reason: 'Raw PDF stream must contain FACTURA');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: Factura B (Voucher Letter 'B', 'COD. 06', CAE, QR Code & Final Consumer)
    // ─────────────────────────────────────────────────────────────────────────
    test('Factura B: verifies presence of "B", "COD. 06", CAE number, and QR code', () async {
      final sale = {
        'id': 102,
        'created_at': '2026-10-07T14:30:00Z',
        'items': [
          {
            'product_name': 'Taladro Percutor 750W',
            'quantity': 1,
            'unit_price': 45000.0,
            'subtotal': 45000.0,
          },
        ],
        'total': 45000.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'point_of_sale': 2,
        'voucher_number': 850,
        'formatted_number': '00002-00000850',
        'cae': '65432109876543',
        'cae_expiration': '2026-10-20',
        'doc_type': 96,
        'doc_number': '28475932',
        'receiver_name': 'Juan Pérez',
        'receiver_address': 'San Martín 789',
        'receiver_tax_condition': 'Consumidor Final',
        'total_amount': 45000.0,
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=TEST_B_QR',
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleBusinessSettings,
        paperSize: 'a4',
        compress: false,
      );

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

      expect(plainTexts.contains('B'), isTrue, reason: 'Voucher letter box must display "B"');
      expect(plainTexts.contains('COD. 06'), isTrue, reason: 'Voucher letter box must display "COD. 06"');
      expect(plainTexts.any((t) => t.contains('FACTURA B')), isTrue, reason: 'Header title must be "FACTURA B"');
      expect(plainTexts.any((t) => t.contains('65432109876543')), isTrue, reason: 'CAE must be present');
      expect(plainTexts.any((t) => t.contains('20/10/2026')), isTrue, reason: 'CAE expiration must be present');

      // Table for Factura B has standard (non-discriminated) columns
      expect(plainTexts.contains('PRECIO UNIT.'), isTrue);
      expect(plainTexts.contains('SUBTOTAL'), isTrue);

      // RG 5614 / Ley 27.743 Transparencia Fiscal al Consumidor must be present on Factura B
      expect(
        plainTexts.any((t) => t.contains('Régimen de Transparencia Fiscal al Consumidor (Ley 27.743)')),
        isTrue,
        reason: 'Factura B must display RG 5614 / Ley 27.743 legend',
      );
      expect(
        plainTexts.any((t) => t.contains('IVA Contenido:') && t.contains('Otros Impuestos Nacionales Indirectos:')),
        isTrue,
        reason: 'Factura B must display IVA Contenido and Otros Impuestos Nacionales Indirectos',
      );
      expect(
        plainTexts.any((t) => t.startsWith(r'$ ')),
        isTrue,
        reason: r'Currency values must use leading $ symbol (e.g. $ 45.000,00)',
      );

      final barcodeWidgets = AfipFiscalPdfService.findWidgets<pw.BarcodeWidget>(doc);
      expect(barcodeWidgets.length, equals(1));
      expect(barcodeWidgets.first.barcode.name, equals('QR-Code'));
      expect(barcodeWidgets.first.dataString, equals('https://www.afip.gob.ar/fe/qr/?p=TEST_B_QR'));

      final pdfBytes = await doc.save();
      final decodedPdf = latin1.decode(pdfBytes);
      expect(decodedPdf.contains('65432109876543'), isTrue);
      expect(decodedPdf.contains('COD.'), isTrue);
      expect(decodedPdf.contains('FACTURA'), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: Factura C (Voucher Letter 'C', 'COD. 11', CAE, QR Code & Monotributo)
    // ─────────────────────────────────────────────────────────────────────────
    test('Factura C: verifies presence of "C", "COD. 11", CAE number, and QR code', () async {
      final sale = {
        'id': 103,
        'created_at': '2026-10-07T16:00:00Z',
        'items': [
          {
            'product_name': 'Servicio de Consultoría',
            'quantity': 1,
            'unit_price': 15000.0,
            'subtotal': 15000.0,
          },
        ],
        'total': 15000.0,
      };

      final electronicInvoice = {
        'voucher_type': 11,
        'voucher_letter': 'C',
        'point_of_sale': 1,
        'voucher_number': 35,
        'formatted_number': '00001-00000035',
        'cae': '88776655443322',
        'cae_expiration': '2026-10-25',
        'doc_type': 99,
        'doc_number': '0',
        'receiver_name': 'Consumidor Final',
        'receiver_tax_condition': 'Consumidor Final',
        'total_amount': 15000.0,
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=TEST_C_QR',
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleBusinessSettings,
        paperSize: 'a4',
        compress: false,
      );

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

      expect(plainTexts.contains('C'), isTrue, reason: 'Voucher letter box must display "C"');
      expect(plainTexts.contains('COD. 11'), isTrue, reason: 'Voucher letter box must display "COD. 11"');
      expect(plainTexts.any((t) => t.contains('FACTURA C')), isTrue);
      expect(plainTexts.any((t) => t.contains('88776655443322')), isTrue);
      expect(plainTexts.any((t) => t.contains('25/10/2026')), isTrue);
      expect(
        plainTexts.any((t) => t.contains('Cond. frente al IVA: Responsable Monotributo')),
        isTrue,
        reason: 'Factura C must enforce coherent issuer condition Responsable Monotributo',
      );
      expect(
        plainTexts.any((t) => t.contains('Régimen de Transparencia Fiscal al Consumidor')),
        isFalse,
        reason: 'Factura C (Monotributo) is exempt from RG 5614 IVA Contenido legend',
      );

      final barcodeWidgets = AfipFiscalPdfService.findWidgets<pw.BarcodeWidget>(doc);
      expect(barcodeWidgets.length, equals(1));
      expect(barcodeWidgets.first.barcode.name, equals('QR-Code'));
      expect(barcodeWidgets.first.dataString, equals('https://www.afip.gob.ar/fe/qr/?p=TEST_C_QR'));

      final pdfBytes = await doc.save();
      final decodedPdf = latin1.decode(pdfBytes);
      expect(decodedPdf.contains('88776655443322'), isTrue);
      expect(decodedPdf.contains('COD.'), isTrue);
      expect(decodedPdf.contains('FACTURA'), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: Responsiveness on A4 and Letter (Zero Layout Exceptions)
    // ─────────────────────────────────────────────────────────────────────────
    test('responsiveness: builds cleanly without layout exceptions on both PdfPageFormat.a4 and PdfPageFormat.letter', () async {
      final sale = {
        'id': 104,
        'items': List.generate(5, (index) => {
          'product_name': 'Producto de Prueba #$index',
          'quantity': index + 1,
          'unit_price': (index + 1) * 100.0,
          'subtotal': (index + 1) * (index + 1) * 100.0,
        }),
        'total': 5500.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'cae': '11223344556677',
        'cae_expiration': '2026-10-30',
        'total_amount': 5500.0,
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=RESPONSIVE_TEST',
      };

      // 1. Verify A4 format
      final docA4 = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleBusinessSettings,
        paperSize: 'a4',
      );
      final bytesA4 = await docA4.save();
      expect(bytesA4.isNotEmpty, isTrue);
      expect(docA4.document.pdfPageList.pages.length, equals(1), reason: '5 items must fit on 1 A4 page');
      final pageA4 = docA4.document.pdfPageList.pages.first;
      expect(pageA4.pageFormat.width, closeTo(PdfPageFormat.a4.width, 0.1));
      expect(pageA4.pageFormat.height, closeTo(PdfPageFormat.a4.height, 0.1));

      // 2. Verify Letter format (49.89 pt shorter height)
      final docLetter = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleBusinessSettings,
        paperSize: 'letter',
      );
      final bytesLetter = await docLetter.save();
      expect(bytesLetter.isNotEmpty, isTrue);
      expect(docLetter.document.pdfPageList.pages.length, equals(1), reason: '5 items must fit on 1 Letter page without overflow');
      final pageLetter = docLetter.document.pdfPageList.pages.first;
      expect(pageLetter.pageFormat.width, closeTo(PdfPageFormat.letter.width, 0.1));
      expect(pageLetter.pageFormat.height, closeTo(PdfPageFormat.letter.height, 0.1));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 5: Multi-Page Scaling with Large Item Lists (25+ items)
    // ─────────────────────────────────────────────────────────────────────────
    test('multi-page scaling: handles large item lists (25+ items) smoothly across multiple pages', () async {
      const itemCount = 28;
      final sale = {
        'id': 105,
        'items': List.generate(itemCount, (i) => {
          'product_name': 'Artículo Extendido Detallado con Nombre Largo N° ${i + 1}',
          'quantity': 1,
          'unit_price': 150.0,
          'subtotal': 150.0,
        }),
        'total': itemCount * 150.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'cae': '99887766554433',
        'cae_expiration': '2026-10-31',
        'total_amount': itemCount * 150.0,
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=MULTIPAGE_TEST',
      };

      // Test on Letter (the more constraint-heavy paper size)
      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleBusinessSettings,
        paperSize: 'letter',
      );

      final bytes = await doc.save();
      expect(bytes.isNotEmpty, isTrue);
      // Large item list must automatically split across at least 2 pages
      expect(doc.document.pdfPageList.pages.length, greaterThanOrEqualTo(2),
          reason: '28 items must paginate gracefully across multiple pages');

      // Verify all items exist in the widget tree
      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();
      for (int i = 1; i <= itemCount; i++) {
        expect(plainTexts.any((t) => t.contains('N° $i')), isTrue,
            reason: 'Item $i must be rendered in the document');
      }

      // Verify QR and CAE are preserved
      final barcodeWidgets = AfipFiscalPdfService.findWidgets<pw.BarcodeWidget>(doc);
      expect(barcodeWidgets.length, equals(1));
      expect(plainTexts.any((t) => t.contains('99887766554433')), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 6: Fallback and Default Safety (Missing QR, Missing CUIT, Map Settings)
    // ─────────────────────────────────────────────────────────────────────────
    test('robustness: generates valid official QR URL and defaults when optional fields are omitted', () async {
      final sale = {
        'id': 106,
        'items': [
          {'product_name': 'Pan', 'quantity': 1.5, 'is_sold_by_weight': true, 'unit_price': 2000.0, 'subtotal': 3000.0},
        ],
        'total': 3000.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'cae': '12345678901234',
        // Omit qr_data to test on-the-fly AFIP QR URL generation
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: {
          'company_name': 'Panadería Don Juan',
          'cuit': '20-12345678-9',
          'address': 'Mitre 500',
        },
      );

      final barcodeWidgets = AfipFiscalPdfService.findWidgets<pw.BarcodeWidget>(doc);
      expect(barcodeWidgets.length, equals(1));
      expect(barcodeWidgets.first.dataString?.startsWith('https://www.afip.gob.ar/fe/qr/?p='), isTrue,
          reason: 'Must construct canonical AFIP RG 4892 QR URL if qr_data was not provided');

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();
      expect(plainTexts.any((t) => t.contains('PANADERÍA DON JUAN')), isTrue);
      expect(plainTexts.any((t) => t.contains('1.5')), isTrue, reason: 'Weight quantity 1.5 must be formatted');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 7: Async High-Level Method generateFiscalInvoice Produces Valid PDF
    // ─────────────────────────────────────────────────────────────────────────
    test('generateFiscalInvoice: produces valid PDF binary stream with %PDF magic header', () async {
      final sale = {
        'id': 107,
        'items': [{'name': 'Item Simple', 'quantity': 1, 'unit_price': 100.0, 'subtotal': 100.0}],
        'total': 100.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'cae': '77889900112233',
        'total_amount': 100.0,
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=MAGIC_BYTES_TEST',
      };

      final bytes = await AfipFiscalPdfService.generateFiscalInvoice(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleBusinessSettings,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.length, greaterThan(1000));
      expect(ascii.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 8: Factura B with Offers, Discounts & RG 5614 Precio s/imp - IVA Contenido
    // ─────────────────────────────────────────────────────────────────────────
    test('Factura B with offers & discounts: renders Precio s/imp - IVA Contenido, Subtotal Lista, Ahorro, and formatted CUIT', () async {
      final sale = {
        'id': 79,
        'created_at': '2026-10-30T18:25:00Z',
        'items': [
          {
            'product_name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
            'quantity': 1,
            'unit_price': 2155120.0,
            'regular_price': 2693900.0,
            'discount_amount': 538780.0,
            'discount_label': 'Oferta Semanal',
            'subtotal': 2155120.0,
            'iva_rate': 21.0,
          },
        ],
        'subtotal': 2155120.0,
        'total': 2155120.0,
        'discount_amount': 538780.0,
        'payments': [
          {'name': 'Efectivo', 'amount': 1155120.0},
          {'name': 'Cuenta Corriente', 'amount': 1000000.0},
        ],
        'tendered_amount': 1200000.0,
        'change_amount': 44880.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'point_of_sale': 1,
        'voucher_number': 2,
        'formatted_number': '00001-00000002',
        'cae': '86441036375060',
        'cae_expiration': '2026-11-09',
        'doc_type': 96,
        'doc_number': '39606329',
        'receiver_name': 'Gustavo Gines',
        'receiver_tax_condition': 'Consumidor Final',
        'net_amount': 1781090.91,
        'iva_amount': 374029.09,
        'total_amount': 2155120.0,
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: {
          'company_name': 'Dev4U',
          'cuit': '20396063299',
          'iibb': '20396063299',
          'address': 'Jujuy 152',
          'tax_condition': 'IVA Responsable Inscripto',
        },
        paperSize: 'a4',
        compress: false,
      );

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

      expect(plainTexts.any((t) => t.contains('CUIT: 20-39606329-9')), isTrue);
      expect(plainTexts.any((t) => t.contains('Ingresos Brutos: 20-39606329-9')), isTrue);
      expect(plainTexts.any((t) => t.contains('(Oferta Semanal) Precio Lista: \$ 2.693.900,00 (-\$ 538.780,00)')), isTrue);
      expect(plainTexts.any((t) => t.contains('Subtotal Lista: \$ 2.693.900,00')), isTrue);
      expect(plainTexts.any((t) => t.contains('Ahorro / Descuento: -\$ 538.780,00')), isTrue);
      expect(
        plainTexts.any((t) => t.contains('Precio s/imp: \$ 1.781.090,91 - IVA Contenido: \$ 374.029,09')),
        isTrue,
      );
      expect(plainTexts.any((t) => t.contains('Efectivo')), isTrue);
      expect(plainTexts.any((t) => t.contains('Cuenta Corriente')), isTrue);
    });

    test('renders split Factura Fiscal ARCA + Remito on A4 and Letter when deliveryNote is provided ("Se lo lleva AHORA")', () async {
      final sale = {
        'id': 84,
        'created_at': '2026-10-31T00:21:00',
        'items': [
          {
            'product_name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
            'quantity': 2,
            'unit_price': 2155120.0,
            'regular_price': 2693900.0,
            'discount_amount': 1077560.0,
            'discount_label': 'Oferta Semanal',
            'subtotal': 4310240.0,
            'iva_rate': 21.0,
            'product': {
              'name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
              'internal_code': 'PS5-PRO',
              'is_sold_by_weight': false,
            },
          },
        ],
        'subtotal': 4310240.0,
        'shipping_cost': 10000.0,
        'total': 4320240.0,
        'discount_amount': 1077560.0,
        'payments': [
          {'name': 'Efectivo', 'amount': 4320240.0},
        ],
        'tendered_amount': 4320240.0,
        'change_amount': 0.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'point_of_sale': 1,
        'voucher_number': 4,
        'formatted_number': '00001-00000004',
        'cae': '86441036399573',
        'cae_expiration': '2026-11-09',
        'doc_type': 96,
        'doc_number': '38823149',
        'receiver_name': 'Lorena Caballero',
        'receiver_address': 'Yrigoyen Hipolito 201',
        'receiver_tax_condition': 'Consumidor Final',
        'net_amount': 3570446.28,
        'iva_amount': 749793.72,
        'total_amount': 4320240.0,
      };

      final deliveryNote = {
        'id': 84,
        'status': 'delivered',
        'delivery_address': 'Yrigoyen Hipolito 201',
        'items': sale['items'],
      };

      final docA4 = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        deliveryNote: deliveryNote,
        businessSettings: {
          'company_name': 'Dev4U',
          'cuit': '20396063299',
          'iibb': '20396063299',
          'address': 'Jujuy 152',
          'tax_condition': 'IVA Responsable Inscripto',
        },
        paperSize: 'a4',
        compress: false,
      );

      final bytesA4 = await docA4.save();
      expect(bytesA4, isNotEmpty);

      final bytesLetter = await AfipFiscalPdfService.generateFiscalInvoice(
        sale: sale,
        electronicInvoice: electronicInvoice,
        deliveryNote: deliveryNote,
        businessSettings: {
          'company_name': 'Dev4U',
          'cuit': '20396063299',
          'iibb': '20396063299',
          'address': 'Jujuy 152',
          'tax_condition': 'IVA Responsable Inscripto',
        },
        paperSize: 'letter',
        compress: false,
      );
      expect(bytesLetter, isNotEmpty);

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(docA4);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

      expect(plainTexts.any((t) => t.contains('FACTURA B')), isTrue);
      expect(plainTexts.any((t) => t.contains('REMITO — ENTREGA INMEDIATA')), isTrue);
      expect(plainTexts.any((t) => t.contains('COD. 091')), isTrue);
      expect(plainTexts.any((t) => t.contains('Destinatario / Cliente: Lorena Caballero')), isTrue);
      expect(plainTexts.any((t) => t.contains('ENTREGADO EN EL ACTO')), isTrue);
      expect(plainTexts.any((t) => t.contains('RECIBÍ CONFORME')), isTrue);
    });
  });
}
