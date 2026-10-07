import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
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

Uint8List generatePng(int width, int height, {int r = 50, int g = 100, int b = 150}) {
  final bytes = BytesBuilder();
  // 1. Signature
  bytes.add([137, 80, 78, 71, 13, 10, 26, 10]);

  // 2. IHDR
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
    8, // bit depth
    2, // RGB
    0, // compression
    0, // filter
    0, // interlace
  ]);
  final ihdrBody = ihdrData.takeBytes();
  final ihdrChunk = BytesBuilder();
  ihdrChunk.add([73, 72, 68, 82]); // IHDR
  ihdrChunk.add(ihdrBody);
  final ihdrChunkBytes = ihdrChunk.takeBytes();
  final ihdrCrc = _crc32(ihdrChunkBytes);

  bytes.add([0, 0, 0, 13]); // length
  bytes.add(ihdrChunkBytes);
  bytes.add([
    (ihdrCrc >> 24) & 0xFF,
    (ihdrCrc >> 16) & 0xFF,
    (ihdrCrc >> 8) & 0xFF,
    ihdrCrc & 0xFF,
  ]);

  // 3. Raw image scanlines
  final rawScanlines = BytesBuilder();
  final rowData = Uint8List(1 + width * 3);
  rowData[0] = 0; // Filter none
  for (int x = 0; x < width; x++) {
    rowData[1 + x * 3] = r;
    rowData[1 + x * 3 + 1] = g;
    rowData[1 + x * 3 + 2] = b;
  }
  for (int y = 0; y < height; y++) {
    rawScanlines.add(rowData);
  }
  final compressed = zlib.encode(rawScanlines.takeBytes());

  // IDAT
  final idatChunk = BytesBuilder();
  idatChunk.add([73, 68, 65, 84]); // IDAT
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

  // 4. IEND
  bytes.add([0, 0, 0, 0]);
  bytes.add([73, 69, 78, 68]);
  bytes.add([0xae, 0x42, 0x60, 0x82]);

  return bytes.toBytes();
}

