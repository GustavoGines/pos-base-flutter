import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/utils/product_share_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleProduct = Product(
    id: 101,
    name: 'Yerba Taragüi 1kg',
    barcode: '7791234567890',
    internalCode: 'YER-01',
    costPrice: 2000,
    sellingPrice: 3500,
    stock: 25,
    active: true,
    isSoldByWeight: false,
    category: Category(id: 1, name: 'Almacén'),
    brand: Brand(id: 2, name: 'Taragüi'),
  );

  group('R2 Unit Tests: isPrivateOrLocalUrl', () {
    test('Returns true for null, empty, whitespace strings', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl(null), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl(''), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('   '), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('\t\n'), isTrue);
    });

    test('Returns true for malformed URLs and non-http schemes', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('not_a_valid_url'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('ftp://example.com/image.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('file:///C:/images/image.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('data:image/png;base64,iVBORw0KGgoAAAANSUhEUg=='), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('javascript:alert(1)'), isTrue);
    });

    test('Returns true for loopback addresses (localhost, 127.x.x.x, 0.0.0.0, ::1)', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://localhost/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://localhost:8000/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://127.0.0.1/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://127.0.0.1:8080/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://127.25.10.1/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://0.0.0.0/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[::1]/prod.jpg'), isTrue);
    });

    test('Returns true for RFC 1918 Class A private IP (10.0.0.0/8)', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://10.0.0.1/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://10.254.1.200:9000/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://10.10.10.10/prod.jpg'), isTrue);
    });

    test('Returns true for RFC 1918 Class B private IP (172.16.0.0/12: 172.16 to 172.31)', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.16.0.1/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.20.10.5:8000/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.31.255.255/prod.jpg'), isTrue);
    });

    test('Returns false for 172.x outside RFC 1918 private range', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.15.255.255/prod.jpg'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.32.0.1/prod.jpg'), isFalse);
    });

    test('Returns true for RFC 1918 Class C private IP (192.168.0.0/16)', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://192.168.1.1/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://192.168.1.200/storage/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://192.168.100.50:8000/prod.jpg'), isTrue);
    });

    test('Returns true for Link-Local IPv4 (169.254.0.0/16)', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://169.254.1.1/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://169.254.100.200/prod.jpg'), isTrue);
    });

    test('Returns true for special test/local TLDs (.test, .local, .localhost, .internal, .lan, .invalid, .example)', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://pos.test/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://api.pos.test:8443/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://sistema.local/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://pos-server.localhost/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://server.internal/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://caja1.lan/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://myhost.invalid/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://sample.example/prod.jpg'), isTrue);
    });

    test('Returns true for local/link-local IPv6 (fe80::, fc00::, fd00::)', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[fe80::1]/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[fc00::1]/prod.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[fd12:3456::1]/prod.jpg'), isTrue);
    });

    test('Returns false for public internet hostnames and public IP addresses', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://example.com/images/prod.jpg'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://cdn.mybusiness.com.ar/products/101.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://images.unsplash.com/photo-12345'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://93.184.216.34/prod.jpg'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://142.250.190.46/logo.png'), isFalse);
    });
  });

  group('R2 Unit Tests: buildWhatsAppUri', () {
    test('Builds wa.me URI without phone number (path is /)', () {
      final uri = ProductShareHelper.buildWhatsAppUri(text: 'Hola Mundo');
      expect(uri.scheme, equals('https'));
      expect(uri.host, equals('wa.me'));
      expect(uri.path, equals('/'));
      expect(uri.queryParameters['text'], equals('Hola Mundo'));
      expect(uri.toString(), equals('https://wa.me/?text=Hola+Mundo'));
    });

    test('Builds wa.me URI with formatted phone number, stripping non-digits', () {
      final uri = ProductShareHelper.buildWhatsAppUri(
        phone: '+54 9 11 2345-6789',
        text: 'Consulta de producto',
      );
      expect(uri.scheme, equals('https'));
      expect(uri.host, equals('wa.me'));
      expect(uri.path, equals('/5491123456789'));
      expect(uri.queryParameters['text'], equals('Consulta de producto'));
    });

    test('Properly percent-encodes special characters, newlines and emojis', () {
      final complexText = '📦 *Producto Top*\n💰 Precio: \$3.500\n🔗 https://example.com';
      final uri = ProductShareHelper.buildWhatsAppUri(text: complexText);
      expect(uri.queryParameters['text'], equals(complexText));
      expect(uri.toString(), contains('wa.me'));
      expect(uri.toString(), contains('text='));
    });
  });

  group('Desktop/Web Flow Tests (isMobile: false)', () {
    test('Image URL: downloads image, copies text to clipboard, and invokes shareFilesFn', () async {
      final productWithImage = sampleProduct.copyWith(
        imageUrl: 'http://example.com/photos/yerba.jpg',
      );

      final mockJpegBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
      final mockClient = MockClient((request) async {
        return http.Response.bytes(mockJpegBytes, 200);
      });

      final testTempDir = await Directory.systemTemp.createTemp('share_desktop_test_');

      List<XFile>? sharedFiles;
      String? captionText;
      String? noticeMessage;
      String? copiedText;

      try {
        await ProductShareHelper.shareProduct(
          productWithImage,
          isMobile: false,
          httpClient: mockClient,
          getTempDir: () async => testTempDir,
          shareFilesFn: (files, {text, subject}) async {
            sharedFiles = files;
            captionText = text;
          },
          copyToClipboardFn: (text) async {
            copiedText = text;
          },
          onShowNotice: (msg, {isError = false}) {
            noticeMessage = msg;
          },
        );

        expect(sharedFiles, isNotNull);
        expect(sharedFiles!.length, equals(1));
        expect(captionText, contains('Yerba Taragüi 1kg'));
        expect(captionText, contains('\$3.500'));
        expect(copiedText, isNotNull);
        expect(copiedText, contains('Yerba Taragüi 1kg'));
        expect(noticeMessage, equals('Foto lista y texto copiado al portapapeles. Pegalo con Ctrl+V en el pie de la foto.'));
      } finally {
        if (testTempDir.existsSync()) {
          testTempDir.deleteSync(recursive: true);
        }
      }
    });

    test('Product without image URL: copies text to clipboard and invokes shareTextFn', () async {
      final productNoImage = sampleProduct.copyWith(imageUrl: null);

      String? sharedText;
      String? noticeMessage;
      String? copiedText;

      await ProductShareHelper.shareProduct(
        productNoImage,
        isMobile: false,
        shareTextFn: (text, {subject}) async {
          sharedText = text;
        },
        copyToClipboardFn: (text) async => copiedText = text,
        onShowNotice: (msg, {isError = false}) => noticeMessage = msg,
      );

      expect(sharedText, isNotNull);
      expect(sharedText, contains('Yerba Taragüi 1kg'));
      expect(copiedText, isNotNull);
      expect(copiedText, contains('Yerba Taragüi 1kg'));
      expect(noticeMessage, equals('Texto del producto copiado al portapapeles'));
    });

    test('Image download failure: falls back to shareTextFn and notifies user', () async {
      final productWithBrokenImage = sampleProduct.copyWith(
        imageUrl: 'http://example.com/broken.jpg',
      );

      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      String? sharedText;
      String? noticeMessage;
      String? copiedText;

      await ProductShareHelper.shareProduct(
        productWithBrokenImage,
        isMobile: false,
        httpClient: mockClient,
        shareTextFn: (text, {subject}) async {
          sharedText = text;
        },
        copyToClipboardFn: (text) async => copiedText = text,
        onShowNotice: (msg, {isError = false}) {
          noticeMessage = msg;
        },
      );

      expect(sharedText, isNotNull);
      expect(sharedText, contains('Yerba Taragüi 1kg'));
      expect(copiedText, isNotNull);
      expect(noticeMessage, equals('No se pudo adjuntar la foto. Texto copiado al portapapeles.'));
    });

    test('Native share exception on image: falls back to wa.me launchUrl', () async {
      final productWithImage = sampleProduct.copyWith(
        imageUrl: 'http://example.com/yerba.png',
      );

      final mockPngBytes = [0x89, 0x50, 0x4E, 0x47];
      final mockClient = MockClient((request) async {
        return http.Response.bytes(mockPngBytes, 200);
      });

      final testTempDir = await Directory.systemTemp.createTemp('share_throw_test_');
      Uri? launchedUri;

      try {
        await ProductShareHelper.shareProduct(
          productWithImage,
          isMobile: false,
          httpClient: mockClient,
          getTempDir: () async => testTempDir,
          shareFilesFn: (files, {text, subject}) async {
            throw Exception('Share dialog not available on this Windows build');
          },
          shareTextFn: (text, {subject}) async {
            throw Exception('Share text not available');
          },
          launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
            launchedUri = uri;
            return true;
          },
        );

        expect(launchedUri, isNotNull);
        expect(launchedUri!.host, equals('wa.me'));
        expect(launchedUri!.queryParameters['text'], contains('Yerba Taragüi 1kg'));
      } finally {
        if (testTempDir.existsSync()) {
          testTempDir.deleteSync(recursive: true);
        }
      }
    });

    test('WhatsApp Launch Failure on fallback: copies text to clipboard and shows error notice', () async {
      final productNoImage = sampleProduct.copyWith(imageUrl: null);
      String? copiedText;
      String? noticeMessage;
      bool? noticeIsError;

      await ProductShareHelper.shareProduct(
        productNoImage,
        isMobile: false,
        shareTextFn: (text, {subject}) async {
          throw Exception('Share not available');
        },
        canLaunchUrlFn: (uri) async => false,
        copyToClipboardFn: (text) async => copiedText = text,
        onShowNotice: (msg, {isError = false}) {
          noticeMessage = msg;
          noticeIsError = isError;
        },
      );

      expect(copiedText, isNotNull);
      expect(copiedText, contains('Yerba Taragüi 1kg'));
      expect(noticeMessage, equals('No se pudo abrir WhatsApp. Texto copiado al portapapeles.'));
      expect(noticeIsError, isTrue);
    });
  });

  group('Mobile Flow Integrity (isMobile: true)', () {
    test('Mobile flow downloads image and calls shareFilesFn', () async {
      final productWithImage = sampleProduct.copyWith(
        imageUrl: 'http://example.com/yerba.png',
      );

      final mockPngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final mockClient = MockClient((request) async {
        return http.Response.bytes(mockPngBytes, 200);
      });

      final testTempDir = await Directory.systemTemp.createTemp('share_mobile_test_');

      List<XFile>? sharedFiles;
      String? captionText;
      bool launchUrlCalled = false;

      try {
        await ProductShareHelper.shareProduct(
          productWithImage,
          isMobile: true,
          httpClient: mockClient,
          getTempDir: () async => testTempDir,
          shareFilesFn: (files, {text, subject}) async {
            sharedFiles = files;
            captionText = text;
          },
          launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
            launchUrlCalled = true;
            return true;
          },
        );

        expect(launchUrlCalled, isFalse);
        expect(sharedFiles, isNotNull);
        expect(sharedFiles!.length, equals(1));
        expect(captionText, contains('Yerba Taragüi 1kg'));
      } finally {
        if (testTempDir.existsSync()) {
          testTempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('Widget Context Notification Integration', () {
    testWidgets('Displays SnackBarService notice when onShowNotice callback is omitted on desktop text share', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await ProductShareHelper.shareProduct(
                    sampleProduct.copyWith(imageUrl: null),
                    context: context,
                    isMobile: false,
                    shareTextFn: (text, {subject}) async {},
                    copyToClipboardFn: (text) async {},
                  );
                },
                child: const Text('Compartir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Compartir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Texto del producto copiado al portapapeles'), findsOneWidget);
    });

    testWidgets('Displays SnackBarService error when WhatsApp launch fails and onShowNotice is omitted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await ProductShareHelper.shareProduct(
                    sampleProduct.copyWith(imageUrl: null),
                    context: context,
                    isMobile: false,
                    shareTextFn: (text, {subject}) async {
                      throw Exception('Share unavailable');
                    },
                    canLaunchUrlFn: (uri) async => false,
                    copyToClipboardFn: (text) async {},
                  );
                },
                child: const Text('Compartir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Compartir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No se pudo abrir WhatsApp. Texto copiado al portapapeles.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
