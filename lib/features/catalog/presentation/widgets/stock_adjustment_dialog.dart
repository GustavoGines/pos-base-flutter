import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';

class StockAdjustmentDialog extends StatefulWidget {
  final CatalogProvider provider;
  final Product product;

  const StockAdjustmentDialog({Key? key, required this.provider, required this.product})
      : super(key: key);

  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _quantityCtrl = TextEditingController();
  final _minStockCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _selectedType = 'in'; // 'in' = Ingreso, 'out' = Egreso

  @override
  void initState() {
    super.initState();
    _minStockCtrl.text = widget.product.minStock?.toStringAsFixed(0) ?? '';
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _minStockCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final double? qty = _quantityCtrl.text.isEmpty ? 0 : double.tryParse(_quantityCtrl.text.replaceAll(',', '.'));
    final double? minStockVal = _minStockCtrl.text.trim().isNotEmpty ? double.tryParse(_minStockCtrl.text.replaceAll(',', '.')) : null;

    // Validación: debe haber cantidad > 0 O un cambio en el stock mínimo
    bool hasMinStockChange = minStockVal != widget.product.minStock;
    if ((qty == null || qty <= 0) && !hasMinStockChange) {
      SnackBarService.error(context, 'Ingrese una cantidad válida o modifique el stock mínimo.');
      return;
    }

    if (qty != null && qty > 0) {
      final typeLabel = _selectedType == 'in' ? 'INGRESO' : 'EGRESO';
      final unitLabel = widget.product.isSoldByWeight ? 'Kg' : 'unidades';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Confirmar $typeLabel de Stock'),
          content: Text.rich(
            TextSpan(
              style: Theme.of(ctx).textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: '${qty.toStringAsFixed(widget.product.isSoldByWeight ? 3 : 0)} $unitLabel',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _selectedType == 'in' ? Colors.teal.shade700 : Colors.orange.shade800,
                  ),
                ),
                const TextSpan(text: ' de '),
                TextSpan(
                  text: '"${widget.product.name}"',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _selectedType == 'in' ? Colors.teal : Colors.orange.shade700,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Confirmar $typeLabel'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    final ok = await widget.provider.adjustStock(
      productId: widget.product.id,
      type: _selectedType == 'in' ? 'increment' : 'decrement',
      quantity: qty ?? 0,
      minStock: minStockVal,
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
    );

    if (mounted) {
      Navigator.of(context).pop();
      if (ok) {
        final newStock = widget.provider.products
            .firstWhere((p) => p.id == widget.product.id,
                orElse: () => widget.product as dynamic)
            .stock;
        
        String snackMsg;
        if (qty != null && qty > 0) {
          final action = _selectedType == 'in' ? 'ingresaron' : 'egresaron';
          final unitLabel = widget.product.isSoldByWeight ? 'Kg' : 'unidades';
          snackMsg = '✓ Se $action ${qty.toStringAsFixed(widget.product.isSoldByWeight ? 3 : 0)} $unitLabel. Stock actual: ${newStock.toStringAsFixed(widget.product.isSoldByWeight ? 3 : 0)} $unitLabel.';
        } else {
          snackMsg = '✓ Stock Mínimo actualizado correctamente.';
        }
        
        SnackBarService.success(context, snackMsg);
      } else {
        SnackBarService.error(context, widget.provider.errorMessage ?? 'Error al ajustar stock.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final unitLabel = product.isSoldByWeight ? 'Kg' : 'unidades';
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warehouse_outlined, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          const Text('Ajuste de Stock'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 420,
        child: Column(
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
                  const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.blueGrey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          'Stock actual: ${product.stock.toStringAsFixed(product.isSoldByWeight ? 3 : 0)} $unitLabel',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cantidad a ${_selectedType == 'in' ? 'ingresar' : 'egresar'}',
                suffixText: unitLabel,
                prefixIcon: Icon(
                  _selectedType == 'in' ? Icons.add : Icons.remove,
                  color: _selectedType == 'in' ? Colors.teal : Colors.orange.shade700,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Stock Mínimo (Configuración rápida)
            TextField(
              controller: _minStockCtrl,
              decoration: const InputDecoration(
                labelText: 'Stock Mínimo (Alerta)',
                prefixIcon: Icon(Icons.notification_important_outlined),
                hintText: 'Umbral para aviso de reposición',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        Consumer<CatalogProvider>(
          builder: (_, p, __) => FilledButton.icon(
            icon: p.isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_selectedType == 'in' ? Icons.add : Icons.remove, size: 18),
            label: Text(_selectedType == 'in' ? 'Registrar Ingreso' : 'Registrar Egreso'),
            style: FilledButton.styleFrom(
              backgroundColor: _selectedType == 'in' ? Colors.teal : Colors.orange.shade700,
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
            Icon(icon, color: isSelected ? Colors.white : Colors.grey.shade600, size: 28),
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
