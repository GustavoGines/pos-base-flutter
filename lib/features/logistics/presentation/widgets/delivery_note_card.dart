import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/core/presentation/widgets/ticket_preview_dialog.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/logistics/services/delivery_note_pdf_service.dart';
import 'dispatch_fulfillment_dialog.dart';

class DeliveryNoteCard extends StatefulWidget {
  final Map<String, dynamic> note;

  const DeliveryNoteCard({Key? key, required this.note}) : super(key: key);

  @override
  State<DeliveryNoteCard> createState() => _DeliveryNoteCardState();
}

class _DeliveryNoteCardState extends State<DeliveryNoteCard> {
  Color _getStatusColor(String status) {
    if (status == 'pending') return Colors.orange;
    if (status == 'partial') return Colors.blue;
    if (status == 'delivered') return Colors.green;
    return Colors.grey;
  }

  String _getStatusTranslation(String status) {
    if (status == 'pending') return 'Pendiente';
    if (status == 'partial') return 'Entrega Parcial';
    if (status == 'delivered') return 'Completado';
    return status;
  }

  /// Lógica completa de Reimprimir: abre un menú con las opciones de reimpresión.
  void _onReprint() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final printOnDispatch = prefs.getBool('print_on_dispatch') ?? true;
    final showPreview = prefs.getBool('show_preview_remito') ?? false;
    final printA4 = prefs.getBool('print_a4_remito') ?? false;
    final showA4Preview = prefs.getBool('show_a4_preview_remito') ?? true;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _ReprintSheet(
        note: widget.note,
        printOnDispatch: printOnDispatch,
        showPreview: showPreview,
        printA4: printA4,
        showA4Preview: showA4Preview,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.note['sale'] ?? {};
    final customer = sale['customer'];
    final customerName = customer?['name'] ?? 'Consumidor Final';
    final status = widget.note['status']?.toString() ?? 'pending';
    final date = widget.note['created_at'] != null
        ? DateTime.parse(widget.note['created_at']).toLocal().toString().split(' ')[0]
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // ── Ícono ──
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.local_shipping, color: Colors.blue.shade800, size: 20),
            ),
            const SizedBox(width: 16),

            // ── Datos compactos (2 renglones) ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Remito #${widget.note['id']}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getStatusTranslation(status),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('📅 $date', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cliente: $customerName',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            // ── Botones de Acción ──
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _onReprint,
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('Reimprimir', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                const SizedBox(width: 8),
                if (status != 'delivered')
                  FilledButton.icon(
                    onPressed: () => DispatchFulfillmentDialog.show(context, widget.note),
                    icon: const Icon(Icons.check_box, size: 16),
                    label: const Text('Despachar', style: TextStyle(fontSize: 13)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Hoja de Reimpresión (Bottom Sheet con las 3 opciones)
// ────────────────────────────────────────────────────────────
class _ReprintSheet extends StatefulWidget {
  final Map<String, dynamic> note;
  final bool printOnDispatch;
  final bool showPreview;
  final bool printA4;
  final bool showA4Preview;

  const _ReprintSheet({
    required this.note,
    required this.printOnDispatch,
    required this.showPreview,
    required this.printA4,
    required this.showA4Preview,
  });

  @override
  State<_ReprintSheet> createState() => _ReprintSheetState();
}

class _ReprintSheetState extends State<_ReprintSheet> {
  bool _isPrinting = false;

  Future<void> _printThermal(BuildContext ctx) async {
    setState(() => _isPrinting = true);
    try {
      final settings = ctx.read<SettingsProvider>().settings;
      final sale = widget.note['sale'] ?? {};
      final customerName = sale['customer']?['name'];
      final vendorName = sale['user']?['name'];
      final currentUser = ctx.read<AuthProvider>().currentUser;
      final dispatcherName = currentUser?['name'] ?? 'SISTEMA';

      // Construir payload de ítems según el estado del remito
      final items = (widget.note['items'] as List? ?? []);
      final noteStatus = widget.note['status']?.toString() ?? 'pending';

      final allItemsPayload = items
          .where((item) =>
              double.tryParse(item['quantity_delivered'].toString()) != null &&
              double.parse(item['quantity_delivered'].toString()) > 0)
          .map((item) => {
                'id': item['id'],
                'delivered_now': double.parse(item['quantity_delivered'].toString()),
              })
          .toList();

      // Regla por estado:
      // pending   → delivered_now: 0 → título "ORDEN DE RETIRO" + muestra saldo pendiente
      // partial   → allItemsPayload tiene solo los entregados parcialmente
      // delivered → allItemsPayload tiene todos los ítems con su cantidad total entregada
      final payloadToUse = allItemsPayload.isNotEmpty
          ? allItemsPayload
          : items.map((item) => {
                'id': item['id'],
                'delivered_now': noteStatus == 'pending'
                    ? 0.0 // ORDEN DE RETIRO: nada entregado aún
                    : double.parse(item['quantity_purchased'].toString()),
              }).toList();

      if (widget.showPreview) {
        final previewLines = _buildTicketLines(sale, customerName, vendorName, dispatcherName, payloadToUse, items, settings, isReprint: true);
        if (!ctx.mounted) return;
        final docLabel = noteStatus == 'pending'
            ? 'Orden de Retiro'
            : noteStatus == 'partial'
                ? 'Remito de Despacho Parcial'
                : 'Remito de Despacho';
        final confirmed = await TicketPreviewDialog.show(
          ctx,
          title: '$docLabel #${widget.note['id']}',
          lines: previewLines,
        );
        if (!confirmed || !ctx.mounted) return;
      }

      await ReceiptPrinterService.instance.printDeliveryNoteTicket(
        note: widget.note,
        deliveredItemsData: payloadToUse,
        settings: settings!,
        localTerminal: ctx.read<LocalTerminalProvider>(),
        customerName: customerName,
        vendorName: vendorName,
        dispatcherName: dispatcherName,
        isReprint: true,
      );

      if (ctx.mounted) {
        SnackBarService.success(ctx, 'Remito térmico enviado a imprimir.');
        Navigator.pop(ctx);
      }
    } catch (e) {
      if (ctx.mounted) SnackBarService.error(ctx, 'Error al imprimir: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _previewA4(BuildContext ctx) async {
    setState(() => _isPrinting = true);
    try {
      final settings = ctx.read<SettingsProvider>().settings;
      final sale = widget.note['sale'] ?? {};
      final vendorName = sale['user']?['name'];
      final currentUser = ctx.read<AuthProvider>().currentUser;
      final dispatcherName = currentUser?['name'] ?? 'SISTEMA';



      await DeliveryNotePdfService.preview(
        context: ctx,
        note: widget.note,
        businessName: settings?.companyName ?? 'Mi Negocio',
        businessAddress: settings?.address,
        businessPhone: settings?.phone,
        businessTaxId: settings?.taxId,
        vendorName: vendorName,
        dispatcherName: dispatcherName,
      );

      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) SnackBarService.error(ctx, 'Error al generar PDF: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _printA4Direct(BuildContext ctx) async {
    setState(() => _isPrinting = true);
    try {
      final settings = ctx.read<SettingsProvider>().settings;
      final sale = widget.note['sale'] ?? {};
      final vendorName = sale['user']?['name'];
      final currentUser = ctx.read<AuthProvider>().currentUser;
      final dispatcherName = currentUser?['name'] ?? 'SISTEMA';



      await DeliveryNotePdfService.printDirect(
        note: widget.note,
        businessName: settings?.companyName ?? 'Mi Negocio',
        businessAddress: settings?.address,
        businessPhone: settings?.phone,
        businessTaxId: settings?.taxId,
        vendorName: vendorName,
        dispatcherName: dispatcherName,
      );

      if (ctx.mounted) {
        SnackBarService.success(ctx, 'Remito A4 enviado a imprimir.');
        Navigator.pop(ctx);
      }
    } catch (e) {
      if (ctx.mounted) SnackBarService.error(ctx, 'Error al imprimir A4: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  List<TicketLine> _buildTicketLines(
    Map sale,
    String? customerName,
    String? vendorName,
    String dispatcherName,
    List payload,
    List items,
    settings, {
    bool isReprint = false,
  }) {
    final now = DateTime.now().toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    final fecha = '${pad(now.day)}/${pad(now.month)}/${now.year} ${pad(now.hour)}:${pad(now.minute)}';
    final remNum = widget.note['id'].toString().padLeft(6, '0');

    List<TicketLine> buildCopy(String copyLabel) => [
      if (settings?.companyName != null)
        TicketLine(settings!.companyName!.toUpperCase(), align: TicketAlign.center, isBold: true, isLarge: true),
      if (settings?.address != null && settings!.address!.isNotEmpty)
        TicketLine(settings.address!, align: TicketAlign.center),
      if (settings?.taxId != null && settings!.taxId!.isNotEmpty)
        TicketLine('CUIT: ${settings.taxId}', align: TicketAlign.center, isBold: true),
      const TicketLine.hr(bold: true),
      const TicketLine('REMITO DE DESPACHO', align: TicketAlign.center, isBold: true),
      TicketLine('[ $copyLabel ]', align: TicketAlign.center),
      const TicketLine.hr(),
      TicketLine('REM N°: $remNum', isBold: true),
      TicketLine('FECHA: $fecha'),
      TicketLine('CLIENTE: ${customerName ?? 'Consumidor Final'}', isBold: true),
      if (vendorName != null) TicketLine('VENDIO: ${vendorName.toUpperCase()}'),
      TicketLine('DESPACHO: ${dispatcherName.toUpperCase()}'),
      const TicketLine.hr(),
      ...payload.expand((d) {
        final item = items.firstWhere((i) => i['id'] == d['id'], orElse: () => null);
        if (item == null) return [const TicketLine.space()];
        final name = (item['product']?['name'] ?? 'Producto').toUpperCase();
        final purchased = double.parse(item['quantity_purchased'].toString());
        final deliveredBefore = double.parse(item['quantity_delivered'].toString());
        final deliveredNow = (d['delivered_now'] as num).toDouble();
        // Para reimpresión: deliveredNow YA ES el total acumulado → remaining = purchased - deliveredNow
        // Para despacho: deliveredNow es incremental → remaining = purchased - deliveredBefore - deliveredNow
        final remaining = isReprint
            ? purchased - deliveredNow
            : purchased - deliveredBefore - deliveredNow;
        return [
          TicketLine(name, isBold: true),
          TicketLine('Entregando: ${deliveredNow.toStringAsFixed(1)} | Saldo: ${remaining.toStringAsFixed(1)}'),
          const TicketLine.space(),
        ];
      }),
      const TicketLine.hr(bold: true),
    ];

    // Copia 1 (Cliente) + separador visual + Copia 2 (Despachante con firma)
    return [
      ...buildCopy('COPIA CLIENTE'),
      const TicketLine.space(),
      const TicketLine('✂ - - - - - - - CORTE - - - - - - - ✂', align: TicketAlign.center),
      const TicketLine.space(),
      ...buildCopy('COPIA DESPACHANTE - ORIGINAL'),
      const TicketLine('FIRMA CONFORMIDAD DEL CLIENTE:', isBold: true),
      const TicketLine('___________________________________'),
      const TicketLine('Aclaración: ________________________'),
      const TicketLine('DNI / CUIT: ________________________'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final noteStatus = widget.note['status']?.toString() ?? 'pending';
    final docLabel = noteStatus == 'pending'
        ? 'Orden de Retiro'
        : noteStatus == 'partial'
            ? 'Remito de Despacho Parcial'
            : 'Remito de Despacho';

    final thermalSubtitle = noteStatus == 'pending'
        ? 'Orden para preparar mercadería en bodega/depósito'
        : noteStatus == 'partial'
            ? 'Historial de entrega parcial — incluye saldo pendiente'
            : 'Comprobante completo con firma del cliente';

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.print, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reimprimir #${widget.note['id']}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      docLabel,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Seleccioná el formato:',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 20),
          const Divider(),

          // ── Opción 1: Térmico ──
          ListTile(
            enabled: !_isPrinting,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.receipt_long, color: Colors.green.shade700, size: 28),
            ),
            title: Text('$docLabel Térmico', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(widget.showPreview ? 'Se mostrará vista previa antes de imprimir — $thermalSubtitle' : thermalSubtitle),
            trailing: _isPrinting ? const CircularProgressIndicator() : const Icon(Icons.chevron_right),
            onTap: () => _printThermal(context),
          ),

          const Divider(),

          // ── Opción 2: Vista previa A4 ──
          ListTile(
            enabled: !_isPrinting,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.preview, color: Colors.blue.shade700, size: 28),
            ),
            title: Text('Ver $docLabel A4 (PDF)', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(noteStatus == 'pending'
                ? 'Abre la Orden de Retiro en A4 para entregar al cliente'
                : 'Abre el doble Remito A4 — ORIGINAL (cliente) + DUPLICADO (despachante con firma)'),
            trailing: _isPrinting ? const CircularProgressIndicator() : const Icon(Icons.chevron_right),
            onTap: () => _previewA4(context),
          ),

          const Divider(),

          // ── Opción 3: Impresión directa A4 ──
          ListTile(
            enabled: !_isPrinting,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.picture_as_pdf, color: Colors.indigo.shade700, size: 28),
            ),
            title: const Text('Imprimir A4 Directo', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Envía el doble remito A4 directamente a la impresora láser'),
            trailing: _isPrinting ? const CircularProgressIndicator() : const Icon(Icons.chevron_right),
            onTap: () => _printA4Direct(context),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
