import 'package:equatable/equatable.dart';

class SupplierInvoice extends Equatable {
  final int? id;
  final int supplierId;
  final String? supplierName;
  final String type; // 'invoice', 'delivery_note', 'credit_note'
  final String status; // 'pending', 'partial', 'paid', 'cancelled'
  final double amount;
  final String? invoiceNumber;
  final String? description;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final String? receiptFileUrl;
  final double? taxAmount;
  final double? freightAmount;
  final double? discountAmount;
  final String? editReason;
  final List<dynamic>? items;

  // ── 15 Campos Fiscales (ARCA / AFIP - Responsable Inscripto) ──
  final String? voucherLetter; // 'A', 'B', 'C', 'M', 'X'
  final int? pointOfSale;
  final int? voucherNumber;
  final double? net21;
  final double? iva21;
  final double? net105;
  final double? iva105;
  final double? net27;
  final double? iva27;
  final double? nonTaxedAmount;
  final double? exemptAmount;
  final double? ivaPerception;
  final double? iibbPerception;
  final double? internalTaxes;
  final bool affectsVatBook;

  const SupplierInvoice({
    this.id,
    required this.supplierId,
    this.supplierName,
    this.type = 'invoice',
    this.status = 'pending',
    required this.amount,
    this.invoiceNumber,
    this.description,
    this.issueDate,
    this.dueDate,
    this.receiptFileUrl,
    this.taxAmount,
    this.freightAmount,
    this.discountAmount,
    this.editReason,
    this.items,
    this.voucherLetter,
    this.pointOfSale,
    this.voucherNumber,
    this.net21,
    this.iva21,
    this.net105,
    this.iva105,
    this.net27,
    this.iva27,
    this.nonTaxedAmount,
    this.exemptAmount,
    this.ivaPerception,
    this.iibbPerception,
    this.internalTaxes,
    this.affectsVatBook = true,
  });

  /// Retorna el formato estandarizado 'A 0001-00012345' si PV y Número existen,
  /// o recurre al invoiceNumber heredado / string vacío.
  String get formattedNumber {
    if (pointOfSale != null && voucherNumber != null) {
      final letter = (voucherLetter != null && voucherLetter!.trim().isNotEmpty)
          ? voucherLetter!.trim().toUpperCase()
          : 'A';
      return '$letter ${pointOfSale.toString().padLeft(4, '0')}-${voucherNumber.toString().padLeft(8, '0')}';
    }
    return invoiceNumber ?? '';
  }

  SupplierInvoice copyWith({
    int? id,
    int? supplierId,
    String? supplierName,
    String? type,
    String? status,
    double? amount,
    String? invoiceNumber,
    String? description,
    DateTime? issueDate,
    DateTime? dueDate,
    String? receiptFileUrl,
    double? taxAmount,
    double? freightAmount,
    double? discountAmount,
    String? editReason,
    List<dynamic>? items,
    String? voucherLetter,
    int? pointOfSale,
    int? voucherNumber,
    double? net21,
    double? iva21,
    double? net105,
    double? iva105,
    double? net27,
    double? iva27,
    double? nonTaxedAmount,
    double? exemptAmount,
    double? ivaPerception,
    double? iibbPerception,
    double? internalTaxes,
    bool? affectsVatBook,
  }) {
    return SupplierInvoice(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      type: type ?? this.type,
      status: status ?? this.status,
      amount: amount ?? this.amount,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      description: description ?? this.description,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      receiptFileUrl: receiptFileUrl ?? this.receiptFileUrl,
      taxAmount: taxAmount ?? this.taxAmount,
      freightAmount: freightAmount ?? this.freightAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      editReason: editReason ?? this.editReason,
      items: items ?? this.items,
      voucherLetter: voucherLetter ?? this.voucherLetter,
      pointOfSale: pointOfSale ?? this.pointOfSale,
      voucherNumber: voucherNumber ?? this.voucherNumber,
      net21: net21 ?? this.net21,
      iva21: iva21 ?? this.iva21,
      net105: net105 ?? this.net105,
      iva105: iva105 ?? this.iva105,
      net27: net27 ?? this.net27,
      iva27: iva27 ?? this.iva27,
      nonTaxedAmount: nonTaxedAmount ?? this.nonTaxedAmount,
      exemptAmount: exemptAmount ?? this.exemptAmount,
      ivaPerception: ivaPerception ?? this.ivaPerception,
      iibbPerception: iibbPerception ?? this.iibbPerception,
      internalTaxes: internalTaxes ?? this.internalTaxes,
      affectsVatBook: affectsVatBook ?? this.affectsVatBook,
    );
  }

  @override
  List<Object?> get props => [
        id,
        supplierId,
        supplierName,
        type,
        status,
        amount,
        invoiceNumber,
        description,
        issueDate,
        dueDate,
        receiptFileUrl,
        taxAmount,
        freightAmount,
        discountAmount,
        editReason,
        items,
        voucherLetter,
        pointOfSale,
        voucherNumber,
        net21,
        iva21,
        net105,
        iva105,
        net27,
        iva27,
        nonTaxedAmount,
        exemptAmount,
        ivaPerception,
        iibbPerception,
        internalTaxes,
        affectsVatBook,
      ];
}
