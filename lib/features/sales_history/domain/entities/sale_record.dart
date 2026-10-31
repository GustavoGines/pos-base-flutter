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
  final String internalCode;
  final double quantity;
  final double unitPrice;
  final double regularPrice;
  final double subtotal;
  final double ivaRate;
  final bool isSoldByWeight;
  final String? discountLabel;

  const SaleItemRecord({
    required this.id,
    this.productId,
    required this.productName,
    this.internalCode = '',
    required this.quantity,
    required this.unitPrice,
    double? regularPrice,
    required this.subtotal,
    this.ivaRate = 21.0,
    this.isSoldByWeight = false,
    this.discountLabel,
  }) : regularPrice = (regularPrice != null && regularPrice > 0) ? regularPrice : unitPrice;

  /// Monto de ahorro / descuento unitario * cantidad
  double get discountSavings =>
      (regularPrice > unitPrice + 0.01) ? (regularPrice - unitPrice) * quantity : 0.0;

  bool get hasDiscount => discountSavings > 0.01;

  factory SaleItemRecord.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    final rawIvaRate = json['iva_rate'] ?? product?['iva_rate'] ?? 21.0;
    final unitPrice = double.tryParse(json['unit_price']?.toString() ?? '0') ?? 0.0;

    final rawRegularPrice = json['regular_price'] ?? product?['selling_price'];
    final regularPrice = double.tryParse(rawRegularPrice?.toString() ?? '') ?? unitPrice;

    String? discountLabel = json['discount_label']?.toString() ?? json['offer_label']?.toString();
    if (discountLabel == null || discountLabel.trim().isEmpty) {
      if (regularPrice > unitPrice + 0.01) {
        final offers = product?['offers'] as List<dynamic>?;
        if (offers != null && offers.isNotEmpty) {
          final firstOffer = offers.first as Map<String, dynamic>?;
          final periodType = firstOffer?['period_type']?.toString();
          if (periodType == 'daily') {
            discountLabel = 'Oferta Diaria';
          } else if (periodType == 'weekly') {
            discountLabel = 'Oferta Semanal';
          } else if (periodType == 'monthly') {
            discountLabel = 'Oferta Mensual';
          } else if (firstOffer?['name'] != null && firstOffer!['name'].toString().trim().isNotEmpty) {
            discountLabel = firstOffer['name'].toString().trim();
          } else {
            discountLabel = 'Oferta Especial';
          }
        } else {
          discountLabel = 'Descuento';
        }
      }
    }

    return SaleItemRecord(
      id: json['id'] is int ? json['id'] : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
      productId: json['product_id'] as int?,
      productName: json['product_name'] as String? ?? product?['name'] as String? ?? '',
      internalCode: product?['internal_code'] as String? ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '0') ?? 0.0,
      unitPrice: unitPrice,
      regularPrice: regularPrice,
      subtotal: double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0.0,
      ivaRate: double.tryParse(rawIvaRate.toString()) ?? 21.0,
      isSoldByWeight: product?['is_sold_by_weight'] == true || product?['is_sold_by_weight'] == 1,
      discountLabel: discountLabel,
    );
  }
}

/// Modelo de venta enriquecido para el historial (no reemplaza la entidad Sale del POS).
class SaleRecord {
  final int id;
  final double total;
  final double totalSurcharge;
  final double shippingCost;
  final double? tenderedAmount;
  final double? changeAmount;
  final String status;  // 'active' | 'voided' | 'pending' | 'completed'
  final DateTime createdAt;
  final List<SaleItemRecord> items;
  final List<SalePayment> payments;
  final int? userId;
  final String? userName;
  final int? cashierId;
  final String? cashierName;
  final int? cashShiftId;
  final int? cashRegisterId;
  final String? cashRegisterName;
  final double? iibbPerceptionAmount;
  final double? iibbPerceptionRate;
  final String invoiceStatus;
  final Map<String, dynamic>? electronicInvoice;
  final Map<String, dynamic>? deliveryNote;
  final int? customerId;
  final String? customerName;
  final int? customerDocumentType;
  final String? customerDocumentNumber;
  final String? customerTaxCondition;
  final String? customerAddress;

  const SaleRecord({
    required this.id,
    required this.total,
    this.totalSurcharge = 0.0,
    this.shippingCost = 0.0,
    this.tenderedAmount,
    this.changeAmount,
    required this.status,
    required this.createdAt,
    required this.items,
    required this.payments,
    this.userId,
    this.userName,
    this.cashierId,
    this.cashierName,
    this.cashShiftId,
    this.cashRegisterId,
    this.cashRegisterName,
    this.iibbPerceptionAmount,
    this.iibbPerceptionRate,
    this.invoiceStatus = 'none',
    this.electronicInvoice,
    this.deliveryNote,
    this.customerId,
    this.customerName,
    this.customerDocumentType,
    this.customerDocumentNumber,
    this.customerTaxCondition,
    this.customerAddress,
  });

