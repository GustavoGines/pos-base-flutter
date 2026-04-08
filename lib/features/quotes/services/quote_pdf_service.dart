import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/quote_repository.dart';

/// Servicio que genera el PDF del presupuesto y abre WhatsApp.
/// No depende de Flutter widgets — puede llamarse desde cualquier contexto.
class QuotePdfService {
  static final _currencyFmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);
  static final _dateFmt = DateFormat('dd/MM/yyyy', 'es_AR');

  /// Genera el PDF, lo guarda en el directorio de descargas, lo muestra al
  /// usuario (preview) y luego abre WhatsApp con un mensaje prearmado.
  static Future<String?> generateAndShare({
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
  }) async {
    try {
      final pdfBytes = await _buildPdf(
        quote: quote,
        businessName: businessName,
        businessAddress: businessAddress,
        businessPhone: businessPhone,
      );

      // ── Guardar archivo ──────────────────────────────────────────────────
      final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final filename = '${quote.quoteNumber}.pdf';
      final file = File('${dir.path}${Platform.pathSeparator}$filename');
      await file.writeAsBytes(pdfBytes);

      return file.path;
    } catch (e) {
      debugPrint('QuotePdfService error: $e');
      return null;
    }
  }

  /// Solo preview en pantalla (usa printing).
  static Future<void> preview({
    required BuildContext context,
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
  }) async {
    await Printing.layoutPdf(
      onLayout: (_) async => _buildPdf(
        quote: quote,
        businessName: businessName,
        businessAddress: businessAddress,
        businessPhone: businessPhone,
      ),
      name: quote.quoteNumber,
    );
  }

  /// Abre WhatsApp con mensaje prearmado.
  static Future<void> openWhatsApp({
    required Quote quote,
    required String businessName,
    String? phone,
  }) async {
    final total = _currencyFmt.format(quote.total);
    final msg = Uri.encodeComponent(
      '¡Hola! Te escribo de $businessName. '
      'Te adjunto el presupuesto **${quote.quoteNumber}** por un total de $total. '
      '(Adjuntá el PDF que se acaba de generar y guardar en tu carpeta de Descargas) '
      '${quote.notes != null && quote.notes!.isNotEmpty ? "\n\nCondiciones: ${quote.notes}" : ""}'
      '\n\n¡Quedamos a tu disposición!',
    );

    // Si se conoce el teléfono del cliente, enviamos al contacto directo.
    // Si no, abre el selector de chat de WhatsApp Desktop/Web.
    final rawPhone = (phone ?? '').replaceAll(RegExp(r'[^\d]'), '');
    final waUrl = rawPhone.isNotEmpty
        ? 'https://wa.me/$rawPhone?text=$msg'
        : 'https://wa.me/?text=$msg';

    final uri = Uri.parse(waUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── PDF Builder ──────────────────────────────────────────────────────────

  static Future<Uint8List> _buildPdf({
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
  }) async {
    final doc = pw.Document();

    // Paleta de colores
    const primary = PdfColor.fromInt(0xFF1A4B8C);    // azul corporativo
    const accent = PdfColor.fromInt(0xFF2E7D32);     // verde para totales
    const bgLight = PdfColor.fromInt(0xFFF5F7FA);
    const textGrey = PdfColor.fromInt(0xFF6B7280);

    final currFmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── HEADER ──────────────────────────────────────────────────
              pw.Container(
                decoration: const pw.BoxDecoration(
                  color: primary,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(businessName,
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                            )),
                        if (businessAddress != null)
                          pw.Text(businessAddress,
                              style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10)),
                        if (businessPhone != null)
                          pw.Text('Tel: $businessPhone',
                              style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('PRESUPUESTO',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                            )),
                        pw.Text(quote.quoteNumber,
                            style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 13)),
                        pw.Text(
                          'Fecha: ${_dateFmt.format(DateTime.now())}',
                          style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10),
                        ),
                        if (quote.validUntil != null)
                          pw.Text(
                            'Válido hasta: ${_dateFmt.format(DateTime.parse(quote.validUntil!))}',
                            style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // ── DATOS CLIENTE ────────────────────────────────────────────
              if (quote.customerName != null || quote.customerPhone != null) ...[
                pw.Container(
                  decoration: const pw.BoxDecoration(
                    color: bgLight,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('CLIENTE', style: pw.TextStyle(fontSize: 9, color: textGrey, fontWeight: pw.FontWeight.bold)),
                            pw.SizedBox(height: 4),
                            if (quote.customerName != null)
                              pw.Text(quote.customerName!, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                            if (quote.customerPhone != null)
                              pw.Text('Tel: ${quote.customerPhone}', style: const pw.TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
              ],

              // ── TABLA DE ÍTEMS ───────────────────────────────────────────
              pw.Table(
                border: pw.TableBorder(
                  bottom: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  horizontalInside: const pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(5),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: primary),
                    children: [
                      _th('DESCRIPCIÓN'),
                      _th('CANT.', align: pw.TextAlign.center),
                      _th('PRECIO UNIT.', align: pw.TextAlign.right),
                      _th('SUBTOTAL', align: pw.TextAlign.right),
                    ],
                  ),
                  // Items
                  ...quote.items.asMap().entries.map((e) {
                    final i = e.key;
                    final item = e.value;
                    final isEven = i % 2 == 0;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : bgLight),
                      children: [
                        _td(item.productName),
                        _td(
                          item.quantity % 1 == 0
                              ? item.quantity.toInt().toString()
                              : item.quantity.toStringAsFixed(3),
                          align: pw.TextAlign.center,
                        ),
                        _td(currFmt.format(item.unitPrice), align: pw.TextAlign.right),
                        _td(currFmt.format(item.subtotal), align: pw.TextAlign.right),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 16),

              // ── TOTALES ──────────────────────────────────────────────────
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 240,
                  decoration: const pw.BoxDecoration(
                    color: bgLight,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Column(
                    children: [
                      _totalRow('Subtotal', currFmt.format(quote.subtotal)),
                      pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                      _totalRow(
                        'TOTAL',
                        currFmt.format(quote.total),
                        bold: true,
                        valueColor: accent,
                        labelColor: primary,
                      ),
                    ],
                  ),
                ),
              ),

              // ── NOTAS ────────────────────────────────────────────────────
              if (quote.notes != null && quote.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text('Condiciones y Observaciones',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: textGrey)),
                pw.SizedBox(height: 4),
                pw.Text(quote.notes!, style: const pw.TextStyle(fontSize: 10)),
              ],

              pw.Spacer(),

              // ── FOOTER ───────────────────────────────────────────────────
              pw.Divider(color: PdfColors.grey300),
              pw.Text(
                'Presupuesto generado por $businessName · ${_dateFmt.format(DateTime.now())} · Los precios pueden estar sujetos a cambios.',
                style: const pw.TextStyle(fontSize: 8, color: textGrey),
                textAlign: pw.TextAlign.center,
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _th(String text, {pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(text,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: align),
      );

  static pw.Widget _td(String text, {pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 10), textAlign: align),
      );

  static pw.Widget _totalRow(String label, String value,
      {bool bold = false, PdfColor? valueColor, PdfColor? labelColor}) {
    const grey = PdfColor.fromInt(0xFF6B7280);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: labelColor ?? grey,
            )),
        pw.Text(value,
            style: pw.TextStyle(
              fontSize: bold ? 14 : 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valueColor,
            )),
      ],
    );
  }
}
