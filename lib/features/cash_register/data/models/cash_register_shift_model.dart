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
    super.totalExpenses,
    super.totalWithdrawals,
    super.totalDeposits,
    required super.status,
    super.userName,
    super.cashRegisterName,
    super.closedByUserId,
    super.closedByUserName,
  });

  static double? _parseDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  static int? _parseInt(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  factory CashRegisterShiftModel.fromJson(Map<String, dynamic> json) {
    try {
      return CashRegisterShiftModel(
        id: json['id'],
        cashRegisterId: json['cash_register_id'] ?? 1,
        userId: json['user_id'] ?? 1,
        openedAt: DateTime.parse(json['opened_at']).toLocal(),
        closedAt: json['closed_at'] != null ? DateTime.parse(json['closed_at']).toLocal() : null,
        openingBalance: _parseDouble(json['opening_balance']) ?? 0.0,
        closingBalance: _parseDouble(json['closing_balance']),
        totalSales: _parseDouble(json['total_sales']),
        difference: _parseDouble(json['difference']),
        expectedBalance: _parseDouble(json['expected_balance']),
        actualBalance: _parseDouble(json['actual_balance']),
        cashSales: _parseDouble(json['cash_sales']),
        cardSales: _parseDouble(json['card_sales']),
        transferSales: _parseDouble(json['transfer_sales']),
        totalSurcharge: _parseDouble(json['total_surcharge']),
        checkSales: _parseDouble(json['check_sales']),
        checkCount: _parseInt(json['check_count']),
        checkDetails: json['check_details'] != null
            ? List<Map<String, dynamic>>.from(
                (json['check_details'] is String
                    ? (json['check_details'] as String).isNotEmpty ? [] : []
                    : json['check_details'] as List)
                    .map((e) => Map<String, dynamic>.from(e)))
            : null,
        ccSales: _parseDouble(json['cc_sales']),
        ccSalesCount: _parseInt(json['cc_sales_count']),
        totalExpenses: _parseDouble(json['total_expenses']),
        totalWithdrawals: _parseDouble(json['total_withdrawals']),
        totalDeposits: _parseDouble(json['total_deposits']),
        status: json['status'],
        userName: json['user'] != null ? json['user']['name'] : null,
        cashRegisterName: json['cash_register'] != null ? json['cash_register']['name'] : null,
        closedByUserId: json['closed_by_user_id'],
        closedByUserName: json['closed_by_user'] != null ? json['closed_by_user']['name'] : null,
      );
    } catch (e, stack) {
      debugPrint('Error parsing CashRegisterShiftModel: $e\n$stack');
      rethrow;
    }
  }
}
