import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/currency_formatter.dart';

class SupplierStatementPdfService {
  static const _primaryColor = PdfColor.fromInt(0xFF1E88E5); // Blue 600
  static const _textGrey = PdfColor.fromInt(0xFF757575);
  static const _bgLight = PdfColor.fromInt(0xFFF5F5F5);

  static Future<void> printStatement({
    required BuildContext context,
    required String supplierName,
    required String? supplierCuit,
    required List<dynamic> history,
    required double currentBalance,
    required String businessName,
    required String? businessTaxId,
    DateTimeRange? dateRange,
  }) async {
    final pdfBytes = await _generateStatementBytes(
      supplierName: supplierName,
      supplierCuit: supplierCuit,
      history: history,
      currentBalance: currentBalance,
      businessName: businessName,
      businessTaxId: businessTaxId,
      dateRange: dateRange,
    );

    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          child: SizedBox(
            width: 800,
            height: 600,
            child: Scaffold(
              appBar: AppBar(title: const Text('Estado de Cuenta - Vista Previa')),
              body: PdfPreview(
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                pdfFileName: 'Estado_Cuenta_$supplierName.pdf',
                build: (format) async => pdfBytes,
              ),
            ),
          ),
        ),
      );
    }
  }

  static Future<Uint8List> _generateStatementBytes({
    required String supplierName,
    required String? supplierCuit,
    required List<dynamic> history,
    required double currentBalance,
    required String businessName,
    required String? businessTaxId,
    DateTimeRange? dateRange,
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
    final dateFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');

    // Dividimos el historial en páginas (ej. 20 items por página)
    const itemsPerPage = 20;
    final totalPages = (history.isEmpty ? 1 : (history.length / itemsPerPage).ceil());

    for (var i = 0; i < totalPages; i++) {
      final startIndex = i * itemsPerPage;
      final endIndex = (startIndex + itemsPerPage < history.length) ? startIndex + itemsPerPage : history.length;
      final pageItems = history.sublist(startIndex, endIndex);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header (solo en primera página)
                if (i == 0) ...[
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(businessName.toUpperCase(), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
                          if (businessTaxId != null && businessTaxId.isNotEmpty)
                            pw.Text('CUIT: $businessTaxId', style: const pw.TextStyle(fontSize: 12, color: _textGrey)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('ESTADO DE CUENTA', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text('Fecha Emisión: ${dateFmt.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 24),
                  
                  // Resumen
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Proveedor
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(12),
                          decoration: pw.BoxDecoration(color: _bgLight, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
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
                      ),
                      pw.SizedBox(width: 16),
                      // Filtro / Deuda
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(12),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: _primaryColor, width: 2),
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              if (dateRange != null) ...[
                                pw.Text('PERÍODO:', style: pw.TextStyle(color: _textGrey, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                                pw.Text('${dateFmt.format(dateRange.start)} - ${dateFmt.format(dateRange.end)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                                pw.SizedBox(height: 8),
                              ],
                              pw.Text('SALDO TOTAL:', style: pw.TextStyle(color: _textGrey, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                              pw.Text(
                                '\$${currentBalance.abs().toCurrency()}', 
                                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _primaryColor)
                              ),
                              pw.Text(currentBalance > 0 ? '(DEUDA)' : (currentBalance < 0 ? '(A FAVOR)' : '(AL DÍA)'), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 24),
                ],

                // Título de la tabla
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
                  child: pw.Text('DETALLE DE MOVIMIENTOS', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                ),
                
                // Tabla header
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(flex: 2, child: pw.Text('FECHA', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                      pw.Expanded(flex: 3, child: pw.Text('CONCEPTO', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                      pw.Expanded(flex: 2, child: pw.Text('COMPROBANTE', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                      pw.Expanded(flex: 2, child: pw.Text('IMPORTE', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                      pw.Expanded(flex: 2, child: pw.Text('SALDO', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                ),

                // Filas
                if (pageItems.isEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(24),
                    child: pw.Center(child: pw.Text('No hay movimientos en este período.', style: const pw.TextStyle(color: _textGrey))),
                  )
                else
                  ...pageItems.map((item) {
                    final date = DateTime.tryParse(item['date'].toString()) ?? DateTime.now();
                    final formattedDate = '${dateFmt.format(date)} ${timeFmt.format(date)}';
                    
                    String actionLabel = '';
                    if (item['source'] == 'invoice') {
                      actionLabel = item['type'] == 'invoice' ? 'Factura / Remito' : 'Nota de Crédito';
                    } else {
                      actionLabel = item['type'] == 'deposit' ? 'Ajuste Saldo' : 'Pago Entregado';
                    }

                    final amount = double.tryParse(item['amount'].toString()) ?? 0;
                    final runningBalance = double.tryParse(item['running_balance'].toString()) ?? 0;
                    final isIncrease = (item['source'] == 'invoice' && item['type'] == 'invoice') || 
                                       (item['source'] == 'payment' && item['type'] == 'deposit');
                    
                    final colorAmount = isIncrease ? PdfColors.red700 : PdfColors.green700;
                    final amountText = '${isIncrease ? '+' : '-'}\$${amount.toCurrency()}';

                    return pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
                      child: pw.Row(
                        children: [
                          pw.Expanded(flex: 2, child: pw.Text(formattedDate, style: const pw.TextStyle(fontSize: 10))),
                          pw.Expanded(flex: 3, child: pw.Text(actionLabel, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                          pw.Expanded(flex: 2, child: pw.Text(item['invoice_number']?.toString() ?? '-', style: const pw.TextStyle(fontSize: 10))),
                          pw.Expanded(flex: 2, child: pw.Text(amountText, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, color: colorAmount, fontWeight: pw.FontWeight.bold))),
                          pw.Expanded(flex: 2, child: pw.Text('\$${runningBalance.toCurrency()}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10))),
                        ],
                      ),
                    );
                  }),

                pw.Spacer(),

                // Paginación
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('Página ${i + 1} de $totalPages', style: const pw.TextStyle(fontSize: 10, color: _textGrey)),
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }
}
