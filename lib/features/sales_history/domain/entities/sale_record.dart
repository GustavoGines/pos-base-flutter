/// Un pago individual dentro de una venta con split tender.
class SalePayment {
  final int id;
  final int paymentMethodId;
  final String methodName;  // nombre legible (ej: "Tarjeta de Débito")
  final String methodCode;  // código técnico (ej: "debito", "efectivo", "transferencia"…)
  final bool isCash;
  final double baseAmount;
  final double surchargeAmount;
  final double totalAmount;

  const SalePayment({
    required this.id,
    required this.paymentMethodId,
    required this.methodName,
    required this.methodCode,
    required this.isCash,
    required this.baseAmount,
    required this.surchargeAmount,
    required this.totalAmount,
  });

  factory SalePayment.fromJson(Map<String, dynamic> json) {
    final pm = json['payment_method'] as Map<String, dynamic>?;
    return SalePayment(
      id: json['id'] as int? ?? 0,
      paymentMethodId: json['payment_method_id'] as int? ?? 0,
      methodName: pm?['name'] as String? ?? 'Desconocido',
      methodCode: pm?['code'] as String? ?? '',
      isCash: pm?['is_cash'] == true || pm?['is_cash'] == 1,
      baseAmount: double.parse((json['base_amount'] ?? '0').toString()),
      surchargeAmount: double.parse((json['surcharge_amount'] ?? '0').toString()),
      totalAmount: double.parse((json['total_amount'] ?? '0').toString()),
    );
  }
}

/// Modelo de ítem de venta enriquecido para el historial.
class SaleItemRecord {
  final int id;
  final int? productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double subtotal;
  final bool isSoldByWeight;

  const SaleItemRecord({
    required this.id,
    this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.isSoldByWeight = false,
  });

  factory SaleItemRecord.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    return SaleItemRecord(
      id: json['id'] as int,
      productId: json['product_id'] as int?,
      productName: json['product_name'] as String,
      quantity: double.parse(json['quantity'].toString()),
      unitPrice: double.parse(json['unit_price'].toString()),
      subtotal: double.parse(json['subtotal'].toString()),
      isSoldByWeight: product?['is_sold_by_weight'] == true || product?['is_sold_by_weight'] == 1,
    );
  }
}

/// Modelo de venta enriquecido para el historial (no reemplaza la entidad Sale del POS).
class SaleRecord {
  final int id;
  final double total;
  final double totalSurcharge;
  final String status;  // 'active' | 'voided' | 'pending' | 'completed'
  final DateTime createdAt;
  final List<SaleItemRecord> items;
  final List<SalePayment> payments;
  final int? userId;
  final String? userName;
  final int? cashierId;
  final String? cashierName;

  const SaleRecord({
    required this.id,
    required this.total,
    this.totalSurcharge = 0.0,
    required this.status,
    required this.createdAt,
    required this.items,
    required this.payments,
    this.userId,
    this.userName,
    this.cashierId,
    this.cashierName,
  });

  bool get isVoided => status == 'voided';
  bool get isPending => status == 'pending';

  /// Sumatoria real de recargos de todos los pagos (calculado desde sale_payments).
  double get surchargeTotal =>
      payments.fold(0.0, (sum, p) => sum + p.surchargeAmount);

  /// Ingreso NETO del negocio = total de items vendidos (sin recargo bancario).
  double get netTotal => total;

  /// Total real cobrado al cliente = base + recargo bancario.
  double get grandTotal => total + surchargeTotal;

  /// Etiqueta resumida de métodos de pago para mostrar en la lista.
  /// Ej: "Efectivo + Tarjeta" o "Transferencia"
  String get paymentMethodLabel {
    if (payments.isEmpty) return 'Sin dato';
    final names = payments.map((p) => p.methodName).toSet().toList();
    if (names.length == 1) return names.first;
    return names.join(' + ');
  }

  /// Código del primer método de pago (retrocompatibilidad).
  String get primaryPaymentCode =>
      payments.isNotEmpty ? payments.first.methodCode : '';

  factory SaleRecord.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List<dynamic>? ?? [])
        .map((i) => SaleItemRecord.fromJson(i as Map<String, dynamic>))
        .toList();

    final paymentsList = (json['payments'] as List<dynamic>? ?? [])
        .map((p) => SalePayment.fromJson(p as Map<String, dynamic>))
        .toList();

    return SaleRecord(
      id: json['id'] as int,
      total: double.parse(json['total'].toString()),
      totalSurcharge: double.parse((json['total_surcharge'] ?? '0').toString()),
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      items: itemsList,
      payments: paymentsList,
      userId: json['user_id'] as int?,
      userName: json['user']?['name'] as String?,
      cashierId: json['cashier_id'] as int?,
      cashierName: json['cashier']?['name'] as String?,
    );
  }
}
