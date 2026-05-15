import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/auth/domain/repositories/auth_repository.dart';

@GenerateMocks([AuthRepository])
import 'auth_provider_test.mocks.dart';

void main() {
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
  });
}
