class OfferModel {
  final int id;
  final String name;
  final String? description;
  final String type; // 'percentage' o 'fixed_price'
  final double? discountPercentage;
  final double? discountAmount;
  final String periodType; // 'daily', 'weekly', 'monthly', 'custom'
  final List<String>? daysOfWeek;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final List<Map<String, dynamic>> products;

  OfferModel({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    this.discountPercentage,
    this.discountAmount,
    required this.periodType,
    this.daysOfWeek,
    this.startDate,
    this.endDate,
    required this.isActive,
    this.products = const [],
  });

  factory OfferModel.fromJson(Map<String, dynamic> json) {
    return OfferModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Oferta',
      description: json['description'] as String?,
      type: json['type'] as String? ?? 'percentage',
      discountPercentage: json['discount_percentage'] != null
          ? double.tryParse(json['discount_percentage'].toString())
          : null,
      discountAmount: json['discount_amount'] != null
          ? double.tryParse(json['discount_amount'].toString())
          : null,
      periodType: json['period_type'] as String? ?? 'daily',
      daysOfWeek: json['days_of_week'] != null
          ? List<String>.from(json['days_of_week'])
          : null,
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'].toString())
          : null,
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'].toString())
          : null,
      isActive: json['is_active'] == true || json['is_active'] == 1,
      products: json['products'] != null
          ? List<Map<String, dynamic>>.from(json['products'])
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type,
      'discount_percentage': discountPercentage,
      'discount_amount': discountAmount,
      'period_type': periodType,
      'days_of_week': daysOfWeek,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'is_active': isActive,
      'products': products,
    };
  }

  /// Calcula el precio con descuento para un producto dado según esta oferta
  double calculateDiscountedPrice(double basePrice, {int? productId}) {
    if (type == 'percentage' && discountPercentage != null && discountPercentage! > 0) {
      final discount = basePrice * (discountPercentage! / 100.0);
      return (basePrice - discount).clamp(0.0, double.infinity);
    }
    if (type == 'fixed_price') {
      if (productId != null) {
        final match = products.firstWhere(
          (p) => p['id'] == productId,
          orElse: () => {},
        );
        final special = double.tryParse(match['pivot']?['special_price']?.toString() ?? '');
        if (special != null && special > 0) {
          return special;
        }
      }
      if (discountAmount != null && discountAmount! > 0) {
        return (basePrice - discountAmount!).clamp(0.0, double.infinity);
      }
    }
    return basePrice;
  }

  /// Label legible del período
  String get periodLabel {
    switch (periodType) {
      case 'daily':
        return '☀️ Diaria (Hoy)';
      case 'weekly':
        return '📅 Semanal (7 días)';
      case 'monthly':
        return '📆 Mensual (30 días)';
      default:
        return '⏱️ Temporal';
    }
  }
}
