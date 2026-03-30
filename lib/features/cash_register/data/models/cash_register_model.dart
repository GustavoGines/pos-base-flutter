import '../../domain/entities/cash_register.dart';

class CashRegisterModel extends CashRegister {
  CashRegisterModel({
    required int id,
    required String name,
    required bool isActive,
  }) : super(id: id, name: name, isActive: isActive);

  factory CashRegisterModel.fromJson(Map<String, dynamic> json) {
    return CashRegisterModel(
      id: json['id'],
      name: json['name'],
      // SQLite/MySQL might return 1/0 for boolean or true/false depending on the driver
      isActive: json['is_active'] == 1 || json['is_active'] == true,
    );
  }
}