  bool get isVoided => status == 'voided';
  bool get isPending => status == 'pending';
  bool get hasCae =>
      electronicInvoice != null &&
      (electronicInvoice!['cae'] != null &&
          electronicInvoice!['cae'].toString().trim().isNotEmpty);

  /// Total de ahorro / descuentos acumulado en todos los items de la venta
  double get totalSavings =>
      items.fold(0.0, (sum, item) => sum + item.discountSavings);

  /// Subtotal de lista (precio regular) antes de descuentos
  double get subtotalList =>
      items.fold(0.0, (sum, item) => sum + (item.regularPrice * item.quantity));

  /// Indica si hubo ahorros o descuentos en la venta
  bool get hasSavings => totalSavings > 0.01;

  /// Sumatoria real de recargos de todos los pagos (calculado desde sale_payments).
  double get surchargeTotal =>
      payments.fold(0.0, (sum, p) => sum + p.surchargeAmount);

  /// Ingreso NETO del negocio = total de items vendidos (sin recargo bancario).
  double get netTotal => total;

  /// Total de venta con flete (sin recargo bancario), homologado con cartTotal de PosProvider.
  double get totalWithShipping => total + shippingCost;

  /// Total real cobrado al cliente = base + flete + recargo bancario.
  double get grandTotal => total + shippingCost + surchargeTotal;

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

    final cashShift = json['cash_shift'] as Map<String, dynamic>?;
    final cashRegister = cashShift?['cash_register'] as Map<String, dynamic>?;
    final rawShiftId = json['cash_shift_id'] ?? cashShift?['id'];
    final rawRegId = cashShift?['cash_register_id'] ?? cashRegister?['id'];

    return SaleRecord(
      id: json['id'] is int ? json['id'] : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
      total: double.tryParse(json['total']?.toString() ?? '0') ?? 0.0,
      totalSurcharge: double.tryParse((json['total_surcharge'] ?? '0').toString()) ?? 0.0,
      shippingCost: double.tryParse((json['shipping_cost'] ?? '0').toString()) ?? 0.0,
      tenderedAmount: json['tendered_amount'] != null
          ? double.tryParse(json['tendered_amount'].toString())
          : null,
      changeAmount: json['change_amount'] != null
          ? double.tryParse(json['change_amount'].toString())
          : null,
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      items: itemsList,
      payments: paymentsList,
      userId: json['user_id'] as int?,
      userName: json['user']?['name'] as String?,
      cashierId: json['cashier_id'] as int?,
      cashierName: json['cashier']?['name'] as String?,
      cashShiftId: rawShiftId is int ? rawShiftId : int.tryParse(rawShiftId?.toString() ?? ''),
      cashRegisterId: rawRegId is int ? rawRegId : int.tryParse(rawRegId?.toString() ?? ''),
      cashRegisterName: cashRegister?['name']?.toString(),
      iibbPerceptionAmount: json['iibb_perception_amount'] != null
          ? double.tryParse(json['iibb_perception_amount'].toString())
          : null,
      iibbPerceptionRate: json['iibb_perception_rate'] != null
          ? double.tryParse(json['iibb_perception_rate'].toString())
          : null,
      invoiceStatus: json['invoice_status'] as String? ?? 'none',
      electronicInvoice: json['electronic_invoice'] as Map<String, dynamic>? ??
          json['electronicInvoice'] as Map<String, dynamic>?,
      deliveryNote: json['delivery_note'] as Map<String, dynamic>? ??
          json['deliveryNote'] as Map<String, dynamic>?,
      customerId: json['customer_id'] as int? ?? json['customer']?['id'] as int?,
      customerName: json['customer']?['name'] as String? ?? json['customer_name'] as String?,
      customerDocumentType: json['customer']?['document_type'] != null
          ? int.tryParse(json['customer']['document_type'].toString())
          : null,
      customerDocumentNumber: json['customer']?['document_number'] as String? ?? json['customer_document_number'] as String?,
      customerTaxCondition: json['customer']?['tax_condition'] as String?,
      customerAddress: (json['customer']?['fiscal_address'] ??
              json['customer']?['delivery_address'] ??
              json['delivery_address'])
          ?.toString(),
    );
  }
}
