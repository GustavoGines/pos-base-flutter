import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'quote_thermal_receipt_widget.dart';

/// Diálogo de Vista Previa interactiva del Ticket Térmico de Presupuestos
/// que permite previsualizar fielmente el documento en 58mm y 80mm,
/// conmutar entre ambos formatos en tiempo real y enviarlo a imprimir.
class QuoteThermalPreviewDialog extends StatefulWidget {
  final Quote quote;
  final BusinessSettings? settings;
  final String vendorName;
  final ThermalPaperWidth initialPaperWidth;

  const QuoteThermalPreviewDialog({
    super.key,
    required this.quote,
    this.settings,
    required this.vendorName,
    this.initialPaperWidth = ThermalPaperWidth.mm80,
  });

  /// Muestra el modal de vista previa y devuelve true si se ejecutó la impresión.
  static Future<bool> show(
    BuildContext context, {
    required Quote quote,
    required BusinessSettings? settings,
    required String vendorName,
    ThermalPaperWidth? initialPaperWidth,
  }) async {
    final terminal = context.read<LocalTerminalProvider>();
    final defaultWidth = initialPaperWidth ??
        (terminal.printerFormat == 'thermal_58'
            ? ThermalPaperWidth.mm58
            : ThermalPaperWidth.mm80);

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => QuoteThermalPreviewDialog(
            quote: quote,
            settings: settings,
            vendorName: vendorName,
            initialPaperWidth: defaultWidth,
          ),
        ) ??
        false;
  }

  @override
  State<QuoteThermalPreviewDialog> createState() =>
      _QuoteThermalPreviewDialogState();
}

class _QuoteThermalPreviewDialogState extends State<QuoteThermalPreviewDialog> {
  late ThermalPaperWidth _currentWidth;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _currentWidth = widget.initialPaperWidth;
  }

  Future<void> _handlePrint() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);

    try {
      final terminal = context.read<LocalTerminalProvider>();
      if (terminal.printerConnection.toLowerCase() == 'none' ||
          terminal.printerNameOrIp.trim().isEmpty) {
        if (mounted) {
          setState(() => _isPrinting = false);
          SnackBarService.warning(
            context,
            'La impresora térmica está desactivada o sin puerto/IP configurado en esta terminal.',
          );
        }
        return;
      }

      final paperOverride = _currentWidth == ThermalPaperWidth.mm58
          ? PaperSize.mm58
          : PaperSize.mm80;

      await ReceiptPrinterService.instance.printQuoteTicket(
        quote: widget.quote,
        settings: widget.settings ?? BusinessSettings(),
        localTerminal: terminal,
        vendorName: widget.vendorName,
        paperSizeOverride: paperOverride,
      );

      if (mounted) {
        SnackBarService.success(
          context,
          'Ticket térmico (${_currentWidth == ThermalPaperWidth.mm58 ? "58mm" : "80mm"}) enviado a la impresora.',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPrinting = false);
        SnackBarService.error(context, 'Error al imprimir ticket: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final is58 = _currentWidth == ThermalPaperWidth.mm58;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header con Título y Selector 58mm / 80mm ─────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long,
                    color: Colors.white70,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ticket ${widget.quote.quoteNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Conmutador interactivo 58mm / 80mm
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFormatChip(
                          label: '58mm',
                          isSelected: is58,
                          onTap: () {
                            if (!is58) {
                              setState(() =>
                                  _currentWidth = ThermalPaperWidth.mm58);
                            }
                          },
                        ),
                        const SizedBox(width: 2),
                        _buildFormatChip(
                          label: '80mm',
                          isSelected: !is58,
                          onTap: () {
                            if (is58) {
                              setState(() =>
                                  _currentWidth = ThermalPaperWidth.mm80);
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),

            // ── Área de Papel Térmico Simulado ──────────────────────────────
            Flexible(
              child: Container(
                color: const Color(0xFFEFEFEF),
                width: double.infinity,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width: _currentWidth.logicalWidth,
                      child: QuoteThermalReceiptWidget(
                        paperWidth: _currentWidth,
                        quote: widget.quote,
                        businessSettings: widget.settings,
                        vendorName: widget.vendorName,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Barra Inferior de Acciones ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
              ),
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
                      onPressed: _isPrinting ? null : _handlePrint,
                      icon: _isPrinting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.print_rounded, size: 18),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isPrinting
                              ? 'Imprimiendo...'
                              : 'Imprimir Ticket (${is58 ? "58mm" : "80mm"})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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

  Widget _buildFormatChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
