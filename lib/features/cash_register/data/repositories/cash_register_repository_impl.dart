import '../../domain/entities/cash_register_shift.dart';
import '../../domain/repositories/cash_register_repository.dart';
import '../datasources/cash_register_remote_datasource.dart';

class CashRegisterRepositoryImpl implements CashRegisterRepository {
  final CashRegisterRemoteDataSource remoteDataSource;

  CashRegisterRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<CashRegisterShift>> getAllShifts() async {
    return await remoteDataSource.getAllShifts();
  }

  @override
  Future<CashRegisterShift?> getCurrentShift() async {
    return await remoteDataSource.getCurrentShift();
  }

  @override
  Future<CashRegisterShift> openShift(double openingBalance, int userId) async {
    return await remoteDataSource.openShift(openingBalance, userId);
  }

  @override
  Future<CashRegisterShift> closeShift(double countedCash) async {
    return await remoteDataSource.closeShift(countedCash);
  }
}
