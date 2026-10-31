import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'afip_fiscal_pdf_service.dart';
import 'currency_formatter.dart';

/// Servicio de generación de Comprobantes de Venta No Fiscales (Letra X)
/// y documentos combinados Venta + Orden de Retiro / Remito (A4 y Letter),
/// con diseño técnico reglamentario estilo ARCA / Facturación Comercial Argentina.
class A4SplitPdfService {
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  static String formatCurrency(double amount) {
    final fmt = NumberFormat.currency(
      locale: 'es_AR',
      symbol: '',
      decimalDigits: 2,
    );
    return '\$ ${fmt.format(amount).trim()}';
  }

  static DateTime _resolveSaleDate(Map<String, dynamic> sale) {
    final raw = sale['created_at']?.toString() ?? sale['issued_at']?.toString();
    if (raw != null && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }

  /// Formatea un CUIT/CUIL de 11 dígitos con guiones (XX-XXXXXXXX-X)
  static String _formatCuit(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 10)}-${digits.substring(10)}';
    }
    return raw.trim();
  }

  /// Convierte valores enum de condición frente al IVA a etiquetas legibles estilo ARCA
  static String _formatTaxCondition(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Consumidor Final';
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

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim() ?? '';
      if (s.isNotEmpty && s.toLowerCase() != 'null') {
        return s;
      }
    }
    return null;
  }

  /// Genera un documento A4/Letter donde la mitad superior es el Comprobante de Venta
  /// y la mitad inferior es la Orden de Retiro / Remito (si <= 5 ítems),
  /// o páginas completas MultiPage si supera los 5 ítems.
  static Future<Uint8List> generateA4SplitReceiptAndDispatch({
    required Map<String, dynamic> sale,
    required Map<String, dynamic> deliveryNote,
    required String businessName,
    String? businessAddress,
    String phone = '',
    String cuit = '',
    String? taxCondition,
    String? iibb,
    String? activityStartDate,
    String? vendorName,
    String paperSize = 'a4',
    dynamic businessSettings,
    Uint8List? logoBytes,
  }) async {
    final resolvedLogo = await AfipFiscalPdfService.resolveLogoBytes(
      logoBytes: logoBytes,
      businessSettings: businessSettings,
    );
    pw.ThemeData? theme;
    try {
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: font, bold: fontBold);
    } catch (_) {
      // Fallback a fuentes estándar PDF en modo offline
    }

    final pdf = pw.Document(theme: theme);
    final items = sale['items'] as List<dynamic>? ?? [];
    final bool isSmallOrder = items.length <= 5;
    final bool isDispatch =
        sale['requires_dispatch'] == 1 || sale['requires_dispatch'] == true;
    final format = paperSize.toLowerCase() == 'letter'
        ? PdfPageFormat.letter
        : PdfPageFormat.a4;

    if (isSmallOrder) {
      pdf.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(22),
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // MITAD SUPERIOR: COMPROBANTE DE VENTA
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: _buildSaleReceiptList(
                          sale,
                          businessName,
                          businessAddress,
                          phone,
                          cuit,
                          vendorName,
                          taxCondition: taxCondition,
                          iibb: iibb,
                          activityStartDate: activityStartDate,
                          logoBytes: resolvedLogo,
                          isCompact: true,
                        ),
                      ),
                      _buildFooter(
                        businessName,
                        isCompact: true,
                        isSale: true,
                        isFiscal: sale['electronic_invoice'] != null,
                      ),
                    ],
                  ),
                ),

                // LÍNEA DE CORTE CENTRAL
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
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

                // MITAD INFERIOR: ORDEN DE RETIRO / REMITO
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: _buildDeliveryNoteList(
                          deliveryNote,
                          sale,
                          businessName,
                          businessAddress,
                          vendorName,
                          phone: phone,
                          cuit: cuit,
                          logoBytes: resolvedLogo,
                          isCompact: true,
                          isDispatch: isDispatch,
                        ),
                      ),
                      _buildFooter(
                        businessName,
                        isCompact: true,
                        isSale: false,
                        isFiscal: false,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    } else {
      // RUTA MULTIPAGE: PÁGINAS COMPLETAS
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(24),
          ),
          footer: (pw.Context ctx) => _buildFooter(
            businessName,
            isCompact: false,
            isSale: true,
            isFiscal: sale['electronic_invoice'] != null,
            ctx: ctx,
          ),
          build: (ctx) => _buildSaleReceiptList(
            sale,
            businessName,
            businessAddress,
            phone,
            cuit,
            vendorName,
            taxCondition: taxCondition,
            iibb: iibb,
            activityStartDate: activityStartDate,
            logoBytes: resolvedLogo,
            isCompact: false,
          ),
        ),
      );

      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(24),
          ),
          footer: (pw.Context ctx) => _buildFooter(
            businessName,
            isCompact: false,
            isSale: false,
            isFiscal: false,
            ctx: ctx,
          ),
          build: (ctx) => _buildDeliveryNoteList(
            deliveryNote,
            sale,
            businessName,
            businessAddress,
            vendorName,
            phone: phone,
            cuit: cuit,
            logoBytes: resolvedLogo,
            isCompact: false,
            isDispatch: isDispatch,
          ),
        ),
      );
    }

    return pdf.save();
  }

  /// Genera un documento A4/Letter para el Comprobante de Venta No Fiscal (o copia interna)
  /// utilizando MultiPage para soportar cualquier cantidad de artículos sin desborde.
  static Future<Uint8List> generateA4SingleReceipt({
    required Map<String, dynamic> sale,
    required String businessName,
    String? businessAddress,
    String phone = '',
    String cuit = '',
    String? taxCondition,
    String? iibb,
    String? activityStartDate,
    String? vendorName,
    String paperSize = 'a4',
    dynamic businessSettings,
    Uint8List? logoBytes,
  }) async {
    final resolvedLogo = await AfipFiscalPdfService.resolveLogoBytes(
      logoBytes: logoBytes,
      businessSettings: businessSettings,
    );
    pw.ThemeData? theme;
    try {
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: font, bold: fontBold);
    } catch (_) {}

    final pdf = pw.Document(theme: theme);
    final format = paperSize.toLowerCase() == 'letter'
        ? PdfPageFormat.letter
        : PdfPageFormat.a4;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(24),
        ),
        footer: (pw.Context ctx) => _buildFooter(
          businessName,
          isCompact: false,
          isSale: true,
          isFiscal: sale['electronic_invoice'] != null,
          ctx: ctx,
        ),
        build: (pw.Context context) => _buildSaleReceiptList(
          sale,
          businessName,
          businessAddress,
          phone,
          cuit,
          vendorName,
          taxCondition: taxCondition,
          iibb: iibb,
          activityStartDate: activityStartDate,
          logoBytes: resolvedLogo,
          isCompact: false,
        ),
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // SECCIÓN 1: COMPROBANTE DE VENTA ESTILO ARCA (X - NO VÁLIDO COMO FACTURA)
  // ---------------------------------------------------------------------------
  static List<pw.Widget> _buildSaleReceiptList(
    Map<String, dynamic> sale,
    String businessName,
    String? businessAddress,
    String phone,
    String cuit,
    String? vendorName, {
    String? taxCondition,
    String? iibb,
    String? activityStartDate,
    Uint8List? logoBytes,
    bool isCompact = false,
  }) {
    final items = sale['items'] as List<dynamic>? ?? [];
    final totalStr = sale['total'] ?? sale['total_amount']?.toString() ?? '0';
    final total = double.tryParse(totalStr.toString()) ?? 0.0;
    final shippingCost =
        double.tryParse(sale['shipping_cost']?.toString() ?? '0') ?? 0.0;
    final surchargeAmount =
        double.tryParse(sale['surcharge_amount']?.toString() ?? '0') ?? 0.0;
    final iibbPerceptionAmount =
        double.tryParse(sale['iibb_perception_amount']?.toString() ?? '0') ??
            0.0;

    final grandTotal = total + surchargeAmount;
    final saleDate = _resolveSaleDate(sale);

    final double explicitSavings = double.tryParse(
            sale['discount_amount']?.toString() ??
            sale['savings']?.toString() ??
            '') ??
        0.0;
    final double calculatedSavings = items.fold<double>(0.0, (sum, it) {
      final s = double.tryParse(it['discount_amount']?.toString() ??
              it['discount_savings']?.toString() ??
              '') ??
          0.0;
      if (s > 0) return sum + s;
      final reg = double.tryParse(it['regular_price']?.toString() ??
              it['product']?['selling_price']?.toString() ??
              '') ??
          0.0;
      final unit =
          double.tryParse(it['unit_price']?.toString() ?? '') ?? 0.0;
      final q =
          double.tryParse(it['quantity']?.toString() ?? '1') ?? 1.0;
      return sum + ((reg > unit + 0.01) ? (reg - unit) * q : 0.0);
    });
    final double totalSavings =
        explicitSavings > 0.01 ? explicitSavings : calculatedSavings;
    final hasSavings = totalSavings > 0.01;

    // Pagos
    final payments = sale['payments'] as List<dynamic>? ?? [];
    final tendered =
        double.tryParse(sale['tendered_amount']?.toString() ?? '0') ??
            grandTotal;
    final change =
        double.tryParse(sale['change_amount']?.toString() ?? '0') ?? 0.0;

    final invoice = sale['electronic_invoice'] as Map<String, dynamic>?;
    final isFiscal = invoice != null;
    final voucherLetter = isFiscal
        ? (invoice['voucher_letter']?.toString().toUpperCase() ?? 'B')
        : 'X';
    final voucherCode = isFiscal
        ? (invoice['voucher_type'] ??
            (voucherLetter == 'A' ? 1 : (voucherLetter == 'C' ? 11 : 6)))
        : 0;
    final voucherCodeInt = int.tryParse(voucherCode.toString()) ?? 0;

    String voucherTitle = isFiscal ? 'FACTURA' : 'COMPROBANTE DE VENTA';
    if (isFiscal) {
      if (<int>[3, 8, 13].contains(voucherCodeInt)) {
        voucherTitle = 'NOTA DE CRÉDITO';
      } else if (<int>[2, 7, 12].contains(voucherCodeInt)) {
        voucherTitle = 'NOTA DE DÉBITO';
      }
    }

    final rawSaleId = sale['id']?.toString() ?? '0';
    final formattedNumber = isFiscal
        ? (invoice['formatted_number']?.toString() ??
            invoice['voucher_number']?.toString().padLeft(8, '0') ??
            '00001-${rawSaleId.padLeft(8, '0')}')
        : '00001-${rawSaleId.padLeft(8, '0')}';

    final customerMap = sale['customer'] as Map<String, dynamic>?;
    final rawDocNumber = _firstNonEmpty([
      if (isFiscal) invoice['doc_number'],
      customerMap?['document_number'],
      customerMap?['tax_id'],
    ]);
    final docNumber =
        rawDocNumber != null ? _formatCuit(rawDocNumber) : '---';

    final rawReceiverTaxCond = _firstNonEmpty([
      if (isFiscal) invoice['receiver_tax_condition'],
      customerMap?['tax_condition'],
    ]);
    final receiverTaxCond = _formatTaxCondition(rawReceiverTaxCond);

    final receiverName = _firstNonEmpty([
          if (isFiscal) invoice['receiver_name'],
          customerMap?['name'],
          sale['customer_name'],
        ]) ??
        'Consumidor Final';

    final receiverAddress = _firstNonEmpty([
          if (isFiscal) invoice['receiver_address'],
          customerMap?['fiscal_address'],
          customerMap?['delivery_address'],
          customerMap?['address'],
          sale['delivery_address'],
        ]) ??
        '---';

    final formattedEmitterCuit = _formatCuit(cuit);
    final formattedEmitterIibb = _formatCuit(iibb);
    final formattedEmitterTaxCond = (taxCondition != null &&
            taxCondition.trim().isNotEmpty)
        ? _formatTaxCondition(taxCondition)
        : null;

    final paymentMethodsText = payments.isNotEmpty
        ? payments
            .map((p) =>
                (p['payment_method']?['name'] ?? p['name'] ?? 'Contado')
                    .toString()
                    .toUpperCase())
            .toSet()
            .join(' / ')
        : 'CONTADO';

    final cashierLabel = (sale['cashier']?['name'] ??
            sale['cashier_name'] ??
            vendorName ??
            sale['user']?['name'] ??
            'CAJA')
        .toString()
        .toUpperCase();

    return [
      // BARRA SUPERIOR ORIGINAL / COPIA
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
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
                fontSize: isCompact ? 8 : 9,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            pw.Text(
              isFiscal
                  ? 'COMPROBANTE ELECTRÓNICO'
                  : 'DOCUMENTO NO VÁLIDO COMO FACTURA',
              style: pw.TextStyle(
                fontSize: isCompact ? 7.5 : 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
          ],
        ),
      ),

      // ENCABEZADO PARTIDO ESTILO ARCA CON RECUADRO CENTRAL DE LETRA (X / A / B / C)
      pw.Stack(
        alignment: pw.Alignment.topCenter,
        children: [
          pw.Table(
            border: const pw.TableBorder(
              left: pw.BorderSide(color: PdfColors.black, width: 1.0),
              right: pw.BorderSide(color: PdfColors.black, width: 1.0),
              bottom: pw.BorderSide(color: PdfColors.black, width: 1.0),
              verticalInside: pw.BorderSide(color: PdfColors.black, width: 1.0),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                children: [
                  // COLUMNA IZQUIERDA: EMISOR
                  pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(
                      isCompact ? 6 : 8,
                      isCompact ? 6 : 8,
                      26,
                      isCompact ? 6 : 8,
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (logoBytes != null) ...[
                          pw.Container(
                            width: isCompact ? 36 : 46,
                            height: isCompact ? 36 : 46,
                            child: pw.Image(
                              pw.MemoryImage(logoBytes),
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
                                  fontSize: isCompact ? 13 : 15,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black,
                                ),
                              ),
                              pw.SizedBox(height: isCompact ? 3 : 5),
                              pw.Text(
                                'Razón Social: $businessName',
                                style:
                                    pw.TextStyle(fontSize: isCompact ? 7 : 7.5),
                              ),
                              if (businessAddress != null &&
                                  businessAddress.trim().isNotEmpty)
                                pw.Text(
                                  'Domicilio Comercial: $businessAddress',
                                  style: pw.TextStyle(
                                      fontSize: isCompact ? 7 : 7.5),
                                ),
                              if (phone.trim().isNotEmpty)
                                pw.Text(
                                  'Teléfono: $phone',
                                  style: pw.TextStyle(
                                      fontSize: isCompact ? 7 : 7.5),
                                ),
                              if (formattedEmitterTaxCond != null)
                                pw.Text(
                                  'Cond. frente al IVA: $formattedEmitterTaxCond',
                                  style: pw.TextStyle(
                                    fontSize: isCompact ? 7 : 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // COLUMNA DERECHA: DATOS DEL COMPROBANTE
                  pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(
                      26,
                      isCompact ? 6 : 8,
                      isCompact ? 6 : 8,
                      isCompact ? 6 : 8,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          isFiscal
                              ? '$voucherTitle $voucherLetter'
                              : voucherTitle,
                          style: pw.TextStyle(
                            fontSize: isCompact ? 11.5 : 13.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Comp. Nro: $formattedNumber',
                          style: pw.TextStyle(
                            fontSize: isCompact ? 8 : 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Fecha de Emisión: ${_dateFmt.format(saleDate)}',
                          style: pw.TextStyle(fontSize: isCompact ? 7.5 : 8),
                        ),
                        if (formattedEmitterCuit.isNotEmpty)
                          pw.Text(
                            'CUIT: $formattedEmitterCuit',
                            style: pw.TextStyle(
                              fontSize: isCompact ? 7.5 : 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (formattedEmitterIibb.isNotEmpty)
                          pw.Text(
                            'Ingresos Brutos: $formattedEmitterIibb',
                            style: pw.TextStyle(fontSize: isCompact ? 7 : 7.5),
                          ),
                        if (activityStartDate != null &&
                            activityStartDate.trim().isNotEmpty)
                          pw.Text(
                            'Inicio de Actividades: $activityStartDate',
                            style: pw.TextStyle(fontSize: isCompact ? 7 : 7.5),
                          ),
                        pw.Text(
                          'Cajero / Vendedor: $cashierLabel',
                          style: pw.TextStyle(fontSize: isCompact ? 7 : 7.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // RECUADRO CENTRAL DE LETRA (X o A/B/C)
          pw.Positioned(
            top: 0,
            child: pw.Container(
              width: isCompact ? 36 : 42,
              height: isCompact ? 36 : 42,
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: PdfColors.black, width: 1.5),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    voucherLetter,
                    style: pw.TextStyle(
                      fontSize: isCompact ? 16 : 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.Text(
                    isFiscal
                        ? 'COD. ${voucherCode.toString().padLeft(3, '0')}'
                        : 'NO FISCAL',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 4.8 : 5.5,
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

      pw.SizedBox(height: isCompact ? 4 : 6),

      // CASILLERO DE RECEPTOR / CLIENTE
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
        ),
        padding: pw.EdgeInsets.symmetric(
          horizontal: 8,
          vertical: isCompact ? 4 : 6,
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
                      fontSize: isCompact ? 7.5 : 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'CUIT / DNI: ${docNumber.isNotEmpty ? docNumber : "---"}   |   Cond. IVA: $receiverTaxCond',
                    style: pw.TextStyle(fontSize: isCompact ? 7 : 8),
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
                    'Domicilio: ${receiverAddress.isNotEmpty ? receiverAddress : "---"}',
                    style: pw.TextStyle(fontSize: isCompact ? 7 : 8),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Condición de Venta: $paymentMethodsText',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7 : 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      pw.SizedBox(height: isCompact ? 4 : 6),

      // TABLA TÉCNICA DE ARTÍCULOS
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.3),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(5.1),
          3: const pw.FlexColumnWidth(2.0),
          4: const pw.FlexColumnWidth(2.0),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            repeat: true,
            children: [
              _th('CÓDIGO', align: pw.TextAlign.center, isCompact: isCompact),
              _th('CANT.', align: pw.TextAlign.center, isCompact: isCompact),
              _th('DESCRIPCIÓN', align: pw.TextAlign.left, isCompact: isCompact),
              _th('PRECIO UNIT.', align: pw.TextAlign.right, isCompact: isCompact),
              _th('SUBTOTAL', align: pw.TextAlign.right, isCompact: isCompact),
            ],
          ),
          ...items.map((item) {
            final subtotalStr = item['subtotal']?.toString() ?? '0';
            final subtotal = double.tryParse(subtotalStr) ?? 0.0;
            final qtyStr = item['quantity']?.toString() ?? '1';
            final qty = double.tryParse(qtyStr) ?? 1.0;
            final unitPrice = double.tryParse(
                    item['unit_price']?.toString() ?? '') ??
                (qty > 0 ? subtotal / qty : 0.0);

            final isWeight =
                item['product']?['is_sold_by_weight'] == true ||
                    item['product']?['is_sold_by_weight'] == 1 ||
                    item['is_sold_by_weight'] == true;
            final qtyText = isWeight ? qty.toQty() : qty.toInt().toString();

            final pName = (item['product_name'] ??
                    item['product']?['name'] ??
                    'Producto')
                .toString();
            final pCode = (item['product']?['internal_code'] ??
                    item['internal_code'] ??
                    '-')
                .toString();

            final discountSavings = double.tryParse(
                    item['discount_amount']?.toString() ??
                        item['discount_savings']?.toString() ??
                        '') ??
                0.0;
            final regularPrice = double.tryParse(
                    item['regular_price']?.toString() ??
                        item['product']?['selling_price']?.toString() ??
                        '') ??
                0.0;
            final discountLabel = (item['discount_label'] ??
                    item['offer_label'] ??
                    '')
                .toString()
                .trim();
            final hasItemDiscount =
                discountSavings > 0.01 || (regularPrice > unitPrice + 0.01);
            final effectiveSavings = discountSavings > 0.01
                ? discountSavings
                : ((regularPrice > unitPrice)
                    ? (regularPrice - unitPrice) * qty
                    : 0.0);
            final effectiveRegPrice = regularPrice > 0.01
                ? regularPrice
                : (unitPrice + (effectiveSavings / (qty > 0 ? qty : 1.0)));

            return pw.TableRow(
              children: [
                _td(
                  pCode.trim().isEmpty ? '-' : pCode,
                  align: pw.TextAlign.center,
                  isCompact: isCompact,
                ),
                _td(qtyText, align: pw.TextAlign.center, isCompact: isCompact),
                pw.Padding(
                  padding: pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: isCompact ? 3 : 4.5,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        pName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: isCompact ? 7.5 : 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      if (hasItemDiscount) ...[
                        pw.SizedBox(height: 1),
                        pw.Text(
                          '(${discountLabel.isNotEmpty ? discountLabel : "En oferta"} - Precio lista: ${formatCurrency(effectiveRegPrice)} - Ahorro: -${formatCurrency(effectiveSavings)})',
                          style: pw.TextStyle(
                            fontSize: isCompact ? 5.8 : 6.8,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _td(
                  formatCurrency(unitPrice),
                  align: pw.TextAlign.right,
                  isCompact: isCompact,
                ),
                _td(
                  formatCurrency(subtotal),
                  align: pw.TextAlign.right,
                  bold: true,
                  isCompact: isCompact,
                ),
              ],
            );
          }),
        ],
      ),

      pw.SizedBox(height: isCompact ? 5 : 8),

      // BLOQUE DE PAGOS Y TOTALES REGLAMENTARIO
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
        ),
        padding: pw.EdgeInsets.all(isCompact ? 6 : 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // DETALLE DE PAGOS (IZQUIERDA)
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'DETALLE DE PAGO',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7.5 : 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  if (payments.isNotEmpty)
                    ...payments.map((p) {
                      final mName = (p['payment_method']?['name'] ??
                              p['name'] ??
                              'PAGO')
                          .toString()
                          .toUpperCase();
                      final mAmount =
                          double.tryParse(p['amount']?.toString() ?? '0') ??
                              grandTotal;
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 1.5),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              '- $mName:',
                              style: pw.TextStyle(fontSize: isCompact ? 7 : 8),
                            ),
                            pw.Text(
                              formatCurrency(mAmount),
                              style: pw.TextStyle(
                                fontSize: isCompact ? 7 : 8,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    })
                  else
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '- EFECTIVO:',
                          style: pw.TextStyle(fontSize: isCompact ? 7 : 8),
                        ),
                        pw.Text(
                          formatCurrency(grandTotal),
                          style: pw.TextStyle(
                            fontSize: isCompact ? 7 : 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  if (tendered > 0.01 &&
                      (payments.length <= 1 || change > 0.01)) ...[
                    pw.SizedBox(height: 3),
                    pw.Divider(color: PdfColors.grey400, thickness: 0.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Abonó con:',
                          style: pw.TextStyle(fontSize: isCompact ? 7 : 7.5),
                        ),
                        pw.Text(
                          formatCurrency(tendered),
                          style: pw.TextStyle(fontSize: isCompact ? 7 : 7.5),
                        ),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Su vuelto:',
                          style: pw.TextStyle(fontSize: isCompact ? 7 : 7.5),
                        ),
                        pw.Text(
                          formatCurrency(change),
                          style: pw.TextStyle(
                            fontSize: isCompact ? 7 : 7.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (hasSavings) ...[
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2.5,
                      ),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      child: pw.Text(
                        '¡Ahorro total en esta compra: ${formatCurrency(totalSavings)}!',
                        style: pw.TextStyle(
                          fontSize: isCompact ? 7 : 7.8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            pw.SizedBox(width: 16),

            // SUBTOTALES E IMPORTE TOTAL (DERECHA)
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (isFiscal &&
                      voucherLetter != 'C' &&
                      invoice['net_amount'] != null) ...[
                    _summaryRow(
                      'Importe Neto Gravado:',
                      formatCurrency(
                          double.tryParse(invoice['net_amount'].toString()) ??
                              0.0),
                      isCompact: isCompact,
                    ),
                    _summaryRow(
                      'IVA Contenido / Liquidado:',
                      formatCurrency(double.tryParse(
                              invoice['iva_amount']?.toString() ?? '0') ??
                          0.0),
                      isCompact: isCompact,
                    ),
                  ],
                  if (hasSavings) ...[
                    _summaryRow(
                      'Subtotal Precio Lista:',
                      formatCurrency(total -
                          shippingCost -
                          iibbPerceptionAmount +
                          totalSavings),
                      isCompact: isCompact,
                    ),
                    _summaryRow(
                      'Bonificaciones / Ahorro:',
                      '- ${formatCurrency(totalSavings)}',
                      isCompact: isCompact,
                    ),
                  ],
                  if (hasSavings ||
                      shippingCost > 0 ||
                      iibbPerceptionAmount > 0 ||
                      surchargeAmount > 0)
                    _summaryRow(
                      'Subtotal Artículos:',
                      formatCurrency(
                          total - shippingCost - iibbPerceptionAmount),
                      isCompact: isCompact,
                    ),
                  if (iibbPerceptionAmount > 0)
                    _summaryRow(
                      'Percepción IIBB:',
                      formatCurrency(iibbPerceptionAmount),
                      isCompact: isCompact,
                    ),
                  if (shippingCost > 0)
                    _summaryRow(
                      'Costo de Envío / Flete:',
                      formatCurrency(shippingCost),
                      isCompact: isCompact,
                    ),
                  if (surchargeAmount > 0)
                    _summaryRow(
                      'Recargo Financiero:',
                      formatCurrency(surchargeAmount),
                      isCompact: isCompact,
                    ),
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 4),
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 6,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                      border: pw.Border(
                        top: pw.BorderSide(color: PdfColors.black, width: 1.0),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'IMPORTE TOTAL:',
                          style: pw.TextStyle(
                            fontSize: isCompact ? 9.5 : 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          formatCurrency(grandTotal),
                          style: pw.TextStyle(
                            fontSize: isCompact ? 10 : 12,
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

      if (isFiscal) ...[
        pw.SizedBox(height: isCompact ? 4 : 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 0.8),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (invoice['qr_data'] != null &&
                  invoice['qr_data'].toString().isNotEmpty)
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: invoice['qr_data'].toString(),
                  width: isCompact ? 42 : 58,
                  height: isCompact ? 42 : 58,
                ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CAE N°: ${invoice['cae'] ?? '---'}',
                      style: pw.TextStyle(
                        fontSize: isCompact ? 8 : 9.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Fecha de Vto. de CAE: ${invoice['cae_expiration']?.toString().split('T').first ?? '---'}',
                      style: pw.TextStyle(fontSize: isCompact ? 7 : 8.5),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Comprobante Autorizado por ARCA / AFIP (RG 4892)',
                      style: pw.TextStyle(
                        fontSize: isCompact ? 6.5 : 7.5,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  // ---------------------------------------------------------------------------
  // SECCIÓN 2: REMITO / ORDEN DE RETIRO ESTILO ARCA (R / X)
  // ---------------------------------------------------------------------------
  static List<pw.Widget> _buildDeliveryNoteList(
    Map<String, dynamic> note,
    Map<String, dynamic> sale,
    String businessName,
    String? businessAddress,
    String? vendorName, {
    String phone = '',
    String cuit = '',
    Uint8List? logoBytes,
    required bool isCompact,
    required bool isDispatch,
  }) {
    final items = note['items'] as List<dynamic>? ?? [];
    final customerMap = sale['customer'] as Map<String, dynamic>?;
    final customerName = _firstNonEmpty([
          customerMap?['name'],
          sale['customer_name'],
        ]) ??
        'Consumidor Final';
    final rawCustomerDoc = _firstNonEmpty([
      customerMap?['document_number'],
      customerMap?['tax_id'],
    ]);
    final customerDoc =
        rawCustomerDoc != null ? _formatCuit(rawCustomerDoc) : '---';
    final noteId = note['id']?.toString().padLeft(6, '0') ?? '000000';
    final saleId = sale['id']?.toString().padLeft(8, '0') ?? '00000000';
    final saleDate = _resolveSaleDate(sale);

    int totalUnits = 0;
    for (final item in items) {
      final qtyStr = item['quantity_purchased']?.toString() ??
          item['quantity']?.toString() ??
          '1';
      final qty = double.tryParse(qtyStr) ?? 1.0;
      final isWeight = item['product']?['is_sold_by_weight'] == true ||
          item['is_sold_by_weight'] == true;
      if (!isWeight) totalUnits += qty.toInt();
    }

    final documentTitle =
        isDispatch ? 'REMITO DE DESPACHO' : 'ORDEN DE RETIRO';
    final boxLetter = isDispatch ? 'R' : 'X';
    final boxCode = isDispatch ? 'COD. 091' : 'INTERNO';
    final barcodeValue = isDispatch ? 'REM$noteId' : 'ORD$noteId';
    final deliveryAddress = _firstNonEmpty([
          sale['delivery_address'],
          customerMap?['delivery_address'],
          customerMap?['fiscal_address'],
          customerMap?['address'],
        ]) ??
        '';
    final formattedCuit = _formatCuit(cuit);

    return [
      // BARRA SUPERIOR
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'ORIGINAL - LOGÍSTICA / DEPÓSITO',
              style: pw.TextStyle(
                fontSize: isCompact ? 8 : 9,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            pw.Text(
              'DOCUMENTO NO VÁLIDO COMO FACTURA',
              style: pw.TextStyle(
                fontSize: isCompact ? 7.5 : 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
          ],
        ),
      ),

      // ENCABEZADO PARTIDO ESTILO ARCA CON RECUADRO R / X Y CÓDIGO DE BARRAS
      pw.Stack(
        alignment: pw.Alignment.topCenter,
        children: [
          pw.Table(
            border: const pw.TableBorder(
              left: pw.BorderSide(color: PdfColors.black, width: 1.0),
              right: pw.BorderSide(color: PdfColors.black, width: 1.0),
              bottom: pw.BorderSide(color: PdfColors.black, width: 1.0),
              verticalInside: pw.BorderSide(color: PdfColors.black, width: 1.0),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                children: [
                  // EMISOR (IZQUIERDA)
                  pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(
                      isCompact ? 6 : 8,
                      isCompact ? 6 : 8,
                      26,
                      isCompact ? 6 : 8,
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (logoBytes != null) ...[
                          pw.Container(
                            width: isCompact ? 36 : 46,
                            height: isCompact ? 36 : 46,
                            child: pw.Image(
                              pw.MemoryImage(logoBytes),
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
                                  fontSize: isCompact ? 13 : 15,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              if (businessAddress != null &&
                                  businessAddress.isNotEmpty)
                                pw.Text(
                                  'Domicilio: $businessAddress',
                                  style: pw.TextStyle(
                                      fontSize: isCompact ? 7 : 7.5),
                                ),
                              if (phone.isNotEmpty)
                                pw.Text(
                                  'Teléfono: $phone',
                                  style: pw.TextStyle(
                                      fontSize: isCompact ? 7 : 7.5),
                                ),
                              if (formattedCuit.isNotEmpty)
                                pw.Text(
                                  'CUIT: $formattedCuit',
                                  style: pw.TextStyle(
                                    fontSize: isCompact ? 7 : 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              pw.SizedBox(height: 3),
                              pw.BarcodeWidget(
                                barcode: pw.Barcode.code128(),
                                data: barcodeValue,
                                width: isCompact ? 105 : 125,
                                height: isCompact ? 20 : 24,
                                drawText: false,
                              ),
                              pw.Text(
                                barcodeValue,
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
                  ),

                  // DATOS DEL REMITO (DERECHA)
                  pw.Padding(
                    padding: pw.EdgeInsets.fromLTRB(
                      26,
                      isCompact ? 6 : 8,
                      isCompact ? 6 : 8,
                      isCompact ? 6 : 8,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          documentTitle,
                          style: pw.TextStyle(
                            fontSize: isCompact ? 11.5 : 13.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Remito Nro: 00001-$noteId',
                          style: pw.TextStyle(
                            fontSize: isCompact ? 8 : 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Venta Asociada: #$saleId',
                          style: pw.TextStyle(fontSize: isCompact ? 7.5 : 8),
                        ),
                        pw.Text(
                          'Fecha de Emisión: ${_dateFmt.format(saleDate)}',
                          style: pw.TextStyle(fontSize: isCompact ? 7.5 : 8),
                        ),
                        pw.Text(
                          'Vendedor: ${(vendorName ?? "SISTEMA").toUpperCase()}',
                          style: pw.TextStyle(fontSize: isCompact ? 7.5 : 8),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // RECUADRO CENTRAL LETRA R / X
          pw.Positioned(
            top: 0,
            child: pw.Container(
              width: isCompact ? 36 : 42,
              height: isCompact ? 36 : 42,
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: PdfColors.black, width: 1.5),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    boxLetter,
                    style: pw.TextStyle(
                      fontSize: isCompact ? 16 : 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    boxCode,
                    style: pw.TextStyle(
                      fontSize: isCompact ? 4.8 : 5.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      pw.SizedBox(height: isCompact ? 4 : 6),

      // CASILLERO DESTINATARIO Y ENTREGA
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
        ),
        padding: pw.EdgeInsets.symmetric(
          horizontal: 8,
          vertical: isCompact ? 4 : 6,
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: 6,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Destinatario / Cliente: ${customerName.toUpperCase()}   (Doc: $customerDoc)',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7.5 : 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (deliveryAddress.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Domicilio de Entrega: $deliveryAddress',
                      style: pw.TextStyle(
                        fontSize: isCompact ? 7.5 : 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                border: pw.Border.all(color: PdfColors.black, width: 0.8),
              ),
              child: pw.Text(
                isDispatch ? 'DESPACHO' : 'A RETIRAR',
                style: pw.TextStyle(
                  fontSize: isCompact ? 7 : 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),

      pw.SizedBox(height: isCompact ? 4 : 6),

      // TABLA DE ARTÍCULOS DEL REMITO
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(6.5),
          2: const pw.FlexColumnWidth(2.0),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            repeat: true,
            children: [
              _th('CÓDIGO', align: pw.TextAlign.center, isCompact: isCompact),
              _th(
                'DESCRIPCIÓN DEL ARTÍCULO',
                align: pw.TextAlign.left,
                isCompact: isCompact,
              ),
              _th('CANTIDAD', align: pw.TextAlign.center, isCompact: isCompact),
            ],
          ),
          ...items.map((item) {
            final qtyStr = item['quantity_purchased']?.toString() ??
                item['quantity']?.toString() ??
                '1';
            final qty = double.tryParse(qtyStr) ?? 1.0;
            final isWeight =
                item['product']?['is_sold_by_weight'] == true ||
                    item['is_sold_by_weight'] == true;
            final qtyText =
                isWeight ? '${qty.toQty()} kg' : '${qty.toInt()} un';
            final pName = (item['product']?['name'] ??
                    item['product_name'] ??
                    'Producto')
                .toString();
            final pCode = (item['product']?['internal_code'] ??
                    item['internal_code'] ??
                    '-')
                .toString();

            return pw.TableRow(
              children: [
                _td(
                  pCode.trim().isEmpty ? '-' : pCode,
                  align: pw.TextAlign.center,
                  isCompact: isCompact,
                ),
                _td(
                  pName.toUpperCase(),
                  align: pw.TextAlign.left,
                  bold: true,
                  isCompact: isCompact,
                ),
                _td(
                  qtyText,
                  align: pw.TextAlign.center,
                  bold: true,
                  isCompact: isCompact,
                ),
              ],
            );
          }),
        ],
      ),

      pw.SizedBox(height: isCompact ? 5 : 10),

      // PIE DE INSTRUCCIONES Y CONFORMIDAD DE ENTREGA
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.8),
              ),
              padding: pw.EdgeInsets.all(isCompact ? 6 : 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    isDispatch
                        ? 'INSTRUCCIONES DE RECEPCIÓN'
                        : 'INSTRUCCIONES DE RETIRO EN DEPÓSITO',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7 : 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    isDispatch
                        ? 'Verifique que los artículos recibidos coincidan con las cantidades detalladas en este remito antes de firmar la conformidad.'
                        : 'Presente este comprobante en depósito para retirar su mercadería. El operador escaneará el código de barras superior.',
                    style: pw.TextStyle(fontSize: isCompact ? 6.5 : 7.5),
                  ),
                  if (totalUnits > 0) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Total de unidades / bultos: $totalUnits',
                      style: pw.TextStyle(
                        fontSize: isCompact ? 7.5 : 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.8),
              ),
              padding: pw.EdgeInsets.all(isCompact ? 6 : 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RECIBÍ CONFORME (FIRMA Y ACLARACIÓN)',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7 : 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: isCompact ? 14 : 22),
                  pw.Divider(color: PdfColors.black, thickness: 0.5),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'DNI / CUIT: ___________________',
                        style: pw.TextStyle(fontSize: isCompact ? 6.5 : 7.5),
                      ),
                      pw.Text(
                        'Fecha: ____/____/______',
                        style: pw.TextStyle(fontSize: isCompact ? 6.5 : 7.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  static pw.Widget _th(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool isCompact = false,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: 5,
        vertical: isCompact ? 3.5 : 5,
      ),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: isCompact ? 7 : 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _td(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    bool isCompact = false,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: 5,
        vertical: isCompact ? 3 : 4.5,
      ),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: isCompact ? 7.5 : 8.5,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _summaryRow(
    String label,
    String value, {
    bool isCompact = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: isCompact ? 7.5 : 8.5)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: isCompact ? 7.5 : 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(
    String businessName, {
    required bool isCompact,
    bool isSale = false,
    bool isFiscal = false,
    pw.Context? ctx,
  }) {
    final docLegend = isFiscal
        ? 'Comprobante Fiscal Electrónico - $businessName'
        : (isSale
            ? 'COMPROBANTE DE VENTA NO VÁLIDO COMO FACTURA - $businessName'
            : 'REMITO / ORDEN DE ENTREGA NO VÁLIDO COMO FACTURA - $businessName');
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.SizedBox(height: isCompact ? 3 : 6),
        pw.Divider(color: PdfColors.grey500, thickness: 0.6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              docLegend,
              style: pw.TextStyle(
                fontSize: isCompact ? 6.5 : 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
            if (!isCompact && ctx != null)
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
