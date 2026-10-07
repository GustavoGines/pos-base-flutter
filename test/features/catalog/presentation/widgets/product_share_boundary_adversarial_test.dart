import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/catalog/utils/product_share_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adversarial Boundary Subnet Tests: 172.15 vs 172.16 vs 172.31 vs 172.32', () {
    test('172.15 boundary (public IP) returns false', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.15.0.0/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.15.0.1/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.15.255.255/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://172.15.100.20:8443/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.15.1.1:8080/img.png?token=xyz&v=1'), isFalse);
    });

    test('172.16 lower private boundary returns true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.16.0.0/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.16.0.1/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.16.255.255/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://172.16.10.5:8000/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.16.0.1:8080/img.png?auth=yes'), isTrue);
    });

    test('172.20 to 172.30 interior private range returns true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.20.0.1/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.25.100.50/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.30.254.1/img.png'), isTrue);
    });

    test('172.31 upper private boundary returns true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.31.0.0/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.31.0.1/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.31.255.255/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://172.31.100.1:9000/img.png?q=test'), isTrue);
    });

    test('172.32 boundary (public IP) returns false', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.32.0.0/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.32.0.1/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.32.255.255/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://172.32.1.1:443/img.png?foo=bar'), isFalse);
    });

    test('172.0 and 172.255 extreme boundaries (public) return false', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.0.0.1/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://172.255.255.255/img.png'), isFalse);
    });
  });

  group('Adversarial Loopback Variants Tests', () {
    test('Standard loopback addresses return true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://127.0.0.1/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://127.0.0.2/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://127.1.2.3/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://127.255.255.254/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://127.0.0.1:8000/img.png?x=1'), isTrue);
    });

    test('0.0.0.0 wildcard bind host returns true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://0.0.0.0/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://0.0.0.0:8000/img.png'), isTrue);
    });

    test('localhost and subdomains return true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://localhost/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://localhost:3000/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://app.localhost/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://api.sub.localhost:8080/img.png'), isTrue);
    });

    test('IPv6 loopback [::1] returns true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[::1]/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[::1]:8080/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://[::1]:8443/img.png?v=1'), isTrue);
    });
  });

  group('Adversarial Link-Local Tests', () {
    test('169.254.0.0/16 IPv4 Link-Local returns true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://169.254.0.1/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://169.254.169.254/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://169.254.255.255/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://169.254.1.1:8080/img.png?meta=1'), isTrue);
    });

    test('169.253 and 169.255 outside Link-Local return false', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://169.253.255.255/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://169.255.0.1/img.png'), isFalse);
    });

    test('IPv6 Link-Local fe80:: returns true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[fe80::1]/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://[fe80::20c:29ff:fe53:45ca]/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://[fe80::1]:8443/img.png'), isTrue);
    });
  });

  group('Adversarial Special TLDs Tests', () {
    test('Special TLDs (.test, .local, .localhost, .internal, .lan, .invalid, .example) return true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://server.test/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://my-nas.local/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://dev.localhost/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://auth.internal/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://gateway.lan/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://dummy.invalid/img.png'), isTrue);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://mock.example/img.png'), isTrue);
    });
  });

  group('Adversarial Public Internet Domains and Query Parameters', () {
    test('Legitimate public domains return false', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://images.unsplash.com/photo.jpg'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://cdn.shopify.com/product.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://storage.googleapis.com/bucket/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://aws-s3.s3.amazonaws.com/item.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('http://93.184.216.34/img.png'), isFalse);
    });

    test('Query params containing private IP or localhost do NOT trick parser into returning true', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://cdn.example.com/img.png?redirect=http://localhost'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://cdn.example.com/img.png?dest=192.168.1.1'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://cdn.example.com/img.png?ip=10.0.0.1&port=8080'), isFalse);
    });

    test('Public domain names ending in words similar to private TLDs return false', () {
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://plan.com/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://myisland.com/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://speedtest.net/img.png'), isFalse);
      expect(ProductShareHelper.isPrivateOrLocalUrl('https://localhost.com/img.png'), isFalse);
    });
  });

  group('Fixed Bug Verifications & Regression Prevention in isPrivateOrLocalUrl', () {
    test('Bug 1 Fix: Public internet domains starting with fc or fd evaluate to false (public)', () {
      final fda = ProductShareHelper.isPrivateOrLocalUrl('https://fda.gov/photo.png');
      final fcBarcelona = ProductShareHelper.isPrivateOrLocalUrl('https://fcbarcelona.com/crest.png');
      final fc2 = ProductShareHelper.isPrivateOrLocalUrl('https://fc2.com/logo.png');
      final fcc = ProductShareHelper.isPrivateOrLocalUrl('https://fcc.gov/banner.png');
      final fcdn = ProductShareHelper.isPrivateOrLocalUrl('https://fcdn.net/img.png');
      final fdic = ProductShareHelper.isPrivateOrLocalUrl('https://fdic.gov/seal.png');

      expect(fda, isFalse, reason: 'fda.gov is a public internet domain and must evaluate to false');
      expect(fcBarcelona, isFalse, reason: 'fcbarcelona.com is a public internet domain and must evaluate to false');
      expect(fc2, isFalse, reason: 'fc2.com is a public internet domain and must evaluate to false');
      expect(fcc, isFalse, reason: 'fcc.gov is a public internet domain and must evaluate to false');
      expect(fcdn, isFalse, reason: 'fcdn.net CDN is a public internet domain and must evaluate to false');
      expect(fdic, isFalse, reason: 'fdic.gov is a public internet domain and must evaluate to false');
    });

    test('Bug 2 Fix: 4-label FQDNs starting with 172.16-31 evaluate to false (public)', () {
      final host172Domain = ProductShareHelper.isPrivateOrLocalUrl('https://172.16.myshop.com/image.png');
      expect(host172Domain, isFalse, reason: '172.16.myshop.com is a public FQDN domain and must evaluate to false');
    });

    test('Bug 3 Fix: Public domains or shard subdomains starting with 10. evaluate to false (public)', () {
      final tenCdn = ProductShareHelper.isPrivateOrLocalUrl('https://10.cdn.mybrand.com/photo.png');
      final tenXyz = ProductShareHelper.isPrivateOrLocalUrl('https://10.xyz/product.jpg');
      expect(tenCdn, isFalse, reason: '10.cdn.mybrand.com is a public domain and must evaluate to false');
      expect(tenXyz, isFalse, reason: '10.xyz is a public domain and must evaluate to false');
    });

    test('Bug 4 Fix: Single-label intranet hostnames without dots evaluate to true (private)', () {
      final servidor = ProductShareHelper.isPrivateOrLocalUrl('http://servidor:8000/storage/img.png');
      final caja = ProductShareHelper.isPrivateOrLocalUrl('http://caja1:8000/storage/img.png');
      final posServer = ProductShareHelper.isPrivateOrLocalUrl('http://pos-server:8000/storage/img.png');
      expect(servidor, isTrue, reason: 'Single-label local hostname servidor must be detected as private/local');
      expect(caja, isTrue, reason: 'Single-label local hostname caja1 must be detected as private/local');
      expect(posServer, isTrue, reason: 'Single-label local hostname pos-server must be detected as private/local');
    });

    test('Bug 5 Fix: Uncompressed and zero-padded IPv6 loopback variants evaluate to true (private)', () {
      final uncompressed1 = ProductShareHelper.isPrivateOrLocalUrl('http://[0:0:0:0:0:0:0:1]/img.png');
      final uncompressed2 = ProductShareHelper.isPrivateOrLocalUrl('http://[::0001]/img.png');
      expect(uncompressed1, isTrue, reason: 'Uncompressed IPv6 loopback must be recognized as private/local');
      expect(uncompressed2, isTrue, reason: 'Zero-padded IPv6 loopback must be recognized as private/local');
    });
  });
}
