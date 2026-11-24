import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/logistics_provider.dart';
import '../../../../core/presentation/widgets/app_modal_shell.dart';
import '../../../../core/utils/snack_bar_service.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/presentation/widgets/thermal_receipt_widget.dart';
import '../../../../core/presentation/widgets/ticket_preview_dialog.dart';
import '../../../../core/utils/receipt_printer_service.dart';
import '../../../../core/providers/local_terminal_provider.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/settings/presentation/providers/settings_provider.dart';
import '../../../../features/logistics/services/delivery_note_pdf_service.dart';

class DispatchFulfillmentDialog extends StatefulWidget {
  final Map<String, dynamic> note;

  const DispatchFulfillmentDialog({super.key, required this.note});

  static Future<void> show(BuildContext context, Map<String, dynamic> note) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DispatchFulfillmentDialog(note: note),
    );
  }

  @override
  State<DispatchFulfillmentDialog> createState() =>
      _DispatchFulfillmentDialogState();
}

class _DispatchFulfillmentDialogState extends State<DispatchFulfillmentDialog> {
  final Map<int, double> _dispatchQuantities = {};
  final Map<int, TextEditingController> _qtyControllers = {};
  late List<dynamic> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.note['items'] ?? [];

    // Autocompletado Inteligente: Cargar por defecto la cantidad que falta entregar.
    // Si compró 10 y retiró 2, arranca en 8 (0 clics para el operario que despacha el resto).
    for (var item in _items) {
      final itemId = item['id'] as int;
      final purchased =
          double.tryParse(item['quantity_purchased'].toString()) ?? 0;
      final delivered =
          double.tryParse(item['quantity_delivered'].toString()) ?? 0;
      final remaining = purchased - delivered;
      final initialQty = remaining > 0 ? remaining : 0.0;

      _dispatchQuantities[itemId] = initialQty;
      _qtyControllers[itemId] =
          TextEditingController(text: _formatQty(initialQty));
    }
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllerText(int id, double value) {
    final ctrl = _qtyControllers[id];
    if (ctrl == null) return;
    final formatted = _formatQty(value);
    ctrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void _increment(int id, double maxAllowed) {
    final current = _dispatchQuantities[id] ?? 0;
    if (current < maxAllowed) {
      final next = (current + 1) > maxAllowed ? maxAllowed : (current + 1);
      setState(() {
        _dispatchQuantities[id] = next;
      });
      _syncControllerText(id, next);
    }
  }

  void _decrement(int id) {
    final current = _dispatchQuantities[id] ?? 0;
    if (current > 0) {
      final next = (current - 1) < 0 ? 0.0 : (current - 1);
      setState(() {
        _dispatchQuantities[id] = next;
      });
      _syncControllerText(id, next);
    }
  }

  void _onDecimalQtyChanged(int id, String raw, double maxAllowed) {
    final normalized = raw.trim().replaceAll(',', '.');
    double parsed = double.tryParse(normalized) ?? 0.0;
    if (parsed < 0) parsed = 0.0;
    final wasClamped = parsed > maxAllowed;
    if (wasClamped) parsed = maxAllowed;
    setState(() {
      _dispatchQuantities[id] = parsed;
    });
    if (wasClamped) {
      _syncControllerText(id, parsed);
    }
  }

  Future<void> _onConfirm() async {
    final sanitized = <int, double>{};
    for (final rawItem in _items) {
      final item = rawItem as Map;
      final itemId = item['id'] as int;
      final purchased =
          double.tryParse(item['quantity_purchased'].toString()) ?? 0.0;
      final delivered =
          double.tryParse(item['quantity_delivered'].toString()) ?? 0.0;
      final remaining = (purchased - delivered).clamp(0.0, double.infinity);
      final chosen =
          (_dispatchQuantities[itemId] ?? 0.0).clamp(0.0, remaining);
      sanitized[itemId] = chosen;
      _dispatchQuantities[itemId] = chosen;
    }

    // Validar que al menos se entregue algo
    bool hasItemsToDeliver = false;
    for (var q in sanitized.values) {
      if (q > 0) {
        hasItemsToDeliver = true;
        break;
      }
    }

    if (!hasItemsToDeliver) {
      SnackBarService.warning(
          context, 'Debe indicar al menos una cantidad a despachar.');
      return;
    }

    final provider = context.read<LogisticsProvider>();
    final success =
        await provider.confirmDispatch(widget.note['id'], sanitized);

    if (success) {
      if (mounted) {
        // Cerrar el dialog de despacho
        Navigator.pop(context);
        // Ofrecer imprimir el Remito de Despacho
        _showPostDispatchPrintDialog(context);
      }
    } else {
      if (mounted) {
        SnackBarService.error(
            context, provider.errorMessage ?? 'Error al confirmar despacho');
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
    return qty.toQty();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LogisticsProvider>();
    SettingsProvider? settingsProv;
    try {
      settingsProv = context.watch<SettingsProvider?>();
    } catch (_) {}
    final isDispatching = provider.isDispatching;

    return AppModalShell(
      title: 'Despachar Remito #${widget.note['id']}',
      subtitle: 'Definí las cantidades a entregar en este despacho',
      icon: Icons.local_shipping_outlined,
      accent: AppModalAccent.teal,
      maxWidth: 680,
      maxHeight: 680,
      expandBody: true,
      onClose: () {
        if (!isDispatching) Navigator.pop(context);
      },
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
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
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final item = Map<String, dynamic>.from(_items[index] as Map);
                  final itemId = item['id'] as int;
                  final saleMap = widget.note['sale'] is Map
                      ? Map<String, dynamic>.from(widget.note['sale'] as Map)
                      : null;
                  final pres = DeliveryNotePdfService.resolveItemPresentation(
                    item,
                    sale: saleMap,
                    businessSettings: settingsProv?.settings,
                  );
                  final productName = pres.displayName;

                  final purchased =
                      double.tryParse(item['quantity_purchased'].toString()) ??
                          0;
                  final delivered =
                      double.tryParse(item['quantity_delivered'].toString()) ??
                          0;
                  final remaining = purchased - delivered;

                  final currentQty = _dispatchQuantities[itemId] ?? 0;
                  final bool isCompleted = remaining <= 0;

                  if (isCompleted) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(productName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey)),
                      subtitle: Text(
                        pres.details != null
                            ? '${pres.details}\nÍtem completado'
                            : 'Ítem completado',
                        style: const TextStyle(
                            color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                      trailing:
                          const Icon(Icons.check_circle, color: Colors.green),
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
                              Text(productName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              if (pres.details != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  pres.details!,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                'Compró: ${_formatQty(purchased)} ${pres.unitLabel} | Ya Retiró: ${_formatQty(delivered)} ${pres.unitLabel} | Faltan: ${_formatQty(remaining)} ${pres.unitLabel}',
                                style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
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
                                onPressed: currentQty <= 0 || isDispatching
                                    ? null
                                    : () => _decrement(itemId),
                                icon: const Icon(Icons.remove),
                                color: Colors.red.shade700,
                                splashRadius: 24,
                              ),
                              if (pres.allowDecimals)
                                SizedBox(
                                  width: 96,
                                  child: TextField(
                                    key: ValueKey('dispatch_qty_input_$itemId'),
                                    controller: _qtyControllers[itemId],
                                    enabled: !isDispatching,
                                    textAlign: TextAlign.center,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*([.,]\d{0,4})?$')),
                                    ],
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 8),
                                      suffixText: pres.unitLabel,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    onChanged: (val) => _onDecimalQtyChanged(
                                        itemId, val, remaining),
                                  ),
                                )
                              else
                                Container(
                                  constraints:
                                      const BoxConstraints(minWidth: 48),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${_formatQty(currentQty)} ${pres.unitLabel}',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              IconButton(
                                onPressed:
                                    currentQty >= remaining || isDispatching
                                        ? null
                                        : () => _increment(itemId, remaining),
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
      footerActions: [
        TextButton(
          onPressed: isDispatching ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: isDispatching ? null : _onConfirm,
          icon: isDispatching
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(isDispatching ? 'PROCESANDO...' : 'CONFIRMAR DESPACHO',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
  State<_PostDispatchPrintSheet> createState() =>
      _PostDispatchPrintSheetState();
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
        businessSettings: settings,
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
      final prefs = await SharedPreferences.getInstance();
      final showPreview = prefs.getBool('show_preview_remito') ?? false;
      if (!mounted) return;

      SettingsProvider? sp;
      try {
        sp = context.read<SettingsProvider?>();
      } catch (_) {}
      final settings = sp?.settings;
      final localTerminal = context.read<LocalTerminalProvider>();
      final isNarrow = localTerminal.printerFormat == 'thermal_58';
      final paperWidth =
          isNarrow ? ThermalPaperWidth.mm58 : ThermalPaperWidth.mm80;
      ThermalPaperWidth selectedWidth = paperWidth;
      final sale = widget.note['sale'] ?? {};
      final customerName = sale['customer']?['name'];
      final vendorName = sale['user']?['name'];
      final currentUser = context.read<AuthProvider>().currentUser;
      final dispatcherName = currentUser?['name'] ?? 'SISTEMA';

      final deliveredList = widget.deliveredNow.entries
          .map((e) => {'id': e.key, 'delivered_now': e.value})
          .toList();

      if (showPreview) {
        final items = (widget.note['items'] as List? ?? []);
        final now = DateTime.now().toLocal();
        String pad(int n) => n.toString().padLeft(2, '0');
        final fecha =
            '${pad(now.day)}/${pad(now.month)}/${now.year} ${pad(now.hour)}:${pad(now.minute)}';
        final remNum = widget.note['id'].toString().padLeft(6, '0');

        List<TicketLine> buildPreviewForWidth(bool narrow) {
          List<TicketLine> buildCopy(String copyLabel) => [
                if (settings?.companyName != null)
                  TicketLine(settings!.companyName!.toUpperCase(),
                      align: TicketAlign.center, isBold: true, isLarge: true),
                if (settings?.address != null && settings!.address!.isNotEmpty)
                  TicketLine(settings.address!, align: TicketAlign.center),
                if (settings?.taxId != null && settings!.taxId!.isNotEmpty)
                  TicketLine('CUIT: ${settings.taxId}',
                      align: TicketAlign.center, isBold: true),
                const TicketLine.hr(bold: true),
                const TicketLine('REMITO DE DESPACHO',
                    align: TicketAlign.center, isBold: true),
                TicketLine('[ $copyLabel ]', align: TicketAlign.center),
                TicketLine(
                    narrow
                        ? 'DOC. NO VALIDO COMO FACTURA'
                        : 'DOCUMENTO NO VÁLIDO COMO FACTURA',
                    align: TicketAlign.center),
                const TicketLine.hr(),
                TicketLine('REM Nro: $remNum', isBold: true),
                TicketLine('FECHA: $fecha'),
                TicketLine('CLIENTE: ${customerName ?? 'Consumidor Final'}',
                    isBold: true),
                if (vendorName != null)
                  TicketLine('VENDIO: ${vendorName.toUpperCase()}'),
                TicketLine('DESPACHO: ${dispatcherName.toUpperCase()}'),
                const TicketLine.hr(),
                ...deliveredList.expand((d) {
                  final item = items.firstWhere((i) => i['id'] == d['id'],
                      orElse: () => null);
                  if (item == null) return [const TicketLine.space()];
                  final pres = DeliveryNotePdfService.resolveItemPresentation(
                    Map<String, dynamic>.from(item as Map),
                    sale: sale is Map ? Map<String, dynamic>.from(sale) : null,
                    businessSettings: settings,
                  );
                  final name = pres.displayName.toUpperCase();
                  final purchased =
                      double.parse(item['quantity_purchased'].toString());
                  final deliveredBefore =
                      double.parse(item['quantity_delivered'].toString());
                  final deliveredNow = (d['delivered_now'] as num).toDouble();
                  final remaining = (purchased - deliveredBefore - deliveredNow)
                      .clamp(0.0, double.infinity);
                  return [
                    TicketLine(name, isBold: true),
                    if (pres.details != null) TicketLine(pres.details!),
                    TicketLine(
                        'Entregando: ${deliveredNow.toQty()} ${pres.unitLabel} | Saldo: ${remaining.toQty()} ${pres.unitLabel}'),
                    const TicketLine.space(),
                  ];
                }),
                const TicketLine.hr(bold: true),
              ];

          return [
            ...buildCopy('COPIA CLIENTE'),
            const TicketLine.space(),
            TicketLine(
                narrow
                    ? '✂ - - - - CORTE - - - - ✂'
                    : '✂ - - - - - - - CORTE - - - - - - - ✂',
                align: TicketAlign.center),
            const TicketLine.space(),
            ...buildCopy('COPIA DESPACHANTE - ORIGINAL'),
            TicketLine(
                narrow
                    ? 'FIRMA CONFORMIDAD CLIENTE:'
                    : 'FIRMA CONFORMIDAD DEL CLIENTE:',
                isBold: true),
            TicketLine(narrow
                ? '____________________________'
                : '___________________________________'),
            TicketLine(narrow
                ? 'Aclaración: ________________'
                : 'Aclaración: ________________________'),
            TicketLine(narrow
                ? 'DNI / CUIT: ________________'
                : 'DNI / CUIT: ________________________'),
          ];
        }

        final confirmed = await TicketPreviewDialog.show(
          context,
          title:
              'Remito de Despacho #${widget.note['id']} (${isNarrow ? "58mm" : "80mm"})',
          paperWidth: paperWidth,
          onConfirmPrintWithWidth: (w) => selectedWidth = w,
          linesBuilder: (w) =>
              buildPreviewForWidth(w == ThermalPaperWidth.mm58),
        );
        if (!confirmed || !mounted) return;
      }

      await ReceiptPrinterService.instance.printDeliveryNoteTicket(
        note: widget.note,
        deliveredItemsData: deliveredList,
        settings: settings!,
        localTerminal: localTerminal,
        customerName: customerName,
        vendorName: vendorName,
        dispatcherName: dispatcherName,
        paperSizeOverride:
            selectedWidth == ThermalPaperWidth.mm58 ? '58mm' : '80mm',
      );

      if (mounted) {
        SnackBarService.success(
            context, '¡Remito de despacho impreso con éxito!');
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
    // Etiqueta dinámica según el formato de papel de esta terminal
    final paperLabel =
        context.watch<LocalTerminalProvider>().pdfPaperSize == 'letter'
            ? 'Carta'
            : 'A4';

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
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(
                      '¿Deseás imprimir el Remito de Despacho para que el cliente firme?',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.preview, color: Colors.blue.shade700, size: 26),
            ),
            title: Text('Ver Remito $paperLabel (Vista Previa)',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                'Abre el doble Remito de Despacho en $paperLabel — ORIGINAL y DUPLICADO'),
            trailing: _isPrinting
                ? const CircularProgressIndicator()
                : const Icon(Icons.chevron_right),
            onTap: _previewA4,
          ),
          const Divider(),
          ListTile(
            enabled: !_isPrinting,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.receipt_long,
                  color: Colors.green.shade700, size: 26),
            ),
            title: const Text('Imprimir Remito Térmico',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                'Imprime 2 copias: una para el cliente y una con firma para el despachante'),
            trailing: _isPrinting
                ? const CircularProgressIndicator()
                : const Icon(Icons.chevron_right),
            onTap: _printThermal,
          ),
          const Divider(),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.close, color: Colors.grey.shade600, size: 26),
            ),
            title: const Text('No imprimir ahora'),
            subtitle: const Text(
                'Podés reimprimir más tarde desde la tarjeta del remito'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
