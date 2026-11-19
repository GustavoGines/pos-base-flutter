import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../providers/catalog_provider.dart';

class _SweepRowState {
  final int batchId;
  final String batchCode;
  final int productId;
  final String productName;
  final String unitType;
  final double availableQty;
  final double unitCost;
  final String? expirationDate;
  final int daysOverdue;
  final bool expiresToday;
  bool selected;
  final TextEditingController qtyCtrl;

  _SweepRowState({
    required this.batchId,
    required this.batchCode,
    required this.productId,
    required this.productName,
    required this.unitType,
    required this.availableQty,
    required this.unitCost,
    required this.expirationDate,
    required this.daysOverdue,
    required this.expiresToday,
  })  : selected = true,
        qtyCtrl = TextEditingController(text: availableQty.toQty());

  double get parsedQty {
    final parsed = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
    if (parsed <= 0) return 0.0;
    return math.min(availableQty, parsed);
  }

  double get estimatedLoss => parsedQty * unitCost;

  void dispose() => qtyCtrl.dispose();
}

/// Diálogo de "Barrido de Vencidos en 1 Clic" para cierre de turno / vitrina.
/// Permite revisar todos los lotes vencidos (y opcionalmente los que vencen hoy),
/// ajustar cantidades si hubo consumo interno y dar de baja masivamente como merma (`waste`).
class ExpiredBatchesSweepDialog extends StatefulWidget {
  final CatalogProvider provider;

  const ExpiredBatchesSweepDialog({
    super.key,
    required this.provider,
  });

  @override
  State<ExpiredBatchesSweepDialog> createState() =>
      _ExpiredBatchesSweepDialogState();
}

class _ExpiredBatchesSweepDialogState extends State<ExpiredBatchesSweepDialog> {
  bool _includeToday = true;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  final List<_SweepRowState> _rows = [];
  final TextEditingController _notesCtrl =
      TextEditingController(text: 'Barrido de cierre / descarte de lotes vencidos');

