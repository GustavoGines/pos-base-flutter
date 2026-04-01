import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/product.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/core/utils/ean13_generator.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PRINT LABELS DIALOG — Split View con Vista Previa en tiempo real
//
// Layout:
//   ┌──────────────────────────────────────────────────────────────────┐
//   │ Header                                                           │
//   ├────────────────────────┬─────────────────────────────────────────┤
//   │ Panel Izquierdo (320px)│ Panel Derecho — PdfPreview (fill)       │
//   │ - Lista productos      │                                         │
//   │ - Selector cantidad    │   [preview en vivo, actualiza 500ms]    │
//   │ - Selector formato     │                                         │
//   │ - Resumen total        │                                         │
//   ├────────────────────────┴─────────────────────────────────────────┤
//   │ Footer — Cancelar | Imprimir (N)                                 │
//   └──────────────────────────────────────────────────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────
class PrintLabelsDialog extends StatefulWidget {
  final List<Product> products;

  const PrintLabelsDialog({super.key, required this.products});

  @override
  State<PrintLabelsDialog> createState() => _PrintLabelsDialogState();
}

class _PrintLabelsDialogState extends State<PrintLabelsDialog> {
  final Map<int, int> _quantities = {};
  final Map<int, double?> _weights = {};
  String _paperFormat = 'custom_55_45';
  // Smart default: se activa solo si algún producto tiene balanza o días de vencimiento.
  // Se calcula en initState() una vez que se conocen los productos.
  bool _printDates = false;

  // Debounce + UniqueKey para forzar rebuild del PdfPreview
  Key _previewKey = UniqueKey();
  Timer? _debounce;

  // Cache de datos empresa (cargados una sola vez desde SettingsProvider)
  String _companyName = 'Mi Negocio';
  String _companyAddress = '';
  String _companyPhone = '';
  String _companyTaxId = '';

  static bool _isPrinting = false;
  static bool _fontLoadingFailed = false;

  // Cache estático de fuentes para evitar re-escaneo de AssetManifest.json (Crash Bloqueante en Windows)
  static pw.Font? _robotoRegular;
  static pw.Font? _robotoBold;

