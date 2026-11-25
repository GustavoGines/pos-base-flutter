import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_batch_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/product_batches_dialog.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class StockAdjustmentDialog extends StatefulWidget {
  final CatalogProvider provider;
  final Product product;

  const StockAdjustmentDialog(
      {super.key, required this.provider, required this.product});

  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _quantityCtrl = TextEditingController();
  final _minStockCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _batchCodeCtrl = TextEditingController();
  final _validityDaysCtrl = TextEditingController();
  String _selectedType = 'in'; // 'in' = Ingreso, 'out' = Egreso
  DateTime? _batchExpDate;
  bool _isWaste = false;
  int? _selectedOutBatchId;
  List<ProductBatchModel> _activeBatches = const [];
  bool _canUseBatches = true;

  bool _resolveCanUseBatches() {
    try {
      final s = Provider.of<SettingsProvider?>(context, listen: false);
      if (s != null) {
        final baseProfile = s.safeVerticalProfile;
        Rubro? itemRubro = widget.product.category?.rubro;
        final rId =
            widget.product.category?.rubroId ?? widget.product.category?.rubro?.id;
        if (rId != null) {
          itemRubro = widget.provider.safeRubros
                  .where((r) => r.id == rId)
                  .firstOrNull ??
              itemRubro;
        }
        final itemProfile = baseProfile.resolveItemProfile(
          itemRubro,
          hasMultiRubro: s.features.multiRubro,
        );
        final storeHasNativeBatch =
            BusinessVerticalProfile.isNativeBatchVertical(
          baseProfile.primaryType,
          baseProfile.secondaryTypes,
        );
        return itemProfile.canUseBatchExpiration(
          featureBatchExpiration: s.features.batchExpiration,
          featureProduction: s.features.production,
          storeHasNativeBatchVertical: storeHasNativeBatch,
        );
      }
    } catch (_) {}
    return true;
  }

  String _resolveUnitLabel(Product product) {
    final u = product.unitType.trim().toLowerCase();
    if (u == 'un' || u.isEmpty) {
      if (!product.isSoldByWeight) return 'unidades';
      bool businessUsesScale = true;
      try {
        businessUsesScale = Provider.of<SettingsProvider?>(context, listen: false)
                ?.safeVerticalProfile
                .canUseScaleWeight ??
            true;
      } catch (_) {}
      return product.isDiscreteFractionalItem(
              businessUsesScaleWeight: businessUsesScale)
          ? 'unidades'
          : 'Kg';
    }
    return product.unitShortLabel;
  }

  @override
  void initState() {
    super.initState();
    _minStockCtrl.text = widget.product.minStock?.toStringAsFixed(0) ?? '';
    _canUseBatches = _resolveCanUseBatches();
    if (_canUseBatches &&
        widget.product.vencimientoDias != null &&
        widget.product.vencimientoDias! > 0) {
      _batchExpDate =
          DateTime.now().add(Duration(days: widget.product.vencimientoDias!));
      _validityDaysCtrl.text = widget.product.vencimientoDias!.toString();
    }
    if (_canUseBatches && !widget.product.isCombo && !widget.product.isService) {
      _loadActiveBatches();
    }
  }

  Future<void> _loadActiveBatches() async {
    try {
      final res = await widget.provider
          .fetchProductBatches(widget.product.id, includeClosed: false);
      if (mounted) {
        setState(() => _activeBatches = res.batches.where((b) => b.isActive).toList());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _minStockCtrl.dispose();
    _notesCtrl.dispose();
    _batchCodeCtrl.dispose();
    _validityDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final double? qty = _quantityCtrl.text.isEmpty
        ? 0
        : double.tryParse(_quantityCtrl.text.replaceAll(',', '.'));
    final double? minStockVal = _minStockCtrl.text.trim().isNotEmpty
        ? double.tryParse(_minStockCtrl.text.replaceAll(',', '.'))
        : null;

    // Validación: debe haber cantidad > 0 O un cambio en el stock mínimo
    bool hasMinStockChange = minStockVal != widget.product.minStock;
    if ((qty == null || qty <= 0) && !hasMinStockChange) {
      SnackBarService.error(
          context, 'Ingrese una cantidad válida o modifique el stock mínimo.');
      return;
    }

    if (qty != null && qty > 0) {
      final typeLabel = _selectedType == 'in' ? 'INGRESO' : 'EGRESO';
      final unitLabel = _resolveUnitLabel(widget.product);
      final qtyStr = qty.toStringAsFixed(widget.product.isSoldByWeight ? 3 : 0);
      final confirmed = await AppConfirmDialog.show(
        context,
        title: 'Confirmar $typeLabel de Stock',
        message: '$qtyStr $unitLabel de "${widget.product.name}"',
        confirmLabel: 'Confirmar $typeLabel',
        cancelLabel: 'Cancelar',
        icon: _selectedType == 'in'
            ? Icons.add_box_outlined
            : Icons.indeterminate_check_box_outlined,
        isDestructive: _selectedType != 'in',
      );

      if (confirmed != true) return;
    }

    final ok = await widget.provider.adjustStock(
      productId: widget.product.id,
      type: _selectedType == 'in' ? 'increment' : 'decrement',
      quantity: qty ?? 0,
      minStock: minStockVal,
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      batchId: _canUseBatches && _selectedType == 'out' ? _selectedOutBatchId : null,
      batchCode: _canUseBatches &&
              _selectedType == 'in' &&
              _batchCodeCtrl.text.trim().isNotEmpty
          ? _batchCodeCtrl.text.trim()
          : null,
      expirationDate: _canUseBatches &&
              _selectedType == 'in' &&
              _batchExpDate != null
          ? DateFormat('yyyy-MM-dd').format(_batchExpDate!)
          : null,
      reasonCode: _selectedType == 'out' && _isWaste ? 'waste' : null,
    );

    if (mounted) {
      InventoryAlertsProvider? alertsProv;
      try {
        alertsProv = Provider.of<InventoryAlertsProvider>(context, listen: false);
      } catch (_) {}

      if (ok) {
        final updatedFromProvider =
            widget.provider.lastUpdatedProduct?.id == widget.product.id
                ? widget.provider.lastUpdatedProduct
                : widget.provider.products
                    .where((p) => p.id == widget.product.id)
                    .firstOrNull;
        if (updatedFromProvider != null) {
          try {
            context.read<PosProvider>().syncUpdatedCatalogProduct(updatedFromProvider);
          } catch (_) {}
        }
        final double computedFallback = _selectedType == 'in'
            ? widget.product.stock + (qty ?? 0)
            : widget.product.stock - (qty ?? 0);
        final newStock = updatedFromProvider?.stock ?? computedFallback;

        String snackMsg;
        if (qty != null && qty > 0) {
          final action = _selectedType == 'in' ? 'ingresaron' : 'egresaron';
          final unitLabel = _resolveUnitLabel(widget.product);
          snackMsg =
              '✓ Se $action ${qty.toStringAsFixed(widget.product.isSoldByWeight ? 3 : 0)} $unitLabel. Stock actual: ${newStock.toStringAsFixed(widget.product.isSoldByWeight ? 3 : 0)} $unitLabel.';
        } else {
          snackMsg = '✓ Stock Mínimo actualizado correctamente.';
        }

        SnackBarService.success(context, snackMsg);
        Navigator.of(context).pop();

        // Disparar sincronización global silenciosa del Motor Cero Gravedad
        alertsProv?.fetchAlerts();
      } else {
        SnackBarService.error(
            context, widget.provider.errorMessage ?? 'Error al ajustar stock.');
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final unitLabel = _resolveUnitLabel(product);
    return AppModalShell(
      title: 'Ajuste de Stock',
      subtitle: product.name,
      icon: Icons.warehouse_outlined,
      accent: AppModalAccent.teal,
      compact: true,
      maxWidth: 480,
      bodyPadding: const EdgeInsets.all(18),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // Info del producto
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 20, color: Colors.blueGrey),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            'Stock actual: ${product.stock.toStringAsFixed(product.isSoldByWeight ? 3 : 0)} $unitLabel',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (_canUseBatches && !product.isCombo && !product.isService)
                      TextButton.icon(
                        icon: const Icon(Icons.layers_outlined, size: 17),
                        label: Text(
                          _activeBatches.isNotEmpty
                              ? 'Lotes (${_activeBatches.length})'
                              : 'Ver Lotes',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => ProductBatchesDialog(
                              provider: widget.provider,
                              product: product,
                            ),
                          ).then((_) {
                            if (mounted) _loadActiveBatches();
                          });
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Selector de tipo: Ingreso / Egreso
            Row(
              children: [
                Expanded(
                  child: _TypeButton(
                    label: 'Ingreso (+)',
                    icon: Icons.add_circle_outline,
                    selectedType: _selectedType,
                    type: 'in',
                    activeColor: Colors.teal,
                    onTap: () => setState(() => _selectedType = 'in'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeButton(
                    label: 'Egreso (−)',
                    icon: Icons.remove_circle_outline,
                    selectedType: _selectedType,
                    type: 'out',
                    activeColor: Colors.orange.shade700,
                    onTap: () => setState(() => _selectedType = 'out'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cantidad
            TextField(
              controller: _quantityCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    'Cantidad a ${_selectedType == 'in' ? 'ingresar' : 'egresar'}',
                suffixText: unitLabel,
                prefixIcon: Icon(
                  _selectedType == 'in' ? Icons.add : Icons.remove,
                  color: _selectedType == 'in'
                      ? Colors.teal
                      : Colors.orange.shade700,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_canUseBatches &&
                !product.isCombo &&
                !product.isService &&
                _selectedType == 'in') ...[
              TextField(
                controller: _batchCodeCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Código de Lote (opc.)',
                  hintText: 'Auto si vacío',
                  isDense: true,
                  prefixIcon: Icon(Icons.qr_code_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 118,
                    child: TextField(
                      controller: _validityDaysCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Validez',
                        suffixText: 'd',
                        isDense: true,
                        prefixIcon: Icon(Icons.hourglass_bottom_outlined, size: 17),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        final trimmed = val.trim();
                        if (trimmed.isEmpty) {
                          setState(() => _batchExpDate = null);
                          return;
                        }
                        final n = int.tryParse(trimmed);
                        if (n != null && n >= 1 && n <= 3650) {
                          setState(() {
                            _batchExpDate =
                                DateTime.now().add(Duration(days: n));
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 14),
                      ),
                      icon: Icon(
                        Icons.event_available_outlined,
                        size: 17,
                        color: _batchExpDate != null ? Colors.deepOrange : null,
                      ),
                      label: Text(
                        _batchExpDate != null
                            ? 'Vto: ${DateFormat('dd/MM/yy').format(_batchExpDate!)}'
                            : 'Vencimiento (opc)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      onPressed: () async {
                        final picked = await showCompactDatePicker(
                          context: context,
                          initialDate: _batchExpDate ??
                              DateTime.now().add(const Duration(days: 7)),
                          helpText: 'Vencimiento del Lote Entrante',
                        );
                        if (picked != null) {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final expDay = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                          );
                          final diff = expDay.difference(today).inDays;
                          setState(() {
                            _batchExpDate = picked;
                            _validityDaysCtrl.text =
                                (diff >= 1 && diff <= 3650)
                                    ? diff.toString()
                                    : '';
                          });
                        }
                      },
                    ),
                  ),
                  if (_batchExpDate != null ||
                      _validityDaysCtrl.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Quitar vencimiento',
                      icon: const Icon(Icons.clear, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        _batchExpDate = null;
                        _validityDaysCtrl.clear();
                      }),
                    ),
                ],
              ),
              if (!product.trackBatches &&
                  (_batchCodeCtrl.text.trim().isNotEmpty ||
                      _batchExpDate != null)) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.teal.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Al guardar con lote o vencimiento, este producto activará el control por lotes automáticamente (el stock previo queda resguardado por separado).',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.teal.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
            if (!product.isCombo &&
                !product.isService &&
                _selectedType == 'out') ...[
              if (_canUseBatches && _activeBatches.isNotEmpty) ...[
                DropdownButtonFormField<int?>(
                  initialValue: _selectedOutBatchId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Lote a descontar',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.layers_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Automático (lo que vence antes sale primero)'),
                    ),
                    ..._activeBatches.map(
                      (b) => DropdownMenuItem<int?>(
                        value: b.id,
                        child: Text(
                          '${b.batchCode} (${b.remainingQuantity.toQty()} disp.${b.expirationDate != null ? ' • Vto ${b.expirationDate}' : ''})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) =>
                      setState(() => _selectedOutBatchId = val),
                ),
                const SizedBox(height: 8),
              ],
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Registrar como Merma / Descarte (pérdida por vencimiento o rotura)',
                  style: TextStyle(fontSize: 12.5),
                ),
                value: _isWaste,
                onChanged: (v) => setState(() => _isWaste = v),
              ),
              const SizedBox(height: 6),
            ],
            // Stock Mínimo (Configuración rápida)
            TextField(
              controller: _minStockCtrl,
              decoration: const InputDecoration(
                labelText: 'Stock Mínimo (Alerta)',
                prefixIcon: Icon(Icons.notification_important_outlined),
                hintText: 'Umbral para aviso de reposición',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            // Motivo
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo / Notas (opcional)',
                hintText: 'Ej: Compra proveedor García, Devolución, Rotura...',
                prefixIcon: Icon(Icons.notes_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        Consumer<CatalogProvider>(
          builder: (_, p, __) => FilledButton.icon(
            icon: p.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _selectedType == 'in' ? Icons.add : Icons.remove,
                    size: 18,
                  ),
            label: Text(
              _selectedType == 'in' ? 'Registrar Ingreso' : 'Registrar Egreso',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _selectedType == 'in'
                  ? AppColors.teal
                  : Colors.orange.shade700,
            ),
            onPressed: p.isLoading ? null : _submit,
          ),
        ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final String type;
  final String selectedType;
  final Color activeColor;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.icon,
    required this.type,
    required this.selectedType,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedType == type;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected ? Colors.white : Colors.grey.shade600,
                size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
