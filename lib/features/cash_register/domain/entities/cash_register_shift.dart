class CashRegisterShift {
  final int id;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingBalance;
  final double? closingBalance;
  final String status;

  CashRegisterShift({
    required this.id,
    required this.openedAt,
    this.closedAt,
    required this.openingBalance,
    this.closingBalance,
    required this.status,
  });

  bool get isOpen => status == 'open';
}
