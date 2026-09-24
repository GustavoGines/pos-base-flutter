import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../domain/entities/cash_register_shift.dart';

class ZClosePdfService {
  static const _primaryColor = PdfColor.fromInt(0xFF1565C0); // Blue 800
  static const _textGrey = PdfColor.fromInt(0xFF757575);
  static const _bgLight = PdfColor.fromInt(0xFFF5F5F5);

  static Future<void> printZClose({
    required BuildContext context,
    required CashRegisterShift shift,
    required String businessName,
    required String? businessTaxId,
    required bool isPremium,
  }) async {
    final pdfBytes = await _generateZCloseBytes(
      shift: shift,
      businessName: businessName,
      businessTaxId: businessTaxId,
      isPremium: isPremium,
    );

    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          child: SizedBox(
            width: 500,
            height: 700,
            child: Scaffold(
              appBar: AppBar(title: const Text('Cierre Z - Vista Previa')),
              body: PdfPreview(
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                pdfFileName: 'Cierre_Z_${shift.id}.pdf',
                build: (format) async => pdfBytes,
              ),
            ),
          ),
        ),
      );
    }
  }

  static Future<Uint8List> _generateZCloseBytes({
    required CashRegisterShift shift,
    required String businessName,
    required String? businessTaxId,
    required bool isPremium,
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
    final currencyFmt = NumberFormat.currency(symbol: '\$');
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    final openedAtStr = dateFmt.format(shift.openedAt);
    final closedAtStr = shift.closedAt != null ? dateFmt.format(shift.closedAt!) : 'En curso';

    final cashSales = shift.cashSales ?? 0;
    final otherIncomes = shift.totalDeposits ?? 0;
    final expenses = shift.totalExpenses ?? 0;
    final ownerWithdrawals = shift.totalWithdrawals ?? 0;
      final supplierPayments = shift.totalSupplierPayments ?? 0;
      final refunds = shift.totalRefunds ?? 0;
    
    // El total de gastos es negativo o positivo? En la base es positivo normalmente, pero en el resumen lo mostramos como salida
    
    final expectedCash = shift.openingBalance + cashSales + otherIncomes - expenses - ownerWithdrawals - supplierPayments - refunds;
    final physicalCash = shift.actualBalance ?? 0;
    final difference = shift.difference ?? (physicalCash - expectedCash);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Cabecera
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
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
                      pw.Text('CIERRE Z', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('Turno #${shift.id}', style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),

              // Datos del Turno
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(color: _bgLight, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('CAJA:', style: pw.TextStyle(fontSize: 10, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                        pw.Text(shift.cashRegisterName ?? 'Caja Principal', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 12),
                        pw.Text('APERTURA:', style: pw.TextStyle(fontSize: 10, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                        pw.Text(openedAtStr, style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('USUARIO:', style: pw.TextStyle(fontSize: 10, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                        pw.Text(shift.userName ?? '-', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 12),
                        pw.Text('CIERRE:', style: pw.TextStyle(fontSize: 10, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                        pw.Text(closedAtStr, style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Resumen Financiero
              pw.Text('RESUMEN FINANCIERO', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
              pw.Divider(color: _primaryColor),
              pw.SizedBox(height: 12),
              
              _buildRow('Fondo Inicial de Caja:', currencyFmt.format(shift.openingBalance)),
              pw.SizedBox(height: 8),
              _buildRow('Ventas en Efectivo:', currencyFmt.format(cashSales), isPositive: true),
              if (isPremium || otherIncomes > 0)
                _buildRow('Ingresos Extra:', currencyFmt.format(otherIncomes), isPositive: true),
              pw.SizedBox(height: 4),
              if (isPremium || expenses > 0)
                _buildRow('Gastos Registrados (Salida):', '-${currencyFmt.format(expenses)}', isNegative: true),
              if (isPremium || ownerWithdrawals > 0)
                _buildRow('Retiros de Dueño (Salida):', '-${currencyFmt.format(ownerWithdrawals)}', isNegative: true),
              if (isPremium || supplierPayments > 0) 
                _buildRow('Pagos a Proveedores (Salida):', '-${currencyFmt.format(supplierPayments)}', isNegative: true),
              if (refunds > 0) 
                _buildRow('Reintegros por Devolución (Salida):', '-${currencyFmt.format(refunds)}', isNegative: true),
              
              pw.SizedBox(height: 12),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 12),

              _buildRow('Ventas con Tarjeta (Deb/Cred):', currencyFmt.format(shift.cardSales ?? 0)),
              _buildRow('Ventas por Transferencia:', currencyFmt.format(shift.transferSales ?? 0)),
              _buildRow('Recargos Cobrados:', currencyFmt.format(shift.totalSurcharge ?? 0)),
              if (isPremium || (shift.checkSales ?? 0) > 0)
                _buildRow('Valores en Cheques:', currencyFmt.format(shift.checkSales ?? 0)),

              pw.SizedBox(height: 24),
              pw.Text('ARQUEO DE CAJA', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
              pw.Divider(color: _primaryColor),
              pw.SizedBox(height: 12),

              _buildRow('Efectivo Esperado en Sistema:', currencyFmt.format(expectedCash), bold: true),
              pw.SizedBox(height: 4),
              _buildRow('Efectivo Físico Declarado:', currencyFmt.format(physicalCash), bold: true),
              
              pw.SizedBox(height: 12),
              
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: difference == 0 ? PdfColors.grey200 : (difference > 0 ? PdfColors.green100 : PdfColors.red100),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  border: pw.Border.all(color: difference == 0 ? PdfColors.grey400 : (difference > 0 ? PdfColors.green400 : PdfColors.red400))
                ),
                child: _buildRow(
                  difference == 0 ? 'DIFERENCIA:' : (difference > 0 ? 'SOBRANTE DE CAJA:' : 'FALTANTE DE CAJA:'),
                  currencyFmt.format(difference.abs()),
                  bold: true,
                  color: difference == 0 ? PdfColors.grey800 : (difference > 0 ? PdfColors.green800 : PdfColors.red800)
                ),
              ),

              pw.Spacer(),

              // Firma
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 200, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 8),
                      pw.Text('Firma del Cajero', style: const pw.TextStyle(fontSize: 10, color: _textGrey)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text('Comprobante generado por Antigravity POS', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey400)),
              )
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildRow(String label, String value, {bool bold = false, bool isPositive = false, bool isNegative = false, PdfColor? color}) {
    PdfColor? finalColor = color;
    if (finalColor == null) {
      if (isPositive) finalColor = PdfColors.green700;
      if (isNegative) finalColor = PdfColors.red700;
    }
    
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 12, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: finalColor)),
      ],
    );
  }
}

