import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/services/quote_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generateQuotePdf behavior when network returns 200 OK with corrupted image bytes', () async {
    QuotePdfService.clearThumbnailCache();

    // Random non-image bytes (e.g., HTML response or garbage)
    final corruptedBytes = Uint8List.fromList(utf8.encode('<html><body>502 Bad Gateway</body></html>'));

    final mockClient = MockClient((request) async {
      return http.Response.bytes(corruptedBytes, 200);
    });

    final quote = Quote(
      id: 999,
      quoteNumber: 'PRE-CORRUPT',
      status: 'pending',
      subtotal: 500,
      total: 500,
      items: [
        QuoteItem(
          productId: 1,
          productName: 'Producto Con Imagen Corrupta',
          unitPrice: 500,
          quantity: 1,
          subtotal: 500,
          imageUrl: 'http://example.com/corrupted.png',
        ),
      ],
    );

    // Let's see if generateQuotePdf throws an exception or handles it
    try {
      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Test Corrupt',
        httpClient: mockClient,
      );
      expect(pdfBytes, isNotNull);
      print('RESULT: generateQuotePdf succeeded with size ${pdfBytes.length}');
    } catch (e, stack) {
      print('RESULT: generateQuotePdf THREW: $e\n$stack');
      rethrow;
    }
  });

  test('generateQuotePdf handles quote with 0 items cleanly', () async {
    final quote = Quote(
      id: 1000,
      quoteNumber: 'PRE-EMPTY',
      status: 'pending',
      subtotal: 0,
      total: 0,
      items: [],
    );

    final pdfBytes = await QuotePdfService.generateQuotePdf(
      quote: quote,
      businessName: 'Empty Test',
    );
    expect(pdfBytes, isNotNull);
    expect(pdfBytes.isNotEmpty, isTrue);
    expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
  });

  test('generateQuotePdf handles extreme character lengths and special characters', () async {
    final quote = Quote(
      id: 1001,
      quoteNumber: 'PRE-EXTREME',
      status: 'pending',
      subtotal: 999999999,
      total: 999999999,
      customerName: 'Cliente con nombre larguísimo ' * 10,
      customerPhone: '+54 9 11 9999-8888 / 7777 / 6666',
      notes: 'Nota muy extensa sin saltos de línea ' * 20,
      items: [
        QuoteItem(
          productId: 99,
          productName: 'ProductoConNombreGiganteSinEspaciosParaProbarSaltoDeLinea' * 4,
          unitPrice: 999999999,
          quantity: 9999,
          subtotal: 999999999,
          imageUrl: null,
        ),
      ],
    );

    final pdfBytes = await QuotePdfService.generateQuotePdf(
      quote: quote,
      businessName: 'Comercio Extremo',
    );
    expect(pdfBytes, isNotNull);
    expect(pdfBytes.isNotEmpty, isTrue);
    expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
  });

  test('generateQuotePdf handles network timeout and connection refused gracefully', () async {
    QuotePdfService.clearThumbnailCache();

    final mockClient = MockClient((request) async {
      if (request.url.toString().contains('timeout')) {
        await Future.delayed(const Duration(milliseconds: 100));
        throw http.ClientException('Connection refused');
      }
      throw Exception('SocketException: OS Error: Connection reset by peer');
    });

    final quote = Quote(
      id: 1002,
      quoteNumber: 'PRE-TIMEOUT',
      status: 'pending',
      subtotal: 100,
      total: 100,
      items: [
        QuoteItem(
          productId: 1,
          productName: 'Producto Timeout',
          unitPrice: 100,
          quantity: 1,
          subtotal: 100,
          imageUrl: 'http://example.com/timeout.png',
        ),
      ],
    );

    final pdfBytes = await QuotePdfService.generateQuotePdf(
      quote: quote,
      businessName: 'Timeout Test',
      httpClient: mockClient,
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.isNotEmpty, isTrue);
    expect(ascii.decode(pdfBytes.sublist(0, 5)), equals('%PDF-'));
  });
}
