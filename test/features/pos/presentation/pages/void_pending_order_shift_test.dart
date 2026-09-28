import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

import '../../providers/pos_provider_test.mocks.dart';
import '../../../cash_register/providers/cash_register_provider_test.mocks.dart';

/// Helper widget that reproduces the exact pos_screen.dart shift-guarded voiding logic:
///
/// ```dart
/// final currentShift = context.read<CashRegisterProvider>().currentShift;
/// if (currentShift == null) {
///   SnackBarService.error(context, 'Debe haber un turno de caja abierto para anular órdenes.');
///   return;
/// }
/// await posProvider.voidPendingOrder(saleId, shiftId: currentShift.id);
/// ```
class TestVoidOrderWidget extends StatelessWidget {
  final int saleId;
  final VoidCallback? onSuccess;
  final void Function(String error)? onError;

  const TestVoidOrderWidget({
    super.key,
    required this.saleId,
    this.onSuccess,
    this.onError,
  });

  Future<void> _handleVoid(BuildContext context) async {
    final currentShift = context.read<CashRegisterProvider>().currentShift;
    if (currentShift == null) {
      SnackBarService.error(
        context,
        'Debe haber un turno de caja abierto para anular órdenes.',
      );
      onError?.call('Debe haber un turno de caja abierto para anular órdenes.');
      return;
    }

    final posProvider = context.read<PosProvider>();
    final success = await posProvider.voidPendingOrder(saleId, shiftId: currentShift.id);
    if (success) {
      onSuccess?.call();
    } else {
      onError?.call(posProvider.errorMessage ?? 'Error desconocido');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      key: const Key('void_order_button'),
      onPressed: () => _handleVoid(context),
      child: const Text('Anular Orden'),
    );
  }
}

