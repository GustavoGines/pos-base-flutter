import '../entities/cash_register_shift.dart';
import '../entities/cash_register.dart';

abstract class CashRegisterRepository {
  Future<List<CashRegister>> getRegisters();
  Future<List<CashRegisterShift>> getAllShifts();
  Future<CashRegisterShift?> getCurrentShift({int? registerId});
  Future<CashRegisterShift> openShift(double openingBalance, int userId, [int? registerId]);
  Future<CashRegisterShift> closeShift(int shiftId, double countedCash, {int? closerUserId});
}
