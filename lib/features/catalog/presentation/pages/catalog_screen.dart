import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import '../widgets/stock_adjustment_dialog.dart';
import '../../domain/entities/product.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../widgets/categories_manager_dialog.dart';
import '../widgets/brands_manager_dialog.dart';
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
    // Cargar productos al inicio
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CatalogProvider>().loadProducts();
      
      // Manejar navegación inteligente desde Alertas
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args != null && args is Product) {
        _showProductForm(context, context.read<CatalogProvider>(), product: args);
      }
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

  Future<void> _openBrandsManager(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const BrandsManagerDialog(),
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
                          icon: const Icon(Icons.branding_watermark_outlined, size: 18),
                          label: const Text('Marcas'),
                          onPressed: () async {
                            final auth = await AdminPinDialog.verify(context, action: 'Gestionar Marcas', permissionKey: 'manage_catalog');
                            if (auth && context.mounted) _openBrandsManager(context);
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.history, color: Colors.deepOrange),
                          tooltip: 'Historial de Aumentos',
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => BulkPriceHistoryDialog(provider: provider),
                          ),
                        ),
                        const SizedBox(width: 4),
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
              // ── Product Table ───────────────────────────────────────────────
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
                          const double minW = 950.0;
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: minW,
                                maxWidth: constraints.maxWidth > minW ? constraints.maxWidth : minW,
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
    const int fNombre = 5;
    const int fBarcode = 3;
    const int fInterno = 2;
    const int fCat = 3;
    const int fBrand = 3;
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
              sortHeader(fId, '#', 'id'),
              sortHeader(fNombre, 'Nombre', 'name'),
              sortHeader(fBarcode, 'Cód. Barras', 'barcode'),
              sortHeader(fInterno, 'Cód. Interno', 'internal_code'),
              sortHeader(fCat, 'Categoría', 'category_id'),
              sortHeader(fBrand, 'Marca', 'brand_id'),
              sortHeader(fCosto, 'Costo', 'cost_price'),
              sortHeader(fVenta, 'Venta', 'selling_price'),

              sortHeader(fStock, 'Stock', 'stock'),
              sortHeader(fBal, 'Balanza', 'is_sold_by_weight'),
              sortHeader(fActivo, 'Activo', 'active'),
              sortHeader(fVto, 'VTO.', 'vencimiento_dias'),
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
              cell(fBrand, p.brand != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Text(p.brand!.name, style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                    )
                  : Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13))),
              cell(fCosto, Text('\$${p.costPrice.toCurrency()}', overflow: TextOverflow.ellipsis)),
              cell(fVenta, Text('\$${p.sellingPrice.toCurrency()}', style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),

              cell(fStock, Text(p.isSoldByWeight ? '${p.stock.toCurrency()} kg' : p.stock.toStringAsFixed(0), overflow: TextOverflow.ellipsis)),
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
  late TextEditingController _marginCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _minStockCtrl;
  bool _isAutoCalculating = false;
  bool _isSoldByWeight = false;
  bool _active = true;
  bool _isCombo = false;
  List<Map<String, dynamic>> _comboIngredients = [];
  List<Map<String, dynamic>> _priceTiers = [];
  String _unitType = 'un';
  int? _categoryId;
  int? _brandId;
  late TextEditingController _expiryCtrl;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _internalCodeCtrl = TextEditingController(text: p?.internalCode ?? '');
    _costCtrl = TextEditingController(text: p != null ? p.costPrice.toCurrency() : '');
    _priceCtrl = TextEditingController(text: p != null ? p.sellingPrice.toCurrency() : '');
    _marginCtrl = TextEditingController();
    _stockCtrl = TextEditingController(text: p != null ? p.stock.toStringAsFixed(p.isSoldByWeight ? 3 : 0) : '0');
    
    _loadSavedMargin();
    
    _costCtrl.addListener(_onCostOrMarginChanged);
    _marginCtrl.addListener(_onCostOrMarginChanged);
    _priceCtrl.addListener(_onPriceChanged);
    _minStockCtrl = TextEditingController(text: (p?.minStock != null) ? p!.minStock!.toStringAsFixed(0) : '');
    _isSoldByWeight = p?.isSoldByWeight ?? false;
    _active = p?.active ?? true;
    _isCombo = p?.isCombo ?? false;
    if (_isCombo && p?.comboIngredients != null) {
      _comboIngredients = List<Map<String, dynamic>>.from(p!.comboIngredients!);
    }
    if (p?.priceTiers != null) {
      _priceTiers = List<Map<String, dynamic>>.from(p!.priceTiers!);
    }
    _unitType = p?.unitType ?? 'un';
    _categoryId = p?.category?.id;
    _brandId = p?.brand?.id;
    _expiryCtrl = TextEditingController(
      text: p?.vencimientoDias != null ? p!.vencimientoDias.toString() : '',
    );
  }

  @override
  void dispose() {
    _costCtrl.removeListener(_onCostOrMarginChanged);
    _marginCtrl.removeListener(_onCostOrMarginChanged);
    _priceCtrl.removeListener(_onPriceChanged);
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _internalCodeCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _marginCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedMargin() async {
    if (_isEditing) {
       final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0.0;
       final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
       if (cost > 0) {
         final margin = ((price - cost) / cost) * 100;
         _isAutoCalculating = true;
         _marginCtrl.text = margin.toStringAsFixed(2);
         _isAutoCalculating = false;
       }
    } else {
       final prefs = await SharedPreferences.getInstance();
       final savedMargin = prefs.getDouble('last_profit_margin') ?? 0.0;
       if (savedMargin > 0) {
         _isAutoCalculating = true;
         _marginCtrl.text = savedMargin.toStringAsFixed(2);
         _isAutoCalculating = false;
       }
    }
  }

  void _onCostOrMarginChanged() {
    if (_isAutoCalculating) return;
    final costStr = _costCtrl.text.replaceAll(',', '.');
    final marginStr = _marginCtrl.text.replaceAll(',', '.');
    
    if (costStr.isEmpty) {
       _isAutoCalculating = true;
       _priceCtrl.text = '';
       _isAutoCalculating = false;
       return;
    }

    final cost = double.tryParse(costStr) ?? 0.0;
    final margin = double.tryParse(marginStr) ?? 0.0;
    
    final newPrice = cost + (cost * (margin / 100));
    _isAutoCalculating = true;
    _priceCtrl.text = newPrice.toStringAsFixed(2);
    _isAutoCalculating = false;
  }

  void _onPriceChanged() {
    if (_isAutoCalculating) return;
    final costStr = _costCtrl.text.replaceAll(',', '.');
    final priceStr = _priceCtrl.text.replaceAll(',', '.');
    
    if (costStr.isEmpty || priceStr.isEmpty) {
       _isAutoCalculating = true;
       _marginCtrl.text = '';
       _isAutoCalculating = false;
       return;
    }

    final cost = double.tryParse(costStr) ?? 0.0;
    final price = double.tryParse(priceStr) ?? 0.0;
    
    if (cost > 0) {
      final margin = ((price - cost) / cost) * 100;
      _isAutoCalculating = true;
      _marginCtrl.text = margin.toStringAsFixed(2);
      _isAutoCalculating = false;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final data = {
      'name': _nameCtrl.text.trim(),
      'barcode': _barcodeCtrl.text.trim(),
      if (_internalCodeCtrl.text.isNotEmpty) 'internal_code': _internalCodeCtrl.text.trim(),
      'cost_price': double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0.0,
      'selling_price': double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0.0,
      'stock': double.tryParse(_stockCtrl.text.replaceAll(',', '.')) ?? 0.0,
      'min_stock': _minStockCtrl.text.trim().isNotEmpty ? double.tryParse(_minStockCtrl.text.replaceAll(',', '.')) : null,
      'is_sold_by_weight': _isSoldByWeight,
      'is_combo': _isCombo,
      if (_isCombo) 'combo_ingredients': _comboIngredients,
      if (_priceTiers.isNotEmpty) 'price_tiers': _priceTiers,
      'unit_type': _unitType,
      'active': _active,
      if (_categoryId != null) 'category_id': _categoryId,
      if (_brandId != null) 'brand_id': _brandId,
      if (_expiryCtrl.text.trim().isNotEmpty)
        'vencimiento_dias': int.parse(_expiryCtrl.text.trim()),
    };

    final bool ok = _isEditing
        ? await widget.provider.updateProduct(widget.product!.id, data)
        : await widget.provider.createProduct(data);

    if (mounted) {
      if (ok) {
        final margin = double.tryParse(_marginCtrl.text.replaceAll(',', '.')) ?? 0.0;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('last_profit_margin', margin);

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
    final brands = widget.provider.brands;
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
                // Categoría + quick-create
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _categoryId,
                        decoration: const InputDecoration(labelText: 'Categoría', prefixIcon: Icon(Icons.category_outlined)),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('— Sin categoría —')),
                          ...categories.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                        ],
                        onChanged: (val) => setState(() => _categoryId = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Crear nueva categoría rápida',
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          final nameCtrl = TextEditingController();
                          final createdId = await showDialog<int?>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Nueva Categoría'),
                              content: TextField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre de la categoría',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.label_outline),
                                ),
                                autofocus: true,
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                                Consumer<CatalogProvider>(
                                  builder: (_, p, __) => FilledButton(
                                    onPressed: p.isLoading
                                      ? null
                                      : () async {
                                          if (nameCtrl.text.trim().isEmpty) return;
                                          final newId = await p.createCategory(nameCtrl.text.trim());
                                          if (newId != null && ctx.mounted) {
                                            Navigator.pop(ctx, newId);
                                          } else if (ctx.mounted) {
                                            SnackBarService.error(ctx, p.errorMessage ?? 'Error al crear');
                                          }
                                      },
                                    child: const Text('Crear'),
                                  )
                                ),
                              ],
                            ),
                          );
                          if (createdId != null && mounted) {
                            setState(() => _categoryId = createdId);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Marca + quick-create
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _brandId,
                        decoration: const InputDecoration(labelText: 'Marca', prefixIcon: Icon(Icons.branding_watermark_outlined)),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('— Sin marca —')),
                          ...brands.map((b) => DropdownMenuItem<int?>(value: b.id, child: Text(b.name))),
                        ],
                        onChanged: (val) => setState(() => _brandId = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Crear nueva marca rápida',
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          final nameCtrl = TextEditingController();
                          final createdId = await showDialog<int?>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Nueva Marca'),
                              content: TextField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre de la marca',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.branding_watermark_outlined),
                                ),
                                autofocus: true,
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                                Consumer<CatalogProvider>(
                                  builder: (_, p, __) => FilledButton(
                                    onPressed: p.isLoading
                                      ? null
                                      : () async {
                                          if (nameCtrl.text.trim().isEmpty) return;
                                          final newId = await p.createBrand(nameCtrl.text.trim());
                                          if (newId != null && ctx.mounted) {
                                            Navigator.pop(ctx, newId);
                                          } else if (ctx.mounted) {
                                            SnackBarService.error(ctx, p.errorMessage ?? 'Error al crear marca');
                                          }
                                      },
                                    child: const Text('Crear'),
                                  )
                                ),
                              ],
                            ),
                          );
                          if (createdId != null && mounted) {
                            setState(() => _brandId = createdId);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Precio Costo — oculto en Combos (el costo se deriva de sus componentes)
                    if (!_isCombo) ...[
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
                          controller: _marginCtrl,
                          decoration: const InputDecoration(labelText: 'Utilidad', suffixText: '%', prefixIcon: Icon(Icons.percent, size: 16)),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: TextFormField(
                        controller: _priceCtrl,
                        decoration: const InputDecoration(labelText: 'Precio Venta *', prefixText: '\$ '),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || double.tryParse(v.replaceAll(',', '.')) == null) return 'Ingrese un precio válido';
                          // Solo validar costo vs precio si no es un combo
                          if (!_isCombo) {
                            final costStr = _costCtrl.text.replaceAll(',', '.');
                            final cost = double.tryParse(costStr) ?? 0;
                            final price = double.parse(v.replaceAll(',', '.'));
                            if (price < cost) return 'El precio de venta debe ser mayor o igual al costo';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // [hardware_store] Listas de Precio — UI Ocultada (Fase 1 Refactorización)
                // Se deprecó la carga manual de price_wholesale y price_card
                const SizedBox(height: 12),
                // --- SECCIÓN: PRECIOS POR VOLUMEN / MAYORISTAS ---
                _buildPriceTiersSection(),
                
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: _isCombo ? const SizedBox.shrink() : Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: TextFormField(
                          controller: _stockCtrl,
                          decoration: InputDecoration(
                            labelText: 'Stock inicial',
                            suffixText: _unitType,
                            prefixIcon: const Icon(Icons.inventory_2_outlined),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 6,
                        child: TextFormField(
                          controller: _minStockCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Stock Mínimo (Alerta)',
                            prefixIcon: Icon(Icons.notification_important_outlined),
                            helperText: 'Opcional: Dejar vacío para no alertar',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _unitType,
                        decoration: const InputDecoration(
                          labelText: 'Unidad de Medida',
                          prefixIcon: Icon(Icons.square_foot),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'un', child: Text('Unidades')),
                          DropdownMenuItem(value: 'kg', child: Text('Kilogramos')),
                          DropdownMenuItem(value: 'g', child: Text('Gramos')),
                          DropdownMenuItem(value: 'lt', child: Text('Litros')),
                        ],
                        onChanged: (val) => setState(() {
                          _unitType = val ?? 'un';
                          if (_unitType != 'un') {
                            _isSoldByWeight = true; // Auto-marcar si es peso/volumen
                          } else {
                            _isSoldByWeight = false; // Desmarcar si es unidad pura
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Venta p/peso (balanza)'),
                        value: _isSoldByWeight,
                        onChanged: (v) => setState(() { 
                          _isSoldByWeight = v;
                          if (v && _unitType == 'un') _unitType = 'kg'; // Auto set
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Producto activo (Visible en POS)'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Es un Combo / Receta (Armado dinámico)'),
                  subtitle: const Text('No maneja stock activo propio, descuenta de sus ingredientes.'),
                  value: _isCombo,
                  onChanged: (v) => setState(() => _isCombo = v),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: !_isCombo ? const SizedBox.shrink() : Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Productos incluidos en el Combo', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Añadir Producto'),
                              onPressed: () async {
                                await _showIngredientSearchDialog(context, widget.provider);
                              },
                            ),
                          ],
                        ),
                        if (_comboIngredients.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('Agregá los productos individuales y la cantidad que se descontará del stock al vender este combo.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          ),
                        ..._comboIngredients.map((ing) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(ing['name'], overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 100,
                                  child: TextFormField(
                                    initialValue: (ing['quantity'] as num).toQty(),
                                    decoration: const InputDecoration(labelText: 'Cant.', isDense: true),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    onChanged: (v) {
                                      ing['quantity'] = double.tryParse(v.replaceAll(',', '.')) ?? 1.0;
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => setState(() => _comboIngredients.remove(ing)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
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

  // --- SECCIÓN PRECIOS POR VOLUMEN ---
  Widget _buildPriceTiersSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border.all(color: Colors.blue.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Precios Mayoristas / Por Volumen', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _priceTiers.add({
                      // Sugerimos x10 para agilizar
                      'min_quantity': 10,
                      'unit_price': double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0.0,
                    });
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Añadir escala', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_priceTiers.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._priceTiers.asMap().entries.map((entry) {
              int idx = entry.key;
              Map<String, dynamic> tier = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        initialValue: (tier['min_quantity'] as num).toQty(),
                        decoration: const InputDecoration(labelText: 'A partir de X cant.', isDense: true, border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (v) => _priceTiers[idx]['min_quantity'] = double.tryParse(v.replaceAll(',', '.')) ?? 1.0,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Requerido';
                          final val = double.tryParse(v.replaceAll(',', '.'));
                          if (val == null || val <= 1) return 'Debe ser > 1';
                          // Verificar repetidos
                          int count = _priceTiers.where((t) => t['min_quantity'] == val).length;
                          if (count > 1) return 'Ya existe un tramo para esta cantidad';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        initialValue: (tier['unit_price'] as num).toCurrency(),
                        decoration: const InputDecoration(labelText: 'Precio Unitario (\$)', isDense: true, prefixText: '\$ ', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (v) => _priceTiers[idx]['unit_price'] = double.tryParse(v.replaceAll(',', '.')) ?? 0.0,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Requerido';
                          if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Precio inválido';
                          return null;
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.deepOrange),
                      tooltip: 'Eliminar escala',
                      onPressed: () => setState(() => _priceTiers.removeAt(idx)),
                    ),
                  ],
                ),
              );
            }).toList(),
            const Text(
              'Nota: Si vende unidades fraccionadas, puede usar decimales (Ej: 5.5).',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ] else
            const Text(
              'No hay escalas de precio configuradas. El producto usará su Precio Base de Venta en cualquier cantidad.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
        ],
      ),
    );
  }

  Future<void> _showIngredientSearchDialog(BuildContext context, CatalogProvider provider) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ComboIngredientPickerDialog(
        provider: provider,
        excludeProductId: widget.product?.id,
        comboIngredients: _comboIngredients,
        onChanged: () => setState(() {}),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PICKER DE INGREDIENTES PARA COMBO — busca en el backend, no en memoria local
// ─────────────────────────────────────────────────────────────────────────────
class _ComboIngredientPickerDialog extends StatefulWidget {
  final CatalogProvider provider;
  final int? excludeProductId;       // El producto que se está editando (para excluirlo)
  final List<Map<String, dynamic>> comboIngredients;
  final VoidCallback onChanged;      // Notifica al formulario padre para rebuild

  const _ComboIngredientPickerDialog({
    required this.provider,
    required this.comboIngredients,
    required this.onChanged,
    this.excludeProductId,
  });

  @override
  State<_ComboIngredientPickerDialog> createState() => _ComboIngredientPickerDialogState();
}

class _ComboIngredientPickerDialogState extends State<_ComboIngredientPickerDialog> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Product> _results = [];
  bool _loading = false;
  bool _firstLoad = true;

  @override
  void initState() {
    super.initState();
    // Carga inicial: trae todos los productos (sin filtro de búsqueda)
    _doSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _doSearch(query));
  }

  Future<void> _doSearch(String query) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await widget.provider.searchProductsForCombo(query);
    if (!mounted) return;
    setState(() {
      _firstLoad = false;
      _loading = false;
      // Filtrar: excluir combos (anti-recursividad) y el producto que se está editando
      _results = results.where((p) {
        if (p.isCombo) return false;
        if (widget.excludeProductId != null && p.id == widget.excludeProductId) return false;
        return true;
      }).cast<Product>().toList();
    });
  }

  void _addIngredient(dynamic p) {
    final alreadyAdded = widget.comboIngredients.any((ing) => ing['id'] == p.id);
    if (alreadyAdded) return;
    setState(() {
      widget.comboIngredients.add({'id': p.id, 'name': p.name, 'quantity': 1});
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buscar Producto para el Combo'),
      content: SizedBox(
        width: 440,
        height: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nombre, código de barras o PLU...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : (_searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              _doSearch('');
                            },
                          )
                        : null),
              ),
              onChanged: _onQueryChanged,
            ),
            const SizedBox(height: 10),
            if (_firstLoad)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_results.isEmpty)
              const Expanded(child: Center(child: Text('No hay resultados')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final p = _results[i];
                    final alreadyAdded = widget.comboIngredients.any((ing) => ing['id'] == p.id);
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text('Stock: ${p.stock} ${p.unitType} | \$${p.sellingPrice.toCurrency()}'),
                      onTap: alreadyAdded ? null : () => _addIngredient(p),
                      trailing: alreadyAdded
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.deepOrange),
                              tooltip: 'Agregar al Combo',
                              onPressed: () => _addIngredient(p),
                            ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: Text(
            'Listo (${widget.comboIngredients.length} producto${widget.comboIngredients.length == 1 ? '' : 's'})',
          ),
          onPressed: () => Navigator.pop(context),
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
  int? _selectedBrandId;
  String _roundingRule = 'none';
  String _targetField = 'selling_price';

  @override
  void dispose() {
    _percentCtrl.dispose();
    super.dispose();
  }

  Future<void> _previewAndApply() async {
    final double? pct = double.tryParse(_percentCtrl.text.replaceAll(',', '.'));
    if (pct == null) {
      SnackBarService.error(context, 'Ingrese un porcentaje válido (ej: 15 o -10).');
      return;
    }

    // 1. Obtener la previsualización del backend
    final previewData = await widget.provider.bulkPricePreview(
      percentage: pct,
      roundingRule: _roundingRule,
      targetField: _targetField,
      productIds: widget.targetProductIds,
      categoryId: _selectedCategoryId,
      brandId: _selectedBrandId,
    );

    if (previewData == null) {
      if (mounted) SnackBarService.error(context, widget.provider.errorMessage ?? 'Error al previsualizar.');
      return;
    }

    final int affectedCount = previewData['affected_count'] ?? 0;
    final List<dynamic> examples = previewData['examples'] ?? [];

    if (affectedCount == 0) {
      if (mounted) SnackBarService.error(context, 'No hay productos que coincidan con estos filtros.');
      return;
    }

    if (!mounted) return;

    // 2. Mostrar diálogo de Confirmación con Previsualización
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            const Text('Confirmar Aumento'),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: Theme.of(ctx).textTheme.bodyMedium,
                  children: [
                    const TextSpan(text: 'Se actualizarán los precios de '),
                    TextSpan(
                      text: '$affectedCount productos',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' aplicando un '),
                    TextSpan(
                      text: '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: pct >= 0 ? Colors.deepOrange.shade700 : Colors.red.shade700,
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Ejemplos de cómo quedarán:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: examples.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade300),
                  itemBuilder: (_, i) {
                    final ex = examples[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(ex['name'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text('\$${(num.tryParse(ex['old_price'].toString()) ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, decoration: TextDecoration.lineThrough, color: Colors.grey)),
                          ),
                          const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                          Expanded(
                            flex: 1,
                            child: Text(' \$${(num.tryParse(ex['new_price'].toString()) ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar y Aplicar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 3. Ejecutar actualización real
    final message = await widget.provider.bulkPriceUpdate(
      percentage: pct,
      roundingRule: _roundingRule,
      targetField: _targetField,
      productIds: widget.targetProductIds,
      categoryId: _selectedCategoryId,
      brandId: _selectedBrandId,
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
    final brands = widget.provider.brands;
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
            DropdownButtonFormField<String>(
              value: _targetField,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Base de Incremento',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
                helperText: 'Elige si aumentas el Costo o el Precio Final.',
              ),
              items: const [
                DropdownMenuItem(value: 'selling_price', child: Text('Solo Precio de Venta (Aumento estándar)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'cost_and_selling_price', child: Text('Costo de Proveedor y Precio de Venta', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'cost_price', child: Text('Solo Costo (Baja el margen de ganancia)', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (val) => setState(() => _targetField = val ?? 'selling_price'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _roundingRule,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Regla de Redondeo',
                prefixIcon: Icon(Icons.calculate_outlined),
                border: OutlineInputBorder(),
                helperText: 'Evita precios con decimales feos.',
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Sin redondeo (Ej: \$1234.56)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'nearest_10', child: Text('A la decena más cercana (Ej: \$1230)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'nearest_50', child: Text('Múltiplos de \$50 (Ej: \$1250)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'nearest_100', child: Text('A la centena más cercana (Ej: \$1200)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'ends_99', child: Text('Terminar en .99 (Ej: \$1234.99)', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (val) => setState(() => _roundingRule = val ?? 'none'),
            ),
            const SizedBox(height: 16),
            if (widget.targetProductIds == null) ...[
              DropdownButtonFormField<int?>(
                value: _selectedCategoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por Categoría',
                  prefixIcon: Icon(Icons.folder_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('📦 Todas las categorías', overflow: TextOverflow.ellipsis)),
                  ...categories.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text('📂 ${c.name}', overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (val) => setState(() => _selectedCategoryId = val),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _selectedBrandId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por Marca',
                  prefixIcon: Icon(Icons.branding_watermark_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('🏷️ Todas las marcas', overflow: TextOverflow.ellipsis)),
                  ...brands.map((b) => DropdownMenuItem<int?>(value: b.id, child: Text('🏷️ ${b.name}', overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (val) => setState(() => _selectedBrandId = val),
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
            icon: const Icon(Icons.preview),
            label: p.isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Previsualizar Impacto'),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: p.isLoading ? null : _previewAndApply,
          ),
        ),
      ],
    );
  }
}

class BulkPriceHistoryDialog extends StatefulWidget {
  final CatalogProvider provider;

  const BulkPriceHistoryDialog({Key? key, required this.provider}) : super(key: key);

  @override
  State<BulkPriceHistoryDialog> createState() => _BulkPriceHistoryDialogState();
}

class _BulkPriceHistoryDialogState extends State<BulkPriceHistoryDialog> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => widget.provider.fetchPriceHistory());
  }

  Future<void> _revert(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revertir Aumento'),
        content: const Text('¿Estás seguro de que deseas deshacer este lote de aumentos? Los precios de todos los productos afectados volverán a su estado anterior.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revertir Lote'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final msg = await widget.provider.revertPriceHistory(id);
    if (mounted) {
      if (msg != null) {
        SnackBarService.success(context, msg);
      } else {
        SnackBarService.error(context, widget.provider.errorMessage ?? 'Error al revertir.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.history),
          SizedBox(width: 8),
          Text('Historial de Aumentos'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Consumer<CatalogProvider>(
          builder: (_, p, __) {
            if (p.isLoading && p.priceHistory.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (p.priceHistory.isEmpty) {
              return const Center(child: Text('No hay registros de aumentos recientes.'));
            }

            return ListView.separated(
              itemCount: p.priceHistory.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (ctx, i) {
                final history = p.priceHistory[i];
                final bool isReverted = history['reverted'] == 1 || history['reverted'] == true;
                final date = DateTime.parse(history['created_at']).toLocal();
                final String formattedDate = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                
                final pct = double.parse(history['percentage'].toString());
                
                final targetField = history['target_field'] == 'cost_price' 
                    ? 'Costo' 
                    : (history['target_field'] == 'selling_price' ? 'Precio Final' : 'Costo y Precio Final');
                
                final roundingRule = history['rounding_rule'] == 'none' ? 'Sin redondeo'
                    : (history['rounding_rule'] == 'nearest_10' ? 'A la decena'
                    : (history['rounding_rule'] == 'nearest_50' ? 'Múltiplos de 50'
                    : (history['rounding_rule'] == 'nearest_100' ? 'A la centena'
                    : (history['rounding_rule'] == 'ends_99' ? 'Termina en .99' : history['rounding_rule']))));
                
                return ListTile(
                  leading: Icon(
                    isReverted ? Icons.undo : Icons.trending_up,
                    color: isReverted ? Colors.grey : (pct >= 0 ? Colors.green : Colors.red),
                  ),
                  title: Text('Aumento: ${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}% ($targetField)'),
                  subtitle: Text('Fecha: $formattedDate | Afectados: ${history['affected_count']} \nRedondeo: $roundingRule'),
                  isThreeLine: true,
                  trailing: isReverted
                      ? const Chip(label: Text('Revertido', style: TextStyle(fontSize: 10)), backgroundColor: Colors.grey)
                      : TextButton.icon(
                          icon: const Icon(Icons.settings_backup_restore, size: 16),
                          label: const Text('Revertir'),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          onPressed: () => _revert(history['id']),
                        ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
    );
  }
}


