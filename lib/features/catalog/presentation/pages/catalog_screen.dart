import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/catalog_provider.dart';
import '../../domain/entities/product.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../widgets/categories_manager_dialog.dart';
import '../widgets/print_labels_dialog.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({Key? key}) : super(key: key);

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  final Map<int, Product> _selectedProducts = {};

  @override
  void initState() {
    super.initState();
    // Siempre resetear la búsqueda al entrar a esta pantalla.
    // Garantiza que el buscador visual y los resultados estén en sincronía.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchController.clear();
      context.read<CatalogProvider>().loadProducts(page: 1, search: '');
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        context.read<CatalogProvider>().loadProducts(page: 1, search: value);
      }
    });
  }

  Future<void> _openCategoriesManager(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => const CategoriesManagerDialog(),
    );
    if (mounted) {
      context.read<CatalogProvider>().loadProducts(page: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CatalogProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: GlobalAppBar(currentRoute: '/catalog'),
          body: Column(
            children: [
              // ── Toolbar: Search + Actions ─────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final searchWidget = ListenableBuilder(
                      listenable: _searchController,
                      builder: (context, _) => TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre, código de barras o código interno...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    context.read<CatalogProvider>().loadProducts(page: 1, search: '');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    );

                    final actionRow = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedProducts.isNotEmpty) ...[
                          PopupMenuButton<int>(
                            tooltip: 'Acciones en Lote',
                            offset: const Offset(0, 45),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            onSelected: (val) {
                              switch (val) {
                                case 1: _bulkUpdateCategory(provider); break;
                                case 2: _bulkToggleActive(provider); break;
                                case 3:
                                  AdminPinDialog.verify(context, action: 'Aumento Masivo Lote', permissionKey: 'manage_catalog').then((auth) {
                                    if (auth && context.mounted) {
                                      showDialog(context: context, builder: (_) => BulkPriceUpdateDialog(provider: provider, targetProductIds: _selectedProducts.keys.toList())).then((_) => setState(() => _selectedProducts.clear()));
                                    }
                                  });
                                  break;
                                case 4: showDialog(context: context, builder: (_) => PrintLabelsDialog(products: _selectedProducts.values.toList())); break;
                                case 5: _confirmBulkDelete(provider); break;
                                case 6: setState(() => _selectedProducts.clear()); break;
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade800,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.checklist, color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Text('Lote (${_selectedProducts.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                                ],
                              ),
                            ),
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.folder_outlined, color: Colors.orange, size: 20), SizedBox(width: 12), Text('Mover Categoría')])),
                              const PopupMenuItem(value: 2, child: Row(children: [Icon(Icons.power_settings_new, color: Colors.teal, size: 20), SizedBox(width: 12), Text('Cambiar Estado')])),
                              const PopupMenuItem(value: 3, child: Row(children: [Icon(Icons.trending_up, color: Colors.deepOrange, size: 20), SizedBox(width: 12), Text('Actualizar Precios')])),
                              const PopupMenuItem(value: 4, child: Row(children: [Icon(Icons.print_outlined, color: Colors.deepPurple, size: 20), SizedBox(width: 12), Text('Imprimir Etiquetas')])),
                              const PopupMenuDivider(),
                              const PopupMenuItem(value: 5, child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 20), SizedBox(width: 12), Text('Eliminar Todo')])),
                              const PopupMenuDivider(),
                              const PopupMenuItem(value: 6, child: Row(children: [Icon(Icons.deselect, color: Colors.grey, size: 20), SizedBox(width: 12), Text('Cancelar Selección')])),
                            ],
                          ),
                          const SizedBox(width: 12),
                        ],
                        OutlinedButton.icon(
                          icon: const Icon(Icons.label_outline, size: 18),
                          label: const Text('Categorías'),
                          onPressed: () async {
                            final auth = await AdminPinDialog.verify(context, action: 'Gestionar Categorías', permissionKey: 'manage_catalog');
                            if (auth && context.mounted) _openCategoriesManager(context);
                          },
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.trending_up, size: 18, color: Colors.deepOrange),
                          label: const Text('Aumento Masivo', style: TextStyle(color: Colors.deepOrange)),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.deepOrange)),
                          onPressed: provider.isLoading
                              ? null
                              : () async {
                                  final auth = await AdminPinDialog.verify(context, action: 'Aumento Masivo de Precios', permissionKey: 'manage_catalog');
                                  if (auth && context.mounted) _showBulkUpdateDialog(context, provider);
                                },
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Nuevo Producto'),
                          onPressed: () async {
                            final auth = await AdminPinDialog.verify(context, action: 'Crear Nuevo Producto', permissionKey: 'manage_catalog');
                            if (auth && context.mounted) _showProductForm(context, provider);
                          },
                        ),
                      ],
                    );

                    if (constraints.maxWidth < 1000) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          searchWidget,
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: actionRow,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: searchWidget),
                        const SizedBox(width: 12),
                        actionRow,
                      ],
                    );
                  },
                ),
              ),
              // ── Loading bar ──────────────────────────────────────
              if (provider.isLoading) const LinearProgressIndicator(),
              if (provider.errorMessage != null)
                Container(
                  color: Colors.red.shade50,
                  padding: const EdgeInsets.all(8),
                  child: Text(provider.errorMessage!, style: TextStyle(color: Colors.red.shade700)),
                ),
              // ── Product Table ─────────────────────────────────────
              Expanded(
                child: provider.products.isEmpty && !provider.isLoading
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
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: 950,
                                maxWidth: constraints.maxWidth > 950 ? constraints.maxWidth : 950,
                              ),
                              child: _buildProductsTable(provider.products, provider),
                            ),
                          );
                        },
                      ),
              ),
              // ── Pagination Controls ───────────────────────────────
              if (!provider.isLoading && provider.lastPage > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: provider.hasPrevPage ? () => provider.prevPage() : null,
                        tooltip: 'Página anterior',
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Página ${provider.currentPage} de ${provider.lastPage}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: provider.hasNextPage ? () => provider.nextPage() : null,
                        tooltip: 'Página siguiente',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductsTable(List<Product> products, CatalogProvider provider) {
    // Responsive flex values para que quepan en pantalla chica
    const int fCheck = 1;
    const int fId = 1;
    const int fNombre = 6;
    const int fBarcode = 3;
    const int fInterno = 2;
    const int fCat = 3;
    const int fCosto = 2;
    const int fVenta = 2;
    const int fStock = 2;
    const int fBal = 1;
    const int fActivo = 1;
    const int fVto = 1;
    const int fAcciones = 3;

    Widget cell(int flexValue, Widget child) => Expanded(
          flex: flexValue,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: child,
          ),
        );

    TextStyle headerStyle() => const TextStyle(fontWeight: FontWeight.bold, fontSize: 13);

    // Sortable header button (Flex)
    Widget sortHeader(int flexValue, String label, String sortKey) {
      final isActive = provider.sortBy == sortKey;
      final isAsc = provider.sortDirection == 'asc';
      return Expanded(
        flex: flexValue,
        child: InkWell(
          onTap: () {
            final newDir = isActive && isAsc ? 'desc' : 'asc';
            provider.loadProducts(page: 1, sortBy: sortKey, sortDirection: newDir);
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: headerStyle().copyWith(color: isActive ? Colors.blue.shade700 : Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 3),
                  Icon(
                    isAsc ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 13,
                    color: Colors.blue.shade700,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    Widget headerRow() => Container(
          color: Colors.grey.shade100,
          child: Row(
            children: [
              cell(
                fCheck,
                Checkbox(
                  value: _selectedProducts.length == products.length && products.isNotEmpty,
                  onChanged: (bool? val) {
                    setState(() {
                      if (val == true) {
                        for (var p in products) {
                          _selectedProducts[p.id] = p;
                        }
                      } else {
                        _selectedProducts.clear();
                      }
                    });
                  },
                ),
              ),
              cell(fId, Text('#', style: headerStyle())),
              sortHeader(fNombre, 'Nombre', 'name'),
              sortHeader(fBarcode, 'Cód. Barras', 'barcode'),
              sortHeader(fInterno, 'Cód. Interno', 'internal_code'),
              sortHeader(fCat, 'Categoría', 'category_id'),
              sortHeader(fCosto, 'Costo', 'cost_price'),
              sortHeader(fVenta, 'Venta', 'selling_price'),
              sortHeader(fStock, 'Stock', 'stock'),
              sortHeader(fBal, 'Balanza', 'is_sold_by_weight'),
              sortHeader(fActivo, 'Activo', 'active'),
              cell(
                fVto,
                Tooltip(
                  message: 'Días de vida útil configurados por producto',
                  child: Text('VTO.', style: headerStyle(), overflow: TextOverflow.ellipsis),
                ),
              ),
              cell(fAcciones, Text('Acciones', style: headerStyle(), overflow: TextOverflow.ellipsis)),
            ],
          ),
        );

    Widget productRow(Product p, int index) => Container(
          color: _selectedProducts.containsKey(p.id) ? Colors.blue.shade50 : (index.isOdd ? Colors.grey.shade50 : Colors.white),
          child: Row(
            children: [
              cell(
                fCheck,
                Checkbox(
                  value: _selectedProducts.containsKey(p.id),
                  onChanged: (bool? val) {
                    setState(() {
                      if (val == true) {
                        _selectedProducts[p.id] = p;
                      } else {
                        _selectedProducts.remove(p.id);
                      }
                    });
                  },
                ),
              ),
              cell(fId, Text(p.id.toString(), style: TextStyle(color: Colors.grey.shade500, fontSize: 12), overflow: TextOverflow.ellipsis)),
              cell(fNombre, Text(p.name, overflow: TextOverflow.ellipsis, maxLines: 1)),
              cell(fBarcode, Text(p.barcode ?? '—', style: TextStyle(fontSize: 12, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)),
              cell(fInterno, Text(p.internalCode, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
              cell(fCat, Text(p.category?.name ?? '—', overflow: TextOverflow.ellipsis)),
              cell(fCosto, Text('\$${p.costPrice.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis)),
              cell(fVenta, Text('\$${p.sellingPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              cell(fStock, Text(p.isSoldByWeight ? '${p.stock.toStringAsFixed(2)} kg' : p.stock.toStringAsFixed(0), overflow: TextOverflow.ellipsis)),
              cell(fBal, Align(alignment: Alignment.centerLeft, child: Icon(p.isSoldByWeight ? Icons.scale : Icons.inventory_2, size: 18, color: p.isSoldByWeight ? Colors.deepPurple : Colors.blueGrey))),
              cell(fActivo, Align(alignment: Alignment.centerLeft, child: Icon(p.active ? Icons.check_circle : Icons.cancel, color: p.active ? Colors.green : Colors.red, size: 20))),
              // Columna VTO: muestra los días o un dash si no aplica
              cell(
                fVto,
                p.vencimientoDias != null
                    ? Tooltip(
                        message: 'Vence ${p.vencimientoDias} días después del envasado',
                        child: Text(
                          '${p.vencimientoDias} d',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: p.vencimientoDias! <= 30
                                ? Colors.red.shade700
                                : p.vencimientoDias! <= 90
                                    ? Colors.orange.shade700
                                    : Colors.green.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              ),
              cell(fAcciones, Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.print_outlined, size: 18),
                    color: Colors.deepPurple,
                    tooltip: 'Imprimir Etiquetas',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => showDialog(context: context, builder: (_) => PrintLabelsDialog(products: [p])),
                  ),
                  IconButton(
                    icon: const Icon(Icons.warehouse_outlined, size: 18),
                    color: Colors.teal,
                    tooltip: 'Ajuste de Stock',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      final auth = await AdminPinDialog.verify(context, action: 'Ajustar Stock', permissionKey: 'adjust_stock');
                      if (auth && context.mounted) _showStockAdjustment(context, provider, p);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: Colors.blue,
                    tooltip: 'Editar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      final auth = await AdminPinDialog.verify(context, action: 'Editar Producto', permissionKey: 'manage_catalog');
                      if (auth && context.mounted) _showProductForm(context, provider, product: p);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Colors.red,
                    tooltip: 'Eliminar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      final auth = await AdminPinDialog.verify(context, action: 'Eliminar Producto', permissionKey: 'manage_catalog');
                      if (auth && context.mounted) _confirmDelete(context, provider, p);
                    },
                  ),
                ],
              )),
            ],
          ),
        );

    return Column(
      children: [
        headerRow(),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (_, i) => productRow(products[i], i),
          ),
        ),
      ],
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

  Future<void> _confirmBulkDelete(CatalogProvider provider) async {
    final auth = await AdminPinDialog.verify(context, action: 'Eliminar Múltiples Productos', permissionKey: 'manage_catalog');
    if (!auth) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Lote', style: TextStyle(color: Colors.red)),
        content: Text('¿Está seguro que desea eliminar DEFINITIVAMENTE los ${_selectedProducts.length} productos seleccionados?\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.icon(
            icon: const Icon(Icons.delete_forever),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            label: const Text('Eliminar Todo'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final msg = await provider.bulkDeleteProducts(_selectedProducts.keys.toList());
      if (msg != null) {
        SnackBarService.success(context, msg);
        setState(() => _selectedProducts.clear());
      } else {
        SnackBarService.error(context, provider.errorMessage ?? 'Error al eliminar masivamente');
      }
    }
  }

  Future<void> _bulkUpdateCategory(CatalogProvider provider) async {
    final auth = await AdminPinDialog.verify(context, action: 'Categorizar Lote', permissionKey: 'manage_catalog');
    if (!auth) return;

    int? newCategory = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        int? selected;
        return AlertDialog(
          title: const Text('Mover a Categoría'),
          content: DropdownButtonFormField<int?>(
            decoration: const InputDecoration(labelText: 'Elige la nueva categoría', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('— Quitar categoría —')),
              ...provider.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
            ],
            onChanged: (val) => selected = val,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected ?? -1), child: const Text('Mover')),
          ],
        );
      },
    );

    if (newCategory != null && mounted) {
      final finalCat = newCategory == -1 ? null : newCategory;
      final msg = await provider.bulkUpdateProducts(_selectedProducts.keys.toList(), categoryId: finalCat);
      if (msg != null) {
        SnackBarService.success(context, msg);
        setState(() => _selectedProducts.clear());
      } else {
        SnackBarService.error(context, provider.errorMessage ?? 'Error al actualizar categoría');
      }
    }
  }

  Future<void> _bulkToggleActive(CatalogProvider provider) async {
    final auth = await AdminPinDialog.verify(context, action: 'Cambiar Estado por Lote', permissionKey: 'manage_catalog');
    if (!auth) return;

    bool? activeStatus = await showDialog<bool?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar Estado (Activo/Inactivo)'),
        content: const Text('¿Qué estado desea aplicar a los productos seleccionados?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
          FilledButton.icon(
            icon: const Icon(Icons.cancel_outlined),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            label: const Text('Dar de Baja (Desactivar)'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            label: const Text('Dar de Alta (Activar)'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (activeStatus != null && mounted) {
      final msg = await provider.bulkUpdateProducts(_selectedProducts.keys.toList(), active: activeStatus);
      if (msg != null) {
        SnackBarService.success(context, msg);
        setState(() => _selectedProducts.clear());
      } else {
        SnackBarService.error(context, provider.errorMessage ?? 'Error al actualizar estado');
      }
    }
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
  late TextEditingController _internalCodeCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _stockCtrl;
  bool _isSoldByWeight = false;
  bool _active = true;
  int? _categoryId;
  late TextEditingController _expiryCtrl;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _internalCodeCtrl = TextEditingController(text: p?.internalCode ?? '');
    _costCtrl = TextEditingController(text: p != null ? p.costPrice.toStringAsFixed(2) : '');
    _priceCtrl = TextEditingController(text: p != null ? p.sellingPrice.toStringAsFixed(2) : '');
    _stockCtrl = TextEditingController(text: p != null ? p.stock.toStringAsFixed(p.isSoldByWeight ? 3 : 0) : '0');
    _isSoldByWeight = p?.isSoldByWeight ?? false;
    _active = p?.active ?? true;
    _categoryId = p?.category?.id;
    _expiryCtrl = TextEditingController(
      text: p?.vencimientoDias != null ? p!.vencimientoDias.toString() : '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _internalCodeCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final data = {
      'name': _nameCtrl.text.trim(),
      if (_barcodeCtrl.text.isNotEmpty) 'barcode': _barcodeCtrl.text.trim(),
      if (_internalCodeCtrl.text.isNotEmpty) 'internal_code': _internalCodeCtrl.text.trim(),
      'cost_price': double.parse(_costCtrl.text.replaceAll(',', '.')),
      'selling_price': double.parse(_priceCtrl.text.replaceAll(',', '.')),
      'stock': double.parse(_stockCtrl.text.replaceAll(',', '.')),
      'is_sold_by_weight': _isSoldByWeight,
      'active': _active,
      if (_categoryId != null) 'category_id': _categoryId,
      if (_expiryCtrl.text.trim().isNotEmpty)
        'vencimiento_dias': int.parse(_expiryCtrl.text.trim()),
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
                // Código Interno (PLU) + Código de barras
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _internalCodeCtrl,
                        maxLength: 5,
                        decoration: const InputDecoration(
                          labelText: 'PLU (Interno) *',
                          prefixIcon: Icon(Icons.numbers),
                          counterText: '',
                          helperText: '5 dígitos numéricos',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: TextFormField(
                        controller: _barcodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Código de Barras (EAN)',
                          prefixIcon: Icon(Icons.qr_code_scanner),
                          helperText: 'Dejar vacío si es pesable',
                        ),
                      ),
                    ),
                  ],
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
                        validator: (v) {
                          if (v == null || double.tryParse(v.replaceAll(',', '.')) == null) return 'Ingrese un precio válido';
                          final costStr = _costCtrl.text.replaceAll(',', '.');
                          final cost = double.tryParse(costStr) ?? 0;
                          final price = double.parse(v.replaceAll(',', '.'));
                          if (price < cost) return 'El precio de venta debe ser mayor o igual al costo';
                          return null;
                        },
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
                // Switches + Vencimiento
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _expiryCtrl,
                  decoration: InputDecoration(
                    labelText: 'Días de Vencimiento (opcional)',
                    prefixIcon: const Icon(Icons.hourglass_bottom_outlined),
                    helperText: 'Ej: 90 → VTO = hoy + 90 días. Dejar vacío si no vence.',
                    suffixText: 'días',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1 || n > 3650) {
                      return 'Ingresá un número entre 1 y 3650';
                    }
                    return null;
                  },
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
  final List<int>? targetProductIds;

  const BulkPriceUpdateDialog({Key? key, required this.provider, this.targetProductIds}) : super(key: key);

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

    final String filterLabel = widget.targetProductIds != null
        ? 'los ${widget.targetProductIds!.length} productos seleccionados'
        : (_selectedCategoryId == null ? 'todo el catálogo' : 'la categoría seleccionada');

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
      productIds: widget.targetProductIds,
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
            if (widget.targetProductIds == null) ...[
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
            ] else ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.blue.shade700, size: 16),
                    const SizedBox(width: 8),
                    Text('Aplicando a ${widget.targetProductIds!.length} productos seleccionados', style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
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
                orElse: () => widget.product as dynamic)
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
