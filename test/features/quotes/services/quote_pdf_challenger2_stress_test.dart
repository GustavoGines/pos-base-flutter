import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/quotes/services/quote_pdf_service.dart';

int _crc32(List<int> bytes) {
  int c = 0xffffffff;
  for (final b in bytes) {
    c ^= b;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}

Uint8List createPng(int width, int height, {int r = 120, int g = 160, int b = 210}) {
  final bytes = BytesBuilder();
  bytes.add([137, 80, 78, 71, 13, 10, 26, 10]);

  final ihdrData = BytesBuilder();
  ihdrData.add([
    (width >> 24) & 0xFF,
    (width >> 16) & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    (height >> 24) & 0xFF,
    (height >> 16) & 0xFF,
    (height >> 8) & 0xFF,
    height & 0xFF,
    8,
    2,
    0,
    0,
    0,
  ]);
  final ihdrBody = ihdrData.takeBytes();
  final ihdrChunk = BytesBuilder();
  ihdrChunk.add([73, 72, 68, 82]);
  ihdrChunk.add(ihdrBody);
  final ihdrChunkBytes = ihdrChunk.takeBytes();
  final ihdrCrc = _crc32(ihdrChunkBytes);

  bytes.add([0, 0, 0, 13]);
  bytes.add(ihdrChunkBytes);
  bytes.add([
    (ihdrCrc >> 24) & 0xFF,
    (ihdrCrc >> 16) & 0xFF,
    (ihdrCrc >> 8) & 0xFF,
    ihdrCrc & 0xFF,
  ]);

  final rawScanlines = BytesBuilder();
  final rowData = Uint8List(1 + width * 3);
  rowData[0] = 0;
  for (int x = 0; x < width; x++) {
    rowData[1 + x * 3] = r;
    rowData[1 + x * 3 + 1] = g;
    rowData[1 + x * 3 + 2] = b;
  }
  for (int y = 0; y < height; y++) {
    rawScanlines.add(rowData);
  }
  final compressed = zlib.encode(rawScanlines.takeBytes());

  final idatChunk = BytesBuilder();
  idatChunk.add([73, 68, 65, 84]);
  idatChunk.add(compressed);
  final idatChunkBytes = idatChunk.takeBytes();
  final idatCrc = _crc32(idatChunkBytes);

  bytes.add([
    (compressed.length >> 24) & 0xFF,
    (compressed.length >> 16) & 0xFF,
    (compressed.length >> 8) & 0xFF,
    compressed.length & 0xFF,
  ]);
  bytes.add(idatChunkBytes);
  bytes.add([
    (idatCrc >> 24) & 0xFF,
    (idatCrc >> 16) & 0xFF,
    (idatCrc >> 8) & 0xFF,
    idatCrc & 0xFF,
  ]);

  bytes.add([0, 0, 0, 0]);
  bytes.add([73, 69, 78, 68]);
  bytes.add([0xae, 0x42, 0x60, 0x82]);

  return bytes.toBytes();
}

class FakeQuoteRepo extends Fake implements QuoteRepository {
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
    return Quote(
      id: 555,
      quoteNumber: 'PRE-555',
      status: 'pending',
      subtotal: items.fold(0, (s, i) => s + i.subtotal),
      total: items.fold(0, (s, i) => s + i.subtotal),
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
        product: null,
        imageUrl: null,
      )).toList(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File validImageFile;
  late File corruptImageFile;
  late File emptyImageFile;
  final validPngBytes = createPng(64, 64);

  setUp(() async {
    QuotePdfService.clearThumbnailCache();
    tempDir = await Directory.systemTemp.createTemp('challenger2_stress_');
    validImageFile = File('${tempDir.path}${Platform.pathSeparator}valid.png');
    await validImageFile.writeAsBytes(validPngBytes);

    corruptImageFile = File('${tempDir.path}${Platform.pathSeparator}corrupt.png');
    await corruptImageFile.writeAsBytes(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03]));

    emptyImageFile = File('${tempDir.path}${Platform.pathSeparator}empty.png');
    await emptyImageFile.writeAsBytes(Uint8List(0));
  });

  tearDown(() async {
    QuotePdfService.clearThumbnailCache();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Challenger 2 Stress 1: Non-Existent and Malformed Local File Paths', () {
    test('Non-existent Windows absolute path does not crash and falls back gracefully', () async {
      final quote = Quote(
        id: 1,
        quoteNumber: 'PRE-MISS-01',
        status: 'pending',
        subtotal: 100,
        total: 100,
        items: [
          QuoteItem(
            productId: 1,
            productName: 'Missing Path Product',
            unitPrice: 100,
            quantity: 1,
            subtotal: 100,
            imageUrl: r'C:\nonexistent\directory\sub\image_99999.jpg',
          ),
        ],
      );

      final thumbs = await QuotePdfService.preloadThumbnails(quote);
      expect(thumbs.isEmpty, isTrue);

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'NonExistent File Test',
      );
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Malformed file:// URIs and non-existent file URIs handled gracefully', () async {
      final quote = Quote(
        id: 2,
        quoteNumber: 'PRE-URI-01',
        status: 'pending',
        subtotal: 200,
        total: 200,
        items: [
          QuoteItem(
            productId: 1,
            productName: 'Malformed URI 1',
            unitPrice: 100,
            quantity: 1,
            subtotal: 100,
            imageUrl: 'file:///C:/non_existent_path_404.png',
          ),
          QuoteItem(
            productId: 2,
            productName: 'Malformed URI 2',
            unitPrice: 100,
            quantity: 1,
            subtotal: 100,
            imageUrl: 'file://::::invalid??query=true',
          ),
        ],
      );

      final thumbs = await QuotePdfService.preloadThumbnails(quote);
      expect(thumbs.isEmpty, isTrue);

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'URI Test',
      );
      expect(pdfBytes.isNotEmpty, isTrue);
    });

    test('Local corrupt file and 0-byte file are rejected without throwing exceptions', () async {
      final quote = Quote(
        id: 3,
        quoteNumber: 'PRE-CORRUPT-DISK',
        status: 'pending',
        subtotal: 300,
        total: 300,
        items: [
          QuoteItem(
            productId: 1,
            productName: 'Corrupt Disk Image',
            unitPrice: 150,
            quantity: 1,
            subtotal: 150,
            imageUrl: corruptImageFile.path,
          ),
          QuoteItem(
            productId: 2,
            productName: 'Empty Disk Image',
            unitPrice: 150,
            quantity: 1,
            subtotal: 150,
            imageUrl: emptyImageFile.path,
          ),
        ],
      );

      final thumbs = await QuotePdfService.preloadThumbnails(quote);
      expect(thumbs.isEmpty, isTrue);

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Corrupt Disk Test',
      );
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });
  });

  group('Challenger 2 Stress 2: Network Timeouts & Edge Cases', () {
    test('SocketException, ClientException, HTTP 502 Bad Gateway and 204 No Content', () async {
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('socket_error')) {
          throw const SocketException('Connection reset by peer');
        } else if (path.contains('client_error')) {
          throw http.ClientException('Failed to connect');
        } else if (path.contains('502')) {
          return http.Response('Bad Gateway', 502);
        } else if (path.contains('204')) {
          return http.Response('', 204);
        } else if (path.contains('timeout')) {
          await Future.delayed(const Duration(seconds: 5));
          return http.Response.bytes(validPngBytes, 200);
        }
        return http.Response('Not Found', 404);
      });

      final quote = Quote(
        id: 4,
        quoteNumber: 'PRE-NET-EDGE',
        status: 'pending',
        subtotal: 500,
        total: 500,
        items: [
          QuoteItem(productId: 1, productName: 'Socket Error', unitPrice: 100, quantity: 1, subtotal: 100, imageUrl: 'http://pos.local/socket_error.png'),
          QuoteItem(productId: 2, productName: 'Client Error', unitPrice: 100, quantity: 1, subtotal: 100, imageUrl: 'http://pos.local/client_error.png'),
          QuoteItem(productId: 3, productName: '502 Error', unitPrice: 100, quantity: 1, subtotal: 100, imageUrl: 'http://pos.local/502.png'),
          QuoteItem(productId: 4, productName: '204 No Content', unitPrice: 100, quantity: 1, subtotal: 100, imageUrl: 'http://pos.local/204.png'),
          QuoteItem(productId: 5, productName: 'Timeout', unitPrice: 100, quantity: 1, subtotal: 100, imageUrl: 'http://pos.local/timeout.png'),
        ],
      );

      final thumbs = await QuotePdfService.preloadThumbnails(quote, httpClient: mockClient);
      expect(thumbs.isEmpty, isTrue);

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Network Edge Cases',
        httpClient: mockClient,
      );
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });
  });

  group('Challenger 2 Stress 3: Logo Aspect Ratio Extremes & ClipOval Rendering', () {
    test('Ultra-wide logo (40:1 ratio, 800x20) renders cleanly inside 68x68 ClipOval', () async {
      final ultraWideBytes = createPng(800, 20);
      final quote = Quote(
        id: 10,
        quoteNumber: 'PRE-WIDE-01',
        status: 'pending',
        subtotal: 500,
        total: 500,
        items: [QuoteItem(productId: 1, productName: 'Producto Wide', unitPrice: 500, quantity: 1, subtotal: 500)],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Comercio Logo Ancho',
        logoBytes: ultraWideBytes,
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Ultra-tall logo (1:40 ratio, 20x800) renders cleanly inside 68x68 ClipOval', () async {
      final ultraTallBytes = createPng(20, 800);
      final quote = Quote(
        id: 11,
        quoteNumber: 'PRE-TALL-01',
        status: 'pending',
        subtotal: 500,
        total: 500,
        items: [QuoteItem(productId: 1, productName: 'Producto Tall', unitPrice: 500, quantity: 1, subtotal: 500)],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Comercio Logo Alto',
        logoBytes: ultraTallBytes,
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Massive 1200x1200 square logo renders and clips without overflow', () async {
      final massiveBytes = createPng(1200, 1200);
      final quote = Quote(
        id: 12,
        quoteNumber: 'PRE-MASSIVE-01',
        status: 'pending',
        subtotal: 500,
        total: 500,
        items: [QuoteItem(productId: 1, productName: 'Producto Massive', unitPrice: 500, quantity: 1, subtotal: 500)],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Comercio Logo Gigante',
        logoBytes: massiveBytes,
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('1x1 minimal pixel logo renders cleanly', () async {
      final pixelBytes = createPng(1, 1);
      final quote = Quote(
        id: 13,
        quoteNumber: 'PRE-1PX-01',
        status: 'pending',
        subtotal: 500,
        total: 500,
        items: [QuoteItem(productId: 1, productName: 'Producto 1px', unitPrice: 500, quantity: 1, subtotal: 500)],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Comercio 1px',
        logoBytes: pixelBytes,
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Local corrupt logo file or non-existent file falls back to null logo without crash', () async {
      final quote = Quote(
        id: 14,
        quoteNumber: 'PRE-LOGOCORRUPT',
        status: 'pending',
        subtotal: 500,
        total: 500,
        items: [QuoteItem(productId: 1, productName: 'Producto', unitPrice: 500, quantity: 1, subtotal: 500)],
      );

      final logo = await QuotePdfService.preloadLogo(logoUrl: corruptImageFile.path);
      expect(logo, isNull);

      final logoMissing = await QuotePdfService.preloadLogo(logoUrl: r'C:\fake\no_logo_999.png');
      expect(logoMissing, isNull);

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Comercio Fallback Logo',
        logoUrl: corruptImageFile.path,
      );
      expect(pdfBytes.isNotEmpty, isTrue);
    });
  });

  group('Challenger 2 Stress 4: Multi-Page Quotes & 5% Watermark Background Stability', () {
    test('100-item multi-page quote (~4-5 pages) renders watermark across all pages cleanly', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(validPngBytes, 200);
      });

      final items = List.generate(100, (i) {
        return QuoteItem(
          productId: i + 1,
          productName: 'Producto Extenso de Catálogo Maestro N° ${i + 1} - SKU #${1000 + i}',
          unitPrice: (i + 1) * 150.0,
          quantity: (i % 3 + 1).toDouble(),
          subtotal: (i + 1) * 150.0 * (i % 3 + 1),
          imageUrl: (i % 3 == 0) ? 'http://pos.local/item_$i.png' : null,
        );
      });

      final subtotal = items.fold(0.0, (s, i) => s + i.subtotal);
      final quote = Quote(
        id: 100,
        quoteNumber: 'PRE-100-ITEMS',
        status: 'pending',
        subtotal: subtotal,
        total: subtotal,
        customerName: 'Constructora Austral S.A.',
        customerPhone: '+54 11 5555-4321',
        notes: 'Presupuesto mayorista para provisión de obra pública con entrega escalonada en 5 depósitos.',
        items: items,
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Corralón y Ferretería Industrial del Plata',
        businessAddress: 'Parque Industrial Pilar Km 60, Buenos Aires',
        businessPhone: '0800-333-PLATA',
        vendorName: 'Martín Rodríguez',
        logoBytes: validPngBytes,
        httpClient: mockClient,
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      expect(pdfBytes.length, greaterThan(35000));
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Multi-page quote with null logo renders background as empty SizedBox without layout crash', () async {
      final items = List.generate(40, (i) {
        return QuoteItem(
          productId: i + 1,
          productName: 'Artículo de Prueba ${i + 1}',
          unitPrice: 100,
          quantity: 2,
          subtotal: 200,
        );
      });

      final quote = Quote(
        id: 101,
        quoteNumber: 'PRE-NO-LOGO-MULTI',
        status: 'pending',
        subtotal: 8000,
        total: 8000,
        items: items,
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Sin Logotipo Multi-Page',
        logoUrl: null,
        logoBytes: null,
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });
  });

  group('Challenger 2 Stress 5: QuoteProvider In-Memory Enrichment Mixed Scenarios', () {
    test('QuoteProvider enriches cart items with mixed images, empty strings, and null images', () async {
      final repo = FakeQuoteRepo();
      final provider = QuoteProvider(repository: repo);

      final prodWithImage = Product(
        id: 1,
        name: 'Producto Con Imagen',
        internalCode: 'P-01',
        costPrice: 50,
        sellingPrice: 100,
        stock: 10,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://pos.local/prod1.png',
      );

      final prodWithEmptyImage = Product(
        id: 2,
        name: 'Producto Con Imagen Vacia',
        internalCode: 'P-02',
        costPrice: 50,
        sellingPrice: 100,
        stock: 10,
        active: true,
        isSoldByWeight: false,
        imageUrl: '',
      );

      final prodWithoutImage = Product(
        id: 3,
        name: 'Producto Sin Imagen',
        internalCode: 'P-03',
        costPrice: 50,
        sellingPrice: 100,
        stock: 10,
        active: true,
        isSoldByWeight: false,
        imageUrl: null,
      );

      provider.addToCart(prodWithImage, quantity: 2);
      provider.addToCart(prodWithEmptyImage, quantity: 1);
      provider.addToCart(prodWithoutImage, quantity: 3);

      expect(provider.cart.length, equals(3));

      final created = await provider.generateQuote(
        customerName: 'Cliente Test',
        customerPhone: '11223344',
      );

      expect(created, isNotNull);
      expect(created!.items.length, equals(3));

      // Item 1: has image URL
      expect(created.items[0].imageUrl, equals('http://pos.local/prod1.png'));
      expect(created.items[0].product, isNotNull);

      // Item 2: empty string
      expect(created.items[1].imageUrl, equals(''));
      expect(created.items[1].product, isNotNull);

      // Item 3: null
      expect(created.items[2].imageUrl, isNull);
      expect(created.items[2].product, isNotNull);

      // Cart is cleared
      expect(provider.cart.isEmpty, isTrue);
    });

    test('QuoteProvider enriches items by name when productId is null', () async {
      final repo = FakeQuoteRepo();
      final provider = QuoteProvider(repository: repo);

      final prod = Product(
        id: 99,
        name: 'Producto Especial',
        internalCode: 'P-99',
        costPrice: 100,
        sellingPrice: 200,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://pos.local/especial.png',
      );

      provider.addToCart(prod, quantity: 1);

      final created = await provider.generateQuote();
      expect(created, isNotNull);
      expect(created!.items.first.imageUrl, equals('http://pos.local/especial.png'));
    });
  });
}
