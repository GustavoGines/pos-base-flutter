import '../../domain/entities/cash_register_shift.dart';
import '../../domain/repositories/cash_register_repository.dart';

class GetCurrentShiftUseCase {
  final CashRegisterRepository repository;

  GetCurrentShiftUseCase(this.repository);

  Future<CashRegisterShift?> call({int? registerId}) async {
    return await repository.getCurrentShift(registerId: registerId);
  }
}