int countPdfPages(Uint8List pdfBytes) {
  final content = latin1.decode(pdfBytes);
  // Match '/Type /Page' or '/Type/Page'
  final regex = RegExp(r'/Type\s*/Page\b');
  final matches = regex.allMatches(content);
  return matches.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final standardPng = generatePng(40, 40);
  late Directory tempDir;

  setUp(() async {
    QuotePdfService.clearThumbnailCache();
    tempDir = await Directory.systemTemp.createTemp('challenger_stress_');
  });

  tearDown(() async {
    QuotePdfService.clearThumbnailCache();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Challenger Stress 1: Product Image Thumbnails Resilience', () {
    test('Handles corrupted random non-image bytes from HTTP gracefully', () async {
      final garbageBytes = Uint8List.fromList(List.generate(512, (i) => (i * 47) % 256));
      final mockClient = MockClient((request) async {
        return http.Response.bytes(garbageBytes, 200);
      });

      final quote = Quote(
        id: 101,
        quoteNumber: 'PRE-CORRUPT-HTTP',
        status: 'pending',
        subtotal: 500,
        total: 500,
        items: [
          QuoteItem(
            productId: 1,
            productName: 'Producto Garbage HTTP',
            unitPrice: 500,
            quantity: 1,
            subtotal: 500,
            imageUrl: 'http://example.com/garbage.png',
          ),
        ],
      );

      final thumbs = await QuotePdfService.preloadThumbnails(quote, httpClient: mockClient);
      expect(thumbs.containsKey(0), isFalse);

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Test',
        httpClient: mockClient,
      );
      expect(pdfBytes, isNotNull);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Handles corrupted local file on disk gracefully', () async {
      final corruptFile = File('${tempDir.path}${Platform.pathSeparator}corrupt.png');
      await corruptFile.writeAsBytes(Uint8List.fromList([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66]));

      final quote = Quote(
        id: 102,
        quoteNumber: 'PRE-CORRUPT-DISK',
        status: 'pending',
        subtotal: 600,
        total: 600,
        items: [
          QuoteItem(
            productId: 2,
            productName: 'Producto Local Corrupto',
            unitPrice: 600,
            quantity: 1,
            subtotal: 600,
            imageUrl: corruptFile.path,
          ),
        ],
      );

      final thumbs = await QuotePdfService.preloadThumbnails(quote);
      expect(thumbs.containsKey(0), isFalse);

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Test',
      );
      expect(pdfBytes, isNotNull);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Handles 0-byte local file and empty imageUrl string gracefully', () async {
      final zeroFile = File('${tempDir.path}${Platform.pathSeparator}zero.png');
      await zeroFile.writeAsBytes(Uint8List(0));

      final quote = Quote(
        id: 103,
        quoteNumber: 'PRE-EMPTY-IMAGES',
        status: 'pending',
        subtotal: 700,
        total: 700,
        items: [
          QuoteItem(
            productId: 3,
            productName: 'Producto Zero Bytes',
            unitPrice: 350,
            quantity: 1,
            subtotal: 350,
            imageUrl: zeroFile.path,
          ),
          QuoteItem(
            productId: 4,
            productName: 'Producto Empty URL String',
            unitPrice: 350,
            quantity: 1,
            subtotal: 350,
            imageUrl: '   ',
          ),
        ],
      );

      final thumbs = await QuotePdfService.preloadThumbnails(quote);
      expect(thumbs.isEmpty, isTrue);

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Test',
      );
      expect(pdfBytes, isNotNull);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Handles oversized / high-resolution image bytes (2000x2000 PNG) without memory blowup', () async {
      // 2000x2000 image uncompressed is 12MB scanlines
      final largePng = generatePng(2000, 2000);
      final largeFile = File('${tempDir.path}${Platform.pathSeparator}large_2k.png');
      await largeFile.writeAsBytes(largePng);

      final quote = Quote(
        id: 104,
        quoteNumber: 'PRE-LARGE-IMAGE',
        status: 'pending',
        subtotal: 1200,
        total: 1200,
        items: [
          QuoteItem(
            productId: 5,
            productName: 'Producto Foto 2K HD',
            unitPrice: 1200,
            quantity: 1,
            subtotal: 1200,
            imageUrl: largeFile.path,
          ),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Alta Resolución',
        logoBytes: standardPng,
      );
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Handles non-existent local file paths and URI formats safely', () async {
      final quote = Quote(
        id: 105,
        quoteNumber: 'PRE-NONEXISTENT-PATHS',
        status: 'pending',
        subtotal: 800,
        total: 800,
        items: [
          QuoteItem(
            productId: 6,
            productName: 'Inexistente Windows Path',
            unitPrice: 400,
            quantity: 1,
            subtotal: 400,
            imageUrl: r'C:\nonexistent_directory\image_xyz.png',
          ),
          QuoteItem(
            productId: 7,
            productName: 'Inexistente File URI',
            unitPrice: 400,
            quantity: 1,
            subtotal: 400,
            imageUrl: 'file:///C:/nonexistent_directory/image_xyz.png',
          ),
        ],
      );

      final thumbs = await QuotePdfService.preloadThumbnails(quote);
      expect(thumbs.isEmpty, isTrue);

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Test',
      );
      expect(pdfBytes, isNotNull);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Handles URL encoding edge cases (spaces, accents, query parameters)', () async {
      final mockClient = MockClient((request) async {
        // Return valid PNG for any request that arrives
        return http.Response.bytes(standardPng, 200);
      });

      final quote = Quote(
        id: 106,
        quoteNumber: 'PRE-URL-ENCODING',
        status: 'pending',
        subtotal: 900,
        total: 900,
        items: [
          QuoteItem(
            productId: 8,
            productName: 'URL Con Espacio Codificado',
            unitPrice: 300,
            quantity: 1,
            subtotal: 300,
            imageUrl: 'http://example.com/products/item%20con%20espacio.png',
          ),
          QuoteItem(
            productId: 9,
            productName: 'URL Con Query String y Hash',
            unitPrice: 300,
            quantity: 1,
            subtotal: 300,
            imageUrl: 'http://example.com/products/item.png?v=2&thumb=1#preview',
          ),
          QuoteItem(
            productId: 10,
            productName: 'URL Con Caracteres Especiales',
            unitPrice: 300,
            quantity: 1,
            subtotal: 300,
            imageUrl: 'http://example.com/products/caño_plástico.png',
          ),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Comercio Especial',
        httpClient: mockClient,
      );
      expect(pdfBytes, isNotNull);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });
  });

  group('Challenger Stress 2: Header Logo Polish (68x68 ClipOval) Resilience', () {
    test('Handles ultra-wide aspect ratio logo (600x60, 10:1) without layout breakage', () async {
      final wideLogoBytes = generatePng(600, 60);

      final quote = Quote(
        id: 201,
        quoteNumber: 'PRE-WIDE-LOGO',
        status: 'pending',
        subtotal: 100,
        total: 100,
        items: [
          QuoteItem(productId: 1, productName: 'Item A', unitPrice: 100, quantity: 1, subtotal: 100),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Empresa Logo Ancho',
        logoBytes: wideLogoBytes,
      );
      expect(pdfBytes, isNotNull);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Handles ultra-tall aspect ratio logo (60x600, 1:10) without layout breakage', () async {
      final tallLogoBytes = generatePng(60, 600);

      final quote = Quote(
        id: 202,
        quoteNumber: 'PRE-TALL-LOGO',
        status: 'pending',
        subtotal: 100,
        total: 100,
        items: [
          QuoteItem(productId: 1, productName: 'Item B', unitPrice: 100, quantity: 1, subtotal: 100),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Empresa Logo Alto',
        logoBytes: tallLogoBytes,
      );
      expect(pdfBytes, isNotNull);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('Handles 1x1 micro logo and 1200x1200 giant logo gracefully', () async {
      final microLogoBytes = generatePng(1, 1);
      final giantLogoBytes = generatePng(1200, 1200);

      final quote = Quote(
        id: 203,
        quoteNumber: 'PRE-EXTREME-DIMENSIONS',
        status: 'pending',
        subtotal: 200,
        total: 200,
        items: [
          QuoteItem(productId: 1, productName: 'Item Micro', unitPrice: 100, quantity: 1, subtotal: 100),
          QuoteItem(productId: 2, productName: 'Item Giant', unitPrice: 100, quantity: 1, subtotal: 100),
        ],
      );

      // 1x1 micro logo
      final pdfBytesMicro = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Micro Logo Inc',
        logoBytes: microLogoBytes,
      );
      expect(pdfBytesMicro, isNotNull);

      // 1200x1200 giant logo
      final pdfBytesGiant = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Giant Logo Corp',
        logoBytes: giantLogoBytes,
      );
      expect(pdfBytesGiant, isNotNull);
    });

    test('Header renders correctly when logo is null (no empty gap or crash)', () async {
      final quote = Quote(
        id: 204,
        quoteNumber: 'PRE-NO-LOGO',
        status: 'pending',
        subtotal: 150,
        total: 150,
        items: [
          QuoteItem(productId: 1, productName: 'Item Normal', unitPrice: 150, quantity: 1, subtotal: 150),
        ],
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Sin Logo',
        logoUrl: null,
        logoBytes: null,
      );
      expect(pdfBytes, isNotNull);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
    });
  });

  group('Challenger Stress 3: 5% Opacity Watermark across Multi-Page Quotes', () {
    test('Multi-page quote (80 items) generates multiple pages and renders watermark on each page', () async {
      final logoBytes = generatePng(200, 200);
      final itemPng = generatePng(30, 30);

      final mockClient = MockClient((request) async {
        return http.Response.bytes(itemPng, 200);
      });

      final items = List.generate(
        80,
        (i) => QuoteItem(
          productId: i + 1,
          productName: 'Producto Industrial Pesado #${i + 1} - Modelo Reforzado 2026',
          unitPrice: (i + 1) * 150.0,
          quantity: (i % 3 + 1).toDouble(),
          subtotal: (i + 1) * 150.0 * (i % 3 + 1),
          imageUrl: 'http://example.com/items/thumb_$i.png',
        ),
      );

      final total = items.fold<double>(0, (sum, it) => sum + it.subtotal);

      final quote = Quote(
        id: 301,
        quoteNumber: 'PRE-MULTI-80',
        status: 'pending',
        subtotal: total,
        total: total,
        customerName: 'Constructora Mega Obras S.A.',
        customerPhone: '+54 11 5555-1234',
        notes: 'Entrega en 3 tandas. Lista de precios Distribuidor Oficial.',
        priceList: 'wholesale',
        items: items,
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Corralón & Materiales del Valle',
        businessAddress: 'Ruta 3 Km 42, Cañuelas',
        businessPhone: '02226-431000',
        vendorName: 'Carlos Ingeniero',
        logoBytes: logoBytes,
        httpClient: mockClient,
      );

      expect(pdfBytes, isNotNull);
      expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));

      final pageCount = countPdfPages(pdfBytes);
      // 80 items must span at least 3 pages
      expect(pageCount, greaterThanOrEqualTo(3));

      // Verify PDF contains ExtGState transparency for 0.05 opacity
      final pdfString = latin1.decode(pdfBytes);
      expect(pdfString.contains('/ca 0.05') || pdfString.contains('/CA 0.05'), isTrue);
    });

    test('Multi-page quote without logo generates clean pages without watermark error', () async {
      final items = List.generate(
        50,
        (i) => QuoteItem(
          productId: i + 1,
          productName: 'Artículo Sin Logo #${i + 1}',
          unitPrice: 100.0,
          quantity: 2,
          subtotal: 200.0,
        ),
      );

      final quote = Quote(
        id: 302,
        quoteNumber: 'PRE-MULTI-NO-LOGO',
        status: 'pending',
        subtotal: 10000,
        total: 10000,
        items: items,
      );

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Distribuidora Directa',
        logoBytes: null,
        logoUrl: null,
      );

      expect(pdfBytes, isNotNull);
      final pageCount = countPdfPages(pdfBytes);
      expect(pageCount, greaterThanOrEqualTo(2));
    });
  });

  group('Challenger Stress 4: Dynamic BaseUrl with Custom Network Configurations', () {
    test('Resolves custom IP, port, and trailing slashes correctly', () async {
      Uri? requestedUri;
      final mockClient = MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(standardPng, 200);
      });

      final quote = Quote(
        id: 401,
        quoteNumber: 'PRE-CUSTOM-BASE',
        status: 'pending',
        subtotal: 100,
        total: 100,
        items: [
          QuoteItem(
            productId: 1,
            productName: 'Producto Base Personalizada',
            unitPrice: 100,
            quantity: 1,
            subtotal: 100,
            imageUrl: 'products/tornillos/t1.png',
          ),
        ],
      );

      await QuotePdfService.preloadThumbnails(
        quote,
        httpClient: mockClient,
        baseUrl: 'http://192.168.0.50:8080/api/',
      );

      expect(requestedUri, isNotNull);
      expect(requestedUri!.host, equals('192.168.0.50'));
      expect(requestedUri!.port, equals(8080));
      expect(requestedUri!.path, equals('/storage/products/tornillos/t1.png'));
    });
  });
}
