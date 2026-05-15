import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/usecases/get_current_shift_usecase.dart';
import 'package:frontend_desktop/features/cash_register/domain/usecases/open_shift_usecase.dart';
import 'package:frontend_desktop/features/cash_register/domain/usecases/close_shift_usecase.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';

@GenerateMocks([
  GetCurrentShiftUseCase,
  OpenShiftUseCase,
  CloseShiftUseCase,
])
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

  group('CashRegisterProvider Shift Blocking', () {
    test('Bloqueo de acciones si el estado indica que no hay turno abierto', () async {
      // Simulamos que no hay turno activo en el backend
      when(mockGetCurrentShiftUseCase.call(registerId: anyNamed('registerId')))
          .thenAnswer((_) async => null);

      await provider.checkCurrentShift();

      // Asegurarse de que el estado local no tiene turno activo
      expect(provider.currentShift, null);

      // Si se intenta cerrar el turno cuando está bloqueado/vacío
      final result = await provider.closeShift(1000.0);
      
      // Debe retornar null y bloquear la acción (preventivo)
      expect(result, null);
    });

    test('Permite acciones si hay un turno válido', () async {
      final shift = CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openingBalance: 100,
        status: 'open',
        openedAt: DateTime.now(),
      );

      // Simulamos turno activo
      when(mockGetCurrentShiftUseCase.call(registerId: anyNamed('registerId')))
          .thenAnswer((_) async => shift);

      await provider.checkCurrentShift();

      expect(provider.currentShift?.id, 1);

      // Si se intenta cerrar, el provider debería permitir delegarlo al backend
      when(mockCloseShiftUseCase.call(1, 1000.0, closerUserId: null))
          .thenAnswer((_) async => CashRegisterShift(
                id: 1,
                cashRegisterId: 1,
                userId: 1,
                openingBalance: 100,
                status: 'closed',
                openedAt: DateTime.now(),
              ));

      final closedShift = await provider.closeShift(1000.0);
      
      expect(closedShift?.status, 'closed');
      // Luego de cerrar, el estado vuelve a bloqueado
      expect(provider.currentShift, null);
    });
  });
}
