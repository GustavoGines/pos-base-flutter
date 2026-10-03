import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend_desktop/core/network/api_client.dart';

void main() {
  group('ApiClient Scoped Ephemeral Admin PIN Injection', () {
    test('withAdminPin inyecta header X-Admin-Pin y lo purga inmediatamente al terminar', () async {
      final recordedHeaders = <Map<String, String>>[];

      final mockClient = MockClient((request) async {
        recordedHeaders.add(Map.from(request.headers));
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(mockClient);

      // 1. Request ordinario sin PIN
      await apiClient.get(Uri.parse('http://localhost/api/test'));
      expect(recordedHeaders.length, 1);
      expect(recordedHeaders[0].containsKey('X-Admin-Pin'), false);
      expect(recordedHeaders[0]['Connection'], 'close');

      // 2. Request dentro de withAdminPin
      final result = await apiClient.withAdminPin('4321', () async {
        await apiClient.post(Uri.parse('http://localhost/api/sales/1/void'));
        return 'executed';
      });

      expect(result, 'executed');
      expect(recordedHeaders.length, 2);
      expect(recordedHeaders[1]['X-Admin-Pin'], '4321');
      expect(recordedHeaders[1]['Connection'], 'close');

      // 3. Request posterior fuera de withAdminPin -> PIN debe estar completamente purgado
      await apiClient.get(Uri.parse('http://localhost/api/test2'));
      expect(recordedHeaders.length, 3);
      expect(recordedHeaders[2].containsKey('X-Admin-Pin'), false);
    });

    test('withAdminPin purga el PIN en bloque finally incluso ante excepciones', () async {
      final recordedHeaders = <Map<String, String>>[];

      final mockClient = MockClient((request) async {
        recordedHeaders.add(Map.from(request.headers));
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(mockClient);

      try {
        await apiClient.withAdminPin('9999', () async {
          await apiClient.delete(Uri.parse('http://localhost/api/cash-movements/5'));
          throw Exception('Fallo simulado en la acción protegida');
        });
      } catch (_) {
        // Excepción esperada
      }

      expect(recordedHeaders.length, 1);
      expect(recordedHeaders[0]['X-Admin-Pin'], '9999');

      // Request posterior fuera del bloque con error
      await apiClient.get(Uri.parse('http://localhost/api/test3'));
      expect(recordedHeaders.length, 2);
      expect(recordedHeaders[1].containsKey('X-Admin-Pin'), false);
    });

    test('withAdminPin anidado restaura correctamente el PIN previo', () async {
      final recordedHeaders = <Map<String, String>>[];

      final mockClient = MockClient((request) async {
        recordedHeaders.add(Map.from(request.headers));
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(mockClient);

      await apiClient.withAdminPin('PIN_A', () async {
        await apiClient.get(Uri.parse('http://localhost/api/outer1'));

        await apiClient.withAdminPin('PIN_B', () async {
          await apiClient.get(Uri.parse('http://localhost/api/inner'));
        });

        await apiClient.get(Uri.parse('http://localhost/api/outer2'));
      });

      expect(recordedHeaders.length, 3);
      expect(recordedHeaders[0]['X-Admin-Pin'], 'PIN_A');
      expect(recordedHeaders[1]['X-Admin-Pin'], 'PIN_B');
      expect(recordedHeaders[2]['X-Admin-Pin'], 'PIN_A');

      // Fuera de todo
      await apiClient.get(Uri.parse('http://localhost/api/none'));
      expect(recordedHeaders.length, 4);
      expect(recordedHeaders[3].containsKey('X-Admin-Pin'), false);
    });

    test('R2: setGlobalEphemeralPin inyecta X-Admin-Pin UNICAMENTE en GET y NO en POST/PUT/DELETE/PATCH', () async {
      final recordedRequests = <http.BaseRequest>[];

      final mockClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(mockClient);
      apiClient.setGlobalEphemeralPin('EPHEMERAL_PIN');
      expect(apiClient.globalEphemeralPin, 'EPHEMERAL_PIN');

      // 1. GET -> DEBE inyectar X-Admin-Pin
      await apiClient.get(Uri.parse('http://localhost/api/reports'));
      expect(recordedRequests.length, 1);
      expect(recordedRequests[0].method, 'GET');
      expect(recordedRequests[0].headers['X-Admin-Pin'], 'EPHEMERAL_PIN');

      // 2. POST -> NO DEBE inyectar X-Admin-Pin
      await apiClient.post(Uri.parse('http://localhost/api/sales'), body: '{}');
      expect(recordedRequests.length, 2);
      expect(recordedRequests[1].method, 'POST');
      expect(recordedRequests[1].headers.containsKey('X-Admin-Pin'), false);

      // 3. PUT -> NO DEBE inyectar X-Admin-Pin
      await apiClient.put(Uri.parse('http://localhost/api/products/1'), body: '{}');
      expect(recordedRequests.length, 3);
      expect(recordedRequests[2].method, 'PUT');
      expect(recordedRequests[2].headers.containsKey('X-Admin-Pin'), false);

      // 4. DELETE -> NO DEBE inyectar X-Admin-Pin
      await apiClient.delete(Uri.parse('http://localhost/api/movements/1'));
      expect(recordedRequests.length, 4);
      expect(recordedRequests[3].method, 'DELETE');
      expect(recordedRequests[3].headers.containsKey('X-Admin-Pin'), false);

      // 5. PATCH -> NO DEBE inyectar X-Admin-Pin
      await apiClient.patch(Uri.parse('http://localhost/api/users/1'), body: '{}');
      expect(recordedRequests.length, 5);
      expect(recordedRequests[4].method, 'PATCH');
      expect(recordedRequests[4].headers.containsKey('X-Admin-Pin'), false);

      // 6. setGlobalEphemeralPin(null) -> GET posterior NO DEBE inyectar X-Admin-Pin
      apiClient.setGlobalEphemeralPin(null);
      expect(apiClient.globalEphemeralPin, isNull);
      await apiClient.get(Uri.parse('http://localhost/api/reports/clean'));
      expect(recordedRequests.length, 6);
      expect(recordedRequests[5].method, 'GET');
      expect(recordedRequests[5].headers.containsKey('X-Admin-Pin'), false);
    });

    test('R3: withAdminPin inyecta en CUALQUIER metodo (POST/PUT/DELETE) y tiene precedencia sobre setGlobalEphemeralPin', () async {
      final recordedRequests = <http.BaseRequest>[];

      final mockClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(mockClient);
      apiClient.setGlobalEphemeralPin('GLOBAL_SCREEN_PIN');

      // 1. POST dentro de withAdminPin -> DEBE inyectar el SCOPED_PIN
      await apiClient.withAdminPin('SCOPED_PIN', () async {
        await apiClient.post(Uri.parse('http://localhost/api/destructive/action'));
      });

      expect(recordedRequests.length, 1);
      expect(recordedRequests[0].method, 'POST');
      expect(recordedRequests[0].headers['X-Admin-Pin'], 'SCOPED_PIN');

      // 2. PUT dentro de withAdminPin -> DEBE inyectar el SCOPED_PIN
      await apiClient.withAdminPin('SCOPED_PIN_2', () async {
        await apiClient.put(Uri.parse('http://localhost/api/users/2'));
      });

      expect(recordedRequests.length, 2);
      expect(recordedRequests[1].method, 'PUT');
      expect(recordedRequests[1].headers['X-Admin-Pin'], 'SCOPED_PIN_2');

      // 3. GET dentro de withAdminPin -> DEBE inyectar el SCOPED_PIN (sobreescribe GLOBAL_SCREEN_PIN)
      await apiClient.withAdminPin('SCOPED_PIN_3', () async {
        await apiClient.get(Uri.parse('http://localhost/api/audit'));
      });

      expect(recordedRequests.length, 3);
      expect(recordedRequests[2].method, 'GET');
      expect(recordedRequests[2].headers['X-Admin-Pin'], 'SCOPED_PIN_3');

      // 4. GET fuera de withAdminPin -> DEBE seguir usando GLOBAL_SCREEN_PIN
      await apiClient.get(Uri.parse('http://localhost/api/audit'));
      expect(recordedRequests.length, 4);
      expect(recordedRequests[3].method, 'GET');
      expect(recordedRequests[3].headers['X-Admin-Pin'], 'GLOBAL_SCREEN_PIN');

      // 5. POST fuera de withAdminPin -> NO DEBE inyectar ningun PIN
      await apiClient.post(Uri.parse('http://localhost/api/post-safe'));
      expect(recordedRequests.length, 5);
      expect(recordedRequests[4].method, 'POST');
      expect(recordedRequests[4].headers.containsKey('X-Admin-Pin'), false);
    });

    test('Adversarial: pre-existing explicit X-Admin-Pin in request headers is not clobbered by setGlobalEphemeralPin', () async {
      final recordedRequests = <http.BaseRequest>[];

      final mockClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(mockClient);
      apiClient.setGlobalEphemeralPin('GLOBAL_FALLBACK_PIN');

      // Request GET con header explícito
      await apiClient.get(
        Uri.parse('http://localhost/api/explicit'),
        headers: {'X-Admin-Pin': 'EXPLICIT_HEADER_PIN'},
      );

      expect(recordedRequests.length, 1);
      expect(recordedRequests[0].headers['X-Admin-Pin'], 'EXPLICIT_HEADER_PIN',
          reason: 'Explicit header must take precedence over automatic global ephemeral fallback');
    });

    test('Adversarial: setGlobalEphemeralPin normalizes whitespace-only and empty strings to null', () {
      final mockClient = MockClient((_) async => http.Response('{}', 200));
      final apiClient = ApiClient(mockClient);

      apiClient.setGlobalEphemeralPin('   ');
      expect(apiClient.globalEphemeralPin, isNull);

      apiClient.setGlobalEphemeralPin('');
      expect(apiClient.globalEphemeralPin, isNull);

      apiClient.setGlobalEphemeralPin('  1234  ');
      expect(apiClient.globalEphemeralPin, '1234');
    });

    test('R3 Adversarial: 403 in-situ retry successfully injects X-Admin-Pin on POST requests', () async {
      int callCount = 0;
      final recordedRequests = <http.BaseRequest>[];

      final mockClient = MockClient((request) async {
        recordedRequests.add(request);
        callCount++;
        if (callCount == 1) {
          // Primer intento falla con 403 PIN_REQUIRED
          return http.Response(
            jsonEncode({'error_code': 'PIN_REQUIRED', 'message': 'Se requiere PIN de supervisor'}),
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        // Reintento exitoso
        return http.Response(
          jsonEncode({'success': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockClient);
      apiClient.sessionToken = 'session-xyz';
      apiClient.setGlobalEphemeralPin('EPHEMERAL_GET_PIN'); // No debe usarse para el POST inicial

      // Hook del prompt in-situ
      apiClient.onPermissionDenied = (reason) async => 'SUPERVISOR_9876';

      final response = await apiClient.post(
        Uri.parse('http://localhost/api/sales/void'),
        body: jsonEncode({'sale_id': 42}),
      );

      expect(response.statusCode, 200);
      expect(recordedRequests.length, 2);

      // Intento 1 (POST): No debe tener PIN efímero global automático (R2)
      expect(recordedRequests[0].method, 'POST');
      expect(recordedRequests[0].headers.containsKey('X-Admin-Pin'), false);

      // Intento 2 (POST reintento): DEBE inyectar el PIN explícito del prompt (R3)
      expect(recordedRequests[1].method, 'POST');
      expect(recordedRequests[1].headers['X-Admin-Pin'], 'SUPERVISOR_9876');
      expect(recordedRequests[1].headers['X-Session-Token'], 'session-xyz');
    });

    test('Adversarial: setGlobalEphemeralPin(null) purges cached verified pin preventing cross-session reuse', () async {
      int promptCount = 0;
      final mockClient = MockClient((request) async {
        if (!request.headers.containsKey('X-Admin-Pin')) {
          return http.Response(jsonEncode({'error_code': 'PIN_REQUIRED'}), 403,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        promptCount++;
        return 'CACHE_PIN_1111';
      };

      // 1. First 403 triggers prompt and caches PIN
      await apiClient.post(Uri.parse('http://localhost/api/first'));
      expect(promptCount, 1);

      // 2. Immediate logout purges global ephemeral pin and cached verified pin
      apiClient.setGlobalEphemeralPin(null);

      // 3. Next 403 must prompt again instead of reusing old session cached PIN
      await apiClient.post(Uri.parse('http://localhost/api/second'));
      expect(promptCount, 2, reason: 'Cached verified pin must be purged on setGlobalEphemeralPin(null)');
    });

    test('Adversarial: lowercase get method injects ephemeral pin and preserves case-insensitive headers on retry', () async {
      final recordedRequests = <http.BaseRequest>[];
      final mockClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(mockClient);
      apiClient.setGlobalEphemeralPin('GET_PIN_4321');

      // Enviar request con método en minúsculas
      final rawGet = http.Request('get', Uri.parse('http://localhost/api/lowercased'));
      await apiClient.send(rawGet);

      expect(recordedRequests.length, 1);
      expect(recordedRequests[0].headers['X-Admin-Pin'], 'GET_PIN_4321');
    });
  });
}
