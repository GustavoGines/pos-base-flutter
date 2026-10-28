import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend_desktop/core/network/api_client.dart';

void main() {
  group('Empirical Challenge: ApiClient Timeout & Failover Behavior', () {
    test('CHALLENGE-01: External path timeout STRICTLY prevents failover to WAN', () async {
      final mockClient = MockClient((request) async {
        // Simular timeout en la capa de transporte
        throw TimeoutException('Request timed out after 90 seconds');
      });

      final apiClient = ApiClient(mockClient)
        ..configureFailover(
          primaryUrl: 'http://192.168.1.50/api',
          fallbackUrl: 'https://cloud.pos.com/api',
        );

      expect(apiClient.isUsingFallbackEndpoint, isFalse);

      // Invocación a ruta externa: /afip
      await expectLater(
        () => apiClient.get(Uri.parse('http://192.168.1.50/api/afip/status')),
        throwsA(isA<NetworkException>().having(
          (e) => e.message,
          'message',
          contains('El servidor está tardando demasiado en responder'),
        )),
      );

      // VERIFICACIÓN CRÍTICA: No debe conmutar a WAN en timeout externo
      expect(apiClient.isUsingFallbackEndpoint, isFalse,
          reason: 'isExternalTimeout must prevent switching to fallback endpoint');

      // Invocación a ruta externa: /license
      await expectLater(
        () => apiClient.get(Uri.parse('http://192.168.1.50/api/license/sync')),
        throwsA(isA<NetworkException>()),
      );
      expect(apiClient.isUsingFallbackEndpoint, isFalse);

      // Invocación a ruta externa: /invoice
      await expectLater(
        () => apiClient.get(Uri.parse('http://192.168.1.50/api/invoice/authorize')),
        throwsA(isA<NetworkException>()),
      );
      expect(apiClient.isUsingFallbackEndpoint, isFalse);

      // Invocación a ruta externa: /backup
      await expectLater(
        () => apiClient.get(Uri.parse('http://192.168.1.50/api/backup/download')),
        throwsA(isA<NetworkException>()),
      );
      expect(apiClient.isUsingFallbackEndpoint, isFalse);

      // FE-HIGH-01: Invocación a ruta externa de Mercado Pago (/pos/mp/*)
      await expectLater(
        () => apiClient.post(Uri.parse('http://192.168.1.50/api/pos/mp/create-order')),
        throwsA(isA<NetworkException>()),
      );
      expect(apiClient.isUsingFallbackEndpoint, isFalse,
          reason: 'Mercado Pago cloud timeout must NOT switch POS terminal to WAN fallback');
    });

    test('CHALLENGE-02: Normal internal LAN path timeout DOES trigger failover to WAN', () async {
      final requestedUrls = <String>[];
      final mockClient = MockClient((request) async {
        requestedUrls.add(request.url.toString());
        if (request.url.host == '192.168.1.50') {
          throw TimeoutException('Request timed out after 20 seconds');
        }
        return http.Response('{"status": "ok"}', 200);
      });

      final apiClient = ApiClient(mockClient)
        ..configureFailover(
          primaryUrl: 'http://192.168.1.50/api',
          fallbackUrl: 'https://cloud.pos.com/api',
        );

      expect(apiClient.isUsingFallbackEndpoint, isFalse);

      // Petición ordinaria a /products (no es ruta pesada/externa)
      final response = await apiClient.get(Uri.parse('http://192.168.1.50/api/products'));
      expect(response.statusCode, 200);

      // VERIFICACIÓN: Conmutó dinámicamente a WAN
      expect(apiClient.isUsingFallbackEndpoint, isTrue);
      expect(requestedUrls, [
        'http://192.168.1.50/api/products',
        'https://cloud.pos.com/api/products',
      ]);
    });

    test('CHALLENGE-03: HTTP 504 on external path STRICTLY prevents failover to WAN', () async {
      final requestedUrls = <String>[];
      final mockClient = MockClient((request) async {
        requestedUrls.add(request.url.toString());
        if (request.url.host == '192.168.1.50') {
          // Servidor local o proxy Nginx devuelve 504 Gateway Timeout hacia AFIP
          return http.Response('Gateway Timeout', 504);
        }
        return http.Response('{"status": "fallback_ok"}', 200);
      });

      final apiClient = ApiClient(mockClient)
        ..configureFailover(
          primaryUrl: 'http://192.168.1.50/api',
          fallbackUrl: 'https://cloud.pos.com/api',
        );

      expect(apiClient.isUsingFallbackEndpoint, isFalse);

      // Petición a ruta externa /afip/status que devuelve 504 no debe conmutar a WAN
      await expectLater(
        () => apiClient.get(Uri.parse('http://192.168.1.50/api/afip/status')),
        throwsA(isA<NetworkException>()),
      );

      expect(apiClient.isUsingFallbackEndpoint, isFalse,
          reason: 'HTTP 504 on external path must not trigger WAN failover');
      expect(requestedUrls, [
        'http://192.168.1.50/api/afip/status',
      ]);
    });
  });
}
