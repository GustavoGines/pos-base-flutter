import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/auth/domain/repositories/auth_repository.dart';

@GenerateMocks([AuthRepository])
import 'auth_provider_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthProvider provider;
  late MockAuthRepository mockRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRepo = MockAuthRepository();
    provider = AuthProvider(repository: mockRepo);
  });

  group('AuthProvider Security & Roles', () {
    test('Simula 401 Unauthorized provocando limpieza de token y estado', () async {
      // 1. Simular login exitoso inicial
      when(mockRepo.verifyPin('1234')).thenAnswer((_) async => {
        'user': {'id': 1, 'name': 'John', 'role': 'cashier'},
        'session_token': 'secure-uuid-token',
        'requires_pin_change': false
      });
      
      await provider.verifyPin('1234');
      
      expect(provider.isAuthenticated, true);
      expect(provider.sessionToken, 'secure-uuid-token');
      expect(provider.currentUser?['name'], 'John');
      
      // 2. Simular recepción de 401 Unauthorized desde backend (Interceptor)
      // El interceptor llamaría a provider.forceLogout()
      await provider.forceLogout();
      
      // 3. Verificar estado limpio y seguro
      expect(provider.isAuthenticated, false);
      expect(provider.sessionToken, null);
      expect(provider.currentUser, null);
      
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pos_session_token'), null);
    });

    test('Verifica Privilegios de Rol (Admin vs Cashier)', () async {
      // Cajero estándar
      when(mockRepo.verifyPin('1111')).thenAnswer((_) async => {
        'user': {
          'id': 2, 
          'name': 'Cajero Local', 
          'role': 'cashier', 
          'permissions': ['sell', 'daily_close']
        },
        'session_token': 'token1',
        'requires_pin_change': false
      });
      
      await provider.verifyPin('1111');
      expect(provider.isAdmin, false);
      expect(provider.hasPermission('config_g3'), false); // No puede entrar a config
      expect(provider.hasPermission('advanced_void'), false); // No puede anular
      expect(provider.hasPermission('sell'), true);
      
      // Admin global
      when(mockRepo.verifyPin('9999')).thenAnswer((_) async => {
        'user': {
          'id': 1, 
          'name': 'Dueño Admin', 
          'role': 'admin',
          'permissions': [] // El admin no necesita lista
        },
        'session_token': 'token2',
        'requires_pin_change': false
      });
      
      await provider.verifyPin('9999');
      expect(provider.isAdmin, true);
      expect(provider.hasPermission('config_g3'), true); // Acceso total automático
      expect(provider.hasPermission('advanced_void'), true);
    });

    test('Usuario con permiso comodín "all" tiene acceso a cualquier permiso', () async {
      when(mockRepo.verifyPin('7777')).thenAnswer((_) async => {
        'user': {
          'id': 3,
          'name': 'Supervisor Turno',
          'role': 'cashier',
          'permissions': ['all']
        },
        'session_token': 'token3',
        'requires_pin_change': false
      });

      await provider.verifyPin('7777');
      expect(provider.isAdmin, false);
      expect(provider.hasPermission('void_sales'), true);
      expect(provider.hasPermission('manage_settings'), true);
      expect(provider.hasPermission('cualquier_otro_permiso'), true);
    });

    test('logout y forceLogout purgan globalEphemeralPin en ApiClient', () async {
      final mockHttpClient = MockHttpClientForTest();
      final apiClient = ApiClient(mockHttpClient);
      provider.apiClient = apiClient;

      // 1. Simular PIN efímero activo en ApiClient
      apiClient.setGlobalEphemeralPin('9988');
      expect(apiClient.globalEphemeralPin, '9988');

      // 2. forceLogout -> DEBE purgar el PIN efímero
      await provider.forceLogout();
      expect(apiClient.globalEphemeralPin, isNull);

      // 3. Simular PIN nuevamente y probar logout() manual
      apiClient.setGlobalEphemeralPin('7766');
      expect(apiClient.globalEphemeralPin, '7766');

      when(mockRepo.logout(any)).thenAnswer((_) async {});
      await provider.logout();
      expect(apiClient.globalEphemeralPin, isNull);
    });
  });
}

class MockHttpClientForTest extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}
