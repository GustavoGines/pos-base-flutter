import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:frontend_desktop/core/utils/afip_fiscal_pdf_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleSettings = BusinessSettings(
    companyName: 'Mayorista Los Álamos S.A.',
    taxId: '30-71458923-9',
    address: 'Av. Corrientes 1234, CABA',
    phone: '011-4567-8900',
    afipEnabled: true,
    isIibbPerceptionAgent: true,
    defaultIibbPerceptionRate: 3.5,
  );

  group('AfipFiscalPdfService - IIBB Perception PDF AST Tests', () {
    test('Factura A: renders "Percepción IIBB (X%): \$Monto" when perception > 0', () async {
      final sale = {
        'id': 201,
        'created_at': '2026-10-08T10:00:00Z',
        'items': [
          {
            'product_name': 'Caja Aceite 12x900ml',
            'quantity': 2,
            'unit_price': 12100.0,
            'subtotal': 24200.0,
            'net_amount': 20000.0,
            'iva_rate': 21.0,
          },
        ],
        'total': 24900.0,
        'iibb_perception_amount': 700.0,
        'iibb_perception_rate': 3.5,
      };

      final electronicInvoice = {
        'voucher_type': 1,
        'voucher_letter': 'A',
        'point_of_sale': 1,
        'voucher_number': 550,
        'formatted_number': '00001-00000550',
        'cae': '74382910492819',
        'cae_expiration': '2026-10-18',
        'doc_type': 80,
        'doc_number': '30-99887766-5',
        'receiver_name': 'Comercializadora Norte S.A.',
        'receiver_tax_condition': 'IVA Responsable Inscripto',
        'net_amount': 20000.0,
        'iva_amount': 4200.0,
        'total_amount': 24900.0,
        'iibb_perception_amount': 700.0,
        'iibb_perception_rate': 3.5,
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=test',
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleSettings,
        paperSize: 'a4',
        compress: false,
      );

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

      // Debería contener la línea de Percepción IIBB
      final perceptionLine = plainTexts.firstWhere(
        (t) => t.contains('Percepción IIBB'),
        orElse: () => '',
      );

      expect(perceptionLine.isNotEmpty, isTrue,
          reason: 'Factura A must render Percepción IIBB in totals section');
      expect(perceptionLine, contains('3.5%'));
      expect(perceptionLine, contains('700'));
      expect(plainTexts.any((t) => t.contains('Subtotal Neto Gravado:')), isTrue);
      expect(plainTexts.any((t) => t.contains('IVA 21%:')), isTrue);
    });

    test('Factura B: renders "Percepción IIBB (X%): \$Monto" when perception > 0', () async {
      final sale = {
        'id': 202,
        'created_at': '2026-10-08T11:00:00Z',
        'items': [
          {
            'product_name': 'Bulto Harina 10x1kg',
            'quantity': 1,
            'unit_price': 12100.0,
            'subtotal': 12100.0,
          },
        ],
        'total': 12450.0,
        'iibb_perception_amount': 350.0,
        'iibb_perception_rate': 3.5,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'point_of_sale': 1,
        'voucher_number': 890,
        'formatted_number': '00001-00000890',
        'cae': '74382910492820',
        'cae_expiration': '2026-10-18',
        'doc_type': 96,
        'doc_number': '20-12345678-6',
        'receiver_name': 'Juan Pérez',
        'receiver_tax_condition': 'IVA Sujeto Exento',
        'total_amount': 12450.0,
        'iibb_perception_amount': 350.0,
        'iibb_perception_rate': 3.5,
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=test_b',
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleSettings,
        paperSize: 'a4',
        compress: false,
      );

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

      final perceptionLine = plainTexts.firstWhere(
        (t) => t.contains('Percepción IIBB'),
        orElse: () => '',
      );

      expect(perceptionLine.isNotEmpty, isTrue,
          reason: 'Factura B must render Percepción IIBB in totals section');
      expect(perceptionLine, contains('3.5%'));
      expect(perceptionLine, contains('350'));
      expect(plainTexts.any((t) => t.contains('Subtotal:')), isTrue);
    });

    test('Omits "Percepción IIBB" line when perception is 0.0 or omitted', () async {
      final sale = {
        'id': 203,
        'created_at': '2026-10-08T12:00:00Z',
        'items': [
          {
            'product_name': 'Producto Standard',
            'quantity': 1,
            'unit_price': 1000.0,
            'subtotal': 1000.0,
          },
        ],
        'total': 1000.0,
        'iibb_perception_amount': 0.0,
      };

      final electronicInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'point_of_sale': 1,
        'voucher_number': 891,
        'formatted_number': '00001-00000891',
        'cae': '74382910492821',
        'cae_expiration': '2026-10-18',
        'total_amount': 1000.0,
      };

      final doc = AfipFiscalPdfService.buildFiscalDocument(
        sale: sale,
        electronicInvoice: electronicInvoice,
        businessSettings: sampleSettings,
        paperSize: 'a4',
        compress: false,
      );

      final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
      final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();

      expect(plainTexts.any((t) => t.contains('Percepción IIBB')), isFalse,
          reason: 'Must not display Percepción IIBB when amount is 0');
    });
  });

  group('ThermalReceiptWidget - IIBB Perception Ticket Rendering Tests', () {
    final testItems = [
      {
        'product_name': 'Yerba Playadito 1Kg',
        'quantity': 2,
        'unit_price': 1210.0,
        'subtotal': 2420.0,
      },
    ];

    testWidgets('Renders "PERCEPCION IIBB (X%):" line when perception > 0 with zero overflow', (tester) async {
      tester.view.physicalSize = const Size(290, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ThermalReceiptWidget(
                paperWidth: ThermalPaperWidth.mm80,
                businessSettings: sampleSettings,
                items: testItems,
                total: 2490.0,
                iibbPerceptionAmount: 70.0,
                iibbPerceptionRate: 3.5,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('PERCEPCION IIBB (3.5%):'), findsOneWidget);
      expect(find.text('\$70'), findsOneWidget);
    });

    testWidgets('Renders cleanly at narrow 58mm (210px) with zero RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(210, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ThermalReceiptWidget(
                paperWidth: ThermalPaperWidth.mm58,
                businessSettings: sampleSettings,
                items: testItems,
                total: 2490.0,
                iibbPerceptionAmount: 70.0,
                iibbPerceptionRate: 3.5,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('PERCEPCION IIBB (3.5%):'), findsOneWidget);
    });

    testWidgets('Omits "PERCEPCION IIBB" line when perception is 0.0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ThermalReceiptWidget(
                paperWidth: ThermalPaperWidth.mm80,
                businessSettings: sampleSettings,
                items: testItems,
                total: 2420.0,
                iibbPerceptionAmount: 0.0,
                iibbPerceptionRate: 0.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('PERCEPCION IIBB'), findsNothing);
    });
  });
}
