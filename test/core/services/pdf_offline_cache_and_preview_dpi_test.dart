import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_pdf_preview.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/a4_split_pdf_service.dart';
import 'package:frontend_desktop/core/utils/afip_fiscal_pdf_service.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:printing/printing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // PNG 1x1 válido transparente
  final fakeLogoPng = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  group('PDF Offline Fonts, Logo Cache e Impresión Vectorial', () {
    setUp(() {
      AfipFiscalPdfService.invalidateLogoCache();
    });

    test('resolveCachedPdfTheme carga fuentes locales offline una única vez en RAM', () async {
      final t1 = await AfipFiscalPdfService.resolveCachedPdfTheme();
      final t2 = await AfipFiscalPdfService.resolveCachedPdfTheme();

      expect(t1, isNotNull);
      expect(identical(t1, t2), isTrue);

      final sale = <String, dynamic>{
        'id': 501,
        'created_at': '2026-11-25T10:30:00',
        'total': 12100.0,
        'customer_name': 'Consumidor Final',
        'items': [
          {
            'product_name': 'Taladro 750W',
            'quantity': 1,
            'unit_price': 12100.0,
            'subtotal': 12100.0,
            'iva_rate': 21.0,
          },
        ],
        'payments': [
          {'method_name': 'Efectivo', 'amount': 12100.0},
        ],
      };

      final fiscalBytes = await AfipFiscalPdfService.generateFiscalInvoice(
        sale: sale,
        electronicInvoice: {
          'voucher_type': 6,
          'voucher_letter': 'B',
          'point_of_sale': 1,
          'voucher_number': 501,
          'formatted_number': '00001-00000501',
          'cae': '74185296301234',
          'cae_expiration': '2026-12-31',
          'doc_type': 99,
          'doc_number': '0',
          'receiver_name': 'Consumidor Final',
          'receiver_tax_condition': 'consumidor_final',
          'net_amount': 10000.0,
          'iva_amount': 2100.0,
          'total_amount': 12100.0,
          'iva_breakdown': [
            {'Id': 5, 'BaseImp': 10000.0, 'Importe': 2100.0},
          ],
          'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=test',
        },
        businessSettings: const BusinessSettings(
          companyName: 'Ferretería Test',
          taxId: '30712345678',
          taxCondition: 'IVA Responsable Inscripto',
        ),
        logoBytes: fakeLogoPng,
      );

      final nonFiscalBytes = await A4SplitPdfService.generateA4SingleReceipt(
        sale: sale,
        businessName: 'Ferretería Test',
        cuit: '30712345678',
        taxCondition: 'IVA Responsable Inscripto',
        logoBytes: fakeLogoPng,
      );

      expect(fiscalBytes.length, greaterThan(1000));
      expect(nonFiscalBytes.length, greaterThan(1000));
    });

    test('resolveLogoBytes cachea en RAM por URL/versión e invalida correctamente', () async {
      int httpCalls = 0;
      final client = MockClient((request) async {
        httpCalls++;
        return http.Response.bytes(fakeLogoPng, 200);
      });

      const settingsV1 = BusinessSettings(
        logoPath: 'business/logo_1.png',
        logoUrl: 'http://pos.local/storage/business/logo_1.png',
      );

      final bytes1 = await AfipFiscalPdfService.resolveLogoBytes(
        businessSettings: settingsV1,
        httpClient: client,
      );
      final bytes2 = await AfipFiscalPdfService.resolveLogoBytes(
        businessSettings: settingsV1,
        httpClient: client,
      );

      expect(bytes1, equals(fakeLogoPng));
      expect(bytes2, equals(fakeLogoPng));
      expect(httpCalls, 1, reason: 'Segunda lectura del mismo logo debe venir de RAM.');
      expect(AfipFiscalPdfService.cachedLogoCount, 1);

      AfipFiscalPdfService.invalidateLogoCache();
      expect(AfipFiscalPdfService.cachedLogoCount, 0);

      final bytesAfterInvalidate = await AfipFiscalPdfService.resolveLogoBytes(
        businessSettings: settingsV1,
        httpClient: client,
      );
      expect(bytesAfterInvalidate, equals(fakeLogoPng));
      expect(httpCalls, 2);
    });

    testWidgets('AppPdfPreviewModal a 160 DPI conserva bytes vectoriales originales en Imprimir y Guardar', (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final vectorPdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);
      Uint8List? printedBytes;
      Uint8List? savedBytes;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AppPdfPreviewModal(
              title: 'Vista Previa - Venta #999',
              dpi: 160.0,
              pdfFileName: 'Comprobante_999.pdf',
              build: (_) async => vectorPdfBytes,
              testPages: [
                PdfPreviewPageData(
                  image: MemoryImage(fakeLogoPng),
                  width: 595,
                  height: 842,
                ),
              ],
              onPrintOverride: (bytes, format, jobName) async {
                printedBytes = bytes;
              },
              onSaveOverride: (bytes, fileName) async {
                savedBytes = bytes;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final previewWidget = tester.widget<AppPdfPreview>(find.byType(AppPdfPreview));
      expect(previewWidget.dpi, 160.0);

      await tester.tap(find.byKey(const ValueKey('pdf_print_btn')));
      await tester.pumpAndSettle();
      expect(printedBytes, equals(vectorPdfBytes));

      await tester.tap(find.byKey(const ValueKey('pdf_save_btn')));
      await tester.pumpAndSettle();
      expect(savedBytes, equals(vectorPdfBytes));
    });
  });
}
