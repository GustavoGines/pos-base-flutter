import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'currency_formatter.dart';

/// Extension wrapper of [pw.Document] that retains the rendered widgets and page
/// for AST programmatic inspection and test validation.
class AfipFiscalDocument extends pw.Document {
  final List<pw.Widget> widgets;
  final pw.MultiPage page;

  AfipFiscalDocument({
    required this.widgets,
    required this.page,
    List<pw.Page>? customPages,
    super.theme,
    super.compress,
  }) {
    if (customPages != null && customPages.isNotEmpty) {
      for (final p in customPages) {
        addPage(p);
      }
    } else {
      addPage(page);
    }
  }
}

/// Service that builds and generates official AFIP fiscal invoice PDFs
/// conforming to RG 1415, RG 4892, RG 5614 (Ley 27.743) and RG 5616 classical layout standards (Facturas A, B, C).
class AfipFiscalPdfService {
  static final _numberFmt = NumberFormat('#,##0.00', 'es_AR');
  static final _dateFmt = DateFormat('dd/MM/yyyy');

  /// Formats currency values in standard Argentinian pesos with leading symbol (e.g. $ 2.155.120,00).
  static String formatCurrency(num amount) {
    if (amount < 0) {
      return '-\$ ${_numberFmt.format(amount.abs())}';
    }
    return '\$ ${_numberFmt.format(amount)}';
  }

  /// Parses date in various formats and formats as standard Argentinian DD/MM/AAAA.
  static String formatDate(dynamic date) {
    if (date == null) return _dateFmt.format(DateTime.now());
    if (date is DateTime) return _dateFmt.format(date);
    final str = date.toString().trim();
    if (str.isEmpty) return _dateFmt.format(DateTime.now());
    if (RegExp(r'^\d{2}/\d{2}/\d{4}').hasMatch(str)) {
      return str.substring(0, 10);
    }
    try {
      final parsed = DateTime.parse(str);
      return _dateFmt.format(parsed);
    } catch (_) {
      return str;
    }
  }

  /// Resuelve los bytes del logo del comercio desde [logoBytes], [businessSettings],
  /// disco local de Laragon o URL HTTP.
  static Future<Uint8List?> resolveLogoBytes({
    Uint8List? logoBytes,
    dynamic businessSettings,
    String? logoPath,
    String? logoUrl,
  }) async {
    if (logoBytes != null) return logoBytes;
    String? path = logoPath;
    String? url = logoUrl;
    if (businessSettings is BusinessSettings) {
      path ??= businessSettings.logoPath;
      url ??= businessSettings.effectiveLogoUrl;
    } else if (businessSettings is Map) {
      path ??= businessSettings['logo_path']?.toString();
      url ??= businessSettings['logo_url']?.toString() ??
          businessSettings['effective_logo_url']?.toString();
    }

    if (path != null && path.isNotEmpty) {
      try {
        final pathsToTry = [
          'C:/laragon/www/Sistema_POS/pos-backend/public/storage/$path',
          '../pos-backend/public/storage/$path',
        ];
        for (final p in pathsToTry) {
          final localFile = File(p);
          if (localFile.existsSync()) {
            return localFile.readAsBytesSync();
          }
        }
      } catch (_) {}
    }

    if (url != null && url.isNotEmpty) {
      try {
        if (url.startsWith('http')) {
          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 3));
          if (response.statusCode == 200) {
            return response.bodyBytes;
          }
        } else {
          final file = File(url);
          if (file.existsSync()) {
            return await file.readAsBytes();
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Generates the raw PDF bytes for an AFIP fiscal invoice.
  /// If [deliveryNote] is provided, renders a split page (Top: Factura Fiscal ARCA,
  /// Bottom: Remito / Orden de Retiro) when items <= 4, or 2 MultiPages when > 4 items.
  static Future<Uint8List> generateFiscalInvoice({
    required Map<String, dynamic> sale,
    Map<String, dynamic>? electronicInvoice,
    Map<String, dynamic>? deliveryNote,
    dynamic businessSettings,
    Uint8List? logoBytes,
    String paperSize = 'a4',
    bool compress = true,
    pw.ThemeData? theme,
  }) async {
    logoBytes = await resolveLogoBytes(
      logoBytes: logoBytes,
      businessSettings: businessSettings,
    );
    pw.ThemeData? effectiveTheme = theme;
    if (effectiveTheme == null) {
      try {
        final font = await PdfGoogleFonts.robotoRegular();
        final fontBold = await PdfGoogleFonts.robotoBold();
        effectiveTheme = pw.ThemeData.withFont(base: font, bold: fontBold);
      } catch (_) {
        // Fallback to default Helvetica in offline or testing environments
      }
    }

    final doc = buildFiscalDocument(
      sale: sale,
      electronicInvoice: electronicInvoice,
      deliveryNote: deliveryNote,
      businessSettings: businessSettings,
      logoBytes: logoBytes,
      paperSize: paperSize,
      compress: compress,
      theme: effectiveTheme,
    );

    return await doc.save();
  }

  /// Builds the [pw.Document] (an [AfipFiscalDocument]) representing the AFIP fiscal invoice.
  static pw.Document buildFiscalDocument({
    required Map<String, dynamic> sale,
    Map<String, dynamic>? electronicInvoice,
    Map<String, dynamic>? deliveryNote,
    dynamic businessSettings,
    Uint8List? logoBytes,
    String paperSize = 'a4',
    bool compress = true,
    pw.ThemeData? theme,
  }) {
    final invoice = electronicInvoice ??
        (sale['electronic_invoice'] as Map<String, dynamic>?) ??
        {};

    final items = sale['items'] as List<dynamic>? ?? [];
    final hasDeliveryNote = deliveryNote != null;
    final isSmallSplitOrder = hasDeliveryNote && items.length <= 4;

    final fiscalWidgets = buildFiscalWidgets(
      sale: sale,
      electronicInvoice: invoice,
      businessSettings: businessSettings,
      logoBytes: logoBytes,
      paperSize: paperSize,
      isCompact: isSmallSplitOrder,
    );

    final page = buildFiscalPage(
      widgets: fiscalWidgets,
      logoBytes: logoBytes,
      paperSize: paperSize,
    );

    if (!hasDeliveryNote) {
      return AfipFiscalDocument(
        widgets: fiscalWidgets,
        page: page,
        theme: theme,
        compress: compress,
      );
    }

    final deliveryWidgets = buildDeliveryNoteWidgets(
      sale: sale,
      electronicInvoice: invoice,
      deliveryNote: deliveryNote,
      businessSettings: businessSettings,
      logoBytes: logoBytes,
      isCompact: isSmallSplitOrder,
    );

    final pageFormat = paperSize.toLowerCase() == 'letter'
        ? PdfPageFormat.letter
        : PdfPageFormat.a4;

    final List<pw.Page> customPages = [];
    if (isSmallSplitOrder) {
      customPages.add(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // MITAD SUPERIOR: FACTURA FISCAL ARCA
              pw.Expanded(
                flex: 57,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: fiscalWidgets,
                ),
              ),
              // LÍNEA DE CORTE CENTRAL
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
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
              // MITAD INFERIOR: REMITO / ORDEN DE RETIRO
              pw.Expanded(
                flex: 43,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: deliveryWidgets,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      customPages.add(page);
      customPages.add(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          ),
          build: (pw.Context context) => deliveryWidgets,
        ),
      );
    }

    return AfipFiscalDocument(
      widgets: [...fiscalWidgets, ...deliveryWidgets],
      page: page,
      customPages: customPages,
      theme: theme,
      compress: compress,
    );
  }

  /// Builds the [pw.MultiPage] containing the fiscal invoice widgets.
  static pw.MultiPage buildFiscalPage({
    required List<pw.Widget> widgets,
    Uint8List? logoBytes,
    String paperSize = 'a4',
  }) {
    final pageFormat = paperSize.toLowerCase() == 'letter'
        ? PdfPageFormat.letter
        : PdfPageFormat.a4;

    return pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      ),
      build: (pw.Context context) => widgets,
    );
  }

