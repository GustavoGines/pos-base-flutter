import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_pdf_preview.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/product.dart';
import '../../data/models/product_batch_model.dart';
import 'package:frontend_desktop/features/pos/utils/batch_barcode_helper.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/core/utils/ean13_generator.dart';
import 'package:frontend_desktop/core/utils/afip_fiscal_pdf_service.dart';

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
  final Map<int, ProductBatchModel>? batchByProductId;
  final Map<int, int>? initialQuantities;

  const PrintLabelsDialog({
    super.key,
    required this.products,
    this.batchByProductId,
    this.initialQuantities,
  });

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
  bool _useBatchBarcode = false;
  BusinessVerticalProfile _profile =
      BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);

  bool _isScaleWeightProduct(Product p) {
    if (!p.isSoldByWeight) return false;
    if (!_profile.canUseScaleWeight) return false;
    final u = p.unitType.trim().toLowerCase();
    return u == 'kg' || u == 'g' || u == 'un' || u.isEmpty;
  }

  // Debounce + UniqueKey para forzar rebuild del PdfPreview
  Key _previewKey = UniqueKey();
  Timer? _debounce;

  // Cache de datos empresa (cargados una sola vez desde SettingsProvider)
  String _companyName = 'Mi Negocio';
  String _companyAddress = '';
  String _companyPhone = '';
  String _companyTaxId = '';

  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    try {
      _profile =
          Provider.of<SettingsProvider?>(context, listen: false)?.safeVerticalProfile ??
              BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
    } catch (_) {
      _profile =
          BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
    }
    for (var p in widget.products) {
      final preset = widget.initialQuantities?[p.id];
      _quantities[p.id] = (preset != null && preset >= 0) ? preset : 1;
      if (_isScaleWeightProduct(p)) {
        _weights[p.id] = 100.0;
      }
    }
    // Smart default del toggle ENV/VTO:
    // Si algún producto tiene balanza (retail kg/g) O tiene días de vencimiento configurados,
    // activamos el check automáticamente — el cajero quiere esas fechas.
    // Para productos simples o de ferretería (mt/m2/m3), arranca desmarcado.
    _printDates = widget.products.any(
      (p) =>
          _isScaleWeightProduct(p) ||
          (p.vencimientoDias != null && p.vencimientoDias! > 0) ||
          (widget.batchByProductId?.containsKey(p.id) ?? false),
    );
    // Leer settings una sola vez para tenerlos disponibles en el motor PDF
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = () {
        try {
          return Provider.of<SettingsProvider?>(context, listen: false)?.settings;
        } catch (_) {
          return null;
        }
      }();
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
  Future<Uint8List> _buildPdfForPreview(PdfPageFormat _) => _buildPdfBytes(
      companyName: _companyName,
      companyAddress: _companyAddress,
      companyPhone: _companyPhone,
      companyTaxId: _companyTaxId,
      printDates: _printDates);

  // ── Motor PDF principal ─────────────────────────────────────────────
  Future<Uint8List> _buildPdfBytes({
    required String companyName,
    required String companyAddress,
    required String companyPhone,
    required String companyTaxId,
    required bool printDates,
  }) async {
    // Carga de fuentes Roboto locales cacheadas en RAM (100% offline, soporta Unicode como '•')
    final theme = await AfipFiscalPdfService.resolveCachedPdfTheme() ??
        pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        );

    final pdf = pw.Document(theme: theme);
    final now = DateTime.now();
    final dateFmt = DateFormat('dd/MM/yy');

    double computeHeight(Product product) {
      if (_paperFormat == 'thermal') return 50.0;
      if (_paperFormat == 'thermal_58') return 48.0;
      return 45.0;
    }

    pw.Widget buildLabel(Product product,
        {required double heightLabel, required double widthLabel}) {
      final bool isThermal = _paperFormat.startsWith('thermal');
      final ProductBatchModel? batch = widget.batchByProductId?[product.id];
      final double? customWeight = _weights[product.id];
      final bool hasWeight =
          _isScaleWeightProduct(product) && customWeight != null && customWeight > 0;

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
      final String? batchBarcode = (batch != null && _useBatchBarcode)
          ? BatchBarcodeHelper.encode(
              batchId: batch.id,
              weightGrams: hasWeight ? customWeight : null,
            )
          : null;
      final String barcodeValue = batchBarcode ?? ean13;

      final DateTime envDt = (batch?.manufacturedAt != null
              ? DateTime.tryParse(batch!.manufacturedAt!)
              : null) ??
          now;
      final String envStr = dateFmt.format(envDt);

      DateTime? vtoDt = batch?.expirationDate != null
          ? DateTime.tryParse(batch!.expirationDate!)
          : null;
      vtoDt ??= product.expirationDate != null
          ? DateTime.tryParse(product.expirationDate!)
          : null;
      vtoDt ??= (product.vencimientoDias != null && product.vencimientoDias! > 0)
          ? now.add(Duration(days: product.vencimientoDias!))
          : null;
      final String? vtoStr = vtoDt != null ? dateFmt.format(vtoDt) : null;

      final String precioStr =
          NumberFormat('#,##0', 'es_AR').format(finalPrice);
      final bool useEan13 =
          batchBarcode == null && Ean13Generator.isValid(ean13);
      final double hPadMm = isThermal ? 1.0 : 1.5;
      final double innerWidthPt =
          (widthLabel - (hPadMm * 2)) * PdfPageFormat.mm;

      // ── Layout completamente plano: un solo Column min-size, sin spaceBetween
      // spaceBetween causaba que los bloques se separaran más allá del SizedBox
      // y el PDF renderizaba el contenido en 2 páginas.
      return pw.SizedBox(
        width: widthLabel * PdfPageFormat.mm,
        height: heightLabel * PdfPageFormat.mm,
        child: pw.ClipRect(
          child: pw.Container(
            width: widthLabel * PdfPageFormat.mm,
            height: heightLabel * PdfPageFormat.mm,
            padding: pw.EdgeInsets.symmetric(
              horizontal: hPadMm * PdfPageFormat.mm,
              vertical: hPadMm * PdfPageFormat.mm,
            ),
            decoration: isThermal
                ? null
                : pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.topCenter,
              child: pw.SizedBox(
                width: innerWidthPt,
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                // ── NOMBRE ──
                pw.Text(
                  product.name.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                  overflow: pw.TextOverflow.clip,
                ),
                if (product.technicalSpec != null &&
                    product.technicalSpec!.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
                  pw.Text(
                    product.technicalSpec!.trim().toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 8.0,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),
                ],
                pw.SizedBox(height: 1 * PdfPageFormat.mm),

                // ── GRAMAJE (solo si tiene peso) ──
                if (hasWeight) ...[
                  pw.Text(
                    '${customWeight.toInt()} GS',
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 1 * PdfPageFormat.mm),
                ],

                // ── FECHAS / LOTE (solo si aplica) ──
                if (batch != null || (printDates && (hasWeight || vtoStr != null))) ...[
                  if (batch != null)
                    pw.Text(
                      'LOTE: ${batch.batchCode}',
                      style: pw.TextStyle(
                        fontSize: 6.0,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('ENV: $envStr',
                          style: const pw.TextStyle(fontSize: 7)),
                      if (vtoStr != null) ...[
                        pw.SizedBox(width: 3 * PdfPageFormat.mm),
                        pw.Text('VTO: $vtoStr',
                            style: pw.TextStyle(
                                fontSize: 7, fontWeight: pw.FontWeight.bold)),
                      ],
                    ],
                  ),
                  pw.SizedBox(
                      height: (batch != null ? 0.7 : 1.0) * PdfPageFormat.mm),
                ],

                // ── UNIDADES / PRECIO X KG ──
                if (!hasWeight)
                  pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (product.unitType.trim().toLowerCase() != 'un' &&
                          product.unitType.trim().isNotEmpty) ...[
                        pw.Text('UNIDAD',
                            style: const pw.TextStyle(fontSize: 5)),
                        pw.Text('1 ${product.unitShortLabel.toUpperCase()}',
                            style: pw.TextStyle(
                                fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ] else ...[
                        pw.Text('UNIDADES',
                            style: const pw.TextStyle(fontSize: 5)),
                        pw.Text('1',
                            style: pw.TextStyle(
                                fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ],
                    ],
                  )
                else
                  pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('\$/KG', style: const pw.TextStyle(fontSize: 5)),
                      pw.Text(
                        NumberFormat('#,##0', 'es_AR')
                            .format(product.sellingPrice),
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),

                pw.SizedBox(height: 1.5 * PdfPageFormat.mm),

                // ── BARCODE + IMPORTE ──
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    // Columna código de barras
                    pw.Expanded(
                      flex: 58,
                      child: pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('PLU:$pluStr',
                              style: const pw.TextStyle(fontSize: 5)),
                          pw.SizedBox(height: 0.5 * PdfPageFormat.mm),
                          pw.BarcodeWidget(
                            barcode: useEan13
                                ? pw.Barcode.ean13()
                                : pw.Barcode.code128(),
                            data: barcodeValue,
                            drawText: false,
                            height: (widthLabel >= 75.0 ? 11 : 8) *
                                PdfPageFormat.mm,
                            width: (widthLabel > 60.0
                                    ? 36
                                    : (widthLabel <= 48.0 ? 24 : 28)) *
                                PdfPageFormat.mm,
                          ),
                          pw.SizedBox(height: 0.5 * PdfPageFormat.mm),
                          pw.Text(
                            batchBarcode != null
                                ? '${batch!.batchCode} ($barcodeValue)'
                                : Ean13Generator.format(ean13),
                            style: const pw.TextStyle(fontSize: 5),
                            textAlign: pw.TextAlign.left,
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 1.5 * PdfPageFormat.mm),
                    // Columna importe
                    pw.Expanded(
                      flex: 42,
                      child: pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('IMPORTE (\$)',
                              style: pw.TextStyle(
                                  fontSize: 6, fontWeight: pw.FontWeight.bold)),
                          pw.FittedBox(
                            fit: pw.BoxFit.scaleDown,
                            child: pw.Text(
                              precioStr,
                              style: pw.TextStyle(
                                  fontSize: 20,
                                  fontWeight: pw.FontWeight.bold,
                                  letterSpacing: -0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 1 * PdfPageFormat.mm),

                // ── PIE DE NEGOCIO ──
                pw.Text(
                  companyName.toUpperCase(),
                  style:
                      pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                ),
                if (companyAddress.isNotEmpty ||
                    companyPhone.isNotEmpty ||
                    companyTaxId.isNotEmpty)
                  pw.Text(
                    [
                      if (companyAddress.isNotEmpty)
                        companyAddress.toUpperCase(),
                      if (companyPhone.isNotEmpty) 'TEL: $companyPhone',
                      if (companyTaxId.isNotEmpty) 'CUIT: $companyTaxId',
                    ].join(' • '),
                    style: const pw.TextStyle(fontSize: 4),
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

    // Generar lista plana de etiquetas para reportes o A4
    final double labelWidth = _paperFormat == 'thermal_58'
        ? 47.0
        : (_paperFormat == 'thermal' ? 78.0 : 55.0);
    final List<pw.Widget> allLabels = [];

    for (final p in widget.products) {
      final qty = _quantities[p.id] ?? 1;
      final h = computeHeight(p);
      for (int i = 0; i < qty; i++) {
        allLabels.add(buildLabel(p, heightLabel: h, widthLabel: labelWidth));
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
    } else if (_paperFormat == 'thermal_58') {
      const format = PdfPageFormat(
        48 * PdfPageFormat.mm,
        48 * PdfPageFormat.mm,
        marginAll: 0,
      );
      for (final label in allLabels) {
        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.zero,
            build: (_) =>
                pw.Align(alignment: pw.Alignment.topCenter, child: label),
          ),
        );
      }
    } else if (_paperFormat == 'custom_55_45') {
      for (final p in widget.products) {
        final qty = _quantities[p.id] ?? 1;
        final h = computeHeight(p);
        final format = PdfPageFormat(
          labelWidth * PdfPageFormat.mm,
          h * PdfPageFormat.mm,
          marginAll: 0,
        );
        final labelWidget =
            buildLabel(p, heightLabel: h, widthLabel: labelWidth);

        for (int i = 0; i < qty; i++) {
          pdf.addPage(
            pw.Page(
                pageFormat: format,
                margin: pw.EdgeInsets.zero,
                build: (_) => pw.Center(child: labelWidget)),
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
    final screenH = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: math.min(660, screenH * 0.92),
        ),
        child: SizedBox(
          width: 960,
          child: Column(
            children: [
              _buildHeader(),
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
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return AppModalHeader(
      title: 'Imprimir Etiquetas de Precio',
      subtitle:
          '${widget.products.length} producto${widget.products.length > 1 ? 's' : ''} · Vista previa en tiempo real',
      icon: Icons.label_important_rounded,
      accent: AppModalAccent.indigo,
      closeTooltip: 'Cancelar',
      onClose: () => Navigator.of(context).pop(),
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
                if (widget.initialQuantities != null &&
                    widget.initialQuantities!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.looks_one_outlined, size: 14),
                        label: const Text('1 por lote/bandeja',
                            style: TextStyle(fontSize: 10.5)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            for (final p in widget.products) {
                              _quantities[p.id] = 1;
                            }
                            _schedulePreviewRebuild();
                          });
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.auto_fix_high, size: 14),
                        label: const Text('Cant. producida',
                            style: TextStyle(fontSize: 10.5)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            for (final p in widget.products) {
                              final preset = widget.initialQuantities?[p.id];
                              if (preset != null && preset >= 0) {
                                _quantities[p.id] = preset;
                              }
                            }
                            _schedulePreviewRebuild();
                          });
                        },
                      ),
                    ],
                  ),
                ],
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 130,
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
                        color: AppColors.indigo,
                      ),
                    ),
                    SizedBox(
                      width: 130,
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
                    SizedBox(
                      width: 130,
                      child: _FormatCard(
                        selected: _paperFormat == 'thermal_58' ||
                            _paperFormat == 'thermal',
                        icon: Icons.receipt_long_outlined,
                        title: 'Rollo Térmico',
                        subtitle: 'Punto de Venta',
                        onTap: () {
                          setState(() {
                            final localTerminal =
                                context.read<LocalTerminalProvider>();
                            _paperFormat =
                                localTerminal.printerFormat == 'thermal_80'
                                    ? 'thermal'
                                    : 'thermal_58';
                            _schedulePreviewRebuild();
                          });
                        },
                        color: Colors.teal,
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
                  child: Material(
                    color: Colors.transparent,
                    child: CheckboxListTile(
                      title: const Text('Imprimir ENV y VTO',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                          'Útil para códigos de góndola o deteriorados.',
                          style: TextStyle(fontSize: 10)),
                      value: _printDates,
                      activeColor: AppColors.indigo,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      visualDensity: VisualDensity.compact,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _printDates = val);
                          _schedulePreviewRebuild();
                        }
                      },
                    ),
                  ),
                ),
                if (widget.batchByProductId != null &&
                    widget.batchByProductId!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: CheckboxListTile(
                        title: const Text('Código de barras por lote (L#)',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: const Text(
                            'Desmarcado: usa el código EAN-13 del producto.',
                            style: TextStyle(fontSize: 10)),
                        value: _useBatchBarcode,
                        activeColor: AppColors.indigo,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        visualDensity: VisualDensity.compact,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _useBatchBarcode = val);
                            _schedulePreviewRebuild();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Resumen sticky al fondo del panel ─────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.summarize_outlined,
                  size: 16,
                  color: _totalLabels > 0
                      ? AppColors.indigo
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
                          ? AppColors.indigo
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
            color: qty > 0 ? Colors.indigo.shade200 : Colors.grey.shade200,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                    if (p.technicalSpec != null &&
                        p.technicalSpec!.trim().isNotEmpty)
                      Text(
                        p.technicalSpec!.trim(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Row(
                      children: [
                        Text(
                          '\$${p.sellingPrice.toCurrency()}',
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
                            ? AppColors.indigo
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
          if (_isScaleWeightProduct(p) && qty > 0) ...[
            const SizedBox(height: 12),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: Colors.orange.shade200, width: 0.5)),
                child: Row(children: [
                  const Icon(Icons.scale_rounded,
                      size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  const Text('Peso:',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  SizedBox(
                    width:
                        82, // Compactado para evitar overflow en panel de 320px
                    height: 32,
                    child: TextFormField(
                      initialValue: currentWeight?.toInt().toString() ?? '',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        hintText: '100',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                              color: Colors.orange.shade200, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                              color: Colors.orange.shade200, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                              color: Colors.orange, width: 1.5),
                        ),
                        suffixText: 'gr',
                        suffixStyle: TextStyle(
                            fontSize: 10,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.bold),
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
                        const Text('Total Etq.',
                            style: TextStyle(fontSize: 9, color: Colors.grey)),
                        Text(
                          '\$${NumberFormat('#,##0', 'es_AR').format((currentWeight ?? 0) / 1000 * p.sellingPrice)}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.indigo,
                              fontWeight: FontWeight.bold),
                        )
                      ])
                ]))
          ]
        ]));
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
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
            ],
          ),
        ),
        // Visor PDF unificado con zoom Ctrl + rueda
        Expanded(
          child: _totalLabels == 0
              ? _buildEmptyPreview()
              : AppPdfPreview(
                  key: _previewKey,
                  build: _buildPdfForPreview,
                  initialPageFormat: _paperFormat == 'a4'
                      ? PdfPageFormat.a4
                      : _paperFormat == 'custom_55_45'
                          ? const PdfPageFormat(
                              55 * PdfPageFormat.mm,
                              45 * PdfPageFormat.mm,
                            )
                          : _paperFormat == 'thermal_58'
                              ? const PdfPageFormat(
                                  58 * PdfPageFormat.mm,
                                  40 * PdfPageFormat.mm,
                                )
                              : const PdfPageFormat(
                                  80 * PdfPageFormat.mm,
                                  50 * PdfPageFormat.mm,
                                ),
                  showPrintAction: false,
                  showSaveAction: false,
                  showShareAction: false,
                  compactToolbar: true,
                  autofocus: false,
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
          Icon(Icons.label_off_outlined, size: 64, color: Colors.grey.shade300),
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
    return AppModalFooter(
      actions: [
        TextButton(
          onPressed: _isPrinting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.indigo,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: (_isPrinting || _totalLabels == 0) ? null : _print,
          icon: _isPrinting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.print_outlined, size: 18),
          label: Text(
            _isPrinting
                ? 'Enviando...'
                : 'Imprimir $_totalLabels etiqueta${_totalLabels != 1 ? 's' : ''}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
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
          color: onTap != null
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
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
          color: selected ? color.withValues(alpha: 0.08) : Colors.white,
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
