import '../../domain/entities/cash_register.dart';
import '../../domain/repositories/cash_register_repository.dart';

class GetRegistersUseCase {
  final CashRegisterRepository repository;

  GetRegistersUseCase(this.repository);

  Future<List<CashRegister>> call() async {
    return await repository.getRegisters();
  }
}
