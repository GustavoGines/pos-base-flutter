import 'dart:convert';
import 'dart:typed_data';
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
    super.theme,
    super.compress,
  }) {
    addPage(page);
  }
}

/// Service that builds and generates official AFIP fiscal invoice PDFs
/// conforming to RG 1415 and RG 4892 classical layout standards (Facturas A, B, C).
class AfipFiscalPdfService {
  static final _currencyFmt =
      NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 2);
  static final _dateFmt = DateFormat('dd/MM/yyyy');

  /// Formats currency values in standard Argentinian pesos.
  static String formatCurrency(num amount) {
    return _currencyFmt.format(amount);
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

  /// Generates the raw PDF bytes for an AFIP fiscal invoice.
  static Future<Uint8List> generateFiscalInvoice({
    required Map<String, dynamic> sale,
    Map<String, dynamic>? electronicInvoice,
    dynamic businessSettings,
    String paperSize = 'a4',
    bool compress = true,
    pw.ThemeData? theme,
  }) async {
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
      businessSettings: businessSettings,
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
    dynamic businessSettings,
    String paperSize = 'a4',
    bool compress = true,
    pw.ThemeData? theme,
  }) {
    final invoice = electronicInvoice ??
        (sale['electronic_invoice'] as Map<String, dynamic>?) ??
        {};

    final widgets = buildFiscalWidgets(
      sale: sale,
      electronicInvoice: invoice,
      businessSettings: businessSettings,
      paperSize: paperSize,
    );

    final page = buildFiscalPage(
      widgets: widgets,
      paperSize: paperSize,
    );

    return AfipFiscalDocument(
      widgets: widgets,
      page: page,
      theme: theme,
      compress: compress,
    );
  }

  /// Builds the [pw.MultiPage] containing the fiscal invoice widgets.
  static pw.MultiPage buildFiscalPage({
    required List<pw.Widget> widgets,
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
    String paperSize = 'a4',
  }) {
    // ── 1. Resolução de Letra e Código de Comprobante AFIP ───────────────────
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

    // ── 2. Datos del Emisor ───────────────────────────────────────────────────
    String issuerName = 'Mi Negocio';
    String issuerCuit = '30-00000000-0';
    String issuerAddress = 'Domicilio Comercial';
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

    if (issuerIibb.isEmpty) {
      issuerIibb = 'Exento';
    }

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
    final receiverDoc = electronicInvoice['doc_number']?.toString() ??
        sale['customer']?['tax_id'] ??
        sale['customer_tax_id'] ??
        '---';
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
    final paymentCondition = 'Contado';

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

    final subtotal = double.tryParse(
            (sale['subtotal'] ?? sale['total'] ?? totalAmount).toString()) ??
        totalAmount;
    final discountsOrSurcharges = totalAmount - subtotal;

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
      voucherLetter: voucherLetter,
      voucherCodeText: voucherCodeText,
      issuerName: issuerName,
      issuerCuit: issuerCuit,
      issuerAddress: issuerAddress,
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

    final totalsWidget = _buildTotalsSection(
      isFacturaA: voucherLetter == 'A',
      netAmount: netAmount,
      ivaAmount: ivaAmount,
      exemptAmount: exemptAmount,
      subtotal: subtotal,
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
    );

    return [
      headerWidget,
      pw.SizedBox(height: 6),
      receiverWidget,
      pw.SizedBox(height: 6),
      itemsTableWidget,
      pw.SizedBox(height: 6),
      totalsWidget,
      pw.SizedBox(height: 6),
      footerWidget,
    ];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Componente 1: Cabecera Oficial AFIP RG 1415
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildAfipHeader({
    required String voucherLetter,
    required String voucherCodeText,
    required String issuerName,
    required String issuerCuit,
    required String issuerAddress,
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
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 1.0),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
          padding: const pw.EdgeInsets.all(8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Emisor (Columna Izquierda)
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 28),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        issuerName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text('Razón Social: $issuerName',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Domicilio Comercial: $issuerAddress',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Condición frente al IVA: $issuerTaxCondition',
                          style: pw.TextStyle(
                              fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      pw.Text('CUIT: $issuerCuit',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Ingresos Brutos: $issuerIibb',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Fecha de Inicio de Actividades: $issuerStartDate',
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ),

              // Línea Divisoria Vertical Central
              pw.Container(
                width: 1,
                height: 98,
                color: PdfColors.black,
              ),

              // Comprobante (Columna Derecha)
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 28),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FACTURA $voucherLetter',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Punto de Venta: $ptoVtaFormatted   Comp. Nro: $cbteNroFormatted',
                        style: pw.TextStyle(
                            fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'Comp. N°: $formattedNumber',
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
              ),
            ],
          ),
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
  static String _formatTaxCondition(String raw) {
    switch (raw.toLowerCase()) {
      case 'consumidor_final':
        return 'Consumidor Final';
      case 'responsable_inscripto':
        return 'IVA Responsable Inscripto';
      case 'monotributo':
      case 'responsable_monotributo':
        return 'Responsable Monotributo';
      case 'exento':
      case 'sujeto_exento':
      case 'iva_exento':
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
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
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
                _buildTableCell(_currencyFmt.format(netUnitPrice),
                    textAlign: pw.TextAlign.right),
                _buildTableCell('${ivaRate.toStringAsFixed(1)}%',
                    textAlign: pw.TextAlign.center),
                _buildTableCell(_currencyFmt.format(netSubtotal),
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
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
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

            return pw.TableRow(
              children: [
                _buildTableCell(qtyText, textAlign: pw.TextAlign.center),
                _buildTableCell(name.toUpperCase(), textAlign: pw.TextAlign.left),
                _buildTableCell(_currencyFmt.format(unitPrice),
                    textAlign: pw.TextAlign.right),
                _buildTableCell(_currencyFmt.format(subtotal),
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
  // Componente 4: Sección de Totales (Diferenciada Factura A vs B/C)
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildTotalsSection({
    required bool isFacturaA,
    required double netAmount,
    required double ivaAmount,
    required double exemptAmount,
    required double subtotal,
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
              otherIvas.add(pw.Text('IVA 27%: ${_currencyFmt.format(imp)}',
                  style: const pw.TextStyle(fontSize: 8)));
            } else if (id == 8) {
              otherIvas.add(pw.Text('IVA 5%: ${_currencyFmt.format(imp)}',
                  style: const pw.TextStyle(fontSize: 8)));
            } else if (id == 9) {
              otherIvas.add(pw.Text('IVA 2.5%: ${_currencyFmt.format(imp)}',
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
                    'Subtotal Neto Gravado: ${_currencyFmt.format(resolvedNetAmount)}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text('IVA 21%: ${_currencyFmt.format(iva21)}',
                       style: const pw.TextStyle(fontSize: 8)),
                  if (iva105 > 0)
                    pw.Text('IVA 10.5%: ${_currencyFmt.format(iva105)}',
                        style: const pw.TextStyle(fontSize: 8)),
                  ...otherIvas,
                  if (exemptAmount > 0)
                    pw.Text('Importe Exento: ${_currencyFmt.format(exemptAmount)}',
                        style: const pw.TextStyle(fontSize: 8)),
                  if (iibbPerceptionAmount > 0)
                    pw.Text(
                      'Percepción IIBB (${iibbPerceptionRate > 0 ? iibbPerceptionRate.toStringAsFixed(1) : "0.0"}%): ${_currencyFmt.format(iibbPerceptionAmount)}',
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
                  pw.Text(_currencyFmt.format(totalAmount),
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
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
                  pw.Text('Subtotal: ${_currencyFmt.format(subtotal)}',
                      style: const pw.TextStyle(fontSize: 8)),
                  if (discountsOrSurcharges != 0)
                    pw.Text(
                      'Descuentos / Recargos: ${_currencyFmt.format(discountsOrSurcharges)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  if (iibbPerceptionAmount > 0)
                    pw.Text(
                      'Percepción IIBB (${iibbPerceptionRate > 0 ? iibbPerceptionRate.toStringAsFixed(1) : "0.0"}%): ${_currencyFmt.format(iibbPerceptionAmount)}',
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
                  pw.Text(_currencyFmt.format(totalAmount),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Componente 5: Pie Fiscal AFIP RG 4892 (Código QR, CAE y Vencimiento)
  // ─────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildFiscalFooter({
    required String qrData,
    required String cae,
    required String caeExpiration,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Código QR Oficial RG 4892
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrData,
            width: 60,
            height: 60,
          ),
          pw.SizedBox(width: 10),
          // Leyenda Legal AFIP
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Comprobante Autorizado por AFIP (RG 4892)',
                  style: pw.TextStyle(
                      fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Esta Administración Federal no se responsabiliza por los datos ingresados en el detalle de la operación.',
                  style: const pw.TextStyle(
                      fontSize: 6.5, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          // CAE y Vencimiento
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'CAE N°: $cae',
                style: pw.TextStyle(
                    fontSize: 9.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Fecha de Vto. de CAE: $caeExpiration',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
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



