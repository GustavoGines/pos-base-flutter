import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../domain/entities/product.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

class PrintLabelsDialog extends StatefulWidget {
  final List<Product> products;
  final String companyName;

  const PrintLabelsDialog({
    Key? key,
    required this.products,
    this.companyName = 'Mi Negocio POS', // Podría venir del SettingsProvider
  }) : super(key: key);

  @override
  State<PrintLabelsDialog> createState() => _PrintLabelsDialogState();
}

class _PrintLabelsDialogState extends State<PrintLabelsDialog> {
  final Map<int, int> _quantities = {};
  bool _isGenerating = false;
  String _paperFormat = 'a4'; // Por defecto A4 (grilla multi-etiqueta)

  @override
  void initState() {
    super.initState();
    for (var p in widget.products) {
      _quantities[p.id] = 1;
    }
  }

  bool _isValidEan13(String code) {
    if (code.length != 13 || double.tryParse(code) == null) return false;
    int sum = 0;
    for (int i = 0; i < 12; i++) {
        int v = int.parse(code[i]);
        sum += (i % 2 == 0) ? v : v * 3;
    }
    int check = (10 - (sum % 10)) % 10;
    return check == int.parse(code[12]);
  }

  Future<void> _generateAndPrint() async {
    setState(() => _isGenerating = true);

    try {
      final pdf = pw.Document();

      pw.Widget buildLabel(Product product) {
        final String codeToPrint = (product.barcode != null && product.barcode!.isNotEmpty)
            ? product.barcode!
            : product.internalCode;

        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              widget.companyName.toUpperCase(),
              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
              maxLines: 1,
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              product.name,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              '\$${product.sellingPrice.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.Spacer(),
            pw.SizedBox(
              height: 16,
              width: 100,
              child: pw.BarcodeWidget(
                barcode: _isValidEan13(codeToPrint) 
                          ? pw.Barcode.ean13()
                          : pw.Barcode.code128(),
                data: codeToPrint,
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 6),
                margin: pw.EdgeInsets.zero,
              ),
            ),
          ],
        );
      }

      // Generar la lista plana de todas las etiquetas solicitadas
      final List<pw.Widget> allLabels = [];
      for (final p in widget.products) {
        final qty = _quantities[p.id] ?? 1;
        for (int i = 0; i < qty; i++) {
          allLabels.add(
            pw.Container(
              width: 50 * PdfPageFormat.mm,
              height: 25 * PdfPageFormat.mm,
              padding: const pw.EdgeInsets.all(2 * PdfPageFormat.mm),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
              child: buildLabel(p),
            )
          );
        }
      }

      if (_paperFormat == 'thermal') {
        final format = const PdfPageFormat(50 * PdfPageFormat.mm, 25 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm);
        for (final labelWidget in allLabels) {
          pdf.addPage(
            pw.Page(
              pageFormat: format,
              build: (context) => labelWidget, // Ya viene en un Container, no importa. Pinta bien.
            ),
          );
        }
      } else {
        // Formato A4 (Grilla Múltiple)
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
            build: (pw.Context context) {
              return [
                pw.Wrap(
                  spacing: 5 * PdfPageFormat.mm,
                  runSpacing: 5 * PdfPageFormat.mm,
                  children: allLabels,
                )
              ];
            }
          ),
        );
      }

      final bytes = await pdf.save();

      // Abrir vista previa / diálogo de impresión nativa (Desktop o Web)
      if (mounted) {
         Navigator.of(context).pop(); // Cerrar el diálogo primero
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat defaultFormat) async => bytes,
        name: 'Lote_Etiquetas_Pos',
        dynamicLayout: false, // Forzar formato
      );

    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al generar PDF: $e');
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.print_outlined, color: Colors.blueGrey),
          SizedBox(width: 8),
          Text('Imprimir Etiquetas'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: SingleChildScrollView(
                child: Column(
                  children: widget.products.map((p) {
                    final qty = _quantities[p.id] ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.grey.shade50, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                                Text(p.barcode ?? p.internalCode, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: qty > 0 ? () => setState(() => _quantities[p.id] = qty - 1) : null,
                                icon: const Icon(Icons.remove_circle_outline),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              SizedBox(
                                width: 30,
                                child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                              IconButton(
                                onPressed: () => setState(() => _quantities[p.id] = qty + 1),
                                icon: const Icon(Icons.add_circle_outline),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Formato de Papel:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Térmica (Unitario)', style: TextStyle(fontSize: 11)),
                    value: 'thermal',
                    groupValue: _paperFormat,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onChanged: (val) => setState(() => _paperFormat = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Hoja A4 (Grilla)', style: TextStyle(fontSize: 11)),
                    value: 'a4',
                    groupValue: _paperFormat,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onChanged: (val) => setState(() => _paperFormat = val!),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _paperFormat == 'thermal' ? Colors.orange.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _paperFormat == 'thermal' ? Colors.orange.shade200 : Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _paperFormat == 'thermal' ? Icons.warning_amber_rounded : Icons.info_outline,
                      size: 20,
                      color: _paperFormat == 'thermal' ? Colors.orange.shade700 : Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _paperFormat == 'thermal'
                            ? 'Genera páginas de 50x25mm. Elija esta opción SOLO si posee una impresora térmica de etiquetas en rollo (ej: Zebra, Xprinter).'
                            : 'Genera una grilla en A4. Ideal para impresoras de tinta o láser sobre papel autoadhesivo troquelado estándar.',
                        style: TextStyle(
                          fontSize: 11,
                          color: _paperFormat == 'thermal' ? Colors.orange.shade900 : Colors.blue.shade900,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isGenerating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _isGenerating ? null : _generateAndPrint,
          icon: _isGenerating 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf, size: 18),
          label: Text(_isGenerating ? 'Generando...' : 'Generar PDF'),
        ),
      ],
    );
  }
}
