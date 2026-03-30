import '../../domain/entities/cash_register_shift.dart';
import '../../domain/repositories/cash_register_repository.dart';
import '../datasources/cash_register_remote_datasource.dart';
import '../models/cash_register_model.dart';
import '../../domain/entities/cash_register.dart';

class CashRegisterRepositoryImpl implements CashRegisterRepository {
  final CashRegisterRemoteDataSource remoteDataSource;

  CashRegisterRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<CashRegister>> getRegisters() async {
    final registersJson = await remoteDataSource.getRegisters();
    return registersJson.map((e) => CashRegisterModel.fromJson(e)).toList();
  }

  @override
  Future<List<CashRegisterShift>> getAllShifts() async {
    return await remoteDataSource.getAllShifts();
  }

  @override
  Future<CashRegisterShift?> getCurrentShift({int? registerId}) async {
    return await remoteDataSource.getCurrentShift(registerId: registerId);
  }

  @override
  Future<CashRegisterShift> openShift(double openingBalance, int userId, [int? registerId]) async {
    return await remoteDataSource.openShift(openingBalance, userId, registerId);
  }

  @override
  Future<CashRegisterShift> closeShift(int shiftId, double countedCash, {int? closerUserId}) async {
    return await remoteDataSource.closeShift(shiftId, countedCash, closerUserId: closerUserId);
  }
}