  @override
  void initState() {
    super.initState();
    for (var p in widget.products) {
      _quantities[p.id] = 1;
      if (p.isSoldByWeight) {
        _weights[p.id] = 100.0;
      }
    }
    // Smart default del toggle ENV/VTO:
    // Si algún producto tiene balanza O tiene días de vencimiento configurados,
    // activamos el check automáticamente — el cajero quiere esas fechas.
    // Para productos simples sin fechas (gaseosas, snacks), arranca desmarcado.
    _printDates = widget.products.any(
      (p) => p.isSoldByWeight || (p.vencimientoDias != null && p.vencimientoDias! > 0),
    );
    // Leer settings una sola vez para tenerlos disponibles en el motor PDF
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<SettingsProvider>().settings;
      setState(() {
        _companyName = s?.companyName ?? 'Mi Negocio';
        _companyAddress = s?.address ?? '';
        _companyPhone = s?.phone ?? '';
        _companyTaxId = s?.taxId ?? '';
        _previewKey = UniqueKey();
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  int get _totalLabels => _quantities.values.fold(0, (a, b) => a + b);

  // ── Dispara rebuild del preview con debounce de 500ms ──────────────
  void _schedulePreviewRebuild() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _previewKey = UniqueKey());
    });
  }

  // ── Callback para PdfPreview — ignora el PdfPageFormat que pasa el widget
  //    y usa siempre el formato elegido por el usuario en el panel izquierdo
  Future<Uint8List> _buildPdfForPreview(PdfPageFormat _) =>
      _buildPdfBytes(companyName: _companyName, companyAddress: _companyAddress, companyPhone: _companyPhone, companyTaxId: _companyTaxId, printDates: _printDates);

  // ── Motor PDF principal ─────────────────────────────────────────────
  Future<Uint8List> _buildPdfBytes({
    required String companyName,
    required String companyAddress,
    required String companyPhone,
    required String companyTaxId,
    required bool printDates,
  }) async {
    // Carga de fuentes con Cache y Fallback de seguridad
    pw.Font ttfRegular;
    pw.Font ttfBold;

    if (_fontLoadingFailed) {
      // Fallback inmediato si ya sabemos que el sistema de assets de Windows está fallando
      ttfRegular = pw.Font.helvetica();
      ttfBold = pw.Font.helveticaBold();
    } else {
      try {
        // Intentar cargar Roboto desde Google Fonts (Cacheado)
        // Usar un timeout corto para no bloquear la UI si hay problemas de red
        ttfRegular = _robotoRegular ??= await PdfGoogleFonts.robotoRegular().timeout(const Duration(seconds: 5));
        ttfBold = _robotoBold ??= await PdfGoogleFonts.robotoBold().timeout(const Duration(seconds: 5));
      } catch (e) {
        // Fallback a Helvetica si hay error de assets/red/timeout para evitar crash fatal
        debugPrint('Fallo al cargar fuentes remotas o manifiesto de assets: $e');
        _fontLoadingFailed = true; // No volver a intentar en esta sesión
        ttfRegular = pw.Font.helvetica();
        ttfBold = pw.Font.helveticaBold();
      }
    }

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: ttfRegular, bold: ttfBold),
    );
    final now = DateTime.now();
    final dateFmt = DateFormat('dd/MM/yy');

    double computeHeight(Product product) {
      // La altura estándar es siempre 45mm para garantizar espacio y evitar clipping.
      // Además, mantenerla en 45mm asegura que los rollos troquelados (55x45) no pierdan calibración.
      return 45.0;
    }

    pw.Widget buildLabel(Product product, {required double heightLabel}) {
      final double? customWeight = _weights[product.id];
      final bool hasWeight = product.isSoldByWeight && customWeight != null && customWeight > 0;

      // Determinamos el PLU numérico: Priorizamos el Código Interno (si es numérico), sino usamos el ID
      final int numericPlu = int.tryParse(product.internalCode) ?? product.id;
      final String pluStr = numericPlu.toString().padLeft(5, '0');

      final double finalPrice = hasWeight 
          ? product.sellingPrice * (customWeight / 1000)
          : product.sellingPrice;

      final String ean13 = hasWeight 
          ? Ean13Generator.generateForScale(numericPlu, finalPrice)
          : Ean13Generator.generate(
              plu: numericPlu,
              existingBarcode: product.barcode,
            );

      final String envStr = dateFmt.format(now);
      final String? vtoStr = (product.vencimientoDias != null &&
              product.vencimientoDias! > 0)
          ? dateFmt.format(now.add(Duration(days: product.vencimientoDias!)))
          : null;

      final String precioStr = NumberFormat('#,##0', 'es_AR').format(finalPrice);
      final bool isValidEan = Ean13Generator.isValid(ean13);
      return pw.SizedBox(
        width: 55 * PdfPageFormat.mm,
        height: heightLabel * PdfPageFormat.mm,
        child: pw.Container(
          padding: pw.EdgeInsets.symmetric(
          horizontal: 1.5 * PdfPageFormat.mm,
          vertical: 1.5 * PdfPageFormat.mm,
        ),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
          borderRadius: pw.BorderRadius.circular(2),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, // Distribute properly
          children: [
            // NOMBRE Y GRAMAJE
            pw.Text(
              product.name.toUpperCase(),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
            ),
            if (hasWeight) ...[
              pw.Text(
                '${customWeight.toInt()} GS',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
            ],
            
            // FECHAS (ENV y VTO)
            // Lógica Profesional: Solo imprimimos ENV si el usuario lo solicita explícitamente usando el toggle (printDates == true)
            // Y además, si el producto amerita fechas (es de balanza o tiene vencimiento). Para gaseosas unitarias, se oculta.
            if (printDates && (hasWeight || vtoStr != null))
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('ENV: $envStr', style: const pw.TextStyle(fontSize: 7)),
                  if (vtoStr != null) ...[
                    pw.SizedBox(width: 4 * PdfPageFormat.mm),
                    pw.Text('VTO: $vtoStr', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  ],
                ],
              )
            else
              pw.SizedBox(height: 3 * PdfPageFormat.mm), // Compensación de espacio para no romper el layout grid
            
            // DETALLE DE UNIDADES / PRECIO X KG
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                 if (!hasWeight) ... [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('UNIDADES', style: const pw.TextStyle(fontSize: 5)),
                        pw.Text('1', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ]
                    )
                 ] else ... [
                     pw.Column(
                       crossAxisAlignment: pw.CrossAxisAlignment.start,
                       children: [
                         pw.Text('\$/KG', style: pw.TextStyle(fontSize: 5)),
                         pw.Text(
                           NumberFormat('#,##0', 'es_AR').format(product.sellingPrice),
                           style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                         ),
                       ],
                     ),
                 ],
              ],
            ),

            // BLOQUE INFERIOR: CÓDIGO BARRAS (IZQ) + IMPORTE (DER)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                 // Columna Barcode
                 pw.Expanded(
                   flex: 55,
                   child: pw.Column(
                     crossAxisAlignment: pw.CrossAxisAlignment.start,
                     children: [
                       pw.Text('PLU:$pluStr', style: const pw.TextStyle(fontSize: 5)),
                       pw.SizedBox(height: 0.5 * PdfPageFormat.mm),
                       pw.BarcodeWidget(
                         barcode: isValidEan ? pw.Barcode.ean13() : pw.Barcode.code128(),
                         data: ean13,
                         drawText: false,
                         height: (heightLabel <= 36.0 ? 8 : 10) * PdfPageFormat.mm, // Escala inteligente para códigos cortos
                         width: 32 * PdfPageFormat.mm, 
                       ),
                       pw.SizedBox(height: 0.5 * PdfPageFormat.mm),
                       pw.Text(
                         Ean13Generator.format(ean13),
                         style: pw.TextStyle(fontSize: 5, font: ttfRegular),
                         textAlign: pw.TextAlign.center,
                       ),
                     ],
                   ),
                 ),
                 pw.SizedBox(width: 2 * PdfPageFormat.mm),
                 // Columna Importe
                 pw.Expanded(
                   flex: 45,
                   child: pw.Column(
                     crossAxisAlignment: pw.CrossAxisAlignment.end,
                     mainAxisAlignment: pw.MainAxisAlignment.end,
                     children: [
                       pw.Text('IMPORTE (\$)', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                       pw.Text(
                         precioStr,
                         style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, letterSpacing: -0.5),
                         textAlign: pw.TextAlign.right,
                       ),
                     ],
                   ),
                 ),
              ]
            ),
            
            // PIE DE NEGOCIO (COMPACTADO)
            pw.Text(
              companyName.toUpperCase(),
              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
              maxLines: 1,
            ),
            if (companyAddress.isNotEmpty || companyPhone.isNotEmpty || companyTaxId.isNotEmpty)
              pw.Text(
                [
                  if (companyAddress.isNotEmpty) companyAddress.toUpperCase(),
                  if (companyPhone.isNotEmpty) 'TEL: $companyPhone',
                  if (companyTaxId.isNotEmpty) 'CUIT: $companyTaxId'
                ].join(' • '),
                style: const pw.TextStyle(fontSize: 4),
                textAlign: pw.TextAlign.center,
                maxLines: 2,
              ),
          ],
        ),
       )
      );
    }

    // Generar lista plana de etiquetas para reportes o A4
    final List<pw.Widget> allLabels = [];
    for (final p in widget.products) {
      final qty = _quantities[p.id] ?? 1;
      final h = computeHeight(p);
      for (int i = 0; i < qty; i++) {
        allLabels.add(buildLabel(p, heightLabel: h));
      }
    }

    if (_paperFormat == 'thermal') {
      const format = PdfPageFormat(
        80 * PdfPageFormat.mm,
        50 * PdfPageFormat.mm,
        marginAll: 0,
      );
      for (final label in allLabels) {
        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Center(child: label),
          ),
        );
      }
    } else if (_paperFormat == 'custom_55_45') {
       for (final p in widget.products) {
         final qty = _quantities[p.id] ?? 1;
         final h = computeHeight(p);
         final format = PdfPageFormat(
           55 * PdfPageFormat.mm,
           h * PdfPageFormat.mm,
           marginAll: 0,
         );
         final labelWidget = buildLabel(p, heightLabel: h);
         
         for (int i = 0; i < qty; i++) {
            pdf.addPage(
               pw.Page(pageFormat: format, margin: pw.EdgeInsets.zero, build: (_) => pw.Center(child: labelWidget)),
            );
         }
       }
    } else {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
          build: (_) => [
            pw.Wrap(
              spacing: 4 * PdfPageFormat.mm,
              runSpacing: 4 * PdfPageFormat.mm,
              children: allLabels,
            ),
          ],
        ),
      );
    }

    return Uint8List.fromList(await pdf.save());
  }

  // ── Acción Imprimir ─────────────────────────────────────────────────
  Future<void> _print() async {
    if (_totalLabels == 0) {
      SnackBarService.error(
          context, 'Seleccioná al menos 1 etiqueta para imprimir.');
      return;
    }
    setState(() => _isPrinting = true);
    try {
      final bytes = await _buildPdfBytes(
        companyName: _companyName,
        companyAddress: _companyAddress,
        companyPhone: _companyPhone,
        companyTaxId: _companyTaxId,
        printDates: _printDates,
      );
      if (mounted) Navigator.of(context).pop();
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name:
            'Etiquetas_POS_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
        dynamicLayout: false,
      );
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al imprimir: $e');
        setState(() => _isPrinting = false);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // UI BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 960,
        height: 660,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Panel Izquierdo — Controles ───────────────
                  SizedBox(width: 320, child: _buildLeftPanel()),
                  const VerticalDivider(width: 1),
                  // ── Panel Derecho — Vista Previa ──────────────
                  Expanded(child: _buildPreviewPanel()),
                ],
              ),
            ),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Colors.deepPurple.shade50,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.label_important,
                color: Colors.deepPurple.shade700, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Imprimir Etiquetas de Precio',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '${widget.products.length} producto${widget.products.length > 1 ? 's' : ''} · Vista previa en tiempo real',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Cancelar',
          ),
        ],
      ),
    );
  }

  // ── Panel Izquierdo ─────────────────────────────────────────────────
  Widget _buildLeftPanel() {
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Lista de productos con cantidad ───────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Text(
                  'CANTIDAD POR PRODUCTO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.products.map((p) => _buildProductQtyRow(p)),
                const SizedBox(height: 16),

                // ── Selector de formato ───────────────────────
                Text(
                  'FORMATO DE IMPRESIÓN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _FormatCard(
                        selected: _paperFormat == 'custom_55_45',
                        icon: Icons.aspect_ratio_rounded,
                        title: 'Etiq. 55x45',
                        subtitle: 'Pixel-perfect',
                        onTap: () {
                          setState(() {
                            _paperFormat = 'custom_55_45';
                            _schedulePreviewRebuild();
                          });
                        },
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FormatCard(
                        selected: _paperFormat == 'a4',
                        icon: Icons.grid_view_rounded,
                        title: 'Plancha A4',
                        subtitle: 'Página Múltiple',
                        onTap: () {
                          setState(() {
                            _paperFormat = 'a4';
                            _schedulePreviewRebuild();
                          });
                        },
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FormatCard(
                        selected: _paperFormat == 'thermal',
                        icon: Icons.receipt_long_outlined,
                        title: 'Rollo 80mm',
                        subtitle: 'Ticketeras',
                        onTap: () {
                          setState(() {
                            _paperFormat = 'thermal';
                            _schedulePreviewRebuild();
                          });
                        },
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // ── Opciones Avanzadas ───────────────────────
                Text(
                  'OPCIONES DE ETIQUETA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: CheckboxListTile(
                    title: const Text('Imprimir ENV y VTO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Útil para códigos de góndola o deteriorados.', style: TextStyle(fontSize: 10)),
                    value: _printDates,
                    activeColor: Colors.deepPurple,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    visualDensity: VisualDensity.compact,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _printDates = val);
                        _schedulePreviewRebuild();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── Resumen sticky al fondo del panel ─────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border:
                  Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.summarize_outlined,
                  size: 16,
                  color: _totalLabels > 0
                      ? Colors.deepPurple
                      : Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _totalLabels > 0
                        ? '$_totalLabels etiqueta${_totalLabels > 1 ? 's' : ''} · ${_paperFormat == 'a4' ? 'Hoja A4' : 'Rollo 80mm'}'
                        : 'Sin etiquetas seleccionadas',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _totalLabels > 0
                          ? Colors.deepPurple.shade700
                          : Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductQtyRow(Product p) {
    final qty = _quantities[p.id] ?? 0;
    final hasExpiry = p.vencimientoDias != null && p.vencimientoDias! > 0;
    final double? currentWeight = _weights[p.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: qty > 0 ? Colors.white : Colors.grey.shade100,
        border: Border.all(
          color: qty > 0 ? Colors.deepPurple.shade100 : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Text(
                          '\$${p.sellingPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.w600),
                        ),
                        if (hasExpiry) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.hourglass_bottom_outlined,
                              size: 10, color: Colors.grey.shade500),
                          Text(
                            ' ${p.vencimientoDias}d',
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade500),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Selector +/-
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QtyButton(
                    icon: Icons.remove,
                    color: Colors.red.shade300,
                    onTap: qty > 0
                        ? () {
                            setState(() => _quantities[p.id] = qty - 1);
                            _schedulePreviewRebuild();
                          }
                        : null,
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: qty > 0
                            ? Colors.deepPurple.shade700
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
                  _QtyButton(
                    icon: Icons.add,
                    color: Colors.green.shade600,
                    onTap: () {
                      setState(() => _quantities[p.id] = qty + 1);
                      _schedulePreviewRebuild();
                    },
                  ),
                ],
              ),
            ],
          ),
          if (p.isSoldByWeight && qty > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200, width: 0.5)
              ),
              child: Row(
                children: [
                  const Icon(Icons.scale_rounded, size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  const Text('Peso:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 82, // Compactado para evitar overflow en panel de 320px
                    height: 32,
                    child: TextFormField(
                      initialValue: currentWeight?.toInt().toString() ?? '',
                      keyboardType: const TextInputType.numberWithOptions(decimal: false),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        hintText: '100',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: Colors.orange.shade200, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: Colors.orange.shade200, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Colors.orange, width: 1.5),
                        ),
                        suffixText: 'gr',
                        suffixStyle: TextStyle(
                          fontSize: 10, 
                          color: Colors.orange.shade800, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                      onChanged: (val) {
                         final w = double.tryParse(val.replaceAll(',', '.'));
                         if (w != null && w > 0) {
                           _weights[p.id] = w;
                         } else {
                           _weights[p.id] = null;
                         }
                         _schedulePreviewRebuild();
                      },
                    ),
                  ),
                  const Spacer(), // Empuja el importe a la derecha de forma flexible
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Total Etq.', style: TextStyle(fontSize: 9, color: Colors.grey)),
                      Text(
                        '\$${NumberFormat('#,##0', 'es_AR').format((currentWeight ?? 0) / 1000 * p.sellingPrice)}',
                        style: const TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.bold),
                      )
                    ]
                  )
                ]
              )
            )
          ]
        ]
      )
    );
  }

  // ── Panel Derecho — Vista Previa ────────────────────────────────────
  Widget _buildPreviewPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Label de la sección
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Icon(Icons.preview_outlined,
                  size: 15, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                'VISTA PREVIA — ${_paperFormat == 'a4' ? 'HOJA A4' : 'ROLLO 80mm'}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (_totalLabels == 0)
                Text(
                  'Seleccioná productos para ver el preview',
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
            ],
          ),
        ),
        // PdfPreview
        Expanded(
          child: _totalLabels == 0
              ? _buildEmptyPreview()
              : PdfPreview(
                  key: _previewKey,
                  build: _buildPdfForPreview,
                  // Ocultar toda la barra de herramientas nativa
                  allowPrinting: false,
                  allowSharing: false,
                  canDebug: false,
                  // Formato inicial para el preview
                  initialPageFormat: _paperFormat == 'a4'
                      ? PdfPageFormat.a4
                      : _paperFormat == 'custom_55_45'
                          ? const PdfPageFormat(
                              55 * PdfPageFormat.mm,
                              45 * PdfPageFormat.mm,
                            )
                          : const PdfPageFormat(
                              80 * PdfPageFormat.mm,
                              50 * PdfPageFormat.mm,
                            ),
                  // Estilo de página con sombra
                  pdfPreviewPageDecoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  scrollViewDecoration: BoxDecoration(
                    color: Colors.grey.shade300,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.label_off_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Sin etiquetas para previsualizar',
            style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            'Asigná al menos 1 unidad a un producto\npara ver el preview en tiempo real.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed:
                _isPrinting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: (_isPrinting || _totalLabels == 0) ? null : _print,
            icon: _isPrinting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print_outlined, size: 18),
            label: Text(
              _isPrinting
                  ? 'Enviando...'
                  : 'Imprimir $_totalLabels etiqueta${_totalLabels != 1 ? 's' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────────────────────────────────────

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _QtyButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: onTap != null ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? color : Colors.grey.shade300,
        ),
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;

  const _FormatCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : Colors.white,
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected ? color : Colors.grey.shade500, size: 24),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: selected ? color : Colors.black87,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
