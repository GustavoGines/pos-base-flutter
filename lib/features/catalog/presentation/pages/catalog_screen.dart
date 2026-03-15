import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/catalog_provider.dart';
import '../../domain/entities/product.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../widgets/categories_manager_dialog.dart';
import '../widgets/print_labels_dialog.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({Key? key}) : super(key: key);

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CatalogProvider>().loadProducts();
    });
  }

  Future<void> _openCategoriesManager(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => const CategoriesManagerDialog(),
    );
    // Al cerrar el Dialog, recargamos para que los dropdowns de producto
    // reflejen las nuevas categorías
    if (mounted) {
      context.read<CatalogProvider>().loadProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CatalogProvider>(
      builder: (context, provider, _) {
        final filtered = provider.products.where((p) =>
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (p.barcode?.contains(_searchQuery) ?? false) ||
          p.internalCode.contains(_searchQuery),
        ).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Catálogo de Productos'),
            centerTitle: false,
            actions: [
              // Botón Gestionar Categorías
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.label_outline, size: 18),
                  label: const Text('Categorías'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3B82F6),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                  ),
                  onPressed: () => _openCategoriesManager(context),
                ),
              ),
              // Botón Aumento Masivo
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilledButton.icon(
                  icon: const Icon(Icons.trending_up, size: 18),
                  label: const Text('Aumento Masivo'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                  onPressed: provider.isLoading
                      ? null
                      : () => _showBulkUpdateDialog(context, provider),
                ),
              ),
              // Botón Nuevo Producto
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nuevo Producto'),
                  onPressed: () => _showProductForm(context, provider),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Barra de búsqueda
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, código de barras o código interno...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              // Estado de carga / error
              if (provider.isLoading)
                const LinearProgressIndicator(),
              if (provider.errorMessage != null)
                Container(
                  color: Colors.red.shade50,
                  padding: const EdgeInsets.all(8),
                  child: Text(provider.errorMessage!, style: TextStyle(color: Colors.red.shade700)),
                ),
              // Tabla de productos
              Expanded(
                child: filtered.isEmpty && !provider.isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text('No se encontraron productos', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                          ],
                        ),
                      )
                    : _buildProductsTable(filtered, provider),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductsTable(List<Product> products, CatalogProvider provider) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          horizontalMargin: 16,
          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
          columns: const [
            DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Cód. Barras', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Cód. Interno', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Categoría', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Costo', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Venta', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Balanza', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Activo', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: products.map((p) => DataRow(
            cells: [
              DataCell(Text(p.id.toString())),
              DataCell(Text(p.name)),
              DataCell(Text(p.barcode ?? '—')),
              DataCell(
                Text(p.internalCode, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey.shade700)),
              ),
              DataCell(Text(p.category?.name ?? '—')),
              DataCell(Text('\$${p.costPrice.toStringAsFixed(2)}')),
              DataCell(
                Text('\$${p.sellingPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              DataCell(Text(p.isSoldByWeight ? '${p.stock.toStringAsFixed(3)} kg' : p.stock.toStringAsFixed(0))),
              DataCell(
                Icon(p.isSoldByWeight ? Icons.scale : Icons.inventory_2, size: 18, color: p.isSoldByWeight ? Colors.deepPurple : Colors.blueGrey),
              ),
              DataCell(
                Icon(p.active ? Icons.check_circle : Icons.cancel, color: p.active ? Colors.green : Colors.red, size: 20),
              ),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.print_outlined, size: 18),
                    color: Colors.deepPurple,
                    tooltip: 'Imprimir Etiquetas',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => PrintLabelsDialog(product: p),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.warehouse_outlined, size: 18),
                    color: Colors.teal,
                    tooltip: 'Ajuste de Stock',
                    onPressed: () => _showStockAdjustment(context, provider, p),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: Colors.blue,
                    tooltip: 'Editar',
                    onPressed: () => _showProductForm(context, provider, product: p),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Colors.red,
                    tooltip: 'Eliminar',
                    onPressed: () => _confirmDelete(context, provider, p),
                  ),
                ],
              )),
            ],
          )).toList(),
        ),
      ),
    );
  }

  void _showStockAdjustment(BuildContext ctx, CatalogProvider provider, Product p) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => StockAdjustmentDialog(provider: provider, product: p),
    );
  }

  void _showProductForm(BuildContext ctx, CatalogProvider provider, {Product? product}) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => ProductFormDialog(
        provider: provider,
        product: product,
      ),
    );
  }

  void _showBulkUpdateDialog(BuildContext ctx, CatalogProvider provider) {
    showDialog(
      context: ctx,
      builder: (_) => BulkPriceUpdateDialog(provider: provider),
    );
  }

  void _confirmDelete(BuildContext ctx, CatalogProvider provider, Product p) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Seguro de eliminar el producto "${p.name}"?\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true && ctx.mounted) {
      final ok = await provider.deleteProduct(p.id);
      if (ctx.mounted) {
        if (ok) {
          SnackBarService.success(ctx, 'Producto "${p.name}" eliminado.');
        } else {
          SnackBarService.error(ctx, provider.errorMessage ?? 'Error al eliminar.');
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORMULARIO CREAR / EDITAR PRODUCTO
// ─────────────────────────────────────────────────────────────────────────────
class ProductFormDialog extends StatefulWidget {
  final CatalogProvider provider;
  final Product? product;

  const ProductFormDialog({Key? key, required this.provider, this.product}) : super(key: key);

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _barcodeCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _stockCtrl;
  bool _isSoldByWeight = false;
  bool _active = true;
  int? _categoryId;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _costCtrl = TextEditingController(text: p != null ? p.costPrice.toStringAsFixed(2) : '');
    _priceCtrl = TextEditingController(text: p != null ? p.sellingPrice.toStringAsFixed(2) : '');
    _stockCtrl = TextEditingController(text: p != null ? p.stock.toStringAsFixed(p.isSoldByWeight ? 3 : 0) : '0');
    _isSoldByWeight = p?.isSoldByWeight ?? false;
    _active = p?.active ?? true;
    _categoryId = p?.category?.id;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final data = {
      'name': _nameCtrl.text.trim(),
      if (_barcodeCtrl.text.isNotEmpty) 'barcode': _barcodeCtrl.text.trim(),
      'cost_price': double.parse(_costCtrl.text.replaceAll(',', '.')),
      'selling_price': double.parse(_priceCtrl.text.replaceAll(',', '.')),
      'stock': double.parse(_stockCtrl.text.replaceAll(',', '.')),
      'is_sold_by_weight': _isSoldByWeight,
      'active': _active,
      if (_categoryId != null) 'category_id': _categoryId,
    };

    final bool ok = _isEditing
        ? await widget.provider.updateProduct(widget.product!.id, data)
        : await widget.provider.createProduct(data);

    if (mounted) {
      if (ok) {
        Navigator.of(context).pop();
        SnackBarService.success(context, _isEditing ? 'Producto actualizado correctamente.' : '¡Producto creado exitosamente!');
      } else {
        SnackBarService.error(context, widget.provider.errorMessage ?? 'Error desconocido.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.provider.categories;
    return AlertDialog(
      title: Text(_isEditing ? 'Editar Producto' : 'Nuevo Producto'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nombre
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre del Producto *', prefixIcon: Icon(Icons.label_outline)),
                  validator: (v) => v == null || v.isEmpty ? 'El nombre es obligatorio' : null,
                ),
                const SizedBox(height: 12),
                // Código de barras
                TextFormField(
                  controller: _barcodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código de Barras (opcional)',
                    prefixIcon: Icon(Icons.qr_code),
                    helperText: 'Deje vacío para que el sistema genere un código EAN-13 automático',
                  ),
                ),
                const SizedBox(height: 12),
                // Categoría
                if (categories.isNotEmpty)
                  DropdownButtonFormField<int?>(
                    value: _categoryId,
                    decoration: const InputDecoration(labelText: 'Categoría', prefixIcon: Icon(Icons.category_outlined)),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('— Sin categoría —')),
                      ...categories.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                    ],
                    onChanged: (val) => setState(() => _categoryId = val),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _costCtrl,
                        decoration: const InputDecoration(labelText: 'Precio Costo', prefixText: '\$ '),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => (v == null || double.tryParse(v.replaceAll(',', '.')) == null) ? 'Ingrese un monto válido' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _priceCtrl,
                        decoration: const InputDecoration(labelText: 'Precio Venta *', prefixText: '\$ '),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => (v == null || double.tryParse(v.replaceAll(',', '.')) == null) ? 'Ingrese un precio válido' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _stockCtrl,
                  decoration: InputDecoration(
                    labelText: 'Stock inicial',
                    suffixText: _isSoldByWeight ? 'Kg' : 'unidades',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                // Switches
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Venta por peso (balanza)'),
                        value: _isSoldByWeight,
                        onChanged: (v) => setState(() => _isSoldByWeight = v),
                      ),
                    ),
                    Expanded(
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Producto activo'),
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        Consumer<CatalogProvider>(
          builder: (_, p, __) => FilledButton(
            onPressed: p.isLoading ? null : _submit,
            child: p.isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isEditing ? 'Guardar Cambios' : 'Crear Producto'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODAL DE AUMENTO MASIVO DE PRECIOS
// ─────────────────────────────────────────────────────────────────────────────
class BulkPriceUpdateDialog extends StatefulWidget {
  final CatalogProvider provider;

  const BulkPriceUpdateDialog({Key? key, required this.provider}) : super(key: key);

  @override
  State<BulkPriceUpdateDialog> createState() => _BulkPriceUpdateDialogState();
}

class _BulkPriceUpdateDialogState extends State<BulkPriceUpdateDialog> {
  final _percentCtrl = TextEditingController();
  int? _selectedCategoryId;

  @override
  void dispose() {
    _percentCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final double? pct = double.tryParse(_percentCtrl.text.replaceAll(',', '.'));
    if (pct == null) {
      SnackBarService.error(context, 'Ingrese un porcentaje válido (ej: 15 o -10).');
      return;
    }

    final String filterLabel = _selectedCategoryId == null
        ? 'todo el catálogo'
        : 'la categoría seleccionada';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Actualización'),
        content: Text.rich(
          TextSpan(
            style: Theme.of(ctx).textTheme.bodyMedium,
            children: [
              const TextSpan(text: '¿Aplicar un '),
              TextSpan(
                text: '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: pct >= 0 ? Colors.deepOrange.shade700 : Colors.red.shade700,
                ),
              ),
              TextSpan(text: ' sobre el precio de venta de $filterLabel?'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final message = await widget.provider.bulkPriceUpdate(
      percentage: pct,
      categoryId: _selectedCategoryId,
    );

    if (mounted) {
      Navigator.of(context).pop();
      if (message != null) {
        SnackBarService.success(context, '¡Precios actualizados! $message');
      } else {
        SnackBarService.error(context, widget.provider.errorMessage ?? 'Error al actualizar precios.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.provider.categories;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.trending_up, color: Colors.deepOrange.shade700),
          const SizedBox(width: 8),
          const Text('Aumento Masivo de Precios'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Esta operación actualizará el precio de venta de forma masiva.\nUse valores negativos para aplicar descuentos (ej: -10 para -10%).',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _percentCtrl,
              decoration: const InputDecoration(
                labelText: 'Porcentaje de variación (%)',
                hintText: 'Ej: 15 para +15% o -10 para -10%',
                prefixIcon: Icon(Icons.percent),
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(
                labelText: 'Aplica a',
                prefixIcon: Icon(Icons.filter_alt_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('📦 Todo el catálogo')),
                ...categories.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text('📂 ${c.name}'))),
              ],
              onChanged: (val) => setState(() => _selectedCategoryId = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        Consumer<CatalogProvider>(
          builder: (_, p, __) => FilledButton.icon(
            icon: const Icon(Icons.bolt),
            label: p.isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Aplicar Aumento'),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: p.isLoading ? null : _apply,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODAL DE AJUSTE DE STOCK
// ─────────────────────────────────────────────────────────────────────────────
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
  final _notesCtrl = TextEditingController();
  String _selectedType = 'in';  // 'in' = Ingreso, 'out' = Egreso

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final double? qty = double.tryParse(_quantityCtrl.text.replaceAll(',', '.'));
    if (qty == null || qty <= 0) {
      SnackBarService.error(context, 'Ingrese una cantidad válida mayor a cero.');
      return;
    }

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

    final ok = await widget.provider.adjustStock(
      productId: widget.product.id,
      type: _selectedType,
      quantity: qty,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    if (mounted) {
      Navigator.of(context).pop();
      if (ok) {
        final newStock = widget.provider.products
            .firstWhere((p) => p.id == widget.product.id,
                orElse: () => widget.product)
            .stock;
        final action = _selectedType == 'in' ? 'ingresaron' : 'egresaron';
        SnackBarService.success(
          context,
          '✓ Se $action ${qty.toStringAsFixed(widget.product.isSoldByWeight ? 3 : 0)} $unitLabel. Stock actual: ${newStock.toStringAsFixed(widget.product.isSoldByWeight ? 3 : 0)} $unitLabel.',
        );
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

// Botón selector de tipo (Ingreso/Egreso)
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
