import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend_desktop/core/network/api_client.dart';

void main() {
  group('Adversarial In-Situ Interception Tests', () {
    test('retried request returning 401 SESSION_EXPIRED triggers onSessionExpired and throws SessionExpiredException', () async {
      int requestCount = 0;
      bool sessionExpiredCallbackCalled = false;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          // 1st attempt: 403 Forbidden PIN_REQUIRED
          return http.Response(
            jsonEncode({
              'error_code': 'PIN_REQUIRED',
              'message': 'Requiere PIN de administrador',
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        } else {
          // 2nd attempt with PIN: Session expired in the meantime!
          return http.Response(
            jsonEncode({
              'error_code': 'SESSION_EXPIRED',
              'message': 'Tu sesión fue cerrada porque otro dispositivo inició sesión.',
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
      });

      final apiClient = ApiClient(mockClient);
      apiClient.sessionToken = 'test-token';
      apiClient.onSessionExpired = () {
        sessionExpiredCallbackCalled = true;
      };
      apiClient.onPermissionDenied = (reason) async => '9999';

      expect(
        () async => await apiClient.post(
          Uri.parse('http://localhost/api/sales/1/void'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'cash_shift_id': 1}),
        ),
        throwsA(isA<SessionExpiredException>()),
      );

      // Verify that after catching exception, onSessionExpired was called
      try {
        await apiClient.post(
          Uri.parse('http://localhost/api/sales/1/void'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'cash_shift_id': 1}),
        );
      } catch (_) {}

      expect(sessionExpiredCallbackCalled, isTrue,
          reason: 'onSessionExpired callback must be called when retry returns 401 SESSION_EXPIRED');
    });

    test('retried request returning 500 throws NetworkException', () async {
      int requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(
            jsonEncode({
              'error_code': 'PIN_REQUIRED',
              'message': 'Requiere PIN',
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        } else {
          // Server crash on retry
          return http.Response(
            'Internal Server Error',
            500,
            headers: {'content-type': 'text/plain'},
          );
        }
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async => '1234';

      expect(
        () async => await apiClient.post(
          Uri.parse('http://localhost/api/sales/1/void'),
          body: jsonEncode({'cash_shift_id': 1}),
        ),
        throwsA(isA<NetworkException>()),
      );
    });

    test('GET request intercepted on 403 retries with X-Admin-Pin and without corrupted body', () async {
      int requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(
            jsonEncode({
              'error_code': 'PIN_REQUIRED',
              'message': 'Requiere ver reportes',
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        } else {
          expect(request.method, 'GET');
          expect(request.headers['X-Admin-Pin'], '7777');
          return http.Response(
            jsonEncode({'reports': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async => '7777';

      final response = await apiClient.get(
        Uri.parse('http://localhost/api/reports/monthly-balance'),
      );

      expect(response.statusCode, 200);
      expect(requestCount, 2);
    });

    test('403 without error_code but with PIN requirement message triggers onPermissionDenied and retries', () async {
      int requestCount = 0;
      bool promptCalled = false;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          // 403 without error_code, e.g. from cash withdrawal or gate
          return http.Response(
            jsonEncode({
              'message': 'Los retiros de dinero requieren PIN de administrador.',
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        } else {
          expect(request.headers['X-Admin-Pin'], '5555');
          return http.Response(
            jsonEncode({'message': 'Movimiento registrado'}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        promptCalled = true;
        expect(reason, contains('requieren PIN'));
        return '5555';
      };

      final response = await apiClient.post(
        Uri.parse('http://localhost/api/cash-movements'),
        headers: {'content-type': 'application/json', 'content-length': '15'},
        body: jsonEncode({'type': 'withdrawal'}),
      );

      expect(response.statusCode, 201);
      expect(promptCalled, isTrue);
      expect(requestCount, 2);
    });

    test('403 with FEATURE_NOT_LICENSED does NOT trigger onPermissionDenied', () async {
      int requestCount = 0;
      bool promptCalled = false;

      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'error_code': 'FEATURE_NOT_LICENSED',
            'message': 'Módulo no incluido en su licencia.',
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        promptCalled = true;
        return '1111';
      };

      final response = await apiClient.get(
        Uri.parse('http://localhost/api/quotes'),
      );

      expect(response.statusCode, 403);
      expect(promptCalled, isFalse, reason: 'License module denial cannot be bypassed by Admin PIN');
      expect(requestCount, 1);
    });

    test('403 with derivative error code PERMISSION_DENIED triggers onPermissionDenied and retries', () async {
      int requestCount = 0;
      bool promptCalled = false;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          expect(request.headers.containsKey('X-Admin-Pin'), isFalse);
          return http.Response(
            jsonEncode({
              'error_code': 'PERMISSION_DENIED',
              'message': 'No cuenta con los permisos necesarios para realizar esta operación.',
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        } else {
          expect(request.headers['X-Admin-Pin'], '3344');
          return http.Response(
            jsonEncode({'message': 'Operación completada exitosamente'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        promptCalled = true;
        return '3344';
      };

      final response = await apiClient.post(
        Uri.parse('http://localhost/api/catalog/products/bulk-delete'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'ids': [1, 2]}),
      );

      expect(response.statusCode, 200);
      expect(promptCalled, isTrue);
      expect(requestCount, 2);
    });

    test('403 with DIFFERENCE_REQUIRES_ADMIN does NOT trigger onPermissionDenied', () async {
      int requestCount = 0;
      bool promptCalled = false;

      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'error_code': 'DIFFERENCE_REQUIRES_ADMIN',
            'message': 'La diferencia de caja requiere autorización de un supervisor.',
            'expected_balance': 1000.0,
            'actual_balance': 800.0,
            'difference': -200.0,
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        promptCalled = true;
        return '9999';
      };

      final response = await apiClient.post(
        Uri.parse('http://localhost/api/shifts/1/close'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'actual_balance': 800.0, 'pin': '1234'}),
      );

      expect(response.statusCode, 403);
      expect(promptCalled, isFalse, reason: 'Difference requires admin is handled by dedicated closeShift UI flow');
      expect(requestCount, 1);
    });
  });
}
