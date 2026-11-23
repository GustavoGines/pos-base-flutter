import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import '../../data/models/product_batch_model.dart';
import '../../domain/entities/product.dart';
import '../providers/catalog_provider.dart';
import 'print_labels_dialog.dart';
import 'production_orders_dialog.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

/// Gestión granular de lotes FEFO/FIFO por producto:
/// listar lotes activos/déficit/cerrados, registrar nuevo lote, editar vencimiento,
/// imprimir etiqueta térmica (`L#<batch_id>`) y registrar mermas (`write-off`).
class ProductBatchesDialog extends StatefulWidget {
  final CatalogProvider provider;
  final Product product;
  final bool initialOpenCreate;

  const ProductBatchesDialog({
    super.key,
    required this.provider,
    required this.product,
    this.initialOpenCreate = false,
  });

  @override
  State<ProductBatchesDialog> createState() => _ProductBatchesDialogState();
}

class _ProductBatchesDialogState extends State<ProductBatchesDialog> {
  ProductBatchesResponse? _response;
  bool _loading = true;
  bool _submitting = false;
  bool _showClosed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBatches();
    if (widget.initialOpenCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openCreateBatchDialog();
      });
    }
  }

  Future<void> _loadBatches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.provider.fetchProductBatches(
        widget.product.id,
        includeClosed: true,
      );
      if (mounted) {
        setState(() {
          _response = res;
          _loading = false;
        });
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
    if (iso == null || iso.isEmpty) return 'Sin fecha';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }

  bool _canUseProduction(BuildContext context) {
    try {
      final s = context.read<SettingsProvider?>();
      if (s != null) return s.features.production;
    } catch (_) {}
    return true;
  }

  String _formatIso(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  String _sourceLabel(String source) {
    switch (source) {
      case 'supplier_invoice':
        return 'Compra Proveedor';
      case 'production_order':
        return 'Producción Propia';
      case 'opening_balance':
        return 'Saldo Inicial';
      case 'deficit_auto':
        return 'Déficit Mostrador';
      default:
        return 'Ajuste Manual';
    }
  }

  Future<void> _openCreateBatchDialog() async {
    final qtyCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final costCtrl = TextEditingController(
      text: widget.product.costPrice > 0 ? widget.product.costPrice.toArsInput() : '',
    );
    final validityCtrl = TextEditingController(
      text: (widget.product.vencimientoDias != null && widget.product.vencimientoDias! > 0)
          ? widget.product.vencimientoDias!.toString()
          : '',
    );
    final notesCtrl = TextEditingController();

    DateTime manufacturedAt = DateTime.now();
    DateTime? expirationDate = widget.product.vencimientoDias != null && widget.product.vencimientoDias! > 0
        ? DateTime(
            manufacturedAt.year,
            manufacturedAt.month,
            manufacturedAt.day + widget.product.vencimientoDias!,
          )
        : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AppModalShell(
          title: 'Ingresar Nuevo Lote',
          subtitle: widget.product.name,
          icon: Icons.add_box_outlined,
          accent: AppModalAccent.teal,
          compact: true,
          maxWidth: 480,
          onClose: () => Navigator.pop(ctx, false),
          bodyPadding: const EdgeInsets.all(18),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.product.trackBatches) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Text(
                    'Al registrar el primer lote, este producto activará automáticamente el control de vencimientos por lotes.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                  ),
                ),
              ],
              TextField(
                controller: qtyCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cantidad (${widget.product.unitShortLabel}) *',
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código de Lote (opcional)',
                  hintText: 'Si se deja vacío se genera automático',
                  prefixIcon: Icon(Icons.qr_code_outlined),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        'Elab: ${DateFormat('dd/MM/yy').format(manufacturedAt)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final picked = await showCompactDatePicker(
                          context: ctx,
                          initialDate: manufacturedAt,
                          helpText: 'Fecha de Elaboración / Ingreso',
                        );
                        if (picked != null) {
                          setModalState(() {
                            manufacturedAt = picked;
                            final n = int.tryParse(validityCtrl.text.trim());
                            if (n != null && n >= 1 && n <= 3650) {
                              expirationDate = DateTime(
                                picked.year,
                                picked.month,
                                picked.day + n,
                              );
                            } else if (expirationDate != null) {
                              final elabDay = DateTime(picked.year, picked.month, picked.day);
                              final expDay = DateTime(
                                expirationDate!.year,
                                expirationDate!.month,
                                expirationDate!.day,
                              );
                              final diff = expDay.difference(elabDay).inDays;
                              validityCtrl.text =
                                  (diff >= 1 && diff <= 3650) ? diff.toString() : '';
                            }
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(
                        Icons.event_available_outlined,
                        size: 16,
                        color: expirationDate != null ? Colors.deepOrange : null,
                      ),
                      label: Text(
                        expirationDate != null
                            ? 'Vto: ${DateFormat('dd/MM/yy').format(expirationDate!)}'
                            : 'Vencimiento (opc)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final picked = await showCompactDatePicker(
                          context: ctx,
                          initialDate: expirationDate ??
                              DateTime.now().add(const Duration(days: 7)),
                          helpText: 'Fecha de Vencimiento del Lote',
                        );
                        if (picked != null) {
                          final elabDay = DateTime(
                            manufacturedAt.year,
                            manufacturedAt.month,
                            manufacturedAt.day,
                          );
                          final expDay = DateTime(picked.year, picked.month, picked.day);
                          final diff = expDay.difference(elabDay).inDays;
                          setModalState(() {
                            expirationDate = picked;
                            validityCtrl.text =
                                (diff >= 1 && diff <= 3650) ? diff.toString() : '';
                          });
                        }
                      },
                    ),
                  ),
                  if (expirationDate != null || validityCtrl.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Quitar vencimiento',
                      icon: const Icon(Icons.clear, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setModalState(() {
                        expirationDate = null;
                        validityCtrl.clear();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: validityCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Validez del lote (días desde elaboración)',
                  hintText: 'Ej. 5, 30, 180',
                  prefixIcon: Icon(Icons.hourglass_bottom_outlined, size: 18),
                  suffixText: 'días',
                  isDense: true,
                ),
                onChanged: (val) {
                  final trimmed = val.trim();
                  if (trimmed.isEmpty) {
                    setModalState(() => expirationDate = null);
                    return;
                  }
                  final n = int.tryParse(trimmed);
                  if (n != null && n >= 1 && n <= 3650) {
                    setModalState(() {
                      expirationDate = DateTime(
                        manufacturedAt.year,
                        manufacturedAt.month,
                        manufacturedAt.day + n,
                      );
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: costCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  ArsThousandsInputFormatter(),
                ],
                decoration: const InputDecoration(
                  labelText: 'Costo unitario del lote (\$)',
                  prefixIcon: Icon(Icons.attach_money),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notas (ej. Remito, Proveedor, Observación)',
                  prefixIcon: Icon(Icons.notes_outlined),
                  isDense: true,
                ),
              ),
            ],
          ),
          footerActions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Registrar Lote'),
              onPressed: () {
                final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim());
                if (qty == null || qty <= 0) {
                  SnackBarService.warning(ctx, 'Ingresá una cantidad válida mayor a 0.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      qtyCtrl.dispose();
      codeCtrl.dispose();
      costCtrl.dispose();
      validityCtrl.dispose();
      notesCtrl.dispose();
      return;
    }

    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final parsedCost = ArsThousandsInputFormatter.parse(costCtrl.text);
    final batchCode = codeCtrl.text.trim();
    final notes = notesCtrl.text.trim();

    qtyCtrl.dispose();
    codeCtrl.dispose();
    costCtrl.dispose();
    validityCtrl.dispose();
    notesCtrl.dispose();

    setState(() => _submitting = true);
    final ok = await AdminPinDialog.protectAction(
      context,
      action: 'Ingresar Nuevo Lote de Stock',
      permissionKey: AppPermissions.adjustStock,
      onAuthorized: () async {
        final res = await widget.provider.createProductBatch(
          widget.product.id,
          quantity: qty,
          batchCode: batchCode.isNotEmpty ? batchCode : null,
          manufacturedAt: _formatIso(manufacturedAt),
          expirationDate: expirationDate != null ? _formatIso(expirationDate!) : null,
          unitCost: parsedCost > 0 ? parsedCost : null,
          notes: notes.isNotEmpty ? notes : null,
        );
        if (mounted) {
          if (res != null) {
            SnackBarService.success(context, 'Lote ingresado y stock actualizado.');
            await _loadBatches();
          } else {
            SnackBarService.error(
              context,
              widget.provider.errorMessage ?? 'No se pudo registrar el lote.',
            );
          }
        }
      },
    );
    if (!ok && mounted) {
      setState(() => _submitting = false);
    } else if (mounted) {
      setState(() => _submitting = false);
    }
  }

  Future<void> _openEditBatchDialog(ProductBatchModel batch) async {
    final codeCtrl = TextEditingController(text: batch.batchCode);
    final notesCtrl = TextEditingController(text: batch.notes ?? '');
    DateTime? expirationDate = batch.expirationDate != null
        ? DateTime.tryParse(batch.expirationDate!)
        : null;
    final rawBaseDate =
        (batch.manufacturedAt != null ? DateTime.tryParse(batch.manufacturedAt!) : null) ??
            DateTime.now();
    final baseDay = DateTime(rawBaseDate.year, rawBaseDate.month, rawBaseDate.day);
    final initialDiff = expirationDate != null
        ? DateTime(expirationDate.year, expirationDate.month, expirationDate.day)
            .difference(baseDay)
            .inDays
        : 0;
    final validityCtrl = TextEditingController(
      text: (expirationDate != null && initialDiff >= 1 && initialDiff <= 3650)
          ? initialDiff.toString()
          : '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AppModalShell(
          title: 'Editar Lote ${batch.batchCode}',
          subtitle: widget.product.name,
          icon: Icons.edit_calendar_outlined,
          accent: AppModalAccent.teal,
          compact: true,
          maxWidth: 440,
          onClose: () => Navigator.pop(ctx, false),
          bodyPadding: const EdgeInsets.all(18),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código de Lote',
                  prefixIcon: Icon(Icons.qr_code_outlined),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined, size: 16),
                      label: Text(
                        expirationDate != null
                            ? 'Vence: ${DateFormat('dd/MM/yyyy').format(expirationDate!)}'
                            : 'Sin fecha de vencimiento',
                      ),
                      onPressed: () async {
                        final picked = await showCompactDatePicker(
                          context: ctx,
                          initialDate: expirationDate ?? DateTime.now(),
                          helpText: 'Fecha de Vencimiento',
                        );
                        if (picked != null) {
                          final expDay = DateTime(picked.year, picked.month, picked.day);
                          final diff = expDay.difference(baseDay).inDays;
                          setModalState(() {
                            expirationDate = picked;
                            validityCtrl.text =
                                (diff >= 1 && diff <= 3650) ? diff.toString() : '';
                          });
                        }
                      },
                    ),
                  ),
                  if (expirationDate != null || validityCtrl.text.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Quitar vencimiento',
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setModalState(() {
                        expirationDate = null;
                        validityCtrl.clear();
                      }),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: validityCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Validez (días)',
                  hintText: 'Ej. 5, 30, 180',
                  prefixIcon: Icon(Icons.hourglass_bottom_outlined, size: 18),
                  suffixText: 'días',
                  isDense: true,
                ),
                onChanged: (val) {
                  final trimmed = val.trim();
                  if (trimmed.isEmpty) {
                    setModalState(() => expirationDate = null);
                    return;
                  }
                  final n = int.tryParse(trimmed);
                  if (n != null && n >= 1 && n <= 3650) {
                    setModalState(() {
                      expirationDate = DateTime(
                        baseDay.year,
                        baseDay.month,
                        baseDay.day + n,
                      );
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notas del lote',
                  isDense: true,
                ),
              ),
            ],
          ),
          footerActions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    final newCode = codeCtrl.text.trim();
    final newNotes = notesCtrl.text.trim();
    codeCtrl.dispose();
    validityCtrl.dispose();
    notesCtrl.dispose();

    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    String editPermission = AppPermissions.manageCatalog;
    try {
      final auth = context.read<AuthProvider>();
      if (!auth.hasPermission(AppPermissions.manageCatalog) &&
          auth.hasPermission(AppPermissions.adjustStock)) {
        editPermission = AppPermissions.adjustStock;
      }
    } catch (_) {}
    await AdminPinDialog.protectAction(
      context,
      action: 'Modificar Lote ${batch.batchCode}',
      permissionKey: editPermission,
      onAuthorized: () async {
        final res = await widget.provider.updateProductBatch(
          batch.id,
          batchCode: newCode.isNotEmpty ? newCode : batch.batchCode,
          expirationDate: expirationDate != null ? _formatIso(expirationDate!) : '',
          notes: newNotes,
        );
        if (mounted) {
          if (res != null) {
            SnackBarService.success(context, 'Lote actualizado.');
            await _loadBatches();
          } else {
            SnackBarService.error(
              context,
              widget.provider.errorMessage ?? 'No se pudo actualizar el lote.',
            );
          }
        }
      },
    );
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _openWriteOffDialog(ProductBatchModel batch) async {
    final qtyCtrl = TextEditingController(text: batch.remainingQuantity.toQty());
    final notesCtrl = TextEditingController(
      text: batch.isExpired ? 'Baja por vencimiento' : 'Descarte / Merma de cocina',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppModalShell(
        title: 'Registrar Merma / Descarte',
        subtitle: widget.product.name,
        icon: Icons.delete_sweep_outlined,
        accent: AppModalAccent.orange,
        compact: true,
        maxWidth: 440,
        onClose: () => Navigator.pop(ctx, false),
        bodyPadding: const EdgeInsets.all(18),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lote ${batch.batchCode} • Disponible: ${batch.remainingQuantity.toQty()} ${widget.product.unitType}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cantidad a descartar (máx ${batch.remainingQuantity.toQty()})',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo de la merma',
                isDense: true,
              ),
            ),
          ],
        ),
        footerActions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Confirmar Merma'),
            onPressed: () {
              final q = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim());
              if (q == null || q <= 0 || q > batch.remainingQuantity + 0.001) {
                SnackBarService.warning(
                  ctx,
                  'La cantidad debe estar entre 0 y ${batch.remainingQuantity.toQty()}.',
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
          ),
        ],
      ),
    );

    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim());
    final notes = notesCtrl.text.trim();
    qtyCtrl.dispose();
    notesCtrl.dispose();

    if (confirmed != true || qty == null || !mounted) return;

    setState(() => _submitting = true);
    await AdminPinDialog.protectAction(
      context,
      action: 'Registrar Merma en Lote ${batch.batchCode}',
      permissionKey: AppPermissions.adjustStock,
      onAuthorized: () async {
        final res = await widget.provider.writeOffBatch(
          batch.id,
          quantity: qty,
          notes: notes.isNotEmpty ? notes : null,
        );
        if (mounted) {
          if (res != null) {
            final costLost = (res['cost_lost'] as num?)?.toDouble();
            final extra = costLost != null && costLost > 0
                ? ' (Costo perdido: \$${costLost.toCurrency()})'
                : '';
            SnackBarService.success(context, 'Merma registrada correctamente$extra.');
            await _loadBatches();
          } else {
            SnackBarService.error(
              context,
              widget.provider.errorMessage ?? 'No se pudo registrar la merma.',
            );
          }
        }
      },
    );
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _openSplitBatchDialog(ProductBatchModel batch) async {
    final maxAvail = batch.availableToSell;
    if (maxAvail <= 0.0005) {
      SnackBarService.warning(context, 'Este lote no tiene stock libre disponible para dividir.');
      return;
    }

    final defaultQty = math.min(maxAvail, widget.product.isSoldByWeight ? maxAvail : 1.0);
    final qtyCtrl = TextEditingController(text: defaultQty.toQty());
    final codeCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: 'Pase de cámara/freezer a vitrina');
    final shelfDays =
        (widget.product.vencimientoDias != null && widget.product.vencimientoDias! > 0)
            ? widget.product.vencimientoDias!
            : 4;
    DateTime displayExp = DateTime.now().add(Duration(days: shelfDays));
    bool printLabelNow = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AppModalShell(
          title: 'Pasar a Vitrina (Dividir Lote)',
          subtitle: widget.product.name,
          icon: Icons.call_split,
          accent: AppModalAccent.blue,
          compact: true,
          maxWidth: 460,
          onClose: () => Navigator.pop(ctx, false),
          bodyPadding: const EdgeInsets.all(18),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Origen: ${batch.batchCode} • Libre: ${maxAvail.toQty()} ${widget.product.unitType}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (maxAvail >= 1.0)
                    ActionChip(
                      label: const Text('1', style: TextStyle(fontSize: 11.5)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => qtyCtrl.text = '1',
                    ),
                  if (maxAvail >= 2.0)
                    ActionChip(
                      label: const Text('2', style: TextStyle(fontSize: 11.5)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => qtyCtrl.text = '2',
                    ),
                  ActionChip(
                    label: Text(
                      'Mitad (${(maxAvail / 2).toQty()})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        qtyCtrl.text = (maxAvail / 2).toQty(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText:
                      'Cantidad a pasar a vitrina (${widget.product.unitType}) *',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_available, size: 17),
                label: Text(
                  'Nuevo Vto. en Vitrina: ${DateFormat('dd/MM/yyyy').format(displayExp)}',
                ),
                onPressed: () async {
                  final picked = await showCompactDatePicker(
                    context: ctx,
                    initialDate: displayExp,
                    helpText: 'Fecha de vencimiento en exhibidor',
                  );
                  if (picked != null) {
                    setModalState(() => displayExp = picked);
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código de sub-lote (opcional)',
                  hintText: 'Ej: auto-generado (-V1)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  value: printLabelNow,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Imprimir etiqueta térmica L# del lote de vitrina al guardar',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  onChanged: (v) =>
                      setModalState(() => printLabelNow = v == true),
                ),
              ),
            ],
          ),
          footerActions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.call_split),
              label: const Text('Pasar a Vitrina'),
              onPressed: () {
                final q = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim());
                if (q == null || q <= 0 || q > maxAvail + 0.001) {
                  SnackBarService.warning(
                    ctx,
                    'La cantidad debe estar entre 0 y ${maxAvail.toQty()}.',
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
      ),
    );

    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim());
    final code = codeCtrl.text.trim();
    final notes = notesCtrl.text.trim();
    qtyCtrl.dispose();
    codeCtrl.dispose();
    notesCtrl.dispose();

    if (confirmed != true || qty == null || !mounted) return;

    setState(() => _submitting = true);
    Map<String, dynamic>? splitResponse;
    final ok = await AdminPinDialog.protectAction(
      context,
      action: 'Pasar ${qty.toQty()} ${widget.product.unitType} a vitrina',
      permissionKey: AppPermissions.adjustStock,
      onAuthorized: () async {
        splitResponse = await widget.provider.splitBatch(
          batch.id,
          quantity: qty,
          expirationDate: _formatIso(displayExp),
          batchCode: code.isNotEmpty ? code : null,
          notes: notes.isNotEmpty ? notes : null,
        );
      },
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (!ok) return;

    if (splitResponse == null) {
      SnackBarService.error(
        context,
        widget.provider.errorMessage ?? 'No se pudo dividir el lote.',
      );
      return;
    }

    final rawNewBatch = splitResponse!['batch'];
    ProductBatchModel? newBatchModel;
    if (rawNewBatch is Map) {
      newBatchModel = ProductBatchModel.fromJson(
        Map<String, dynamic>.from(rawNewBatch),
      );
    }

    SnackBarService.success(
      context,
      'Sub-lote ${newBatchModel?.batchCode ?? ''} creado en vitrina (${qty.toQty()} ${widget.product.unitType}).',
    );
    await _loadBatches();

    if (printLabelNow && newBatchModel != null && mounted) {
      await showDialog(
        context: context,
        builder: (_) => PrintLabelsDialog(
          products: [widget.product],
          batchByProductId: {widget.product.id: newBatchModel!},
          initialQuantities: {
            widget.product.id:
                widget.product.isSoldByWeight ? 1 : qty.ceil().clamp(1, 500),
          },
        ),
      );
    }
  }

  Widget _buildStatusBadge(ProductBatchModel b) {
    Color bg;
    Color fg;
    String label;
    if (b.isDeficit) {
      bg = Colors.deepOrange.shade50;
      fg = Colors.deepOrange.shade900;
      label = 'DÉFICIT';
    } else if (b.isWrittenOff) {
      bg = Colors.red.shade50;
      fg = Colors.red.shade800;
      label = 'MERMA';
    } else if (b.isExhausted || b.remainingQuantity <= 0) {
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade700;
      label = 'AGOTADO';
    } else if (b.isExpired) {
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
      label = 'VENCIDO';
    } else if (b.daysUntilExpiry != null && b.daysUntilExpiry! <= 3) {
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade900;
      label = b.daysUntilExpiry == 0
          ? 'VENCE HOY'
          : 'VENCE EN ${b.daysUntilExpiry}D';
    } else {
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
      label = 'ACTIVO';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allBatches = _response?.batches ?? const <ProductBatchModel>[];
    final visibleBatches = _showClosed
        ? allBatches
        : allBatches
            .where((b) => b.isActive || b.isDeficit || b.remainingQuantity > 0)
            .toList();
    final hasDeficit = allBatches.any((b) => b.isDeficit);

    return AppModalShell(
      title: 'Lotes y Vencimientos: ${widget.product.name}',
      subtitle:
          'Stock total: ${(_response?.stock ?? widget.product.stock).toUnitStockDisplay(isSoldByWeight: widget.product.isSoldByWeight, unitSuffix: widget.product.unitType)} • Salida: ${(_response?.lotDeductionPolicy ?? widget.product.lotDeductionPolicy) == 'fifo' ? 'Más antiguo primero' : 'Vence antes primero'}',
      icon: Icons.layers_outlined,
      accent: AppModalAccent.teal,
      maxWidth: 840,
      maxHeight: 680,
      expandBody: true,
      topBar: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        decoration: const BoxDecoration(
          color: AppColors.surfaceMuted,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text(
                'Ver historial completo',
                style: TextStyle(fontSize: 12),
              ),
              selected: _showClosed,
              onSelected: (v) => setState(() => _showClosed = v),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nuevo Lote'),
              onPressed: _submitting ? null : _openCreateBatchDialog,
            ),
          ],
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasDeficit) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.deepOrange.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.deepOrange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hay ventas registradas sin lote respaldatorio (DÉFICIT). Al cargar una compra o nueva producción, el sistema absorberá automáticamente ese saldo negativo.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, style: const TextStyle(color: Colors.red)),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Reintentar'),
                                  onPressed: _loadBatches,
                                ),
                              ],
                            ),
                          )
                        : visibleBatches.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_2_outlined,
                                        size: 46, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text(
                                      allBatches.isEmpty
                                          ? 'Este producto todavía no tiene lotes registrados.'
                                          : 'No hay lotes activos. Activá "Ver historial completo" para ver agotados o mermas.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: visibleBatches.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, idx) {
                                  final b = visibleBatches[idx];
                                  final canSellActions =
                                      !b.isDeficit && !b.isWrittenOff && b.remainingQuantity > 0;

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: b.isDeficit
                                          ? Colors.deepOrange.shade50.withValues(alpha: 0.4)
                                          : (b.isExpired && b.remainingQuantity > 0
                                              ? Colors.red.shade50.withValues(alpha: 0.45)
                                              : Colors.grey.shade50),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: b.isExpired && b.remainingQuantity > 0
                                            ? Colors.red.shade200
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 4,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                _buildStatusBadge(b),
                                                Text(
                                                  b.batchCode,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13.5,
                                                  ),
                                                ),
                                                Text(
                                                  '• ${_sourceLabel(b.sourceType)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                                if (b.supplierName != null)
                                                  Text(
                                                    '(${b.supplierName})',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: Colors.grey.shade600,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 14,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  'Vence: ${_formatDate(b.expirationDate)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: b.expirationDate != null
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                    color: b.isExpired && b.remainingQuantity > 0
                                                        ? Colors.red.shade800
                                                        : Colors.grey.shade800,
                                                  ),
                                                ),
                                                if (b.manufacturedAt != null)
                                                  Text(
                                                    'Elab: ${_formatDate(b.manufacturedAt)}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                                if (b.unitCost != null)
                                                  Text(
                                                    'Costo u.: \$${b.unitCost!.toCurrency()}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            if (b.notes != null && b.notes!.trim().isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 3),
                                                child: Text(
                                                  b.notes!,
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontStyle: FontStyle.italic,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '${b.remainingQuantity.toQty()} / ${b.initialQuantity.toQty()} ${widget.product.unitType}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13.5,
                                                    color: b.remainingQuantity < 0
                                                        ? Colors.deepOrange.shade800
                                                        : Colors.teal.shade800,
                                                  ),
                                                ),
                                                if (b.reservedQuantity > 0)
                                                  Text(
                                                    'Reserv: ${b.reservedQuantity.toQty()} • Libre: ${b.availableToSell.toQty()}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.amber.shade900,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(width: 8),
                                            if (!b.isDeficit) ...[
                                              if (!b.isWrittenOff && b.availableToSell > 0.0005)
                                                IconButton(
                                                  tooltip: 'Pasar a Vitrina (Dividir Lote)',
                                                  icon: const Icon(Icons.call_split, size: 19),
                                                  color: Colors.blue.shade700,
                                                  onPressed: _submitting
                                                      ? null
                                                      : () => _openSplitBatchDialog(b),
                                                ),
                                              if (_canUseProduction(context) &&
                                                  !b.isWrittenOff &&
                                                  b.availableToSell > 0.0005)
                                                IconButton(
                                                  tooltip: 'Transformar en otra receta',
                                                  icon: const Icon(Icons.bakery_dining_outlined, size: 19),
                                                  color: Colors.teal.shade700,
                                                  onPressed: _submitting
                                                      ? null
                                                      : () async {
                                                          await showDialog(
                                                            context: context,
                                                            builder: (_) => ProductionOrdersDialog(
                                                              provider: widget.provider,
                                                              filterIngredientProductId:
                                                                  widget.product.id,
                                                              initialExplicitBatchId: b.id,
                                                              initialExplicitBatchCode: b.batchCode,
                                                              initialExplicitBatchAvailableQty:
                                                                  b.availableToSell,
                                                            ),
                                                          );
                                                          if (mounted) _loadBatches();
                                                        },
                                                ),
                                              IconButton(
                                                tooltip: 'Imprimir Etiqueta Térmica del Lote',
                                                icon: const Icon(Icons.qr_code_2, size: 20),
                                                color: AppColors.indigo,
                                                onPressed: () {
                                                  showDialog(
                                                    context: context,
                                                    builder: (_) => PrintLabelsDialog(
                                                      products: [widget.product],
                                                      batchByProductId: {widget.product.id: b},
                                                    ),
                                                  );
                                                },
                                              ),
                                              IconButton(
                                                tooltip: 'Editar código / vencimiento',
                                                icon: const Icon(Icons.edit_calendar_outlined, size: 19),
                                                color: Colors.blueGrey,
                                                onPressed: _submitting
                                                    ? null
                                                    : () => _openEditBatchDialog(b),
                                              ),
                                            ],
                                            if (canSellActions)
                                              IconButton(
                                                tooltip: 'Registrar Merma / Descarte',
                                                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                                                color: Colors.deepOrange,
                                                onPressed: _submitting
                                                    ? null
                                                    : () => _openWriteOffDialog(b),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
        ],
      ),
      footerLeading: IconButton(
        tooltip: 'Refrescar lista',
        icon: const Icon(Icons.refresh),
        onPressed: _loading ? null : _loadBatches,
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
