import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/quotes/services/quote_pdf_service.dart';

class MockQuoteRepository extends Fake implements QuoteRepository {
  Quote? quoteToReturn;

  @override
  Future<Quote> createQuote({
    required List<QuoteItem> items,
    String? customerName,
    String? customerPhone,
    String? notes,
    String? validUntil,
    int? userId,
    String? priceList,
  }) async {
    if (quoteToReturn != null) {
      return quoteToReturn!;
    }
    return Quote(
      id: 99,
      quoteNumber: 'PRE-0099',
      status: 'pending',
      subtotal: 100,
      total: 100,
      customerName: customerName,
      customerPhone: customerPhone,
      notes: notes,
      validUntil: validUntil,
      priceList: priceList ?? 'base',
      items: items.map((i) => QuoteItem(
        productId: i.productId,
        productName: i.productName,
        unitPrice: i.unitPrice,
        quantity: i.quantity,
        subtotal: i.subtotal,
        product: null,    // Simula que el backend no hidrata el producto
        imageUrl: null,   // Simula que el backend no retorna image_url
      )).toList(),
    );
  }
}

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

  late Directory tempDir;
  late File localImageFile;

  setUp(() async {
    QuotePdfService.clearThumbnailCache();
    tempDir = await Directory.systemTemp.createTemp('quote_pdf_test_');
    localImageFile = File('${tempDir.path}${Platform.pathSeparator}test_thumb.png');
    await localImageFile.writeAsBytes(samplePngBytes);
  });

  tearDown(() async {
    QuotePdfService.clearThumbnailCache();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Milestone 3: Local File Thumbnail & Dynamic BaseUrl Tests', () {
    test('preloadThumbnails loads local file directly without network request', () async {
      // Mock client fails if any network request is attempted
      final failingClient = MockClient((request) async {
        fail('Network client should not be called for local files: ${request.url}');
      });

      final quote = Quote(
        id: 1,
        quoteNumber: 'PRE-LOC-01',
        status: 'pending',
        subtotal: 500,
        total: 500,
        items: [
          QuoteItem(
            productId: 101,
            productName: 'Producto Local',
            unitPrice: 500,
            quantity: 1,
            subtotal: 500,
            imageUrl: localImageFile.path,
          ),
        ],
      );

      final thumbnails = await QuotePdfService.preloadThumbnails(quote, httpClient: failingClient);

      expect(thumbnails.containsKey(0), isTrue);
      expect(thumbnails[0], isNotNull);
      expect(thumbnails[0]!.bytes, equals(samplePngBytes));
    });

    test('preloadThumbnails resolves file:// URI scheme directly without network', () async {
      final failingClient = MockClient((request) async {
        fail('Network client should not be called for file URI: ${request.url}');
      });

      final fileUri = localImageFile.uri.toString();
      final quote = Quote(
        id: 2,
        quoteNumber: 'PRE-LOC-02',
        status: 'pending',
        subtotal: 300,
        total: 300,
        items: [
          QuoteItem(
            productId: 102,
            productName: 'Producto File URI',
            unitPrice: 300,
            quantity: 1,
            subtotal: 300,
            imageUrl: fileUri,
          ),
        ],
      );

      final thumbnails = await QuotePdfService.preloadThumbnails(quote, httpClient: failingClient);

      expect(thumbnails.containsKey(0), isTrue);
      expect(thumbnails[0], isNotNull);
      expect(thumbnails[0]!.bytes, equals(samplePngBytes));
    });

    test('preloadThumbnails resolves dynamic baseUrl parameter for relative paths', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        if (request.url.path.contains('sample_prod.png')) {
          return http.Response.bytes(samplePngBytes, 200);
        }
        return http.Response('Not Found', 404);
      });

      final quote = Quote(
        id: 3,
        quoteNumber: 'PRE-REM-01',
        status: 'pending',
        subtotal: 400,
        total: 400,
        items: [
          QuoteItem(
            productId: 103,
            productName: 'Producto Relativo',
            unitPrice: 400,
            quantity: 1,
            subtotal: 400,
            imageUrl: 'products/sample_prod.png',
          ),
        ],
      );

      final thumbnails = await QuotePdfService.preloadThumbnails(
        quote,
        httpClient: mockClient,
        baseUrl: 'http://custom-pos.internal:8000/api',
      );

      expect(thumbnails.containsKey(0), isTrue);
      expect(capturedUri, isNotNull);
      expect(capturedUri!.host, equals('custom-pos.internal'));
      expect(capturedUri!.port, equals(8000));
      expect(capturedUri!.path, equals('/storage/products/sample_prod.png'));
    });

    test('preloadThumbnails handles non-existent or 0-byte local file gracefully', () async {
      final quote = Quote(
        id: 4,
        quoteNumber: 'PRE-ERR-01',
        status: 'pending',
        subtotal: 100,
        total: 100,
        items: [
          QuoteItem(
            productId: 104,
            productName: 'Archivo Inexistente',
            unitPrice: 100,
            quantity: 1,
            subtotal: 100,
            imageUrl: 'C:/fake/path/does_not_exist_12345.png',
          ),
        ],
      );

      final thumbnails = await QuotePdfService.preloadThumbnails(quote);
      expect(thumbnails.containsKey(0), isFalse);
    });
  });

  group('Milestone 3: Local File Logo & Dynamic BaseUrl Tests', () {
    test('preloadLogo loads local file directly without network request', () async {
      final failingClient = MockClient((request) async {
        fail('Network client should not be called for local logo: ${request.url}');
      });

      final logo = await QuotePdfService.preloadLogo(
        logoUrl: localImageFile.path,
        httpClient: failingClient,
      );

      expect(logo, isNotNull);
      expect(logo!.bytes, equals(samplePngBytes));
    });

    test('preloadLogo resolves file:// URI scheme directly without network', () async {
      final failingClient = MockClient((request) async {
        fail('Network client should not be called for file URI logo: ${request.url}');
      });

      final logo = await QuotePdfService.preloadLogo(
        logoUrl: localImageFile.uri.toString(),
        httpClient: failingClient,
      );

      expect(logo, isNotNull);
      expect(logo!.bytes, equals(samplePngBytes));
    });

    test('preloadLogo resolves dynamic baseUrl parameter for relative paths', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response.bytes(samplePngBytes, 200);
      });

      final logo = await QuotePdfService.preloadLogo(
        logoUrl: 'business/company_logo.png',
        httpClient: mockClient,
        baseUrl: 'http://test-server.pos:9000/api',
      );

      expect(logo, isNotNull);
      expect(capturedUri, isNotNull);
      expect(capturedUri!.host, equals('test-server.pos'));
      expect(capturedUri!.port, equals(9000));
      expect(capturedUri!.path, equals('/storage/business/company_logo.png'));
    });
  });

  group('Milestone 3: PDF Generation Watermark & Enlarged Logo Tests', () {
    test('generateQuotePdf builds valid PDF with 5% watermark when logoBytes provided', () async {
      final quote = Quote(
        id: 10,
        quoteNumber: 'PRE-WM-01',
        status: 'pending',
        subtotal: 1200,
        total: 1200,
        items: [
          QuoteItem(
            productId: 201,
            productName: 'Tornillo Autoperforante',
            unitPrice: 120,
            quantity: 10,
            subtotal: 1200,
          ),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Central',
        businessAddress: 'Av. Corrientes 1234',
        businessPhone: '11-4567-8901',
        logoBytes: samplePngBytes,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(100));
      // PDF documents start with %PDF- header
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('generateQuotePdf builds valid PDF without watermark when no logo is provided', () async {
      final quote = Quote(
        id: 11,
        quoteNumber: 'PRE-WM-02',
        status: 'pending',
        subtotal: 500,
        total: 500,
        items: [
          QuoteItem(
            productId: 202,
            productName: 'Clavos 2 Pulgadas',
            unitPrice: 50,
            quantity: 10,
            subtotal: 500,
          ),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Sin Logo',
        logoUrl: null,
        logoBytes: null,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(100));
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('generateQuotePdf renders both local file thumbnails and logo without crash', () async {
      final quote = Quote(
        id: 12,
        quoteNumber: 'PRE-WM-03',
        status: 'pending',
        subtotal: 800,
        total: 800,
        items: [
          QuoteItem(
            productId: 203,
            productName: 'Martillo Carpintero',
            unitPrice: 800,
            quantity: 1,
            subtotal: 800,
            imageUrl: localImageFile.path,
          ),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Integral',
        logoUrl: localImageFile.path,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });
  });

  group('Milestone 3: QuoteProvider In-Memory Cart Enrichment Tests', () {
    test('createQuote enriches returned quote items with product and imageUrl from cart', () async {
      final repo = MockQuoteRepository();
      final provider = QuoteProvider(repository: repo);

      final sampleProduct = Product(
        id: 42,
        name: 'Taladro Percutor 750W',
        internalCode: 'TAL-01',
        costPrice: 10000,
        sellingPrice: 15000,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/taladro.png',
      );

      provider.addToCart(sampleProduct, quantity: 1);
      expect(provider.cart.length, equals(1));

      final createdQuote = await provider.generateQuote(
        customerName: 'Juan Pérez',
        customerPhone: '11-1234-5678',
      );

      expect(createdQuote, isNotNull);
      expect(createdQuote!.items.length, equals(1));
      final item = createdQuote.items.first;

      // In-memory enrichment verification:
      expect(item.productId, equals(42));
      expect(item.productName, equals('Taladro Percutor 750W'));
      expect(item.product, isNotNull);
      expect(item.product!.id, equals(42));
      expect(item.imageUrl, equals('http://example.com/taladro.png'));

      // Cart should be cleared after creation
      expect(provider.cart.isEmpty, isTrue);
    });
  });
}
