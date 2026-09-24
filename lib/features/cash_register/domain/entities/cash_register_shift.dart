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
  final double? checkSales;
  final int? checkCount;
  final List<Map<String, dynamic>>? checkDetails;
  final double? ccSales;
  final int? ccSalesCount;
  final String status;
  
  // Egresos e Ingresos Extra
  final double? totalExpenses;
  final double? totalWithdrawals;
  final double? totalDeposits;
  final double? totalSupplierPayments;
  final double? totalRefunds;

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
    this.checkSales,
    this.checkCount,
    this.checkDetails,
    this.ccSales,
    this.ccSalesCount,
    this.totalExpenses,
    this.totalWithdrawals,
    this.totalDeposits,
    this.totalSupplierPayments,
    this.totalRefunds,
    this.userName,
    this.cashRegisterName,
    this.closedByUserId,
    this.closedByUserName,
  });

  bool get isOpen => status == 'open';
}

