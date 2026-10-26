import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/cash_movements/models/cash_movement_model.dart';
import 'package:frontend_desktop/features/sales_history/domain/entities/sale_record.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/domain/repositories/cash_register_repository.dart';
import 'package:frontend_desktop/features/cash_register/domain/usecases/get_current_shift_usecase.dart';
import 'package:frontend_desktop/features/cash_register/domain/usecases/open_shift_usecase.dart';
import 'package:frontend_desktop/features/cash_register/domain/usecases/close_shift_usecase.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';

class _FakeCashRegisterRepository implements CashRegisterRepository {
  int? lastRequestedRegisterId;
  CashRegisterShift? shiftToReturn;

  @override
  Future<CashRegisterShift?> getCurrentShift({int? registerId}) async {
    lastRequestedRegisterId = registerId;
    return shiftToReturn;
  }

  @override
  Future<CashRegisterShift> openShift(double openingBalance, int userId, [int? registerId]) async {
    lastRequestedRegisterId = registerId;
    shiftToReturn = CashRegisterShift(
      id: 22,
      cashRegisterId: registerId ?? 1,
      userId: userId,
      openedAt: DateTime.now(),
      openingBalance: openingBalance,
      status: 'open',
      cashRegisterName: 'Caja ${registerId ?? 1}',
    );
    return shiftToReturn!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Multi-Caja Audit Regression Suite (MC-01..MC-10)', () {
    test('MC-02: CashMovementModel parses cashShift and exposes cashRegisterId & cashRegisterName', () {
      final json = {
        'id': 10,
        'cash_shift_id': 14,
        'user_id': 1,
        'amount': '1500.00',
        'payment_method': 'cash',
        'type': 'withdrawal',
        'category': 'Retiro de Caja',
        'description': 'Retiro parcial en Caja 2',
        'created_at': '2026-10-26T12:00:00Z',
        'cash_shift': {
          'id': 14,
          'cash_register_id': 2,
          'cash_register': {
            'id': 2,
            'name': 'Caja 2',
          },
        },
      };

      final model = CashMovementModel.fromJson(json);
      expect(model.cashShiftId, 14);
      expect(model.cashRegisterId, 2);
      expect(model.cashRegisterName, 'Caja 2');
    });

    test('MC-02 (Backward Compat v1.8.5): CashMovementModel handles missing cash_shift gracefully', () {
      final json = {
        'id': 11,
        'cash_shift_id': 7,
        'user_id': 1,
        'amount': '500.00',
        'payment_method': 'cash',
        'type': 'expense',
        'category': 'Gasto',
        'created_at': '2026-10-26T12:00:00Z',
      };

      final model = CashMovementModel.fromJson(json);
      expect(model.cashShiftId, 7);
      expect(model.cashRegisterId, isNull);
      expect(model.cashRegisterName, isNull);
    });

    test('MC-08: SaleRecord parses cash_shift.cash_register for origin register traceability', () {
      final json = {
        'id': 99,
        'total': '4500.00',
        'total_surcharge': '0.00',
        'status': 'completed',
        'created_at': '2026-10-26T14:30:00Z',
        'cash_shift_id': 18,
        'cash_shift': {
          'id': 18,
          'cash_register_id': 2,
          'cash_register': {
            'id': 2,
            'name': 'Caja Secundaria',
          },
        },
        'items': [],
        'payments': [],
      };

      final record = SaleRecord.fromJson(json);
      expect(record.cashShiftId, 18);
      expect(record.cashRegisterId, 2);
      expect(record.cashRegisterName, 'Caja Secundaria');
    });

    test('MC-06: CashRegisterProvider preserves activeRegisterId across checkCurrentShift calls without hijacking to null/Caja 1', () async {
      final repo = _FakeCashRegisterRepository();
      final provider = CashRegisterProvider(
        getCurrentShiftUseCase: GetCurrentShiftUseCase(repo),
        openShiftUseCase: OpenShiftUseCase(repo),
        closeShiftUseCase: CloseShiftUseCase(repo),
      );

      // User opens Shift on Caja 2 via dropdown (without locking terminal in Settings)
      final opened = await provider.openShift(5000.0, 1, 2);
      expect(opened, isTrue);
      expect(provider.activeRegisterId, 2);
      expect(provider.currentShift?.cashRegisterId, 2);

      // Subsequent checkCurrentShift() or checkCurrentShiftSilently() with null registerId
      // MUST use activeRegisterId (2) instead of sending null (which defaults to Caja 1 on backend)
      await provider.checkCurrentShift();
      expect(repo.lastRequestedRegisterId, 2);

      await provider.checkCurrentShiftSilently();
      expect(repo.lastRequestedRegisterId, 2);
    });
  });
}
