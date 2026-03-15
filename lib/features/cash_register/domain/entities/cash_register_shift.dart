class CashRegisterShift {
  final int id;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingBalance;
  final double? closingBalance;
  final double? totalSales;
  final double? difference;
  final String status;
  final dynamic user;

  CashRegisterShift({
    required this.id,
    required this.openedAt,
    this.closedAt,
    required this.openingBalance,
    this.closingBalance,
    this.totalSales,
    this.difference,
    required this.status,
    this.user,
  });

  bool get isOpen => status == 'open';
}
