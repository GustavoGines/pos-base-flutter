import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import '../../../../core/constants/app_permissions.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../../catalog/presentation/providers/catalog_provider.dart';
import '../../providers/supplier_provider.dart';
import 'supplier_invoice_form_dialog.dart';

Future<String?> _promptDeletionReasonDialog(BuildContext context, Map<String, dynamic> doc) async {
  final ctrl = TextEditingController();
  final invNum = doc['invoice_number']?.toString();
  final label = invNum != null && invNum.isNotEmpty ? '#$invNum' : 'ID #${doc['id']}';

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Anular Comprobante $label',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Al anular este comprobante:\n'
              '• Se revertirá automáticamente el impacto en el saldo del proveedor.\n'
              '• Se descontará (o repondrá en Notas de Crédito) el stock de los productos involucrados.\n'
              '• El comprobante quedará registrado en Auditoría y en la Papelera.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Motivo de anulación (Auditoría)',
                hintText: 'Ej: Factura duplicada / Error de proveedor',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (val) => Navigator.of(ctx).pop(
                val.trim().isNotEmpty ? val.trim() : 'Anulación manual de comprobante',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () {
            final reason = ctrl.text.trim().isNotEmpty
                ? ctrl.text.trim()
                : 'Anulación manual de comprobante';
            Navigator.of(ctx).pop(reason);
          },
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Confirmar Anulación'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return result;
}

class SupplierDocumentDetailDialog extends StatefulWidget {
  final Map<String, dynamic> document;
  final String? supplierName;
  final VoidCallback? onChanged;
  final int initialTab;

  const SupplierDocumentDetailDialog({
    super.key,
    required this.document,
    this.supplierName,
    this.onChanged,
    this.initialTab = 0,
  });

  @override
  State<SupplierDocumentDetailDialog> createState() => _SupplierDocumentDetailDialogState();
}

class _SupplierDocumentDetailDialogState extends State<SupplierDocumentDetailDialog> {
  late Map<String, dynamic> _doc;
  late int _selectedTab;
  bool _isWorking = false;
  bool _didModify = false;

  @override
  void initState() {
    super.initState();
    _doc = Map<String, dynamic>.from(widget.document);
    _selectedTab = widget.initialTab;
    // Si no trae el array de auditorías completo, lo refrescamos en segundo plano
    if (_doc['audits'] == null && _doc['id'] != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDetail());
    }
  }

  Future<void> _refreshDetail() async {
    final id = int.tryParse(_doc['id'].toString());
    if (id == null) return;
    final prov = context.read<SupplierProvider>();
    try {
      final fresh = await prov.fetchSupplierInvoiceDetail(id);
      if (mounted) {
        setState(() => _doc = fresh);
      }
    } catch (_) {}
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'delivery_note':
        return 'REMITO DE MERCADERÍA';
      case 'credit_note':
        return 'NOTA DE CRÉDITO';
      default:
        return 'FACTURA DE COMPRA';
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'delivery_note':
        return Colors.indigo.shade700;
      case 'credit_note':
        return Colors.orange.shade800;
      default:
        return Colors.blue.shade800;
    }
  }

  Future<void> _handleEdit() async {
    final supplierId = int.tryParse(
          (_doc['supplier_id'] ?? (_doc['supplier'] is Map ? _doc['supplier']['id'] : null) ?? 0)
              .toString(),
        ) ??
        0;
    final supName = widget.supplierName ??
        _doc['supplier_name']?.toString() ??
        (_doc['supplier'] is Map ? _doc['supplier']['name']?.toString() : null) ??
        'Proveedor';

    if (supplierId <= 0) return;

    final pinResult = await AdminPinDialog.verifyAndGetPin(
      context,
      action: 'Editar Comprobante de Proveedor #${_doc['id']}',
      permissionKey: AppPermissions.manageSupplierInvoices,
    );
    if (pinResult == null || !mounted) return;

    final edited = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplierInvoiceFormDialog(
        supplierId: supplierId,
        supplierName: supName,
        initialInvoice: _doc,
        authorizedAdminPin: pinResult == 'ALREADY_AUTHORIZED' ? null : pinResult,
      ),
    );

    if (edited == true && mounted) {
      _didModify = true;
      widget.onChanged?.call();
      await _refreshDetail();
    }
  }

  Future<void> _handleDelete() async {
    final id = int.tryParse(_doc['id'].toString());
    if (id == null) return;

    final reason = await _promptDeletionReasonDialog(context, _doc);
    if (reason == null || !mounted) return;

    await AdminPinDialog.protectAction(
      context,
      action: 'Anular Comprobante de Proveedor #$id',
      permissionKey: AppPermissions.manageSupplierInvoices,
      onAuthorized: () async {
        setState(() => _isWorking = true);
        try {
          final prov = context.read<SupplierProvider>();
          CatalogProvider? catalogProv;
          try {
            catalogProv = context.read<CatalogProvider>();
          } catch (_) {}
          final ok = await prov.deleteInvoice(id, reason: reason);
          if (ok && mounted) {
            if (catalogProv != null) {
              unawaited(catalogProv.loadProducts());
            }
            _didModify = true;
            widget.onChanged?.call();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Comprobante anulado. Saldo y stock revertidos.'),
              ),
            );
            await _refreshDetail();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
            );
          }
        } finally {
          if (mounted) setState(() => _isWorking = false);
        }
      },
    );
  }

  Future<void> _handleRestore() async {
    final id = int.tryParse(_doc['id'].toString());
    if (id == null) return;

    await AdminPinDialog.protectAction(
      context,
      action: 'Restaurar Comprobante de Proveedor #$id',
      permissionKey: AppPermissions.manageSupplierInvoices,
      onAuthorized: () async {
        setState(() => _isWorking = true);
        try {
          final prov = context.read<SupplierProvider>();
          CatalogProvider? catalogProv;
          try {
            catalogProv = context.read<CatalogProvider>();
          } catch (_) {}
          final ok = await prov.restoreInvoice(id);
          if (ok && mounted) {
            if (catalogProv != null) {
              unawaited(catalogProv.loadProducts());
            }
            _didModify = true;
            widget.onChanged?.call();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Comprobante restaurado. Saldo y stock reaplicados.'),
                backgroundColor: Colors.green,
              ),
            );
            await _refreshDetail();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
            );
          }
        } finally {
          if (mounted) setState(() => _isWorking = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'es_AR', symbol: '\$');
    final type = _doc['type']?.toString() ?? 'invoice';
    final invNumber = _doc['invoice_number']?.toString();
    final desc = _doc['description']?.toString() ?? '-';
    final userName = _doc['user_name']?.toString() ??
        (_doc['user'] is Map ? _doc['user']['name']?.toString() : null) ??
        'Sistema';
    final supName = widget.supplierName ??
        _doc['supplier_name']?.toString() ??
        (_doc['supplier'] is Map ? _doc['supplier']['name']?.toString() : null) ??
        'Proveedor';

    final rawDate = _doc['issue_date']?.toString() ?? _doc['date']?.toString();
    final parsedDate = rawDate != null ? DateTime.tryParse(rawDate)?.toLocal() : null;
    final dateStr = parsedDate != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(parsedDate)
        : (rawDate ?? '-');

    final totalAmount = double.tryParse(
            (_doc['total_amount'] ?? _doc['amount'] ?? 0).toString()) ??
        0.0;
    final taxAmount = double.tryParse((_doc['tax_amount'] ?? 0).toString()) ?? 0.0;
    final freightAmount = double.tryParse((_doc['freight_amount'] ?? 0).toString()) ?? 0.0;
    final discountAmount = double.tryParse((_doc['discount_amount'] ?? 0).toString()) ?? 0.0;

    final isEdited = _doc['is_edited'] == true ||
        ((int.tryParse((_doc['edit_count'] ?? 0).toString()) ?? 0) > 0);
    final editCount = int.tryParse((_doc['edit_count'] ?? 0).toString()) ?? 0;
    final isDeleted = _doc['is_deleted'] == true || _doc['deleted_at'] != null;

    final rawItems = _doc['items'] as List<dynamic>? ?? [];
    final rawAudits = _doc['audits'] as List<dynamic>? ?? [];

    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: (screenSize.width * 0.92).clamp(320.0, 960.0),
        constraints: BoxConstraints(
          maxHeight: (screenSize.height * 0.90).clamp(420.0, 720.0),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _typeColor(type).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _typeColor(type).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          _typeLabel(type),
                          style: TextStyle(
                            color: _typeColor(type),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        invNumber != null && invNumber.isNotEmpty
                            ? 'Comprobante #$invNumber'
                            : 'Comprobante S/N (ID #${_doc['id']})',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          decoration: isDeleted ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isEdited)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amber.shade700),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_edu, size: 14, color: Colors.amber.shade900),
                              const SizedBox(width: 4),
                              Text(
                                'EDITADO ($editCount)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isDeleted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.red.shade700),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.block, size: 14, color: Colors.red.shade900),
                              const SizedBox(width: 4),
                              Text(
                                'ANULADO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_isWorking)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  if (!isDeleted) ...[
                    OutlinedButton.icon(
                      onPressed: _handleEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Editar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber.shade900,
                        side: BorderSide(color: Colors.amber.shade700),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _handleDelete,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Anular'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: _handleRestore,
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text('Restaurar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(_didModify),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Metadata banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDeleted ? Colors.red.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDeleted ? Colors.red.shade200 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 28,
                    runSpacing: 8,
                    children: [
                      _metaItem(Icons.local_shipping_outlined, 'Proveedor', supName),
                      _metaItem(Icons.calendar_today_outlined, 'Fecha / Hora', dateStr),
                      _metaItem(Icons.person_outline, 'Cargado por', userName),
                      _metaItem(Icons.notes_outlined, 'Concepto', desc),
                    ],
                  ),
                  if (isEdited && _doc['last_edited_by_name'] != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Última edición por ${_doc['last_edited_by_name']} '
                      '(${_formatDateTime(_doc['last_edited_at']?.toString())})',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (isDeleted) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Anulado por ${_doc['deleted_by_name'] ?? 'Usuario'} '
                      '(${_formatDateTime(_doc['deleted_at']?.toString())})'
                      '${_doc['deletion_reason'] != null ? ' • Motivo: ${_doc['deletion_reason']}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Selector de Pestañas (Artículos vs Auditoría)
            Row(
              children: [
                _buildTabButton(
                  index: 0,
                  icon: Icons.inventory_2_outlined,
                  label: 'Artículos y Precios (${rawItems.length})',
                ),
                const SizedBox(width: 10),
                _buildTabButton(
                  index: 1,
                  icon: Icons.history_edu,
                  label: 'Historial de Auditoría (${rawAudits.length})',
                  badgeColor: isEdited || isDeleted ? Colors.amber.shade800 : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _selectedTab == 0
                  ? _buildItemsTab(rawItems, currency)
                  : _buildAuditTab(rawAudits, currency),
            ),
            const SizedBox(height: 16),
            // Totals footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDeleted ? Colors.red.shade900 : Colors.blueGrey.shade900,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 20,
                runSpacing: 8,
                children: [
                  Wrap(
                    spacing: 20,
                    runSpacing: 4,
                    children: [
                      if (freightAmount > 0)
                        Text(
                          'Flete: ${currency.format(freightAmount)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      if (taxAmount > 0)
                        Text(
                          'Impuestos: ${currency.format(taxAmount)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      if (discountAmount > 0)
                        Text(
                          'Descuento: -${currency.format(discountAmount)}',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                        ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isDeleted ? 'TOTAL ANULADO: ' : 'TOTAL COMPROBANTE: ',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        currency.format(totalAmount),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          decoration: isDeleted ? TextDecoration.lineThrough : null,
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
    );
  }

  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String label,
    Color? badgeColor,
  }) {
    final selected = _selectedTab == index;
    final activeColor = badgeColor ?? Colors.indigo.shade700;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? activeColor : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? activeColor : Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? activeColor : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsTab(List<dynamic> rawItems, NumberFormat currency) {
    if (rawItems.isEmpty) {
      return Center(
        child: Text(
          'Este comprobante fue registrado por monto global sin detalle de artículos.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: const Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'ARTÍCULO',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'CANT.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'COSTO ANT.',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'COSTO NUEVO',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'NUEVO PVP',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'SUBTOTAL',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: rawItems.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, idx) {
                  final item = rawItems[idx] as Map<String, dynamic>;
                  final prodName = item['product_name']?.toString() ??
                      (item['product'] is Map ? item['product']['name']?.toString() : null) ??
                      'Producto #${item['product_id']}';
                  final qty = double.tryParse((item['quantity'] ?? 0).toString()) ?? 0.0;
                  final prevCost = item['previous_cost'] != null
                      ? double.tryParse(item['previous_cost'].toString())
                      : null;
                  final unitCost = double.tryParse((item['unit_cost'] ?? 0).toString()) ?? 0.0;
                  final newPvp = item['new_selling_price'] != null
                      ? double.tryParse(item['new_selling_price'].toString())
                      : null;
                  final subtotal =
                      double.tryParse((item['subtotal'] ?? 0).toString()) ?? (qty * unitCost);

                  double? diffPct;
                  if (prevCost != null && prevCost > 0 && unitCost > 0) {
                    diffPct = ((unitCost - prevCost) / prevCost) * 100;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            prodName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(3),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            prevCost != null ? currency.format(prevCost) : '-',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currency.format(unitCost),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              if (diffPct != null && diffPct.abs() >= 0.1)
                                Text(
                                  '${diffPct > 0 ? '+' : ''}${diffPct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: diffPct > 0
                                        ? Colors.red.shade700
                                        : Colors.green.shade700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            newPvp != null ? currency.format(newPvp) : 'Sin cambio',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: newPvp != null ? FontWeight.bold : FontWeight.normal,
                              color:
                                  newPvp != null ? Colors.green.shade800 : Colors.grey.shade500,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            currency.format(subtotal),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
    );
  }

  Widget _buildAuditTab(List<dynamic> rawAudits, NumberFormat currency) {
    if (rawAudits.isEmpty) {
      return Center(
        child: Text(
          'Este comprobante no registra modificaciones ni eventos adicionales.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: rawAudits.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, idx) {
          final audit = Map<String, dynamic>.from(rawAudits[idx] as Map);
          final action = audit['action']?.toString() ?? 'updated';
          final userName = audit['user_name']?.toString() ?? 'Sistema';
          final authAdminName = (audit['authorizer_name'] ?? audit['authorized_by_admin_name'])
              ?.toString();
          final reason = audit['reason']?.toString();
          final dateStr = _formatDateTime(audit['created_at']?.toString());

          final rawSummary = audit['changes_summary'];
          List<dynamic> fields = [];
          List<dynamic> itemsDiff = [];
          if (rawSummary is List) {
            fields = rawSummary;
          } else if (rawSummary is Map) {
            final summary = Map<String, dynamic>.from(rawSummary);
            fields = (summary['fields'] as List<dynamic>?) ?? [];
            itemsDiff = (summary['items'] as List<dynamic>?) ?? [];
          }

          Color badgeColor;
          String badgeLabel;
          IconData badgeIcon;
          switch (action) {
            case 'created':
              badgeColor = Colors.blue.shade700;
              badgeLabel = 'CARGA INICIAL';
              badgeIcon = Icons.add_circle_outline;
              break;
            case 'deleted':
              badgeColor = Colors.red.shade700;
              badgeLabel = 'ANULACIÓN';
              badgeIcon = Icons.delete_outline;
              break;
            case 'restored':
              badgeColor = Colors.green.shade700;
              badgeLabel = 'RESTAURACIÓN';
              badgeIcon = Icons.restore;
              break;
            default:
              badgeColor = Colors.amber.shade900;
              badgeLabel = 'EDICIÓN APLICADA';
              badgeIcon = Icons.edit_note;
          }

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 14, color: badgeColor),
                          const SizedBox(width: 4),
                          Text(
                            badgeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: badgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '• Usuario: $userName',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (authAdminName != null && authAdminName.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.purple.shade200),
                        ),
                        child: Text(
                          'PIN Admin: $authAdminName',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.purple.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Motivo: $reason',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
                if (fields.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Detalle de Modificaciones (Antes → Después):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...fields.map((f) {
                    final fm = Map<String, dynamic>.from(f as Map);
                    final fieldLabel = (fm['field'] ?? fm['label'] ?? 'Campo').toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_right, size: 16, color: Colors.amber),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                                children: [
                                  TextSpan(
                                    text: '$fieldLabel: ',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(
                                    text: '${fm['old']}',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const TextSpan(text: '  →  '),
                                  TextSpan(
                                    text: '${fm['new']}',
                                    style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                if (itemsDiff.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Cambios en Artículos:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...itemsDiff.map((it) {
                    final im = Map<String, dynamic>.from(it as Map);
                    final change = im['change']?.toString() ?? 'modified';
                    final name = im['product_name']?.toString() ?? 'Producto';
                    if (change == 'added') {
                      final newCost = double.tryParse((im['new_cost'] ?? 0).toString()) ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '➕ Agregado: $name (Cant: ${im['new_qty']} • Costo: ${currency.format(newCost)})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    } else if (change == 'removed') {
                      final oldCost = double.tryParse((im['old_cost'] ?? 0).toString()) ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '➖ Quitado: $name (Cant ant: ${im['old_qty']} • Costo ant: ${currency.format(oldCost)})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    } else {
                      final oldCost = double.tryParse((im['old_cost'] ?? 0).toString()) ?? 0;
                      final newCost = double.tryParse((im['new_cost'] ?? 0).toString()) ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '✏️ Modificado: $name — Cant: ${im['old_qty']} → ${im['new_qty']} | Costo: ${currency.format(oldCost)} → ${currency.format(newCost)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                  }),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  Widget _metaItem(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey.shade600),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class SupplierDocumentsHistoryDialog extends StatefulWidget {
  final int? initialSupplierId;

  const SupplierDocumentsHistoryDialog({super.key, this.initialSupplierId});

  @override
  State<SupplierDocumentsHistoryDialog> createState() => _SupplierDocumentsHistoryDialogState();
}

class _SupplierDocumentsHistoryDialogState extends State<SupplierDocumentsHistoryDialog> {
  int? _selectedSupplierId;
  String _selectedType = 'all';
  String _auditFilter = 'all'; // 'active' | 'edited' | 'deleted' | 'all'
  final _searchCtrl = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _isLoading = true;
  List<dynamic> _documents = [];

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = widget.initialSupplierId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDocuments());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    try {
      final prov = context.read<SupplierProvider>();
      final res = await prov.fetchSupplierInvoices(
        supplierId: _selectedSupplierId,
        type: _selectedType == 'all' ? null : _selectedType,
        auditFilter: _auditFilter,
        search: _searchCtrl.text.trim(),
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (!mounted) return;
      setState(() {
        _documents = res;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _documents = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCreateInvoice() async {
    final suppliers = context.read<SupplierProvider>().suppliers;
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero debe registrar al menos un proveedor.')),
      );
      return;
    }

    int? targetSupplierId = _selectedSupplierId;
    String? targetSupplierName;

    if (targetSupplierId != null) {
      final found = suppliers.where((s) => s.id == targetSupplierId).toList();
      if (found.isNotEmpty) targetSupplierName = found.first.name;
    }

    if (targetSupplierId == null || targetSupplierName == null) {
      int chosenId = suppliers.first.id;
      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('Seleccionar Proveedor'),
            content: SizedBox(
              width: 380,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: chosenId,
                decoration: const InputDecoration(
                  labelText: 'Proveedor del Comprobante',
                  border: OutlineInputBorder(),
                ),
                items: suppliers
                    .map(
                      (s) => DropdownMenuItem<int>(
                        value: s.id,
                        child: Text(s.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => chosenId = val);
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(chosenId),
                child: const Text('Continuar'),
              ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      targetSupplierId = picked;
      targetSupplierName = suppliers.firstWhere((s) => s.id == picked).name;
    }

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplierInvoiceFormDialog(
        supplierId: targetSupplierId!,
        supplierName: targetSupplierName!,
      ),
    );
    if (created == true && mounted) {
      _loadDocuments();
    }
  }

  Future<void> _handleQuickEdit(Map<String, dynamic> doc, String supName) async {
    final supplierId = int.tryParse(
          (doc['supplier_id'] ?? (doc['supplier'] is Map ? doc['supplier']['id'] : null) ?? 0)
              .toString(),
        ) ??
        0;
    if (supplierId <= 0) return;

    final pinResult = await AdminPinDialog.verifyAndGetPin(
      context,
      action: 'Editar Comprobante de Proveedor #${doc['id']}',
      permissionKey: AppPermissions.manageSupplierInvoices,
    );
    if (pinResult == null || !mounted) return;

    final edited = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplierInvoiceFormDialog(
        supplierId: supplierId,
        supplierName: supName,
        initialInvoice: doc,
        authorizedAdminPin: pinResult == 'ALREADY_AUTHORIZED' ? null : pinResult,
      ),
    );

    if (edited == true && mounted) {
      _loadDocuments();
    }
  }

  Future<void> _handleQuickDelete(Map<String, dynamic> doc) async {
    final id = int.tryParse(doc['id'].toString());
    if (id == null) return;

    final reason = await _promptDeletionReasonDialog(context, doc);
    if (reason == null || !mounted) return;

    await AdminPinDialog.protectAction(
      context,
      action: 'Anular Comprobante de Proveedor #$id',
      permissionKey: AppPermissions.manageSupplierInvoices,
      onAuthorized: () async {
        try {
          final prov = context.read<SupplierProvider>();
          CatalogProvider? catalogProv;
          try {
            catalogProv = context.read<CatalogProvider>();
          } catch (_) {}
          final ok = await prov.deleteInvoice(id, reason: reason);
          if (ok && mounted) {
            if (catalogProv != null) {
              unawaited(catalogProv.loadProducts());
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Comprobante anulado. Saldo y stock revertidos.'),
              ),
            );
            _loadDocuments();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
            );
          }
        }
      },
    );
  }

  Future<void> _handleQuickRestore(Map<String, dynamic> doc) async {
    final id = int.tryParse(doc['id'].toString());
    if (id == null) return;

    await AdminPinDialog.protectAction(
      context,
      action: 'Restaurar Comprobante de Proveedor #$id',
      permissionKey: AppPermissions.manageSupplierInvoices,
      onAuthorized: () async {
        try {
          final prov = context.read<SupplierProvider>();
          CatalogProvider? catalogProv;
          try {
            catalogProv = context.read<CatalogProvider>();
          } catch (_) {}
          final ok = await prov.restoreInvoice(id);
          if (ok && mounted) {
            if (catalogProv != null) {
              unawaited(catalogProv.loadProducts());
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Comprobante restaurado. Saldo y stock reaplicados.'),
                backgroundColor: Colors.green,
              ),
            );
            _loadDocuments();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
            );
          }
        }
      },
    );
  }

  String _typeBadgeText(String? type) {
    switch (type) {
      case 'delivery_note':
        return 'REMITO';
      case 'credit_note':
        return 'NOTA CRÉD.';
      default:
        return 'FACTURA';
    }
  }

  Color _typeBadgeColor(String? type) {
    switch (type) {
      case 'delivery_note':
        return Colors.indigo.shade700;
      case 'credit_note':
        return Colors.orange.shade800;
      default:
        return Colors.blue.shade800;
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = context.watch<SupplierProvider>().suppliers;
    final currency = NumberFormat.currency(locale: 'es_AR', symbol: '\$');
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: (screenSize.width * 0.95).clamp(320.0, 1140.0),
        height: (screenSize.height * 0.88).clamp(420.0, 740.0),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, color: Colors.indigo, size: 28),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Historial y Auditoría de Comprobantes de Proveedores',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Consulte, cargue, edite o anule Facturas, Remitos y Notas de Crédito con auditoría completa',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _handleCreateInvoice,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Cargar Comprobante'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Filters bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      initialValue: _selectedSupplierId,
                      decoration: const InputDecoration(
                        labelText: 'Proveedor',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todos', overflow: TextOverflow.ellipsis),
                        ),
                        ...suppliers.map(
                          (s) => DropdownMenuItem<int?>(
                            value: s.id,
                            child: Text(s.name, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedSupplierId = val);
                        _loadDocuments();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 165,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo Comprobante',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('Todos', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'invoice',
                          child: Text('Facturas', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'delivery_note',
                          child: Text('Remitos', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'credit_note',
                          child: Text('Notas de Crédito', overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedType = val ?? 'all');
                        _loadDocuments();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 195,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _auditFilter,
                      decoration: const InputDecoration(
                        labelText: 'Estado / Auditoría',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('Todos (Incl. Anulados)', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Vigentes', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'edited',
                          child: Text('Editados (Con cambios)', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'deleted',
                          child: Text('Anulados (Papelera)', overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _auditFilter = val ?? 'all');
                        _loadDocuments();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nº Comprobante / Producto',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search, size: 18),
                          onPressed: _loadDocuments,
                        ),
                      ),
                      onSubmitted: (_) => _loadDocuments(),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showCompactDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDateRange: _dateFrom != null && _dateTo != null
                            ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
                            : null,
                        helpText: 'Filtrar Comprobantes por Fecha',
                      );
                      if (!mounted) return;
                      if (picked != null) {
                        setState(() {
                          _dateFrom = picked.start;
                          _dateTo = picked.end;
                        });
                        _loadDocuments();
                      }
                    },
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      _dateFrom != null && _dateTo != null
                          ? '${DateFormat('dd/MM/yy').format(_dateFrom!)} - ${DateFormat('dd/MM/yy').format(_dateTo!)}'
                          : 'Rango Fechas',
                    ),
                  ),
                  if (_dateFrom != null ||
                      _selectedSupplierId != null ||
                      _selectedType != 'all' ||
                      _auditFilter != 'all' ||
                      _searchCtrl.text.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedSupplierId = null;
                          _selectedType = 'all';
                          _auditFilter = 'all';
                          _searchCtrl.clear();
                          _dateFrom = null;
                          _dateTo = null;
                        });
                        _loadDocuments();
                      },
                      icon: const Icon(Icons.filter_alt_off, size: 16),
                      label: const Text('Limpiar'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _documents.isEmpty
                      ? const Center(
                          child: Text(
                            'No se encontraron comprobantes con los filtros seleccionados.',
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListView.separated(
                            itemCount: _documents.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, idx) {
                              final doc = Map<String, dynamic>.from(
                                _documents[idx] as Map,
                              );
                              final type = doc['type']?.toString() ?? 'invoice';
                              final supName = doc['supplier_name']?.toString() ??
                                  (doc['supplier'] is Map
                                      ? doc['supplier']['name']?.toString()
                                      : null) ??
                                  '-';
                              final userName = doc['user_name']?.toString() ??
                                  (doc['user'] is Map ? doc['user']['name']?.toString() : null) ??
                                  'Sistema';
                              final items = (doc['items'] as List<dynamic>?) ?? [];
                              final rawDate = doc['issue_date']?.toString();
                              final parsedDate =
                                  rawDate != null ? DateTime.tryParse(rawDate)?.toLocal() : null;
                              final dateStr = parsedDate != null
                                  ? DateFormat('dd/MM/yyyy HH:mm').format(parsedDate)
                                  : (rawDate ?? '-');
                              final rawTotal = double.tryParse(
                                      (doc['total_amount'] ?? doc['amount'] ?? 0).toString()) ??
                                  0.0;
                              final itemsSum = items.fold<double>(
                                0.0,
                                (sum, it) =>
                                    sum +
                                    (double.tryParse((it['subtotal'] ?? 0).toString()) ?? 0.0),
                              );
                              final total = rawTotal > 0 ? rawTotal : itemsSum;

                              final isEdited = doc['is_edited'] == true ||
                                  ((int.tryParse((doc['edit_count'] ?? 0).toString()) ?? 0) > 0);
                              final editCount =
                                  int.tryParse((doc['edit_count'] ?? 0).toString()) ?? 0;
                              final isDeleted =
                                  doc['is_deleted'] == true || doc['deleted_at'] != null;

                              final subtitleParts = <String>[
                                dateStr,
                                'Cargó: $userName',
                                if (doc['description'] != null &&
                                    doc['description'].toString().isNotEmpty)
                                  doc['description'].toString(),
                                if (isEdited && doc['last_edited_by_name'] != null)
                                  'Editó: ${doc['last_edited_by_name']}',
                                if (isDeleted)
                                  'Anuló: ${doc['deleted_by_name'] ?? 'Usuario'}'
                                      '${doc['deletion_reason'] != null ? ' (${doc['deletion_reason']})' : ''}',
                              ];

                              return Container(
                                color: isDeleted ? Colors.red.shade50.withValues(alpha: 0.4) : null,
                                child: ListTile(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => SupplierDocumentDetailDialog(
                                        document: doc,
                                        supplierName: supName,
                                        onChanged: _loadDocuments,
                                      ),
                                    );
                                  },
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _typeBadgeColor(type).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _typeBadgeText(type),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: _typeBadgeColor(type),
                                      ),
                                    ),
                                  ),
                                  title: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        supName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          decoration:
                                              isDeleted ? TextDecoration.lineThrough : null,
                                        ),
                                      ),
                                      Text(
                                        doc['invoice_number'] != null &&
                                                doc['invoice_number'].toString().isNotEmpty
                                            ? '#${doc['invoice_number']}'
                                            : '(S/N)',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blueGrey.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${items.length} ítems',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.blueGrey.shade700,
                                          ),
                                        ),
                                      ),
                                      if (isEdited)
                                        InkWell(
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              builder: (_) => SupplierDocumentDetailDialog(
                                                document: doc,
                                                supplierName: supName,
                                                onChanged: _loadDocuments,
                                                initialTab: 1,
                                              ),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade100,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.amber.shade600),
                                            ),
                                            child: Text(
                                              'EDITADO (${editCount}x)',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (isDeleted)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.red.shade600),
                                          ),
                                          child: Text(
                                            'ANULADO',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade900,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    subtitleParts.join(' • '),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDeleted ? Colors.red.shade800 : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        currency.format(total),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          decoration:
                                              isDeleted ? TextDecoration.lineThrough : null,
                                          color: isDeleted
                                              ? Colors.red.shade700
                                              : (type == 'credit_note'
                                                  ? Colors.green.shade700
                                                  : Colors.blueGrey.shade900),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: 'Ver Detalle y Auditoría',
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 20,
                                          color: Colors.indigo,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (_) => SupplierDocumentDetailDialog(
                                              document: doc,
                                              supplierName: supName,
                                              onChanged: _loadDocuments,
                                            ),
                                          );
                                        },
                                      ),
                                      if (!isDeleted) ...[
                                        IconButton(
                                          tooltip: 'Editar Comprobante',
                                          icon: Icon(
                                            Icons.edit_outlined,
                                            size: 19,
                                            color: Colors.amber.shade900,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _handleQuickEdit(doc, supName),
                                        ),
                                        IconButton(
                                          tooltip: 'Anular Comprobante',
                                          icon: Icon(
                                            Icons.delete_outline,
                                            size: 19,
                                            color: Colors.red.shade700,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _handleQuickDelete(doc),
                                        ),
                                      ] else
                                        IconButton(
                                          tooltip: 'Restaurar Comprobante',
                                          icon: Icon(
                                            Icons.restore,
                                            size: 20,
                                            color: Colors.green.shade700,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _handleQuickRestore(doc),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
