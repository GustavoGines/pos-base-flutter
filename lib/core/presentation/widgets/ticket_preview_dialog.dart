import 'package:flutter/material.dart';
import 'thermal_receipt_widget.dart';

/// Diálogo de Vista Previa del ticket en formato papel térmico simulado (58mm y 80mm).
/// Soporta tanto [ThermalReceiptWidget] moderno como la lista de [TicketLine],
/// e incluye selector interactivo 58mm / 80mm en la cabecera.
class TicketPreviewDialog extends StatefulWidget {
  final String title;
  final List<TicketLine> lines;
  final List<TicketLine> Function(ThermalPaperWidth width)? linesBuilder;
  final Widget? receiptWidget;
  final Widget Function(ThermalPaperWidth width)? receiptBuilder;
  final ThermalPaperWidth? paperWidth;
  final VoidCallback? onConfirmPrint;
  final void Function(ThermalPaperWidth selectedWidth)? onConfirmPrintWithWidth;

  const TicketPreviewDialog({
    super.key,
    required this.title,
    this.lines = const [],
    this.linesBuilder,
    this.receiptWidget,
    this.receiptBuilder,
    this.paperWidth,
    this.onConfirmPrint,
    this.onConfirmPrintWithWidth,
  });

  /// Muestra el dialog y devuelve true si el usuario confirmó la impresión.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    List<TicketLine>? lines,
    List<TicketLine> Function(ThermalPaperWidth width)? linesBuilder,
    Widget? receiptWidget,
    Widget Function(ThermalPaperWidth width)? receiptBuilder,
    ThermalPaperWidth? paperWidth,
    VoidCallback? onConfirmPrint,
    void Function(ThermalPaperWidth selectedWidth)? onConfirmPrintWithWidth,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => TicketPreviewDialog(
            title: title,
            lines: lines ?? const [],
            linesBuilder: linesBuilder,
            receiptWidget: receiptWidget,
            receiptBuilder: receiptBuilder,
            paperWidth: paperWidth,
            onConfirmPrint: onConfirmPrint ?? () => Navigator.pop(ctx, true),
            onConfirmPrintWithWidth: onConfirmPrintWithWidth,
          ),
        ) ??
        false;
  }

  @override
  State<TicketPreviewDialog> createState() => _TicketPreviewDialogState();
}

class _TicketPreviewDialogState extends State<TicketPreviewDialog> {
  late ThermalPaperWidth _selectedWidth;

  @override
  void initState() {
    super.initState();
    _selectedWidth = widget.paperWidth ?? ThermalPaperWidth.mm80;
  }

  @override
  Widget build(BuildContext context) {
    final effectivePaperWidth = _selectedWidth.logicalWidth;
    final is58 = _selectedWidth == ThermalPaperWidth.mm58;
    final effectiveLines = widget.linesBuilder != null
        ? widget.linesBuilder!(_selectedWidth)
        : widget.lines;
    final effectiveReceiptWidget = widget.receiptBuilder != null
        ? widget.receiptBuilder!(_selectedWidth)
        : widget.receiptWidget;

    final effectiveTitle = widget.title
        .replaceAll('(58mm)', '(${is58 ? "58mm" : "80mm"})')
        .replaceAll('(80mm)', '(${is58 ? "58mm" : "80mm"})')
        .replaceAll(' 58mm', ' ${is58 ? "58mm" : "80mm"}')
        .replaceAll(' 80mm', ' ${is58 ? "58mm" : "80mm"}');

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 740),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.white70, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      effectiveTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Selector rápido 58mm / 80mm
                  Flexible(
                    flex: 0,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade700),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildWidthChip('58mm', ThermalPaperWidth.mm58),
                            _buildWidthChip('80mm', ThermalPaperWidth.mm80),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),

            // Ticket simulado en papel térmico
            Flexible(
              child: Container(
                color: const Color(0xFFEFEFEF),
                width: double.infinity,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: effectivePaperWidth,
                        child: effectiveReceiptWidget ??
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              width: effectivePaperWidth,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: is58 ? 8 : 14,
                                vertical: 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: effectiveLines
                                    .map((line) => _buildLine(line, is58: is58))
                                    .toList(),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Cancelar'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        if (widget.onConfirmPrintWithWidth != null) {
                          widget.onConfirmPrintWithWidth!(_selectedWidth);
                        }
                        if (widget.onConfirmPrint != null) {
                          widget.onConfirmPrint!();
                        } else {
                          Navigator.pop(context, true);
                        }
                      },
                      icon: const Icon(Icons.print, size: 18),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Imprimir'),
                            const SizedBox(width: 4),
                            Text('(${is58 ? "58mm" : "80mm"})'),
                          ],
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWidthChip(String label, ThermalPaperWidth width) {
    final selected = _selectedWidth == width;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _selectedWidth = width),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade400,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLine(TicketLine line, {bool is58 = false}) {
    final baseFontSize = is58 ? 9.5 : 11.0;
    final boldFontSize = is58 ? 10.5 : 12.0;
    final largeFontSize = is58 ? 12.5 : 14.5;
    switch (line.type) {
      case TicketLineType.divider:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Divider(
            color: Colors.grey.shade400,
            thickness: line.isBold ? 2 : 1,
          ),
        );
      case TicketLineType.spacer:
        return const SizedBox(height: 8);
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            mainAxisAlignment: line.align == TicketAlign.center
                ? MainAxisAlignment.center
                : line.align == TicketAlign.right
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.spaceBetween,
            children: line.rightText != null
                ? [
                    Expanded(
                      child: Text(
                        line.text,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: line.isLarge ? largeFontSize : baseFontSize,
                          fontWeight: line.isBold ? FontWeight.bold : FontWeight.normal,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          line.rightText!,
                          style: TextStyle(
                            fontSize: line.isLarge ? largeFontSize : baseFontSize,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ]
                : [
                    Expanded(
                      child: Text(
                        line.text,
                        textAlign: line.align == TicketAlign.center
                            ? TextAlign.center
                            : line.align == TicketAlign.right
                                ? TextAlign.right
                                : TextAlign.left,
                        style: TextStyle(
                          fontSize: line.isLarge
                              ? (is58 ? 13.5 : 16.0)
                              : (line.isBold ? boldFontSize : baseFontSize),
                          fontWeight: line.isBold ? FontWeight.bold : FontWeight.normal,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
          ),
        );
    }
  }
}

enum TicketLineType { text, divider, spacer }
enum TicketAlign { left, center, right }

class TicketLine {
  final String text;
  final String? rightText;
  final TicketLineType type;
  final TicketAlign align;
  final bool isBold;
  final bool isLarge;

  const TicketLine(
    this.text, {
    this.rightText,
    this.type = TicketLineType.text,
    this.align = TicketAlign.left,
    this.isBold = false,
    this.isLarge = false,
  });

  /// Línea separadora ═══
  const TicketLine.hr({bool bold = false})
      : text = '',
        rightText = null,
        type = TicketLineType.divider,
        align = TicketAlign.left,
        isBold = bold,
        isLarge = false;

  /// Espacio en blanco
  const TicketLine.space()
      : text = '',
        rightText = null,
        type = TicketLineType.spacer,
        align = TicketAlign.left,
        isBold = false,
        isLarge = false;
}
