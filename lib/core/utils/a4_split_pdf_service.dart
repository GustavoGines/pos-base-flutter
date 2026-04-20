import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class A4SplitPdfService {
  static final _currencyFmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 2);
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  // Paleta de colores para igualar el remito de Logística
  static const _primary   = PdfColor.fromInt(0xFFE65100); // Naranja entrega
  static const _secondary = PdfColor.fromInt(0xFF1A4B8C); // Azul Venta
  static const _bgLight   = PdfColor.fromInt(0xFFF5F7FA);
  static const _textGrey  = PdfColor.fromInt(0xFF6B7280);

  /// Genera un documento A4 donde la mitad superior es el Comprobante de Venta 
  /// y la mitad inferior es la Orden de Retiro / Remito.
  static Future<Uint8List> generateA4SplitReceiptAndDispatch({
    required Map<String, dynamic> sale,
    required Map<String, dynamic> deliveryNote,
    required String businessName,
    String? businessAddress,
    String? vendorName,
  }) async {
    final pdf = pw.Document();

    // Extraer datos comunes
    final phone = ''; // Agregar si tienes el teléfono en settings
    final cuit = ''; // Agregar si tienes el CUIT en settings

    final items = sale['items'] as List<dynamic>? ?? [];
    final bool isSmallOrder = items.length <= 4;

    // buildWatermark pinta la marca de agua detrás de cada sección
    pw.Widget _buildWatermark(String text, bool isSmall) => pw.Center(
      child: pw.Transform.rotateBox(
        angle: 0.6,
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: isSmall ? 40 : 65,
            fontWeight: pw.FontWeight.bold,
            color: const PdfColor.fromInt(0xFFE5E5E5), // Gris muy claro sólido (sin opacidad)
          ),
        ),
      ),
    );

    pw.Widget buildWatermarkBg(pw.Context ctx) => pw.Positioned.fill(
      child: _buildWatermark('COMPROBANTE NO FISCAL', isSmallOrder),
    );

    if (isSmallOrder) {
      // ── RUTA A: VENTA CHICA (A4 SPLIT) ──
      pdf.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
          ),
          build: (pw.Context context) {
            return pw.Column(
              children: [
                // ==========================================
                // MITAD SUPERIOR: COMPROBANTE DE VENTA (ORIGINAL)
                // ==========================================
                pw.Expanded(
                  child: pw.Stack(
                    children: [
                      pw.Positioned.fill(child: _buildWatermark('COMPROBANTE NO FISCAL', true)),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Align(
                            alignment: pw.Alignment.topRight,
                            child: pw.Text('ORIGINAL', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontWeight: pw.FontWeight.bold)),
                          ),
                          ..._buildSaleReceiptList(sale, businessName, businessAddress, phone, cuit, vendorName),
                        ],
                      ),
                    ],
                  ),
                ),

                // ==========================================
                // DIVISOR VISUAL CON TIJERA
                // ==========================================
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('CORTAR AQUÍ', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Divider(
                          color: PdfColors.grey500,
                          borderStyle: pw.BorderStyle.dashed,
                          thickness: 1,
                        ),
                      ),
                    ],
                  ),
                ),

                // ==========================================
                // MITAD INFERIOR: ORDEN DE RETIRO / REMITO (DUPLICADO)
                // ==========================================
                pw.Expanded(
                  child: pw.Stack(
                    children: [
                      pw.Positioned.fill(child: _buildWatermark('COMPROBANTE NO FISCAL', true)),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Align(
                            alignment: pw.Alignment.topRight,
                            child: pw.Text('DUPLICADO', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontWeight: pw.FontWeight.bold)),
                          ),
                          ..._buildDeliveryNoteList(deliveryNote, sale, businessName, businessAddress, vendorName),
                        ],
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
      // ── RUTA B: VENTA GRANDE (MULTIPAGE) ──
      
      // Comprobante de Venta (Páginas Completas)
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            buildBackground: buildWatermarkBg,
          ),
          build: (ctx) => _buildSaleReceiptList(sale, businessName, businessAddress, phone, cuit, vendorName),
        ),
      );

      // Vale de Retiro / Remito (Páginas Completas)
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            buildBackground: buildWatermarkBg,
          ),
          build: (ctx) => _buildDeliveryNoteList(deliveryNote, sale, businessName, businessAddress, vendorName),
        ),
      );
    }

    return pdf.save();
  }

  /// Genera un documento A4 con UN SOLO comprobante de venta (útil para cuando no hay logística inmediata)
  static Future<Uint8List> generateA4SingleReceipt({
    required Map<String, dynamic> sale,
    required String businessName,
    String? businessAddress,
    String phone = '',
    String cuit = '',
    String? vendorName,
  }) async {
    final pdf = pw.Document();
    

    pdf.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
        ),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              // Marca de agua (Fondo)
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Transform.rotateBox(
                    angle: 0.6,
                    child: pw.Text(
                      'COMPROBANTE NO FISCAL',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 90,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFFE5E5E5),
                      ),
                    ),
                  ),
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Align(
                    alignment: pw.Alignment.topRight,
                    child: pw.Text('ORIGINAL', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontWeight: pw.FontWeight.bold)),
                  ),
                  ..._buildSaleReceiptList(sale, businessName, businessAddress, phone, cuit, vendorName),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // SECCIÓN 1: VENTA (CON PRECIOS Y DISEÑO DEL BACKEND)
  // ---------------------------------------------------------------------------
  static List<pw.Widget> _buildSaleReceiptList(Map<String, dynamic> sale, String businessName, String? businessAddress, String phone, String cuit, String? vendorName) {
    final items = sale['items'] as List<dynamic>? ?? [];
    final totalStr = sale['total'] ?? sale['total_amount']?.toString() ?? '0';
    final total = double.tryParse(totalStr.toString()) ?? 0.0;
    final shippingCost = double.tryParse(sale['shipping_cost']?.toString() ?? '0') ?? 0.0;
    
    // Pagos (simplificado para la demo)
    final payments = sale['payments'] as List<dynamic>? ?? [];
    double tendered = total; 
    double change = 0.0;

    return [
      // ENCABEZADO VENTA (Estilo Laravel: Izquierda/Derecha)
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(businessName.toUpperCase(), style: pw.TextStyle(color: _secondary, fontSize: 18, fontWeight: pw.FontWeight.bold)),
              if (businessAddress != null && businessAddress.isNotEmpty)
                pw.Text(businessAddress, style: const pw.TextStyle(color: PdfColors.black, fontSize: 10)),
              if (phone.isNotEmpty)
                pw.Text('Tel: $phone', style: const pw.TextStyle(color: PdfColors.black, fontSize: 9)),
              if (cuit.isNotEmpty)
                pw.Text('CUIT: $cuit', style: const pw.TextStyle(color: PdfColors.black, fontSize: 9)),
            ]
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('COMPROBANTE DE VENTA', style: pw.TextStyle(color: PdfColors.black, fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('Número: ${sale['id'].toString().padLeft(8, '0')}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('Fecha: ${_dateFmt.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Cajero: ${vendorName?.toUpperCase() ?? 'CAJA'}', style: const pw.TextStyle(fontSize: 9)),
            ]
          )
        ],
      ),
      
      pw.SizedBox(height: 5),
      pw.Divider(thickness: 2, color: PdfColors.black),
      pw.SizedBox(height: 8),

      // DATOS CLIENTE Y CAJERO
      pw.Container(
        decoration: const pw.BoxDecoration(
          color: _bgLight,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        padding: const pw.EdgeInsets.all(8),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CLIENTE', style: pw.TextStyle(fontSize: 8, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text((sale['customer']?['name'] ?? sale['customer_name'] ?? 'Consumidor Final').toUpperCase(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CAJERO', style: pw.TextStyle(fontSize: 8, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text((vendorName ?? 'SISTEMA').toUpperCase(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),

      pw.SizedBox(height: 8),

      // TABLA DE ITEMS
      pw.Table(
        border: pw.TableBorder(
          bottom: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(1),
          1: const pw.FlexColumnWidth(5),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(2),
        },
        children: [
          // Header
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _secondary),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: pw.Text('CANT.', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: pw.Text('DESCRIPCIÓN', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: pw.Text('P. UNIT.', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.right),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: pw.Text('SUBTOTAL', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.right),
              ),
            ],
          ),
          // Filas
          ...items.map((item) {
            final subtotalStr = item['subtotal']?.toString() ?? '0';
            final subtotal = double.tryParse(subtotalStr) ?? 0.0;
            final qtyStr = item['quantity']?.toString() ?? '1';
            final qty = double.tryParse(qtyStr) ?? 1.0;
            final unitPrice = qty > 0 ? subtotal / qty : 0.0;
            
            final isWeight = item['product']?['is_sold_by_weight'] ?? item['is_sold_by_weight'] ?? false;
            final qtyText = isWeight ? qty.toStringAsFixed(3) : qty.toInt().toString();

            final pName = item['product_name'] ?? item['product']?['name'] ?? 'Producto';

            return pw.TableRow(
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))
              ),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: pw.Text(qtyText, style: const pw.TextStyle(fontSize: 9, color: PdfColors.black), textAlign: pw.TextAlign.center),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: pw.Text(pName.toUpperCase(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: pw.Text(_currencyFmt.format(unitPrice), style: const pw.TextStyle(fontSize: 9, color: PdfColors.black), textAlign: pw.TextAlign.right),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: pw.Text(_currencyFmt.format(subtotal), style: const pw.TextStyle(fontSize: 9, color: PdfColors.black), textAlign: pw.TextAlign.right),
                ),
              ],
            );
          }),
        ],
      ),
        
        pw.SizedBox(height: 10),
        
        // TOTAL Y PAGOS (Idéntico a la foto 2)
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Pagos
            pw.Expanded(
              flex: 6,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Información de Pago', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  if (payments.length > 1) ...[
                    ...payments.map((p) => pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('- ${(p['payment_method']?['name'] ?? 'PAGO').toUpperCase()}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(_currencyFmt.format(double.tryParse(p['amount'].toString()) ?? 0), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ]
                    )).toList(),
                  ] else if (payments.isNotEmpty) ...[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('PAGO EN:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text((payments.first['payment_method']?['name'] ?? 'PAGO').toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                      ]
                    ),
                  ] else ...[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('PAGO EN:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text('EFECTIVO', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                      ]
                    ),
                  ],
                    
                  if (tendered > 0.01) ...[
                    pw.SizedBox(height: 8),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Abonó con:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(_currencyFmt.format(tendered), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ]
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Vuelto:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(_currencyFmt.format(change), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ]
                    ),
                  ],
                ]
              )
            ),
            pw.SizedBox(width: 40),
            // Total
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (shippingCost > 0)
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Subtotal:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(_currencyFmt.format(total - shippingCost), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ]
                    ),
                  if (shippingCost > 0)
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Flete / Envío:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(_currencyFmt.format(shippingCost), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ]
                    ),
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 8),
                    padding: const pw.EdgeInsets.only(top: 8),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(color: PdfColors.grey800, width: 1.5))
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('TOTAL:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Text(_currencyFmt.format(total), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      ]
                    )
                  )
                ]
              )
            )
          ]
        ),
        
        pw.Spacer(), // Empujar las firmas al final
        // FIRMAS
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            pw.Column(
              children: [
                pw.SizedBox(height: 35), // Espacio para la firma física
                pw.Container(width: 160, height: 1, color: PdfColors.grey800),
                pw.SizedBox(height: 5),
                pw.Text('FIRMA CAJERO / VENDEDOR', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
              ]
            ),
            pw.Column(
              children: [
                pw.SizedBox(height: 35), // Espacio para la firma física
                pw.Container(width: 160, height: 1, color: PdfColors.grey800),
                pw.SizedBox(height: 5),
                pw.Text('FIRMA CLIENTE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
              ]
            ),
          ]
        ),
        pw.SizedBox(height: 15),
    ];
  }

  // ---------------------------------------------------------------------------
  // SECCIÓN 2: REMITO (SIN PRECIOS, PARA LOGÍSTICA)
  // ---------------------------------------------------------------------------
  static List<pw.Widget> _buildDeliveryNoteList(Map<String, dynamic> note, Map<String, dynamic> sale, String businessName, String? businessAddress, String? vendorName) {
    final items = note['items'] as List<dynamic>? ?? [];
    final customerName = sale['customer']?['name'] ?? sale['customer_name'] ?? 'Consumidor Final';
    final noteId = note['id']?.toString().padLeft(6, '0') ?? '000000';

    return [
      // ENCABEZADO REMITO (Estilo Laravel: Izquierda/Derecha)
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(businessName.toUpperCase(), style: pw.TextStyle(color: PdfColors.black, fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('ORDEN DE RETIRO / REMITO', style: pw.TextStyle(color: _primary, fontSize: 14, fontWeight: pw.FontWeight.bold)),
              if (businessAddress != null && businessAddress.isNotEmpty)
                pw.Text(businessAddress, style: const pw.TextStyle(color: PdfColors.black, fontSize: 10)),
            ]
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Remito N°: $noteId', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('Venta Asoc: ${sale['id'].toString().padLeft(8, '0')}', style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Fecha: ${_dateFmt.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Cliente: ${customerName.toUpperCase()}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ]
          )
        ],
      ),

      pw.SizedBox(height: 5),
      pw.Divider(thickness: 2, color: PdfColors.black),
      pw.SizedBox(height: 8),

      // DATOS CLIENTE (Estilo Logística)
      pw.Container(
        decoration: const pw.BoxDecoration(
          color: _bgLight,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        padding: const pw.EdgeInsets.all(8),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CLIENTE', style: pw.TextStyle(fontSize: 8, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(customerName.toUpperCase(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('VENDIÓ', style: pw.TextStyle(fontSize: 8, color: _textGrey, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text((vendorName ?? 'SISTEMA').toUpperCase(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),

      pw.SizedBox(height: 8),

      // TABLA DE ITEMS
      pw.Table(
        border: pw.TableBorder(
          bottom: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(8),
          1: const pw.FlexColumnWidth(2),
        },
        children: [
          // Header
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _primary),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: pw.Text('DESCRIPCIÓN', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: pw.Text('CANTIDAD', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center),
              ),
            ]
          ),
          // Items
          ...items.map((item) {
            final qtyStr = item['quantity_purchased']?.toString() ?? item['quantity']?.toString() ?? '1';
            final qty = double.tryParse(qtyStr) ?? 1.0;
            
            final isWeight = item['product']?['is_sold_by_weight'] ?? false;
            final qtyText = isWeight ? '${qty.toStringAsFixed(3)} kg' : '${qty.toInt()} un';
            final pName = item['product']?['name'] ?? item['product_name'] ?? 'Producto';

            return pw.TableRow(
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))
              ),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: pw.Text(pName.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: pw.Text(qtyText, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                ),
              ]
            );
          }),
        ]
      ),
        
        pw.Spacer(),
        
        // FIRMAS (Con espacio real)
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            pw.Column(
              children: [
                pw.SizedBox(height: 35), // Espacio para la firma física
                pw.Container(width: 160, height: 1, color: PdfColors.grey800),
                pw.SizedBox(height: 5),
                pw.Text('FIRMA DESPACHANTE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
              ]
            ),
            pw.Column(
              children: [
                pw.SizedBox(height: 35), // Espacio para la firma física
                pw.Container(width: 160, height: 1, color: PdfColors.grey800),
                pw.SizedBox(height: 5),
                pw.Text('FIRMA CLIENTE / RETIRA', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
              ]
            ),
          ]
        ),
        pw.SizedBox(height: 15),
    ];
  }
}
