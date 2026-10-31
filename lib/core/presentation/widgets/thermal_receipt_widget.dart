import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';

/// Ancho de papel térmico para tickets
enum ThermalPaperWidth {
  mm58(logicalWidth: 210.0, innerPadding: 8.0, qrSize: 100.0, fontSizeFactor: 0.9),
  mm80(logicalWidth: 290.0, innerPadding: 12.0, qrSize: 135.0, fontSizeFactor: 1.0);

  final double logicalWidth;
  final double innerPadding;
  final double qrSize;
  final double fontSizeFactor;

  const ThermalPaperWidth({
    required this.logicalWidth,
    required this.innerPadding,
    required this.qrSize,
    required this.fontSizeFactor,
  });
}

/// Widget responsivo para renderizado y previsualización de tickets térmicos
/// tanto en formato 58mm como en 80mm con cero desbordamiento (RenderFlex overflow).
///
/// Soporta tanto tickets fiscales (AFIP/ARCA RG 1415, RG 4892, RG 5614 Ley 27.743 y RG 5616
/// con CAE, Vto, QR) como comprobantes estándar no fiscales y remitos de entrega / retiro.
class ThermalReceiptWidget extends StatelessWidget {
  final ThermalPaperWidth paperWidth;
  final BusinessSettings? businessSettings;
  final List<dynamic> items;
  final List<Map<String, dynamic>> payments;
  final double total;
  final Map<String, dynamic>? electronicInvoice;
  final Map<String, dynamic>? deliveryNote;
  final bool isReprint;
  final String? saleNumber;
  final String? cashierName;
  final String? customerName;
  final String? customerDoc;
  final String? customerAddress;
  final double surchargeAmount;
  final double discountAmount;
  final String? discountLabel;
  final double tenderedAmount;
  final double changeAmount;
  final double shippingCost;
  final double iibbPerceptionAmount;
  final double iibbPerceptionRate;
  final DateTime? dateTime;

  const ThermalReceiptWidget({
    super.key,
    this.paperWidth = ThermalPaperWidth.mm80,
    this.businessSettings,
    required this.items,
    this.payments = const [],
    required this.total,
    this.electronicInvoice,
    this.deliveryNote,
    this.isReprint = false,
    this.saleNumber,
    this.cashierName,
    this.customerName,
    this.customerDoc,
    this.customerAddress,
    this.surchargeAmount = 0.0,
    this.discountAmount = 0.0,
    this.discountLabel,
    this.tenderedAmount = 0.0,
    this.changeAmount = 0.0,
    this.shippingCost = 0.0,
    this.iibbPerceptionAmount = 0.0,
    this.iibbPerceptionRate = 0.0,
    this.dateTime,
  });

  String _formatPrice(double value) {
    return value.toCurrency();
  }

  double _calculateTotalSavings() {
    if (discountAmount > 0.01) return discountAmount;
    double savings = 0.0;
    for (final rawItem in items) {
      if (rawItem is CartItem) {
        savings += rawItem.discountSavings;
      } else if (rawItem is Map<String, dynamic>) {
        final d = double.tryParse(rawItem['discount_amount']?.toString() ?? '') ?? 0.0;
        if (d > 0.01) {
          savings += d;
        } else {
          final regPrice = double.tryParse(
            rawItem['regular_price']?.toString() ??
            rawItem['product']?['selling_price']?.toString() ??
            ''
          ) ?? 0.0;
          final uPrice = double.tryParse(rawItem['unit_price']?.toString() ?? '') ?? 0.0;
          final q = double.tryParse(rawItem['quantity']?.toString() ?? '1') ?? 1.0;
          if (regPrice > uPrice + 0.01) {
            savings += (regPrice - uPrice) * q;
          }
        }
      }
    }
    return savings;
  }

