import '../../domain/entities/cash_register_shift.dart';

class CashRegisterShiftModel extends CashRegisterShift {
  CashRegisterShiftModel({
    required super.id,
    required super.cashRegisterId,
    required super.userId,
    required super.openedAt,
    super.closedAt,
    required super.openingBalance,
    super.closingBalance,
    super.totalSales,
    super.difference,
    super.expectedBalance,
    super.actualBalance,
    super.cashSales,
    super.cardSales,
    super.transferSales,
    super.totalSurcharge,
    super.checkSales,
    super.checkCount,
    super.checkDetails,
    super.ccSales,
    super.ccSalesCount,
    required super.status,
    super.userName,
    super.cashRegisterName,
    super.closedByUserId,
    super.closedByUserName,
  });

  factory CashRegisterShiftModel.fromJson(Map<String, dynamic> json) {
    return CashRegisterShiftModel(
      id: json['id'],
      cashRegisterId: json['cash_register_id'] ?? 1,
      userId: json['user_id'] ?? 1,
      openedAt: DateTime.parse(json['opened_at']).toLocal(),
      closedAt: json['closed_at'] != null ? DateTime.parse(json['closed_at']).toLocal() : null,
      openingBalance: double.parse(json['opening_balance'].toString()),
      closingBalance: json['closing_balance'] != null ? double.parse(json['closing_balance'].toString()) : null,
      totalSales: json['total_sales'] != null ? double.parse(json['total_sales'].toString()) : null,
      difference: json['difference'] != null ? double.parse(json['difference'].toString()) : null,
      expectedBalance: json['expected_balance'] != null ? double.parse(json['expected_balance'].toString()) : null,
      actualBalance: json['actual_balance'] != null ? double.parse(json['actual_balance'].toString()) : null,
      cashSales: json['cash_sales'] != null ? double.parse(json['cash_sales'].toString()) : null,
      cardSales: json['card_sales'] != null ? double.parse(json['card_sales'].toString()) : null,
      transferSales: json['transfer_sales'] != null ? double.parse(json['transfer_sales'].toString()) : null,
      totalSurcharge: json['total_surcharge'] != null ? double.parse(json['total_surcharge'].toString()) : null,
      checkSales: json['check_sales'] != null ? double.parse(json['check_sales'].toString()) : null,
      checkCount: json['check_count'] != null ? int.tryParse(json['check_count'].toString()) : null,
      checkDetails: json['check_details'] != null
          ? List<Map<String, dynamic>>.from(
              (json['check_details'] is String
                  ? (json['check_details'] as String).isNotEmpty ? [] : []
                  : json['check_details'] as List)
                  .map((e) => Map<String, dynamic>.from(e)))
          : null,
      ccSales: json['cc_sales'] != null ? double.parse(json['cc_sales'].toString()) : null,
      ccSalesCount: json['cc_sales_count'] != null ? int.tryParse(json['cc_sales_count'].toString()) : null,
      status: json['status'],
      userName: json['user'] != null ? json['user']['name'] : null,
      cashRegisterName: json['cash_register'] != null ? json['cash_register']['name'] : null,
      closedByUserId: json['closed_by_user_id'],
      closedByUserName: json['closed_by_user'] != null ? json['closed_by_user']['name'] : null,
    );
  }
}
