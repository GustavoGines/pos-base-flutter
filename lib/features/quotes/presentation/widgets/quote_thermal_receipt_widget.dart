import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:barcode/barcode.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';

/// Widget visual interactivo para renderizar la vista previa de un Presupuesto
/// en formato de papel térmico (58mm u 80mm) con estilo ARCA / Comercial idéntico
/// a los tickets emitidos por la impresora física.
class QuoteThermalReceiptWidget extends StatelessWidget {
  final ThermalPaperWidth paperWidth;
  final Quote quote;
  final BusinessSettings? businessSettings;
  final String vendorName;

  const QuoteThermalReceiptWidget({
    super.key,
    this.paperWidth = ThermalPaperWidth.mm80,
    required this.quote,
    this.businessSettings,
    required this.vendorName,
  });

  String _formatPrice(double value) {
    return NumberFormat.currency(
      locale: 'es_AR',
      symbol: '',
      decimalDigits: 2,
    ).format(value).trim();
  }

  String _formatCuit(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 10)}-${digits.substring(10)}';
    }
    return raw.trim();
  }

  String _resolveIssuerTaxCondition() {
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
        return rawCond.isNotEmpty
            ? rawCond.toUpperCase()
            : 'IVA RESPONSABLE INSCRIPTO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = paperWidth.logicalWidth;
    final padding = paperWidth.innerPadding;
    final factor = paperWidth.fontSizeFactor;
    final is58mm = paperWidth == ThermalPaperWidth.mm58;

    final emissionDate = quote.createdAt != null
        ? (DateTime.tryParse(quote.createdAt!)?.toLocal() ?? DateTime.now())
        : DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(emissionDate);

    String validUntilFormatted = '7 DÍAS';
    if (quote.validUntil != null && quote.validUntil!.trim().isNotEmpty) {
      final parsedValid = DateTime.tryParse(quote.validUntil!.trim());
      validUntilFormatted = parsedValid != null
          ? DateFormat('dd/MM/yyyy').format(parsedValid)
          : quote.validUntil!.trim();
    }

    final resolvedCustomer =
        (quote.customerName != null && quote.customerName!.trim().isNotEmpty)
            ? quote.customerName!.trim().toUpperCase()
            : 'CONSUMIDOR FINAL';

    final sanitizedNotes = quote.notes
        ?.replaceAll(
          RegExp(
            r'\s*-\s*V[aá]lido\s+\d+\s+d[ií]as\s+con\s+precio\s+congelado\.?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\s*con\s+precio\s+congelado\.?', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s*precio\s+congelado\.?', caseSensitive: false),
          '',
        )
        .trim();

    final cleanBarcode = quote.quoteNumber
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\-\.\ \$\/\+\%]'), '');

    int totalItemsQty = 0;
    for (final item in quote.items) {
      final isWeight =
          item.product?.isSoldByWeight ?? (item.quantity % 1 != 0);
      if (!isWeight) {
        totalItemsQty += item.quantity.toInt();
      } else {
        totalItemsQty += 1;
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Encabezado de la Empresa ──────────────────────────────────
          _buildCenterText(
            businessSettings?.companyName?.toUpperCase() ?? 'MI NEGOCIO',
            fontSize: 13.5 * factor,
            isBold: true,
          ),
          if (businessSettings?.address != null &&
              businessSettings!.address!.trim().isNotEmpty) ...[
            const SizedBox(height: 1.5),
            _buildCenterText(
              businessSettings!.address!.trim(),
              fontSize: 10.0 * factor,
            ),
          ],
          if (businessSettings?.taxId != null &&
              businessSettings!.taxId!.trim().isNotEmpty) ...[
            const SizedBox(height: 1.5),
            _buildCenterText(
              'CUIT: ${_formatCuit(businessSettings!.taxId!)}',
              fontSize: 10.0 * factor,
              isBold: true,
            ),
          ],
          if (businessSettings?.iibb != null &&
              businessSettings!.iibb!.trim().isNotEmpty) ...[
            const SizedBox(height: 1),
            _buildCenterText(
              'Ing. Brutos: ${_formatCuit(businessSettings!.iibb!.trim())}',
              fontSize: 9.2 * factor,
            ),
          ],
          if (businessSettings?.activityStartDate != null &&
              businessSettings!.activityStartDate!.trim().isNotEmpty) ...[
            const SizedBox(height: 1),
            _buildCenterText(
              'Inicio Act.: ${businessSettings!.activityStartDate!.trim()}',
              fontSize: 9.2 * factor,
            ),
          ],
          if (businessSettings?.phone != null &&
              businessSettings!.phone!.trim().isNotEmpty) ...[
            const SizedBox(height: 1),
            _buildCenterText(
              'Tel: ${businessSettings!.phone!.trim()}',
              fontSize: 9.5 * factor,
            ),
          ],
          if (businessSettings?.taxCondition != null &&
              businessSettings!.taxCondition!.trim().isNotEmpty) ...[
            const SizedBox(height: 1.5),
            _buildCenterText(
              _resolveIssuerTaxCondition(),
              fontSize: 9.5 * factor,
              isBold: true,
            ),
          ],
          const SizedBox(height: 3),
          _buildDivider(thickness: 1.8),

          // ── 2. Tipo y Número de Comprobante ───────────────────────────────
          _buildCenterText(
            'PRESUPUESTO (X)',
            fontSize: 13.0 * factor,
            isBold: true,
          ),
          const SizedBox(height: 1.5),
          _buildCenterText(
            'Nro: ${quote.quoteNumber}',
            fontSize: 11.5 * factor,
            isBold: true,
          ),
          const SizedBox(height: 1.5),
          _buildCenterText(
            '*** NO VALIDO COMO FACTURA ***',
            fontSize: 9.8 * factor,
            isBold: true,
          ),
          const SizedBox(height: 3),
          _buildDivider(),

          // ── 3. Metadatos (Fecha, Validez, Vendedor, Cliente) ─────────────
          _buildKeyValueRow('FECHA:', formattedDate, factor: factor),
          _buildKeyValueRow('VALIDO HASTA:', validUntilFormatted, factor: factor),
          _buildKeyValueRow(
            'VENDEDOR:',
            vendorName.toUpperCase(),
            factor: factor,
          ),
          if (is58mm || resolvedCustomer.length > 18)
            _buildMultilineTextRow(
              'CLIENTE:',
              resolvedCustomer,
              factor: factor,
              isBold: resolvedCustomer != 'CONSUMIDOR FINAL',
            )
          else
            _buildKeyValueRow(
              'CLIENTE:',
              resolvedCustomer,
              factor: factor,
              isBold: resolvedCustomer != 'CONSUMIDOR FINAL',
            ),
          if (quote.customerPhone != null &&
              quote.customerPhone!.trim().isNotEmpty)
            _buildKeyValueRow(
              'TEL CLIENTE:',
              quote.customerPhone!.trim(),
              factor: factor,
            ),
          _buildKeyValueRow(
            'COND. VENTA:',
            quote.priceListLabel.toUpperCase(),
            factor: factor,
            isBold: true,
          ),
          const SizedBox(height: 3),
          _buildDivider(),

          // ── 4. Detalle de Artículos Cotizados ─────────────────────────────
          for (final item in quote.items) ...[
            _buildItemRow(item, factor),
          ],
          const SizedBox(height: 3),
          _buildDivider(thickness: 1.8),

          // ── 5. Subtotal y Totales ─────────────────────────────────────────
          _buildKeyValueRow(
            'SUBTOTAL:',
            '\$${_formatPrice(quote.subtotal)}',
            factor: factor,
          ),
          _buildDivider(),
          _buildKeyValueRow(
            is58mm ? 'TOTAL:' : 'TOTAL PRESUPUESTO:',
            '\$${_formatPrice(quote.total)}',
            factor: factor,
            isBold: true,
            fontSize: 12.0,
          ),
          const SizedBox(height: 2),
          _buildKeyValueRow(
            is58mm ? 'UNIDADES:' : 'UNIDADES COTIZADAS:',
            '$totalItemsQty',
            factor: factor,
            isBold: true,
          ),
          _buildDivider(),

          // ── 6. Observaciones (si existen) ─────────────────────────────────
          if (sanitizedNotes != null && sanitizedNotes.isNotEmpty) ...[
            Text(
              'OBSERVACIONES:',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9.8 * factor,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              sanitizedNotes,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9.2 * factor,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 3),
            _buildDivider(),
          ],

          // ── 7. Código de Barras del Presupuesto ────────────────────────────
          if (cleanBarcode.isNotEmpty) ...[
            const SizedBox(height: 6),
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: is58mm ? 160.0 : 210.0,
                height: 48.0,
                child: CustomPaint(
                  painter: _BarcodePainter(
                    barcode: Barcode.code39(),
                    data: cleanBarcode,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            _buildCenterText(
              cleanBarcode,
              fontSize: 10.0 * factor,
              isBold: true,
            ),
            const SizedBox(height: 6),
          ],

          // ── 8. Pie Legal ──────────────────────────────────────────────────
          _buildCenterText(
            'Precios sujetos a variación sin previo aviso.',
            fontSize: 8.8 * factor,
          ),
          const SizedBox(height: 1),
          _buildCenterText(
            '*** NO VALIDO COMO FACTURA ***',
            fontSize: 9.5 * factor,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(QuoteItem item, double factor) {
    final isWeight = item.product?.isSoldByWeight ?? (item.quantity % 1 != 0);
    final cantStr = isWeight
        ? '${item.quantity.toQty()} kg'
        : (item.quantity % 1 == 0
            ? '${item.quantity.toInt()} un'
            : '${item.quantity.toQty()} un');

    final rawCode = item.product?.internalCode.trim() ?? '';
    final codePrefix = rawCode.isNotEmpty ? '[$rawCode] ' : '';
    final name = '$codePrefix${item.productName}'.toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Línea 1: Código + Descripción
          Text(
            name,
            softWrap: true,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.2 * factor,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 1.5),
          // Línea 2: [CANT x $UNIT] a la izq y [$SUBTOTAL] a la der
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$cantStr x \$${_formatPrice(item.unitPrice)}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.0 * factor,
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
                    '\$${_formatPrice(item.subtotal)}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.8 * factor,
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
    );
  }

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
    double fontSize = 10.2,
  }) {
    final cleanTrim = value.trim();
    if (cleanTrim.length > 22 &&
        !cleanTrim.startsWith(r'$') &&
        !cleanTrim.startsWith('-')) {
      return _buildMultilineTextRow(
        key,
        value,
        factor: factor,
        isBold: isBold,
        fontSize: fontSize,
      );
    }

    final isShortKey = key.trim().length <= 10;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxValRatio = isShortKey ? 0.68 : 0.48;
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

class _BarcodePainter extends CustomPainter {
  final Barcode barcode;
  final String data;
  static const Color color = Colors.black;

  _BarcodePainter({
    required this.barcode,
    required this.data,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    try {
      for (final element in barcode.make(data, width: size.width, height: size.height)) {
        if (element is BarcodeBar && element.black) {
          canvas.drawRect(
            Rect.fromLTWH(element.left, element.top, element.width, element.height),
            paint,
          );
        }
      }
    } catch (_) {}
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) =>
      oldDelegate.data != data;
}
