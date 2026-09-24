class CashMovementModel {
  final int id;
  final int cashShiftId;
  final int userId;
  final int? authorizedBy;
  final int? supplierId;
  final int? checkId;
  final double amount;
  final String paymentMethod;
  final String type;
  final String category;
  final String? description;
  final String? receiptNumber;
  final String? receiptFileUrl;
  final DateTime createdAt;
  
  // Relaciones
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? authorizer;
  final Map<String, dynamic>? supplier;
  final Map<String, dynamic>? check;

  CashMovementModel({
    required this.id,
    required this.cashShiftId,
    required this.userId,
    this.authorizedBy,
    this.supplierId,
    this.checkId,
    required this.amount,
    required this.paymentMethod,
    required this.type,
    required this.category,
    this.description,
    this.receiptNumber,
    this.receiptFileUrl,
    required this.createdAt,
    this.user,
    this.authorizer,
    this.supplier,
    this.check,
  });

  factory CashMovementModel.fromJson(Map<String, dynamic> json) {
    return CashMovementModel(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      cashShiftId: json['cash_shift_id'] is int ? json['cash_shift_id'] : int.parse(json['cash_shift_id'].toString()),
      userId: json['user_id'] is int ? json['user_id'] : int.parse(json['user_id'].toString()),
      authorizedBy: json['authorized_by'] != null ? (json['authorized_by'] is int ? json['authorized_by'] : int.parse(json['authorized_by'].toString())) : null,
      supplierId: json['supplier_id'] != null ? (json['supplier_id'] is int ? json['supplier_id'] : int.parse(json['supplier_id'].toString())) : null,
      checkId: json['check_id'] != null ? (json['check_id'] is int ? json['check_id'] : int.parse(json['check_id'].toString())) : null,
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      paymentMethod: json['payment_method'],
      type: json['type'],
      category: json['category'] ?? 'Sin categoría',
      description: json['description'],
      receiptNumber: json['receipt_number'],
      receiptFileUrl: json['receipt_file_url'],
      createdAt: DateTime.parse(json['created_at']),
      user: json['user'],
      authorizer: json['authorizer'],
      supplier: json['supplier'],
      check: json['check'],
    );
  }
}
