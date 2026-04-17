import 'package:flutter/material.dart';

/// Diálogo de Vista Previa del ticket en formato papel térmico simulado.
/// Recibe una lista de [TicketLine] con texto e indicador de estilo.
class TicketPreviewDialog extends StatelessWidget {
  final String title;
  final List<TicketLine> lines;
  final VoidCallback? onConfirmPrint;

  const TicketPreviewDialog({
    Key? key,
    required this.title,
    required this.lines,
    this.onConfirmPrint,
  }) : super(key: key);

  /// Muestra el dialog y devuelve true si el usuario confirmó la impresión.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required List<TicketLine> lines,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => TicketPreviewDialog(
            title: title,
            lines: lines,
            onConfirmPrint: () => Navigator.pop(ctx, true),
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.white70, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),

            // Ticket simulado en papel térmico
            Flexible(
              child: Container(
                color: const Color(0xFFF5F5F5),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: lines.map((line) => _buildLine(line)).toList(),
                    ),
                  ),
                ),
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onConfirmPrint,
                      icon: const Icon(Icons.print),
                      label: const Text('Imprimir'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
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

  Widget _buildLine(TicketLine line) {
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
                        style: TextStyle(
                          fontSize: line.isLarge ? 14 : 11,
                          fontWeight: line.isBold ? FontWeight.bold : FontWeight.normal,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Text(
                      line.rightText!,
                      style: TextStyle(
                        fontSize: line.isLarge ? 14 : 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
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
                          fontSize: line.isLarge ? 16 : (line.isBold ? 12 : 11),
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
