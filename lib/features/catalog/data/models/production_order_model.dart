class ProductionOrderConsumptionModel {
  final int id;
  final int ingredientProductId;
  final String ingredientName;
  final String unitType;
  final int? batchId;
  final String? batchCode;
  final String? batchExpirationDate;
  final double quantityUsed;
  final double unitCost;
  final double subtotalCost;

  const ProductionOrderConsumptionModel({
    required this.id,
    required this.ingredientProductId,
    required this.ingredientName,
    required this.unitType,
    this.batchId,
    this.batchCode,
    this.batchExpirationDate,
    required this.quantityUsed,
    required this.unitCost,
    required this.subtotalCost,
  });

  factory ProductionOrderConsumptionModel.fromJson(Map<String, dynamic> json) {
    final ingredient = json['ingredient'] is Map
        ? Map<String, dynamic>.from(json['ingredient'] as Map)
        : null;
    final batch = json['batch'] is Map
        ? Map<String, dynamic>.from(json['batch'] as Map)
        : null;

    return ProductionOrderConsumptionModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ingredientProductId: (json['ingredient_product_id'] as num?)?.toInt() ??
          (ingredient?['id'] as num?)?.toInt() ??
          0,
      ingredientName: ingredient?['name']?.toString() ?? 'Insumo',
      unitType: ingredient?['unit_type']?.toString() ?? 'un',
      batchId: (json['batch_id'] as num?)?.toInt() ??
          (batch?['id'] as num?)?.toInt(),
      batchCode: batch?['batch_code']?.toString(),
      batchExpirationDate: batch?['expiration_date']?.toString().split('T').first,
      quantityUsed: double.tryParse(json['quantity_used']?.toString() ?? '0') ?? 0.0,
      unitCost: double.tryParse(json['unit_cost']?.toString() ?? '0') ?? 0.0,
      subtotalCost: double.tryParse(json['subtotal_cost']?.toString() ?? '0') ?? 0.0,
    );
  }
}

class ProductionOrderModel {
  final int id;
  final String orderNumber;
  final int productId;
  final String productName;
  final String unitType;
  final int? vencimientoDias;
  final double quantityProduced;
  final int? producedBatchId;
  final String? producedBatchCode;
  final String? producedBatchExpiration;
  final double? producedBatchRemaining;
  final String? producedBatchStatus;
  final double totalCost;
  final double unitCost;
  final String status;
  final String? notes;
  final String? userName;
  final String? manufacturedAt;
  final String? createdAt;
  final List<ProductionOrderConsumptionModel> consumptions;

  const ProductionOrderModel({
    required this.id,
    required this.orderNumber,
    required this.productId,
    required this.productName,
    required this.unitType,
    this.vencimientoDias,
    required this.quantityProduced,
    this.producedBatchId,
    this.producedBatchCode,
    this.producedBatchExpiration,
    this.producedBatchRemaining,
    this.producedBatchStatus,
    required this.totalCost,
    required this.unitCost,
    required this.status,
    this.notes,
    this.userName,
    this.manufacturedAt,
    this.createdAt,
    required this.consumptions,
  });

  bool get isVoided => status == 'voided';

  factory ProductionOrderModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] is Map
        ? Map<String, dynamic>.from(json['product'] as Map)
        : null;
    final producedBatch = json['produced_batch'] is Map
        ? Map<String, dynamic>.from(json['produced_batch'] as Map)
        : null;
    final user = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : null;
    final rawConsumptions = (json['consumptions'] as List?) ?? const [];

    return ProductionOrderModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      orderNumber: json['order_number']?.toString() ?? 'OP',
      productId: (json['product_id'] as num?)?.toInt() ??
          (product?['id'] as num?)?.toInt() ??
          0,
      productName: product?['name']?.toString() ?? 'Producto',
      unitType: product?['unit_type']?.toString() ?? 'un',
      vencimientoDias: (product?['vencimiento_dias'] as num?)?.toInt(),
      quantityProduced: double.tryParse(json['quantity_produced']?.toString() ?? '0') ?? 0.0,
      producedBatchId: (json['produced_batch_id'] as num?)?.toInt() ??
          (producedBatch?['id'] as num?)?.toInt(),
      producedBatchCode: producedBatch?['batch_code']?.toString(),
      producedBatchExpiration: producedBatch?['expiration_date']?.toString().split('T').first,
      producedBatchRemaining: producedBatch?['remaining_quantity'] != null
          ? double.tryParse(producedBatch!['remaining_quantity'].toString())
          : null,
      producedBatchStatus: producedBatch?['status']?.toString(),
      totalCost: double.tryParse(json['total_cost']?.toString() ?? '0') ?? 0.0,
      unitCost: double.tryParse(json['unit_cost']?.toString() ?? '0') ?? 0.0,
      status: json['status']?.toString() ?? 'completed',
      notes: json['notes']?.toString(),
      userName: user?['name']?.toString(),
      manufacturedAt: json['manufactured_at']?.toString().split('T').first,
      createdAt: json['created_at']?.toString(),
      consumptions: rawConsumptions
          .whereType<Map>()
          .map((e) => ProductionOrderConsumptionModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
