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
  final Map<String, dynamic>? cashShift;

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
    this.cashShift,
  });

  int? get cashRegisterId {
    final raw = cashShift?['cash_register_id'] ?? cashShift?['cash_register']?['id'];
    if (raw is int) return raw;
    if (raw != null) return int.tryParse(raw.toString());
    return null;
  }

  String? get cashRegisterName {
    final reg = cashShift?['cash_register'];
    if (reg is Map) {
      final name = reg['name']?.toString();
      if (name != null && name.trim().isNotEmpty) return name;
    }
    return null;
  }

  factory CashMovementModel.fromJson(Map<String, dynamic> json) {
    return CashMovementModel(
      id: json['id'] is int ? json['id'] : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
      cashShiftId: json['cash_shift_id'] is int ? json['cash_shift_id'] : (int.tryParse(json['cash_shift_id']?.toString() ?? '0') ?? 0),
      userId: json['user_id'] is int ? json['user_id'] : (int.tryParse(json['user_id']?.toString() ?? '0') ?? 0),
      authorizedBy: json['authorized_by'] != null ? (json['authorized_by'] is int ? json['authorized_by'] : int.tryParse(json['authorized_by'].toString())) : null,
      supplierId: json['supplier_id'] != null ? (json['supplier_id'] is int ? json['supplier_id'] : int.tryParse(json['supplier_id'].toString())) : null,
      checkId: json['check_id'] != null ? (json['check_id'] is int ? json['check_id'] : int.tryParse(json['check_id'].toString())) : null,
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      type: json['type']?.toString() ?? 'expense',
      category: json['category']?.toString() ?? 'Sin categoría',
      description: json['description'],
      receiptNumber: json['receipt_number'],
      receiptFileUrl: json['receipt_file_url'],
      createdAt: json['created_at'] != null ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()) : DateTime.now(),
      user: json['user'],
      authorizer: json['authorizer'],
      supplier: json['supplier'],
      check: json['check'],
      cashShift: json['cash_shift'] is Map<String, dynamic>
          ? json['cash_shift'] as Map<String, dynamic>
          : (json['cash_shift'] is Map ? Map<String, dynamic>.from(json['cash_shift'] as Map) : null),
    );
  }
}
