import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/utils/image_url_resolver.dart';

void main() {
  group('ImageUrlResolver Tests', () {
    test('returns null for null, empty, whitespace, or "null" string', () {
      expect(resolveImageUrl(null), isNull);
      expect(resolveImageUrl(''), isNull);
      expect(resolveImageUrl('   '), isNull);
      expect(resolveImageUrl('null'), isNull);
      expect(resolveImageUrl('NULL'), isNull);
    });

    test('preserves valid absolute HTTP and HTTPS URLs', () {
      const httpUrl = 'http://pos-backend.test/storage/business/logo_1.png';
      expect(resolveImageUrl(httpUrl), httpUrl);

      const httpsUrl = 'https://cloud.pos.com/images/prod_99.webp';
      expect(resolveImageUrl(httpsUrl), httpsUrl);
    });

    test('resolves relative storage paths using custom baseUrl', () {
      const customBase = 'http://pos-backend.test/api';

      // 1. Path without storage/ prefix
      expect(
        resolveImageUrl('business/logo.png', baseUrl: customBase),
        'http://pos-backend.test/storage/business/logo.png',
      );

      // 2. Path with storage/ prefix
      expect(
        resolveImageUrl('storage/products/item_1.jpg', baseUrl: customBase),
        'http://pos-backend.test/storage/products/item_1.jpg',
      );

      // 3. Path with leading slash
      expect(
        resolveImageUrl('/storage/products/item_2.png', baseUrl: customBase),
        'http://pos-backend.test/storage/products/item_2.png',
      );

      // 4. Relative path with public/api base URL
      const publicBase = 'http://192.168.1.200/Sistema_POS/pos-backend/public/api';
      expect(
        resolveImageUrl('products/item_3.png', baseUrl: publicBase),
        'http://192.168.1.200/Sistema_POS/pos-backend/public/storage/products/item_3.png',
      );
    });

    test('returns null for malformed or hostless http/https URLs', () {
      expect(resolveImageUrl('http://'), isNull);
      expect(resolveImageUrl('https://'), isNull);
      expect(resolveImageUrl('http://   '), isNull);
    });

    test('normalizes Windows backslashes and cleans redundant leading slashes', () {
      const customBase = 'http://pos-backend.test/api';
      expect(
        resolveImageUrl(r'products\sub\item_5.jpg', baseUrl: customBase),
        'http://pos-backend.test/storage/products/sub/item_5.jpg',
      );
      expect(
        resolveImageUrl(r'\\storage\products\item_6.png', baseUrl: customBase),
        'http://pos-backend.test/storage/products/item_6.png',
      );
      expect(
        resolveImageUrl('///products/item_7.png', baseUrl: customBase),
        'http://pos-backend.test/storage/products/item_7.png',
      );
    });

    test('prevents double slashes when baseUrl has trailing slash', () {
      const baseWithSlash = 'http://pos-backend.test/';
      expect(
        resolveImageUrl('business/logo.png', baseUrl: baseWithSlash),
        'http://pos-backend.test/storage/business/logo.png',
      );

      const baseApiWithSlash = 'http://pos-backend.test/api/';
      expect(
        resolveImageUrl('storage/products/item_8.png', baseUrl: baseApiWithSlash),
        'http://pos-backend.test/storage/products/item_8.png',
      );
    });

    test('falls back to AppConfig.kApiBaseUrl when baseUrl is not provided', () {
      final resolved = resolveImageUrl('business/logo.png');
      expect(resolved, isNotNull);
      expect(resolved, contains('/storage/business/logo.png'));
    });
  });
}