void main() {
  late MockPosRepository mockPosRepository;
  late MockProcessSaleUseCase mockProcessSaleUseCase;
  late MockSearchProductsUseCase mockSearchProductsUseCase;
  late PosProvider posProvider;

  late MockGetCurrentShiftUseCase mockGetCurrentShiftUseCase;
  late MockOpenShiftUseCase mockOpenShiftUseCase;
  late MockCloseShiftUseCase mockCloseShiftUseCase;
  late CashRegisterProvider cashRegisterProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    mockPosRepository = MockPosRepository();
    mockProcessSaleUseCase = MockProcessSaleUseCase();
    mockSearchProductsUseCase = MockSearchProductsUseCase();

    when(mockPosRepository.fetchPaymentMethods()).thenAnswer((_) async => []);
    when(mockPosRepository.fetchPendingSales()).thenAnswer((_) async => []);

    posProvider = PosProvider(
      processSaleUseCase: mockProcessSaleUseCase,
      searchProductsUseCase: mockSearchProductsUseCase,
      repository: mockPosRepository,
    );

    mockGetCurrentShiftUseCase = MockGetCurrentShiftUseCase();
    mockOpenShiftUseCase = MockOpenShiftUseCase();
    mockCloseShiftUseCase = MockCloseShiftUseCase();

    cashRegisterProvider = CashRegisterProvider(
      getCurrentShiftUseCase: mockGetCurrentShiftUseCase,
      openShiftUseCase: mockOpenShiftUseCase,
      closeShiftUseCase: mockCloseShiftUseCase,
    );
  });

  group('Empirical Verification of voidPendingOrder: currentShift null vs open (Requirement 3)', () {
    test('posProvider.voidPendingOrder strictly requires shiftId and passes it to repository', () async {
      const testSaleId = 777;
      const testShiftId = 15;

      when(mockPosRepository.voidPendingSale(testSaleId, shiftId: testShiftId))
          .thenAnswer((_) async => {'message': 'Sale voided successfully'});

      final success = await posProvider.voidPendingOrder(testSaleId, shiftId: testShiftId);

      expect(success, isTrue);
      verify(mockPosRepository.voidPendingSale(testSaleId, shiftId: testShiftId)).called(1);
    });

    testWidgets('When currentShift is NULL: blocks voidPendingOrder and displays error snackbar', (tester) async {
      // Simulate no shift open
      when(mockGetCurrentShiftUseCase.call(registerId: anyNamed('registerId')))
          .thenAnswer((_) async => null);
      await cashRegisterProvider.checkCurrentShift();
      expect(cashRegisterProvider.currentShift, isNull);

      String? recordedError;
      bool wasSuccessCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: posProvider),
                ChangeNotifierProvider.value(value: cashRegisterProvider),
              ],
              child: TestVoidOrderWidget(
                saleId: 123,
                onSuccess: () => wasSuccessCalled = true,
                onError: (err) => recordedError = err,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap void order button
      await tester.tap(find.byKey(const Key('void_order_button')));
      await tester.pumpAndSettle();

      // 1. Error message was emitted
      expect(recordedError, equals('Debe haber un turno de caja abierto para anular órdenes.'));
      expect(wasSuccessCalled, isFalse);

      // 2. SnackBar displayed
      expect(find.text('Debe haber un turno de caja abierto para anular órdenes.'), findsOneWidget);

      // 3. posProvider / repository was NEVER called with any shiftId
      verifyNever(mockPosRepository.voidPendingSale(any, shiftId: anyNamed('shiftId')));
    });

    testWidgets('When currentShift is OPEN: passes currentShift.id to voidPendingOrder and succeeds', (tester) async {
      const openShiftId = 88;
      const targetSaleId = 456;

      final openShift = CashRegisterShift(
        id: openShiftId,
        cashRegisterId: 1,
        userId: 2,
        openingBalance: 5000.0,
        status: 'open',
        openedAt: DateTime.now(),
      );

      when(mockGetCurrentShiftUseCase.call(registerId: anyNamed('registerId')))
          .thenAnswer((_) async => openShift);
      await cashRegisterProvider.checkCurrentShift();
      expect(cashRegisterProvider.currentShift, isNotNull);
      expect(cashRegisterProvider.currentShift!.id, equals(openShiftId));

      when(mockPosRepository.voidPendingSale(targetSaleId, shiftId: openShiftId))
          .thenAnswer((_) async => {'message': 'Order voided'});

      bool wasSuccessCalled = false;
      String? recordedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: posProvider),
                ChangeNotifierProvider.value(value: cashRegisterProvider),
              ],
              child: TestVoidOrderWidget(
                saleId: targetSaleId,
                onSuccess: () => wasSuccessCalled = true,
                onError: (err) => recordedError = err,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap void order button
      await tester.tap(find.byKey(const Key('void_order_button')));
      await tester.pumpAndSettle();

      // 1. Successful execution
      expect(wasSuccessCalled, isTrue);
      expect(recordedError, isNull);

      // 2. Repository received the exact saleId and shiftId
      verify(mockPosRepository.voidPendingSale(targetSaleId, shiftId: openShiftId)).called(1);
    });

    testWidgets('When currentShift is OPEN but backend fails: captures error properly', (tester) async {
      const openShiftId = 88;
      const targetSaleId = 456;

      final openShift = CashRegisterShift(
        id: openShiftId,
        cashRegisterId: 1,
        userId: 2,
        openingBalance: 5000.0,
        status: 'open',
        openedAt: DateTime.now(),
      );

      when(mockGetCurrentShiftUseCase.call(registerId: anyNamed('registerId')))
          .thenAnswer((_) async => openShift);
      await cashRegisterProvider.checkCurrentShift();

      when(mockPosRepository.voidPendingSale(targetSaleId, shiftId: openShiftId))
          .thenThrow(Exception('Backend 403: Shift is not authorized'));

      bool wasSuccessCalled = false;
      String? recordedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: posProvider),
                ChangeNotifierProvider.value(value: cashRegisterProvider),
              ],
              child: TestVoidOrderWidget(
                saleId: targetSaleId,
                onSuccess: () => wasSuccessCalled = true,
                onError: (err) => recordedError = err,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap void order button
      await tester.tap(find.byKey(const Key('void_order_button')));
      await tester.pumpAndSettle();

      expect(wasSuccessCalled, isFalse);
      expect(recordedError, contains('Backend 403: Shift is not authorized'));
      verify(mockPosRepository.voidPendingSale(targetSaleId, shiftId: openShiftId)).called(1);
    });
  });
}
