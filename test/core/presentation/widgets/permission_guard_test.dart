import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/presentation/widgets/permission_guard.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';

class TestAuthProvider extends ChangeNotifier implements AuthProvider {
  bool _isAdmin = false;
  final Set<String> _permissions = {};
  Map<String, dynamic>? _currentUser;

  TestAuthProvider({
    bool isAdmin = false,
    List<String> permissions = const [],
    Map<String, dynamic>? currentUser,
  }) {
    _isAdmin = isAdmin;
    _permissions.addAll(permissions);
    _currentUser = currentUser ?? {'id': 1, 'name': 'User'};
  }

  @override
  bool get isAdmin => _isAdmin;

  @override
  bool hasPermission(String permission) => _isAdmin || _permissions.contains(permission);

  @override
  Map<String, dynamic>? get currentUser => _currentUser;

  @override
  bool get isAuthenticated => _currentUser != null;

  @override
  Future<Map<String, dynamic>?> authorizePin(String pin) async {
    if (pin == '1234') {
      return {'id': 99, 'name': 'Admin Supervisor', 'role': 'admin'};
    }
    return null;
  }

  void simulateLogout(ApiClient? apiClient) {
    _currentUser = null;
    _isAdmin = false;
    _permissions.clear();
    apiClient?.setGlobalEphemeralPin(null);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PermissionGuard and ApiClient Ephemeral PIN Integration', () {
    testWidgets('R1: Route con injectedPin inyecta setGlobalEphemeralPin en ApiClient y provee InheritedAdminPin', (tester) async {
      final recordedRequests = <http.BaseRequest>[];
      final mockClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: []);

      String? capturedInheritedPin;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            initialRoute: '/',
            onGenerateRoute: (settings) {
              return MaterialPageRoute(
                settings: const RouteSettings(
                  name: '/protected',
                  arguments: {'unlocked_pin': '8877'},
                ),
                builder: (_) => PermissionGuard(
                  permissionKey: 'view_reports',
                  child: Builder(
                    builder: (context) {
                      capturedInheritedPin = InheritedAdminPin.of(context);
                      return const Text('Protected Content Screen');
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verifica que el contenido protegido se renderice
      expect(find.text('Protected Content Screen'), findsOneWidget);

      // Verifica que InheritedAdminPin tenga el PIN inyectado
      expect(capturedInheritedPin, '8877');

      // Verifica que ApiClient tenga el PIN efímero global
      expect(apiClient.globalEphemeralPin, '8877');

      // R2: Request GET dentro de la pantalla viva DEBE incluir X-Admin-Pin
      await apiClient.get(Uri.parse('http://localhost/api/reports'));
      expect(recordedRequests.length, 1);
      expect(recordedRequests[0].method, 'GET');
      expect(recordedRequests[0].headers['X-Admin-Pin'], '8877');

      // R2: Request POST dentro de la pantalla viva NO DEBE incluir X-Admin-Pin
      await apiClient.post(Uri.parse('http://localhost/api/reports/export'), body: '{}');
      expect(recordedRequests.length, 2);
      expect(recordedRequests[1].method, 'POST');
      expect(recordedRequests[1].headers.containsKey('X-Admin-Pin'), false);
    });

    testWidgets('R1: dispose de PermissionGuard purga setGlobalEphemeralPin(null) en ApiClient', (tester) async {
      final recordedRequests = <http.BaseRequest>[];
      final mockClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: []);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        settings: const RouteSettings(
                          arguments: {'unlocked_pin': '4455'},
                        ),
                        builder: (_) => const PermissionGuard(
                          permissionKey: 'protected_screen',
                          child: Text('Screen Alive'),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Screen'),
                );
              },
            ),
          ),
        ),
      );

      // Abrir pantalla protegida con PIN
      await tester.tap(find.text('Open Screen'));
      await tester.pumpAndSettle();

      expect(find.text('Screen Alive'), findsOneWidget);
      expect(apiClient.globalEphemeralPin, '4455');

      // GET mientras está viva -> contiene X-Admin-Pin
      await apiClient.get(Uri.parse('http://localhost/api/data'));
      expect(recordedRequests.last.headers['X-Admin-Pin'], '4455');

      // Cerrar pantalla protegida (pop -> dispose)
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // La pantalla ya no está viva
      expect(find.text('Screen Alive'), findsNothing);

      // ApiClient DEBE tener el PIN efímero global en null
      expect(apiClient.globalEphemeralPin, isNull);

      // GET posterior NO contiene X-Admin-Pin
      await apiClient.get(Uri.parse('http://localhost/api/data-after-pop'));
      expect(recordedRequests.last.headers.containsKey('X-Admin-Pin'), false);
    });

    testWidgets('Adversarial: Popping an authorized screen (no PIN) does NOT purge ephemeral PIN of underlying screen', (tester) async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'ok': true}), 200));
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: ['authorized_perm']);

      late BuildContext innerContext;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                innerContext = context;
                return const Text('Root');
              },
            ),
          ),
        ),
      );

      // 1. Abrir Pantalla A (requiere PIN, desbloqueada con '1111')
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '1111'}),
          builder: (_) => const PermissionGuard(
            permissionKey: 'protected_a',
            child: Text('Screen A Protected'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Screen A Protected'), findsOneWidget);
      expect(apiClient.globalEphemeralPin, '1111');

      // 2. Desde Pantalla A, abrir Pantalla B (el usuario TIENE permiso 'authorized_perm', NO requiere PIN)
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          builder: (_) => const PermissionGuard(
            permissionKey: 'authorized_perm',
            child: Text('Screen B Authorized'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Screen B Authorized'), findsOneWidget);

      // 3. Cerrar Pantalla B (pop -> dispose de Pantalla B)
      Navigator.pop(innerContext);
      await tester.pumpAndSettle();

      expect(find.text('Screen B Authorized'), findsNothing);
      expect(find.text('Screen A Protected'), findsOneWidget);

      // Pantalla A sigue viva: el PIN en ApiClient DEBE seguir siendo '1111'
      expect(apiClient.globalEphemeralPin, '1111',
          reason: 'Screen B dispose must not wipe out Screen A ephemeral pin');
    });

    testWidgets('Adversarial: Popping a screen with PIN restores previous screen PIN', (tester) async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'ok': true}), 200));
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: []);

      late BuildContext innerContext;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                innerContext = context;
                return const Text('Root');
              },
            ),
          ),
        ),
      );

      // 1. Abrir Pantalla A con PIN '1111'
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '1111'}),
          builder: (_) => const PermissionGuard(
            permissionKey: 'protected_a',
            child: Text('Screen A Protected'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '1111');

      // 2. Abrir Pantalla B con PIN '2222'
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '2222'}),
          builder: (_) => const PermissionGuard(
            permissionKey: 'protected_b',
            child: Text('Screen B Protected'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '2222');

      // 3. Cerrar Pantalla B (pop)
      Navigator.pop(innerContext);
      await tester.pumpAndSettle();

      expect(find.text('Screen B Protected'), findsNothing);
      expect(find.text('Screen A Protected'), findsOneWidget);

      // ApiClient DEBE haber restaurado el PIN de Pantalla A ('1111')
      expect(apiClient.globalEphemeralPin, '1111',
          reason: 'Popping Screen B must restore Screen A ephemeral pin');
    });

    testWidgets('Adversarial: Canceling PIN dialog on new screen does NOT wipe out underlying screen PIN', (tester) async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'ok': true}), 200));
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: []);

      late BuildContext innerContext;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                innerContext = context;
                return const Text('Root');
              },
            ),
          ),
        ),
      );

      // 1. Abrir Pantalla A con PIN '5555'
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '5555'}),
          builder: (_) => const PermissionGuard(
            permissionKey: 'protected_a',
            child: Text('Screen A Protected'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '5555');

      // 2. Abrir Pantalla B (sin PIN previo -> mostrará dialog)
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          builder: (_) => const PermissionGuard(
            permissionKey: 'protected_b',
            child: Text('Screen B Protected'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Diálogo de PIN visible
      expect(find.byType(AdminPinDialog), findsOneWidget);

      // 3. Cancelar el diálogo cerrándolo
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.pop(); // cierra el diálogo con null
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Al cancelar el diálogo, PermissionGuard hace Navigator.pop() y se destruye
      expect(find.text('Screen A Protected'), findsOneWidget);

      // El PIN de Pantalla A en ApiClient DEBE seguir intacto ('5555')
      expect(apiClient.globalEphemeralPin, '5555',
          reason: 'Canceling dialog on Screen B must not destroy Screen A pin');
    });

    testWidgets('Adversarial: pushReplacement from Screen A to Screen B preserves Screen B PIN', (tester) async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'ok': true}), 200));
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: []);

      late BuildContext innerContext;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                innerContext = context;
                return const Text('Root');
              },
            ),
          ),
        ),
      );

      // 1. Navegar a Pantalla A con PIN '1111'
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '1111'}),
          builder: (ctx) {
            innerContext = ctx;
            return const PermissionGuard(
              permissionKey: 'protected_a',
              child: Text('Screen A'),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Screen A'), findsOneWidget);
      expect(apiClient.globalEphemeralPin, '1111');

      // 2. Desde Pantalla A, hacer pushReplacement a Pantalla B con PIN '2222'
      Navigator.pushReplacement(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '2222'}),
          builder: (_) => const PermissionGuard(
            permissionKey: 'protected_b',
            child: Text('Screen B'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Screen A'), findsNothing);
      expect(find.text('Screen B'), findsOneWidget);

      // ApiClient DEBE tener el PIN de Pantalla B ('2222'), NO ser null!
      expect(apiClient.globalEphemeralPin, '2222',
          reason: 'pushReplacement to Screen B must preserve Screen B ephemeral PIN');
    });

    testWidgets('Adversarial: pushReplacement from Screen A to Screen B without PIN clears globalEphemeralPin', (tester) async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'ok': true}), 200));
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: ['authorized_b']);

      late BuildContext innerContext;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                innerContext = context;
                return const Text('Root');
              },
            ),
          ),
        ),
      );

      // 1. Screen A con PIN '1111'
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '1111'}),
          builder: (ctx) {
            innerContext = ctx;
            return const PermissionGuard(
              permissionKey: 'protected_a',
              child: Text('Screen A'),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '1111');

      // 2. pushReplacement a Screen B que no necesita PIN
      Navigator.pushReplacement(
        innerContext,
        MaterialPageRoute(
          builder: (_) => const PermissionGuard(
            permissionKey: 'authorized_b',
            child: Text('Screen B Authorized'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Screen A'), findsNothing);
      expect(find.text('Screen B Authorized'), findsOneWidget);
      expect(apiClient.globalEphemeralPin, isNull,
          reason: 'pushReplacement to screen without PIN must leave globalEphemeralPin null');
    });

    testWidgets('Adversarial: Screen A rebuild underneath active Screen B does not hijack top of stack', (tester) async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'ok': true}), 200));
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: []);

      late StateSetter triggerRebuildA;
      late BuildContext innerContext;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                innerContext = context;
                return const Text('Root');
              },
            ),
          ),
        ),
      );

      // 1. Abrir Pantalla A con PIN '1111'
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '1111'}),
          builder: (ctx) {
            innerContext = ctx;
            return StatefulBuilder(
              builder: (context, setState) {
                triggerRebuildA = setState;
                return const PermissionGuard(
                  permissionKey: 'protected_a',
                  child: Text('Screen A Protected'),
                );
              },
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '1111');

      // 2. Abrir Pantalla B encima con PIN '2222'
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '2222'}),
          builder: (_) => const PermissionGuard(
            permissionKey: 'protected_b',
            child: Text('Screen B Protected'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '2222');

      // 3. Forzar rebuild de Pantalla A mientras Pantalla B sigue activa encima
      triggerRebuildA(() {});
      await tester.pump();

      // ApiClient DEBE mantener el PIN de Pantalla B ('2222'), no volver a '1111'!
      expect(apiClient.globalEphemeralPin, '2222',
          reason: 'Rebuilding underlying Screen A must not hijack top of ephemeral pin stack');

      // 4. Popping Pantalla B ahora sí debe restaurar Pantalla A ('1111')
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('Screen B Protected'), findsNothing);
      expect(find.text('Screen A Protected'), findsOneWidget);
      expect(apiClient.globalEphemeralPin, '1111');
    });

    testWidgets('Adversarial: 3-level route stack restores LIFO correctly at each pop', (tester) async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'ok': true}), 200));
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: []);

      late BuildContext innerContext;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                innerContext = context;
                return const Text('Root');
              },
            ),
          ),
        ),
      );

      // Nivel 1: Screen A ('1111')
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '1111'}),
          builder: (ctx) {
            innerContext = ctx;
            return const PermissionGuard(permissionKey: 'perm_a', child: Text('A'));
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '1111');

      // Nivel 2: Screen B ('2222')
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '2222'}),
          builder: (ctx) {
            innerContext = ctx;
            return const PermissionGuard(permissionKey: 'perm_b', child: Text('B'));
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '2222');

      // Nivel 3: Screen C ('3333')
      Navigator.push(
        innerContext,
        MaterialPageRoute(
          settings: const RouteSettings(arguments: {'unlocked_pin': '3333'}),
          builder: (ctx) {
            innerContext = ctx;
            return const PermissionGuard(permissionKey: 'perm_c', child: Text('C'));
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '3333');

      // Pop C -> restores B ('2222')
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '2222');

      // Pop B -> restores A ('1111')
      navigator.pop();
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, '1111');

      // Pop A -> restores null
      navigator.pop();
      await tester.pumpAndSettle();
      expect(apiClient.globalEphemeralPin, isNull);
    });

    testWidgets('Adversarial: Route with non-Map arguments does not crash with TypeError', (tester) async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'ok': true}), 200));
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            initialRoute: '/',
            onGenerateRoute: (settings) {
              return MaterialPageRoute(
                settings: const RouteSettings(
                  name: '/catalog',
                  arguments: 'raw_string_argument_123',
                ),
                builder: (_) => const PermissionGuard(
                  permissionKey: 'catalog',
                  child: Text('Catalog Content Screen'),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Catalog Content Screen'), findsOneWidget);
    });

    testWidgets('Adversarial: Logging out invalidates PermissionGuard temporary pin and leaves globalEphemeralPin null', (tester) async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'ok': true}), 200));
      final apiClient = ApiClient(mockClient);
      final authProvider = TestAuthProvider(isAdmin: false, permissions: []);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: apiClient),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            home: const PermissionGuard(
              permissionKey: 'protected_feature',
              child: Text('Unlocked Feature Content'),
            ),
          ),
        ),
      );

      // 1. Desbloquear pantalla ingresando PIN
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(AdminPinDialog), findsOneWidget);
      // Introducir '1234'
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.widgetWithText(InkWell, digit));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('Unlocked Feature Content'), findsOneWidget);
      expect(apiClient.globalEphemeralPin, '1234');

      // 2. Simular Logout del usuario
      authProvider.simulateLogout(apiClient);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // ApiClient NO DEBE haber resucitado el PIN '1234'
      expect(apiClient.globalEphemeralPin, isNull,
          reason: 'Logout must not allow PermissionGuard to resurrect temporary admin pin');
      // La pantalla protegida NO DEBE seguir visible
      expect(find.text('Unlocked Feature Content'), findsNothing);
    });
  });
}


