import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/utils/afip_fiscal_pdf_service.dart';
import '../../../core/utils/currency_formatter.dart';

/// Genera el PDF del Remito de Entrega / Orden de Retiro en A4 y Letter
/// con diseño técnico reglamentario estilo ARCA (Letra R / X).
class DeliveryNotePdfService {
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  static String _formatCuit(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 10)}-${digits.substring(10)}';
    }
    return raw.trim();
  }

  /// Genera y muestra el visor PDF dentro de la app (preview real con botón imprimir).
  static Future<void> preview({
    required BuildContext context,
    required Map<String, dynamic> note,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessTaxId,
    Map<int, double> deliveredNow = const {},
    String? vendorName,
    String? dispatcherName,
    String paperSize = 'a4',
    dynamic businessSettings,
    Uint8List? logoBytes,
  }) async {
    final paperLabel = paperSize.toLowerCase() == 'letter' ? 'Carta' : 'A4';
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      pageBuilder: (ctx, _, __) {
        return Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              width: 880,
              height: MediaQuery.of(ctx).size.height * 0.92,
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    color: Colors.grey.shade900,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_shipping,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            (deliveredNow.values.fold(0.0, (s, v) => s + v) > 0 ||
                                    note['status'] == 'partial' ||
                                    note['status'] == 'delivered')
                                ? 'Remito de Despacho N° ${note['id'].toString().padLeft(6, '0')} — Vista Previa $paperLabel'
                                : 'Orden de Retiro N° ${note['id'].toString().padLeft(6, '0')} — Vista Previa $paperLabel',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PdfPreview(
                      allowPrinting: true,
                      allowSharing: true,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      pdfFileName:
                          'Remito_${note['id'].toString().padLeft(6, '0')}.pdf',
                      build: (_) async => generatePdf(
                        note: note,
                        businessName: businessName,
                        businessAddress: businessAddress,
                        businessPhone: businessPhone,
                        businessTaxId: businessTaxId,
                        deliveredNow: deliveredNow,
                        vendorName: vendorName,
                        dispatcherName: dispatcherName,
                        paperSize: paperSize,
                        businessSettings: businessSettings,
                        logoBytes: logoBytes,
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
    dynamic businessSettings,
    Uint8List? logoBytes,
  }) async {
    final bytes = await generatePdf(
      note: note,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessTaxId: businessTaxId,
      deliveredNow: deliveredNow,
      vendorName: vendorName,
      dispatcherName: dispatcherName,
      paperSize: paperSize,
      businessSettings: businessSettings,
      logoBytes: logoBytes,
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
    dynamic businessSettings,
    Uint8List? logoBytes,
  }) async {
    final bytes = await generatePdf(
      note: note,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessTaxId: businessTaxId,
      deliveredNow: deliveredNow,
      vendorName: vendorName,
      dispatcherName: dispatcherName,
      paperSize: paperSize,
      businessSettings: businessSettings,
      logoBytes: logoBytes,
    );
    final docsDir = await getApplicationDocumentsDirectory();
    final remitosDir = Directory(
      '${docsDir.path}${Platform.pathSeparator}Sistema_POS${Platform.pathSeparator}Remitos',
    );
    if (!await remitosDir.exists()) await remitosDir.create(recursive: true);
    final file = File(
      '${remitosDir.path}${Platform.pathSeparator}Remito_${note['id'].toString().padLeft(6, '0')}.pdf',
    );
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Builder principal del PDF (público para previsualización, impresión y tests).
  static Future<Uint8List> generatePdf({
    required Map<String, dynamic> note,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessTaxId,
    Map<int, double> deliveredNow = const {},
    String? vendorName,
    String? dispatcherName,
    String paperSize = 'a4',
    dynamic businessSettings,
    Uint8List? logoBytes,
  }) async {
    final resolvedLogo = await AfipFiscalPdfService.resolveLogoBytes(
      logoBytes: logoBytes,
      businessSettings: businessSettings,
    );
    pw.ThemeData? theme;
    try {
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: font, bold: fontBold);
    } catch (_) {}

    final doc = pw.Document(theme: theme);

    final noteId = note['id']?.toString().padLeft(6, '0') ?? '000000';
    final items = (note['items'] as List?) ?? [];
    final sale = note['sale'] as Map<String, dynamic>? ?? {};
    final customer = sale['customer'] as Map<String, dynamic>?;
    final customerName =
        customer?['name'] as String? ?? sale['customer_name'] as String?;
    final customerDoc = customer?['document_number']?.toString() ??
        customer?['tax_id']?.toString() ??
        '---';
    final createdAt = note['created_at'] as String?;
    final DateTime createdDate = createdAt != null
        ? (DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now())
        : DateTime.now();

    final int totalUnits = items.fold(0, (sum, item) {
      final qty =
          double.tryParse(item['quantity_purchased']?.toString() ?? '') ?? 0.0;
      final isWeight = item['product']?['is_sold_by_weight'] == true ||
          item['is_sold_by_weight'] == true;
      return sum + (isWeight ? 0 : qty.toInt());
    });

    final deliveredNowSum =
        deliveredNow.values.fold(0.0, (sum, val) => sum + val);
    final isAlreadyDispatched =
        note['status'] == 'partial' || note['status'] == 'delivered';
    final isDispatch = deliveredNowSum > 0 || isAlreadyDispatched;

    double totalPendingAfter = 0.0;
    double totalDeliveredAfter = 0.0;
    for (final item in items) {
      final it = item as Map<String, dynamic>;
      final tq =
          double.tryParse(it['quantity_purchased']?.toString() ?? '') ?? 0.0;
      final dqDb =
          double.tryParse(it['quantity_delivered']?.toString() ?? '') ?? 0.0;
      final dqNow = deliveredNow[it['id']] ?? 0.0;
      final effectiveDelivered =
          deliveredNow.isNotEmpty ? (dqDb + dqNow) : dqDb;
      totalDeliveredAfter += effectiveDelivered;
      totalPendingAfter +=
          (tq - effectiveDelivered).clamp(0.0, double.infinity);
    }

    String effectiveDocStatus = 'pending';
    if (totalPendingAfter <= 0 && totalDeliveredAfter > 0) {
      effectiveDocStatus = 'delivered';
    } else if (totalPendingAfter > 0 && totalDeliveredAfter > 0) {
      effectiveDocStatus = 'partial';
    }

    final documentTitle =
        isDispatch ? 'REMITO DE DESPACHO' : 'ORDEN DE RETIRO';
    final documentCode = isDispatch ? 'REM$noteId' : 'ORD$noteId';

    final bool isSmallOrder = items.length <= 5;
    final format = paperSize.toLowerCase() == 'letter'
        ? PdfPageFormat.letter
        : PdfPageFormat.a4;

    if (isSmallOrder) {
      // RUTA A: AHORRO DE PAPEL (SPLIT EN 1 HOJA: ORIGINAL + DUPLICADO)
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(22),
          build: (pw.Context ctx) {
            final copyLabelTop = isDispatch
                ? 'ORIGINAL - COPIA CLIENTE'
                : 'ORIGINAL - ORDEN DE RETIRO';
            final copyLabelBot = isDispatch
                ? 'DUPLICADO - COPIA DESPACHANTE / CONFORMIDAD'
                : 'DUPLICADO - CONTROL DE DEPÓSITO';
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // MITAD SUPERIOR
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: _buildContentList(
                          businessName: businessName,
                          businessAddress: businessAddress,
                          businessPhone: businessPhone,
                          businessTaxId: businessTaxId,
                          documentTitle: documentTitle,
                          noteId: noteId,
                          documentCode: documentCode,
                          createdDate: createdDate,
                          customerName: customerName,
                          customerDoc: customerDoc,
                          sale: sale,
                          vendorName: vendorName,
                          dispatcherName: dispatcherName,
                          effectiveDocStatus: effectiveDocStatus,
                          isDispatch: isDispatch,
                          items: items,
                          deliveredNow: deliveredNow,
                          totalUnits: totalUnits,
                          isCompact: true,
                          copyLabel: copyLabelTop,
                          logoBytes: resolvedLogo,
                        ),
                      ),
                      _buildCompactFooter(businessName, createdDate),
                    ],
                  ),
                ),

                // LÍNEA DE CORTE
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        '--- CORTAR AQUÍ ---',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.grey700,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Divider(
                          color: PdfColors.grey600,
                          borderStyle: pw.BorderStyle.dashed,
                          thickness: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),

                // MITAD INFERIOR
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: _buildContentList(
                          businessName: businessName,
                          businessAddress: businessAddress,
                          businessPhone: businessPhone,
                          businessTaxId: businessTaxId,
                          documentTitle: documentTitle,
                          noteId: noteId,
                          documentCode: documentCode,
                          createdDate: createdDate,
                          customerName: customerName,
                          customerDoc: customerDoc,
                          sale: sale,
                          vendorName: vendorName,
                          dispatcherName: dispatcherName,
                          effectiveDocStatus: effectiveDocStatus,
                          isDispatch: isDispatch,
                          items: items,
                          deliveredNow: deliveredNow,
                          totalUnits: totalUnits,
                          isCompact: true,
                          copyLabel: copyLabelBot,
                          logoBytes: resolvedLogo,
                        ),
                      ),
                      _buildCompactFooter(businessName, createdDate),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    } else {
      // RUTA B: PEDIDO GRANDE (PÁGINAS COMPLETAS MULTIPAGE)
      final copyLabelFull1 = isDispatch
          ? 'ORIGINAL - COPIA CLIENTE'
          : 'ORIGINAL - ORDEN DE RETIRO';
      final copyLabelFull2 = isDispatch
          ? 'DUPLICADO - COPIA DESPACHANTE / CONFORMIDAD'
          : 'DUPLICADO - CONTROL DE DEPÓSITO';

      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(24),
          ),
          footer: (pw.Context ctx) => _buildFooter(ctx, businessName),
          build: (pw.Context ctx) => _buildContentList(
            businessName: businessName,
            businessAddress: businessAddress,
            businessPhone: businessPhone,
            businessTaxId: businessTaxId,
            documentTitle: documentTitle,
            noteId: noteId,
            documentCode: documentCode,
            createdDate: createdDate,
            customerName: customerName,
            customerDoc: customerDoc,
            sale: sale,
            vendorName: vendorName,
            dispatcherName: dispatcherName,
            effectiveDocStatus: effectiveDocStatus,
            isDispatch: isDispatch,
            items: items,
            deliveredNow: deliveredNow,
            totalUnits: totalUnits,
            isCompact: false,
            copyLabel: copyLabelFull1,
            logoBytes: resolvedLogo,
          ),
        ),
      );

      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(24),
          ),
          footer: (pw.Context ctx) => _buildFooter(ctx, businessName),
          build: (pw.Context ctx) => _buildContentList(
            businessName: businessName,
            businessAddress: businessAddress,
            businessPhone: businessPhone,
            businessTaxId: businessTaxId,
            documentTitle: documentTitle,
            noteId: noteId,
            documentCode: documentCode,
            createdDate: createdDate,
            customerName: customerName,
            customerDoc: customerDoc,
            sale: sale,
            vendorName: vendorName,
            dispatcherName: dispatcherName,
            effectiveDocStatus: effectiveDocStatus,
            isDispatch: isDispatch,
            items: items,
            deliveredNow: deliveredNow,
            totalUnits: totalUnits,
            isCompact: false,
            copyLabel: copyLabelFull2,
            logoBytes: resolvedLogo,
          ),
        ),
      );
    }

    return doc.save();
  }

  static pw.Widget _buildCompactFooter(String businessName, DateTime date) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Divider(color: PdfColors.grey500, thickness: 0.5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Emitido el ${_dateFmt.format(date)} - $businessName',
              style: pw.TextStyle(
                fontSize: 6.5,
                color: PdfColors.grey800,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'DOCUMENTO NO VÁLIDO COMO FACTURA',
              style: pw.TextStyle(
                fontSize: 6.5,
                color: PdfColors.grey800,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context ctx, String businessName) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.SizedBox(height: 6),
        pw.Divider(color: PdfColors.grey500, thickness: 0.6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'DOCUMENTO NO VÁLIDO COMO FACTURA - SOLO COMPROBANTE DE ENTREGA - $businessName',
              style: pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey800,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey800,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static List<pw.Widget> _buildContentList({
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessTaxId,
    required String documentTitle,
    required String noteId,
    required String documentCode,
    required DateTime createdDate,
    required String? customerName,
    required String customerDoc,
    required Map<String, dynamic> sale,
    String? vendorName,
    String? dispatcherName,
    required String effectiveDocStatus,
    required bool isDispatch,
    required List<dynamic> items,
    required Map<int, double> deliveredNow,
    required int totalUnits,
    required bool isCompact,
    String copyLabel = 'ORIGINAL',
    Uint8List? logoBytes,
  }) {
    final boxLetter = isDispatch ? 'R' : 'X';
    final boxCode = isDispatch ? 'COD. 091' : 'INTERNO';
    final saleIdStr = sale['id'] != null
        ? '#${sale['id'].toString().padLeft(8, '0')}'
        : '---';
    final customerMap = sale['customer'] as Map<String, dynamic>?;
    final rawDeliveryAddr = (sale['delivery_address'] ??
            customerMap?['delivery_address'] ??
            customerMap?['fiscal_address'] ??
            customerMap?['address'] ??
            '')
        .toString()
        .trim();
    final deliveryAddress =
        rawDeliveryAddr.toLowerCase() == 'null' ? '' : rawDeliveryAddr;
    final formattedBusinessCuit = _formatCuit(businessTaxId);
    final formattedCustomerDoc =
        customerDoc != '---' ? _formatCuit(customerDoc) : '---';

    return [
      // BARRA SUPERIOR ORIGINAL / DUPLICADO
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              copyLabel,
              style: pw.TextStyle(
                fontSize: isCompact ? 7.5 : 8.5,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            pw.Text(
              'DOCUMENTO NO VÁLIDO COMO FACTURA',
              style: pw.TextStyle(
                fontSize: isCompact ? 7 : 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
          ],
        ),
      ),

      // ENCABEZADO PARTIDO ESTILO ARCA CON LETRA R / X Y CÓDIGO DE BARRAS
      pw.Stack(
        alignment: pw.Alignment.topCenter,
        children: [
          pw.Table(
            border: const pw.TableBorder(
              left: pw.BorderSide(color: PdfColors.black, width: 1.0),
              right: pw.BorderSide(color: PdfColors.black, width: 1.0),
              bottom: pw.BorderSide(color: PdfColors.black, width: 1.0),
              verticalInside: pw.BorderSide(color: PdfColors.black, width: 1.0),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                children: [
                  // COLUMNA IZQUIERDA: EMISOR + BARCODE
                  pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(
                      isCompact ? 6 : 8,
                      isCompact ? 6 : 8,
                      26,
                      isCompact ? 6 : 8,
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (logoBytes != null) ...[
                          pw.Container(
                            width: isCompact ? 36 : 46,
                            height: isCompact ? 36 : 46,
                            child: pw.Image(
                              pw.MemoryImage(logoBytes),
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                        ],
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                businessName.toUpperCase(),
                                style: pw.TextStyle(
                                  fontSize: isCompact ? 13 : 15,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black,
                                ),
                              ),
                              if (businessAddress != null &&
                                  businessAddress.isNotEmpty)
                                pw.Text(
                                  'Domicilio Comercial: $businessAddress',
                                  style: pw.TextStyle(
                                      fontSize: isCompact ? 7 : 7.5),
                                ),
                              if (businessPhone != null &&
                                  businessPhone.isNotEmpty)
                                pw.Text(
                                  'Teléfono: $businessPhone',
                                  style: pw.TextStyle(
                                      fontSize: isCompact ? 7 : 7.5),
                                ),
                              if (formattedBusinessCuit.isNotEmpty)
                                pw.Text(
                                  'CUIT: $formattedBusinessCuit',
                                  style: pw.TextStyle(
                                    fontSize: isCompact ? 7 : 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              pw.SizedBox(height: 3),
                              pw.BarcodeWidget(
                                barcode: pw.Barcode.code128(),
                                data: documentCode,
                                width: isCompact ? 105 : 130,
                                height: isCompact ? 18 : 24,
                                drawText: false,
                              ),
                              pw.Text(
                                documentCode,
                                style: pw.TextStyle(
                                  fontSize: 6.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // COLUMNA DERECHA: DATOS DEL REMITO
                  pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(
                      26,
                      isCompact ? 6 : 8,
                      isCompact ? 6 : 8,
                      isCompact ? 6 : 8,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          documentTitle,
                          style: pw.TextStyle(
                            fontSize: isCompact ? 11.5 : 13.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Remito Nro: 00001-$noteId   ($documentCode)',
                          style: pw.TextStyle(
                            fontSize: isCompact ? 8 : 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Fecha de Emisión: ${_dateFmt.format(createdDate)}',
                          style: pw.TextStyle(fontSize: isCompact ? 7.5 : 8),
                        ),
                        pw.Text(
                          'Venta Asociada: $saleIdStr',
                          style: pw.TextStyle(fontSize: isCompact ? 7.5 : 8),
                        ),
                        if (vendorName != null && vendorName.isNotEmpty)
                          pw.Text(
                            'Vendió: ${vendorName.toUpperCase()}',
                            style: pw.TextStyle(fontSize: isCompact ? 7 : 7.5),
                          ),
                        if (dispatcherName != null &&
                            dispatcherName.isNotEmpty)
                          pw.Text(
                            'Despachó: ${dispatcherName.toUpperCase()}',
                            style: pw.TextStyle(
                              fontSize: isCompact ? 7 : 7.5,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // RECUADRO CENTRAL SUPERIOR DE LETRA (R / X)
          pw.Positioned(
            top: 0,
            child: pw.Container(
              width: isCompact ? 36 : 42,
              height: isCompact ? 36 : 42,
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: PdfColors.black, width: 1.5),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    boxLetter,
                    style: pw.TextStyle(
                      fontSize: isCompact ? 16 : 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    boxCode,
                    style: pw.TextStyle(
                      fontSize: isCompact ? 4.8 : 5.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      pw.SizedBox(height: isCompact ? 4 : 6),

      // CASILLERO DE DESTINATARIO Y ESTADO LOGÍSTICO
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
        ),
        padding: pw.EdgeInsets.symmetric(
          horizontal: 8,
          vertical: isCompact ? 4 : 6,
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: 7,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Destinatario / Cliente: ${(customerName ?? "Consumidor Final").toUpperCase()}   |   CUIT / DNI: $formattedCustomerDoc',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7.5 : 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    deliveryAddress.isNotEmpty
                        ? 'Domicilio de Entrega: $deliveryAddress'
                        : 'Modalidad de Entrega: Retiro en mostrador / depósito comercial',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7.5 : 8,
                      fontWeight: deliveryAddress.isNotEmpty
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                border: pw.Border.all(color: PdfColors.black, width: 0.8),
              ),
              child: pw.Text(
                isDispatch ? _statusLabel(effectiveDocStatus) : 'A PREPARAR',
                style: pw.TextStyle(
                  color: PdfColors.black,
                  fontSize: isCompact ? 7.5 : 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),

      pw.SizedBox(height: isCompact ? 4 : 6),

      // TABLA TÉCNICA DE MERCADERÍA
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.4),
          1: const pw.FlexColumnWidth(4.8),
          2: const pw.FlexColumnWidth(1.6),
          3: const pw.FlexColumnWidth(1.7),
          4: const pw.FlexColumnWidth(1.6),
          5: const pw.FlexColumnWidth(1.7),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            repeat: true,
            children: [
              _th('CÓDIGO', align: pw.TextAlign.center, isCompact: isCompact),
              _th(
                'DESCRIPCIÓN DEL ARTÍCULO',
                align: pw.TextAlign.left,
                isCompact: isCompact,
              ),
              _th(
                'CANT. TOTAL',
                align: pw.TextAlign.center,
                isCompact: isCompact,
              ),
              _th(
                deliveredNow.isNotEmpty ? 'ENTREGADO HOY' : 'ENTREGADO',
                align: pw.TextAlign.center,
                isCompact: isCompact,
              ),
              _th(
                'SALDO PEND.',
                align: pw.TextAlign.center,
                isCompact: isCompact,
              ),
              _th('ESTADO', align: pw.TextAlign.center, isCompact: isCompact),
            ],
          ),
          ...items.map((rawItem) {
            final item = rawItem as Map<String, dynamic>;
            final product = item['product'] as Map<String, dynamic>? ?? {};
            final isByWeight = product['is_sold_by_weight'] == true ||
                item['is_sold_by_weight'] == true;
            final totalQty = double.tryParse(
                    item['quantity_purchased']?.toString() ?? '') ??
                0.0;
            final deliveredQtyDb = double.tryParse(
                    item['quantity_delivered']?.toString() ?? '') ??
                0.0;
            final deliveredQtyNow = deliveredNow[item['id']] ?? 0.0;
            final effectiveDelivered = deliveredNow.isNotEmpty
                ? (deliveredQtyDb + deliveredQtyNow)
                : deliveredQtyDb;
            final pendingQty =
                (totalQty - effectiveDelivered).clamp(0.0, double.infinity);

            String effectiveItemStatus = 'pending';
            if (pendingQty <= 0 && totalQty > 0) {
              effectiveItemStatus = 'delivered';
            } else if (effectiveDelivered > 0) {
              effectiveItemStatus = 'partial';
            }

            String fmt(double v) =>
                isByWeight ? '${v.toQty()} kg' : '${v.toInt()} un';

            final valToShow =
                deliveredNow.isNotEmpty ? deliveredQtyNow : deliveredQtyDb;
            final code =
                (product['internal_code'] ?? item['internal_code'] ?? '-')
                    .toString();
            final name = (product['name'] ?? item['product_name'] ?? '-')
                .toString()
                .toUpperCase();

            return pw.TableRow(
              children: [
                _td(
                  code.trim().isEmpty ? '-' : code,
                  align: pw.TextAlign.center,
                  isCompact: isCompact,
                ),
                _td(
                  name,
                  align: pw.TextAlign.left,
                  bold: true,
                  isCompact: isCompact,
                ),
                _td(
                  fmt(totalQty),
                  align: pw.TextAlign.center,
                  isCompact: isCompact,
                ),
                _td(
                  valToShow > 0 ? fmt(valToShow) : '-',
                  align: pw.TextAlign.center,
                  bold: valToShow > 0,
                  isCompact: isCompact,
                ),
                _td(
                  pendingQty > 0 ? fmt(pendingQty) : '0',
                  align: pw.TextAlign.center,
                  bold: pendingQty > 0,
                  isCompact: isCompact,
                ),
                _td(
                  _statusLabel(effectiveItemStatus),
                  align: pw.TextAlign.center,
                  bold: true,
                  isCompact: isCompact,
                ),
              ],
            );
          }),
        ],
      ),

      pw.SizedBox(height: isCompact ? 5 : 10),

      // PIE DE INSTRUCCIONES Y CONFORMIDAD DEL RECEPTOR
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.8),
              ),
              padding: pw.EdgeInsets.all(isCompact ? 6 : 9),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    isDispatch
                        ? 'INSTRUCCIONES DE RECEPCIÓN DE MERCADERÍA'
                        : 'INSTRUCCIONES DE RETIRO EN DEPÓSITO',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7 : 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: isCompact ? 2 : 4),
                  pw.Text(
                    isDispatch
                        ? 'Por favor verifique que los artículos recibidos coincidan con las cantidades detalladas en este comprobante antes de firmar la conformidad.'
                        : 'Presente este comprobante al retirar la mercadería en depósito. El operador escaneará el código de barras superior o buscará por N° de Remito.',
                    style: pw.TextStyle(fontSize: isCompact ? 6.5 : 7.5),
                  ),
                  if (totalUnits > 0) ...[
                    pw.SizedBox(height: isCompact ? 3 : 6),
                    pw.Text(
                      'Total de unidades / bultos: $totalUnits',
                      style: pw.TextStyle(
                        fontSize: isCompact ? 7.5 : 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.8),
              ),
              padding: pw.EdgeInsets.all(isCompact ? 6 : 9),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RECIBÍ CONFORME (FIRMA Y ACLARACIÓN DEL RECEPTOR)',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7 : 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: isCompact ? 14 : 24),
                  pw.Divider(color: PdfColors.black, thickness: 0.5),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'DNI / CUIT: ___________________',
                        style: pw.TextStyle(fontSize: isCompact ? 6.5 : 7.5),
                      ),
                      pw.Text(
                        'Fecha retiro: ____/____/______',
                        style: pw.TextStyle(fontSize: isCompact ? 6.5 : 7.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'PENDIENTE';
      case 'partial':
        return 'PARCIAL';
      case 'delivered':
        return 'ENTREGADO';
      default:
        return status.toUpperCase();
    }
  }

  static pw.Widget _th(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool isCompact = false,
  }) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(
          horizontal: 5,
          vertical: isCompact ? 3.5 : 5,
        ),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            color: PdfColors.black,
            fontSize: isCompact ? 7 : 8,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: align,
        ),
      );

  static pw.Widget _td(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    bool isCompact = false,
  }) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(
          horizontal: 5,
          vertical: isCompact ? 3 : 4.5,
        ),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: isCompact ? 7.5 : 8.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: PdfColors.black,
          ),
          textAlign: align,
        ),
      );
}
