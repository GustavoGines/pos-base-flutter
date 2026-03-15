import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../domain/entities/product.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

class PrintLabelsDialog extends StatefulWidget {
  final Product product;
  final String companyName;

  const PrintLabelsDialog({
    Key? key,
    required this.product,
    this.companyName = 'Mi Negocio POS', // Podría venir del SettingsProvider
  }) : super(key: key);

  @override
  State<PrintLabelsDialog> createState() => _PrintLabelsDialogState();
}

class _PrintLabelsDialogState extends State<PrintLabelsDialog> {
  int _quantity = 1;
  bool _isGenerating = false;

  Future<void> _generateAndPrint() async {
    setState(() => _isGenerating = true);

    try {
      final pdf = pw.Document();
      
      // Intentar usar el código de barras del producto, si no, código interno
      final String codeToPrint = (widget.product.barcode != null && widget.product.barcode!.isNotEmpty)
          ? widget.product.barcode!
          : widget.product.internalCode;

      // 1. Elegimos el formato compacto (Ej: estándar térmica 50x25 mm)
      // Ajustamos márgenes muy reducidos para no desperdiciar espacio.
      // 50 mm = 141.7 pt; 25 mm = 70.8 pt (1 mm = 2.83 pt aprx)
      final format = const PdfPageFormat(50 * PdfPageFormat.mm, 25 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm);

      for (int i = 0; i < _quantity; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: format,
            build: (context) {
              return pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Nombre del Negocio (Muy pequeño)
                  pw.Text(
                    widget.companyName.toUpperCase(),
                    style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                    maxLines: 1,
                  ),
                  pw.SizedBox(height: 1),
                  
                  // Nombre del Producto (Cortado si es muy largo)
                  pw.Text(
                    widget.product.name,
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),
                  pw.SizedBox(height: 1),
                  
                  // Precio (Destacado)
                  pw.Text(
                    '\$${widget.product.sellingPrice.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ),
                  
                  pw.Spacer(),

                  // Código de barras
                  pw.SizedBox(
                    height: 16,
                    width: 100,
                    child: pw.BarcodeWidget(
                      barcode: (codeToPrint.length == 13 && double.tryParse(codeToPrint) != null) 
                                ? pw.Barcode.ean13()   // Asumimos EAN-13 si son 13 dígitos
                                : pw.Barcode.code128(), // De lo contrario code128 soporta alfanumérico
                      data: codeToPrint,
                      drawText: true,
                      textStyle: const pw.TextStyle(fontSize: 6),
                      margin: pw.EdgeInsets.zero,
                    ),
                  ),
                ],
              );
            },
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
        name: 'Etiquetas_${widget.product.name.replaceAll(' ', '_')}',
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
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('¿Cuántas etiquetas desea imprimir?'),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Expanded(
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
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
