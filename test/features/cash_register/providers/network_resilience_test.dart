import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/core/network/api_client.dart';

import 'cash_register_provider_test.mocks.dart';

void main() {
  late CashRegisterProvider provider;
  late MockGetCurrentShiftUseCase mockGetCurrentShiftUseCase;
  late MockOpenShiftUseCase mockOpenShiftUseCase;
  late MockCloseShiftUseCase mockCloseShiftUseCase;

  setUp(() {
    mockGetCurrentShiftUseCase = MockGetCurrentShiftUseCase();
    mockOpenShiftUseCase = MockOpenShiftUseCase();
    mockCloseShiftUseCase = MockCloseShiftUseCase();

    provider = CashRegisterProvider(
      getCurrentShiftUseCase: mockGetCurrentShiftUseCase,
      openShiftUseCase: mockOpenShiftUseCase,
      closeShiftUseCase: mockCloseShiftUseCase,
    );
  });

  group('Network Resilience y Modos Offline (Fase 3)', () {
    test('Intercepta SocketException (Servidor apagado), frena la carga y emite error manejable', () async {
      // 1. Simulamos que al intentar abrir caja el servidor no responde (SocketException traducido por ApiClient)
      final networkError = NetworkException('No se pudo conectar con el servidor principal. Verifique su conexión a red o si el servidor está encendido.');
      
      when(mockOpenShiftUseCase.call(100.0, 1, null))
          .thenThrow(networkError);

      // Estado inicial
      expect(provider.isLoading, false);
      expect(provider.errorMessage, null);

      // 2. Ejecutamos la acción que falla por red
      final result = await provider.openShift(100.0, 1);

      // 3. Verificamos resiliencia
      expect(result, false); // La acción falló
      expect(provider.isLoading, false); // No se quedó cargando infinitamente
      expect(provider.errorMessage, networkError.message); // El mensaje de error fue propagado para la UI
      expect(provider.currentShift, null); // El estado no se corrompió
    });

    test('Recuperación exitosa: la conexión vuelve en el próximo intento', () async {
      final networkError = NetworkException('No se pudo conectar con el servidor principal.');
      
      // Primer intento falla
      when(mockOpenShiftUseCase.call(100.0, 1, null)).thenThrow(networkError);
      
      await provider.openShift(100.0, 1);
      expect(provider.errorMessage, networkError.message);

      // Segundo intento: el internet volvió
      final validShift = CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openingBalance: 100,
        status: 'open',
        openedAt: DateTime.now(),
      );

      when(mockOpenShiftUseCase.call(100.0, 1, null)).thenAnswer((_) async => validShift);

      final result = await provider.openShift(100.0, 1);

      // Verificamos recuperación total
      expect(result, true);
      expect(provider.isLoading, false);
      expect(provider.errorMessage, null); // El error anterior fue limpiado
      expect(provider.currentShift?.id, 1); // Estado restaurado con éxito
    });
  });
}
