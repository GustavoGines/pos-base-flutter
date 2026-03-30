import '../../domain/entities/cash_register_shift.dart';
import '../../domain/repositories/cash_register_repository.dart';

class OpenShiftUseCase {
  final CashRegisterRepository repository;

  OpenShiftUseCase(this.repository);

  Future<CashRegisterShift> call(double openingBalance, int userId, [int? registerId]) async {
    return await repository.openShift(openingBalance, userId, registerId);
  }
}
