enum OfferStatus { active, scheduled, expired, paused }

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

  OfferStatus get status {
    if (!isActive) return OfferStatus.paused;
    final now = DateTime.now();
    if (startDate != null && startDate!.isAfter(now)) return OfferStatus.scheduled;
    if (endDate != null && endDate!.isBefore(now)) return OfferStatus.expired;
    return OfferStatus.active;
  }

  bool get isCurrentlyActive => status == OfferStatus.active;
  bool get isExpired => status == OfferStatus.expired;
  bool get isPaused => status == OfferStatus.paused;
  bool get isScheduled => status == OfferStatus.scheduled;

  String get statusLabel {
    switch (status) {
      case OfferStatus.active:
        return '🟢 Activa';
      case OfferStatus.scheduled:
        return '🟡 Programada';
      case OfferStatus.expired:
        return '🔴 Vencida';
      case OfferStatus.paused:
        return '⏸️ Pausada';
    }
  }

  /// Verifica si algún producto tiene margen en riesgo (precio con oferta < precio costo)
  List<Map<String, dynamic>> get marginWarnings {
    final warnings = <Map<String, dynamic>>[];
    for (final p in products) {
      final sellingPrice = double.tryParse(p['selling_price']?.toString() ?? '0') ?? 0.0;
      final costPrice = double.tryParse(p['cost_price']?.toString() ?? '0') ?? 0.0;
      final id = (p['id'] as num?)?.toInt();
      if (costPrice > 0 && sellingPrice > 0) {
        final discounted = calculateDiscountedPrice(sellingPrice, productId: id);
        if (discounted < costPrice) {
          warnings.add({
            'product_name': p['name'] ?? 'Producto',
            'cost_price': costPrice,
            'discounted_price': discounted,
          });
        }
      }
    }
    return warnings;
  }

  bool get hasMarginWarning => marginWarnings.isNotEmpty;

  /// Calcula el precio con descuento para un producto dado según esta oferta
  double calculateDiscountedPrice(double basePrice, {int? productId}) {
    if (type == 'percentage' && discountPercentage != null && discountPercentage! > 0) {
      final discount = basePrice * (discountPercentage! / 100.0);
      final raw = (basePrice - discount).clamp(0.0, double.infinity);
      return (raw * 100).roundToDouble() / 100.0;
    }
    if (type == 'fixed_discount' && discountAmount != null && discountAmount! > 0) {
      final raw = (basePrice - discountAmount!).clamp(0.0, double.infinity);
      return (raw * 100).roundToDouble() / 100.0;
    }
    if (type == 'fixed_price') {
      if (productId != null) {
        final match = products.firstWhere(
          (p) => p['id'] == productId,
          orElse: () => {},
        );
        final special = double.tryParse(match['pivot']?['special_price']?.toString() ?? '');
        if (special != null && special > 0) {
          return (special * 100).roundToDouble() / 100.0;
        }
      }
      if (discountAmount != null && discountAmount! > 0) {
        final raw = (basePrice - discountAmount!).clamp(0.0, double.infinity);
        return (raw * 100).roundToDouble() / 100.0;
      }
    }
    return (basePrice * 100).roundToDouble() / 100.0;
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
