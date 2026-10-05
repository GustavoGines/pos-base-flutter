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

  // Valid 1x1 PNG bytes for testing MemoryImage creation
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

  group('Milestone 4: QuotePdfService Preload Thumbnails Tests', () {
    test('preloadThumbnails downloads and caches pw.MemoryImage for items with valid imageUrl', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        if (request.url.toString() == 'http://example.com/item1.png') {
          return http.Response.bytes(samplePngBytes, 200);
        }
        return http.Response('Not Found', 404);
      });

      final quote = Quote(
        id: 1,
        quoteNumber: 'PRE-0001',
        status: 'pending',
        subtotal: 1000,
        total: 1000,
        items: [
          QuoteItem(
            productId: 10,
            productName: 'Producto Con Imagen',
            unitPrice: 500,
            quantity: 2,
            subtotal: 1000,
            imageUrl: 'http://example.com/item1.png',
          ),
          QuoteItem(
            productId: 11,
            productName: 'Producto Sin Imagen',
            unitPrice: 500,
            quantity: 1,
            subtotal: 500,
            imageUrl: null,
          ),
        ],
      );

      final thumbnails = await QuotePdfService.preloadThumbnails(quote, httpClient: mockClient);

      expect(thumbnails.length, equals(1));
      expect(thumbnails.containsKey(0), isTrue);
      expect(thumbnails[0], isNotNull);
      expect(thumbnails[0]!.bytes, equals(samplePngBytes));
      expect(thumbnails.containsKey(1), isFalse);
      expect(requestCount, equals(1));

      // Second run should use cache without additional HTTP request
      final cachedThumbnails = await QuotePdfService.preloadThumbnails(quote, httpClient: mockClient);
      expect(cachedThumbnails.containsKey(0), isTrue);
      expect(requestCount, equals(1)); // Still 1 because cache was hit
    });

    test('preloadThumbnails handles HTTP errors gracefully without throwing', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final quote = Quote(
        id: 2,
        quoteNumber: 'PRE-0002',
        status: 'pending',
        subtotal: 300,
        total: 300,
        items: [
          QuoteItem(
            productId: 20,
            productName: 'Producto Con Error',
            unitPrice: 300,
            quantity: 1,
            subtotal: 300,
            imageUrl: 'http://example.com/error.png',
          ),
        ],
      );

      final thumbnails = await QuotePdfService.preloadThumbnails(quote, httpClient: mockClient);
      expect(thumbnails.isEmpty, isTrue);
    });

    test('preloadThumbnails falls back to item.product.imageUrl if item.imageUrl is null', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString() == 'http://example.com/product_entity.png') {
          return http.Response.bytes(samplePngBytes, 200);
        }
        return http.Response('Not Found', 404);
      });

      final product = Product(
        id: 30,
        name: 'Item de Catalogo',
        internalCode: 'CAT30',
        costPrice: 100,
        sellingPrice: 200,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/product_entity.png',
      );

      final quote = Quote(
        id: 3,
        quoteNumber: 'PRE-0003',
        status: 'pending',
        subtotal: 200,
        total: 200,
        items: [
          QuoteItem(
            productId: 30,
            productName: 'Item de Catalogo',
            unitPrice: 200,
            quantity: 1,
            subtotal: 200,
            product: product,
          ),
        ],
      );

      final thumbnails = await QuotePdfService.preloadThumbnails(quote, httpClient: mockClient);
      expect(thumbnails.containsKey(0), isTrue);
      expect(thumbnails[0]!.bytes, equals(samplePngBytes));
    });
  });

  group('Milestone 4: QuotePdfService PDF Generation & Image Embed Tests', () {
    test('generateQuotePdf builds valid PDF bytes with embedded product images without errors', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(samplePngBytes, 200);
      });

      final quote = Quote(
        id: 100,
        quoteNumber: 'P-0001-00000042',
        status: 'pending',
        subtotal: 12500,
        total: 12500,
        customerName: 'Juan Pérez',
        customerPhone: '1122334455',
        notes: 'Entrega a convenir. Presupuesto válido por 7 días.',
        validUntil: '2026-11-01',
        priceList: 'wholesale',
        items: [
          QuoteItem(
            productId: 1,
            productName: 'Taladro Percutor 750W',
            unitPrice: 7500,
            quantity: 1,
            subtotal: 7500,
            imageUrl: 'http://example.com/taladro.png',
          ),
          QuoteItem(
            productId: 2,
            productName: 'Juego de Mechas para Pared x5',
            unitPrice: 2500,
            quantity: 2,
            subtotal: 5000,
            imageUrl: 'http://example.com/mechas.png',
          ),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Central',
        businessAddress: 'Av. Libertador 1234',
        businessPhone: '011-4567-8900',
        vendorName: 'Carlos Gómez',
        httpClient: mockClient,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);

      // Verify PDF magic header bytes: %PDF- (0x25, 0x50, 0x44, 0x46, 0x2D)
      final header = ascii.decode(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('generateQuotePdf builds cleanly for quotes with mix of images and empty placeholders', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString() == 'http://example.com/image_ok.png') {
          return http.Response.bytes(samplePngBytes, 200);
        }
        return http.Response('Not Found', 404);
      });

      final quote = Quote(
        id: 101,
        quoteNumber: 'P-0001-00000043',
        status: 'pending',
        subtotal: 6000,
        total: 6000,
        items: [
          QuoteItem(
            productId: 1,
            productName: 'Producto con foto',
            unitPrice: 2000,
            quantity: 1,
            subtotal: 2000,
            imageUrl: 'http://example.com/image_ok.png',
          ),
          QuoteItem(
            productId: 2,
            productName: 'Producto sin foto',
            unitPrice: 2000,
            quantity: 1,
            subtotal: 2000,
            imageUrl: null,
          ),
          QuoteItem(
            productId: 3,
            productName: 'Producto con imagen fallida',
            unitPrice: 2000,
            quantity: 1,
            subtotal: 2000,
            imageUrl: 'http://example.com/broken.png',
          ),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Comercio Test',
        httpClient: mockClient,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('generateQuotePdf handles large item list without overflow layout errors', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(samplePngBytes, 200);
      });

      final items = List.generate(
        15,
        (i) => QuoteItem(
          productId: i + 1,
          productName: 'Artículo de Prueba Número ${i + 1} con descripción larga para verificar que no desborde',
          unitPrice: 100.0 * (i + 1),
          quantity: (i % 3 + 1).toDouble(),
          subtotal: 100.0 * (i + 1) * (i % 3 + 1),
          imageUrl: i.isEven ? 'http://example.com/item_$i.png' : null,
        ),
      );

      final total = items.fold<double>(0, (sum, it) => sum + it.subtotal);

      final quote = Quote(
        id: 102,
        quoteNumber: 'P-0001-00000044',
        status: 'pending',
        subtotal: total,
        total: total,
        customerName: 'Cliente Mayorista',
        notes: 'Presupuesto con paginado automático.',
        items: items,
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Distribuidora Mayorista S.A.',
        httpClient: mockClient,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });
  });
}
