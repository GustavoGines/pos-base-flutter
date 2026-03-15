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
  final String paymentMethod;
  final String status;  // 'active' | 'voided'
  final DateTime createdAt;
  final List<SaleItemRecord> items;
  final int? userId;
  final String? userName;

  const SaleRecord({
    required this.id,
    required this.total,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    required this.items,
    this.userId,
    this.userName,
  });

  bool get isVoided => status == 'voided';

  factory SaleRecord.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List<dynamic>? ?? [])
        .map((i) => SaleItemRecord.fromJson(i as Map<String, dynamic>))
        .toList();
    return SaleRecord(
      id: json['id'] as int,
      total: double.parse(json['total'].toString()),
      paymentMethod: json['payment_method'] as String,
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.parse(json['created_at'] as String),
      items: itemsList,
      userId: json['user_id'] as int?,
      userName: json['user']?['name'] as String?,
    );
  }
}
