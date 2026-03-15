import '../../domain/entities/cash_register_shift.dart';
import '../../domain/repositories/cash_register_repository.dart';

class CloseShiftUseCase {
  final CashRegisterRepository repository;

  CloseShiftUseCase(this.repository);

  Future<CashRegisterShift> call(double countedCash) async {
    return await repository.closeShift(countedCash);
  }
}
