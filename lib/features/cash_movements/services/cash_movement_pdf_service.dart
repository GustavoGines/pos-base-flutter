import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../core/utils/afip_fiscal_pdf_service.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/presentation/widgets/app_modal_shell.dart';
import '../../../../core/presentation/widgets/app_pdf_preview.dart';
import '../../../../core/presentation/widgets/ticket_preview_dialog.dart';

class CashMovementPdfService {
  static final _numberFmt = NumberFormat('#,##0.00', 'es_AR');
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  /// Formatea importes con el signo $ adelante ($ 123.187,24), consistente con todo el sistema.
  static String formatCurrency(num amount) {
    if (amount < 0) {
      return '-\$ ${_numberFmt.format(amount.abs())}';
    }
    return '\$ ${_numberFmt.format(amount)}';
  }

  /// Formatea un CUIT/CUIL de 11 dígitos con guiones (XX-XXXXXXXX-X).
  static String formatCuit(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 10)}-${digits.substring(10)}';
    }
    return raw.trim();
  }

  static String _formatTaxCondition(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    switch (raw.trim().toLowerCase()) {
      case 'responsable_inscripto':
      case 'iva responsable inscripto':
        return 'IVA Responsable Inscripto';
      case 'monotributo':
      case 'responsable_monotributo':
      case 'responsable monotributo':
        return 'Responsable Monotributo';
      case 'exento':
      case 'iva sujeto exento':
        return 'IVA Sujeto Exento';
      case 'consumidor_final':
      case 'consumidor final':
        return 'Consumidor Final';
      default:
        return raw.trim().replaceAll('_', ' ');
    }
  }

  static Future<void> printGenericMovement({
    required BuildContext context,
    required String type,
    required String category,
    required double totalAmount,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessTaxId,
    dynamic businessSettings,
    List<int> movementIds = const [],
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
    DateTime? issuedAt,
  }) async {
    final pdfBytes = await _generateGenericPdfBytes(
      type: type,
      category: category,
      totalAmount: totalAmount,
      payments: payments,
      businessName: businessName,
      businessTaxId: businessTaxId,
      businessSettings: businessSettings,
      movementIds: movementIds,
      description: description,
      receiptNumber: receiptNumber,
      cashierName: cashierName,
      paperSize: paperSize,
      issuedAt: issuedAt,
    );

    final paperLabel = pdfPaperSizeLabel(paperSize);
    if (context.mounted) {
      await _showPdfPreviewDialog(
        context: context,
        title: 'Vista Previa de Comprobante ($paperLabel)',
        fileName: 'Comprobante_Caja_${movementIds.isNotEmpty ? movementIds.first : '00'}.pdf',
        pdfBytes: pdfBytes,
        paperSize: paperSize,
      );
    }
  }

  static Future<Uint8List> generateGenericPdfBytesForTest({
    required String type,
    required String category,
    required double totalAmount,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessTaxId,
    dynamic businessSettings,
    List<int> movementIds = const [],
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
    DateTime? issuedAt,
  }) =>
      _generateGenericPdfBytes(
        type: type,
        category: category,
        totalAmount: totalAmount,
        payments: payments,
        businessName: businessName,
        businessTaxId: businessTaxId,
        businessSettings: businessSettings,
        movementIds: movementIds,
        description: description,
        receiptNumber: receiptNumber,
        cashierName: cashierName,
        paperSize: paperSize,
        issuedAt: issuedAt,
      );

  static Future<Uint8List> _generateGenericPdfBytes({
    required String type,
    required String category,
    required double totalAmount,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessTaxId,
    dynamic businessSettings,
    List<int> movementIds = const [],
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
    DateTime? issuedAt,
  }) async {
    final resolvedLogo = await AfipFiscalPdfService.resolveLogoBytes(
      businessSettings: businessSettings,
    );
    pw.ThemeData? theme;
    try {
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: font, bold: fontBold);
    } catch (_) {
      theme = pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }

    final pdf = pw.Document(theme: theme);
    final format = paperSize.toLowerCase() == 'letter' ? PdfPageFormat.letter : PdfPageFormat.a4;

    String titulo;
    switch (type) {
      case 'withdrawal':
        titulo = 'COMPROBANTE DE RETIRO';
        break;
      case 'deposit':
        titulo = 'COMPROBANTE DE INGRESO';
        break;
      default:
        titulo = 'COMPROBANTE DE GASTO';
    }

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(22),
        build: (pw.Context context) {
          return _buildHalfPageLayout(
            voucherContent: _buildCanonicalVoucherCard(
              businessName: businessName,
              businessTaxId: businessTaxId,
              businessSettings: businessSettings,
              logoBytes: resolvedLogo,
              titulo: titulo,
              movementIds: movementIds,
              cashierName: cashierName,
              issuedAt: issuedAt,
              recipientBox: _buildGenericConceptBox(
                type: type,
                category: category,
                description: description,
                receiptNumber: receiptNumber,
              ),
              payments: payments,
              totalAmount: totalAmount,
              totalLabel: type == 'deposit' ? 'TOTAL INGRESADO:' : 'TOTAL EGRESADO:',
              balanceBefore: null,
              isExpense: type != 'deposit',
              leftSignatureLabel: 'ENTREGADO POR (COMERCIO / CAJA)',
              rightSignatureLabel: 'RECIBÍ CONFORME / AUTORIZACIÓN',
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> printSupplierPayment({
    required BuildContext context,
    required String type,
    required String supplierName,
    required double totalAmount,
    double? balanceBefore,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessTaxId,
    dynamic businessSettings,
    List<int> movementIds = const [],
    String? supplierCuit,
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
    DateTime? issuedAt,
  }) async {
    final pdfBytes = await _generateSupplierPdfBytes(
      type: type,
      supplierName: supplierName,
      totalAmount: totalAmount,
      balanceBefore: balanceBefore,
      payments: payments,
      businessName: businessName,
      businessTaxId: businessTaxId,
      businessSettings: businessSettings,
      movementIds: movementIds,
      supplierCuit: supplierCuit,
      description: description,
      receiptNumber: receiptNumber,
      cashierName: cashierName,
      paperSize: paperSize,
      issuedAt: issuedAt,
    );

    final paperLabel = pdfPaperSizeLabel(paperSize);
    if (context.mounted) {
      await _showPdfPreviewDialog(
        context: context,
        title: 'Vista Previa de Pago a Proveedor ($paperLabel)',
        fileName: 'Comprobante_Proveedor_${movementIds.isNotEmpty ? movementIds.first : '00'}.pdf',
        pdfBytes: pdfBytes,
        paperSize: paperSize,
      );
    }
  }

  static Future<Uint8List> generateSupplierPdfBytesForTest({
    required String type,
    required String supplierName,
    required double totalAmount,
    double? balanceBefore,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessTaxId,
    dynamic businessSettings,
    List<int> movementIds = const [],
    String? supplierCuit,
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
    DateTime? issuedAt,
  }) =>
      _generateSupplierPdfBytes(
        type: type,
        supplierName: supplierName,
        totalAmount: totalAmount,
        balanceBefore: balanceBefore,
        payments: payments,
        businessName: businessName,
        businessTaxId: businessTaxId,
        businessSettings: businessSettings,
        movementIds: movementIds,
        supplierCuit: supplierCuit,
        description: description,
        receiptNumber: receiptNumber,
        cashierName: cashierName,
        paperSize: paperSize,
        issuedAt: issuedAt,
      );

  static Future<Uint8List> _generateSupplierPdfBytes({
    required String type,
    required String supplierName,
    required double totalAmount,
    double? balanceBefore,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessTaxId,
    dynamic businessSettings,
    List<int> movementIds = const [],
    String? supplierCuit,
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
    DateTime? issuedAt,
  }) async {
    final resolvedLogo = await AfipFiscalPdfService.resolveLogoBytes(
      businessSettings: businessSettings,
    );
    pw.ThemeData? theme;
    try {
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: font, bold: fontBold);
    } catch (_) {
      theme = pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }

    final pdf = pw.Document(theme: theme);
    final format = paperSize.toLowerCase() == 'letter' ? PdfPageFormat.letter : PdfPageFormat.a4;

    final titulo = type == 'deposit' ? 'COBRO DE SALDO A FAVOR' : 'ORDEN DE PAGO A PROVEEDOR';
    final formattedSupplierCuit = formatCuit(supplierCuit);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(22),
        build: (pw.Context context) {
          return _buildHalfPageLayout(
            voucherContent: _buildCanonicalVoucherCard(
              businessName: businessName,
              businessTaxId: businessTaxId,
              businessSettings: businessSettings,
              logoBytes: resolvedLogo,
              titulo: titulo,
              movementIds: movementIds,
              cashierName: cashierName,
              issuedAt: issuedAt,
              recipientBox: _buildSupplierRecipientBox(
                supplierName: supplierName,
                formattedSupplierCuit: formattedSupplierCuit,
                description: description,
                receiptNumber: receiptNumber,
              ),
              payments: payments,
              totalAmount: totalAmount,
              totalLabel: type == 'deposit' ? 'TOTAL COBRADO:' : 'TOTAL ABONADO:',
              balanceBefore: balanceBefore,
              isExpense: type == 'expense' || type == 'supplier_payment',
              leftSignatureLabel: 'ENTREGADO POR (COMERCIO)',
              rightSignatureLabel: 'RECIBÍ CONFORME (PROVEEDOR)',
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> _showPdfPreviewDialog({
    required BuildContext context,
    required String title,
    required String fileName,
    required Uint8List pdfBytes,
    String paperSize = 'a4',
  }) async {
    await showAppPdfPreviewDialog(
      context: context,
      title: title,
      subtitle: 'Comprobante de caja • Hoja ${pdfPaperSizeLabel(paperSize)}',
      icon: Icons.receipt_long_rounded,
      accent: AppModalAccent.blue,
      initialPageFormat: pdfPageFormatFromPaperSize(paperSize),
      pdfFileName: fileName,
      build: (format) async => pdfBytes,
    );
  }

  // --- Helpers PDF (100% compatibles con diseño monocromático técnico ARCA / Media Hoja A4) ---

  static pw.Widget _buildHalfPageLayout({required pw.Widget voucherContent}) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        voucherContent,
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: PdfColors.grey500,
                        width: 0.7,
                        style: pw.BorderStyle.dashed,
                      ),
                    ),
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                child: pw.Text(
                  '--- CORTAR AQUÍ ---',
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: PdfColors.grey500,
                        width: 0.7,
                        style: pw.BorderStyle.dashed,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildCanonicalVoucherCard({
    required String businessName,
    required String? businessTaxId,
    required dynamic businessSettings,
    required Uint8List? logoBytes,
    required String titulo,
    required List<int> movementIds,
    required String? cashierName,
    DateTime? issuedAt,
    required pw.Widget recipientBox,
    required List<Map<String, dynamic>> payments,
    required double totalAmount,
    required String totalLabel,
    required double? balanceBefore,
    required bool isExpense,
    required String leftSignatureLabel,
    required String rightSignatureLabel,
  }) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _buildCanonicalHeader(
          businessName: businessName,
          businessTaxId: businessTaxId,
          businessSettings: businessSettings,
          logoBytes: logoBytes,
          titulo: titulo,
          movementIds: movementIds,
          cashierName: cashierName,
          issuedAt: issuedAt,
        ),
        pw.SizedBox(height: 4),
        recipientBox,
        pw.SizedBox(height: 4),
        _buildCanonicalPaymentTable(payments),
        pw.SizedBox(height: 4),
        _buildCanonicalBottomSection(
          totalAmount: totalAmount,
          totalLabel: totalLabel,
          balanceBefore: balanceBefore,
          isExpense: isExpense,
          leftSignatureLabel: leftSignatureLabel,
          rightSignatureLabel: rightSignatureLabel,
        ),
        pw.SizedBox(height: 3),
        _buildCanonicalFooter(businessName),
      ],
    );
  }

  static pw.Widget _buildCanonicalHeader({
    required String businessName,
    required String? businessTaxId,
    required dynamic businessSettings,
    required Uint8List? logoBytes,
    required String titulo,
    required List<int> movementIds,
    required String? cashierName,
    DateTime? issuedAt,
  }) {
    String movNumber = 'MOV-000000';
    String barcodeData = 'MOV-000000';
    if (movementIds.isNotEmpty) {
      final firstPadded = movementIds.first.toString().padLeft(6, '0');
      barcodeData = 'MOV-$firstPadded';
      if (movementIds.length == 1) {
        movNumber = barcodeData;
      } else {
        movNumber = '$barcodeData/${movementIds.last.toString().padLeft(6, '0')}';
      }
    }

    final formattedEmitterCuit = formatCuit(businessTaxId ?? businessSettings?.taxId?.toString());
    final String? address = businessSettings?.address?.toString();
    final String? phone = businessSettings?.phone?.toString();
    final String taxCond = _formatTaxCondition(businessSettings?.taxCondition?.toString());
    final String? iibb = businessSettings?.iibb?.toString();
    final DateTime effectiveDate = issuedAt ?? DateTime.now();
    pw.MemoryImage? safeLogoImage;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      try {
        safeLogoImage = pw.MemoryImage(logoBytes);
      } catch (_) {
        safeLogoImage = null;
      }
    }

    return pw.Stack(
      alignment: pw.Alignment.topCenter,
      children: [
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 1.0),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Barra Superior ORIGINAL / DOCUMENTO INTERNO - NO VÁLIDO COMO FACTURA
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black, width: 1.0),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'ORIGINAL',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.2,
                        color: PdfColors.black,
                      ),
                    ),
                    pw.Text(
                      'DOCUMENTO INTERNO - NO VÁLIDO COMO FACTURA',
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                  ],
                ),
              ),

              pw.Table(
                border: const pw.TableBorder(
                  verticalInside: pw.BorderSide(color: PdfColors.black, width: 1.0),
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1),
                  1: pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    children: [
                      // Columna Izquierda: Emisor
                      pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(8, 6, 24, 6),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            if (safeLogoImage != null) ...[
                              pw.Container(
                                width: 34,
                                height: 34,
                                child: pw.Image(
                                  safeLogoImage,
                                  fit: pw.BoxFit.contain,
                                ),
                              ),
                              pw.SizedBox(width: 7),
                            ],
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    businessName.toUpperCase(),
                                    style: pw.TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.black,
                                    ),
                                  ),
                                  pw.SizedBox(height: 1.5),
                                  if (address != null && address.trim().isNotEmpty)
                                    pw.Text(
                                      'Domicilio Comercial: ${address.trim()}',
                                      style: const pw.TextStyle(fontSize: 7.5),
                                    ),
                                  if (phone != null && phone.trim().isNotEmpty)
                                    pw.Text(
                                      'Teléfono: ${phone.trim()}',
                                      style: const pw.TextStyle(fontSize: 7.5),
                                    ),
                                  if (taxCond.isNotEmpty)
                                    pw.Text(
                                      'Cond. frente al IVA: $taxCond',
                                      style: pw.TextStyle(
                                        fontSize: 7.5,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Columna Derecha: Datos del Comprobante + Código de Barras Code128
                      pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(24, 6, 8, 6),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Expanded(
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        titulo,
                                        style: pw.TextStyle(
                                          fontSize: 11,
                                          fontWeight: pw.FontWeight.bold,
                                          color: PdfColors.black,
                                        ),
                                      ),
                                      pw.SizedBox(height: 1.5),
                                      pw.Text(
                                        'Comp. Nro: $movNumber',
                                        style: pw.TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: pw.FontWeight.bold,
                                        ),
                                      ),
                                      pw.Text(
                                        'Fecha de Emisión: ${_dateFmt.format(effectiveDate)}',
                                        style: const pw.TextStyle(fontSize: 7.8),
                                      ),
                                    ],
                                  ),
                                ),
                                pw.SizedBox(width: 6),
                                pw.BarcodeWidget(
                                  barcode: pw.Barcode.code128(),
                                  data: barcodeData,
                                  width: 78,
                                  height: 20,
                                  drawText: false,
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 1.5),
                            pw.Row(
                              children: [
                                if (formattedEmitterCuit.isNotEmpty)
                                  pw.Text(
                                    'CUIT: $formattedEmitterCuit',
                                    style: pw.TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                if (formattedEmitterCuit.isNotEmpty &&
                                    iibb != null &&
                                    iibb.trim().isNotEmpty)
                                  pw.Text('   |   ', style: const pw.TextStyle(fontSize: 7.2)),
                                if (iibb != null && iibb.trim().isNotEmpty)
                                  pw.Text(
                                    'Ing. Brutos: ${iibb.trim()}',
                                    style: const pw.TextStyle(fontSize: 7.5),
                                  ),
                              ],
                            ),
                            if (cashierName != null && cashierName.trim().isNotEmpty)
                              pw.Text(
                                'Operador / Caja: ${cashierName.trim().toUpperCase()}',
                                style: const pw.TextStyle(fontSize: 7.5),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Recuadro Central [X | INTERNO]
        pw.Positioned(
          top: 16,
          child: pw.Container(
            width: 36,
            height: 36,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'X',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.Text(
                  'INTERNO',
                  style: pw.TextStyle(
                    fontSize: 5.2,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildGenericConceptBox({
    required String type,
    required String category,
    required String? description,
    required String? receiptNumber,
  }) {
    final opLabel = type == 'withdrawal'
        ? 'RETIRO DE CAJA'
        : (type == 'deposit' ? 'INGRESO A CAJA' : 'EGRESO / GASTO OPERATIVO');
    final cleanDesc = (description != null && description.trim().isNotEmpty)
        ? description.trim()
        : 'Movimiento interno de caja';
    final cleanRef = (receiptNumber != null && receiptNumber.trim().isNotEmpty)
        ? receiptNumber.trim()
        : '-';

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 6,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('Concepto / Categoría: ',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(
                      child: pw.Text(category.toUpperCase(),
                          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                pw.Row(
                  children: [
                    pw.Text('Detalle / Observación: ',
                        style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(
                      child: pw.Text(cleanDesc, style: const pw.TextStyle(fontSize: 7.8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 4,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('Tipo de Operación: ',
                        style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(
                      child: pw.Text(opLabel, style: const pw.TextStyle(fontSize: 7.8)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                pw.Row(
                  children: [
                    pw.Text('Comprobante Asoc.: ',
                        style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(
                      child: pw.Text(cleanRef, style: const pw.TextStyle(fontSize: 7.8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSupplierRecipientBox({
    required String supplierName,
    required String formattedSupplierCuit,
    required String? description,
    required String? receiptNumber,
  }) {
    final cleanDesc = (description != null && description.trim().isNotEmpty)
        ? description.trim()
        : 'Imputación en Cuenta Corriente de Proveedor';
    final cleanRef = (receiptNumber != null && receiptNumber.trim().isNotEmpty)
        ? receiptNumber.trim()
        : '-';

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 6,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('Proveedor / Razón Social: ',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(
                      child: pw.Text(supplierName.toUpperCase(),
                          style: pw.TextStyle(fontSize: 8.8, fontWeight: pw.FontWeight.bold)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                pw.Row(
                  children: [
                    pw.Text('Detalle / Concepto: ',
                        style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(
                      child: pw.Text(cleanDesc, style: const pw.TextStyle(fontSize: 7.8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 4,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('CUIT Proveedor: ',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      formattedSupplierCuit.isNotEmpty ? formattedSupplierCuit : 'S/D',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                pw.Row(
                  children: [
                    pw.Text('Comprobante / Ref.: ',
                        style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(
                      child: pw.Text(cleanRef, style: const pw.TextStyle(fontSize: 7.8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCanonicalPaymentTable(List<Map<String, dynamic>> payments) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.0),
        1: pw.FlexColumnWidth(6.5),
        2: pw.FlexColumnWidth(2.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 5),
              child: pw.Text('ÍTEM',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: pw.Text('MEDIO DE PAGO / ORIGEN DE FONDOS',
                  textAlign: pw.TextAlign.left,
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: pw.Text('IMPORTE',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
        for (int i = 0; i < payments.length; i++)
          () {
            final p = payments[i];
            final method = mapPaymentMethod(
              p['payment_method'] as String? ?? 'cash',
              fundingSource: p['funding_source'] as String?,
            );
            final amount = (p['amount'] as num).toDouble();
            return pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 5),
                  child: pw.Text((i + 1).toString().padLeft(2, '0'),
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 8)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                  child: pw.Text(method,
                      textAlign: pw.TextAlign.left,
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                  child: pw.Text(formatCurrency(amount),
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(fontSize: 8.2, fontWeight: pw.FontWeight.bold)),
                ),
              ],
            );
          }(),
      ],
    );
  }

  static pw.Widget _buildCanonicalBottomSection({
    required double totalAmount,
    required String totalLabel,
    required double? balanceBefore,
    required bool isExpense,
    required String leftSignatureLabel,
    required String rightSignatureLabel,
  }) {
    final bool hasBalance = balanceBefore != null;
    final double balanceAfter = hasBalance
        ? (isExpense ? balanceBefore - totalAmount : balanceBefore + totalAmount)
        : 0.0;
    final String balanceLabel = balanceAfter > 0
        ? 'SALDO DEUDOR RESTANTE:'
        : (balanceAfter < 0 ? 'SALDO A FAVOR DEL COMERCIO:' : 'CUENTA AL DÍA (SALDO \$ 0,00)');

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                flex: 6,
                child: hasBalance
                    ? pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.black, width: 0.6),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'RESUMEN DE ESTADO DE CUENTA CORRIENTE',
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('Saldo Anterior:', style: const pw.TextStyle(fontSize: 7.5)),
                                pw.Text(formatCurrency(balanceBefore.abs()),
                                    style: const pw.TextStyle(fontSize: 7.5)),
                              ],
                            ),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  isExpense
                                      ? 'Importe Abonado en este recibo:'
                                      : 'Importe Imputado:',
                                  style: const pw.TextStyle(fontSize: 7.5),
                                ),
                                pw.Text(
                                  '${isExpense ? '-' : '+'} ${formatCurrency(totalAmount)}',
                                  style: pw.TextStyle(
                                      fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                                ),
                              ],
                            ),
                            pw.Divider(color: PdfColors.black, height: 5, thickness: 0.5),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(balanceLabel,
                                    style: pw.TextStyle(
                                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
                                pw.Text(formatCurrency(balanceAfter.abs()),
                                    style: pw.TextStyle(
                                        fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      )
                    : _buildInlineSignatures(
                        leftLabel: leftSignatureLabel,
                        rightLabel: rightSignatureLabel,
                      ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                flex: 4,
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    border: pw.Border.all(color: PdfColors.black, width: 1.0),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        totalLabel,
                        style: pw.TextStyle(
                          fontSize: 8.8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.Text(
                        formatCurrency(totalAmount),
                        style: pw.TextStyle(
                          fontSize: 11.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (hasBalance) ...[
            pw.SizedBox(height: 5),
            _buildInlineSignatures(
              leftLabel: leftSignatureLabel,
              rightLabel: rightSignatureLabel,
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildInlineSignatures({
    required String leftLabel,
    required String rightLabel,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(leftLabel,
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 11),
                pw.Text('Firma y Aclaración: ___________________________',
                    style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(rightLabel,
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 11),
                pw.Text('Firma / Aclaración / DNI: ______________________',
                    style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCanonicalFooter(String businessName) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Comprobante interno emitido por $businessName',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
        ),
        pw.Text(
          '*** DOCUMENTO INTERNO - NO VÁLIDO COMO FACTURA ***',
          style: pw.TextStyle(
            fontSize: 7,
            color: PdfColors.grey800,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static String mapPaymentMethod(String method, {String? fundingSource, bool shortForThermal = false}) {
    final bool isOwner = fundingSource == 'owner_funds' || method.toLowerCase() == 'owner_funds';
    switch (method.toLowerCase()) {
      case 'cash':
      case 'owner_funds':
        if (shortForThermal) {
          return isOwner ? 'EFECTIVO (BOLSILLO)' : 'EFECTIVO (CAJA)';
        }
        return isOwner ? 'EFECTIVO (FONDOS PROPIOS / BOLSILLO)' : 'EFECTIVO (CAJA)';
      case 'transfer':
        if (shortForThermal) {
          return isOwner ? 'TRANSF. (BOLSILLO)' : 'TRANSFERENCIA';
        }
        return isOwner ? 'TRANSFERENCIA (FONDOS PROPIOS / BOLSILLO)' : 'TRANSFERENCIA';
      case 'card':
        if (shortForThermal) {
          return isOwner ? 'TARJETA (BOLSILLO)' : 'TARJETA';
        }
        return isOwner ? 'TARJETA (FONDOS PROPIOS / BOLSILLO)' : 'TARJETA';
      case 'check':
        return 'CHEQUE';
      default:
        return method.toUpperCase();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  GENERADORES DE VISTA PREVIA TÉRMICA (58mm y 80mm)
  // ══════════════════════════════════════════════════════════════════════════

  static List<TicketLine> buildGenericMovementTicketLines({
    required String type,
    required String category,
    required double totalAmount,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessAddress,
    String? businessTaxId,
    List<int> movementIds = const [],
    String? description,
    String? receiptNumber,
    String? cashierName,
    DateTime? issuedAt,
    bool is58mm = false,
  }) {
    final List<TicketLine> lines = [];
    final dateStr = _dateFmt.format(issuedAt ?? DateTime.now());
    final String titulo = type == 'withdrawal'
        ? 'COMPROBANTE DE RETIRO'
        : (type == 'deposit' ? 'COMPROBANTE DE INGRESO' : 'COMPROBANTE DE GASTO');

    lines.add(TicketLine(
      businessName.toUpperCase(),
      align: TicketAlign.center,
      isBold: true,
      isLarge: true,
    ));
    if (businessAddress != null && businessAddress.trim().isNotEmpty) {
      lines.add(TicketLine(businessAddress.trim(), align: TicketAlign.center));
    }
    final cuitFormatted = formatCuit(businessTaxId);
    if (cuitFormatted.isNotEmpty) {
      lines.add(TicketLine('CUIT: $cuitFormatted', align: TicketAlign.center, isBold: true));
    }
    lines.add(const TicketLine.hr(bold: true));
    lines.add(TicketLine(titulo, align: TicketAlign.center, isBold: true));
    lines.add(const TicketLine.hr());

    lines.add(TicketLine('FECHA:', rightText: dateStr, isBold: true));
    if (movementIds.isNotEmpty) {
      final idStr = movementIds.length == 1
          ? 'MOV-${movementIds.first.toString().padLeft(6, '0')}'
          : 'MOV-${movementIds.first.toString().padLeft(6, '0')}/${movementIds.last.toString().padLeft(6, '0')}';
      lines.add(TicketLine('COMPROBANTE:', rightText: idStr, isBold: true));
    }
    if (cashierName != null && cashierName.trim().isNotEmpty) {
      lines.add(TicketLine('CAJERO:', rightText: cashierName.trim().toUpperCase()));
    }
    lines.add(const TicketLine.hr());

    lines.add(TicketLine('CATEGORIA:', rightText: category.toUpperCase(), isBold: true));
    if (description != null && description.trim().isNotEmpty) {
      lines.add(TicketLine('DETALLE: ${description.trim()}'));
    }
    if (receiptNumber != null && receiptNumber.trim().isNotEmpty) {
      lines.add(TicketLine('REF/COMP:', rightText: receiptNumber.trim()));
    }

    if (payments.length == 1) {
      final methodName = mapPaymentMethod(
        payments.first['payment_method'] as String? ?? 'cash',
        fundingSource: payments.first['funding_source'] as String?,
        shortForThermal: true,
      );
      lines.add(TicketLine(is58mm ? 'PAGO:' : 'MEDIO DE PAGO:', rightText: methodName));
    } else if (payments.length > 1) {
      lines.add(const TicketLine.hr());
      lines.add(const TicketLine('DESGLOSE DE PAGOS:', isBold: true));
      for (final p in payments) {
        final methodName = mapPaymentMethod(
          p['payment_method'] as String? ?? 'cash',
          fundingSource: p['funding_source'] as String?,
          shortForThermal: true,
        );
        final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
        lines.add(TicketLine(methodName, rightText: '\$${amount.toCurrency()}'));
      }
    }

    lines.add(const TicketLine.hr(bold: true));
    lines.add(TicketLine(
      type == 'deposit' ? 'TOTAL INGRESO:' : 'TOTAL EGRESO:',
      rightText: '\$${totalAmount.toCurrency()}',
      isBold: true,
      isLarge: true,
    ));

    lines.add(const TicketLine.space());
    lines.add(const TicketLine.space());
    lines.add(TicketLine(
      is58mm ? '........................' : '................................',
      align: TicketAlign.center,
    ));
    lines.add(const TicketLine('Firma quien entrega', align: TicketAlign.center));
    lines.add(const TicketLine.space());
    lines.add(const TicketLine.space());
    lines.add(TicketLine(
      is58mm ? '........................' : '................................',
      align: TicketAlign.center,
    ));
    lines.add(const TicketLine('Firma quien recibe', align: TicketAlign.center));
    lines.add(const TicketLine.space());
    lines.add(const TicketLine(
      '*** DOCUMENTO NO FISCAL ***',
      align: TicketAlign.center,
      isBold: true,
    ));

    return lines;
  }

  static List<TicketLine> buildSupplierPaymentTicketLines({
    required String type,
    required String supplierName,
    required double totalAmount,
    double? balanceBefore,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessAddress,
    String? businessTaxId,
    List<int> movementIds = const [],
    String? supplierCuit,
    String? description,
    String? receiptNumber,
    String? cashierName,
    DateTime? issuedAt,
    bool is58mm = false,
  }) {
    final List<TicketLine> lines = [];
    final dateStr = _dateFmt.format(issuedAt ?? DateTime.now());
    final titulo = type == 'deposit' ? 'COBRO DE SALDO A FAVOR' : 'PAGO A PROVEEDOR';

    lines.add(TicketLine(
      businessName.toUpperCase(),
      align: TicketAlign.center,
      isBold: true,
      isLarge: true,
    ));
    if (businessAddress != null && businessAddress.trim().isNotEmpty) {
      lines.add(TicketLine(businessAddress.trim(), align: TicketAlign.center));
    }
    final cuitFormatted = formatCuit(businessTaxId);
    if (cuitFormatted.isNotEmpty) {
      lines.add(TicketLine('CUIT: $cuitFormatted', align: TicketAlign.center, isBold: true));
    }
    lines.add(const TicketLine.hr(bold: true));
    lines.add(TicketLine(titulo, align: TicketAlign.center, isBold: true));
    lines.add(const TicketLine.hr());

    lines.add(TicketLine('FECHA:', rightText: dateStr, isBold: true));
    if (movementIds.isNotEmpty) {
      final idStr = movementIds.length == 1
          ? 'MOV-${movementIds.first.toString().padLeft(6, '0')}'
          : 'MOV-${movementIds.first.toString().padLeft(6, '0')}/${movementIds.last.toString().padLeft(6, '0')}';
      lines.add(TicketLine('COMPROBANTE:', rightText: idStr, isBold: true));
    }
    if (cashierName != null && cashierName.trim().isNotEmpty) {
      lines.add(TicketLine('CAJERO:', rightText: cashierName.trim().toUpperCase()));
    }
    lines.add(const TicketLine.hr());

    lines.add(const TicketLine('PROVEEDOR:', isBold: true));
    lines.add(TicketLine(supplierName.toUpperCase(), isBold: true, isLarge: true));
    final suppCuit = formatCuit(supplierCuit);
    if (suppCuit.isNotEmpty) {
      lines.add(TicketLine('CUIT: $suppCuit'));
    }
    if (description != null && description.trim().isNotEmpty) {
      lines.add(TicketLine('DETALLE: ${description.trim()}'));
    }
    if (receiptNumber != null && receiptNumber.trim().isNotEmpty) {
      lines.add(TicketLine('COMPROBANTE:', rightText: receiptNumber.trim()));
    }

    if (payments.length == 1) {
      final methodName = mapPaymentMethod(
        payments.first['payment_method'] as String? ?? 'cash',
        fundingSource: payments.first['funding_source'] as String?,
        shortForThermal: true,
      );
      lines.add(TicketLine(is58mm ? 'PAGO:' : 'MEDIO DE PAGO:', rightText: methodName));
    } else if (payments.length > 1) {
      lines.add(const TicketLine.hr());
      lines.add(const TicketLine('DESGLOSE DE PAGOS:', isBold: true));
      for (final p in payments) {
        final methodName = mapPaymentMethod(
          p['payment_method'] as String? ?? 'cash',
          fundingSource: p['funding_source'] as String?,
          shortForThermal: true,
        );
        final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
        lines.add(TicketLine(methodName, rightText: '\$${amount.toCurrency()}'));
      }
    }

    lines.add(const TicketLine.hr(bold: true));
    lines.add(TicketLine(
      type == 'deposit' ? 'TOTAL COBRADO:' : 'TOTAL ABONADO:',
      rightText: '\$${totalAmount.toCurrency()}',
      isBold: true,
      isLarge: true,
    ));

    if (balanceBefore != null) {
      lines.add(const TicketLine.hr());
      lines.add(const TicketLine('ESTADO DE CUENTA:', isBold: true));
      final isExpense = type == 'expense' || type == 'supplier_payment';
      final balanceAfter = isExpense ? balanceBefore - totalAmount : balanceBefore + totalAmount;
      lines.add(TicketLine('SALDO ANTERIOR:', rightText: '\$${balanceBefore.abs().toCurrency()}'));
      lines.add(TicketLine(
        isExpense ? 'ABONADO:' : 'DEUDA GENERADA:',
        rightText: '${isExpense ? '-' : '+'}\$${totalAmount.toCurrency()}',
      ));
      lines.add(const TicketLine.hr());
      final balanceLabel = balanceAfter > 0
          ? 'DEUDA RESTANTE:'
          : (balanceAfter < 0 ? 'SALDO A FAVOR:' : 'CUENTA AL DIA');
      lines.add(TicketLine(balanceLabel, rightText: '\$${balanceAfter.abs().toCurrency()}', isBold: true));
    }

    lines.add(const TicketLine.space());
    lines.add(const TicketLine.space());
    lines.add(TicketLine(
      is58mm ? '........................' : '................................',
      align: TicketAlign.center,
    ));
    lines.add(const TicketLine('Firma del Proveedor', align: TicketAlign.center));
    lines.add(const TicketLine.space());
    lines.add(const TicketLine.space());
    lines.add(TicketLine(
      is58mm ? '........................' : '................................',
      align: TicketAlign.center,
    ));
    lines.add(const TicketLine('Firma del Responsable', align: TicketAlign.center));
    lines.add(const TicketLine.space());
    lines.add(const TicketLine(
      '*** DOCUMENTO NO FISCAL ***',
      align: TicketAlign.center,
      isBold: true,
    ));

    return lines;
  }

  static List<TicketLine> buildSupplierStatementTicketLines({
    required String supplierName,
    required double currentBalance,
    required String businessName,
    String? businessTaxId,
    String? supplierCuit,
    bool is58mm = false,
  }) {
    final List<TicketLine> lines = [];
    lines.add(TicketLine(
      businessName.toUpperCase(),
      align: TicketAlign.center,
      isBold: true,
      isLarge: true,
    ));
    final cuitFormatted = formatCuit(businessTaxId);
    if (cuitFormatted.isNotEmpty) {
      lines.add(TicketLine('CUIT: $cuitFormatted', align: TicketAlign.center, isBold: true));
    }
    lines.add(const TicketLine.hr(bold: true));
    lines.add(const TicketLine('ESTADO DE CUENTA', align: TicketAlign.center, isBold: true));
    lines.add(const TicketLine.hr());
    lines.add(TicketLine('PROVEEDOR: ${supplierName.toUpperCase()}', isBold: true));
    final suppCuit = formatCuit(supplierCuit);
    if (suppCuit.isNotEmpty) {
      lines.add(TicketLine('CUIT: $suppCuit'));
    }
    lines.add(TicketLine('FECHA:', rightText: _dateFmt.format(DateTime.now())));
    lines.add(const TicketLine.space());
    lines.add(const TicketLine('SALDO ACTUAL:', isBold: true));
    final balanceText = currentBalance < 0
        ? 'A FAVOR: \$${currentBalance.abs().toCurrency()}'
        : (currentBalance > 0 ? 'DEUDA: \$${currentBalance.toCurrency()}' : 'CUENTA AL DIA (\$0,00)');
    lines.add(TicketLine(balanceText, align: TicketAlign.center, isBold: true, isLarge: true));
    lines.add(const TicketLine.hr(bold: true));
    lines.add(const TicketLine(
      '*** DOCUMENTO NO FISCAL ***',
      align: TicketAlign.center,
      isBold: true,
    ));
    return lines;
  }
}
