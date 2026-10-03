import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend_desktop/core/network/api_client.dart';

void main() {
  group('ApiClient 403 In-Situ Permission Interception & Re-dispatch', () {
    test('intercepts 403 PIN_REQUIRED, prompts for PIN, and retries with X-Admin-Pin header', () async {
      int requestCount = 0;
      final recordedHeaders = <Map<String, String>>[];
      String? promptReason;

      final mockClient = MockClient((request) async {
        requestCount++;
        recordedHeaders.add(Map.from(request.headers));

        if (requestCount == 1) {
          // Primer intento: el backend rechaza por falta de permisos
          return http.Response(
            jsonEncode({
              'error_code': 'PIN_REQUIRED',
              'message': 'Acceso denegado: Se requiere permiso void_sales o PIN de administrador.',
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        } else {
          // Segundo intento: el backend recibe el PIN y autoriza la anulación
          expect(request.headers['X-Admin-Pin'], '4321');
          return http.Response(
            jsonEncode({'status': 'voided', 'message': 'Venta anulada con éxito'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      });

      final apiClient = ApiClient(mockClient);
      apiClient.sessionToken = 'test-cashier-session';

      // Simulamos el modal que ingresa el PIN del supervisor
      apiClient.onPermissionDenied = (reason) async {
        promptReason = reason;
        return '4321'; // PIN ingresado por el supervisor
      };

      final response = await apiClient.post(
        Uri.parse('http://localhost/api/sales/10/void'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'cash_shift_id': 1}),
      );

      // Verificaciones
      expect(response.statusCode, 200);
      final body = jsonDecode(response.body);
      expect(body['status'], 'voided');
      expect(requestCount, 2);
      expect(promptReason, contains('void_sales'));
      expect(recordedHeaders[0].containsKey('X-Admin-Pin'), false);
      expect(recordedHeaders[1]['X-Admin-Pin'], '4321');
      expect(recordedHeaders[1]['X-Session-Token'], 'test-cashier-session');
    });

    test('intercepts 403 UNAUTHORIZED_PRICE_DISCOUNT on sales and retries in-situ with PIN', () async {
      int requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(
            jsonEncode({
              'error_code': 'UNAUTHORIZED_PRICE_DISCOUNT',
              'message': "Rebaja no autorizada en producto 'Amoladora'. Requiere PIN.",
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        } else {
          expect(request.headers['X-Admin-Pin'], '8888');
          return http.Response(
            jsonEncode({'message': 'Venta registrada correctamente', 'sale_id': 99}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async => '8888';

      final response = await apiClient.post(
        Uri.parse('http://localhost/api/pos/sales'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'total': 2500}),
      );

      expect(response.statusCode, 201);
      final body = jsonDecode(response.body);
      expect(body['sale_id'], 99);
      expect(requestCount, 2);
    });

    test('returns 403 without retry when supervisor cancels the PIN prompt (returns null)', () async {
      int requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'error_code': 'PIN_REQUIRED',
            'message': 'Requiere PIN de administrador.',
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockClient);
      // El usuario cancela el modal (presiona cancelar o escape)
      apiClient.onPermissionDenied = (reason) async => null;

      final response = await apiClient.post(
        Uri.parse('http://localhost/api/sales/5/void'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'cash_shift_id': 1}),
      );

      expect(response.statusCode, 403);
      final body = jsonDecode(response.body);
      expect(body['error_code'], 'PIN_REQUIRED');
      expect(requestCount, 1, reason: 'No se debe reintentar si el usuario canceló');
    });

    test('does NOT intercept auth verification endpoints to prevent deadlock loops', () async {
      int requestCount = 0;
      bool promptCalled = false;

      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({'authorized': false, 'message': 'PIN incorrecto'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        promptCalled = true;
        return '1111';
      };

      final response = await apiClient.post(
        Uri.parse('http://localhost/api/auth/authorize-pin'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'pin': '0000'}),
      );

      expect(response.statusCode, 401);
      expect(promptCalled, false, reason: 'Rutas de auth no deben disparar el interceptor');
      expect(requestCount, 1);
    });

    test('does not loop when retried request with X-Admin-Pin still fails (invalid PIN)', () async {
      int requestCount = 0;
      int promptCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'error_code': 'INVALID_ADMIN_PIN',
            'message': 'El PIN ingresado es incorrecto.',
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        promptCount++;
        return 'wrong-pin';
      };

      final response = await apiClient.post(
        Uri.parse('http://localhost/api/sales/1/void'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'cash_shift_id': 1}),
      );

      expect(response.statusCode, 403);
      expect(requestCount, 2, reason: 'Intento 1 sin PIN, Intento 2 con PIN');
      expect(promptCount, 1, reason: 'Solo debe pedir PIN una vez, no encadenar bucle');
    });

    test('concurrency: simultaneous 403 responses share single PIN prompt and retry cleanly', () async {
      int promptCallCount = 0;

      final mockClient = MockClient((request) async {
        final pin = request.headers['X-Admin-Pin'];
        if (pin == null) {
          return http.Response(
            jsonEncode({'error_code': 'PIN_REQUIRED', 'message': 'PIN requerido'}),
            403,
            headers: {'content-type': 'application/json'},
          );
        } else {
          return http.Response(
            jsonEncode({'status': 'ok', 'url': request.url.path}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        promptCallCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return '5555';
      };

      // Disparar dos peticiones en paralelo
      final future1 = apiClient.post(Uri.parse('http://localhost/api/action1'));
      final future2 = apiClient.post(Uri.parse('http://localhost/api/action2'));

      final responses = await Future.wait([future1, future2]);

      expect(responses[0].statusCode, 200);
      expect(responses[1].statusCode, 200);
      expect(promptCallCount, 1, reason: 'El mutex debe prevenir modales superpuestos');
    });
  });
}
