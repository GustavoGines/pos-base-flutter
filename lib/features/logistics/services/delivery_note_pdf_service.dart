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
  static const _primary   = PdfColor.fromInt(0xFFE65100); // naranja entrega
  static const _accent    = PdfColor.fromInt(0xFF1A4B8C); // azul corporativo
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
    String? vendorName,
    String? dispatcherName,
    String paperSize = 'a4',
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
                    color: const Color(0xFFE65100),
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
                        vendorName: vendorName,
                        dispatcherName: dispatcherName,
                        paperSize: paperSize,
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
    String? vendorName,
    String? dispatcherName,
    String paperSize = 'a4',
  }) async {
    final bytes = await _buildPdf(
      note: note,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessTaxId: businessTaxId,
      deliveredNow: deliveredNow,
      vendorName: vendorName,
      dispatcherName: dispatcherName,
      paperSize: paperSize,
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
    String? vendorName,
    String? dispatcherName,
    String paperSize = 'a4',
  }) async {
    final bytes = await _buildPdf(
      note: note,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessTaxId: businessTaxId,
      deliveredNow: deliveredNow,
      vendorName: vendorName,
      dispatcherName: dispatcherName,
      paperSize: paperSize,
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
    String? vendorName,
    String? dispatcherName,
    String paperSize = 'a4',
  }) async {
    pw.ThemeData? theme;
    try {
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: font, bold: fontBold);
    } catch (_) {}

    final doc = pw.Document(theme: theme);

    final noteId  = note['id']?.toString().padLeft(6, '0') ?? '000000';
    final items   = (note['items'] as List?) ?? [];
    final sale    = note['sale'] as Map<String, dynamic>? ?? {};
    final customer= sale['customer'] as Map<String, dynamic>?;
    final customerName = customer?['name'] as String?;
    final createdAt = note['created_at'] as String?;
    final DateTime createdDate = createdAt != null
        ? DateTime.tryParse(createdAt) ?? DateTime.now()
        : DateTime.now();

    // Total de bultos / unidades
    final int totalUnits = items.fold(0, (sum, item) {
      final qty = double.tryParse(item['quantity_purchased']?.toString() ?? '') ?? 0.0;
      return sum + (item['product']?['is_sold_by_weight'] == true ? 0 : qty.toInt());
    });

    final deliveredNowSum = deliveredNow.values.fold(0.0, (sum, val) => sum + val);
    final isAlreadyDispatched = note['status'] == 'partial' || note['status'] == 'delivered';
    // Es remito de despacho si estamos entregando ahora o si ya se entregó mercadería en el pasado
    final isDispatch = deliveredNowSum > 0 || isAlreadyDispatched;
    
    // Calcular estado proyectado del documento
    double totalPendingAfter = 0.0;
    double totalDeliveredAfter = 0.0;
    for (final item in items) {
      final it = item as Map<String, dynamic>;
      final tq = double.tryParse(it['quantity_purchased']?.toString() ?? '') ?? 0.0;
      final dqDb = double.tryParse(it['quantity_delivered']?.toString() ?? '') ?? 0.0;
      final dqNow = deliveredNow[it['id']] ?? 0.0;
      totalDeliveredAfter += (dqDb + dqNow);
      totalPendingAfter += (tq - dqDb - dqNow).clamp(0.0, double.infinity);
    }
    
    String effectiveDocStatus = 'pending';
    if (totalPendingAfter <= 0 && totalDeliveredAfter > 0) {
      effectiveDocStatus = 'delivered';
    } else if (totalPendingAfter > 0 && totalDeliveredAfter > 0) {
      effectiveDocStatus = 'partial';
    }

    final documentTitle = isDispatch ? 'REMITO DE DESPACHO' : 'ORDEN DE RETIRO';
    final documentCode = isDispatch ? 'REM$noteId' : 'ORD$noteId';

    final bool isSmallOrder = items.length <= 5;
    final format = paperSize.toLowerCase() == 'letter' ? PdfPageFormat.letter : PdfPageFormat.a4;

    if (isSmallOrder) {
      // ── RUTA A: AHORRO DE PAPEL (A4 SPLIT) ──
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) {
            final copyLabelTop = isDispatch ? 'COPIA\nCLIENTE' : 'ORIGINAL';
            final copyLabelBot = isDispatch ? 'COPIA\nDESPACHANTE' : 'DUPLICADO';
            return pw.Column(
              children: [
                // MITAD SUPERIOR
                pw.Expanded(
                  child: pw.Stack(
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          ..._buildContentList(
                            businessName: businessName, businessAddress: businessAddress, businessPhone: businessPhone, businessTaxId: businessTaxId,
                            documentTitle: documentTitle, noteId: noteId, documentCode: documentCode, createdDate: createdDate, customerName: customerName,
                            sale: sale, vendorName: vendorName, dispatcherName: dispatcherName, effectiveDocStatus: effectiveDocStatus,
                            isDispatch: isDispatch, items: items, deliveredNow: deliveredNow, totalUnits: totalUnits, isCompact: true,
                            copyLabel: copyLabelTop,
                          ),
                          pw.Spacer(),
                          _buildFooter(ctx, businessName, isCompact: true),
                        ],
                      ),
                      _buildWatermark(copyLabelTop, true),
                    ],
                  ),
                ),

                // DIVISOR
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Row(
                    children: [
                      pw.Text('CORTAR AQUÍ', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                      pw.SizedBox(width: 8),
                      pw.Expanded(child: pw.Divider(color: PdfColors.grey500, borderStyle: pw.BorderStyle.dashed)),
                    ],
                  ),
                ),

                // MITAD INFERIOR
                pw.Expanded(
                  child: pw.Stack(
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          ..._buildContentList(
                            businessName: businessName, businessAddress: businessAddress, businessPhone: businessPhone, businessTaxId: businessTaxId,
                            documentTitle: documentTitle, noteId: noteId, documentCode: documentCode, createdDate: createdDate, customerName: customerName,
                            sale: sale, vendorName: vendorName, dispatcherName: dispatcherName, effectiveDocStatus: effectiveDocStatus,
                            isDispatch: isDispatch, items: items, deliveredNow: deliveredNow, totalUnits: totalUnits, isCompact: true,
                            copyLabel: copyLabelBot,
                          ),
                          pw.Spacer(),
                          _buildFooter(ctx, businessName, isCompact: true),
                        ],
                      ),
                      _buildWatermark(copyLabelBot, true),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    } else {
      // ── RUTA B: PEDIDO MAYORISTA (PÁGINAS COMPLETAS) ──
      final copyLabelFull1 = isDispatch ? 'COPIA\nCLIENTE' : 'ORIGINAL';
      final copyLabelFull2 = isDispatch ? 'COPIA\nDESPACHANTE' : 'DUPLICADO';
      // Página 1
      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: format,
            margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 48),
            buildForeground: (ctx) => _buildWatermark(copyLabelFull1, false),
          ),
          footer: (pw.Context ctx) => _buildFooter(ctx, businessName),
          build: (pw.Context ctx) => _buildContentList(
            businessName: businessName, businessAddress: businessAddress, businessPhone: businessPhone, businessTaxId: businessTaxId,
            documentTitle: documentTitle, noteId: noteId, documentCode: documentCode, createdDate: createdDate, customerName: customerName,
            sale: sale, vendorName: vendorName, dispatcherName: dispatcherName, effectiveDocStatus: effectiveDocStatus,
            isDispatch: isDispatch, items: items, deliveredNow: deliveredNow, totalUnits: totalUnits, isCompact: false,
            copyLabel: copyLabelFull1,
          ),
        ),
      );
      // Página 2
      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: format,
            margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 48),
            buildForeground: (ctx) => _buildWatermark(copyLabelFull2, false),
          ),
          footer: (pw.Context ctx) => _buildFooter(ctx, businessName),
          build: (pw.Context ctx) => _buildContentList(
            businessName: businessName, businessAddress: businessAddress, businessPhone: businessPhone, businessTaxId: businessTaxId,
            documentTitle: documentTitle, noteId: noteId, documentCode: documentCode, createdDate: createdDate, customerName: customerName,
            sale: sale, vendorName: vendorName, dispatcherName: dispatcherName, effectiveDocStatus: effectiveDocStatus,
            isDispatch: isDispatch, items: items, deliveredNow: deliveredNow, totalUnits: totalUnits, isCompact: false,
            copyLabel: copyLabelFull2,
          ),
        ),
      );
    }

    return doc.save();
  }

  // ─── Helpers Paginación Inteligente ──────────────────────────────────
  
  static pw.Widget _buildWatermark(String text, bool isCompact) {
    return pw.Positioned.fill(
      child: pw.Center(
        child: pw.Opacity(
          opacity: 0.1, // 10% negro = gris sutil
          child: pw.Transform.rotateBox(
            angle: 0.6,
            child: pw.Text(
              text,
              style: pw.TextStyle(
                fontSize: isCompact ? 36 : 60,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context ctx, String businessName, {bool isCompact = false}) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.SizedBox(height: isCompact ? 4 : 8),
        pw.Divider(color: PdfColors.grey300),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Remito generado el ${_dateFmt.format(DateTime.now())} - $businessName',
              style: pw.TextStyle(fontSize: isCompact ? 6 : 7, color: PdfColors.grey),
            ),
            if (!isCompact)
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey),
              ),
          ],
        ),
      ],
    );
  }

  // ─── Contenido Principal del Remito ──────────────────────────────────
  static List<pw.Widget> _buildContentList({
    required String businessName, String? businessAddress, String? businessPhone, String? businessTaxId,
    required String documentTitle, required String noteId, required String documentCode, required DateTime createdDate,
    required String? customerName, required Map<String, dynamic> sale, String? vendorName, String? dispatcherName,
    required String effectiveDocStatus, required bool isDispatch, required List<dynamic> items,
    required Map<int, double> deliveredNow, required int totalUnits, required bool isCompact,
    String copyLabel = 'ORIGINAL',
  }) {
    return [
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
                        style: pw.TextStyle(color: PdfColors.white, fontSize: isCompact ? 16 : 20, fontWeight: pw.FontWeight.bold)),
                    if (businessAddress != null && businessAddress.isNotEmpty)
                      pw.Text(businessAddress, style: pw.TextStyle(color: PdfColors.grey300, fontSize: isCompact ? 8 : 10)),
                    if (businessPhone != null && businessPhone.isNotEmpty)
                      pw.Text('Tel: $businessPhone', style: pw.TextStyle(color: PdfColors.grey300, fontSize: isCompact ? 8 : 10)),
                    if (businessTaxId != null && businessTaxId.isNotEmpty)
                      pw.Text('CUIT: $businessTaxId', style: pw.TextStyle(color: PdfColors.grey300, fontSize: isCompact ? 8 : 10)),
                  ],
                ),
                // REMITO + código de barras
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(documentTitle,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: isCompact ? 14 : (isDispatch ? 24 : 22),
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                        )),
                    pw.Text('N° $noteId', style: pw.TextStyle(color: PdfColors.grey300, fontSize: isCompact ? 11 : 13)),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      color: PdfColors.white,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      height: isCompact ? 25 : 35,
                      width: isCompact ? 100 : 130,
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: documentCode,
                        drawText: false,
                        color: PdfColors.black,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(documentCode, style: pw.TextStyle(color: PdfColors.grey300, fontSize: isCompact ? 8 : 9)),
                    pw.SizedBox(height: 4),
                    pw.Text('Fecha: ${_dateFmt.format(createdDate)}',
                        style: pw.TextStyle(color: PdfColors.grey300, fontSize: isCompact ? 8 : 10)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: isCompact ? 8 : 16),

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
                if (vendorName != null || dispatcherName != null)
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (vendorName != null) ...[
                          pw.Text('VENDIÓ', style: pw.TextStyle(fontSize: 9, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 2),
                          pw.Text(vendorName.toUpperCase(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 8),
                        ],
                        if (dispatcherName != null) ...[
                          pw.Text('DESPACHÓ', style: pw.TextStyle(fontSize: 9, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 2),
                          pw.Text(dispatcherName.toUpperCase(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        ],
                      ],
                    ),
                  ),
                pw.SizedBox(width: 24),
                // Badge de estado
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: _statusColor(effectiveDocStatus),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
                  ),
                  child: pw.Text(
                    isDispatch ? _statusLabel(effectiveDocStatus) : 'A PREPARAR',
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
                  _th(deliveredNow.isNotEmpty ? 'ENTREGADO HOY' : 'ENTREGADO', align: pw.TextAlign.center),
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
                final totalQty    = double.tryParse(item['quantity_purchased']?.toString() ?? '') ?? 0.0;
                final deliveredQtyDb = double.tryParse(item['quantity_delivered']?.toString() ?? '') ?? 0.0;
                final deliveredQtyNow = deliveredNow[item['id']] ?? 0.0;
                final pendingQty  = (totalQty - deliveredQtyDb - deliveredQtyNow).clamp(0.0, double.infinity);
                
                String effectiveItemStatus = 'pending';
                if (pendingQty <= 0) {
                  effectiveItemStatus = 'delivered';
                } else if (deliveredQtyDb + deliveredQtyNow > 0) {
                  effectiveItemStatus = 'partial';
                }

                String fmt(double v) => isByWeight
                    ? '${v.toStringAsFixed(3)} kg'
                    : '${v.toInt()} un';

                final valToShow = deliveredNow.isNotEmpty ? deliveredQtyNow : deliveredQtyDb;

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: idx % 2 == 0 ? PdfColors.white : _bgLight,
                  ),
                  children: [
                    _td(product['name']?.toString().toUpperCase() ?? '-', bold: true),
                    _td(fmt(totalQty), align: pw.TextAlign.center),
                    _td(valToShow > 0 ? fmt(valToShow) : '-', align: pw.TextAlign.center,
                        color: valToShow > 0 ? _greenOk : _textGrey),
                    _td(pendingQty > 0 ? fmt(pendingQty) : '-', align: pw.TextAlign.center,
                        color: pendingQty > 0 ? _redPend : _greenOk),
                    _tdBadge(_statusLabel(effectiveItemStatus), _statusColor(effectiveItemStatus)),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: isCompact ? 10 : 20),

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
                  padding: pw.EdgeInsets.all(isCompact ? 8 : 12),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                          isDispatch ? '! INSTRUCCIONES DE RECEPCIÓN' : '! INSTRUCCIONES DE ENTREGA',
                          style: pw.TextStyle(fontSize: isCompact ? 7.5 : 9, fontWeight: pw.FontWeight.bold, color: _accent)),
                      pw.SizedBox(height: isCompact ? 4 : 6),
                      pw.Text(
                        isDispatch 
                          ? 'Por favor verifique que los artículos recibidos coincidan con las cantidades indicadas en este comprobante antes de firmar la conformidad.'
                          : 'Presente este comprobante al retirar la mercadería en depósito. El operador escaneará el código de barras o buscará por N° de Remito. Solo se entregarán los artículos indicados y en las cantidades autorizadas.',
                        style: pw.TextStyle(fontSize: isCompact ? 7 : 9),
                      ),
                      if (totalUnits > 0) ...[
                        pw.SizedBox(height: isCompact ? 4 : 8),
                        pw.Text('Total de unidades: $totalUnits',
                            style: pw.TextStyle(fontSize: isCompact ? 8 : 10, fontWeight: pw.FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: isCompact ? 12 : 24),
              // Firma del receptor
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    color: _bgLight,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  padding: pw.EdgeInsets.all(isCompact ? 8 : 12),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('FIRMA Y ACLARACIÓN DEL RECEPTOR',
                          style: pw.TextStyle(fontSize: 8, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: isCompact ? 20 : 32),
                      pw.Divider(color: PdfColors.grey500, thickness: 0.5),
                      pw.SizedBox(height: 4),
                      pw.Text('DNI:', style: pw.TextStyle(fontSize: isCompact ? 8 : 9, color: _textGrey)),
                      pw.SizedBox(height: isCompact ? 8 : 16),
                      pw.Divider(color: PdfColors.grey500, thickness: 0.5),
                      pw.SizedBox(height: 4),
                      pw.Text('Fecha de retiro:', style: pw.TextStyle(fontSize: isCompact ? 8 : 9, color: _textGrey)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: isCompact ? 8 : 16),
          // ══ PIE INFORMATIVO ════════════════════════════════════════════════
          pw.Center(
            child: pw.Text(
              'DOCUMENTO NO VALIDO COMO FACTURA - SOLO SIRVE COMO COMPROBANTE DE ENTREGA DE MERCADERIA',
              style: pw.TextStyle(fontSize: isCompact ? 7 : 8, color: _textGrey, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ];
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
