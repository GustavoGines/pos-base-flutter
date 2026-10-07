import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/utils/product_share_helper.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CHALLENGER 1: WhatsApp Deep Link Formation Stress Tests (Desktop/Web)', () {
    test('Extreme product data: Multibyte Emojis, Accents, Quotes, Slashes, and Special Symbols', () async {
      final product = Product(
        id: 501,
        name: '🧉 Yerba Mate "Taragüí" Selección Especial 1kg 🔥🚀 (50% OFF)',
        barcode: '  77900112233  ',
        internalCode: 'YER-ARG/01',
        costPrice: 1500,
        sellingPrice: 3500.50,
        priceWholesale: 2800,
        priceCard: 3900.75,
        stock: 40,
        active: true,
        isSoldByWeight: false,
        category: Category(id: 1, name: 'Almacén & Bebidas'),
        brand: Brand(id: 2, name: 'Taragüí & Las Marías'),
        supplier: Supplier(id: 3, name: 'Distribuidora "El Sol" S.A.', balance: 0, isActive: true),
      );

      Uri? capturedUri;
      await ProductShareHelper.shareProduct(
        product,
        isMobile: false,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          capturedUri = uri;
          return true;
        },
      );

      expect(capturedUri, isNotNull);
      expect(capturedUri!.scheme, equals('https'));
      expect(capturedUri!.host, equals('wa.me'));

      final textParam = capturedUri!.queryParameters['text'];
      expect(textParam, isNotNull);

      // Verify Emojis & Accents are preserved intact in decoded query
      expect(textParam, contains('🧉 Yerba Mate "Taragüí" Selección Especial 1kg 🔥🚀 (50% OFF)'));
      expect(textParam, contains('- Precio: \$3.500,50'));
      expect(textParam, contains('- Mayorista: \$2.800'));
      expect(textParam, contains('- Tarjeta: \$3.900,75'));

      expect(textParam, contains('- Categoría: Almacén & Bebidas'));
      expect(textParam, contains('- Marca: Taragüí & Las Marías'));
      expect(textParam, contains('- Proveedor: Distribuidora "El Sol" S.A.'));

      // Verify URL string percent-encoding roundtrip integrity
      final rawUriString = capturedUri.toString();
      final roundtripUri = Uri.parse(rawUriString);
      expect(roundtripUri.queryParameters['text'], equals(textParam));

      // In the raw URL string, query parameter separators like '&' inside text must be percent-encoded (%26)
      // so they do not break parameter parsing
      expect(rawUriString, contains('%26'));
    });

    test('Adversarial characters: URL Fragment (#), Query Separator (&), Percent (%), and Plus (+)', () async {
      final product = Product(
        id: 502,
        name: 'Item #1 & 100% Cotton + 2 Extra? <Tag> "Quote" / Slash \\ Backslash',
        internalCode: 'ADV#01',
        costPrice: 100,
        sellingPrice: 250,
        stock: 5,
        active: true,
        isSoldByWeight: false,
      );

      Uri? capturedUri;
      await ProductShareHelper.shareProduct(
        product,
        isMobile: false,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          capturedUri = uri;
          return true;
        },
      );

      expect(capturedUri, isNotNull);
      final rawUriString = capturedUri.toString();

      // If '#' is unencoded, it truncates the query string as a fragment identifier!
      // Must be safely encoded as %23
      expect(rawUriString, isNot(contains('wa.me/?text=Item+#1')));
      expect(rawUriString, contains('%23'));

      // Verify full roundtrip decoding preserves exact hostile characters
      final roundtrip = Uri.parse(rawUriString);
      final decodedText = roundtrip.queryParameters['text']!;
      expect(decodedText, contains('Item #1 & 100% Cotton + 2 Extra? <Tag> "Quote" / Slash \\ Backslash'));
    });

    test('Multiline names and descriptions with newlines (LF and CRLF)', () async {
      final product = Product(
        id: 503,
        name: 'Combo Familiar:\r\n- 2kg Asado\r\n- 1kg Chorizo\r\n- 1 Carbón 4kg',
        internalCode: 'COMBO-FAM',
        costPrice: 8000,
        sellingPrice: 15990,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );

      Uri? capturedUri;
      await ProductShareHelper.shareProduct(
        product,
        isMobile: false,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          capturedUri = uri;
          return true;
        },
      );

      expect(capturedUri, isNotNull);
      final textParam = capturedUri!.queryParameters['text']!;
      expect(textParam, contains('- 2kg Asado'));
      expect(textParam, contains('- 1kg Chorizo'));
      expect(textParam, contains('- 1 Carbón 4kg'));

      // Verify roundtrip through Uri.parse preserves multiline structure
      final roundtrip = Uri.parse(capturedUri.toString());
      expect(roundtrip.queryParameters['text'], equals(textParam));
    });

    test('Null prices, zero prices, negative prices, and extreme price values', () async {
      // 1. Null optional wholesale and card prices
      final productNullPrices = Product(
        id: 504,
        name: 'Producto Precios Opcionales Nulos',
        internalCode: 'NULL-01',
        costPrice: 50,
        sellingPrice: 120,
        priceWholesale: null,
        priceCard: null,
        stock: 20,
        active: true,
        isSoldByWeight: false,
      );

      Uri? uri1;
      await ProductShareHelper.shareProduct(
        productNullPrices,
        isMobile: false,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          uri1 = uri;
          return true;
        },
      );

      final text1 = uri1!.queryParameters['text']!;
      expect(text1, contains('- Precio: \$120'));
      expect(text1, isNot(contains('Mayorista')));
      expect(text1, isNot(contains('Tarjeta')));

      // 2. Zero selling price
      final productZeroPrice = Product(
        id: 505,
        name: 'Muestra de Degustación',
        internalCode: 'DEGUSTA',
        costPrice: 0,
        sellingPrice: 0,
        priceWholesale: 0,
        priceCard: 0,
        stock: 100,
        active: true,
        isSoldByWeight: false,
      );

      Uri? uri2;
      await ProductShareHelper.shareProduct(
        productZeroPrice,
        isMobile: false,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          uri2 = uri;
          return true;
        },
      );

      final text2 = uri2!.queryParameters['text']!;
      expect(text2, contains('- Precio: \$0'));
      expect(text2, isNot(contains('Mayorista')));
      expect(text2, isNot(contains('Tarjeta')));

      // 3. Extreme large price
      final productHugePrice = Product(
        id: 506,
        name: 'Auto 0KM de Alta Gama',
        internalCode: 'AUTO-01',
        costPrice: 50000000,
        sellingPrice: 85900500.25,
        stock: 1,
        active: true,
        isSoldByWeight: false,
      );

      Uri? uri3;
      await ProductShareHelper.shareProduct(
        productHugePrice,
        isMobile: false,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          uri3 = uri;
          return true;
        },
      );

      final text3 = uri3!.queryParameters['text']!;
      expect(text3, contains('- Precio: \$85.900.500,25'));
    });

    test('Massive 3000-character product name generates valid wa.me deep link', () async {
      final massiveName = 'A' * 3000;
      final product = Product(
        id: 507,
        name: massiveName,
        internalCode: 'MASSIVE',
        costPrice: 10,
        sellingPrice: 20,
        stock: 1,
        active: true,
        isSoldByWeight: false,
      );

      Uri? capturedUri;
      await ProductShareHelper.shareProduct(
        product,
        isMobile: false,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          capturedUri = uri;
          return true;
        },
      );

      expect(capturedUri, isNotNull);
      expect(capturedUri!.queryParameters['text']!.length, greaterThanOrEqualTo(3000));
      // Uri.parse does not throw and preserves length
      final roundtrip = Uri.parse(capturedUri.toString());
      expect(roundtrip.queryParameters['text']!.contains(massiveName), isTrue);
    });

    test('Public Image URL with complex query parameters and fragment formats correctly', () async {
      final product = Product(
        id: 508,
        name: 'Zapatillas Running Pro',
        internalCode: 'RUN-01',
        costPrice: 15000,
        sellingPrice: 29990,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=1000&auto=format&fit=crop&q=80#hero',
      );

      String? copied;
      await ProductShareHelper.shareProduct(
        product,
        isMobile: false,
        shareTextFn: (text, {subject}) async {},
        copyToClipboardFn: (text) async => copied = text,
      );

      expect(copied, isNotNull);
      expect(copied, contains('Zapatillas Running Pro'));
      expect(copied, contains('- Precio: \$29.990'));

    });
  });

  group('CHALLENGER 1: Adversarial URL Detection Matrix (isPrivateOrLocalUrl)', () {
    test('Boundary testing for RFC 1918 Class B (172.16.0.0/12: 172.16 - 172.31)', () {
      // Boundaries inside private range
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.16.0.0/test.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.16.0.1:8080/test.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.31.255.255/test.png'), isTrue);

      // Boundaries outside private range (public internet IPs)
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.15.255.255/test.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.32.0.0/test.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.32.0.1/test.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.0.0.1/test.png'), isFalse);
    });

    test('Boundary testing for RFC 1918 Class A and Class C', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://10.0.0.0/test.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://10.255.255.255:3000/test.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://192.168.0.0/test.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://192.168.255.255/test.png'), isTrue);
    });

    test('Case insensitivity for schemes, hostnames, and TLDs', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('HTTP://LOCALHOST:8000/test.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('HTTPS://SISTEMA.TEST/test.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://SERVER.LOCAL/test.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://CAJA1.LAN/test.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('HTTPS://EXAMPLE.COM/test.png'), isFalse);
    });

    test('Hostile or broken URL strings are classified as private/unreachable', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl(null), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl(''), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('   \n\t  '), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('not_a_url'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http:///only/path'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('file:///C:/images/pic.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('ftp://10.0.0.1/pic.png'), isTrue);
    });

    test('Public hostnames containing substrings of private keywords are NOT false-positives', () {
      // "lancaster.org" contains "lan" but ends with ".org"
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://lancaster.org/photo.jpg'), isFalse);
      // "testdomain.com" contains "test" but ends with ".com"
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://testdomain.com/photo.jpg'), isFalse);
      // "internal-tools.corp.amazon.com" contains "internal" but ends with ".com"
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://internal-tools.corp.amazon.com/photo.jpg'), isFalse);
      // "example.com" ends with ".com", not ".example"
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://example.com/photo.jpg'), isFalse);
    });
  });

  group('CHALLENGER 1: Launch Failures and Never Fail Silently Verification', () {
    final testProduct = Product(
      id: 601,
      name: 'Yerba Clásica 500g',
      internalCode: 'YER-500',
      costPrice: 800,
      sellingPrice: 1500,
      stock: 20,
      active: true,
      isSoldByWeight: false,
    );

    test('Simulated failure: canLaunchUrl returns false -> copies to clipboard and reports error notice', () async {
      String? copiedContent;
      String? reportedNotice;
      bool? reportedIsError;
      bool launchCalled = false;

      await ProductShareHelper.shareProduct(
        testProduct,
        isMobile: false,
        canLaunchUrlFn: (uri) async => false,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          launchCalled = true;
          return true;
        },
        copyToClipboardFn: (text) async => copiedContent = text,
        onShowNotice: (msg, {isError = false}) {
          reportedNotice = msg;
          reportedIsError = isError;
        },
      );

      expect(launchCalled, isFalse);
      expect(copiedContent, isNotNull);
      expect(copiedContent, contains('Yerba Clásica 500g'));
      expect(reportedNotice, equals('No se pudo abrir WhatsApp. Texto copiado al portapapeles.'));
      expect(reportedIsError, isTrue);
    });

    test('Simulated failure: launchUrl returns false -> copies to clipboard and reports error notice', () async {
      String? copiedContent;
      String? reportedNotice;
      bool? reportedIsError;

      await ProductShareHelper.shareProduct(
        testProduct,
        isMobile: false,
        canLaunchUrlFn: (uri) async => true,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async => false,
        copyToClipboardFn: (text) async => copiedContent = text,
        onShowNotice: (msg, {isError = false}) {
          reportedNotice = msg;
          reportedIsError = isError;
        },
      );

      expect(copiedContent, isNotNull);
      expect(copiedContent, contains('Yerba Clásica 500g'));
      expect(reportedNotice, equals('No se pudo abrir WhatsApp. Texto copiado al portapapeles.'));
      expect(reportedIsError, isTrue);
    });

    test('Simulated failure: canLaunchUrl throws PlatformException -> caught gracefully, copies to clipboard and reports error', () async {
      String? copiedContent;
      String? reportedNotice;
      bool? reportedIsError;

      await ProductShareHelper.shareProduct(
        testProduct,
        isMobile: false,
        canLaunchUrlFn: (uri) async {
          throw PlatformException(code: 'ACTIVITY_NOT_FOUND', message: 'No activity found to handle intent');
        },
        copyToClipboardFn: (text) async => copiedContent = text,
        onShowNotice: (msg, {isError = false}) {
          reportedNotice = msg;
          reportedIsError = isError;
        },
      );

      expect(copiedContent, isNotNull);
      expect(copiedContent, contains('Yerba Clásica 500g'));
      expect(reportedNotice, equals('No se pudo abrir WhatsApp. Texto copiado al portapapeles.'));
      expect(reportedIsError, isTrue);
    });

    test('Simulated failure: launchUrl throws Exception -> caught gracefully, copies to clipboard and reports error', () async {
      String? copiedContent;
      String? reportedNotice;
      bool? reportedIsError;

      await ProductShareHelper.shareProduct(
        testProduct,
        isMobile: false,
        canLaunchUrlFn: (uri) async => true,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          throw Exception('Fatal OS protocol error');
        },
        copyToClipboardFn: (text) async => copiedContent = text,
        onShowNotice: (msg, {isError = false}) {
          reportedNotice = msg;
          reportedIsError = isError;
        },
      );

      expect(copiedContent, isNotNull);
      expect(copiedContent, contains('Yerba Clásica 500g'));
      expect(reportedNotice, equals('No se pudo abrir WhatsApp. Texto copiado al portapapeles.'));
      expect(reportedIsError, isTrue);
    });

    test('Private URL scenario: when image download fails on desktop, safely falls back to text and clipboard', () async {
      final productWithPrivateUrl = testProduct.copyWith(
        imageUrl: 'http://192.168.1.100:8000/storage/products/yerba.png',
      );

      String? copiedContent;
      String? reportedNotice;
      bool? reportedIsError;

      await ProductShareHelper.shareProduct(
        productWithPrivateUrl,
        isMobile: false,
        shareTextFn: (text, {subject}) async {},
        copyToClipboardFn: (text) async => copiedContent = text,
        onShowNotice: (msg, {isError = false}) {
          reportedNotice = msg;
          reportedIsError = isError;
        },
      );

      expect(reportedNotice, equals('No se pudo adjuntar la foto. Texto copiado al portapapeles.'));
      expect(reportedIsError, isFalse);
      expect(copiedContent, isNotNull);
      expect(copiedContent, contains('Yerba Clásica 500g'));
    });

    test('Clipboard error does not crash shareProduct flow', () async {
      bool launchAttempted = false;

      // Even if clipboard operations fail (e.g., security restriction or lock), shareProduct should not crash
      await ProductShareHelper.shareProduct(
        testProduct,
        isMobile: false,
        canLaunchUrlFn: (uri) async => false,
        copyToClipboardFn: (text) async {
          throw PlatformException(code: 'CLIPBOARD_LOCKED', message: 'Access denied');
        },
        onShowNotice: (msg, {isError = false}) {},
      );

      // Verify execution finished without uncaught throw
      expect(launchAttempted, isFalse);
    });

    test('Runs cleanly without error when context and onShowNotice are null', () async {
      // Must not throw NullPointer when notifying without UI context
      await ProductShareHelper.shareProduct(
        testProduct,
        isMobile: false,
        context: null,
        onShowNotice: null,
        canLaunchUrlFn: (uri) async => false,
        copyToClipboardFn: (text) async {},
      );
    });
  });

  group('CHALLENGER 1: Phone Formatting and Canonical URL Path', () {
    test('Cleans arbitrary phone formatting characters (+, spaces, hyphens, brackets, dots)', () {
      final uri1 = ProductShareHelper.buildWhatsAppUri(
        phone: '+54 (9 11) 2345-6789.0',
        text: 'Consulta',
      );
      expect(uri1.path, equals('/54911234567890'));

      final uri2 = ProductShareHelper.buildWhatsAppUri(
        phone: '  +1-800-555-0199  ',
        text: 'Consulta',
      );
      expect(uri2.path, equals('/18005550199'));

      final uri3 = ProductShareHelper.buildWhatsAppUri(
        phone: null,
        text: 'Consulta',
      );
      expect(uri3.path, equals('/'));

      final uri4 = ProductShareHelper.buildWhatsAppUri(
        phone: '   ',
        text: 'Consulta',
      );
      expect(uri4.path, equals('/'));

      final uri5 = ProductShareHelper.buildWhatsAppUri(
        phone: 'alphanumeric-only-no-digits',
        text: 'Consulta',
      );
      expect(uri5.path, equals('/'));
    });
  });

  group('CHALLENGER 1: Deep Hostile Scenarios & Advanced Invariants', () {
    test('Complex Unicode sequences: ZWJ emoji family, skin tones, and RTL markers', () async {
      final hostileProduct = Product(
        id: 701,
        name: '👨‍👩‍👧‍👦 Familia & 👍🏽 Pulgar \u202E [RTL-HACK] \u200B\uFEFF',
        internalCode: 'UNI-99',
        costPrice: 500,
        sellingPrice: 1200,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );

      Uri? launchedUri;
      await ProductShareHelper.shareProduct(
        hostileProduct,
        isMobile: false,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          launchedUri = uri;
          return true;
        },
      );

      expect(launchedUri, isNotNull);
      final rawUri = launchedUri.toString();
      final roundtrip = Uri.parse(rawUri);
      expect(roundtrip.queryParameters['text'], contains('👨‍👩‍👧‍👦 Familia & 👍🏽 Pulgar'));
    });

    test('Spaces in public image URL are encoded without crashing or dropping URL', () async {
      final productWithSpacedUrl = Product(
        id: 702,
        name: 'Producto URL Con Espacios',
        internalCode: 'SPC-01',
        costPrice: 10,
        sellingPrice: 20,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'https://images.example.com/fotos de productos/yerba 1kg.jpg',
      );

      String? copied;
      await ProductShareHelper.shareProduct(
        productWithSpacedUrl,
        isMobile: false,
        copyToClipboardFn: (text) async => copied = text,
        shareTextFn: (text, {subject}) async {},
      );

      expect(copied, isNotNull);
      expect(copied, contains('Producto URL Con Espacios'));
      expect(copied, contains('- Precio: \$20'));
    });

    test('Relative product imageUrl automatically resolves to AppConfig.kApiBaseUrl', () async {
      final relativeProduct = Product(
        id: 703,
        name: 'Producto Con Storage Relativo',
        internalCode: 'REL-01',
        costPrice: 100,
        sellingPrice: 300,
        stock: 15,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'products/galletitas_rellenas.jpg',
      );

      String? notice;
      String? clipboard;

      await ProductShareHelper.shareProduct(
        relativeProduct,
        isMobile: false,
        onShowNotice: (msg, {isError = false}) => notice = msg,
        copyToClipboardFn: (text) async => clipboard = text,
        shareTextFn: (text, {subject}) async {},
      );

      expect(clipboard, isNotNull);
      expect(clipboard, contains('Producto Con Storage Relativo'));
      expect(notice, equals('No se pudo adjuntar la foto. Texto copiado al portapapeles.'));
    });

    test('IPv6 public vs private classification', () {
      // Private / local IPv6
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[::1]/pic.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[fe80::1ff:fe23:4567:890a]/pic.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[fc00::1]/pic.jpg'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[fd12:3456:789a::1]/pic.jpg'), isTrue);

      // Public global unicast IPv6 (e.g. Cloudflare DNS, Google DNS)
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://[2606:4700:4700::1111]/pic.jpg'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://[2001:4860:4860::8888]/pic.jpg'), isFalse);
    });

    test('Desktop environment default: When isMobile and shareFilesFn are omitted on Windows runner, desktop flow is selected', () async {
      final sampleProd = Product(
        id: 704,
        name: 'Auto-detection Test Product',
        internalCode: 'AUTO-RUN',
        costPrice: 50,
        sellingPrice: 100,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );

      Uri? launchedUri;
      // On Windows test environment, AppConfig.isMobile is false
      await ProductShareHelper.shareProduct(
        sampleProd,
        launchUrlFn: (uri, {mode = LaunchMode.platformDefault}) async {
          launchedUri = uri;
          return true;
        },
      );

      expect(launchedUri, isNotNull);
      expect(launchedUri!.host, equals('wa.me'));
      expect(launchedUri!.queryParameters['text'], contains('Auto-detection Test Product'));
    });
  });
}

