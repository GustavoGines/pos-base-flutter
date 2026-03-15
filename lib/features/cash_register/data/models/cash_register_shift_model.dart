import '../../domain/entities/cash_register_shift.dart';

class CashRegisterShiftModel extends CashRegisterShift {
  CashRegisterShiftModel({
    required int id,
    required DateTime openedAt,
    DateTime? closedAt,
    required double openingBalance,
    double? closingBalance,
    required String status,
  }) : super(
          id: id,
          openedAt: openedAt,
          closedAt: closedAt,
          openingBalance: openingBalance,
          closingBalance: closingBalance,
          status: status,
        );

  factory CashRegisterShiftModel.fromJson(Map<String, dynamic> json) {
    return CashRegisterShiftModel(
      id: json['id'],
      openedAt: DateTime.parse(json['opened_at']),
      closedAt: json['closed_at'] != null ? DateTime.parse(json['closed_at']) : null,
      openingBalance: double.parse(json['opening_balance'].toString()),
      closingBalance: json['closing_balance'] != null ? double.parse(json['closing_balance'].toString()) : null,
      status: json['status'],
    );
  }
}
