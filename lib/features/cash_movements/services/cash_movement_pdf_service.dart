import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

class CashMovementPdfService {
  static final _currencyFmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  static const _primary = PdfColor.fromInt(0xFF1A4B8C); // Azul corporativo
  static const _bgLight = PdfColor.fromInt(0xFFF5F7FA);
  static const _textGrey = PdfColor.fromInt(0xFF6B7280);

  static Future<void> printGenericMovement({
    required BuildContext context,
    required String type,
    required String category,
    required double totalAmount,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessTaxId,
    List<int> movementIds = const [],
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
  }) async {
    final pdfBytes = await _generateGenericPdfBytes(
      type: type,
      category: category,
      totalAmount: totalAmount,
      payments: payments,
      businessName: businessName,
      businessTaxId: businessTaxId,
      movementIds: movementIds,
      description: description,
      receiptNumber: receiptNumber,
      cashierName: cashierName,
      paperSize: paperSize,
    );

    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          child: SizedBox(
            width: 800,
            height: 600,
            child: Scaffold(
              appBar: AppBar(title: const Text('Vista Previa de Comprobante')),
              body: PdfPreview(
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                pdfFileName: 'Comprobante_Caja_${movementIds.isNotEmpty ? movementIds.first : '00'}.pdf',
                build: (format) async => pdfBytes,
              ),
            ),
          ),
        ),
      );
    }
  }

  static Future<Uint8List> _generateGenericPdfBytes({
    required String type,
    required String category,
    required double totalAmount,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessTaxId,
    List<int> movementIds = const [],
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
  }) async {
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
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(businessName, businessTaxId, titulo, movementIds, cashierName),
              pw.SizedBox(height: 20),
              
              _buildInfoRow('Categoría:', category.toUpperCase()),
              if (description != null && description.isNotEmpty)
                _buildInfoRow('Detalle:', description),
              if (receiptNumber != null && receiptNumber.isNotEmpty)
                _buildInfoRow('Nº Comprobante / Ref:', receiptNumber),
              
              pw.SizedBox(height: 20),
              _buildPaymentBreakdown(payments, totalAmount, type == 'deposit'),
              
              pw.Spacer(),
              _buildSignatures(),
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
    List<int> movementIds = const [],
    String? supplierCuit,
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
  }) async {
    final pdfBytes = await _generateSupplierPdfBytes(
      type: type,
      supplierName: supplierName,
      totalAmount: totalAmount,
      balanceBefore: balanceBefore,
      payments: payments,
      businessName: businessName,
      businessTaxId: businessTaxId,
      movementIds: movementIds,
      supplierCuit: supplierCuit,
      description: description,
      receiptNumber: receiptNumber,
      cashierName: cashierName,
      paperSize: paperSize,
    );

    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          child: SizedBox(
            width: 800,
            height: 600,
            child: Scaffold(
              appBar: AppBar(title: const Text('Vista Previa de Pago a Proveedor')),
              body: PdfPreview(
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                pdfFileName: 'Comprobante_Proveedor_${movementIds.isNotEmpty ? movementIds.first : '00'}.pdf',
                build: (format) async => pdfBytes,
              ),
            ),
          ),
        ),
      );
    }
  }

  static Future<Uint8List> _generateSupplierPdfBytes({
    required String type,
    required String supplierName,
    required double totalAmount,
    double? balanceBefore,
    required List<Map<String, dynamic>> payments,
    required String businessName,
    String? businessTaxId,
    List<int> movementIds = const [],
    String? supplierCuit,
    String? description,
    String? receiptNumber,
    String? cashierName,
    String paperSize = 'a4',
  }) async {
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

    final titulo = type == 'deposit' ? 'COBRO DE SALDO A FAVOR' : 'PAGO A PROVEEDOR';

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(businessName, businessTaxId, titulo, movementIds, cashierName),
              pw.SizedBox(height: 20),
              
              // Datos del Proveedor
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: _bgLight,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('PROVEEDOR:', style: pw.TextStyle(color: _textGrey, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(supplierName.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    if (supplierCuit != null && supplierCuit.isNotEmpty)
                      pw.Text('CUIT: $supplierCuit', style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 12),
              
              if (description != null && description.isNotEmpty)
                _buildInfoRow('Detalle:', description),
              if (receiptNumber != null && receiptNumber.isNotEmpty)
                _buildInfoRow('Nº Comprobante / Ref:', receiptNumber),
              
              pw.SizedBox(height: 20),
              _buildPaymentBreakdown(payments, totalAmount, type == 'deposit'),
              
              pw.SizedBox(height: 20),
              if (balanceBefore != null)
                _buildSupplierBalance(balanceBefore, totalAmount, type == 'expense' || type == 'supplier_payment'),

              pw.Spacer(),
              _buildSignatures(),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // --- Helpers ---

  static pw.Widget _buildHeader(String businessName, String? businessTaxId, String titulo, List<int> movementIds, String? cashierName) {
    String movNumber = '';
    if (movementIds.isNotEmpty) {
      if (movementIds.length == 1) {
        movNumber = 'MOV-${movementIds.first.toString().padLeft(6, '0')}';
      } else {
        movNumber = 'MOV-${movementIds.first.toString().padLeft(6, '0')}/${movementIds.last.toString().padLeft(6, '0')}';
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(businessName.toUpperCase(), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _primary)),
                if (businessTaxId != null && businessTaxId.isNotEmpty)
                  pw.Text('CUIT: $businessTaxId', style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(titulo, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('FECHA: ${_dateFmt.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 12)),
                if (movNumber.isNotEmpty)
                  pw.Text('Nº: $movNumber', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                if (cashierName != null)
                  pw.Text('CAJERO: ${cashierName.toUpperCase()}', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: _primary, thickness: 2),
      ]
    );
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label, style: pw.TextStyle(color: _textGrey, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPaymentBreakdown(List<Map<String, dynamic>> payments, double total, bool isDeposit) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          // Cabecera desglose
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: const pw.BoxDecoration(
              color: _bgLight,
              borderRadius: pw.BorderRadius.only(topLeft: pw.Radius.circular(7), topRight: pw.Radius.circular(7)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('MÉTODO DE PAGO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text('IMPORTE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ],
            ),
          ),
          // Filas
          ...payments.map((p) {
            final method = _mapPaymentMethod(p['payment_method'] as String? ?? 'cash');
            final amount = (p['amount'] as num).toDouble();
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey200)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(method, style: const pw.TextStyle(fontSize: 12)),
                  pw.Text(_currencyFmt.format(amount), style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
            );
          }),
          // Total
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: isDeposit ? PdfColor.fromInt(0xFFE8F5E9) : PdfColor.fromInt(0xFFFFEBEE), // Verde suave o Rojo suave
              borderRadius: const pw.BorderRadius.only(bottomLeft: pw.Radius.circular(7), bottomRight: pw.Radius.circular(7)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(isDeposit ? 'TOTAL COBRADO:' : 'TOTAL ABONADO:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Text(_currencyFmt.format(total), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSupplierBalance(double balanceBefore, double totalAmount, bool isExpense) {
    // Si es un egreso (pago a proveedor), RESTA la deuda. Si es un ingreso (cobro de saldo a favor), SUMA a la deuda.
    final balanceAfter = isExpense ? balanceBefore - totalAmount : balanceBefore + totalAmount;
    final balanceLabel = balanceAfter > 0 ? 'DEUDA RESTANTE:' : (balanceAfter < 0 ? 'SALDO A FAVOR:' : 'CUENTA AL DÍA');

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _primary),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('ESTADO DE CUENTA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _primary)),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Saldo Anterior:', style: const pw.TextStyle(fontSize: 12)),
              pw.Text(_currencyFmt.format(balanceBefore.abs()), style: const pw.TextStyle(fontSize: 12)),
            ]
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(isExpense ? 'Abonado:' : 'Deuda Generada:', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('${isExpense ? '-' : '+'} ${_currencyFmt.format(totalAmount)}', style: const pw.TextStyle(fontSize: 12)),
            ]
          ),
          pw.Divider(color: PdfColors.grey300),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(balanceLabel, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Text(_currencyFmt.format(balanceAfter.abs()), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            ]
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatures() {
    return pw.Column(
      children: [
        pw.Text('*** DOCUMENTO NO FISCAL ***', style: pw.TextStyle(fontSize: 10, color: _textGrey, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 40),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            pw.Column(
              children: [
                pw.Container(width: 200, height: 1, color: PdfColors.black),
                pw.SizedBox(height: 4),
                pw.Text('Firma quien entrega', style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
            pw.Column(
              children: [
                pw.Container(width: 200, height: 1, color: PdfColors.black),
                pw.SizedBox(height: 4),
                pw.Text('Firma quien recibe / Conforme', style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ]
    );
  }

  static String _mapPaymentMethod(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'EFECTIVO';
      case 'transfer':
        return 'TRANSFERENCIA';
      case 'check':
        return 'CHEQUE';
      default:
        return method.toUpperCase();
    }
  }
}
