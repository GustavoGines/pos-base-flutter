class CashRegisterShift {
  final int id;
  final int cashRegisterId;
  final int userId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingBalance;
  final double? closingBalance;
  final double? totalSales;
  final double? difference;
  final double? expectedBalance;
  final double? actualBalance;
  final double? cashSales;
  final double? cardSales;
  final double? transferSales;
  final double? totalSurcharge;
  final String status;

  // Relaciones
  final String? userName;
  final String? cashRegisterName;
  final int? closedByUserId;
  final String? closedByUserName;

  CashRegisterShift({
    required this.id,
    required this.cashRegisterId,
    required this.userId,
    required this.openedAt,
    this.closedAt,
    required this.openingBalance,
    this.closingBalance,
    this.totalSales,
    required this.status,
    this.expectedBalance,
    this.actualBalance,
    this.difference,
    this.cashSales,
    this.cardSales,
    this.transferSales,
    this.totalSurcharge,
    this.userName,
    this.cashRegisterName,
    this.closedByUserId,
    this.closedByUserName,
  });

  bool get isOpen => status == 'open';
}
