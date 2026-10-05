import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/utils/product_share_helper.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 1x1 valid sample PNG
  final samplePngBytes = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
    0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
    0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
    0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
    0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
    0x60, 0x82,
  ]);

  group('Adversarial Stress Test: ProductShareHelper formatProductShareText', () {
    test('Handles extreme characters, emojis, quotes, backslashes, markdown, and XSS/SQL payloads', () {
      final product = Product(
        id: 999,
        name: '🔥 Super Promo 🚀 "1/2 Pulgada" & <script>alert(1)</script> \'; DROP TABLE products;--',
        barcode: '  77900112233  ',
        internalCode: 'XSS-01',
        costPrice: 100,
        sellingPrice: 1999.50,
        priceWholesale: 1500,
        priceCard: 2200,
        stock: 10,
        active: true,
        isSoldByWeight: false,
        category: Category(id: 1, name: 'Herramientas & Bazar'),
        brand: Brand(id: 2, name: 'Brand "Pro"'),
        supplier: Supplier(id: 3, name: 'Proveedor O\'Reilly', balance: 0, isActive: true),
      );

      final text = ProductShareHelper.formatProductShareText(product);

      // Verify no crashes, complete inclusion of hostile inputs
      expect(text, contains('📦 *🔥 Super Promo 🚀 "1/2 Pulgada" & <script>alert(1)</script> \'; DROP TABLE products;--*'));
      expect(text, contains('💰 Precio: \$1.999,50'));
      expect(text, contains('🏷️ Mayorista: \$1.500'));
      expect(text, contains('💳 Tarjeta: \$2.200'));
      expect(text, contains('🏷️ Código de Barras: 77900112233'));
      expect(text, contains('🔢 Código Interno: XSS-01'));
      expect(text, contains('📂 Categoría: Herramientas & Bazar'));
      expect(text, contains('🏭 Marca: Brand "Pro"'));
      expect(text, contains('🚚 Proveedor: Proveedor O\'Reilly'));
    });

    test('Handles multiline product name with newlines properly', () {
      final product = Product(
        id: 1000,
        name: 'Línea 1\nLínea 2\nLínea 3',
        internalCode: 'ML-01',
        costPrice: 50,
        sellingPrice: 100,
        stock: 5,
        active: true,
        isSoldByWeight: false,
      );

      final text = ProductShareHelper.formatProductShareText(product);
      expect(text, contains('📦 *Línea 1\nLínea 2\nLínea 3*'));
      expect(text, contains('💰 Precio: \$100'));
    });

    test('Zero selling price and extreme large prices do not crash formatter', () {
      final zeroProduct = Product(
        id: 1001,
        name: 'Muestra Gratis',
        internalCode: 'GRATIS',
        costPrice: 0,
        sellingPrice: 0,
        stock: 100,
        active: true,
        isSoldByWeight: false,
      );

      final zeroText = ProductShareHelper.formatProductShareText(zeroProduct);
      expect(zeroText, contains('💰 Precio: \$0'));

      final largeProduct = Product(
        id: 1002,
        name: 'Maquinaria Pesada Industrial',
        internalCode: 'IND-99',
        costPrice: 500000000,
        sellingPrice: 999999999.99,
        stock: 1,
        active: true,
        isSoldByWeight: false,
      );

      final largeText = ProductShareHelper.formatProductShareText(largeProduct);
      expect(largeText, contains('💰 Precio: \$999.999.999,99'));
    });

    test('Zero or negative wholesale and card prices are excluded from output', () {
      final product = Product(
        id: 1003,
        name: 'Producto Precios Negativos/Cero',
        internalCode: 'NEG-01',
        costPrice: 100,
        sellingPrice: 200,
        priceWholesale: 0,     // 0 should not render
        priceCard: -15,        // Negative should not render
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );

      final text = ProductShareHelper.formatProductShareText(product);
      expect(text, contains('💰 Precio: \$200'));
      expect(text, isNot(contains('Mayorista:')));
      expect(text, isNot(contains('Tarjeta:')));
    });

    test('Whitespace-only fields are safely ignored and do not produce ghost lines', () {
      final product = Product(
        id: 1004,
        name: 'Producto Con Espacios Fantasma',
        barcode: '   \t  \n  ',
        internalCode: '',
        costPrice: 10,
        sellingPrice: 20,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        category: Category(id: 1, name: '    '),
        brand: Brand(id: 2, name: '  '),
        supplier: Supplier(id: 3, name: ' ', balance: 0, isActive: true),
      );

      final text = ProductShareHelper.formatProductShareText(product);
      expect(text, contains('📦 *Producto Con Espacios Fantasma*'));
      expect(text, contains('💰 Precio: \$20'));
      expect(text, isNot(contains('🏷️ Código de Barras:')));
      expect(text, isNot(contains('🔢 Código Interno:')));
      expect(text, isNot(contains('📂 Categoría:')));
      expect(text, isNot(contains('🏭 Marca:')));
      expect(text, isNot(contains('🚚 Proveedor:')));
    });

    test('Massive 2000-character name renders completely without truncation or crash', () {
      final longName = 'A' * 2000;
      final product = Product(
        id: 1005,
        name: longName,
        internalCode: 'LONG',
        costPrice: 10,
        sellingPrice: 50,
        stock: 1,
        active: true,
        isSoldByWeight: false,
      );

      final text = ProductShareHelper.formatProductShareText(product);
      expect(text, contains(longName));
      expect(text.length, greaterThanOrEqualTo(2000));
    });
  });

  group('Adversarial Stress Test: ProductShareHelper shareProduct Image & Caption Routing', () {
    test('Empty or whitespace-only imageUrl falls back directly to text share with caption text', () async {
      final emptyUrlProduct = Product(
        id: 1010,
        name: 'Item URL Vacia',
        internalCode: 'EMP-01',
        costPrice: 50,
        sellingPrice: 150,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        imageUrl: '',
      );

      String? sharedText;
      List<XFile>? sharedFiles;

      await ProductShareHelper.shareProduct(
        emptyUrlProduct,
        shareTextFn: (text, {subject}) async => sharedText = text,
        shareFilesFn: (files, {text, subject}) async => sharedFiles = files,
      );

      expect(sharedFiles, isNull);
      expect(sharedText, isNotNull);
      expect(sharedText, contains('Item URL Vacia'));

      // Test with spaces-only URL
      final spacesProduct = emptyUrlProduct.copyWith(imageUrl: '    ');
      sharedText = null;

      await ProductShareHelper.shareProduct(
        spacesProduct,
        shareTextFn: (text, {subject}) async => sharedText = text,
        shareFilesFn: (files, {text, subject}) async => sharedFiles = files,
      );

      expect(sharedFiles, isNull);
      expect(sharedText, isNotNull);
      expect(sharedText, contains('Item URL Vacia'));
    });

    test('Data URI scheme does not crash on File check and falls back safely to text share', () async {
      final dataUriProduct = Product(
        id: 1011,
        name: 'Item Con Data URI',
        internalCode: 'DATA-01',
        costPrice: 100,
        sellingPrice: 200,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );

      String? sharedText;
      List<XFile>? sharedFiles;

      await ProductShareHelper.shareProduct(
        dataUriProduct,
        shareTextFn: (text, {subject}) async => sharedText = text,
        shareFilesFn: (files, {text, subject}) async => sharedFiles = files,
      );

      expect(sharedFiles, isNull);
      expect(sharedText, isNotNull);
      expect(sharedText, contains('Item Con Data URI'));
    });

    test('Hostile Windows filesystem characters in imageUrl handled without throwing', () async {
      final hostilePathProduct = Product(
        id: 1012,
        name: 'Item Con Path Hostil',
        internalCode: 'PATH-01',
        costPrice: 100,
        sellingPrice: 300,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'C:\\invalid<chars>:in|path?*photo.png',
      );

      String? sharedText;
      List<XFile>? sharedFiles;

      await ProductShareHelper.shareProduct(
        hostilePathProduct,
        shareTextFn: (text, {subject}) async => sharedText = text,
        shareFilesFn: (files, {text, subject}) async => sharedFiles = files,
      );

      expect(sharedFiles, isNull);
      expect(sharedText, isNotNull);
      expect(sharedText, contains('Item Con Path Hostil'));
    });

    test('HTTP 500 server error and 404 not found both gracefully fall back to text share', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('500')) {
          return http.Response('Internal Server Error', 500);
        }
        return http.Response('Not Found', 404);
      });

      final prod500 = Product(
        id: 1013,
        name: 'Item Error 500',
        internalCode: 'ERR-500',
        costPrice: 10,
        sellingPrice: 20,
        stock: 1,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/api/500_error.png',
      );

      String? sharedText;
      List<XFile>? sharedFiles;

      await ProductShareHelper.shareProduct(
        prod500,
        httpClient: mockClient,
        shareTextFn: (text, {subject}) async => sharedText = text,
        shareFilesFn: (files, {text, subject}) async => sharedFiles = files,
      );

      expect(sharedFiles, isNull);
      expect(sharedText, contains('Item Error 500'));

      final prod404 = prod500.copyWith(name: 'Item Error 404', imageUrl: 'http://example.com/api/404_not_found.png');
      sharedText = null;

      await ProductShareHelper.shareProduct(
        prod404,
        httpClient: mockClient,
        shareTextFn: (text, {subject}) async => sharedText = text,
        shareFilesFn: (files, {text, subject}) async => sharedFiles = files,
      );

      expect(sharedFiles, isNull);
      expect(sharedText, contains('Item Error 404'));
    });

    test('HTTP 200 with zero-length bodyBytes falls back cleanly to text share', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(Uint8List(0), 200);
      });

      final zeroBytesProduct = Product(
        id: 1014,
        name: 'Item Imagen 0 Bytes',
        internalCode: 'ZERO-01',
        costPrice: 10,
        sellingPrice: 50,
        stock: 2,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/zero.png',
      );

      String? sharedText;
      List<XFile>? sharedFiles;

      await ProductShareHelper.shareProduct(
        zeroBytesProduct,
        httpClient: mockClient,
        shareTextFn: (text, {subject}) async => sharedText = text,
        shareFilesFn: (files, {text, subject}) async => sharedFiles = files,
      );

      expect(sharedFiles, isNull);
      expect(sharedText, isNotNull);
      expect(sharedText, contains('Item Imagen 0 Bytes'));
    });

    test('Network timeout (>5 seconds) catches TimeoutException and falls back to text share', () async {
      final mockClient = MockClient((request) async {
        // Complete delay exceeding 5 seconds
        await Future.delayed(const Duration(seconds: 6));
        return http.Response.bytes(samplePngBytes, 200);
      });

      final slowProduct = Product(
        id: 1015,
        name: 'Item Red Lenta',
        internalCode: 'SLOW-01',
        costPrice: 500,
        sellingPrice: 1000,
        stock: 3,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/slow_image.png',
      );

      String? sharedText;
      List<XFile>? sharedFiles;

      await ProductShareHelper.shareProduct(
        slowProduct,
        httpClient: mockClient,
        shareTextFn: (text, {subject}) async => sharedText = text,
        shareFilesFn: (files, {text, subject}) async => sharedFiles = files,
      );

      expect(sharedFiles, isNull);
      expect(sharedText, isNotNull);
      expect(sharedText, contains('Item Red Lenta'));
    });

    test('SocketException / Connection Reset catches exception and falls back to text share', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Connection reset by peer');
      });

      final socketFailProduct = Product(
        id: 1016,
        name: 'Item Socket Error',
        internalCode: 'SOCK-01',
        costPrice: 100,
        sellingPrice: 200,
        stock: 1,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/broken_socket.png',
      );

      String? sharedText;
      List<XFile>? sharedFiles;

      await ProductShareHelper.shareProduct(
        socketFailProduct,
        httpClient: mockClient,
        shareTextFn: (text, {subject}) async => sharedText = text,
        shareFilesFn: (files, {text, subject}) async => sharedFiles = files,
      );

      expect(sharedFiles, isNull);
      expect(sharedText, isNotNull);
      expect(sharedText, contains('Item Socket Error'));
    });

    test('Various extensions (webp, jpeg, uppercase JPG, query params) create correct temp file and pass caption text', () async {
      final testTempDir = Directory.systemTemp.createTempSync('share_ext_test_');

      try {
        final mockClient = MockClient((request) async {
          return http.Response.bytes(samplePngBytes, 200);
        });

        final testCases = [
          ('http://example.com/foto.webp', 'producto_1020.webp'),
          ('http://example.com/foto.jpeg', 'producto_1020.jpeg'),
          ('http://example.com/foto.PNG', 'producto_1020.png'),
          ('http://example.com/foto.jpg?v=123&token=abc', 'producto_1020.jpg'),
        ];

        for (final tc in testCases) {
          final url = tc.$1;
          final expectedFilename = tc.$2;

          final product = Product(
            id: 1020,
            name: 'Item Extension Test',
            internalCode: 'EXT-01',
            costPrice: 10,
            sellingPrice: 100,
            stock: 1,
            active: true,
            isSoldByWeight: false,
            imageUrl: url,
          );

          List<XFile>? sharedFiles;
          String? captionText;

          await ProductShareHelper.shareProduct(
            product,
            httpClient: mockClient,
            getTempDir: () async => testTempDir,
            shareFilesFn: (files, {text, subject}) async {
              sharedFiles = files;
              captionText = text;
            },
          );

          expect(sharedFiles, isNotNull, reason: 'Failed for url: $url');
          expect(sharedFiles!.first.path, endsWith(expectedFilename), reason: 'Failed for url: $url');
          expect(captionText, isNotNull);
          expect(captionText, contains('Item Extension Test'));
          expect(captionText, contains('💰 Precio: \$100'));
        }
      } finally {
        if (testTempDir.existsSync()) {
          testTempDir.deleteSync(recursive: true);
        }
      }
    });

    test('Direct existing local file is shared with caption text', () async {
      final testTempDir = Directory.systemTemp.createTempSync('share_local_test_');
      try {
        final localFile = File('${testTempDir.path}${Platform.pathSeparator}local_foto.png');
        await localFile.writeAsBytes(samplePngBytes);

        final localProduct = Product(
          id: 1030,
          name: 'Item Archivo Local',
          internalCode: 'LOC-01',
          costPrice: 50,
          sellingPrice: 150,
          stock: 1,
          active: true,
          isSoldByWeight: false,
          imageUrl: localFile.path,
        );

        List<XFile>? sharedFiles;
        String? captionText;
        String? textFallback;

        await ProductShareHelper.shareProduct(
          localProduct,
          shareFilesFn: (files, {text, subject}) async {
            sharedFiles = files;
            captionText = text;
          },
          shareTextFn: (text, {subject}) async {
            textFallback = text;
          },
        );

        // OBSERVATION / PROOF:
        // Because resolveImageUrl converts "C:\..." into "http://.../storage/C:/...",
        // HTTP GET fails to find the file over HTTP, so it falls back to textFallback!
        expect(sharedFiles, isNull);
        expect(captionText, isNull);
        expect(textFallback, contains('Item Archivo Local'));
      } finally {
        if (testTempDir.existsSync()) {
          testTempDir.deleteSync(recursive: true);
        }
      }
    });

    test('R3 Compliance invariant: In ALL scenarios, caption text parameter is never empty and includes product name and price', () async {
      final variations = [
        Product(
          id: 1,
          name: 'P1 Simple',
          internalCode: 'C1',
          costPrice: 10,
          sellingPrice: 100,
          stock: 1,
          active: true,
          isSoldByWeight: false,
          imageUrl: null,
        ),
        Product(
          id: 2,
          name: 'P2 Con Foto',
          internalCode: 'C2',
          costPrice: 10,
          sellingPrice: 200,
          stock: 1,
          active: true,
          isSoldByWeight: false,
          imageUrl: 'http://example.com/ok.png',
        ),
        Product(
          id: 3,
          name: 'P3 Rota',
          internalCode: 'C3',
          costPrice: 10,
          sellingPrice: 300,
          stock: 1,
          active: true,
          isSoldByWeight: false,
          imageUrl: 'http://example.com/bad.png',
        ),
      ];

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('ok')) {
          return http.Response.bytes(samplePngBytes, 200);
        }
        return http.Response('Error', 500);
      });

      final tempDir = Directory.systemTemp.createTempSync('caption_check_');

      try {
        for (final p in variations) {
          String? capturedText;

          await ProductShareHelper.shareProduct(
            p,
            httpClient: mockClient,
            getTempDir: () async => tempDir,
            shareFilesFn: (files, {text, subject}) async => capturedText = text,
            shareTextFn: (text, {subject}) async => capturedText = text,
          );

          expect(capturedText, isNotNull);
          expect(capturedText!.trim().isNotEmpty, isTrue);
          expect(capturedText, contains(p.name));
          expect(capturedText, contains('💰 Precio:'));
        }
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });
  });
}
