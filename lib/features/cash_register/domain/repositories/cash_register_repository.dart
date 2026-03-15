import '../entities/cash_register_shift.dart';

abstract class CashRegisterRepository {
  Future<List<CashRegisterShift>> getAllShifts();
  Future<CashRegisterShift?> getCurrentShift();
  Future<CashRegisterShift> openShift(double openingBalance, int userId);
  Future<CashRegisterShift> closeShift(double countedCash);
}