  @override
  void initState() {
    super.initState();
    _loadExpired();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExpired() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res =
          await widget.provider.fetchExpiredBatches(includeToday: _includeToday);
      final rawList = (res['batches'] as List?) ?? const [];
      for (final r in _rows) {
        r.dispose();
      }
      _rows.clear();
      for (final raw in rawList.whereType<Map>()) {
        final m = Map<String, dynamic>.from(raw);
        final batchId = (m['id'] as num?)?.toInt() ?? 0;
        final avail =
            double.tryParse(m['remaining_quantity']?.toString() ?? '0') ?? 0.0;
        if (batchId <= 0 || avail <= 0.0005) continue;
        _rows.add(
          _SweepRowState(
            batchId: batchId,
            batchCode: m['batch_code']?.toString() ?? '#$batchId',
            productId: (m['product_id'] as num?)?.toInt() ?? 0,
            productName: m['product_name']?.toString() ?? 'Producto',
            unitType: m['unit_type']?.toString() ?? 'un',
            availableQty: avail,
            unitCost: double.tryParse(m['unit_cost']?.toString() ?? '0') ?? 0.0,
            expirationDate: m['expiration_date']?.toString(),
            daysOverdue: (m['days_overdue'] as num?)?.toInt() ?? 0,
            expiresToday: m['expires_today'] == true,
          ),
        );
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final parsed = DateTime.tryParse(iso);
    return parsed != null ? DateFormat('dd/MM/yyyy').format(parsed) : iso;
  }

  Future<void> _confirmSweep() async {
    final selectedRows =
        _rows.where((r) => r.selected && r.parsedQty > 0.0005).toList();
    if (selectedRows.isEmpty) {
      SnackBarService.warning(
        context,
        'Seleccioná al menos un lote con cantidad válida para dar de baja.',
      );
      return;
    }

    await AdminPinDialog.protectAction(
      context,
      action:
          'Barrido masivo de ${selectedRows.length} lote(s) vencido(s)',
      permissionKey: AppPermissions.adjustStock,
      onAuthorized: () async {
        if (!mounted) return;
        setState(() => _submitting = true);
        final items = selectedRows
            .map((r) => {
                  'batch_id': r.batchId,
                  'quantity': r.parsedQty,
                })
            .toList();
        final res = await widget.provider.writeOffExpiredBatches(
          items: items,
          includeToday: _includeToday,
          notes: _notesCtrl.text.trim().isNotEmpty
              ? _notesCtrl.text.trim()
              : null,
        );
        if (!mounted) return;
        setState(() => _submitting = false);

        if (res != null) {
          final count = (res['written_off_count'] as num?)?.toInt() ?? 0;
          final lost = (res['total_cost_lost'] as num?)?.toDouble() ?? 0.0;
          SnackBarService.success(
            context,
            'Barrido completado: $count lote(s) dados de baja (Costo merma: \$${lost.toCurrency()}).',
          );
          Navigator.of(context).pop(true);
        } else {
          SnackBarService.error(
            context,
            widget.provider.errorMessage ??
                'No se pudo ejecutar el barrido de vencidos.',
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedRows =
        _rows.where((r) => r.selected && r.parsedQty > 0.0005).toList();
    final totalUnits =
        selectedRows.fold<double>(0.0, (acc, r) => acc + r.parsedQty);
    final totalLoss =
        selectedRows.fold<double>(0.0, (acc, r) => acc + r.estimatedLoss);
    final allSelected =
        _rows.isNotEmpty && _rows.every((element) => element.selected);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: math.min(680, MediaQuery.of(context).size.height * 0.88),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.cleaning_services_outlined,
                        color: Colors.deepOrange.shade700),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Barrido de Lotes Vencidos (Cierre del Día)',
                          style: TextStyle(
                              fontSize: 16.5, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Da de baja en 1 clic la mercadería vencida restante y valoriza la merma.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Material(
                color: Colors.orange.shade50.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                child: SwitchListTile.adaptive(
                  dense: true,
                  title: const Text(
                    'Incluir lotes que vencen HOY (cierre de vitrina)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Ideal al cerrar el turno noche para retirar productos del día que no pasan a mañana.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  value: _includeToday,
                  onChanged: _loading || _submitting
                      ? null
                      : (v) {
                          setState(() => _includeToday = v);
                          _loadExpired();
                        },
                ),
              ),
              const SizedBox(height: 10),
              if (!_loading && _error == null && _rows.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Checkbox(
                        value: allSelected,
                        onChanged: _submitting
                            ? null
                            : (v) {
                                final target = v == true;
                                setState(() {
                                  for (final r in _rows) {
                                    r.selected = target;
                                  }
                                });
                              },
                      ),
                      Text(
                        'Seleccionar todos (${_rows.length} lotes)',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Recargar',
                        icon: const Icon(Icons.refresh, size: 19),
                        onPressed: _loading ? null : _loadExpired,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red)),
                          )
                        : _rows.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_outlined,
                                        size: 48, color: Colors.green.shade400),
                                    const SizedBox(height: 8),
                                    const Text(
                                      '¡Vitrina limpia! No hay lotes vencidos con stock pendiente.',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, idx) {
                                  final r = _rows[idx];
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: r.selected
                                          ? (r.expiresToday
                                              ? Colors.amber.shade50
                                                  .withValues(alpha: 0.55)
                                              : Colors.red.shade50
                                                  .withValues(alpha: 0.45))
                                          : Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: r.selected
                                            ? (r.expiresToday
                                                ? Colors.orange.shade200
                                                : Colors.red.shade200)
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: r.selected,
                                          onChanged: _submitting
                                              ? null
                                              : (v) => setState(
                                                  () => r.selected = v == true),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: r.expiresToday
                                                          ? Colors
                                                              .orange.shade700
                                                          : Colors.red.shade700,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      r.expiresToday
                                                          ? 'VENCE HOY'
                                                          : 'VENCIDO (${r.daysOverdue}d)',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    r.productName,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'Lote ${r.batchCode} • Vto: ${_formatDate(r.expirationDate)} • Disp: ${r.availableQty.toQty()} ${r.unitType} • Costo: \$${r.unitCost.toCurrency()}/u',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 100,
                                          child: TextField(
                                            controller: r.qtyCtrl,
                                            enabled: r.selected && !_submitting,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            decoration: InputDecoration(
                                              labelText: 'Baja (${r.unitType})',
                                              isDense: true,
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Nota / Motivo de merma (para historial Kardex)',
                  isDense: true,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${selectedRows.length} lote(s) • ${totalUnits.toQty()} unidades a descartar',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                      Text(
                        'Costo valorizado estimado de merma: \$${totalLoss.toCurrency()}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade800,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.deepOrange),
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.delete_sweep_outlined),
                        label: Text(
                          _submitting
                              ? 'Procesando...'
                              : 'Confirmar Baja (${selectedRows.length})',
                        ),
                        onPressed: _submitting || selectedRows.isEmpty
                            ? null
                            : _confirmSweep,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
