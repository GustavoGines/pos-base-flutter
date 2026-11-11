import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/image_url_resolver.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Servicio que genera el PDF del presupuesto (A4 y Letter) con diseño técnico
/// reglamentario estilo ARCA / Facturación Comercial Argentina (Letra X - No Fiscal)
/// y permite compartirlo por WhatsApp o imprimirlo.
class QuotePdfService {
  static final _currencyFmt =
      NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);
  static final _numberFmt = NumberFormat('#,##0.00', 'es_AR');
  static final _dateFmt = DateFormat('dd/MM/yyyy');
  static final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

  /// Cache en memoria de imágenes de productos y logos para evitar peticiones redundantes.
  static final Map<String, pw.MemoryImage?> _thumbnailCache = {};

  /// Limpia la caché de miniaturas (útil para tests).
  static void clearThumbnailCache() {
    _thumbnailCache.clear();
  }

  /// Formatea importes en pesos argentinos estilo contable ARCA ($ 1.234,56).
  static String formatCurrency(num amount) {
    if (amount < 0) {
      return '-\$ ${_numberFmt.format(amount.abs())}';
    }
    return '\$ ${_numberFmt.format(amount)}';
  }

  /// Formatea un CUIT/CUIL de 11 dígitos con guiones (XX-XXXXXXXX-X).
  static String _formatCuit(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 10)}-${digits.substring(10)}';
    }
    return raw.trim();
  }

  /// Convierte valores de condición frente al IVA a etiquetas legibles estilo ARCA.
  static String _formatTaxCondition(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final clean = raw.trim();
    switch (clean.toLowerCase()) {
      case 'consumidor_final':
      case 'consumidor final':
        return 'Consumidor Final';
      case 'responsable_inscripto':
      case 'iva responsable inscripto':
        return 'IVA Responsable Inscripto';
      case 'monotributo':
      case 'responsable monotributo':
        return 'Responsable Monotributo';
      case 'exento':
      case 'iva sujeto exento':
        return 'IVA Sujeto Exento';
      default:
        return clean.replaceAll('_', ' ');
    }
  }

  static Future<String?> _resolveEffectiveBaseUrl(String? baseUrl) async {
    if (baseUrl != null && baseUrl.trim().isNotEmpty) {
      return baseUrl.trim();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('pos_api');
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        return savedUrl.trim();
      }
    } catch (_) {}
    return AppConfig.kApiBaseUrl;
  }

  static File? _checkLocalFile(String pathOrUrl) {
    final trimmed = pathOrUrl.trim();
    if (trimmed.startsWith('file:')) {
      try {
        final uri = Uri.parse(trimmed);
        final file = File.fromUri(uri);
        if (file.existsSync()) return file;
      } catch (_) {
        try {
          final cleanPath = trimmed.replaceFirst(RegExp(r'^file:[/\\]+'), '');
          final file = File(cleanPath);
          if (file.existsSync()) return file;
        } catch (_) {}
      }
      return null;
    }

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      try {
        final file = File(trimmed);
        if (file.existsSync()) {
          return file;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Precarga asíncronamente el logotipo del negocio para el encabezado del PDF.
  static Future<pw.MemoryImage?> preloadLogo({
    String? logoUrl,
    Uint8List? logoBytes,
    http.Client? httpClient,
    String? baseUrl,
  }) async {
    if (logoBytes != null && logoBytes.isNotEmpty) {
      try {
        return pw.MemoryImage(logoBytes);
      } catch (e) {
        debugPrint('Error al crear MemoryImage desde logoBytes: $e');
        return null;
      }
    }
    if (logoUrl == null || logoUrl.trim().isEmpty) return null;
    final trimmed = logoUrl.trim();

    if (_thumbnailCache.containsKey(trimmed)) {
      return _thumbnailCache[trimmed];
    }

    // 1. Verificar si es archivo local antes de resolveImageUrl
    final localFile = _checkLocalFile(trimmed);
    if (localFile != null && localFile.existsSync()) {
      try {
        final bytes = await localFile.readAsBytes();
        if (bytes.isNotEmpty) {
          final memImg = pw.MemoryImage(bytes);
          _thumbnailCache[trimmed] = memImg;
          return memImg;
        }
      } catch (e) {
        debugPrint('Error al leer archivo local de logotipo ($trimmed): $e');
      }
      _thumbnailCache[trimmed] = null;
      return null;
    }

    // 2. Resolver con baseUrl dinámica
    final effectiveBase = await _resolveEffectiveBaseUrl(baseUrl);
    final resolvedUrl =
        resolveImageUrl(trimmed, baseUrl: effectiveBase) ?? trimmed;

    if (_thumbnailCache.containsKey(resolvedUrl)) {
      return _thumbnailCache[resolvedUrl];
    }

    final client = httpClient ?? http.Client();
    try {
      final uri = Uri.tryParse(resolvedUrl);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        final response =
            await client.get(uri).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final memImg = pw.MemoryImage(response.bodyBytes);
          _thumbnailCache[trimmed] = memImg;
          _thumbnailCache[resolvedUrl] = memImg;
          return memImg;
        }
      } else {
        final file = _checkLocalFile(resolvedUrl) ?? File(resolvedUrl);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            final memImg = pw.MemoryImage(bytes);
            _thumbnailCache[trimmed] = memImg;
            _thumbnailCache[resolvedUrl] = memImg;
            return memImg;
          }
        }
      }
    } catch (e) {
      debugPrint('Error al precargar logotipo ($resolvedUrl): $e');
    } finally {
      if (httpClient == null) client.close();
    }
    _thumbnailCache[trimmed] = null;
    _thumbnailCache[resolvedUrl] = null;
    return null;
  }

  /// Precarga asíncronamente las imágenes de los ítems de presupuesto antes del renderizado sincrónico de MultiPage.
  static Future<Map<int, pw.MemoryImage>> preloadThumbnails(
    Quote quote, {
    http.Client? httpClient,
    String? baseUrl,
  }) async {
    final Map<int, pw.MemoryImage> imageMap = {};
    final client = httpClient ?? http.Client();
    final effectiveBase = await _resolveEffectiveBaseUrl(baseUrl);

    try {
      for (var i = 0; i < quote.items.length; i++) {
        final item = quote.items[i];
        final rawUrl = item.imageUrl ?? item.product?.imageUrl;
        if (rawUrl == null || rawUrl.trim().isEmpty) continue;
        final trimmedRaw = rawUrl.trim();

        if (_thumbnailCache.containsKey(trimmedRaw)) {
          final cached = _thumbnailCache[trimmedRaw];
          if (cached != null) {
            imageMap[i] = cached;
          }
          continue;
        }

        // 1. Verificar si es archivo local antes de resolveImageUrl
        final localFile = _checkLocalFile(trimmedRaw);
        if (localFile != null && localFile.existsSync()) {
          try {
            final bytes = await localFile.readAsBytes();
            if (bytes.isNotEmpty) {
              final memImg = pw.MemoryImage(bytes);
              _thumbnailCache[trimmedRaw] = memImg;
              imageMap[i] = memImg;
              continue;
            } else {
              _thumbnailCache[trimmedRaw] = null;
              continue;
            }
          } catch (e) {
            debugPrint('Error al leer archivo local ($trimmedRaw): $e');
            _thumbnailCache[trimmedRaw] = null;
            continue;
          }
        }

        // 2. Resolver con dynamic baseUrl
        final url =
            resolveImageUrl(trimmedRaw, baseUrl: effectiveBase) ?? trimmedRaw;

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
            final response =
                await client.get(uri).timeout(const Duration(seconds: 4));
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              final memImg = pw.MemoryImage(response.bodyBytes);
              _thumbnailCache[trimmedRaw] = memImg;
              _thumbnailCache[url] = memImg;
              imageMap[i] = memImg;
            } else {
              _thumbnailCache[trimmedRaw] = null;
              _thumbnailCache[url] = null;
            }
          } else {
            final file = _checkLocalFile(url) ?? File(url);
            if (file.existsSync()) {
              final bytes = await file.readAsBytes();
              if (bytes.isNotEmpty) {
                final memImg = pw.MemoryImage(bytes);
                _thumbnailCache[trimmedRaw] = memImg;
                _thumbnailCache[url] = memImg;
                imageMap[i] = memImg;
              } else {
                _thumbnailCache[trimmedRaw] = null;
                _thumbnailCache[url] = null;
              }
            } else {
              _thumbnailCache[trimmedRaw] = null;
              _thumbnailCache[url] = null;
            }
          }
        } catch (e) {
          debugPrint('Error al precargar imagen de presupuesto ($url): $e');
          _thumbnailCache[trimmedRaw] = null;
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

  /// Genera el PDF y lo guarda en Documentos/Sistema_POS/Presupuestos.
  static Future<String?> generateAndShare({
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessCuit,
    String? businessTaxCondition,
    String? businessIibb,
    String? businessActivityStartDate,
    dynamic businessSettings,
    String? vendorName,
    String? logoUrl,
    Uint8List? logoBytes,
    String? baseUrl,
    String paperSize = 'a4',
  }) async {
    final pdfBytes = await _buildPdf(
      quote: quote,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessCuit: businessCuit,
      businessTaxCondition: businessTaxCondition,
      businessIibb: businessIibb,
      businessActivityStartDate: businessActivityStartDate,
      businessSettings: businessSettings,
      vendorName: vendorName,
      logoUrl: logoUrl,
      logoBytes: logoBytes,
      baseUrl: baseUrl,
      paperSize: paperSize,
    );

    // ── Guardar archivo ──────────────────────────────────────────────────
    final docsDir = await getApplicationDocumentsDirectory();
    final presupuestosDir = Directory(
      '${docsDir.path}${Platform.pathSeparator}Sistema_POS${Platform.pathSeparator}Presupuestos',
    );

    if (!await presupuestosDir.exists()) {
      await presupuestosDir.create(recursive: true);
    }

    final filename = '${quote.quoteNumber}.pdf';
    final file =
        File('${presupuestosDir.path}${Platform.pathSeparator}$filename');

    try {
      await file.writeAsBytes(pdfBytes);
    } catch (e) {
      throw Exception('Permiso denegado o error de disco al guardar: $e');
    }

    return file.path;
  }

  /// Muestra el visor interactivo del presupuesto PDF en formato A4 o Carta (Letter).
  static Future<void> preview({
    required BuildContext context,
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessCuit,
    String? businessTaxCondition,
    String? businessIibb,
    String? businessActivityStartDate,
    dynamic businessSettings,
    String? vendorName,
    String? logoUrl,
    Uint8List? logoBytes,
    String? baseUrl,
    String paperSize = 'a4',
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
                          Icons.request_quote_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Presupuesto N° ${quote.quoteNumber} — Vista Previa $paperLabel',
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
                      pdfFileName: '${quote.quoteNumber}.pdf',
                      build: (_) async => _buildPdf(
                        quote: quote,
                        businessName: businessName,
                        businessAddress: businessAddress,
                        businessPhone: businessPhone,
                        businessCuit: businessCuit,
                        businessTaxCondition: businessTaxCondition,
                        businessIibb: businessIibb,
                        businessActivityStartDate: businessActivityStartDate,
                        businessSettings: businessSettings,
                        vendorName: vendorName,
                        logoUrl: logoUrl,
                        logoBytes: logoBytes,
                        baseUrl: baseUrl,
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

  /// Abre WhatsApp con mensaje prearmado y resalta el PDF en el explorador.
  static Future<void> openWhatsApp({
    required Quote quote,
    required String businessName,
    String? phone,
    String? savedPdfPath,
  }) async {
    if (savedPdfPath != null && Platform.isWindows) {
      try {
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
    final sanitizedNotes = _sanitizeNotes(quote.notes);
    final msg = Uri.encodeComponent(
      '¡Hola! Te enviamos el presupuesto *${quote.quoteNumber}* de $businessName.\n\n'
      'Total: $total\n'
      'Adjuntamos el documento PDF con el detalle de los artículos y condiciones.'
      '${sanitizedNotes != null && sanitizedNotes.isNotEmpty ? "\n\nNotas adicionales: $sanitizedNotes" : ""}'
      '\n\n¡Quedamos a tu entera disposición por cualquier consulta!',
    );

    final rawPhone = (phone ?? '').replaceAll(RegExp(r'[^\d]'), '');
    final waUrl = rawPhone.isNotEmpty
        ? 'https://wa.me/$rawPhone?text=$msg'
        : 'https://wa.me/?text=$msg';

    final uri = Uri.parse(waUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── PDF Builder Reglamentario Estilo ARCA / Comercial (Letra X) ──────────

  /// Sanea las notas del presupuesto eliminando leyendas obsoletas de "precio congelado".
  static String? _sanitizeNotes(String? raw) {
    return raw
        ?.replaceAll(
          RegExp(
            r'\s*-\s*V[aá]lido\s+\d+\s+d[ií]as\s+con\s+precio\s+congelado\.?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\s*con\s+precio\s+congelado\.?', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s*precio\s+congelado\.?', caseSensitive: false),
          '',
        )
        .trim();
  }

  static Future<Uint8List> generateQuotePdf({
    required Quote quote,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessCuit,
    String? businessTaxCondition,
    String? businessIibb,
    String? businessActivityStartDate,
    dynamic businessSettings,
    String? vendorName,
    String? logoUrl,
    Uint8List? logoBytes,
    http.Client? httpClient,
    String? baseUrl,
    String paperSize = 'a4',
  }) async {
    // Extraer datos adicionales desde businessSettings si fue provisto
    String? effectiveAddress = businessAddress;
    String? effectivePhone = businessPhone;
    String? effectiveCuit = businessCuit;
    String? effectiveTaxCondition = businessTaxCondition;
    String? effectiveIibb = businessIibb;
    String? effectiveActivityStart = businessActivityStartDate;
    String? effectiveLogoUrl = logoUrl;

    if (businessSettings is BusinessSettings) {
      effectiveAddress ??= businessSettings.address;
      effectivePhone ??= businessSettings.phone;
      effectiveCuit ??= businessSettings.taxId;
      effectiveTaxCondition ??= businessSettings.taxCondition;
      effectiveIibb ??= businessSettings.iibb;
      effectiveActivityStart ??= businessSettings.activityStartDate;
      effectiveLogoUrl ??= businessSettings.effectiveLogoUrl;
    } else if (businessSettings is Map) {
      effectiveAddress ??= businessSettings['address']?.toString();
      effectivePhone ??= businessSettings['phone']?.toString();
      effectiveCuit ??= businessSettings['tax_id']?.toString() ??
          businessSettings['cuit']?.toString();
      effectiveTaxCondition ??= businessSettings['tax_condition']?.toString();
      effectiveIibb ??= businessSettings['iibb']?.toString();
      effectiveActivityStart ??=
          businessSettings['activity_start_date']?.toString();
      effectiveLogoUrl ??= businessSettings['logo_url']?.toString() ??
          businessSettings['effective_logo_url']?.toString();
    }

    // 1. Precarga asíncrona de miniaturas y logotipo antes del renderizado sincrónico de MultiPage
    final results = await Future.wait([
      preloadThumbnails(quote, httpClient: httpClient, baseUrl: baseUrl),
      preloadLogo(
        logoUrl: effectiveLogoUrl,
        logoBytes: logoBytes,
        httpClient: httpClient,
        baseUrl: baseUrl,
      ),
    ]);
    final itemThumbnails = results[0] as Map<int, pw.MemoryImage>;
    final logoImage = results[1] as pw.MemoryImage?;

    final doc = pw.Document();
    final pageFormat = paperSize.toLowerCase() == 'letter'
        ? PdfPageFormat.letter
        : PdfPageFormat.a4;

    final DateTime emissionDate = quote.createdAt != null
        ? (DateTime.tryParse(quote.createdAt!)?.toLocal() ?? DateTime.now())
        : DateTime.now();
    final String emissionDateStr = _dateTimeFmt.format(emissionDate);

    final String validUntilStr = (quote.validUntil != null &&
            quote.validUntil!.trim().isNotEmpty)
        ? (() {
            final parsed = DateTime.tryParse(quote.validUntil!.trim());
            return parsed != null
                ? _dateFmt.format(parsed)
                : quote.validUntil!.trim();
          })()
        : '${_dateFmt.format(emissionDate.add(const Duration(days: 7)))} (7 días)';

    final formattedEmitterCuit = _formatCuit(effectiveCuit);
    final formattedEmitterIibb = _formatCuit(effectiveIibb);
    final formattedEmitterTaxCond = _formatTaxCondition(effectiveTaxCondition);

    final receiverName =
        (quote.customerName != null && quote.customerName!.trim().isNotEmpty)
            ? quote.customerName!.trim()
            : 'Consumidor Final';
    final receiverPhone =
        (quote.customerPhone != null && quote.customerPhone!.trim().isNotEmpty)
            ? quote.customerPhone!.trim()
            : '---';

    final cleanBarcodeData = quote.quoteNumber.trim().isNotEmpty
        ? quote.quoteNumber.trim()
        : 'PRES-${quote.id.toString().padLeft(4, '0')}';

    final String? sanitizedNotes = _sanitizeNotes(quote.notes);

    final int totalUnits = quote.items.fold<int>(0, (sum, item) {
      final isWeight =
          item.product?.isSoldByWeight ?? (item.quantity % 1 != 0);
      return sum + (isWeight ? 1 : item.quantity.toInt());
    });

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(24),
          buildForeground: (pw.Context context) {
            if (logoImage == null) return pw.SizedBox();
            return pw.FullPage(
              ignoreMargins: false,
              child: pw.Center(
                child: pw.Opacity(
                  opacity: 0.10,
                  child: pw.Image(
                    logoImage,
                    width: 280,
                    height: 280,
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
            );
          },
        ),
        footer: (pw.Context ctx) {
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.SizedBox(height: 6),
              pw.Divider(color: PdfColors.grey500, thickness: 0.6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'PRESUPUESTO COMERCIAL - DOCUMENTO NO VÁLIDO COMO FACTURA - $businessName',
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
        },
        build: (pw.Context ctx) {
          return [
            // ── 1. BARRA SUPERIOR REGLAMENTARIA (ORIGINAL / NO FISCAL) ──────
            pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                border: pw.Border.all(color: PdfColors.black, width: 1.0),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'ORIGINAL',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  pw.Text(
                    'DOCUMENTO NO VÁLIDO COMO FACTURA',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
            ),

            // ── 2. ENCABEZADO PARTIDO ESTILO ARCA CON RECUADRO CENTRAL X ────
            pw.Stack(
              alignment: pw.Alignment.topCenter,
              children: [
                pw.Table(
                  border: const pw.TableBorder(
                    left: pw.BorderSide(color: PdfColors.black, width: 1.0),
                    right: pw.BorderSide(color: PdfColors.black, width: 1.0),
                    bottom: pw.BorderSide(color: PdfColors.black, width: 1.0),
                    verticalInside:
                        pw.BorderSide(color: PdfColors.black, width: 1.0),
                  ),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        // COLUMNA IZQUIERDA: DATOS DE LA EMPRESA / EMISOR
                        pw.Padding(
                          padding: const pw.EdgeInsets.fromLTRB(8, 8, 26, 8),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              if (logoImage != null) ...[
                                pw.Container(
                                  width: 52,
                                  height: 52,
                                  child: pw.Image(
                                    logoImage,
                                    fit: pw.BoxFit.contain,
                                  ),
                                ),
                                pw.SizedBox(width: 8),
                              ],
                              pw.Expanded(
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      businessName.toUpperCase(),
                                      style: pw.TextStyle(
                                        fontSize: 15,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.black,
                                      ),
                                    ),
                                    pw.SizedBox(height: 3),
                                    if (effectiveAddress != null &&
                                        effectiveAddress.trim().isNotEmpty)
                                      pw.Text(
                                        'Domicilio Comercial: ${effectiveAddress.trim()}',
                                        style:
                                            const pw.TextStyle(fontSize: 7.5),
                                      ),
                                    if (effectivePhone != null &&
                                        effectivePhone.trim().isNotEmpty)
                                      pw.Text(
                                        'Teléfono: ${effectivePhone.trim()}',
                                        style:
                                            const pw.TextStyle(fontSize: 7.5),
                                      ),
                                    if (formattedEmitterCuit.isNotEmpty)
                                      pw.Text(
                                        'CUIT: $formattedEmitterCuit',
                                        style: pw.TextStyle(
                                          fontSize: 7.5,
                                          fontWeight: pw.FontWeight.bold,
                                        ),
                                      ),
                                    if (formattedEmitterIibb.isNotEmpty)
                                      pw.Text(
                                        'Ingresos Brutos: $formattedEmitterIibb',
                                        style:
                                            const pw.TextStyle(fontSize: 7.5),
                                      ),
                                    if (effectiveActivityStart != null &&
                                        effectiveActivityStart.trim().isNotEmpty)
                                      pw.Text(
                                        'Inicio de Actividades: ${effectiveActivityStart.trim()}',
                                        style:
                                            const pw.TextStyle(fontSize: 7.5),
                                      ),
                                    if (formattedEmitterTaxCond.isNotEmpty)
                                      pw.Text(
                                        'Cond. frente al IVA: $formattedEmitterTaxCond',
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

                        // COLUMNA DERECHA: DATOS DEL PRESUPUESTO + CÓDIGO DE BARRAS
                        pw.Padding(
                          padding: const pw.EdgeInsets.fromLTRB(26, 8, 8, 8),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'PRESUPUESTO',
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'Comp. Nro: ${quote.quoteNumber}',
                                style: pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                'Fecha de Emisión: $emissionDateStr',
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                              pw.Text(
                                'Válido hasta: $validUntilStr',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              if (vendorName != null &&
                                  vendorName.trim().isNotEmpty)
                                pw.Text(
                                  'Cajero / Vendedor: ${vendorName.trim().toUpperCase()}',
                                  style: const pw.TextStyle(fontSize: 7.5),
                                ),
                              pw.SizedBox(height: 6),
                              pw.BarcodeWidget(
                                barcode: pw.Barcode.code128(),
                                data: cleanBarcodeData,
                                width: 140,
                                height: 22,
                                drawText: false,
                                color: PdfColors.black,
                              ),
                              pw.SizedBox(height: 1.5),
                              pw.Text(
                                cleanBarcodeData,
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
                  ],
                ),

                // RECUADRO CENTRAL DE LETRA (X - NO FISCAL)
                pw.Positioned(
                  top: 0,
                  child: pw.Container(
                    width: 42,
                    height: 42,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(color: PdfColors.black, width: 1.5),
                    ),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          'X',
                          style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.Text(
                          'NO FISCAL',
                          style: pw.TextStyle(
                            fontSize: 5.5,
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

            pw.SizedBox(height: 6),

            // ── 3. CASILLERO DE RECEPTOR / CLIENTE ──────────────────────────
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 1.0),
              ),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Apellido y Nombre / Razón Social: ${receiverName.toUpperCase()}',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Teléfono / Contacto: $receiverPhone',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Condición de Venta: ${quote.priceListLabel.toUpperCase()}',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Cond. IVA / Doc: Consumidor Final',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 6),

            // ── 4. TABLA TÉCNICA DE ARTÍCULOS ───────────────────────────────
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.3), // CÓDIGO
                1: pw.FlexColumnWidth(1.2), // CANT.
                2: pw.FlexColumnWidth(5.1), // DESCRIPCIÓN
                3: pw.FlexColumnWidth(2.0), // PRECIO UNIT.
                4: pw.FlexColumnWidth(2.0), // SUBTOTAL
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  repeat: true,
                  children: [
                    _th('CÓDIGO', align: pw.TextAlign.center),
                    _th('CANT.', align: pw.TextAlign.center),
                    _th('DESCRIPCIÓN', align: pw.TextAlign.left),
                    _th('PRECIO UNIT.', align: pw.TextAlign.right),
                    _th('SUBTOTAL', align: pw.TextAlign.right),
                  ],
                ),
                ...quote.items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  final memImg = itemThumbnails[i];

                  final isWeight = item.product?.isSoldByWeight ??
                      (item.quantity % 1 != 0);
                  final qtyText = isWeight
                      ? '${item.quantity.toQty()} kg'
                      : (item.quantity % 1 == 0
                          ? item.quantity.toInt().toString()
                          : item.quantity.toQty());

                  final rawCode = item.product?.internalCode.trim() ?? '';
                  final codeText = rawCode.isNotEmpty
                      ? rawCode
                      : (item.productId != null ? '#${item.productId}' : '-');

                  return pw.TableRow(
                    children: [
                      _td(codeText, align: pw.TextAlign.center),
                      _td(qtyText, align: pw.TextAlign.center),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 4.5,
                        ),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            if (memImg != null) ...[
                              pw.Container(
                                width: 22,
                                height: 22,
                                margin: const pw.EdgeInsets.only(right: 6),
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(
                                    color: PdfColors.grey400,
                                    width: 0.5,
                                  ),
                                ),
                                child: pw.Image(
                                  memImg,
                                  fit: pw.BoxFit.cover,
                                ),
                              ),
                            ],
                            pw.Expanded(
                              child: pw.Text(
                                item.productName.toUpperCase(),
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _td(
                        formatCurrency(item.unitPrice),
                        align: pw.TextAlign.right,
                      ),
                      _td(
                        formatCurrency(item.subtotal),
                        align: pw.TextAlign.right,
                        bold: true,
                      ),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 8),

            // ── 5. BLOQUE INFERIOR DE OBSERVACIONES Y TOTALES REGLAMENTARIO ─
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 1.0),
              ),
              padding: const pw.EdgeInsets.all(8),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // OBSERVACIONES Y CONDICIONES (IZQUIERDA)
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'OBSERVACIONES Y CONDICIONES COMERCIALES',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        if (sanitizedNotes != null &&
                            sanitizedNotes.isNotEmpty) ...[
                          pw.Text(
                            sanitizedNotes,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.SizedBox(height: 4),
                        ],
                        pw.Text(
                          '- Documento de cotizacion no vinculante emitido a titulo informativo.',
                          style: const pw.TextStyle(
                            fontSize: 7.2,
                            color: PdfColors.grey800,
                          ),
                        ),
                        pw.Text(
                          '- Los precios y la disponibilidad de stock quedan sujetos a confirmacion y/o modificacion al momento de concretar la operacion.',
                          style: const pw.TextStyle(
                            fontSize: 7.2,
                            color: PdfColors.grey800,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Total de articulos cotizados: $totalUnits unidades',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(width: 14),

                  // TOTALES (DERECHA)
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if ((quote.subtotal - quote.total).abs() > 0.01) ...[
                          _summaryRow(
                            'Subtotal Artículos:',
                            formatCurrency(quote.subtotal),
                          ),
                          _summaryRow(
                            'Descuento / Bonificación:',
                            '- ${formatCurrency(quote.subtotal - quote.total)}',
                          ),
                        ],
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 2),
                          padding: const pw.EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 8,
                          ),
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.grey200,
                            border: pw.Border(
                              top: pw.BorderSide(
                                color: PdfColors.black,
                                width: 1.0,
                              ),
                            ),
                          ),
                          child: pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'TOTAL PRESUPUESTO:',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(width: 8),
                              pw.Text(
                                formatCurrency(quote.total),
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
    String? businessCuit,
    String? businessTaxCondition,
    String? businessIibb,
    String? businessActivityStartDate,
    dynamic businessSettings,
    String? vendorName,
    String? logoUrl,
    Uint8List? logoBytes,
    http.Client? httpClient,
    String? baseUrl,
    String paperSize = 'a4',
  }) async {
    return generateQuotePdf(
      quote: quote,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessCuit: businessCuit,
      businessTaxCondition: businessTaxCondition,
      businessIibb: businessIibb,
      businessActivityStartDate: businessActivityStartDate,
      businessSettings: businessSettings,
      vendorName: vendorName,
      logoUrl: logoUrl,
      logoBytes: logoBytes,
      httpClient: httpClient,
      baseUrl: baseUrl,
      paperSize: paperSize,
    );
  }

  static pw.Widget _th(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            color: PdfColors.black,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: align,
        ),
      );

  static pw.Widget _td(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: PdfColors.black,
          ),
          textAlign: align,
        ),
      );

  static pw.Widget _summaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 8.5,
              color: PdfColors.grey900,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }
}
