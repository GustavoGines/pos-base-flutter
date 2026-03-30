class PaymentMethod {
  final int id;
  final String name;
  final String code;
  final String surchargeType;
  final double surchargeValue;
  final bool isCash;
  final bool isActive;
  final int sortOrder;

  PaymentMethod({
    required this.id,
    required this.name,
    required this.code,
    required this.surchargeType,
    required this.surchargeValue,
    required this.isCash,
    required this.isActive,
    required this.sortOrder,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'],
      name: json['name'],
      code: json['code'],
      surchargeType: json['surcharge_type'] ?? 'none',
      surchargeValue: double.tryParse(json['surcharge_value']?.toString() ?? '0') ?? 0.0,
      isCash: json['is_cash'] == 1 || json['is_cash'] == true,
      isActive: json['is_active'] == 1 || json['is_active'] == true,
      sortOrder: json['sort_order'] ?? 0,
    );
  }

  double calculateSurcharge(double baseAmount) {
    if (surchargeType == 'percent') {
      return (baseAmount * surchargeValue) / 100.0;
    } else if (surchargeType == 'fixed') {
      return surchargeValue;
    }
    return 0.0;
  }
}
