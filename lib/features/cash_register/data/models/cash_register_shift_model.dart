import '../../domain/entities/cash_register_shift.dart';

class CashRegisterShiftModel extends CashRegisterShift {
  CashRegisterShiftModel({
    required int id,
    required DateTime openedAt,
    DateTime? closedAt,
    required double openingBalance,
    double? closingBalance,
    double? totalSales,
    double? difference,
    required String status,
    dynamic user,
  }) : super(
          id: id,
          openedAt: openedAt,
          closedAt: closedAt,
          openingBalance: openingBalance,
          closingBalance: closingBalance,
          totalSales: totalSales,
          difference: difference,
          status: status,
          user: user,
        );

  factory CashRegisterShiftModel.fromJson(Map<String, dynamic> json) {
    return CashRegisterShiftModel(
      id: json['id'],
      openedAt: DateTime.parse(json['opened_at']),
      closedAt: json['closed_at'] != null ? DateTime.parse(json['closed_at']) : null,
      openingBalance: double.parse(json['opening_balance'].toString()),
      closingBalance: json['closing_balance'] != null ? double.parse(json['closing_balance'].toString()) : null,
      totalSales: json['total_sales'] != null ? double.parse(json['total_sales'].toString()) : null,
      difference: json['difference'] != null ? double.parse(json['difference'].toString()) : null,
      status: json['status'],
      user: json['user'],
    );
  }
}
