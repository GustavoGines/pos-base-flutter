import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:frontend_desktop/features/auth/domain/repositories/auth_repository.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';

void main() {
  group('In-Situ Admin PIN Dialog Flow & 403 Interception Widget Test', () {
    testWidgets('Displays AdminPinDialog on 403, accepts PIN keypad input, and retries action', (tester) async {
      int actionRequestCount = 0;
      bool actionCompletedSuccessfully = false;

      // Mock HTTP client:
      // - Handles /api/sales/55/void: first returns 403, retry with X-Admin-Pin returns 200
      // - Handles /api/auth/authorize-pin: returns admin user if PIN is 1234
      final mockClient = MockClient((request) async {
        final path = request.url.path;

        if (path.contains('/api/auth/authorize-pin')) {
          final body = jsonDecode(request.body);
          if (body['pin'] == '1234') {
            return http.Response(
              jsonEncode({
                'authorized': true,
                'user': {'id': 1, 'name': 'Gerente General', 'role': 'admin'},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else {
            return http.Response(
              jsonEncode({'authorized': false, 'message': 'PIN incorrecto'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
        }

        if (path.contains('/api/sales/55/void')) {
          actionRequestCount++;
          if (actionRequestCount == 1) {
            // Primer intento sin PIN -> 403
            return http.Response(
              jsonEncode({
                'error_code': 'PIN_REQUIRED',
                'message': 'Acceso denegado: Se requiere autorización de supervisor para anular.',
              }),
              403,
              headers: {'content-type': 'application/json'},
            );
          } else {
            // Reintento con PIN -> Debe contener X-Admin-Pin
            expect(request.headers['X-Admin-Pin'], '1234');
            return http.Response(
              jsonEncode({'message': 'Venta anulada correctamente', 'status': 'voided'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(mockClient);
      final authRepo = AuthRepository(
        remoteDataSource: AuthRemoteDataSource(baseUrl: 'http://localhost/api', client: apiClient),
      );
      final authProvider = AuthProvider(repository: authRepo)..apiClient = apiClient;

      // Clave de navegación para que ApiClient pueda desplegar el diálogo
      final navKey = GlobalKey<NavigatorState>();

      // Wire up onPermissionDenied hook exactly as in main.dart
      apiClient.onPermissionDenied = (reason) async {
        final ctx = navKey.currentContext;
        if (ctx == null || !ctx.mounted) return null;
        return await showDialog<String>(
          context: ctx,
          barrierDismissible: true,
          builder: (_) => AdminPinDialog(actionDescription: reason ?? 'Acción Restringida'),
        );
      };

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            Provider<ApiClient>.value(value: apiClient),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    key: const Key('btn_void_sale'),
                    onPressed: () async {
                      final client = context.read<ApiClient>();
                      final resp = await client.post(
                        Uri.parse('http://localhost/api/sales/55/void'),
                        headers: {'content-type': 'application/json'},
                        body: jsonEncode({'cash_shift_id': 1}),
                      );
                      if (resp.statusCode == 200) {
                        actionCompletedSuccessfully = true;
                      }
                    },
                    child: const Text('Anular Venta'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // 1. Pantalla inicial con botón
      expect(find.byKey(const Key('btn_void_sale')), findsOneWidget);
      expect(find.byType(AdminPinDialog), findsNothing);

      // 2. Cajero presiona "Anular Venta"
      await tester.tap(find.byKey(const Key('btn_void_sale')));
      await tester.pump(); // Inicia la petición HTTP y recibe 403
      await tester.pumpAndSettle(); // Despliega el modal de PIN

      // 3. El modal de PIN de Administrador se desplegó automáticamente!
      expect(find.byType(AdminPinDialog), findsOneWidget);
      expect(find.text('Acceso Restringido'), findsOneWidget);
      expect(find.textContaining('Se requiere autorización de supervisor'), findsOneWidget);

      // 4. El supervisor presiona los dígitos 1, 2, 3, 4 en el teclado numérico del modal
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '2'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '3'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '4'));
      await tester.pump(); // Al completar 4 dígitos, dispara _verifyAdminPin()

      await tester.pumpAndSettle(); // Espera la respuesta de /auth/authorize-pin y el cierre del diálogo

      // 5. El diálogo se cerró tras validar el PIN
      expect(find.byType(AdminPinDialog), findsNothing);

      // 6. La acción original se re-despachó con el PIN y se completó con éxito!
      expect(actionRequestCount, 2);
      expect(actionCompletedSuccessfully, true);
    });

    testWidgets('Cancelling AdminPinDialog aborts retry and leaves action failed', (tester) async {
      int actionRequestCount = 0;
      int? finalStatusCode;

      final mockClient = MockClient((request) async {
        actionRequestCount++;
        return http.Response(
          jsonEncode({'error_code': 'PIN_REQUIRED', 'message': 'PIN Requerido'}),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockClient);
      final authRepo = AuthRepository(
        remoteDataSource: AuthRemoteDataSource(baseUrl: 'http://localhost/api', client: apiClient),
      );
      final authProvider = AuthProvider(repository: authRepo)..apiClient = apiClient;
      final navKey = GlobalKey<NavigatorState>();

      apiClient.onPermissionDenied = (reason) async {
        final ctx = navKey.currentContext;
        if (ctx == null || !ctx.mounted) return null;
        return await showDialog<String>(
          context: ctx,
          barrierDismissible: true,
          builder: (_) => AdminPinDialog(actionDescription: reason ?? 'Acción'),
        );
      };

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            Provider<ApiClient>.value(value: apiClient),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    key: const Key('btn_action'),
                    onPressed: () async {
                      final client = context.read<ApiClient>();
                      final resp = await client.post(Uri.parse('http://localhost/api/test-action'));
                      finalStatusCode = resp.statusCode;
                    },
                    child: const Text('Acción'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Presionar acción
      await tester.tap(find.byKey(const Key('btn_action')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(AdminPinDialog), findsOneWidget);

      // Cancelar tocando fuera o cerrando el diálogo (pop null)
      navKey.currentState?.pop(null);
      await tester.pumpAndSettle();

      expect(find.byType(AdminPinDialog), findsNothing);
      expect(actionRequestCount, 1, reason: 'Solo se ejecutó el intento inicial sin reintento');
      expect(finalStatusCode, 403);
    });

    testWidgets('AdminPinDialog displays rate limit lockout message from server when throttled (429)', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/auth/authorize-pin')) {
          return http.Response(
            jsonEncode({
              'authorized': false,
              'message': 'Demasiados intentos erróneos de PIN. Operación bloqueada temporalmente por 300 segundos.',
              'error_code': 'PIN_LOCKED_TEMPORARILY',
              'retry_after': 300,
            }),
            429,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(mockClient);
      final authRepo = AuthRepository(
        remoteDataSource: AuthRemoteDataSource(baseUrl: 'http://localhost/api', client: apiClient),
      );
      final authProvider = AuthProvider(repository: authRepo)..apiClient = apiClient;
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            Provider<ApiClient>.value(value: apiClient),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(
              body: AdminPinDialog(actionDescription: 'Prueba de Bloqueo'),
            ),
          ),
        ),
      );

      // Ingresar 4 dígitos
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Debe mostrar el mensaje del rate limit devuelto por el servidor
      expect(find.textContaining('bloqueada temporalmente'), findsOneWidget);
    });
  });
}
