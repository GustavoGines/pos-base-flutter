class CustomerTransaction {
  final int id;
  final int customerId;
  final int userId;
  final int? saleId;
  final String type; // 'charge' or 'payment'
  final double amount;
  final double balanceAfter;
  final String? description;
  final String? paymentMethod; // 'efectivo', 'transferencia', 'cheque', etc.
  final DateTime createdAt;

  CustomerTransaction({
    required this.id,
    required this.customerId,
    required this.userId,
    this.saleId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.paymentMethod,
    required this.createdAt,
  });

  factory CustomerTransaction.fromJson(Map<String, dynamic> json) {
    return CustomerTransaction(
      id: json['id'],
      customerId: json['customer_id'],
      userId: json['user_id'],
      saleId: json['sale_id'],
      type: json['type'],
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      balanceAfter: double.tryParse(json['balance_after'].toString()) ?? 0.0,
      description: json['description'],
      paymentMethod: json['payment_method'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class Customer {
  final int id;
  final String name;
  final String? phone;
  final String documentNumber;
  final double creditLimit;
  final double balance;
  final bool isActive;
  final String? defaultPriceTier; // 'base', 'wholesale', 'card'
  final String? deliveryAddress;
  final bool isInternalAccount;
  final List<CustomerTransaction> transactions;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    required this.documentNumber,
    required this.creditLimit,
    required this.balance,
    required this.isActive,
    this.defaultPriceTier,
    this.deliveryAddress,
    this.isInternalAccount = false,
    this.transactions = const [],
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'],
      name: json['name'],
      phone: json['phone'],
      documentNumber: json['document_number'] ?? '',
      creditLimit: double.tryParse(json['credit_limit']?.toString() ?? '0') ?? 0.0,
      balance: double.tryParse(json['balance']?.toString() ?? '0') ?? 0.0,
      isActive: json['is_active'] == 1 || json['is_active'] == true,
      defaultPriceTier: json['default_price_tier'],
      deliveryAddress: json['delivery_address'],
      isInternalAccount: json['is_internal_account'] == 1 || json['is_internal_account'] == true,
      transactions: json['transactions'] != null 
          ? (json['transactions'] as List).map((t) => CustomerTransaction.fromJson(t)).toList()
          : [],
    );
  }
}
