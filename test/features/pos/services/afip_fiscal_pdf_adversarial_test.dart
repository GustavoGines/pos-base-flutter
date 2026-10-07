import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:frontend_desktop/core/utils/afip_fiscal_pdf_service.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone M2: AfipFiscalPdfService - Adversarial Stress & Edge Cases', () {
    const testCae = '98765432101234';
    const testExpiration = '2026-12-31';

    final testBusinessSettings = const BusinessSettings(
      companyName: 'Adversarial Tech Corp S.A.',
      taxId: '30-79998888-4',
      address: 'Avenida Hipólito Yrigoyen 5678, Piso 4',
      phone: '011-9988-7766',
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Edge Case: 0 items (Empty Sales / Fee Only)
    // ─────────────────────────────────────────────────────────────────────────
    test('edge case: 0 items builds on A4 and Letter without throwing exceptions', () async {
      final sale = {
        'id': 201,
        'created_at': '2026-10-07T10:00:00Z',
        'items': <Map<String, dynamic>>[],
        'total': 0.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'cae': testCae,
        'cae_expiration': testExpiration,
        'total_amount': 0.0,
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=ZERO_ITEMS_TEST',
      };

      // Test A4
      final docA4 = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: testBusinessSettings,
        paperSize: 'a4',
      );
      final bytesA4 = await docA4.save();
      expect(bytesA4.isNotEmpty, isTrue);
      expect(ascii.decode(bytesA4.sublist(0, 5)), equals('%PDF-'));
      expect(docA4.document.pdfPageList.pages.length, equals(1));

      // Test Letter
      final docLetter = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: testBusinessSettings,
        paperSize: 'letter',
      );
      final bytesLetter = await docLetter.save();
      expect(bytesLetter.isNotEmpty, isTrue);
      expect(docLetter.document.pdfPageList.pages.length, equals(1));

      // AST verification: Letra 'B', CAE, QR
      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(docA4);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();
      expect(plainTexts.contains('B'), isTrue);
      expect(plainTexts.any((t) => t.contains(testCae)), isTrue);

      final barcodes = AfipFiscalPdfService.findWidgets<pw.BarcodeWidget>(docA4);
      expect(barcodes.length, equals(1));
      expect(barcodes.first.dataString, equals('https://www.afip.gob.ar/fe/qr/?p=ZERO_ITEMS_TEST'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Edge Case: 50+ items (Extreme Multi-Page Pagination)
    // ─────────────────────────────────────────────────────────────────────────
    test('edge case: 50+ items paginates smoothly on both A4 and Letter without overflow exceptions', () async {
      const totalItemCount = 55;
      final sale = {
        'id': 202,
        'items': List.generate(totalItemCount, (i) => {
          'product_name': 'Producto de Catálogo Industrial Código #${(i + 1).toString().padLeft(4, '0')}',
          'quantity': (i % 5) + 1,
          'unit_price': (i + 1) * 25.50,
          'subtotal': ((i % 5) + 1) * ((i + 1) * 25.50),
        }),
        'total': 150000.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'cae': testCae,
        'cae_expiration': testExpiration,
        'total_amount': 150000.0,
      };

      // Test A4 format
      final docA4 = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: testBusinessSettings,
        paperSize: 'a4',
      );
      final bytesA4 = await docA4.save();
      expect(bytesA4.isNotEmpty, isTrue);
      expect(docA4.document.pdfPageList.pages.length, greaterThanOrEqualTo(2),
          reason: '55 items must create at least 2 pages on A4');

      // Test Letter format (Letter is ~50pt shorter, more prone to overflow)
      final docLetter = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: testBusinessSettings,
        paperSize: 'letter',
      );
      final bytesLetter = await docLetter.save();
      expect(bytesLetter.isNotEmpty, isTrue);
      expect(docLetter.document.pdfPageList.pages.length, greaterThanOrEqualTo(2),
          reason: '55 items must create at least 2 pages on Letter');

      // Verify all items are rendered
      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(docLetter);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();
      for (int i = 1; i <= totalItemCount; i++) {
        final code = '#${i.toString().padLeft(4, '0')}';
        expect(plainTexts.any((t) => t.contains(code)), isTrue,
            reason: 'Item $code must be found in text nodes');
      }

      // Verify QR Code & CAE still present
      final barcodes = AfipFiscalPdfService.findWidgets<pw.BarcodeWidget>(docLetter);
      expect(barcodes.length, equals(1));
      expect(plainTexts.any((t) => t.contains(testCae)), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Edge Case: Very Long Product Descriptions (100+ chars, special characters)
    // ─────────────────────────────────────────────────────────────────────────
    test('edge case: very long product descriptions (100+ and 250+ chars) wrap cleanly without crashing', () async {
      final sale = {
        'id': 203,
        'items': [
          {
            'product_name': 'Tornillo Autoperforante Cabeza Hexagonal con Arandela de Neoprene Vulcano 14x2 Pulgadas para Techos Tinglados Estructuras Metálicas Pesadas con Tratamiento Galvanizado Antioxidante Extra Resistente según Norma IRAM',
            'quantity': 100,
            'unit_price': 15.0,
            'subtotal': 1500.0,
          },
          {
            'product_name': 'Cable Subterráneo IRAM 2178 Sintenax 4x10 mm² Cobre Electrolítico Rojo/Negro/Marrón/Celeste Aislación XLPE Vaina Exterior PVC Violeta Libre de Halógenos Resistencia al Fuego Certificado IRAM/TÜV Rheinland Rollo 50m Bobina Sellada con Precinto de Seguridad Fábrica',
            'quantity': 1,
            'unit_price': 85000.0,
            'subtotal': 85000.0,
          },
          {
            'product_name': 'SERVICIO TÉCNICO ESPECIALIZADO:\n- Diagnóstico de placa madre\n- Reballing de chip gráfico\n- Mantenimiento térmico con pasta Noctua NT-H1\n- Limpieza con alcohol isopropílico al 99.8%\n- Pruebas de estrés bajo carga por 48 horas seguidas',
            'quantity': 1,
            'unit_price': 45000.0,
            'subtotal': 45000.0,
          },
        ],
        'total': 131500.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'cae': testCae,
        'cae_expiration': testExpiration,
        'total_amount': 131500.0,
      };

      // Test on A4
      final docA4 = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: testBusinessSettings,
        paperSize: 'a4',
      );
      final bytesA4 = await docA4.save();
      expect(bytesA4.isNotEmpty, isTrue);

      // Test on Letter
      final docLetter = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: testBusinessSettings,
        paperSize: 'letter',
      );
      final bytesLetter = await docLetter.save();
      expect(bytesLetter.isNotEmpty, isTrue);

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(docLetter);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();
      expect(plainTexts.any((t) => t.contains('TORNILLO AUTOPERFORANTE')), isTrue);
      expect(plainTexts.any((t) => t.contains('CABLE SUBTERRÁNEO')), isTrue);
      expect(plainTexts.any((t) => t.contains('SERVICIO TÉCNICO ESPECIALIZADO')), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Edge Case: Prices with Many Decimals and Extreme Precision
    // ─────────────────────────────────────────────────────────────────────────
    test('edge case: high decimal precision and fractional quantities format gracefully', () async {
      final sale = {
        'id': 204,
        'items': [
          {
            'product_name': 'Gas Natural Comprimido GNC m³',
            'quantity': 14.857,
            'is_sold_by_weight': true,
            'unit_price': 345.6789,
            'subtotal': 5135.7514,
            'iva_rate': 21.0,
          },
          {
            'product_name': 'Micro Resistencia SMD 0805 10k',
            'quantity': 1000,
            'unit_price': 0.04567,
            'subtotal': 45.67,
            'iva_rate': 10.5,
          },
        ],
        'total': 5181.42,
      };

      final electronicInvoice = {
        'voucher_type': 1,
        'voucher_letter': 'A',
        'cae': testCae,
        'cae_expiration': testExpiration,
        'net_amount': 4282.17,
        'iva_amount': 899.25,
        'total_amount': 5181.42,
        'iva_breakdown': [
          {'id': 5, 'importe': 894.46},
          {'id': 4, 'importe': 4.79},
        ],
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: testBusinessSettings,
        paperSize: 'a4',
      );

      final bytes = await doc.save();
      expect(bytes.isNotEmpty, isTrue);

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

      // Factura A headers and values
      expect(plainTexts.contains('A'), isTrue);
      expect(plainTexts.contains('COD. 01'), isTrue);
      expect(plainTexts.any((t) => t.contains('14,857') || t.contains('14.857') || t.contains('14.86')), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Edge Case: Zero Net / IVA Amounts & Zero Aliquot (No Division by Zero)
    // ─────────────────────────────────────────────────────────────────────────
    test('edge case: zero net, zero IVA, and zero unit price handle without NaN or division by zero', () async {
      final sale = {
        'id': 205,
        'items': [
          {
            'product_name': 'Muestra Promocional Gratuita',
            'quantity': 0, // 0 quantity edge case
            'unit_price': 0.0,
            'subtotal': 0.0,
            'iva_rate': 0.0,
            'net_amount': 0.0,
          },
          {
            'product_name': 'Producto 100% Exento',
            'quantity': 1,
            'unit_price': 5000.0,
            'subtotal': 5000.0,
            'iva_rate': 0.0,
            'net_amount': 5000.0,
          },
        ],
        'total': 5000.0,
      };

      final electronicInvoice = {
        'voucher_type': 1,
        'voucher_letter': 'A',
        'cae': testCae,
        'cae_expiration': testExpiration,
        'net_amount': 0.0,
        'iva_amount': 0.0,
        'exempt_amount': 5000.0,
        'total_amount': 5000.0,
        'iva_breakdown': <Map<String, dynamic>>[],
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: testBusinessSettings,
        paperSize: 'letter',
      );

      final bytes = await doc.save();
      expect(bytes.isNotEmpty, isTrue);

      // Verify no 'NaN' or 'Infinity' in rendered strings
      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();
      for (final t in plainTexts) {
        expect(t.contains('NaN'), isFalse, reason: 'Text must never contain NaN: $t');
        expect(t.contains('Infinity'), isFalse, reason: 'Text must never contain Infinity: $t');
      }

      expect(plainTexts.any((t) => t.contains('Importe Exento:')), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 6. AST & Byte Stream Verification across Facturas A, B, and C
    // ─────────────────────────────────────────────────────────────────────────
    test('AST & byte stream: Facturas A, B, and C have exact Letras, Codes, CAE, and QR Barcode', () async {
      final cases = [
        {'letter': 'A', 'expectedType': 1, 'expectedCode': 'COD. 01', 'title': 'FACTURA A'},
        {'letter': 'B', 'expectedType': 6, 'expectedCode': 'COD. 06', 'title': 'FACTURA B'},
        {'letter': 'C', 'expectedType': 11, 'expectedCode': 'COD. 11', 'title': 'FACTURA C'},
      ];

      for (final tc in cases) {
        final letter = tc['letter'] as String;
        final expectedCode = tc['expectedCode'] as String;
        final title = tc['title'] as String;

        final sale = {
          'id': 300,
          'items': [
            {'product_name': 'Item $letter', 'quantity': 1, 'unit_price': 1000.0, 'subtotal': 1000.0},
          ],
          'total': 1000.0,
        };

        final electronicInvoice = {
          'voucher_letter': letter,
          'cae': '1122334455667788',
          'cae_expiration': '2026-11-15',
          'total_amount': 1000.0,
          'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=AST_VERIF_$letter',
        };

        final doc = AfipFiscalPdfService.buildFiscalDocument(
          sale: sale,
          electronicInvoice: electronicInvoice,
          businessSettings: testBusinessSettings,
          paperSize: 'a4',
          compress: false,
        );

        // 1. AST RichText checks
        final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
        final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

        expect(plainTexts.contains(letter), isTrue,
            reason: 'Letter box must contain $letter');
        expect(plainTexts.contains(expectedCode), isTrue,
            reason: 'Voucher code box must contain $expectedCode');
        expect(plainTexts.any((t) => t.contains(title)), isTrue,
            reason: 'Title must contain $title');
        expect(plainTexts.any((t) => t.contains('1122334455667788')), isTrue,
            reason: 'CAE must be present in AST');

        // 2. Barcode Widget checks
        final barcodeWidgets = AfipFiscalPdfService.findWidgets<pw.BarcodeWidget>(doc);
        expect(barcodeWidgets.length, equals(1));
        expect(barcodeWidgets.first.barcode.name, equals('QR-Code'));
        expect(barcodeWidgets.first.dataString, equals('https://www.afip.gob.ar/fe/qr/?p=AST_VERIF_$letter'));

        // 3. Binary byte stream checks
        final bytes = await doc.save();
        expect(bytes.isNotEmpty, isTrue);
        expect(ascii.decode(bytes.sublist(0, 5)), equals('%PDF-'));

        final decodedLatin1 = latin1.decode(bytes);
        expect(decodedLatin1.contains('1122334455667788'), isTrue);
        expect(decodedLatin1.contains('COD.'), isTrue);
        expect(decodedLatin1.contains('FACTURA'), isTrue);
      }
    });
  });
}
