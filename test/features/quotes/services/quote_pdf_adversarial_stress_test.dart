import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/services/quote_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Valid 1x1 PNG bytes
  final samplePngBytes = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
    0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
    0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
    0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
    0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
    0x60, 0x82,
  ]);

  setUp(() {
    QuotePdfService.clearThumbnailCache();
  });

  group('Adversarial Stress Test: QuotePdfService preloadLogo Resilience', () {
    test('Corrupt non-image logoBytes returns null gracefully without throwing', () async {
      final corruptBytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0xFF]);
      final logo = await QuotePdfService.preloadLogo(logoBytes: corruptBytes);
      expect(logo, isNull);
    });

    test('Zero-length logoBytes returns null gracefully', () async {
      final logo = await QuotePdfService.preloadLogo(logoBytes: Uint8List(0));
      expect(logo, isNull);
    });

    test('Valid logoBytes returns pw.MemoryImage without network call', () async {
      final logo = await QuotePdfService.preloadLogo(logoBytes: samplePngBytes);
      expect(logo, isNotNull);
      expect(logo!.bytes, equals(samplePngBytes));
    });

    test('Null, empty, and whitespace logoUrl return null gracefully', () async {
      expect(await QuotePdfService.preloadLogo(logoUrl: null), isNull);
      expect(await QuotePdfService.preloadLogo(logoUrl: ''), isNull);
      expect(await QuotePdfService.preloadLogo(logoUrl: '    \n  '), isNull);
    });

    test('HTTP 404, 500, and 200 with 0 bytes for logoUrl return null', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('404')) {
          return http.Response('Not Found', 404);
        }
        if (request.url.path.contains('500')) {
          return http.Response('Internal Error', 500);
        }
        if (request.url.path.contains('zero')) {
          return http.Response.bytes(Uint8List(0), 200);
        }
        return http.Response('Unknown', 400);
      });

      expect(await QuotePdfService.preloadLogo(logoUrl: 'http://example.com/404.png', httpClient: mockClient), isNull);
      expect(await QuotePdfService.preloadLogo(logoUrl: 'http://example.com/500.png', httpClient: mockClient), isNull);
      expect(await QuotePdfService.preloadLogo(logoUrl: 'http://example.com/zero.png', httpClient: mockClient), isNull);
    });

    test('HTTP 200 with corrupted HTML content for logoUrl catches exception and returns null', () async {
      final htmlBytes = Uint8List.fromList(utf8.encode('<!DOCTYPE html><html><body>Error 502 Bad Gateway</body></html>'));
      final mockClient = MockClient((request) async {
        return http.Response.bytes(htmlBytes, 200);
      });

      final logo = await QuotePdfService.preloadLogo(logoUrl: 'http://example.com/corrupt_logo.png', httpClient: mockClient);
      expect(logo, isNull);
    });

    test('HTTP network timeout (>4s) in preloadLogo catches TimeoutException and returns null within 5s', () async {
      final mockClient = MockClient((request) async {
        await Future.delayed(const Duration(seconds: 5));
        return http.Response.bytes(samplePngBytes, 200);
      });

      final stopwatch = Stopwatch()..start();
      final logo = await QuotePdfService.preloadLogo(logoUrl: 'http://example.com/slow_logo.png', httpClient: mockClient);
      stopwatch.stop();

      expect(logo, isNull);
      // Ensure timeout terminated around 4s, well below infinite hang
      expect(stopwatch.elapsed.inSeconds, lessThanOrEqualTo(6));
    });

    test('Memory cache avoids duplicate requests and clearThumbnailCache resets it', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response.bytes(samplePngBytes, 200);
      });

      const url = 'http://example.com/cached_logo.png';
      final logo1 = await QuotePdfService.preloadLogo(logoUrl: url, httpClient: mockClient);
      expect(logo1, isNotNull);
      expect(requestCount, equals(1));

      // Second call uses cache
      final logo2 = await QuotePdfService.preloadLogo(logoUrl: url, httpClient: mockClient);
      expect(logo2, isNotNull);
      expect(requestCount, equals(1));

      // After clearing cache, new call executes request
      QuotePdfService.clearThumbnailCache();
      final logo3 = await QuotePdfService.preloadLogo(logoUrl: url, httpClient: mockClient);
      expect(logo3, isNotNull);
      expect(requestCount, equals(2));
    });
  });

  group('Adversarial Stress Test: QuotePdfService Mixed Table Thumbnails & Multi-page', () {
    test('generateQuotePdf handles quote table with 10 items of mixed valid/corrupt/404/500/timeout images', () async {
      final corruptHtmlBytes = Uint8List.fromList(utf8.encode('<html>500 Internal Error</html>'));

      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('ok')) {
          return http.Response.bytes(samplePngBytes, 200);
        } else if (path.contains('404')) {
          return http.Response('Not Found', 404);
        } else if (path.contains('500')) {
          return http.Response('Server Error', 500);
        } else if (path.contains('zero')) {
          return http.Response.bytes(Uint8List(0), 200);
        } else if (path.contains('corrupt')) {
          return http.Response.bytes(corruptHtmlBytes, 200);
        } else if (path.contains('timeout')) {
          await Future.delayed(const Duration(seconds: 5));
          return http.Response.bytes(samplePngBytes, 200);
        }
        return http.Response('Not Found', 404);
      });

      final items = [
        QuoteItem(productId: 1, productName: 'Item 1 OK', unitPrice: 100, quantity: 1, subtotal: 100, imageUrl: 'http://example.com/ok_1.png'),
        QuoteItem(productId: 2, productName: 'Item 2 Null URL', unitPrice: 200, quantity: 2, subtotal: 400, imageUrl: null),
        QuoteItem(productId: 3, productName: 'Item 3 Empty URL', unitPrice: 300, quantity: 1, subtotal: 300, imageUrl: ''),
        QuoteItem(productId: 4, productName: 'Item 4 404 URL', unitPrice: 400, quantity: 1, subtotal: 400, imageUrl: 'http://example.com/404.png'),
        QuoteItem(productId: 5, productName: 'Item 5 500 URL', unitPrice: 500, quantity: 1, subtotal: 500, imageUrl: 'http://example.com/500.png'),
        QuoteItem(productId: 6, productName: 'Item 6 Zero Bytes', unitPrice: 600, quantity: 1, subtotal: 600, imageUrl: 'http://example.com/zero.png'),
        QuoteItem(productId: 7, productName: 'Item 7 Corrupt Bytes', unitPrice: 700, quantity: 1, subtotal: 700, imageUrl: 'http://example.com/corrupt.png'),
        QuoteItem(
          productId: 8,
          productName: 'Item 8 Product Fallback OK',
          unitPrice: 800,
          quantity: 1,
          subtotal: 800,
          imageUrl: null,
          product: Product(
            id: 8,
            name: 'Item 8 Product Fallback OK',
            internalCode: 'P-08',
            costPrice: 400,
            sellingPrice: 800,
            stock: 10,
            active: true,
            isSoldByWeight: false,
            imageUrl: 'http://example.com/ok_8.png',
          ),
        ),
        QuoteItem(productId: 9, productName: 'Item 9 Timeout URL', unitPrice: 900, quantity: 1, subtotal: 900, imageUrl: 'http://example.com/timeout.png'),
        QuoteItem(productId: 10, productName: 'Item 10 OK Last', unitPrice: 1000, quantity: 1, subtotal: 1000, imageUrl: 'http://example.com/ok_10.png'),
      ];

      final total = items.fold<double>(0, (sum, it) => sum + it.subtotal);

      final quote = Quote(
        id: 900,
        quoteNumber: 'PRE-MIXED-001',
        status: 'pending',
        subtotal: total,
        total: total,
        items: items,
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería & Bazar Mix',
        businessAddress: 'Av. Corrientes 1234',
        businessPhone: '11-4567-8901',
        vendorName: 'Vendedor Test',
        logoUrl: 'http://example.com/ok_logo.png',
        httpClient: mockClient,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('generateQuotePdf with corrupt logo and corrupt table images still generates valid PDF', () async {
      final corruptBytes = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);
      final mockClient = MockClient((request) async {
        return http.Response.bytes(corruptBytes, 200);
      });

      final quote = Quote(
        id: 901,
        quoteNumber: 'PRE-ALL-CORRUPT',
        status: 'pending',
        subtotal: 1500,
        total: 1500,
        items: [
          QuoteItem(productId: 1, productName: 'Item Con Imagen Rota', unitPrice: 1500, quantity: 1, subtotal: 1500, imageUrl: 'http://example.com/broken.png'),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Comercio Imagen Rota',
        logoBytes: corruptBytes,
        httpClient: mockClient,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Massive 60-item multi-page quote with alternating images generates multi-page PDF cleanly without overflow', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(samplePngBytes, 200);
      });

      final items = List.generate(
        60,
        (i) => QuoteItem(
          productId: i + 1,
          productName: 'Producto Extenso de Prueba Lote #${i + 1} - Especificaciones Técnicas y Garantía Oficial',
          unitPrice: (i + 1) * 250.0,
          quantity: (i % 5 + 1).toDouble(),
          subtotal: (i + 1) * 250.0 * (i % 5 + 1),
          imageUrl: i.isEven ? 'http://example.com/item_$i.png' : null,
        ),
      );

      final total = items.fold<double>(0, (sum, it) => sum + it.subtotal);

      final quote = Quote(
        id: 902,
        quoteNumber: 'PRE-PAGINADO-60',
        status: 'pending',
        subtotal: total,
        total: total,
        customerName: 'Gran Empresa Constructora S.A.',
        customerPhone: '+54 9 11 4444-5555',
        notes: 'Presupuesto de 60 artículos para obra civil mayor. Validez 15 días corridos.',
        items: items,
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Corralón Central de Materiales',
        logoBytes: samplePngBytes,
        httpClient: mockClient,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(20000));
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });
  });
}
