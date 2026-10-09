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
/// Soporta tanto tickets fiscales (AFIP/ARCA RG 1415 & 4892 con CAE, Vto, QR)
/// como comprobantes estándar no fiscales y remitos de entrega / retiro.
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
  final double surchargeAmount;
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
    this.surchargeAmount = 0.0,
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

  @override
  Widget build(BuildContext context) {
    final width = paperWidth.logicalWidth;
    final padding = paperWidth.innerPadding;
    final factor = paperWidth.fontSizeFactor;
    final isFiscal = electronicInvoice != null;
    final date = dateTime ?? DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(date);

    return Container(
      width: width,
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 12.0),
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
            fontSize: 14.0 * factor,
            isBold: true,
          ),
          if (businessSettings?.address != null &&
              businessSettings!.address!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            _buildCenterText(
              businessSettings!.address!.trim(),
              fontSize: 10.5 * factor,
            ),
          ],
          if (businessSettings?.taxId != null &&
              businessSettings!.taxId!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            _buildCenterText(
              'CUIT: ${businessSettings!.taxId!.trim()}',
              fontSize: 10.5 * factor,
              isBold: true,
            ),
          ],
          if (businessSettings?.phone != null &&
              businessSettings!.phone!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            _buildCenterText(
              'Tel: ${businessSettings!.phone!.trim()}',
              fontSize: 10.5 * factor,
            ),
          ],
          const SizedBox(height: 4),
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

          const SizedBox(height: 4),
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
          ] else if (customerName != null &&
              customerName!.isNotEmpty &&
              customerName != 'Consumidor Final') ...[
            _buildKeyValueRow(
              'CLIENTE:',
              customerName!.toUpperCase(),
              factor: factor,
              isBold: true,
            ),
          ],

          const SizedBox(height: 4),
          _buildDivider(),

          // ── 5. Detalle de Ítems Vendidos ──
          ..._buildItemsList(factor),

          const SizedBox(height: 4),
          _buildDivider(thickness: 1.5),

          // ── 6. Resumen Financiero y Métodos de Pago ──
          _buildFinancialSummary(factor),

          // ── 7. Pie Fiscal AFIP (o Leyenda No Fiscal) ──
          if (isFiscal) ...[
            _buildFiscalFooter(factor),
          ] else ...[
            const SizedBox(height: 4),
            _buildDivider(),
            _buildCenterText(
              '*** NO VALIDO COMO FACTURA ***',
              fontSize: 10.0 * factor,
              isBold: true,
            ),
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
  // COMPONENTES FISCALES AFIP
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFiscalVoucherHeader(double factor) {
    final invoice = electronicInvoice!;
    final letter = invoice['voucher_letter']?.toString().toUpperCase() ?? 'B';
    final nro = invoice['formatted_number']?.toString() ??
        invoice['voucher_number']?.toString() ??
        (saleNumber ?? '00001');
    final pv = invoice['point_of_sale']?.toString().padLeft(5, '0') ?? '00001';
    final vType = int.tryParse(invoice['voucher_type']?.toString() ?? '0') ?? 0;
    final isNotaCredito = [3, 8, 13, 113].contains(vType);
    final tipoComp = isNotaCredito ? 'NOTA DE CREDITO' : 'FACTURA';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCenterText(
          '$tipoComp $letter Nro $nro',
          fontSize: 13.5 * factor,
          isBold: true,
        ),
        const SizedBox(height: 2),
        _buildCenterText(
          'PUNTO DE VENTA: $pv',
          fontSize: 10.5 * factor,
        ),
      ],
    );
  }

  Widget _buildFiscalReceiverInfo(double factor) {
    final invoice = electronicInvoice!;
    final recName = invoice['receiver_name']?.toString() ??
        customerName ??
        'CONSUMIDOR FINAL';
    final recDoc = invoice['doc_number']?.toString() ?? '---';
    final recCond = (invoice['receiver_tax_condition']?.toString() ??
            'CONSUMIDOR FINAL')
        .toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildKeyValueRow('CLIENTE:', recName.toUpperCase(), factor: factor),
        _buildKeyValueRow('DOC:', recDoc, factor: factor),
        _buildKeyValueRow('IVA:', recCond, factor: factor),
      ],
    );
  }

  Widget _buildFiscalFooter(double factor) {
    final invoice = electronicInvoice!;
    final netAmount = invoice['net_amount'];
    final ivaAmount = invoice['iva_amount'];
    final cae = invoice['cae']?.toString() ?? '';
    final caeVto = invoice['cae_expiration']?.toString() ?? '';
    final qrData = invoice['qr_data']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Desglose de IVA si existe (Factura A o B)
        if (netAmount != null && ivaAmount != null) ...[
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

        const SizedBox(height: 6),
        _buildDivider(),

        if (cae.isNotEmpty) ...[
          const SizedBox(height: 2),
          _buildCenterText(
            'CAE: $cae',
            fontSize: 11.5 * factor,
            isBold: true,
          ),
          const SizedBox(height: 2),
          _buildCenterText(
            'VTO. CAE: $caeVto',
            fontSize: 11.5 * factor,
            isBold: true,
          ),
          const SizedBox(height: 6),
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

  // ─────────────────────────────────────────────────────────────────────────
  // DETALLE DE ÍTEMS CON PROTECCIÓN DEFENSIVA OVERFLOW
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildItemsList(double factor) {
    final widgets = <Widget>[];

    for (final rawItem in items) {
      String name = 'PRODUCTO';
      double quantity = 1.0;
      double unitPrice = 0.0;
      double subtotal = 0.0;
      bool isSoldByWeight = false;

      if (rawItem is CartItem) {
        name = rawItem.product.name;
        quantity = rawItem.quantity;
        unitPrice = rawItem.product.sellingPrice;
        subtotal = rawItem.subtotal;
        isSoldByWeight = rawItem.product.isSoldByWeight;
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
      }

      final qtyStr = isSoldByWeight
          ? '${quantity.toQty()} kg'
          : '${quantity.toInt()} un';

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Fila 1: Cantidad x Precio Unitario a la izquierda, Subtotal a la derecha
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '$qtyStr x \$${_formatPrice(unitPrice)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10.5 * factor,
                        color: Colors.black87,
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
              // Fila 2: Nombre de producto con wrap dinámico (cero overflow)
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

    final grandTotal = total + surchargeAmount;
    final hasSurcharge = surchargeAmount > 0.01;
    final hasShipping = shippingCost > 0.01;
    final hasMultiplePayments = payments.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasMultiplePayments ||
            hasSurcharge ||
            hasShipping ||
            hasPerception) ...[
          _buildKeyValueRow(
            'SUBTOTAL:',
            '\$${_formatPrice(total - shippingCost)}',
            factor: factor,
          ),
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

        if (tenderedAmount > 0.01) ...[
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
    final address = note['sale']?['delivery_address']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDivider(thickness: 2),
        const SizedBox(height: 4),
        _buildCenterText(
          businessSettings?.companyName?.toUpperCase() ?? 'MI NEGOCIO',
          fontSize: 13.0 * factor,
          isBold: true,
        ),
        const SizedBox(height: 2),
        _buildCenterText(
          'ORDEN DE RETIRO / REMITO',
          fontSize: 12.0 * factor,
          isBold: true,
        ),
        if (noteId.isNotEmpty)
          _buildCenterText('REMITO N°: ${noteId.padLeft(6, '0')}',
              fontSize: 10.5 * factor, isBold: true),
        if (saleNumber != null)
          _buildCenterText('VENTA ASOC: ${saleNumber!.padLeft(6, '0')}',
              fontSize: 10.0 * factor),
        const SizedBox(height: 4),
        _buildDivider(),
        if (customerName != null && customerName!.isNotEmpty)
          _buildKeyValueRow('CLIENTE:', customerName!.toUpperCase(),
              factor: factor, isBold: true),
        if (address.trim().isNotEmpty)
          _buildKeyValueRow('ENTREGA:', address.toUpperCase(),
              factor: factor),
        const SizedBox(height: 4),
        _buildCenterText('ARTICULOS A RETIRAR',
            fontSize: 11.0 * factor, isBold: true),
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

  Widget _buildKeyValueRow(
    String key,
    String value, {
    required double factor,
    bool isBold = false,
    double fontSize = 10.5,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
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
          Flexible(
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
      ),
    );
  }

  Widget _buildDivider({double thickness = 1.0}) {
    return Divider(
      height: 6.0,
      thickness: thickness,
      color: Colors.black54,
    );
  }
}
