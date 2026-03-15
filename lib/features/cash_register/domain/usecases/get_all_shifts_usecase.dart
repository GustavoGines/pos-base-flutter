import '../../domain/entities/cash_register_shift.dart';
import '../../domain/repositories/cash_register_repository.dart';

class GetAllShiftsUseCase {
  final CashRegisterRepository repository;

  GetAllShiftsUseCase(this.repository);

  Future<List<CashRegisterShift>> call() async {
    return await repository.getAllShifts();
  }
}
