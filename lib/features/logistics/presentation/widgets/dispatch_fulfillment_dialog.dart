import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/logistics_provider.dart';
import '../../../../core/utils/snack_bar_service.dart';
import '../../../../core/utils/receipt_printer_service.dart';
import '../../../../core/providers/local_terminal_provider.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/settings/presentation/providers/settings_provider.dart';
import '../../../../features/logistics/services/delivery_note_pdf_service.dart';

class DispatchFulfillmentDialog extends StatefulWidget {
  final Map<String, dynamic> note;

  const DispatchFulfillmentDialog({Key? key, required this.note}) : super(key: key);

  static Future<void> show(BuildContext context, Map<String, dynamic> note) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DispatchFulfillmentDialog(note: note),
    );
  }

  @override
  State<DispatchFulfillmentDialog> createState() => _DispatchFulfillmentDialogState();
}

class _DispatchFulfillmentDialogState extends State<DispatchFulfillmentDialog> {
  final Map<int, double> _dispatchQuantities = {};
  late List<dynamic> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.note['items'] ?? [];
    
    // Autocompletado Inteligente: Cargar por defecto la cantidad que falta entregar.
    // Si compró 10 y retiró 2, arranca en 8 (0 clics para el operario que despacha el resto).
    for (var item in _items) {
      final itemId = item['id'] as int;
      final purchased = double.tryParse(item['quantity_purchased'].toString()) ?? 0;
      final delivered = double.tryParse(item['quantity_delivered'].toString()) ?? 0;
      final remaining = purchased - delivered;
      
      _dispatchQuantities[itemId] = remaining > 0 ? remaining : 0;
    }
  }

  void _increment(int id, double maxAllowed) {
    final current = _dispatchQuantities[id] ?? 0;
    if (current < maxAllowed) {
      setState(() {
        _dispatchQuantities[id] = current + 1;
        // Evitar desborde decimal por sumas inexactas
        if (_dispatchQuantities[id]! > maxAllowed) {
          _dispatchQuantities[id] = maxAllowed;
        }
      });
    }
  }

  void _decrement(int id) {
    final current = _dispatchQuantities[id] ?? 0;
    if (current > 0) {
      setState(() {
        _dispatchQuantities[id] = current - 1;
        if (_dispatchQuantities[id]! < 0) {
          _dispatchQuantities[id] = 0;
        }
      });
    }
  }

  Future<void> _onConfirm() async {
    // Validar que al menos se entregue algo
    bool hasItemsToDeliver = false;
    for (var q in _dispatchQuantities.values) {
      if (q > 0) {
        hasItemsToDeliver = true;
        break;
      }
    }

    if (!hasItemsToDeliver) {
      SnackBarService.warning(context, 'Debe indicar al menos una cantidad a despachar.');
      return;
    }

    final provider = context.read<LogisticsProvider>();
    final success = await provider.confirmDispatch(widget.note['id'], _dispatchQuantities);

    if (success) {
      if (mounted) {
        // Cerrar el dialog de despacho
        Navigator.pop(context);
        // Ofrecer imprimir el Remito de Despacho
        _showPostDispatchPrintDialog(context);
      }
    } else {
      if (mounted) {
        SnackBarService.error(context, provider.errorMessage ?? 'Error al confirmar despacho');
      }
    }
  }

  /// Muestra el Bottom Sheet de impresión del Remito DESPUÉS de confirmar el despacho.
  void _showPostDispatchPrintDialog(BuildContext ctx) {
    // Reconstruir el mapa de cantidades para pasarlo al PDF
    final deliveredNowForPdf = <int, double>{};
    for (final entry in _dispatchQuantities.entries) {
      if (entry.value > 0) deliveredNowForPdf[entry.key] = entry.value;
    }

    showModalBottomSheet(
      context: ctx,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _PostDispatchPrintSheet(
        note: widget.note,
        deliveredNow: deliveredNowForPdf,
      ),
    );
  }

  String _formatQty(double qty) {
    return qty.truncateToDouble() == qty ? qty.toInt().toString() : qty.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LogisticsProvider>();
    final isDispatching = provider.isDispatching;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.inventory, color: Colors.blue.shade700, size: 32),
          const SizedBox(width: 12),
          Text('Despachar Remito #${widget.note['id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 650,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cantidades a entregar AHORA. El sistema carga automáticamente lo restante. Puede ajustarlo si es una entrega parcial.',
                      style: TextStyle(color: Colors.blue, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final itemId = item['id'] as int;
                  final product = item['product'] ?? {};
                  final productName = product['name'] ?? 'Producto Desconocido';
                  
                  final purchased = double.tryParse(item['quantity_purchased'].toString()) ?? 0;
                  final delivered = double.tryParse(item['quantity_delivered'].toString()) ?? 0;
                  final remaining = purchased - delivered;
                  
                  final currentQty = _dispatchQuantities[itemId] ?? 0;
                  final bool isCompleted = remaining <= 0;

                  if (isCompleted) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(productName, style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.lineThrough, color: Colors.grey)),
                      subtitle: const Text('Ítem completado', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.check_circle, color: Colors.green),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 6),
                              Text(
                                'Compró: ${_formatQty(purchased)} | Ya Retiró: ${_formatQty(delivered)} | Faltan: ${_formatQty(remaining)}',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: currentQty <= 0 || isDispatching ? null : () => _decrement(itemId),
                                icon: const Icon(Icons.remove),
                                color: Colors.red.shade700,
                                splashRadius: 24,
                              ),
                              Container(
                                width: 45,
                                alignment: Alignment.center,
                                child: Text(
                                  _formatQty(currentQty),
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                onPressed: currentQty >= remaining || isDispatching ? null : () => _increment(itemId, remaining),
                                icon: const Icon(Icons.add),
                                color: Colors.green.shade700,
                                splashRadius: 24,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      actions: [
        TextButton(
          onPressed: isDispatching ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 16)),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: isDispatching ? null : _onConfirm,
          icon: isDispatching 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(isDispatching ? 'PROCESANDO...' : 'CONFIRMAR DESPACHO', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// Bottom Sheet de impresión post-despacho
// ─────────────────────────────────────────────────────────
class _PostDispatchPrintSheet extends StatefulWidget {
  final Map<String, dynamic> note;
  final Map<int, double> deliveredNow;

  const _PostDispatchPrintSheet({
    required this.note,
    required this.deliveredNow,
  });

  @override
  State<_PostDispatchPrintSheet> createState() => _PostDispatchPrintSheetState();
}

class _PostDispatchPrintSheetState extends State<_PostDispatchPrintSheet> {
  bool _isPrinting = false;

  Future<void> _previewA4() async {
    setState(() => _isPrinting = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      final sale = widget.note['sale'] ?? {};
      final vendorName = sale['user']?['name'];
      final currentUser = context.read<AuthProvider>().currentUser;
      final dispatcherName = currentUser?['name'] ?? 'SISTEMA';

      await DeliveryNotePdfService.preview(
        context: context,
        note: widget.note,
        businessName: settings?.companyName ?? 'Mi Negocio',
        businessAddress: settings?.address,
        businessPhone: settings?.phone,
        businessTaxId: settings?.taxId,
        deliveredNow: widget.deliveredNow,
        vendorName: vendorName,
        dispatcherName: dispatcherName,
        paperSize: context.read<LocalTerminalProvider>().pdfPaperSize,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) SnackBarService.error(context, 'Error al generar PDF: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _printThermal() async {
    setState(() => _isPrinting = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      final sale = widget.note['sale'] ?? {};
      final customerName = sale['customer']?['name'];
      final vendorName = sale['user']?['name'];
      final currentUser = context.read<AuthProvider>().currentUser;
      final dispatcherName = currentUser?['name'] ?? 'SISTEMA';

      final deliveredList = widget.deliveredNow.entries
          .map((e) => {'id': e.key, 'delivered_now': e.value})
          .toList();

      await ReceiptPrinterService.instance.printDeliveryNoteTicket(
        note: widget.note,
        deliveredItemsData: deliveredList,
        settings: settings!,
        localTerminal: context.read<LocalTerminalProvider>(),
        customerName: customerName,
        vendorName: vendorName,
        dispatcherName: dispatcherName,
      );

      if (mounted) {
        SnackBarService.success(context, '¡Remito de despacho impreso con éxito!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) SnackBarService.error(context, 'Error al imprimir: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('¡Despacho confirmado!',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(
                      '¿Deseás imprimir el Remito de Despacho para que el cliente firme?',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),

          ListTile(
            enabled: !_isPrinting,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.preview, color: Colors.blue.shade700, size: 26),
            ),
            title: const Text('Ver Remito A4 (Vista Previa)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Abre el doble Remito de Despacho en A4 — ORIGINAL y DUPLICADO'),
            trailing: _isPrinting ? const CircularProgressIndicator() : const Icon(Icons.chevron_right),
            onTap: _previewA4,
          ),

          const Divider(),

          ListTile(
            enabled: !_isPrinting,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.receipt_long, color: Colors.green.shade700, size: 26),
            ),
            title: const Text('Imprimir Remito Térmico', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Imprime 2 copias: una para el cliente y una con firma para el despachante'),
            trailing: _isPrinting ? const CircularProgressIndicator() : const Icon(Icons.chevron_right),
            onTap: _printThermal,
          ),

          const Divider(),

          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.close, color: Colors.grey.shade600, size: 26),
            ),
            title: const Text('No imprimir ahora'),
            subtitle: const Text('Podés reimprimir más tarde desde la tarjeta del remito'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
