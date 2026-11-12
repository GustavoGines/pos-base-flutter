import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../core/utils/afip_fiscal_pdf_service.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/presentation/widgets/ticket_preview_dialog.dart';

class CashMovementPdfService {
  static final _numberFmt = NumberFormat('#,##0.00', 'es_AR');
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  static const _primary = PdfColor.fromInt(0xFF1A4B8C); // Azul corporativo
  static const _bgLight = PdfColor.fromInt(0xFFF5F7FA);
  static const _textGrey = PdfColor.fromInt(0xFF6B7280);

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

    final paperLabel = paperSize.toLowerCase() == 'letter' ? 'Carta' : 'A4';
    if (context.mounted) {
      await _showPdfPreviewDialog(
        context: context,
        title: 'Vista Previa de Comprobante ($paperLabel)',
        fileName: 'Comprobante_Caja_${movementIds.isNotEmpty ? movementIds.first : '00'}.pdf',
        pdfBytes: pdfBytes,
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
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey800, width: 1.0),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    ..._buildArcaStyleHeader(
                      businessName: businessName,
                      businessTaxId: businessTaxId,
                      businessSettings: businessSettings,
                      logoBytes: resolvedLogo,
                      titulo: titulo,
                      movementIds: movementIds,
                      cashierName: cashierName,
                      issuedAt: issuedAt,
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(14),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(10),
                            decoration: pw.BoxDecoration(
                              color: _bgLight,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                              border: pw.Border.all(color: PdfColors.grey300),
                            ),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                _buildInfoRow('CONCEPTO / CATEGORÍA:', category.toUpperCase()),
                                if (description != null && description.trim().isNotEmpty)
                                  _buildInfoRow('DETALLE / OBSERVACIÓN:', description.trim()),
                                if (receiptNumber != null && receiptNumber.trim().isNotEmpty)
                                  _buildInfoRow('Nº COMPROBANTE ASOC.:', receiptNumber.trim()),
                              ],
                            ),
                          ),
                          pw.SizedBox(height: 14),
                          _buildPaymentBreakdown(
                            payments,
                            totalAmount,
                            type == 'deposit',
                            totalLabel: type == 'deposit' ? 'TOTAL INGRESADO:' : 'TOTAL EGRESADO:',
                          ),
                          pw.SizedBox(height: 28),
                          _buildSignatures(
                            leftLabel: 'Firma quien entrega',
                            rightLabel: 'Firma quien recibe / Conforme',
                          ),
                        ],
                      ),
                    ),
                    _buildVoucherFooter(businessName),
                  ],
                ),
              ),
            ],
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

    final paperLabel = paperSize.toLowerCase() == 'letter' ? 'Carta' : 'A4';
    if (context.mounted) {
      await _showPdfPreviewDialog(
        context: context,
        title: 'Vista Previa de Pago a Proveedor ($paperLabel)',
        fileName: 'Comprobante_Proveedor_${movementIds.isNotEmpty ? movementIds.first : '00'}.pdf',
        pdfBytes: pdfBytes,
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
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey800, width: 1.0),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    ..._buildArcaStyleHeader(
                      businessName: businessName,
                      businessTaxId: businessTaxId,
                      businessSettings: businessSettings,
                      logoBytes: resolvedLogo,
                      titulo: titulo,
                      movementIds: movementIds,
                      cashierName: cashierName,
                      issuedAt: issuedAt,
                    ),
                    // Casillero de Receptor / Proveedor estilo ARCA
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                        color: _bgLight,
                        border: pw.Border(
                          bottom: pw.BorderSide(color: PdfColors.grey800, width: 1.0),
                        ),
                      ),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'PROVEEDOR / RAZÓN SOCIAL:',
                                  style: pw.TextStyle(
                                    color: _textGrey,
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  supplierName.toUpperCase(),
                                  style: pw.TextStyle(
                                    fontSize: 13,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (formattedSupplierCuit.isNotEmpty)
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.white,
                                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                                border: pw.Border.all(color: PdfColors.grey400),
                              ),
                              child: pw.Text(
                                'CUIT: $formattedSupplierCuit',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(14),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          if ((description != null && description.trim().isNotEmpty) ||
                              (receiptNumber != null && receiptNumber.trim().isNotEmpty)) ...[
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.grey100,
                                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                                border: pw.Border.all(color: PdfColors.grey300),
                              ),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  if (description != null && description.trim().isNotEmpty)
                                    _buildInfoRow('DETALLE / CONCEPTO:', description.trim()),
                                  if (receiptNumber != null && receiptNumber.trim().isNotEmpty)
                                    _buildInfoRow('COMPROBANTE / REF.:', receiptNumber.trim()),
                                ],
                              ),
                            ),
                            pw.SizedBox(height: 12),
                          ],
                          _buildPaymentBreakdown(
                            payments,
                            totalAmount,
                            type == 'deposit',
                            totalLabel: type == 'deposit' ? 'TOTAL COBRADO:' : 'TOTAL ABONADO:',
                          ),
                          if (balanceBefore != null) ...[
                            pw.SizedBox(height: 12),
                            _buildSupplierBalance(
                              balanceBefore,
                              totalAmount,
                              type == 'expense' || type == 'supplier_payment',
                            ),
                          ],
                          pw.SizedBox(height: 28),
                          _buildSignatures(
                            leftLabel: 'Firma quien entrega (Comercio)',
                            rightLabel: 'Firma quien recibe / Conforme (Proveedor)',
                          ),
                        ],
                      ),
                    ),
                    _buildVoucherFooter(businessName),
                  ],
                ),
              ),
            ],
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
              height: MediaQuery.of(ctx).size.height * 0.90,
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf, color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
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
                      pdfFileName: fileName,
                      build: (format) async => pdfBytes,
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

  // --- Helpers PDF ---

  static List<pw.Widget> _buildArcaStyleHeader({
    required String businessName,
    required String? businessTaxId,
    required dynamic businessSettings,
    required Uint8List? logoBytes,
    required String titulo,
    required List<int> movementIds,
    required String? cashierName,
    DateTime? issuedAt,
  }) {
    String movNumber = 'S/N';
    if (movementIds.isNotEmpty) {
      if (movementIds.length == 1) {
        movNumber = 'MOV-${movementIds.first.toString().padLeft(6, '0')}';
      } else {
        movNumber = 'MOV-${movementIds.first.toString().padLeft(6, '0')}/${movementIds.last.toString().padLeft(6, '0')}';
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

    return [
      // Barra Superior ORIGINAL / DOCUMENTO NO VÁLIDO COMO FACTURA
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        decoration: const pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey800, width: 1.0),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'ORIGINAL',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            pw.Text(
              'DOCUMENTO INTERNO - NO VÁLIDO COMO FACTURA',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
          ],
        ),
      ),

      // Encabezado Partido con Letra [X] Central
      pw.Stack(
        alignment: pw.Alignment.topCenter,
        children: [
          pw.Table(
            border: const pw.TableBorder(
              bottom: pw.BorderSide(color: PdfColors.grey800, width: 1.0),
              verticalInside: pw.BorderSide(color: PdfColors.grey800, width: 1.0),
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
                    padding: const pw.EdgeInsets.fromLTRB(10, 10, 28, 10),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (safeLogoImage != null) ...[
                          pw.Container(
                            width: 42,
                            height: 42,
                            child: pw.Image(
                              safeLogoImage,
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
                                  fontSize: 15,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _primary,
                                ),
                              ),
                              pw.SizedBox(height: 3),
                              if (address != null && address.trim().isNotEmpty)
                                pw.Text(
                                  'Domicilio: ${address.trim()}',
                                  style: const pw.TextStyle(fontSize: 8),
                                ),
                              if (phone != null && phone.trim().isNotEmpty)
                                pw.Text(
                                  'Teléfono: ${phone.trim()}',
                                  style: const pw.TextStyle(fontSize: 8),
                                ),
                              if (taxCond.isNotEmpty)
                                pw.Text(
                                  'Cond. IVA: $taxCond',
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Columna Derecha: Datos del Comprobante
                  pw.Padding(
                    padding: const pw.EdgeInsets.fromLTRB(28, 10, 10, 10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          titulo,
                          style: pw.TextStyle(
                            fontSize: 12.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Comp. Nro: $movNumber',
                          style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Fecha de Emisión: ${_dateFmt.format(effectiveDate)}',
                          style: const pw.TextStyle(fontSize: 8.5),
                        ),
                        if (formattedEmitterCuit.isNotEmpty)
                          pw.Text(
                            'CUIT: $formattedEmitterCuit',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (iibb != null && iibb.trim().isNotEmpty)
                          pw.Text(
                            'Ing. Brutos: ${iibb.trim()}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        if (cashierName != null && cashierName.trim().isNotEmpty)
                          pw.Text(
                            'Operador / Caja: ${cashierName.trim().toUpperCase()}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Recuadro Central [X]
          pw.Positioned(
            top: 0,
            child: pw.Container(
              width: 40,
              height: 40,
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: PdfColors.grey800, width: 1.5),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    'X',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.Text(
                    'NO FISCAL',
                    style: pw.TextStyle(
                      fontSize: 5.2,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(
              label,
              style: pw.TextStyle(color: _textGrey, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPaymentBreakdown(
    List<Map<String, dynamic>> payments,
    double total,
    bool isDeposit, {
    required String totalLabel,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        children: [
          // Cabecera desglose
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey900,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(5),
                topRight: pw.Radius.circular(5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'MEDIO DE PAGO / ORIGEN DE FONDOS',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
                pw.Text(
                  'IMPORTE',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          // Filas
          ...payments.map((p) {
            final method = mapPaymentMethod(
              p['payment_method'] as String? ?? 'cash',
              fundingSource: p['funding_source'] as String?,
            );
            final amount = (p['amount'] as num).toDouble();
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(method, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text(formatCurrency(amount), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            );
          }),
          // Total
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
            ),
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: pw.BoxDecoration(
                color: isDeposit ? const PdfColor.fromInt(0xFFE8F5E9) : const PdfColor.fromInt(0xFFFFEBEE),
                borderRadius: const pw.BorderRadius.only(
                  bottomLeft: pw.Radius.circular(5),
                  bottomRight: pw.Radius.circular(5),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    totalLabel,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                  ),
                  pw.Text(
                    formatCurrency(total),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSupplierBalance(double balanceBefore, double totalAmount, bool isExpense) {
    final balanceAfter = isExpense ? balanceBefore - totalAmount : balanceBefore + totalAmount;
    final balanceLabel = balanceAfter > 0
        ? 'SALDO DEUDOR RESTANTE:'
        : (balanceAfter < 0 ? 'SALDO A FAVOR DEL COMERCIO:' : 'CUENTA AL DÍA (SALDO \$ 0,00)');

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: _bgLight,
        border: pw.Border.all(color: _primary, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'RESUMEN DE ESTADO DE CUENTA CORRIENTE',
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _primary),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Saldo Anterior:', style: const pw.TextStyle(fontSize: 10)),
              pw.Text(formatCurrency(balanceBefore.abs()), style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(isExpense ? 'Importe Abonado en este recibo:' : 'Importe Imputado:', style: const pw.TextStyle(fontSize: 10)),
              pw.Text(
                '${isExpense ? '-' : '+'} ${formatCurrency(totalAmount)}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.Divider(color: PdfColors.grey400, height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(balanceLabel, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11.5)),
              pw.Text(formatCurrency(balanceAfter.abs()), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatures({
    required String leftLabel,
    required String rightLabel,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          pw.Column(
            children: [
              pw.Container(width: 190, height: 1, color: PdfColors.grey800),
              pw.SizedBox(height: 5),
              pw.Text(leftLabel, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
              pw.Text('Aclaración / DNI', style: const pw.TextStyle(fontSize: 8, color: _textGrey)),
            ],
          ),
          pw.Column(
            children: [
              pw.Container(width: 190, height: 1, color: PdfColors.grey800),
              pw.SizedBox(height: 5),
              pw.Text(rightLabel, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
              pw.Text('Aclaración / DNI', style: const pw.TextStyle(fontSize: 8, color: _textGrey)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildVoucherFooter(String businessName) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Comprobante interno emitido por $businessName',
            style: const pw.TextStyle(fontSize: 7.5, color: _textGrey),
          ),
          pw.Text(
            '*** DOCUMENTO NO VÁLIDO COMO FACTURA ***',
            style: pw.TextStyle(fontSize: 7.5, color: _textGrey, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
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
