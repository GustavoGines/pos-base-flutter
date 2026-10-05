import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/quote_repository.dart';

/// Servicio que genera el PDF del presupuesto y abre WhatsApp.
/// No depende de Flutter widgets — puede llamarse desde cualquier contexto.
class QuotePdfService {
  static final _currencyFmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);
  static final _dateFmt = DateFormat('dd/MM/yyyy');

  /// Cache en memoria de imágenes de productos para evitar peticiones redundantes.
  static final Map<String, pw.MemoryImage?> _thumbnailCache = {};

  /// Limpia la caché de miniaturas (útil para tests).
  static void clearThumbnailCache() {
    _thumbnailCache.clear();
  }

  /// Precarga asíncronamente las imágenes de los ítems de presupuesto antes del renderizado sincrónico de MultiPage.
  static Future<Map<int, pw.MemoryImage>> preloadThumbnails(
    Quote quote, {
    http.Client? httpClient,
  }) async {
    final Map<int, pw.MemoryImage> imageMap = {};
    final client = httpClient ?? http.Client();

    try {
      for (var i = 0; i < quote.items.length; i++) {
        final item = quote.items[i];
        final rawUrl = item.imageUrl ?? item.product?.imageUrl;
        if (rawUrl == null || rawUrl.trim().isEmpty) continue;
        final url = rawUrl.trim();

        if (_thumbnailCache.containsKey(url)) {
          final cached = _thumbnailCache[url];
          if (cached != null) {
            imageMap[i] = cached;
          }
          continue;
        }

        try {
          final uri = Uri.tryParse(url);
          if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
            final response = await client.get(uri).timeout(const Duration(seconds: 4));
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              final memImg = pw.MemoryImage(response.bodyBytes);
              _thumbnailCache[url] = memImg;
              imageMap[i] = memImg;
            } else {
              _thumbnailCache[url] = null;
            }
          }
        } catch (e) {
          debugPrint('Error al precargar imagen de presupuesto ($url): $e');
          _thumbnailCache[url] = null;
        }
      }
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }

    return imageMap;
  }

  /// Genera el PDF, lo guarda en el directorio de descargas, lo muestra al
  /// usuario (preview) y luego abre WhatsApp con un mensaje prearmado.
  static Future<String?> generateAndShare({
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? vendorName,
  }) async {
    final pdfBytes = await _buildPdf(
      quote: quote,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      vendorName: vendorName,
    );

    // ── Guardar archivo ──────────────────────────────────────────────────
    final docsDir = await getApplicationDocumentsDirectory();
    final presupuestosDir = Directory('${docsDir.path}${Platform.pathSeparator}Sistema_POS${Platform.pathSeparator}Presupuestos');
    
    if (!await presupuestosDir.exists()) {
      await presupuestosDir.create(recursive: true);
    }
    
    final filename = '${quote.quoteNumber}.pdf';
    final file = File('${presupuestosDir.path}${Platform.pathSeparator}$filename');
    
    try {
      await file.writeAsBytes(pdfBytes);
    } catch (e) {
      throw Exception('Permiso denegado o error de disco al guardar: \$e');
    }

    return file.path;
  }

  static Future<void> preview({
    required BuildContext context,
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? vendorName,
  }) async {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      pageBuilder: (context, _, __) {
        return Material(
          color: Colors.black45,
          child: Center(
            child: Container(
              width: 850,
              height: MediaQuery.of(context).size.height * 0.9,
              margin: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Vista Previa del Presupuesto', 
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: PdfPreview(
                      allowPrinting: true,
                      allowSharing: true,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      pdfFileName: '${quote.quoteNumber}.pdf',
                      build: (format) async => _buildPdf(
                        quote: quote,
                        businessName: businessName,
                        businessAddress: businessAddress,
                        businessPhone: businessPhone,
                        vendorName: vendorName,
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

  /// Abre WhatsApp con mensaje prearmado.
  static Future<void> openWhatsApp({
    required Quote quote,
    required String businessName,
    String? phone,
    String? savedPdfPath,
  }) async {
    if (savedPdfPath != null && Platform.isWindows) {
      try {
        // Abre el explorador de Windows y resalta exactamente el archivo que se guardó
        await Process.run('explorer.exe', ['/select,', savedPdfPath]);
      } catch (e) {
        debugPrint('Error abriendo directorio nativo: $e');
      }
    } else if (savedPdfPath != null) {
      try {
        final parentDir = File(savedPdfPath).parent.path.replaceAll('\\', '/');
        final folderUri = Uri.parse('file:///$parentDir');
        if (await canLaunchUrl(folderUri)) {
          await launchUrl(folderUri);
        }
      } catch (e) {
        debugPrint('Error abriendo directorio fallback: $e');
      }
    }
    final total = _currencyFmt.format(quote.total);
    final msg = Uri.encodeComponent(
      '¡Hola! Te enviamos el presupuesto *${quote.quoteNumber}* de $businessName.\n\n'
      'Total: $total\n'
      'Adjuntamos el documento PDF con el detalle de los artículos y condiciones.'
      '${quote.notes != null && quote.notes!.isNotEmpty ? "\n\nNotas adicionales: ${quote.notes}" : ""}'
      '\n\n¡Quedamos a tu entera disposición por cualquier consulta!',
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

  static Future<Uint8List> generateQuotePdf({
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? vendorName,
    http.Client? httpClient,
  }) async {
    // 1. Precarga asíncrona de miniaturas antes del renderizado sincrónico de MultiPage
    final itemThumbnails = await preloadThumbnails(quote, httpClient: httpClient);

    final doc = pw.Document();

    // Paleta de colores
    const primary = PdfColor.fromInt(0xFF1A4B8C);    // azul corporativo
    const accent = PdfColor.fromInt(0xFF2E7D32);     // verde para totales
    const bgLight = PdfColor.fromInt(0xFFF5F7FA);
    const textGrey = PdfColor.fromInt(0xFF6B7280);

    final currFmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (pw.Context ctx) {
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  quote.validUntil != null
                    ? 'Validez del presupuesto: hasta el ${_dateFmt.format(DateTime.parse(quote.validUntil!))}. Los precios pueden variar sin previo aviso.'
                    : 'Validez del presupuesto: 7 días. Los precios pueden variar sin previo aviso.',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: primary,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.grey300),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Presupuesto generado por G-LABS Sistema POS · ${_dateFmt.format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 8, color: textGrey),
                  ),
                  pw.Text(
                    'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                    style: pw.TextStyle(fontSize: 8, color: textGrey, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context ctx) {
          return [
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
                            fontSize: 36, // Tamaño aumentado drásticamente
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.2,
                          )),
                      pw.Text(quote.quoteNumber,
                          style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 13)),
                      pw.SizedBox(height: 6),
                      pw.Container(
                        color: PdfColors.white,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        height: 35,
                        width: 130,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.code128(),
                          data: quote.quoteNumber,
                          drawText: false,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                          'Fecha: ${_dateFmt.format(DateTime.now())}',
                        style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10),
                      ),
                      if (quote.validUntil != null)
                        pw.Text(
                         'Válido hasta: ${_dateFmt.format(DateTime.parse(quote.validUntil!))}',
                          style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10),
                        ),
                      // ── Condición de venta (badge en el header) ──
                      pw.SizedBox(height: 4),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFF2E7D32), // verde
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          'Cond. de Venta: ${quote.priceListLabel}',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
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
            
            if (vendorName != null) ...[
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
                          pw.Text('VENDEDOR', style: pw.TextStyle(fontSize: 9, color: textGrey, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text(vendorName.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],

            // ── CONDICIÓN DE VENTA (bloque propio si hay lista activa) ────────
            if (quote.priceList != 'base') ...[
              pw.Container(
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE8F5E9),
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColor.fromInt(0xFF2E7D32), width: 0.5),
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: pw.Row(
                  children: [
                    pw.Text('Condición de Venta: ',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromInt(0xFF1B5E20))),
                    pw.Text(quote.priceListLabel,
                        style: pw.TextStyle(fontSize: 10,
                            color: PdfColor.fromInt(0xFF2E7D32), fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
            ],

            // ── TABLA DE ÍTEMS ───────────────────────────────────────────
            pw.Table(
              border: pw.TableBorder(
                bottom: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                horizontalInside: const pw.BorderSide(color: PdfColors.grey200, width: 0.5),
              ),
              columnWidths: {
                0: const pw.FixedColumnWidth(36), // FOTO / Miniatura
                1: const pw.FlexColumnWidth(5),   // DESCRIPCIÓN
                2: const pw.FlexColumnWidth(1.4), // CANT.
                3: const pw.FlexColumnWidth(1.8), // PRECIO UNIT.
                4: const pw.FlexColumnWidth(1.8), // SUBTOTAL
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: primary),
                  repeat: true, // Repite la cabecera de la tabla si salta de hoja
                  children: [
                    _th('', align: pw.TextAlign.center),
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
                  final memImg = itemThumbnails[i];
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : bgLight),
                    children: [
                      _thumbnailCell(memImg),
                      _td(item.productName),
                      _td(
                        item.quantity % 1 == 0
                            ? item.quantity.toInt().toString()
                            : item.quantity.toQty(),
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
          ];
        },
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> _buildPdf({
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? vendorName,
    http.Client? httpClient,
  }) async {
    return generateQuotePdf(
      quote: quote,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      vendorName: vendorName,
      httpClient: httpClient,
    );
  }

  static pw.Widget _thumbnailCell(pw.MemoryImage? memoryImage) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: pw.Center(
        child: memoryImage != null
            ? pw.Container(
                width: 32,
                height: 32,
                decoration: pw.BoxDecoration(
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 4,
                  verticalRadius: 4,
                  child: pw.Image(
                    memoryImage,
                    fit: pw.BoxFit.cover,
                  ),
                ),
              )
            : pw.Container(
                width: 32,
                height: 32,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Center(
                  child: pw.Text(
                    '-',
                    style: const pw.TextStyle(color: PdfColors.grey400, fontSize: 10),
                  ),
                ),
              ),
      ),
    );
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
