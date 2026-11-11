import '../../domain/entities/supplier_invoice.dart';

class SupplierInvoiceModel extends SupplierInvoice {
  const SupplierInvoiceModel({
    super.id,
    required super.supplierId,
    super.supplierName,
    super.type = 'invoice',
    super.status = 'pending',
    required super.amount,
    super.invoiceNumber,
    super.description,
    super.issueDate,
    super.dueDate,
    super.receiptFileUrl,
    super.taxAmount,
    super.freightAmount,
    super.discountAmount,
    super.editReason,
    super.items,
    super.voucherLetter,
    super.pointOfSale,
    super.voucherNumber,
    super.net21,
    super.iva21,
    super.net105,
    super.iva105,
    super.net27,
    super.iva27,
    super.nonTaxedAmount,
    super.exemptAmount,
    super.ivaPerception,
    super.iibbPerception,
    super.internalTaxes,
    super.affectsVatBook = true,
  });

  static double? _parseDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString());
  }

  static int? _parseInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString());
  }

  static bool _parseBool(dynamic val, {bool defaultValue = true}) {
    if (val == null) return defaultValue;
    if (val is bool) return val;
    if (val is num) return val != 0;
    final s = val.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
  }

  factory SupplierInvoiceModel.fromJson(Map<String, dynamic> json) {
    final rawIssue = json['issue_date'] ?? json['date'];
    final rawDue = json['due_date'];

    return SupplierInvoiceModel(
      id: _parseInt(json['id']),
      supplierId: _parseInt(json['supplier_id']) ?? 0,
      supplierName: json['supplier_name']?.toString() ??
          (json['supplier'] is Map ? json['supplier']['name']?.toString() : null),
      type: json['type']?.toString() ?? 'invoice',
      status: json['status']?.toString() ?? 'pending',
      amount: _parseDouble(json['amount']) ?? 0.0,
      invoiceNumber: json['invoice_number']?.toString(),
      description: json['description']?.toString(),
      issueDate: rawIssue != null ? DateTime.tryParse(rawIssue.toString()) : null,
      dueDate: rawDue != null ? DateTime.tryParse(rawDue.toString()) : null,
      receiptFileUrl: json['receipt_file_url']?.toString(),
      taxAmount: _parseDouble(json['tax_amount']),
      freightAmount: _parseDouble(json['freight_amount']),
      discountAmount: _parseDouble(json['discount_amount']),
      editReason: json['edit_reason']?.toString(),
      items: json['items'] is List ? json['items'] as List<dynamic> : null,
      // ── 15 Campos Fiscales ──
      voucherLetter: (json['voucher_letter'] ?? json['voucherLetter'])?.toString(),
      pointOfSale: _parseInt(json['point_of_sale'] ?? json['pointOfSale']),
      voucherNumber: _parseInt(json['voucher_number'] ?? json['voucherNumber']),
      net21: _parseDouble(json['net_21'] ?? json['net21']),
      iva21: _parseDouble(json['iva_21'] ?? json['iva21']),
      net105: _parseDouble(json['net_105'] ?? json['net105']),
      iva105: _parseDouble(json['iva_105'] ?? json['iva105']),
      net27: _parseDouble(json['net_27'] ?? json['net27']),
      iva27: _parseDouble(json['iva_27'] ?? json['iva27']),
      nonTaxedAmount: _parseDouble(json['non_taxed_amount'] ?? json['nonTaxedAmount']),
      exemptAmount: _parseDouble(json['exempt_amount'] ?? json['exemptAmount']),
      ivaPerception: _parseDouble(json['iva_perception'] ?? json['ivaPerception']),
      iibbPerception: _parseDouble(json['iibb_perception'] ?? json['iibbPerception']),
      internalTaxes: _parseDouble(json['internal_taxes'] ?? json['internalTaxes']),
      affectsVatBook: _parseBool(json['affects_vat_book'] ?? json['affectsVatBook'], defaultValue: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'supplier_id': supplierId,
      'type': type,
      'status': status,
      'amount': amount,
      if (invoiceNumber != null) 'invoice_number': invoiceNumber,
      if (description != null) 'description': description,
      if (issueDate != null) 'issue_date': issueDate!.toIso8601String(),
      if (dueDate != null) 'due_date': dueDate!.toIso8601String().split('T')[0],
      if (receiptFileUrl != null) 'receipt_file_url': receiptFileUrl,
      if (taxAmount != null) 'tax_amount': taxAmount,
      if (freightAmount != null) 'freight_amount': freightAmount,
      if (discountAmount != null) 'discount_amount': discountAmount,
      if (editReason != null) 'edit_reason': editReason,
      if (items != null) 'items': items,
      // ── 15 Campos Fiscales ──
      'voucher_letter': voucherLetter,
      'point_of_sale': pointOfSale,
      'voucher_number': voucherNumber,
      'net_21': net21,
      'iva_21': iva21,
      'net_105': net105,
      'iva_105': iva105,
      'net_27': net27,
      'iva_27': iva27,
      'non_taxed_amount': nonTaxedAmount,
      'exempt_amount': exemptAmount,
      'iva_perception': ivaPerception,
      'iibb_perception': iibbPerception,
      'internal_taxes': internalTaxes,
      'affects_vat_book': affectsVatBook,
    };
  }

  factory SupplierInvoiceModel.fromEntity(SupplierInvoice entity) {
    return SupplierInvoiceModel(
      id: entity.id,
      supplierId: entity.supplierId,
      supplierName: entity.supplierName,
      type: entity.type,
      status: entity.status,
      amount: entity.amount,
      invoiceNumber: entity.invoiceNumber,
      description: entity.description,
      issueDate: entity.issueDate,
      dueDate: entity.dueDate,
      receiptFileUrl: entity.receiptFileUrl,
      taxAmount: entity.taxAmount,
      freightAmount: entity.freightAmount,
      discountAmount: entity.discountAmount,
      editReason: entity.editReason,
      items: entity.items,
      voucherLetter: entity.voucherLetter,
      pointOfSale: entity.pointOfSale,
      voucherNumber: entity.voucherNumber,
      net21: entity.net21,
      iva21: entity.iva21,
      net105: entity.net105,
      iva105: entity.iva105,
      net27: entity.net27,
      iva27: entity.iva27,
      nonTaxedAmount: entity.nonTaxedAmount,
      exemptAmount: entity.exemptAmount,
      ivaPerception: entity.ivaPerception,
      iibbPerception: entity.iibbPerception,
      internalTaxes: entity.internalTaxes,
      affectsVatBook: entity.affectsVatBook,
    );
  }
}
