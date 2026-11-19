class ProductBatchModel {
  final int id;
  final int productId;
  final String batchCode;
  final String sourceType;
  final int? supplierInvoiceId;
  final int? supplierId;
  final String? supplierName;
  final int? productionOrderId;
  final String? manufacturedAt;
  final String? expirationDate;
  final int? daysUntilExpiry;
  final bool isExpired;
  final double initialQuantity;
  final double remainingQuantity;
  final double reservedQuantity;
  final double availableToSell;
  final double? unitCost;
  final String status;
  final String? notes;
  final String? createdAt;

  const ProductBatchModel({
    required this.id,
    required this.productId,
    required this.batchCode,
    required this.sourceType,
    this.supplierInvoiceId,
    this.supplierId,
    this.supplierName,
    this.productionOrderId,
    this.manufacturedAt,
    this.expirationDate,
    this.daysUntilExpiry,
    required this.isExpired,
    required this.initialQuantity,
    required this.remainingQuantity,
    required this.reservedQuantity,
    required this.availableToSell,
    this.unitCost,
    required this.status,
    this.notes,
    this.createdAt,
  });

  bool get isDeficit => status == 'deficit';
  bool get isActive => status == 'active';
  bool get isWrittenOff => status == 'written_off';
  bool get isExhausted => status == 'exhausted';

  factory ProductBatchModel.fromJson(Map<String, dynamic> json) {
    final rem = double.tryParse(json['remaining_quantity']?.toString() ?? '0') ?? 0.0;
    final res = double.tryParse(json['reserved_quantity']?.toString() ?? '0') ?? 0.0;
    final availRaw = json['available_to_sell'];
    final avail = availRaw != null
        ? (double.tryParse(availRaw.toString()) ?? (rem - res))
        : (rem - res);

    return ProductBatchModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      batchCode: json['batch_code']?.toString() ?? 'SIN-LOTE',
      sourceType: json['source_type']?.toString() ?? 'adjustment',
      supplierInvoiceId: (json['supplier_invoice_id'] as num?)?.toInt(),
      supplierId: (json['supplier_id'] as num?)?.toInt(),
      supplierName: json['supplier_name']?.toString(),
      productionOrderId: (json['production_order_id'] as num?)?.toInt(),
      manufacturedAt: json['manufactured_at']?.toString().split('T').first,
      expirationDate: json['expiration_date'] != null &&
              json['expiration_date'].toString() != 'null' &&
              json['expiration_date'].toString().trim().isNotEmpty
          ? json['expiration_date'].toString().split('T').first
          : null,
      daysUntilExpiry: (json['days_until_expiry'] as num?)?.toInt(),
      isExpired: json['is_expired'] == true || json['is_expired'] == 1,
      initialQuantity: double.tryParse(json['initial_quantity']?.toString() ?? '0') ?? 0.0,
      remainingQuantity: rem,
      reservedQuantity: res,
      availableToSell: avail,
      unitCost: json['unit_cost'] != null
          ? double.tryParse(json['unit_cost'].toString())
          : null,
      status: json['status']?.toString() ?? 'active',
      notes: json['notes']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

class ProductBatchesResponse {
  final int productId;
  final String productName;
  final bool trackBatches;
  final String lotDeductionPolicy;
  final bool allowSellExpired;
  final double stock;
  final String? expirationDate;
  final List<ProductBatchModel> batches;

  const ProductBatchesResponse({
    required this.productId,
    required this.productName,
    required this.trackBatches,
    required this.lotDeductionPolicy,
    required this.allowSellExpired,
    required this.stock,
    this.expirationDate,
    required this.batches,
  });

  factory ProductBatchesResponse.fromJson(Map<String, dynamic> json) {
    final rawBatches = (json['batches'] as List?) ?? const [];
    return ProductBatchesResponse(
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      productName: json['product_name']?.toString() ?? '',
      trackBatches: json['track_batches'] == true || json['track_batches'] == 1,
      lotDeductionPolicy: json['lot_deduction_policy']?.toString() ?? 'fefo',
      allowSellExpired: json['allow_sell_expired'] == true || json['allow_sell_expired'] == 1,
      stock: double.tryParse(json['stock']?.toString() ?? '0') ?? 0.0,
      expirationDate: json['expiration_date']?.toString().split('T').first,
      batches: rawBatches
          .whereType<Map>()
          .map((e) => ProductBatchModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