  /// Builds the complete list of [pw.Widget]s corresponding to AFIP RG 1415 & 4892 layout.
  static List<pw.Widget> buildFiscalWidgets({
    required Map<String, dynamic> sale,
    required Map<String, dynamic> electronicInvoice,
    dynamic businessSettings,
    Uint8List? logoBytes,
    String paperSize = 'a4',
    bool isCompact = false,
  }) {
    // ── 1. Resolución de Letra y Código de Comprobante AFIP ───────────────────
    final rawLetter = (electronicInvoice['voucher_letter'] ?? 'B')
        .toString()
        .trim()
        .toUpperCase();
    final voucherLetter = (rawLetter == 'A' || rawLetter == 'C') ? rawLetter : 'B';

    int defaultCode;
    switch (voucherLetter) {
      case 'A':
        defaultCode = 1;
        break;
      case 'C':
        defaultCode = 11;
        break;
      case 'B':
      default:
        defaultCode = 6;
        break;
    }

    final rawVoucherType = electronicInvoice['voucher_type'] ?? defaultCode;
    final voucherType = int.tryParse(rawVoucherType.toString()) ?? defaultCode;
    final voucherCodeText = 'COD. ${voucherType.toString().padLeft(2, '0')}';

    String voucherTitle = 'FACTURA';
    if (<int>[3, 8, 13].contains(voucherType)) {
      voucherTitle = 'NOTA DE CRÉDITO';
    } else if (<int>[2, 7, 12].contains(voucherType)) {
      voucherTitle = 'NOTA DE DÉBITO';
    }
    voucherTitle = '$voucherTitle $voucherLetter';

    // ── 2. Datos del Emisor ───────────────────────────────────────────────────
    String issuerName = 'Mi Negocio';
    String issuerCuit = '30-00000000-0';
    String issuerAddress = 'Domicilio Comercial';
    String issuerPhone = '';
    String issuerTaxCondition = voucherLetter == 'C'
        ? 'Responsable Monotributo'
        : 'IVA Responsable Inscripto';
    String issuerIibb = '';
    String issuerStartDate = '01/01/2020';

    if (businessSettings is BusinessSettings) {
      if (businessSettings.companyName != null &&
          businessSettings.companyName!.isNotEmpty) {
        issuerName = businessSettings.companyName!;
      }
      if (businessSettings.taxId != null && businessSettings.taxId!.isNotEmpty) {
        issuerCuit = businessSettings.taxId!;
      }
      if (businessSettings.address != null &&
          businessSettings.address!.isNotEmpty) {
        issuerAddress = businessSettings.address!;
      }
      if (businessSettings.phone != null &&
          businessSettings.phone!.isNotEmpty) {
        issuerPhone = businessSettings.phone!;
      }
      if (businessSettings.taxCondition != null &&
          businessSettings.taxCondition!.isNotEmpty) {
        issuerTaxCondition = businessSettings.taxCondition!;
      }
      if (businessSettings.iibb != null && businessSettings.iibb!.isNotEmpty) {
        issuerIibb = businessSettings.iibb!;
      }
      if (businessSettings.activityStartDate != null &&
          businessSettings.activityStartDate!.isNotEmpty) {
        issuerStartDate = businessSettings.activityStartDate!;
      }
    } else if (businessSettings is Map) {
      issuerName = (businessSettings['company_name'] ??
              businessSettings['companyName'] ??
              businessSettings['business_name'] ??
              issuerName)
          .toString();
      issuerCuit = (businessSettings['cuit'] ??
              businessSettings['tax_id'] ??
              businessSettings['taxId'] ??
              businessSettings['afip_cuit'] ??
              issuerCuit)
          .toString();
      issuerAddress = (businessSettings['address'] ??
              businessSettings['business_address'] ??
              issuerAddress)
          .toString();
      issuerPhone = (businessSettings['phone'] ??
              businessSettings['phone_number'] ??
              issuerPhone)
          .toString();
      issuerTaxCondition = (businessSettings['tax_condition'] ??
              businessSettings['afip_tax_condition'] ??
              issuerTaxCondition)
          .toString();
      issuerIibb = (businessSettings['iibb'] ??
              businessSettings['afip_iibb'] ??
              businessSettings['gross_income'] ??
              'Exento')
          .toString();
      issuerStartDate = (businessSettings['activity_start_date'] ??
              businessSettings['afip_activity_start_date'] ??
              issuerStartDate)
          .toString();
    }

    // Normalizar condición frente al IVA del emisor respetando la configuración del negocio
    issuerTaxCondition = _formatTaxCondition(issuerTaxCondition);

    if (issuerIibb.isEmpty) {
      issuerIibb = 'Exento';
    }
    issuerCuit = _formatCuit(issuerCuit);
    issuerIibb = _formatCuit(issuerIibb);

    // ── 3. Datos del Comprobante ──────────────────────────────────────────────
    final pointOfSale = int.tryParse(
            (electronicInvoice['point_of_sale'] ?? sale['point_of_sale'] ?? 1)
                .toString()) ??
        1;
    final voucherNumber = int.tryParse((electronicInvoice['voucher_number'] ??
                sale['voucher_number'] ??
                sale['id'] ??
                1)
            .toString()) ??
        1;
    final formattedNumber = electronicInvoice['formatted_number']?.toString() ??
        '${pointOfSale.toString().padLeft(5, '0')}-${voucherNumber.toString().padLeft(8, '0')}';
    final ptoVtaFormatted = pointOfSale.toString().padLeft(5, '0');
    final cbteNroFormatted = voucherNumber.toString().padLeft(8, '0');

    final issueDate = formatDate(electronicInvoice['issued_at'] ??
        electronicInvoice['date'] ??
        sale['created_at'] ??
        DateTime.now());

    String issueTime;
    try {
      final rawCreatedAt = sale['created_at'] ?? electronicInvoice['issued_at'];
      if (rawCreatedAt != null) {
        if (rawCreatedAt is DateTime) {
          issueTime = DateFormat('HH:mm').format(rawCreatedAt.toLocal());
        } else {
          final str = rawCreatedAt.toString().trim();
          if (str.isNotEmpty) {
            issueTime = DateFormat('HH:mm').format(DateTime.parse(str).toLocal());
          } else {
            issueTime = DateFormat('HH:mm').format(DateTime.now());
          }
        }
      } else {
        issueTime = DateFormat('HH:mm').format(DateTime.now());
      }
    } catch (_) {
      issueTime = DateFormat('HH:mm').format(DateTime.now());
    }

    final cashierName = sale['cashier']?['name']?.toString() ??
        sale['cashier_name']?.toString() ??
        sale['cashierName']?.toString() ??
        sale['userName']?.toString() ??
        sale['user_name']?.toString() ??
        sale['user']?['name']?.toString() ??
        'Cajero';

    // ── 4. Datos del Receptor ─────────────────────────────────────────────────
    final rawReceiverDoc = (electronicInvoice['doc_number']?.toString() ??
            sale['customer']?['tax_id'] ??
            sale['customer_tax_id'] ??
            '---')
        .toString();
    final receiverDoc = _formatCuit(rawReceiverDoc);
    final rawReceiverTaxCondition =
        electronicInvoice['receiver_tax_condition']?.toString() ??
            (voucherLetter == 'A'
                ? 'responsable_inscripto'
                : 'consumidor_final');
    final receiverTaxCondition = _formatTaxCondition(rawReceiverTaxCondition);
    final receiverName = electronicInvoice['receiver_name']?.toString() ??
        sale['customer']?['name'] ??
        sale['customer_name'] ??
        'Consumidor Final';
    final receiverAddress =
        electronicInvoice['receiver_address']?.toString() ??
            sale['customer']?['address'] ??
            sale['delivery_address'] ??
            '---';
    String paymentCondition = 'Contado';
    if (sale['payments'] != null && (sale['payments'] as List).isNotEmpty) {
      final List<dynamic> payments = sale['payments'];
      final List<String> methods = payments
          .map((p) =>
              p['payment_method']?['name']?.toString() ??
              p['name']?.toString() ??
              'Efectivo')
          .toList();
      paymentCondition = methods.toSet().join(' + ');
    } else if (sale['payment_status'] == 'pending') {
      paymentCondition = 'Cuenta Corriente';
    }

    // ── 5. Ítems de la Venta ──────────────────────────────────────────────────
    final items = sale['items'] as List<dynamic>? ?? [];

    // ── 6. Totales e Importes ─────────────────────────────────────────────────
    final totalAmount = double.tryParse((electronicInvoice['total_amount'] ??
                sale['total'] ??
                sale['total_amount'] ??
                0)
            .toString()) ??
        0.0;
    final netAmount = double.tryParse((electronicInvoice['net_amount'] ??
                sale['net_amount'] ??
                0)
            .toString()) ??
        0.0;
    final ivaAmount = double.tryParse((electronicInvoice['iva_amount'] ??
                sale['iva_amount'] ??
                0)
            .toString()) ??
        0.0;
    final exemptAmount = double.tryParse((electronicInvoice['exempt_amount'] ??
                sale['exempt_amount'] ??
                0)
            .toString()) ??
        0.0;
    final iibbPerceptionAmount = double.tryParse(
            (electronicInvoice['tribute_amount'] ??
                    electronicInvoice['iibb_perception_amount'] ??
                    sale['iibb_perception_amount'] ??
                    0)
                .toString()) ??
        0.0;
    double extractedRate = 0.0;
    if (electronicInvoice['tributes_breakdown'] != null && (electronicInvoice['tributes_breakdown'] as List).isNotEmpty) {
      extractedRate = double.tryParse(electronicInvoice['tributes_breakdown'][0]['Alic']?.toString() ?? '0') ?? 0.0;
    }
    final iibbPerceptionRate = double.tryParse(
            (electronicInvoice['iibb_perception_rate'] ??
                    sale['iibb_perception_rate'] ??
                    extractedRate)
                .toString()) ??
        0.0;

    final shippingCost =
        double.tryParse((sale['shipping_cost'] ?? 0).toString()) ?? 0.0;
    final surchargeAmount = double.tryParse(
            (sale['surcharge_amount'] ?? sale['total_surcharge'] ?? 0)
                .toString()) ??
        0.0;

    double calcItemsSubtotal = 0.0;
    for (final item in items) {
      if (item is Map) {
        final itemSub = double.tryParse((item['subtotal'] ?? 0).toString()) ??
            0.0;
        if (itemSub > 0.01) {
          calcItemsSubtotal += itemSub;
        } else {
          final uPrice = double.tryParse(
                  (item['unit_price'] ?? item['price'] ?? 0).toString()) ??
              0.0;
          final qty = double.tryParse(
                  (item['quantity'] ?? item['qty'] ?? 1).toString()) ??
              1.0;
          calcItemsSubtotal += uPrice * qty;
        }
      }
    }

    final rawSubtotal = double.tryParse(
            (sale['subtotal'] ?? sale['total'] ?? totalAmount).toString()) ??
        totalAmount;
    final fallbackSubtotal = (rawSubtotal - iibbPerceptionAmount - shippingCost)
        .clamp(0.0, double.infinity);
    final realSubtotal = calcItemsSubtotal > 0.01
        ? calcItemsSubtotal
        : (fallbackSubtotal > 0.01
            ? fallbackSubtotal
            : (rawSubtotal - iibbPerceptionAmount).clamp(0.0, double.infinity));
    final discountsOrSurcharges = surchargeAmount > 0.01
        ? surchargeAmount
        : (totalAmount - realSubtotal - shippingCost - iibbPerceptionAmount);

    double totalSavings =
        double.tryParse((sale['discount_amount'] ?? 0).toString()) ?? 0.0;
    if (totalSavings <= 0.01 && items.isNotEmpty) {
      double calcSavings = 0.0;
      for (final item in items) {
        if (item is Map) {
          final dAmt =
              double.tryParse((item['discount_amount'] ?? 0).toString()) ?? 0.0;
          if (dAmt > 0.01) {
            calcSavings += dAmt;
          } else {
            final regPrice = double.tryParse((item['regular_price'] ??
                        item['product']?['selling_price'] ??
                        0)
                    .toString()) ??
                0.0;
            final uPrice = double.tryParse(
                    (item['unit_price'] ?? item['price'] ?? 0).toString()) ??
                0.0;
            final qty = double.tryParse(
                    (item['quantity'] ?? item['qty'] ?? 1).toString()) ??
                1.0;
            if (regPrice > uPrice + 0.01) {
              calcSavings += (regPrice - uPrice) * qty;
            }
          }
        }
      }
      totalSavings = calcSavings;
    }

    // ── 7. Pie Fiscal (CAE y QR) ──────────────────────────────────────────────
    final cae = electronicInvoice['cae']?.toString() ?? '---';
    final caeExpiration = formatDate(electronicInvoice['cae_expiration'] ??
        DateTime.now().add(const Duration(days: 10)));

    final rawQrData = electronicInvoice['qr_data']?.toString();
    final qrData = (rawQrData != null && rawQrData.isNotEmpty)
        ? rawQrData
        : buildAfipQrUrl(
            issuerCuit: issuerCuit,
            ptoVta: pointOfSale,
            voucherType: voucherType,
            cbteNro: voucherNumber,
            totalAmount: totalAmount,
            date: issueDate,
            docNumber: receiverDoc != '---' ? receiverDoc : '0',
            cae: cae != '---' ? cae : '',
          );

    // ── 8. Construcción de Secciones Visuales ──────────────────────────────────
    final headerWidget = _buildAfipHeader(
      voucherTitle: voucherTitle,
      voucherLetter: voucherLetter,
      voucherCodeText: voucherCodeText,
      issuerName: issuerName,
      issuerCuit: issuerCuit,
      issuerAddress: issuerAddress,
      issuerPhone: issuerPhone,
      issuerTaxCondition: issuerTaxCondition,
      issuerIibb: issuerIibb,
      issuerStartDate: issuerStartDate,
      formattedNumber: formattedNumber,
      ptoVtaFormatted: ptoVtaFormatted,
      cbteNroFormatted: cbteNroFormatted,
      issueDate: issueDate,
      issueTime: issueTime,
      cashierName: cashierName,
    );

    final receiverWidget = _buildReceiverSection(
      receiverDoc: receiverDoc,
      receiverTaxCondition: receiverTaxCondition,
      receiverName: receiverName,
      receiverAddress: receiverAddress,
      paymentCondition: paymentCondition,
    );

    final itemsTableWidget = _buildItemsTable(
      items: items,
      isFacturaA: voucherLetter == 'A',
    );

    final taxableTotal = (totalAmount - iibbPerceptionAmount).clamp(0.0, double.infinity);
    final baseForTaxes = taxableTotal > 0 ? taxableTotal : totalAmount;
    final resolvedIvaContenido = ivaAmount > 0
        ? ivaAmount
        : _calculateContainedIvaFromItems(items, baseForTaxes);
    final resolvedNetSinImpuestos = netAmount > 0
        ? netAmount
        : (baseForTaxes - resolvedIvaContenido).clamp(0.0, double.infinity);

    final totalsWidget = _buildTotalsSection(
      isFacturaA: voucherLetter == 'A',
      isFacturaB: voucherLetter == 'B',
      netAmount: netAmount,
      ivaAmount: ivaAmount,
      containedNetAmount: resolvedNetSinImpuestos,
      containedIvaAmount: resolvedIvaContenido,
      exemptAmount: exemptAmount,
      subtotal: realSubtotal,
      shippingCost: shippingCost,
      totalSavings: totalSavings,
      discountsOrSurcharges: discountsOrSurcharges,
      totalAmount: totalAmount,
      ivaBreakdown: electronicInvoice['iva_breakdown'] as List<dynamic>?,
      iibbPerceptionAmount: iibbPerceptionAmount,
      iibbPerceptionRate: iibbPerceptionRate,
    );

    final footerWidget = _buildFiscalFooter(
      qrData: qrData,
      cae: cae,
      caeExpiration: caeExpiration,
      logoBytes: logoBytes,
      isCompact: isCompact,
    );

    final isCreditNote = [3, 8, 13, 113].contains(voucherType);
    final gap = isCompact ? 3.5 : 6.0;

    return [
      headerWidget,
      pw.SizedBox(height: gap),
      receiverWidget,
      if (isCreditNote) pw.SizedBox(height: gap),
      if (isCreditNote) pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('COMPROBANTE ASOCIADO (RG 1415)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text(
              (electronicInvoice['associated_voucher_label'] ??
                      sale['associated_voucher_label'] ??
                      (electronicInvoice['associated_formatted_number'] != null
                          ? 'Factura $voucherLetter Nº ${electronicInvoice['associated_formatted_number']}'
                          : 'Factura $voucherLetter Original Autorizada'))
                  .toString(),
              style: const pw.TextStyle(fontSize: 8),
            ),
          ]
        )
      ),
      pw.SizedBox(height: gap),
      itemsTableWidget,
      pw.SizedBox(height: gap),
      totalsWidget,
      if (_buildPaymentSummary(sale, isCompact: isCompact) != null) ...[
        pw.SizedBox(height: gap),
        _buildPaymentSummary(sale, isCompact: isCompact)!,
      ],
      pw.SizedBox(height: gap),
      footerWidget,
    ];
  }

  /// Construye la sección de Remito / Orden de Retiro homologada con el estilo visual
  /// de la Factura Fiscal ARCA para la mitad inferior (o segunda hoja) en entregas inmediatas.
  static List<pw.Widget> buildDeliveryNoteWidgets({
    required Map<String, dynamic> sale,
    required Map<String, dynamic> electronicInvoice,
    required Map<String, dynamic> deliveryNote,
    dynamic businessSettings,
    Uint8List? logoBytes,
    bool isCompact = false,
  }) {
    String issuerName = 'Mi Negocio';
    String issuerCuit = '30-00000000-0';
    String issuerAddress = 'Domicilio Comercial';
    String issuerPhone = '';
    String issuerTaxCondition = 'IVA Responsable Inscripto';
    String issuerIibb = '';
    String issuerStartDate = '';

    if (businessSettings is BusinessSettings) {
      if (businessSettings.companyName != null &&
          businessSettings.companyName!.isNotEmpty) {
        issuerName = businessSettings.companyName!;
      }
      if (businessSettings.taxId != null &&
          businessSettings.taxId!.isNotEmpty) {
        issuerCuit = businessSettings.taxId!;
      }
      if (businessSettings.address != null &&
          businessSettings.address!.isNotEmpty) {
        issuerAddress = businessSettings.address!;
      }
      if (businessSettings.phone != null &&
          businessSettings.phone!.trim().isNotEmpty) {
        issuerPhone = businessSettings.phone!.trim();
      }
      if (businessSettings.taxCondition != null &&
          businessSettings.taxCondition!.isNotEmpty) {
        issuerTaxCondition = businessSettings.taxCondition!;
      }
      if (businessSettings.iibb != null &&
          businessSettings.iibb!.trim().isNotEmpty) {
        issuerIibb = businessSettings.iibb!.trim();
      }
      if (businessSettings.activityStartDate != null &&
          businessSettings.activityStartDate!.trim().isNotEmpty) {
        issuerStartDate = businessSettings.activityStartDate!.trim();
      }
    } else if (businessSettings is Map) {
      issuerName = (businessSettings['company_name'] ??
              businessSettings['companyName'] ??
              issuerName)
          .toString();
      issuerCuit =
          (businessSettings['tax_id'] ?? businessSettings['taxId'] ?? issuerCuit)
              .toString();
      issuerAddress = (businessSettings['address'] ?? issuerAddress).toString();
      issuerPhone = (businessSettings['phone'] ?? '').toString().trim();
      issuerTaxCondition = (businessSettings['tax_condition'] ??
              businessSettings['taxCondition'] ??
              issuerTaxCondition)
          .toString();
      issuerIibb = (businessSettings['iibb'] ?? '').toString().trim();
      issuerStartDate = (businessSettings['activity_start_date'] ??
              businessSettings['activityStartDate'] ??
              '')
          .toString()
          .trim();
    }

    issuerCuit = _formatCuit(issuerCuit);
    issuerIibb = issuerIibb.isNotEmpty ? _formatCuit(issuerIibb) : 'Exento';
    issuerTaxCondition = _formatTaxCondition(issuerTaxCondition);
    issuerStartDate =
        issuerStartDate.isNotEmpty ? formatDate(issuerStartDate) : '01/01/2020';

    final noteId =
        (deliveryNote['id'] ?? sale['id'] ?? 1).toString().padLeft(8, '0');
    final noteStatus =
        (deliveryNote['status'] ?? sale['fulfillment_status'] ?? 'delivered')
            .toString()
            .toLowerCase();
    final isDelivered = noteStatus == 'delivered' || noteStatus == 'partial';
    final remitoLetter = isDelivered ? 'R' : 'X';
    final remitoCode = isDelivered ? 'COD. 091' : 'INTERNO';
    final remitoTitle = isDelivered
        ? 'REMITO — ENTREGA INMEDIATA'
        : 'ORDEN DE RETIRO';

    final rawVoucherLetter =
        (electronicInvoice['voucher_letter'] ?? 'B').toString().toUpperCase();
    final formattedInvoiceNumber =
        (electronicInvoice['formatted_number'] ?? '').toString();
    final saleIdStr = (sale['id'] ?? '').toString();
    final associatedLabel = formattedInvoiceNumber.isNotEmpty
        ? 'Factura $rawVoucherLetter $formattedInvoiceNumber (Ticket #$saleIdStr)'
        : 'Ticket #$saleIdStr';

    final issueDate = formatDate(
        electronicInvoice['issued_at'] ?? sale['created_at'] ?? DateTime.now());
    final cashierName = (sale['cashier']?['name'] ??
            sale['cashier_name'] ??
            sale['user']?['name'] ??
            sale['userName'] ??
            'Cajero')
        .toString();

    final rawReceiverDoc = (electronicInvoice['doc_number'] ??
            sale['customer']?['document_number'] ??
            sale['customer']?['tax_id'] ??
            '---')
        .toString();
    final receiverDoc = _formatCuit(rawReceiverDoc);
    final receiverName = (electronicInvoice['receiver_name'] ??
            sale['customer']?['name'] ??
            sale['customer_name'] ??
            'Consumidor Final')
        .toString();
    final deliveryAddress = (deliveryNote['delivery_address'] ??
            deliveryNote['sale']?['delivery_address'] ??
            sale['delivery_address'] ??
            electronicInvoice['receiver_address'] ??
            sale['customer']?['delivery_address'] ??
            sale['customer']?['address'] ??
            'Retiro en Mostrador / Local')
        .toString();

    final rawItems = (deliveryNote['items'] as List<dynamic>?) ??
        (sale['items'] as List<dynamic>?) ??
        [];
    int totalUnits = 0;
    for (final it in rawItems) {
      if (it is Map) {
        final q = double.tryParse((it['quantity'] ??
                    it['quantity_purchased'] ??
                    it['qty'] ??
                    1)
                .toString()) ??
            1.0;
        final isW = it['product']?['is_sold_by_weight'] == true ||
            it['is_sold_by_weight'] == true;
        if (!isW) totalUnits += q.toInt();
      }
    }

    final gap = isCompact ? 3.5 : 6.0;

    return [
      // 1. Cabecera del Remito (mismo estilo que Factura Fiscal ARCA)
      pw.Stack(
        alignment: pw.Alignment.topCenter,
        children: [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1.0),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(
                        8, isCompact ? 5 : 8, 26, isCompact ? 5 : 8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          issuerName.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: isCompact ? 13 : 15,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.SizedBox(height: isCompact ? 3 : 6),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              flex: 5,
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text('Razón Social: $issuerName',
                                      style: const pw.TextStyle(fontSize: 7.2)),
                                  pw.Text('Domicilio Comercial: $issuerAddress',
                                      style: const pw.TextStyle(fontSize: 7.2)),
                                  if (issuerPhone.isNotEmpty)
                                    pw.Text('Teléfono: $issuerPhone',
                                        style:
                                            const pw.TextStyle(fontSize: 7.2)),
                                  pw.Text(
                                      'Cond. frente al IVA: $issuerTaxCondition',
                                      style: pw.TextStyle(
                                          fontSize: 7.2,
                                          fontWeight: pw.FontWeight.bold)),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 4),
                            pw.Expanded(
                              flex: 4,
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text('CUIT: $issuerCuit',
                                      style: pw.TextStyle(
                                          fontSize: 7.2,
                                          fontWeight: pw.FontWeight.bold)),
                                  pw.Text('Ingresos Brutos: $issuerIibb',
                                      style: const pw.TextStyle(fontSize: 7.2)),
                                  pw.Text(
                                      'Inicio de Actividades: $issuerStartDate',
                                      style: const pw.TextStyle(fontSize: 7.2)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(
                        26, isCompact ? 5 : 8, 8, isCompact ? 5 : 8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              child: pw.Text(
                                remitoTitle,
                                style: pw.TextStyle(
                                  fontSize: isCompact ? 10.5 : 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black,
                                ),
                              ),
                            ),
                            pw.Text(
                              'ORIGINAL',
                              style: const pw.TextStyle(
                                fontSize: 9,
                                color: PdfColors.black,
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Remito Nro: 00001-$noteId',
                          style: pw.TextStyle(
                              fontSize: 8.2, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text('Comp. Asociado: $associatedLabel',
                            style: const pw.TextStyle(fontSize: 7.8)),
                        pw.Text('Fecha de Emisión: $issueDate',
                            style: const pw.TextStyle(fontSize: 7.8)),
                        pw.Text('Cajero / Despachante: ${cashierName.toUpperCase()}',
                            style: const pw.TextStyle(fontSize: 7.8)),
                        pw.Text(
                          'DOCUMENTO NO VÁLIDO COMO FACTURA',
                          style: pw.TextStyle(
                            fontSize: 6.8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.Positioned(
            top: 0,
            child: pw.Container(
              width: isCompact ? 38 : 42,
              height: isCompact ? 38 : 42,
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: PdfColors.black, width: 1.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    remitoLetter,
                    style: pw.TextStyle(
                      fontSize: isCompact ? 17 : 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.Text(
                    remitoCode,
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
      pw.SizedBox(height: gap),

      // 2. Destinatario / Entrega
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        ),
        padding: pw.EdgeInsets.symmetric(
            horizontal: 8, vertical: isCompact ? 3.5 : 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CUIT / DNI: $receiverDoc',
                      style: pw.TextStyle(
                          fontSize: 7.8, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 1.5),
                  pw.Text('Destinatario / Cliente: $receiverName',
                      style: pw.TextStyle(
                          fontSize: 7.8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Domicilio de Entrega: $deliveryAddress',
                      style: const pw.TextStyle(fontSize: 7.8)),
                  pw.SizedBox(height: 1.5),
                  pw.Text(
                    'Estado: ${isDelivered ? "ENTREGADO EN EL ACTO" : "PENDIENTE DE RETIRO"}',
                    style: pw.TextStyle(
                        fontSize: 7.8, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: gap),

      // 3. Tabla de Artículos del Remito
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.5),
          1: pw.FlexColumnWidth(1.2),
          2: pw.FlexColumnWidth(5.5),
          3: pw.FlexColumnWidth(1.8),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              _buildTableHeaderCell('CÓDIGO', textAlign: pw.TextAlign.center),
              _buildTableHeaderCell('CANT.', textAlign: pw.TextAlign.center),
              _buildTableHeaderCell('DESCRIPCIÓN DEL ARTÍCULO',
                  textAlign: pw.TextAlign.left),
              _buildTableHeaderCell('ESTADO', textAlign: pw.TextAlign.center),
            ],
          ),
          ...rawItems.map((item) {
            final pCode = (item['product']?['internal_code'] ??
                    item['internal_code'] ??
                    '-')
                .toString();
            final pName = (item['product_name'] ??
                    item['name'] ??
                    item['product']?['name'] ??
                    'Producto')
                .toString();
            final qty = double.tryParse((item['quantity'] ??
                        item['quantity_purchased'] ??
                        item['qty'] ??
                        1)
                    .toString()) ??
                1.0;
            final isWeight = item['product']?['is_sold_by_weight'] == true ||
                item['is_sold_by_weight'] == true;
            final qtyText =
                isWeight ? '${qty.toQty()} kg' : '${qty.toInt()} un';

            return pw.TableRow(
              children: [
                _buildTableCell(pCode.trim().isEmpty ? '-' : pCode,
                    textAlign: pw.TextAlign.center),
                _buildTableCell(qtyText, textAlign: pw.TextAlign.center),
                _buildTableCell(pName.toUpperCase(),
                    textAlign: pw.TextAlign.left),
                _buildTableCell(isDelivered ? 'ENTREGADO' : 'A RETIRAR',
                    textAlign: pw.TextAlign.center),
              ],
            );
          }),
        ],
      ),
      pw.SizedBox(height: gap),

      // 4. Pie de Conformidad de Entrega y Logo
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        ),
        padding: pw.EdgeInsets.all(isCompact ? 5 : 7),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ENTREGADO POR (DESPACHO)',
                    style: pw.TextStyle(
                        fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: isCompact ? 14 : 20),
                  pw.Text(
                    'Firma y Aclaración: ________________________',
                    style: const pw.TextStyle(fontSize: 7.2),
                  ),
                  if (totalUnits > 0) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Total Unidades / Bultos: $totalUnits',
                      style: pw.TextStyle(
                          fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RECIBÍ CONFORME (CLIENTE / RETIRA)',
                    style: pw.TextStyle(
                        fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: isCompact ? 14 : 20),
                  pw.Text(
                    'Firma: ___________________  Aclaración / DNI: ___________________',
                    style: const pw.TextStyle(fontSize: 7.2),
                  ),
                ],
              ),
            ),
            if (logoBytes != null) ...[
              pw.SizedBox(width: 10),
              pw.Container(
                width: isCompact ? 44 : 52,
                height: isCompact ? 44 : 52,
                alignment: pw.Alignment.centerRight,
                child:
                    pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  /// Calcula el IVA contenido para Factura B / Nota de Crédito B (RG 5614 - Ley 27.743)
  /// cuando el backend no envió explícitamente `iva_amount`.
  static double _calculateContainedIvaFromItems(List<dynamic> items, double fallbackSubtotal) {
    if (items.isNotEmpty) {
      double totalIva = 0.0;
      for (final item in items) {
        if (item is Map) {
          final sub = double.tryParse((item['subtotal'] ?? item['total'] ?? 0).toString()) ?? 0.0;
          final rate = double.tryParse((item['iva_rate'] ?? item['tax_rate'] ?? item['aliquot'] ?? 21).toString()) ?? 21.0;
          if (rate > 0 && sub > 0) {
            final net = sub / (1 + (rate / 100));
            totalIva += (sub - net);
          }
        }
      }
      if (totalIva > 0) {
        return totalIva;
      }
    }
    if (fallbackSubtotal > 0) {
      return fallbackSubtotal - (fallbackSubtotal / 1.21);
    }
    return 0.0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Componente 1: Cabecera Oficial AFIP RG 1415
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildAfipHeader({
    required String voucherTitle,
    required String voucherLetter,
    required String voucherCodeText,
    required String issuerName,
    required String issuerCuit,
    required String issuerAddress,
    String issuerPhone = '',
    required String issuerTaxCondition,
    required String issuerIibb,
    required String issuerStartDate,
    required String formattedNumber,
    required String ptoVtaFormatted,
    required String cbteNroFormatted,
    required String issueDate,
    required String issueTime,
    required String cashierName,
  }) {
    return pw.Stack(
      alignment: pw.Alignment.topCenter,
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1.0),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              children: [
                // Emisor (Columna Izquierda)
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(8, 8, 26, 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        issuerName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            flex: 5,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('Razón Social: $issuerName',
                                    style: const pw.TextStyle(fontSize: 7.5)),
                                pw.Text('Domicilio Comercial: $issuerAddress',
                                    style: const pw.TextStyle(fontSize: 7.5)),
                                if (issuerPhone.isNotEmpty)
                                  pw.Text('Teléfono: $issuerPhone',
                                      style: const pw.TextStyle(fontSize: 7.5)),
                                pw.Text('Cond. frente al IVA: $issuerTaxCondition',
                                    style: pw.TextStyle(
                                        fontSize: 7.5,
                                        fontWeight: pw.FontWeight.bold)),
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 4),
                          pw.Expanded(
                            flex: 4,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('CUIT: $issuerCuit',
                                    style: pw.TextStyle(
                                        fontSize: 7.5,
                                        fontWeight: pw.FontWeight.bold)),
                                pw.Text('Ingresos Brutos: $issuerIibb',
                                    style: const pw.TextStyle(fontSize: 7.5)),
                                pw.Text('Inicio de Actividades: $issuerStartDate',
                                    style: const pw.TextStyle(fontSize: 7.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Comprobante (Columna Derecha)
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(26, 8, 8, 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            voucherTitle,
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                          pw.Text(
                            'ORIGINAL',
                            style: pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.black,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Punto de Venta: $ptoVtaFormatted   Comp. Nro: $cbteNroFormatted ($formattedNumber)',
                        style: pw.TextStyle(
                            fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text('Fecha de Emisión: $issueDate $issueTime',
                          style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text('Cajero: ${cashierName.toUpperCase()}',
                          style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text('Concepto: 1 - Productos',
                          style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text('Período Facturado: $issueDate al $issueDate',
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),

        // Recuadro Central Superior de Letra y Código Fiscal AFIP
        pw.Positioned(
          top: 0,
          child: pw.Container(
            width: 42,
            height: 42,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  voucherLetter,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  voucherCodeText,
                  style: pw.TextStyle(
                    fontSize: 6,
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

  // ─────────────────────────────────────────────────────────────────────────
  // Componente 2: Sección Receptor (Datos del Cliente)
  // ─────────────────────────────────────────────────────────────────────────
  static String _formatCuit(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11 && RegExp(r'^[0-9\-\s]+$').hasMatch(trimmed)) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 10)}-${digits.substring(10)}';
    }
    return trimmed;
  }

  static String _formatTaxCondition(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'consumidor_final':
      case 'consumidor final':
      case 'a consumidor final':
        return 'Consumidor Final';
      case 'responsable_inscripto':
      case 'iva responsable inscripto':
        return 'IVA Responsable Inscripto';
      case 'monotributo':
      case 'responsable_monotributo':
      case 'responsable monotributo':
        return 'Responsable Monotributo';
      case 'exento':
      case 'sujeto_exento':
      case 'iva_exento':
      case 'iva sujeto exento':
        return 'IVA Sujeto Exento';
      default:
        return raw;
    }
  }

  static pw.Widget _buildReceiverSection({
    required String receiverDoc,
    required String receiverTaxCondition,
    required String receiverName,
    required String receiverAddress,
    required String paymentCondition,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 5,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('CUIT / DNI: $receiverDoc',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('Condición frente al IVA: $receiverTaxCondition',
                    style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 2),
                pw.Text('Apellido y Nombre / Razón Social: $receiverName',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 4,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Domicilio: $receiverAddress',
                    style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 2),
                pw.Text('Condición de venta: $paymentCondition',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Componente 3: Tabla de Ítems (Diferenciada Factura A vs B/C)
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildItemsTable({
    required List<dynamic> items,
    required bool isFacturaA,
  }) {
    if (isFacturaA) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.2), // Cantidad
          1: const pw.FlexColumnWidth(5.0), // Descripción
          2: const pw.FlexColumnWidth(2.0), // Precio Unitario (Neto)
          3: const pw.FlexColumnWidth(1.6), // Alícuota IVA (% IVA)
          4: const pw.FlexColumnWidth(2.0), // Subtotal Neto
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              _buildTableHeaderCell('CANT.', textAlign: pw.TextAlign.center),
              _buildTableHeaderCell('DESCRIPCIÓN', textAlign: pw.TextAlign.left),
              _buildTableHeaderCell('PRECIO UNIT. (NETO)',
                  textAlign: pw.TextAlign.right),
              _buildTableHeaderCell('% IVA', textAlign: pw.TextAlign.center),
              _buildTableHeaderCell('SUBTOTAL NETO',
                  textAlign: pw.TextAlign.right),
            ],
          ),
          ...items.map((item) {
            final name = (item['product_name'] ??
                    item['name'] ??
                    item['product']?['name'] ??
                    'Producto')
                .toString();
            final qty = double.tryParse(
                    (item['quantity'] ?? item['qty'] ?? 1).toString()) ??
                1.0;
            final isWeight = item['product']?['is_sold_by_weight'] == true ||
                item['is_sold_by_weight'] == true;
            final qtyText = isWeight ? qty.toQty() : qty.toInt().toString();

            final subtotal = double.tryParse(
                    (item['subtotal'] ?? item['total'] ?? 0).toString()) ??
                0.0;
            final ivaRate = double.tryParse((item['iva_rate'] ??
                        item['tax_rate'] ??
                        item['aliquot'] ??
                        21)
                    .toString()) ??
                21.0;

            final netSubtotal = item['net_amount'] != null
                ? (double.tryParse(item['net_amount'].toString()) ??
                    (subtotal / (1 + ivaRate / 100)))
                : (subtotal / (1 + ivaRate / 100));
            final netUnitPrice =
                qty > 0 ? (netSubtotal / qty) : (subtotal / (1 + ivaRate / 100));

            return pw.TableRow(
              children: [
                _buildTableCell(qtyText, textAlign: pw.TextAlign.center),
                _buildTableCell(name.toUpperCase(), textAlign: pw.TextAlign.left),
                _buildTableCell(formatCurrency(netUnitPrice),
                    textAlign: pw.TextAlign.right),
                _buildTableCell('${ivaRate.toStringAsFixed(1)}%',
                    textAlign: pw.TextAlign.center),
                _buildTableCell(formatCurrency(netSubtotal),
                    textAlign: pw.TextAlign.right),
              ],
            );
          }),
        ],
      );
    } else {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.2), // Cantidad
          1: const pw.FlexColumnWidth(5.8), // Descripción
          2: const pw.FlexColumnWidth(2.0), // Precio Unitario
          3: const pw.FlexColumnWidth(2.0), // Subtotal
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              _buildTableHeaderCell('CANT.', textAlign: pw.TextAlign.center),
              _buildTableHeaderCell('DESCRIPCIÓN', textAlign: pw.TextAlign.left),
              _buildTableHeaderCell('PRECIO UNIT.',
                  textAlign: pw.TextAlign.right),
              _buildTableHeaderCell('SUBTOTAL', textAlign: pw.TextAlign.right),
            ],
          ),
          ...items.map((item) {
            final name = (item['product_name'] ??
                    item['name'] ??
                    item['product']?['name'] ??
                    'Producto')
                .toString();
            final qty = double.tryParse(
                    (item['quantity'] ?? item['qty'] ?? 1).toString()) ??
                1.0;
            final isWeight = item['product']?['is_sold_by_weight'] == true ||
                item['is_sold_by_weight'] == true;
            final qtyText = isWeight ? qty.toQty() : qty.toInt().toString();

            final subtotal = double.tryParse(
                    (item['subtotal'] ?? item['total'] ?? 0).toString()) ??
                0.0;
            final unitPrice = double.tryParse(
                    (item['unit_price'] ?? item['price'] ?? 0).toString()) ??
                (qty > 0 ? subtotal / qty : 0.0);

            final regularPrice = double.tryParse((item['regular_price'] ??
                        item['product']?['selling_price'] ??
                        0)
                    .toString()) ??
                0.0;
            final discountSaving =
                double.tryParse((item['discount_amount'] ?? 0).toString()) ??
                    0.0;
            final hasItemDiscount =
                discountSaving > 0.01 || (regularPrice > unitPrice + 0.01);
            final effectiveRegularPrice = regularPrice > unitPrice + 0.01
                ? regularPrice
                : (qty > 0 ? unitPrice + (discountSaving / qty) : unitPrice);
            final effectiveSaving = discountSaving > 0.01
                ? discountSaving
                : (effectiveRegularPrice - unitPrice) * qty;
            final rawLabel = (item['discount_label'] ??
                    item['offer_label'] ??
                    'Descuento')
                .toString()
                .trim();
            final discountLabel = rawLabel.isNotEmpty ? rawLabel : 'Descuento';

            return pw.TableRow(
              children: [
                _buildTableCell(qtyText, textAlign: pw.TextAlign.center),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 5.0, horizontal: 5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        name.toUpperCase(),
                        textAlign: pw.TextAlign.left,
                        style: const pw.TextStyle(
                            fontSize: 8.0, color: PdfColors.black),
                      ),
                      if (hasItemDiscount)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 1.5),
                          child: pw.Text(
                            '($discountLabel) Precio Lista: ${formatCurrency(effectiveRegularPrice)} (-${formatCurrency(effectiveSaving)})',
                            style: pw.TextStyle(
                              fontSize: 7.0,
                              fontStyle: pw.FontStyle.italic,
                              color: PdfColors.grey800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _buildTableCell(formatCurrency(unitPrice),
                    textAlign: pw.TextAlign.right),
                _buildTableCell(formatCurrency(subtotal),
                    textAlign: pw.TextAlign.right),
              ],
            );
          }),
        ],
      );
    }
  }

  static pw.Widget _buildTableHeaderCell(String text,
      {required pw.TextAlign textAlign}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 5),
      child: pw.Text(
        text,
        textAlign: textAlign,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _buildTableCell(String text,
      {required pw.TextAlign textAlign}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5.0, horizontal: 5),
      child: pw.Text(
        text,
        textAlign: textAlign,
        style: const pw.TextStyle(fontSize: 8.0, color: PdfColors.black),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Componente 4: Sección de Totales (Diferenciada Factura A vs B vs C)
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildTotalsSection({
    required bool isFacturaA,
    bool isFacturaB = false,
    required double netAmount,
    required double ivaAmount,
    double containedNetAmount = 0.0,
    double containedIvaAmount = 0.0,
    required double exemptAmount,
    required double subtotal,
    double shippingCost = 0.0,
    double totalSavings = 0.0,
    required double discountsOrSurcharges,
    required double totalAmount,
    List<dynamic>? ivaBreakdown,
    double iibbPerceptionAmount = 0.0,
    double iibbPerceptionRate = 0.0,
  }) {
    if (isFacturaA) {
      double iva21 = 0.0;
      double iva105 = 0.0;
      final otherIvas = <pw.Widget>[];

      if (ivaBreakdown != null && ivaBreakdown.isNotEmpty) {
        for (final item in ivaBreakdown) {
          if (item is Map) {
            final id = item['id'] ?? item['iva_id'];
            final imp = double.tryParse(
                    (item['importe'] ?? item['amount'] ?? 0).toString()) ??
                0.0;
            if (id == 5) {
              iva21 += imp;
            } else if (id == 4) {
              iva105 += imp;
            } else if (id == 6) {
              otherIvas.add(pw.Text('IVA 27%: ${formatCurrency(imp)}',
                  style: const pw.TextStyle(fontSize: 8)));
            } else if (id == 8) {
              otherIvas.add(pw.Text('IVA 5%: ${formatCurrency(imp)}',
                  style: const pw.TextStyle(fontSize: 8)));
            } else if (id == 9) {
              otherIvas.add(pw.Text('IVA 2.5%: ${formatCurrency(imp)}',
                  style: const pw.TextStyle(fontSize: 8)));
            }
          }
        }
      }

      if (iva21 == 0.0 && iva105 == 0.0 && otherIvas.isEmpty && ivaAmount > 0) {
        iva21 = ivaAmount;
      }

      final resolvedNetAmount =
          netAmount > 0 ? netAmount : (totalAmount - ivaAmount);

      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Subtotal Neto Gravado: ${formatCurrency(resolvedNetAmount)}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  if (shippingCost > 0.01)
                    pw.Text(
                      'Incluye Flete / Envío (Neto s/IVA): ${formatCurrency(shippingCost / 1.21)}',
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                  pw.Text('IVA 21%: ${formatCurrency(iva21)}',
                       style: const pw.TextStyle(fontSize: 8)),
                  if (iva105 > 0)
                    pw.Text('IVA 10.5%: ${formatCurrency(iva105)}',
                        style: const pw.TextStyle(fontSize: 8)),
                  ...otherIvas,
                  if (exemptAmount > 0)
                    pw.Text('Importe Exento: ${formatCurrency(exemptAmount)}',
                        style: const pw.TextStyle(fontSize: 8)),
                  if (iibbPerceptionAmount > 0)
                    pw.Text(
                      'Percepción IIBB (${iibbPerceptionRate > 0 ? iibbPerceptionRate.toStringAsFixed(1) : "0.0"}%): ${formatCurrency(iibbPerceptionAmount)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                ],
              ),
            ),
            pw.Expanded(
              flex: 4,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Importe Total: ',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text(formatCurrency(totalAmount),
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      final hasSavings = totalSavings > 0.01;
      final effectiveContainedNet = containedNetAmount > 0
          ? containedNetAmount
          : ((subtotal > 0 ? subtotal : totalAmount) - containedIvaAmount)
              .clamp(0.0, double.infinity);

      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              flex: 6,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (hasSavings) ...[
                    pw.Text(
                      'Subtotal Lista: ${formatCurrency(subtotal + totalSavings)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      'Ahorro / Descuento: -${formatCurrency(totalSavings)}',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                  pw.Text('Subtotal: ${formatCurrency(subtotal)}',
                      style: const pw.TextStyle(fontSize: 8)),
                  if (shippingCost > 0.01)
                    pw.Text(
                      'Flete / Envío: ${formatCurrency(shippingCost)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  if (discountsOrSurcharges.abs() > 0.01)
                    pw.Text(
                      'Descuentos / Recargos: ${formatCurrency(discountsOrSurcharges)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  if (iibbPerceptionAmount > 0)
                    pw.Text(
                      'Percepción IIBB (${iibbPerceptionRate > 0 ? iibbPerceptionRate.toStringAsFixed(1) : "0.0"}%): ${formatCurrency(iibbPerceptionAmount)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  if (isFacturaB) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Régimen de Transparencia Fiscal al Consumidor (Ley 27.743)',
                      style: pw.TextStyle(
                          fontSize: 6.8, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Precio s/imp: ${formatCurrency(effectiveContainedNet)} - IVA Contenido: ${formatCurrency(containedIvaAmount)}\nOtros Impuestos Nacionales Indirectos: ${formatCurrency(0)}',
                      style: const pw.TextStyle(fontSize: 6.8),
                    ),
                  ],
                ],
              ),
            ),
            pw.Expanded(
              flex: 4,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Importe Total: ',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text(formatCurrency(totalAmount),
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  static pw.Widget? _buildPaymentSummary(Map<String, dynamic> sale,
      {bool isCompact = false}) {
    final payments = sale['payments'] as List<dynamic>? ?? [];
    final hasTendered = (double.tryParse(sale['tendered_amount']?.toString() ?? '0') ?? 0.0) > 0.01;
    final tendered = double.tryParse(sale['tendered_amount']?.toString() ?? '0') ?? 0.0;
    final change = double.tryParse(sale['change_amount']?.toString() ?? '0') ?? 0.0;

    final paymentsRows = <pw.Widget>[];
    for (final p in payments) {
      final name = p['payment_method']?['name']?.toString() ??
          p['name']?.toString() ??
          'Pago';
      final amt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
      paymentsRows.add(pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(name, style: const pw.TextStyle(fontSize: 8)), pw.Text(formatCurrency(amt), style: const pw.TextStyle(fontSize: 8))],
      ));
    }
    if (hasTendered && (payments.length <= 1 || change > 0.01)) {
      paymentsRows.add(pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text('Efectivo Recibido', style: const pw.TextStyle(fontSize: 8)), pw.Text(formatCurrency(tendered), style: const pw.TextStyle(fontSize: 8))],
      ));
      paymentsRows.add(pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text('Su Vuelto', style: const pw.TextStyle(fontSize: 8)), pw.Text(formatCurrency(change), style: const pw.TextStyle(fontSize: 8))],
      ));
    }

    if (paymentsRows.isEmpty) return null;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      padding: pw.EdgeInsets.symmetric(
          horizontal: 10, vertical: isCompact ? 3.5 : 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Detalle de Pagos:', style: pw.TextStyle(fontSize: isCompact ? 8.2 : 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: isCompact ? 1.5 : 3),
          ...paymentsRows,
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Componente 5: Pie Fiscal AFIP RG 4892 (Código QR, CAE y Vencimiento)
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildFiscalFooter({
    required String qrData,
    required String cae,
    required String caeExpiration,
    Uint8List? logoBytes,
    bool isCompact = false,
  }) {
    final qrSize = isCompact ? 46.0 : 60.0;
    final logoSize = isCompact ? 44.0 : 55.0;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      padding: pw.EdgeInsets.all(isCompact ? 4.5 : 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Código QR Oficial RG 4892
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrData,
            width: qrSize,
            height: qrSize,
          ),
          pw.SizedBox(width: 10),
          // Leyenda Legal AFIP y CAE (Agrupados en el medio)
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CAE N°: $cae',
                  style: pw.TextStyle(
                      fontSize: isCompact ? 8.8 : 9.5,
                      fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 1.5),
                pw.Text(
                  'Fecha de Vto. de CAE: $caeExpiration',
                  style: pw.TextStyle(fontSize: isCompact ? 7.5 : 8),
                ),
                pw.SizedBox(height: isCompact ? 3 : 8),
                pw.Text(
                  'Comprobante Autorizado por AFIP (RG 4892)',
                  style: pw.TextStyle(
                      fontSize: isCompact ? 7.0 : 7.5,
                      fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Esta Administración Federal no se responsabiliza por los datos ingresados en el detalle de la operación.',
                  style: const pw.TextStyle(
                      fontSize: 6.5, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          // Logo (a la derecha de todo, donde estaba el CAE)
          if (logoBytes != null) ...[
            pw.SizedBox(width: 10),
            pw.Container(
              width: logoSize,
              height: logoSize,
              alignment: pw.Alignment.centerRight,
              child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Utilidades: Constructor de URL QR Oficial AFIP (RG 4892)
  // ─────────────────────────────────────────────────────────────────────────
  static String buildAfipQrUrl({
    required String issuerCuit,
    required int ptoVta,
    required int voucherType,
    required int cbteNro,
    required double totalAmount,
    required String date,
    int docType = 99,
    String docNumber = '0',
    String cae = '',
  }) {
    final cleanCuit =
        int.tryParse(issuerCuit.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final cleanDoc =
        int.tryParse(docNumber.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final cleanCae = int.tryParse(cae.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    final jsonMap = {
      'ver': 1,
      'fecha': date,
      'cuit': cleanCuit,
      'ptoVta': ptoVta,
      'tipoCmp': voucherType,
      'nroCmp': cbteNro,
      'importe': double.parse(totalAmount.toStringAsFixed(2)),
      'moneda': 'PES',
      'ctz': 1,
      'tipoDocRec': docType,
      'nroDocRec': cleanDoc,
      'tipoCodAut': 'E',
      'codAut': cleanCae,
    };
    final jsonString = jsonEncode(jsonMap);
    final base64String = base64Encode(utf8.encode(jsonString));
    return 'https://www.afip.gob.ar/fe/qr/?p=$base64String';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Utilidades: Inspección Recursiva de AST Widgets para Testing
  // ─────────────────────────────────────────────────────────────────────────
  static List<T> findWidgets<T extends pw.Widget>(dynamic root) {
    final List<T> results = [];

    void traverse(dynamic node) {
      if (node == null) return;

      if (node is T) {
        results.add(node);
      }

      if (node is AfipFiscalDocument) {
        for (final w in node.widgets) {
          traverse(w);
        }
        return;
      }

      if (node is List) {
        for (final item in node) {
          traverse(item);
        }
        return;
      }

      if (node is pw.Container) {
        if (node.child != null) {
          traverse(node.child);
        }
      } else if (node is pw.MultiChildWidget) {
        for (final child in node.children) {
          traverse(child);
        }
      } else if (node is pw.SingleChildWidget) {
        if (node.child != null) {
          traverse(node.child);
        }
      } else if (node is pw.Table) {
        for (final row in node.children) {
          for (final cell in row.children) {
            traverse(cell);
          }
        }
      } else if (node is pw.DecoratedBox) {
        if (node.child != null) {
          traverse(node.child);
        }
      } else if (node is pw.Padding) {
        if (node.child != null) {
          traverse(node.child);
        }
      } else if (node is pw.Transform) {
        if (node.child != null) {
          traverse(node.child);
        }
      } else if (node is pw.Opacity) {
        if (node.child != null) {
          traverse(node.child);
        }
      }
    }

    traverse(root);
    return results;
  }
}