  String _formatCuit(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 10)}-${digits.substring(10)}';
    }
    return raw.trim();
  }

  /// Resuelve la condición frente al IVA del emisor respetando la configuración del negocio.
  String _resolveIssuerTaxCondition() {
    final letter = electronicInvoice?['voucher_letter']?.toString().trim().toUpperCase() ?? 'B';
    final rawCond = businessSettings?.taxCondition?.trim() ?? '';
    switch (rawCond.toLowerCase()) {
      case 'monotributo':
      case 'responsable_monotributo':
      case 'responsable monotributo':
        return 'RESPONSABLE MONOTRIBUTO';
      case 'exento':
      case 'sujeto_exento':
      case 'iva_exento':
      case 'iva sujeto exento':
        return 'IVA SUJETO EXENTO';
      case 'responsable_inscripto':
      case 'responsable inscripto':
      case 'iva responsable inscripto':
        return 'IVA RESPONSABLE INSCRIPTO';
      default:
        if (rawCond.isNotEmpty) {
          return rawCond.toUpperCase();
        }
        return letter == 'C' ? 'RESPONSABLE MONOTRIBUTO' : 'IVA RESPONSABLE INSCRIPTO';
    }
  }

  /// Normaliza la condición frente al IVA del receptor según RG 5616.
  String _formatReceiverTaxCondition(String raw, String voucherLetter) {
    switch (raw.trim().toLowerCase()) {
      case 'consumidor_final':
      case 'consumidor final':
      case 'a consumidor final':
        return 'A CONSUMIDOR FINAL';
      case 'responsable_inscripto':
      case 'responsable inscripto':
      case 'iva responsable inscripto':
        return 'IVA RESPONSABLE INSCRIPTO';
      case 'monotributo':
      case 'responsable_monotributo':
      case 'responsable monotributo':
        return 'RESPONSABLE MONOTRIBUTO';
      case 'exento':
      case 'sujeto_exento':
      case 'iva_exento':
      case 'iva sujeto exento':
        return 'IVA SUJETO EXENTO';
      default:
        if (raw.trim().isEmpty) {
          return voucherLetter == 'A' ? 'IVA RESPONSABLE INSCRIPTO' : 'A CONSUMIDOR FINAL';
        }
        return raw.trim().toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = paperWidth.logicalWidth;
    final padding = paperWidth.innerPadding;
    final factor = paperWidth.fontSizeFactor;
    final isFiscal = electronicInvoice != null;
    final date = dateTime ?? DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(date);

    final iibbStr = (businessSettings?.iibb != null && businessSettings!.iibb!.trim().isNotEmpty)
        ? businessSettings!.iibb!.trim()
        : (isFiscal ? 'Exento' : '');
    final startDateStr = (businessSettings?.activityStartDate != null &&
            businessSettings!.activityStartDate!.trim().isNotEmpty)
        ? businessSettings!.activityStartDate!.trim()
        : '';

    return Container(
      width: width,
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Encabezado de la Empresa ──
          _buildCenterText(
            businessSettings?.companyName?.toUpperCase() ?? 'MI NEGOCIO',
            fontSize: 13.5 * factor,
            isBold: true,
          ),
          if (businessSettings?.address != null &&
              businessSettings!.address!.trim().isNotEmpty) ...[
            const SizedBox(height: 1),
            _buildCenterText(
              businessSettings!.address!.trim(),
              fontSize: 10.0 * factor,
            ),
          ],
          if (businessSettings?.taxId != null &&
              businessSettings!.taxId!.trim().isNotEmpty) ...[
            const SizedBox(height: 1),
            _buildCenterText(
              'CUIT: ${_formatCuit(businessSettings!.taxId!)}',
              fontSize: 10.0 * factor,
              isBold: true,
            ),
          ],
          if (isFiscal && iibbStr.isNotEmpty) ...[
            _buildCenterText(
              'Ing. Brutos: ${_formatCuit(iibbStr)}',
              fontSize: 9.2 * factor,
            ),
          ],
          if (isFiscal && startDateStr.isNotEmpty) ...[
            _buildCenterText(
              'Inicio de Actividades: $startDateStr',
              fontSize: 9.2 * factor,
            ),
          ],
          if (businessSettings?.phone != null &&
              businessSettings!.phone!.trim().isNotEmpty) ...[
            _buildCenterText(
              'Tel: ${businessSettings!.phone!.trim()}',
              fontSize: 9.5 * factor,
            ),
          ],
          if (isFiscal) ...[
            const SizedBox(height: 1),
            _buildCenterText(
              _resolveIssuerTaxCondition(),
              fontSize: 9.5 * factor,
              isBold: true,
            ),
          ],
          const SizedBox(height: 2),
          _buildDivider(thickness: 1.5),

          // ── 2. Tipo y Número de Comprobante ──
          if (isFiscal) ...[
            _buildFiscalVoucherHeader(factor),
          ] else ...[
            _buildCenterText(
              'COMPROBANTE DE VENTA',
              fontSize: 13.0 * factor,
              isBold: true,
            ),
            const SizedBox(height: 2),
            _buildCenterText(
              '*** NO VALIDO COMO FACTURA ***',
              fontSize: 10.0 * factor,
              isBold: true,
            ),
          ],

          const SizedBox(height: 2),
          _buildDivider(),

          // ── 3. Metadatos (Fecha, Cajero, Ticket) ──
          _buildKeyValueRow('FECHA:', formattedDate, factor: factor),
          if (saleNumber != null && saleNumber!.isNotEmpty)
            _buildKeyValueRow(
              'TICKET N°:',
              saleNumber!.padLeft(6, '0'),
              factor: factor,
              isBold: true,
            ),
          if (cashierName != null && cashierName!.isNotEmpty)
            _buildKeyValueRow(
              'CAJERO:',
              cashierName!.toUpperCase(),
              factor: factor,
            ),

          // ── 4. Datos del Cliente / Receptor ──
          if (isFiscal) ...[
            _buildFiscalReceiverInfo(factor),
          ] else ...[
            _buildNonFiscalReceiverInfo(factor),
          ],

          const SizedBox(height: 2),
          _buildDivider(),

          // ── 5. Detalle de Ítems Vendidos ──
          ..._buildItemsList(factor),

          const SizedBox(height: 2),
          _buildDivider(thickness: 1.5),

          // ── 6. Resumen Financiero y Métodos de Pago ──
          _buildFinancialSummary(factor),

          // ── 7. Pie Fiscal AFIP (o Pie Comercial No Fiscal) ──
          if (isFiscal) ...[
            _buildFiscalFooter(factor),
          ] else ...[
            _buildNonFiscalFooter(factor),
          ],

          if (isReprint) ...[
            const SizedBox(height: 6),
            _buildCenterText(
              '[ REIMPRESIÓN ]',
              fontSize: 11.0 * factor,
              isBold: true,
            ),
          ],

          // ── 8. Sección Opcional de Remito / Orden de Retiro ──
          if (deliveryNote != null) ...[
            const SizedBox(height: 12),
            _buildDeliveryNoteSection(factor),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPONENTES FISCALES AFIP / ARCA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFiscalVoucherHeader(double factor) {
    final invoice = electronicInvoice!;
    final letter = invoice['voucher_letter']?.toString().toUpperCase() ?? 'B';
    final nro = invoice['formatted_number']?.toString() ??
        invoice['voucher_number']?.toString() ??
        (saleNumber ?? '00001');
    final pv = invoice['point_of_sale']?.toString().padLeft(5, '0') ?? '00001';
    final defaultCode = letter == 'A' ? 1 : (letter == 'C' ? 11 : 6);
    final vType = int.tryParse(invoice['voucher_type']?.toString() ?? '') ?? defaultCode;
    final codStr = 'COD. ${vType.toString().padLeft(3, '0')}';
    final isNotaCredito = [3, 8, 13, 113].contains(vType);
    final tipoComp = isNotaCredito ? 'NOTA DE CREDITO' : 'FACTURA';
    final assocLabel = invoice['associated_voucher_label']?.toString() ??
        (invoice['associated_formatted_number'] != null
            ? 'Factura $letter Nro ${invoice['associated_formatted_number']}'
            : null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: _buildCenterText(
            '$tipoComp $letter Nro $nro',
            fontSize: 13.0 * factor,
            isBold: true,
          ),
        ),
        const SizedBox(height: 1),
        _buildCenterText(
          codStr,
          fontSize: 9.8 * factor,
          isBold: true,
        ),
        const SizedBox(height: 2),
        _buildCenterText(
          (isNotaCredito && assocLabel != null && assocLabel.trim().isNotEmpty)
              ? 'PUNTO DE VENTA: $pv\nCOMP. ASOC: ${assocLabel.trim()}'
              : 'PUNTO DE VENTA: $pv',
          fontSize: 10.5 * factor,
        ),
      ],
    );
  }

  Widget _buildFiscalReceiverInfo(double factor) {
    final invoice = electronicInvoice!;
    final letter = invoice['voucher_letter']?.toString().toUpperCase() ?? 'B';
    final recName = invoice['receiver_name']?.toString() ??
        customerName ??
        'CONSUMIDOR FINAL';
    final recDoc = invoice['doc_number']?.toString() ?? customerDoc ?? '---';
    final rawRecCond = invoice['receiver_tax_condition']?.toString() ?? '';
    final recCond = _formatReceiverTaxCondition(rawRecCond, letter);
    final recAddress = (invoice['receiver_address']?.toString() ?? customerAddress ?? '').trim();

    final isCustomClient = recName.toUpperCase() != 'CONSUMIDOR FINAL';
    final isLongName = recName.trim().length > 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLongName)
          _buildMultilineTextRow('CLIENTE:', recName.toUpperCase(), factor: factor, isBold: isCustomClient)
        else
          _buildKeyValueRow('CLIENTE:', recName.toUpperCase(), factor: factor, isBold: isCustomClient),
        _buildKeyValueRow('DOC:', _formatCuit(recDoc), factor: factor),
        _buildKeyValueRow('IVA:', recCond, factor: factor),
        if (recAddress.isNotEmpty && recAddress != '---')
          _buildMultilineTextRow('DOMICILIO:', recAddress.toUpperCase(), factor: factor),
      ],
    );
  }

  Widget _buildNonFiscalReceiverInfo(double factor) {
    final name = (customerName != null && customerName!.trim().isNotEmpty)
        ? customerName!.trim().toUpperCase()
        : 'CONSUMIDOR FINAL';
    final isCustomClient = name != 'CONSUMIDOR FINAL';
    final isLongName = name.trim().length > 20;
    final doc = (customerDoc ?? '').trim();
    final address = (customerAddress ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLongName)
          _buildMultilineTextRow('CLIENTE:', name, factor: factor, isBold: isCustomClient)
        else
          _buildKeyValueRow('CLIENTE:', name, factor: factor, isBold: isCustomClient),
        if (doc.isNotEmpty && doc != '---')
          _buildKeyValueRow('DOC / CUIT:', _formatCuit(doc), factor: factor),
        if (address.isNotEmpty && address != '---')
          _buildMultilineTextRow('DOMICILIO:', address.toUpperCase(), factor: factor),
      ],
    );
  }

  double _calculateContainedIva() {
    final invoice = electronicInvoice;
    if (invoice != null) {
      final explicitIva = double.tryParse(invoice['iva_amount']?.toString() ?? '') ?? 0.0;
      if (explicitIva > 0) return explicitIva;
    }

    double sumIva = 0.0;
    for (final rawItem in items) {
      double sub = 0.0;
      double rate = 21.0;
      if (rawItem is CartItem) {
        sub = rawItem.subtotal;
        rate = rawItem.product.ivaRate > 0 ? rawItem.product.ivaRate : 21.0;
      } else if (rawItem is Map<String, dynamic>) {
        final q = double.tryParse(rawItem['quantity']?.toString() ?? '1') ?? 1.0;
        final up = double.tryParse(
                rawItem['unit_price']?.toString() ?? rawItem['price']?.toString() ?? '0') ??
            0.0;
        sub = double.tryParse(rawItem['subtotal']?.toString() ?? '') ?? (q * up);
        rate = double.tryParse(
                (rawItem['iva_rate'] ?? rawItem['tax_rate'] ?? rawItem['aliquot'] ?? 21)
                    .toString()) ??
            21.0;
      }
      if (sub > 0 && rate > 0) {
        final net = sub / (1 + (rate / 100.0));
        sumIva += (sub - net);
      }
    }
    if (sumIva > 0) return sumIva;

    final baseTotal = total - shippingCost - iibbPerceptionAmount;
    if (baseTotal > 0) {
      return baseTotal - (baseTotal / 1.21);
    }
    return 0.0;
  }

  double _calculateNetWithoutTaxes() {
    final invoice = electronicInvoice;
    if (invoice != null) {
      final explicitNet =
          double.tryParse(invoice['net_amount']?.toString() ?? '') ?? 0.0;
      if (explicitNet > 0) return explicitNet;
    }
    final perceptionAmt = iibbPerceptionAmount > 0
        ? iibbPerceptionAmount
        : (double.tryParse(
                electronicInvoice?['iibb_perception_amount']?.toString() ??
                    '') ??
            0.0);
    final baseTotal = total - shippingCost - perceptionAmt;
    final containedIva = _calculateContainedIva();
    return (baseTotal - containedIva).clamp(0.0, double.infinity);
  }

  String _formatCaeExpiration(dynamic raw) {
    final str = (raw ?? '').toString().trim();
    if (str.isEmpty) return '';
    final datePart = str.split('T').first.split(' ').first;
    final parts = datePart.split('-');
    if (parts.length == 3 && parts[0].length == 4) {
      return '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
    }
    return datePart;
  }

  Widget _buildFiscalFooter(double factor) {
    final invoice = electronicInvoice!;
    final voucherLetter = invoice['voucher_letter']?.toString().toUpperCase();
    final vType = int.tryParse(invoice['voucher_type']?.toString() ?? '0') ?? 0;
    final isFacturaA = voucherLetter == 'A' || vType == 1 || vType == 2 || vType == 3;
    final isFacturaB = voucherLetter == 'B' || vType == 6 || vType == 7 || vType == 8;
    final netAmount = invoice['net_amount'];
    final ivaAmount = invoice['iva_amount'];
    final cae = invoice['cae']?.toString() ?? '';
    final caeVto = _formatCaeExpiration(invoice['cae_expiration']);
    final qrData = invoice['qr_data']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Desglose de IVA para Factura A
        if (isFacturaA && netAmount != null && ivaAmount != null) ...[
          const SizedBox(height: 4),
          _buildDivider(),
          _buildKeyValueRow(
            'Neto Gravado:',
            '\$${_formatPrice(double.tryParse(netAmount.toString()) ?? 0.0)}',
            factor: factor,
            isBold: true,
          ),
          _buildKeyValueRow(
            'IVA:',
            '\$${_formatPrice(double.tryParse(ivaAmount.toString()) ?? 0.0)}',
            factor: factor,
            isBold: true,
          ),
        ],

        // Régimen de Transparencia Fiscal al Consumidor (Ley 27.743 / RG 5614) para Factura B
        if (isFacturaB) ...[
          const SizedBox(height: 2),
          _buildDivider(),
          _buildCenterText(
            'Régimen Trans. Fiscal al Consumidor (Ley 27.743)',
            fontSize: 8.8 * factor,
            isBold: true,
          ),
          const SizedBox(height: 1.5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              'Precio s/imp: \$${_formatPrice(_calculateNetWithoutTaxes())} - IVA Contenido: \$${_formatPrice(_calculateContainedIva())}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.8 * factor,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 1),
          _buildKeyValueRow(
            'Otros Imp. Nac. Indirectos:',
            '\$${_formatPrice(0)}',
            factor: factor,
            fontSize: 9.2,
          ),
        ],

        const SizedBox(height: 2),
        _buildDivider(),

        if (cae.isNotEmpty) ...[
          _buildCenterText(
            'CAE: $cae',
            fontSize: 11.0 * factor,
            isBold: true,
          ),
          _buildCenterText(
            'VTO. CAE: $caeVto',
            fontSize: 11.0 * factor,
            isBold: true,
          ),
          const SizedBox(height: 3),
        ],

        if (qrData != null && qrData.isNotEmpty) ...[
          Center(
            child: SizedBox(
              width: paperWidth.qrSize,
              height: paperWidth.qrSize,
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: paperWidth.qrSize,
                padding: const EdgeInsets.all(2),
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],

        _buildCenterText(
          'Comprobante Autorizado por AFIP',
          fontSize: 10.5 * factor,
          isBold: true,
        ),
      ],
    );
  }

  Widget _buildNonFiscalFooter(double factor) {
    int totalUnits = 0;
    for (final rawItem in items) {
      if (rawItem is CartItem) {
        if (!rawItem.product.isSoldByWeight) {
          totalUnits += rawItem.quantity.toInt();
        }
      } else if (rawItem is Map<String, dynamic>) {
        final prod = rawItem['product'] as Map<String, dynamic>? ?? {};
        final isWeight = rawItem['is_sold_by_weight'] == true ||
            prod['is_sold_by_weight'] == true;
        if (!isWeight) {
          final q = double.tryParse(rawItem['quantity']?.toString() ?? '1') ?? 1.0;
          totalUnits += q.toInt();
        }
      }
    }

    final totalSavings = _calculateTotalSavings();
    final hasSavings = totalSavings > 0.01;

    final footerMsg = (businessSettings?.receiptFooterMessage != null &&
            businessSettings!.receiptFooterMessage!.trim().isNotEmpty)
        ? businessSettings!.receiptFooterMessage!.trim()
        : '¡Gracias por su compra!';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 2),
        _buildDivider(),
        if (totalUnits > 0) ...[
          _buildKeyValueRow(
            'UNIDADES VENDIDAS:',
            totalUnits.toString(),
            factor: factor,
            isBold: true,
          ),
          _buildDivider(),
        ],
        if (hasSavings) ...[
          _buildCenterText(
            '*** ¡USTED AHORRÓ: \$${_formatPrice(totalSavings)}! ***',
            fontSize: 10.0 * factor,
            isBold: true,
          ),
          const SizedBox(height: 2),
          _buildDivider(),
        ],
        const SizedBox(height: 2),
        _buildCenterText(
          footerMsg,
          fontSize: 10.0 * factor,
          isBold: true,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DETALLE DE ÍTEMS CON PROTECCIÓN DEFENSIVA OVERFLOW
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildItemsList(double factor) {
    final widgets = <Widget>[];
    final isFiscal = electronicInvoice != null;
    final letter = electronicInvoice?['voucher_letter']?.toString().toUpperCase() ?? 'B';
    final showIvaAliquot = isFiscal && (letter == 'A' || letter == 'B');

    for (final rawItem in items) {
      String name = 'PRODUCTO';
      double quantity = 1.0;
      double unitPrice = 0.0;
      double subtotal = 0.0;
      bool isSoldByWeight = false;
      double ivaRate = 21.0;
      String discountTag = '';

      if (rawItem is CartItem) {
        name = rawItem.product.name;
        quantity = rawItem.quantity;
        unitPrice = rawItem.unitPrice;
        subtotal = rawItem.subtotal;
        isSoldByWeight = rawItem.product.isSoldByWeight;
        if (rawItem.hasDiscount) {
          discountTag = rawItem.hasActiveOffer
              ? rawItem.offerBadgeLabel
              : (rawItem.promotionalLabel != null &&
                      rawItem.promotionalLabel!.trim().isNotEmpty
                  ? rawItem.promotionalLabel!.trim()
                  : 'Descuento');
        }
      } else if (rawItem is Map<String, dynamic>) {
        final prod = rawItem['product'] as Map<String, dynamic>? ?? {};
        name = rawItem['product_name']?.toString() ??
            prod['name']?.toString() ??
            rawItem['name']?.toString() ??
            'PRODUCTO';
        quantity = double.tryParse(rawItem['quantity']?.toString() ?? '1') ?? 1.0;
        unitPrice = double.tryParse(
                rawItem['unit_price']?.toString() ?? rawItem['price']?.toString() ?? '0') ??
            0.0;
        subtotal = double.tryParse(rawItem['subtotal']?.toString() ?? '') ??
            (quantity * unitPrice);
        isSoldByWeight = rawItem['is_sold_by_weight'] == true ||
            prod['is_sold_by_weight'] == true;
        ivaRate = double.tryParse(
                (rawItem['iva_rate'] ?? rawItem['tax_rate'] ?? rawItem['aliquot'] ?? 21)
                    .toString()) ??
            21.0;
        final dAmt =
            double.tryParse(rawItem['discount_amount']?.toString() ?? '') ?? 0.0;
        final regPrice = double.tryParse(
                rawItem['regular_price']?.toString() ??
                    prod['selling_price']?.toString() ??
                    '') ??
            0.0;
        if (dAmt > 0.01 || (regPrice > unitPrice + 0.01)) {
          final lbl = rawItem['discount_label']?.toString() ??
              rawItem['offer_label']?.toString() ??
              '';
          discountTag = lbl.trim().isNotEmpty ? lbl.trim() : 'Descuento';
        }
      }

      final qtyStr = isSoldByWeight
          ? '${quantity.toQty()} kg'
          : (quantity % 1 == 0 ? '${quantity.toInt()}' : quantity.toQty());

      final aliquotTag = showIvaAliquot
          ? ' (${ivaRate == ivaRate.roundToDouble() ? ivaRate.toInt() : ivaRate})'
          : '';

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Fila 1: Nombre de producto con wrap dinámico (cero overflow)
              Text(
                name.toUpperCase(),
                softWrap: true,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5 * factor,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              if (discountTag.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  '($discountTag)',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9.2 * factor,
                    fontStyle: FontStyle.italic,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 1.5),
              // Fila 2: Cantidad x Precio Unitario (+ Alícuota IVA) a la izquierda, Subtotal a la derecha
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$qtyStr x \$${_formatPrice(unitPrice)}$aliquotTag',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.5 * factor,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '\$${_formatPrice(subtotal)}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.0 * factor,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESUMEN FINANCIERO Y PAGOS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFinancialSummary(double factor) {
    final perceptionAmt = iibbPerceptionAmount > 0
        ? iibbPerceptionAmount
        : (double.tryParse(
                electronicInvoice?['iibb_perception_amount']?.toString() ?? '') ??
            0.0);
    final perceptionRt = iibbPerceptionRate > 0
        ? iibbPerceptionRate
        : (double.tryParse(
                electronicInvoice?['iibb_perception_rate']?.toString() ?? '') ??
            0.0);
    final hasPerception = perceptionAmt > 0.01;

    final totalSavings = _calculateTotalSavings();
    final hasSavings = totalSavings > 0.01;
    final grandTotal = total + surchargeAmount;
    final hasSurcharge = surchargeAmount > 0.01;
    final hasShipping = shippingCost > 0.01;
    final hasMultiplePayments = payments.length > 1;

    final isComplexSummary = hasMultiplePayments ||
        hasSurcharge ||
        hasShipping ||
        hasPerception ||
        hasSavings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isComplexSummary) ...[
          if (hasSavings) ...[
            _buildKeyValueRow(
              'SUBTOTAL LISTA:',
              '\$${_formatPrice(total + totalSavings - shippingCost - perceptionAmt)}',
              factor: factor,
            ),
            _buildKeyValueRow(
              (discountLabel != null && discountLabel!.trim().isNotEmpty)
                  ? '${discountLabel!.replaceAll(RegExp(r'[^\w\s\/\-]'), '').trim().toUpperCase()}:'
                  : 'AHORRO / DESCUENTO:',
              '-\$${_formatPrice(totalSavings)}',
              factor: factor,
              isBold: true,
            ),
          ] else ...[
            _buildKeyValueRow(
              'SUBTOTAL:',
              '\$${_formatPrice(total - shippingCost - perceptionAmt)}',
              factor: factor,
            ),
          ],
          if (hasShipping)
            _buildKeyValueRow(
              'FLETE / ENVIO:',
              '\$${_formatPrice(shippingCost)}',
              factor: factor,
            ),
          if (hasPerception)
            _buildKeyValueRow(
              'PERCEPCION IIBB (${perceptionRt.toStringAsFixed(1)}%):',
              '\$${_formatPrice(perceptionAmt)}',
              factor: factor,
            ),
          if (hasSurcharge)
            _buildKeyValueRow(
              'RECARGO:',
              '\$${_formatPrice(surchargeAmount)}',
              factor: factor,
            ),
          if (payments.isNotEmpty) ...[
            _buildDivider(),
            for (final p in payments)
              _buildKeyValueRow(
                (p['name']?.toString() ?? 'PAGO').toUpperCase(),
                '\$${_formatPrice(double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0)}',
                factor: factor,
              ),
          ],
          _buildDivider(),
          _buildKeyValueRow(
            'TOTAL COBRADO:',
            '\$${_formatPrice(grandTotal)}',
            factor: factor,
            isBold: true,
            fontSize: 13.0,
          ),
        ] else ...[
          _buildKeyValueRow(
            'TOTAL GENERAL:',
            '\$${_formatPrice(grandTotal)}',
            factor: factor,
            isBold: true,
            fontSize: 13.0,
          ),
          if (payments.isNotEmpty) ...[
            _buildDivider(),
            _buildKeyValueRow(
              'PAGO EN:',
              (payments.first['name']?.toString() ?? 'PAGO').toUpperCase(),
              factor: factor,
            ),
          ],
        ],

        if (tenderedAmount > 0.01 &&
            (!hasMultiplePayments || changeAmount > 0.01)) ...[
          const SizedBox(height: 2),
          _buildKeyValueRow(
            'EFECTIVO RECIBIDO:',
            '\$${_formatPrice(tenderedAmount)}',
            factor: factor,
          ),
          _buildKeyValueRow(
            'SU VUELTO:',
            '\$${_formatPrice(changeAmount)}',
            factor: factor,
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REMITO / ORDEN DE RETIRO
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDeliveryNoteSection(double factor) {
    final note = deliveryNote!;
    final noteId = note['id']?.toString() ?? '';
    final status = (note['status'] ?? 'pending').toString().toLowerCase();
    final isDelivered = status == 'delivered' || status == 'partial';

    final resolvedCustomerName = (customerName != null &&
            customerName!.trim().isNotEmpty)
        ? customerName!.trim()
        : (electronicInvoice?['receiver_name']?.toString() ??
            note['customer']?['name']?.toString() ??
            note['sale']?['customer']?['name']?.toString() ??
            '');
    final resolvedCustomerDoc =
        (electronicInvoice?['doc_number']?.toString() ??
                note['customer']?['document_number']?.toString() ??
                note['sale']?['customer']?['document_number']?.toString() ??
                '')
            .trim();
    final address = (note['delivery_address'] ??
            note['sale']?['delivery_address'] ??
            electronicInvoice?['receiver_address'] ??
            '')
        .toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCenterText(
          '--- CORTAR AQUÍ (REMITO) ---',
          fontSize: 9.0 * factor,
          isBold: true,
        ),
        const SizedBox(height: 2),
        _buildDivider(thickness: 2),
        const SizedBox(height: 4),
        _buildCenterText(
          businessSettings?.companyName?.toUpperCase() ?? 'MI NEGOCIO',
          fontSize: 13.0 * factor,
          isBold: true,
        ),
        const SizedBox(height: 2),
        _buildCenterText(
          isDelivered
              ? 'REMITO — ENTREGA INMEDIATA'
              : 'ORDEN DE RETIRO / REMITO',
          fontSize: 11.5 * factor,
          isBold: true,
        ),
        _buildCenterText(
          '*** DOC. NO VALIDO COMO FACTURA ***',
          fontSize: 9.0 * factor,
        ),
        if (noteId.isNotEmpty)
          _buildCenterText('REMITO N°: ${noteId.padLeft(6, '0')}',
              fontSize: 10.5 * factor, isBold: true),
        if (saleNumber != null)
          _buildCenterText('VENTA ASOC: ${saleNumber!.padLeft(6, '0')}',
              fontSize: 10.0 * factor),
        const SizedBox(height: 4),
        _buildDivider(),
        if (resolvedCustomerName.isNotEmpty) ...[
          if (resolvedCustomerName.trim().length > 20)
            _buildMultilineTextRow('CLIENTE:', resolvedCustomerName.toUpperCase(),
                factor: factor, isBold: true)
          else
            _buildKeyValueRow('CLIENTE:', resolvedCustomerName.toUpperCase(),
                factor: factor, isBold: true),
        ],
        if (resolvedCustomerDoc.isNotEmpty && resolvedCustomerDoc != '---')
          _buildKeyValueRow('DOC / CUIT:', _formatCuit(resolvedCustomerDoc),
              factor: factor),
        if (address.trim().isNotEmpty && address.trim() != '---')
          _buildMultilineTextRow('ENTREGA:', address.toUpperCase(),
              factor: factor),
        const SizedBox(height: 4),
        _buildCenterText(
            isDelivered ? 'ARTICULOS ENTREGADOS' : 'ARTICULOS A RETIRAR',
            fontSize: 11.0 * factor,
            isBold: true),
        _buildDivider(),
        for (final rawItem in items) ...[
          _buildDeliveryItemRow(rawItem, factor),
        ],
        const SizedBox(height: 12),
        _buildCenterText('FIRMA DESPACHANTE:',
            fontSize: 10.0 * factor, isBold: false),
        const SizedBox(height: 24),
        _buildCenterText('____________________________',
            fontSize: 10.0 * factor, isBold: false),
        const SizedBox(height: 8),
        _buildCenterText('FIRMA CLIENTE / RETIRA:',
            fontSize: 10.0 * factor, isBold: false),
        const SizedBox(height: 24),
        _buildCenterText('____________________________',
            fontSize: 10.0 * factor, isBold: false),
      ],
    );
  }

  Widget _buildDeliveryItemRow(dynamic rawItem, double factor) {
    String name = 'PRODUCTO';
    double quantity = 1.0;
    bool isSoldByWeight = false;

    if (rawItem is CartItem) {
      name = rawItem.product.name;
      quantity = rawItem.quantity;
      isSoldByWeight = rawItem.product.isSoldByWeight;
    } else if (rawItem is Map<String, dynamic>) {
      final prod = rawItem['product'] as Map<String, dynamic>? ?? {};
      name = rawItem['product_name']?.toString() ??
          prod['name']?.toString() ??
          rawItem['name']?.toString() ??
          'PRODUCTO';
      quantity = double.tryParse(rawItem['quantity']?.toString() ?? '1') ?? 1.0;
      isSoldByWeight = rawItem['is_sold_by_weight'] == true ||
          prod['is_sold_by_weight'] == true;
    }

    final qtyStr = isSoldByWeight
        ? '${quantity.toQty()} kg'
        : '${quantity.toInt()} un';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              name.toUpperCase(),
              softWrap: true,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5 * factor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            qtyStr,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5 * factor,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS DE RENDERIZADO VISUAL
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCenterText(
    String text, {
    required double fontSize,
    bool isBold = false,
  }) {
    return Text(
      text,
      textAlign: TextAlign.center,
      softWrap: true,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        color: Colors.black,
      ),
    );
  }

  Widget _buildMultilineTextRow(
    String label,
    String value, {
    required double factor,
    bool isBold = false,
    double fontSize = 10.0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize * factor,
            color: Colors.black,
            height: 1.25,
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        softWrap: true,
        textAlign: TextAlign.left,
      ),
    );
  }

  Widget _buildKeyValueRow(
    String key,
    String value, {
    required double factor,
    bool isBold = false,
    double fontSize = 10.5,
  }) {
    final cleanTrim = value.trim();
    if (cleanTrim.length > 24 &&
        !cleanTrim.startsWith(r'$') &&
        !cleanTrim.startsWith('-')) {
      return _buildMultilineTextRow(key, value,
          factor: factor, isBold: isBold, fontSize: fontSize);
    }

    final isShortKey = key.trim().length <= 10;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxValRatio = isShortKey ? 0.66 : 0.45;
          final maxValWidth =
              (constraints.maxWidth * maxValRatio).clamp(36.0, 240.0);
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  key,
                  softWrap: true,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: fontSize * factor,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxValWidth),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: fontSize * factor,
                      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDivider({double thickness = 1.0}) {
    return Divider(
      height: 4.0,
      thickness: thickness,
      color: Colors.black54,
    );
  }
}
