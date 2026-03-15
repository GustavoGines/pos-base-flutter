import '../../domain/entities/cash_register_shift.dart';
import '../../domain/repositories/cash_register_repository.dart';
import '../datasources/cash_register_remote_datasource.dart';

class CashRegisterRepositoryImpl implements CashRegisterRepository {
  final CashRegisterRemoteDataSource remoteDataSource;

  CashRegisterRepositoryImpl({required this.remoteDataSource});

  @override
  Future<CashRegisterShift?> getCurrentShift() async {
    return await remoteDataSource.getCurrentShift();
  }

  @override
  Future<CashRegisterShift> openShift(double openingBalance) async {
    return await remoteDataSource.openShift(openingBalance);
  }

  @override
  Future<CashRegisterShift> closeShift(double closingBalance) async {
    return await remoteDataSource.closeShift(closingBalance);
  }
}
