import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/services/quote_pdf_service.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'quote_thermal_preview_dialog.dart';

/// Diálogo modal post-generación de presupuesto que ofrece:
/// 1. Imprimir Ticket térmico directamente.
/// 2. Ver / Imprimir PDF (A4 o Carta según configuración de terminal).
/// 3. Compartir por WhatsApp.
class QuoteSuccessDialog extends StatefulWidget {
  final Quote quote;
  final String businessName;
  final String? businessAddress;
  final String? businessPhone;
  final String? customerPhone;
  final String vendorName;

  const QuoteSuccessDialog({
    super.key,
    required this.quote,
    required this.businessName,
    this.businessAddress,
    this.businessPhone,
    this.customerPhone,
    required this.vendorName,
  });

  @override
  State<QuoteSuccessDialog> createState() => _QuoteSuccessDialogState();
}

class _QuoteSuccessDialogState extends State<QuoteSuccessDialog> {
  bool _generatingPdf = false;
  String? _savedPath;
  final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);

  Future<void> _printTicket() async {
    try {
      final settings = context.read<SettingsProvider>().settings;
      final localTerminal = context.read<LocalTerminalProvider>();
      final initialWidth = localTerminal.printerFormat == 'thermal_58'
          ? ThermalPaperWidth.mm58
          : ThermalPaperWidth.mm80;

      final printed = await QuoteThermalPreviewDialog.show(
        context,
        quote: widget.quote,
        settings: settings,
        vendorName: widget.vendorName,
        initialPaperWidth: initialWidth,
      );

      if (printed && mounted) {
        Navigator.pop(context); // Cierra el modal exitosamente al confirmar la impresión
      }
    } catch (e) {
      if (mounted) SnackBarService.error(context, e.toString());
    }
  }

  Future<void> _generateAndSave() async {
    setState(() => _generatingPdf = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      final paperSize = context.read<LocalTerminalProvider>().pdfPaperSize;
      final logoUrl = settings?.effectiveLogoUrl;
      final path = await QuotePdfService.generateAndShare(
        quote: widget.quote,
        businessName: widget.businessName,
        businessAddress: widget.businessAddress,
        businessPhone: widget.businessPhone,
        businessSettings: settings,
        vendorName: widget.vendorName,
        logoUrl: logoUrl,
        paperSize: paperSize,
      );
      if (mounted) setState(() { _generatingPdf = false; _savedPath = path; });
    } catch (e) {
      if (mounted) {
        setState(() => _generatingPdf = false);
        SnackBarService.error(context, e.toString());
      }
    }
  }

  Future<void> _preview() async {
    final settings = context.read<SettingsProvider>().settings;
    final paperSize = context.read<LocalTerminalProvider>().pdfPaperSize;
    final logoUrl = settings?.effectiveLogoUrl;
    await QuotePdfService.preview(
      context: context,
      quote: widget.quote,
      businessName: widget.businessName,
      businessAddress: widget.businessAddress,
      businessPhone: widget.businessPhone,
      businessSettings: settings,
      vendorName: widget.vendorName,
      logoUrl: logoUrl,
      paperSize: paperSize,
    );
  }

  Future<void> _openWhatsApp() async {
    await QuotePdfService.openWhatsApp(
      quote: widget.quote,
      businessName: widget.businessName,
      phone: widget.customerPhone,
      savedPdfPath: _savedPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Etiqueta dinámica según el tamaño de papel configurado en esta terminal
    final paperLabel = context.watch<LocalTerminalProvider>().pdfPaperSize == 'letter' ? 'Carta' : 'A4';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header azul índigo con resumen
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.indigo.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 48),
                  const SizedBox(height: 8),
                  const Text('¡Presupuesto Generado!',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(widget.quote.quoteNumber,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  Text(fmt.format(widget.quote.total),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 🖨️ Botón Primario: Imprimir Ticket (Térmica)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _printTicket,
                    icon: const Icon(Icons.print_rounded, size: 28),
                    label: const Text('Imprimir Ticket (Térmica)', style: TextStyle(fontSize: 16)),
                  ),
                  
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  // Botones Secundarios: PDF y WhatsApp
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            foregroundColor: Colors.indigo.shade700,
                          ),
                          onPressed: _preview,
                          icon: const Icon(Icons.picture_as_pdf_rounded),
                          label: Text('Ver PDF ($paperLabel)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _generatingPdf 
                          ? const Center(child: CircularProgressIndicator()) 
                          : OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                foregroundColor: const Color(0xFF25D366),
                              ),
                              onPressed: () async {
                                if (_savedPath == null) await _generateAndSave();
                                await _openWhatsApp();
                              },
                              icon: const Icon(Icons.rocket_launch_rounded),
                              label: const Text('WhatsApp'),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
