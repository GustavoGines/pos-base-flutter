import '../entities/cash_register_shift.dart';

abstract class CashRegisterRepository {
  Future<CashRegisterShift?> getCurrentShift();
  Future<CashRegisterShift> openShift(double openingBalance);
  Future<CashRegisterShift> closeShift(double closingBalance);
}
