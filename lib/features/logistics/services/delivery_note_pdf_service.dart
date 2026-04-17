import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Genera el PDF del Remito de Entrega en A4 con diseño profesional.
class DeliveryNotePdfService {
  static final _dateFmt = DateFormat('dd/MM/yyyy');

  // ─── Paleta de colores corporativa (naranja logística) ───────────────
  static const _primary   = PdfColor.fromInt(0xFF1A4B8C); // azul corporativo
  static const _accent    = PdfColor.fromInt(0xFFE65100); // naranja entrega
  static const _bgLight   = PdfColor.fromInt(0xFFF5F7FA);
  static const _textGrey  = PdfColor.fromInt(0xFF6B7280);
  static const _greenOk   = PdfColor.fromInt(0xFF2E7D32);
  static const _redPend   = PdfColor.fromInt(0xFFC62828);

  // ─── API principal ────────────────────────────────────────────────────

  /// Genera y muestra el visor PDF dentro de la app (preview real con botón imprimir).
  static Future<void> preview({
    required BuildContext context,
    required Map<String, dynamic> note,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessTaxId,
    /// Mapa de itemId → cantidad entregada en este despacho (puede ser vacío para el comprobante inicial).
    Map<int, double> deliveredNow = const {},
  }) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      pageBuilder: (ctx, _, __) {
        return Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              width: 860,
              height: MediaQuery.of(ctx).size.height * 0.92,
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Barra superior
                  Container(
                    color: const Color(0xFF1A4B8C),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping, color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            (deliveredNow.values.fold(0.0, (s, v) => s + v) > 0)
                                ? 'Remito N° ${note['id'].toString().padLeft(6, '0')} — Vista Previa A4'
                                : 'Orden de Retiro N° ${note['id'].toString().padLeft(6, '0')} — Vista Previa A4',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  // Visor
                  Expanded(
                    child: PdfPreview(
                      allowPrinting: true,
                      allowSharing: true,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      pdfFileName: 'Remito_${note['id'].toString().padLeft(6,'0')}.pdf',
                      build: (_) async => _buildPdf(
                        note: note,
                        businessName: businessName,
                        businessAddress: businessAddress,
                        businessPhone: businessPhone,
                        businessTaxId: businessTaxId,
                        deliveredNow: deliveredNow,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Imprime directamente sin mostrar el visor (si showPreview=false).
  static Future<void> printDirect({
    required Map<String, dynamic> note,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessTaxId,
    Map<int, double> deliveredNow = const {},
  }) async {
    final bytes = await _buildPdf(
      note: note,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessTaxId: businessTaxId,
      deliveredNow: deliveredNow,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Remito_${note['id'].toString().padLeft(6, '0')}',
    );
  }

  /// Guarda el PDF en el directorio Documentos/Sistema_POS/Remitos.
  static Future<String> savePdf({
    required Map<String, dynamic> note,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessTaxId,
    Map<int, double> deliveredNow = const {},
  }) async {
    final bytes = await _buildPdf(
      note: note,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessTaxId: businessTaxId,
      deliveredNow: deliveredNow,
    );
    final docsDir = await getApplicationDocumentsDirectory();
    final remitosDir = Directory('${docsDir.path}${Platform.pathSeparator}Sistema_POS${Platform.pathSeparator}Remitos');
    if (!await remitosDir.exists()) await remitosDir.create(recursive: true);
    final file = File('${remitosDir.path}${Platform.pathSeparator}Remito_${note['id'].toString().padLeft(6,'0')}.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ─── Builder PDF ──────────────────────────────────────────────────────

  static Future<Uint8List> _buildPdf({
    required Map<String, dynamic> note,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessTaxId,
    Map<int, double> deliveredNow = const {},
  }) async {
    final doc = pw.Document();

    final noteId  = note['id']?.toString().padLeft(6, '0') ?? '000000';
    final items   = (note['items'] as List?) ?? [];
    final sale    = note['sale'] as Map<String, dynamic>? ?? {};
    final customer= sale['customer'] as Map<String, dynamic>?;
    final customerName = customer?['name'] as String?;
    final status  = note['status'] as String? ?? 'pending';
    final createdAt = note['created_at'] as String?;
    final DateTime createdDate = createdAt != null
        ? DateTime.tryParse(createdAt) ?? DateTime.now()
        : DateTime.now();

    // Total de bultos / unidades
    final int totalUnits = items.fold(0, (sum, item) {
      final qty = (item['quantity_purchased'] as num?)?.toDouble() ?? 0.0;
      return sum + (item['product']?['is_sold_by_weight'] == true ? 0 : qty.toInt());
    });

    final deliveredNowSum = deliveredNow.values.fold(0.0, (sum, val) => sum + val);
    final isDispatch = deliveredNowSum > 0;
    final documentTitle = isDispatch ? 'REMITO DE DESPACHO' : 'ORDEN DE RETIRO';
    final documentCode = isDispatch ? 'REM$noteId' : 'ORD$noteId';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 48),
        footer: (pw.Context ctx) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.grey300),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Remito generado el ${_dateFmt.format(DateTime.now())} - $businessName',
                  style: const pw.TextStyle(fontSize: 8, color: _textGrey),
                ),
                pw.Text(
                  'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: _textGrey, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        build: (pw.Context ctx) => [

          // ══ ENCABEZADO ══════════════════════════════════════════════════
          pw.Container(
            decoration: const pw.BoxDecoration(
              color: _primary,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // Datos de la empresa
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(businessName,
                        style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    if (businessAddress != null && businessAddress.isNotEmpty)
                      pw.Text(businessAddress, style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10)),
                    if (businessPhone != null && businessPhone.isNotEmpty)
                      pw.Text('Tel: $businessPhone', style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10)),
                    if (businessTaxId != null && businessTaxId.isNotEmpty)
                      pw.Text('CUIT: $businessTaxId', style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10)),
                  ],
                ),
                // REMITO + código de barras
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(documentTitle,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: isDispatch ? 24 : 22,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                        )),
                    pw.Text('N° $noteId', style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 13)),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      color: PdfColors.white,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      height: 35,
                      width: 130,
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: documentCode,
                        drawText: false,
                        color: PdfColors.black,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(documentCode, style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 9)),
                    pw.SizedBox(height: 4),
                    pw.Text('Fecha: ${_dateFmt.format(createdDate)}',
                        style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // ══ ESTADO + DATOS CLIENTE ═══════════════════════════════════════
          pw.Container(
            decoration: const pw.BoxDecoration(
              color: _bgLight,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            padding: const pw.EdgeInsets.all(12),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('CLIENTE', style: pw.TextStyle(fontSize: 9, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text(customerName ?? 'Consumidor Final',
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      if (sale['id'] != null)
                        pw.Text('Venta N°: ${sale['id'].toString().padLeft(6,'0')}',
                            style: const pw.TextStyle(fontSize: 10, color: _textGrey)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 24),
                // Badge de estado
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
                  ),
                  child: pw.Text(
                    _statusLabel(status),
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // ══ TABLA DE ÍTEMS ════════════════════════════════════════════════
          pw.Table(
            border: pw.TableBorder(
              bottom: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              horizontalInside: const pw.BorderSide(color: PdfColors.grey200, width: 0.5),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(5),
              1: const pw.FlexColumnWidth(1.8), // Cant. pedida
              2: const pw.FlexColumnWidth(2),   // Entregado hoy
              3: const pw.FlexColumnWidth(1.8), // Saldo
              4: const pw.FlexColumnWidth(2.5), // Estado
            },
            children: [
              // Encabezado
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _primary),
                repeat: true,
                children: [
                  _th('DESCRIPCIÓN'),
                  _th('CANT. TOTAL', align: pw.TextAlign.center),
                  _th('ENTREGADO HOY', align: pw.TextAlign.center),
                  _th('SALDO PEND.', align: pw.TextAlign.center),
                  _th('ESTADO', align: pw.TextAlign.center),
                ],
              ),
              // Filas de ítems
              ...items.asMap().entries.map((e) {
                final idx  = e.key;
                final item = e.value as Map<String, dynamic>;
                final product = item['product'] as Map<String, dynamic>? ?? {};
                final isByWeight = product['is_sold_by_weight'] == true;
                final totalQty    = (item['quantity_purchased']  as num?)?.toDouble() ?? 0.0;
                final deliveredQtyDb = (item['quantity_delivered'] as num?)?.toDouble() ?? 0.0;
                final deliveredQtyNow = deliveredNow[item['id']] ?? 0.0;
                final pendingQty  = (totalQty - deliveredQtyDb - deliveredQtyNow).clamp(0.0, double.infinity);
                final itemStatus  = item['status'] as String? ?? 'pending';

                String fmt(double v) => isByWeight
                    ? '${v.toStringAsFixed(3)} kg'
                    : '${v.toInt()} un';

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: idx % 2 == 0 ? PdfColors.white : _bgLight,
                  ),
                  children: [
                    _td(product['name']?.toString().toUpperCase() ?? '-', bold: true),
                    _td(fmt(totalQty), align: pw.TextAlign.center),
                    _td(deliveredQtyNow > 0 ? fmt(deliveredQtyNow) : '-', align: pw.TextAlign.center,
                        color: deliveredQtyNow > 0 ? _greenOk : _textGrey),
                    _td(pendingQty > 0 ? fmt(pendingQty) : '-', align: pw.TextAlign.center,
                        color: pendingQty > 0 ? _redPend : _greenOk),
                    _tdBadge(_statusLabel(itemStatus), _statusColor(itemStatus)),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 20),

          // ══ RESUMEN / FIRMA ════════════════════════════════════════════════
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Nota de instrucción
              pw.Expanded(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _accent, width: 1),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('! INSTRUCCIONES DE ENTREGA',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _accent)),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Presente este comprobante al retirar la mercadería en depósito. '
                        'El operador escaneará el código de barras o buscará por N° de Remito. '
                        'Solo se entregarán los artículos indicados y en las cantidades autorizadas.',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      if (totalUnits > 0) ...[
                        pw.SizedBox(height: 8),
                        pw.Text('Total de unidades: $totalUnits',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 24),
              // Firma del receptor
              pw.Container(
                width: 200,
                decoration: const pw.BoxDecoration(
                  color: _bgLight,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                padding: const pw.EdgeInsets.all(12),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('FIRMA Y ACLARACIÓN DEL RECEPTOR',
                        style: pw.TextStyle(fontSize: 8, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 32),
                    pw.Divider(color: PdfColors.grey500, thickness: 0.5),
                    pw.SizedBox(height: 4),
                    pw.Text('DNI:', style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
                    pw.SizedBox(height: 16),
                    pw.Divider(color: PdfColors.grey400, thickness: 0.5),
                    pw.SizedBox(height: 4),
                    pw.Text('Fecha de retiro:', style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 16),
          // ══ PIE INFORMATIVO ════════════════════════════════════════════════
          pw.Center(
            child: pw.Text(
              'DOCUMENTO NO VALIDO COMO FACTURA - SOLO SIRVE COMO COMPROBANTE DE ENTREGA DE MERCADERIA',
              style: pw.TextStyle(fontSize: 8, color: _textGrey, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  static String _statusLabel(String status) {
    switch (status) {
      case 'pending': return 'PENDIENTE';
      case 'partial': return 'PARCIAL';
      case 'delivered': return 'ENTREGADO';
      default: return status.toUpperCase();
    }
  }

  static PdfColor _statusColor(String status) {
    switch (status) {
      case 'pending': return _accent;
      case 'partial': return const PdfColor.fromInt(0xFFF57F17);
      case 'delivered': return _greenOk;
      default: return _textGrey;
    }
  }

  static pw.Widget _th(String text, {pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Text(text,
            style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold),
            textAlign: align),
      );

  static pw.Widget _td(String text,
      {pw.TextAlign align = pw.TextAlign.left, bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(text,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
            textAlign: align),
      );

  static pw.Widget _tdBadge(String text, PdfColor color) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Text(text,
                style: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold)),
          ),
        ),
      );
}
