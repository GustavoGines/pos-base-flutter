import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import '../widgets/stock_adjustment_dialog.dart';
import '../widgets/product_batches_dialog.dart';
import '../widgets/production_orders_dialog.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../widgets/catalog_import_dialog.dart';
import '../../domain/entities/brand.dart';
import 'package:frontend_desktop/core/presentation/widgets/plan_upgrade_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/searchable_select_field.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../widgets/categories_manager_dialog.dart';
import '../widgets/brands_manager_dialog.dart';
import '../widgets/rubros_manager_dialog.dart';
import '../../../suppliers/presentation/widgets/supplier_form_dialog.dart';
import '../widgets/print_labels_dialog.dart';
import '../widgets/product_image_preview_dialog.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import '../../../suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/combo_fraction_pricing.dart';
import '../../utils/product_share_helper.dart';
import 'package:frontend_desktop/core/utils/image_url_resolver.dart';
import '../../../quotes/presentation/pages/quote_screen.dart';
import '../../../quotes/presentation/providers/quote_provider.dart';
import '../../../pos/presentation/providers/pos_provider.dart';
import '../../../offers/presentation/providers/offer_provider.dart';
import '../../../reports/presentation/providers/inventory_alerts_provider.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

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
    // Cargar productos al inicio asegurando catálogo completo sin filtros residuales
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchController.text = '';
      final catalogProv = context.read<CatalogProvider>();
      // El POS deja sortBy vacío (orden por popularidad del servidor); el Catálogo siempre
      // debe entrar con un orden explícito (el último elegido o alfabético), limpiando el filtro rápido.
      final resetSort = catalogProv.sortBy.isEmpty || catalogProv.sortBy == 'needs_catalog_review';
      catalogProv.loadProducts(
        page: 1,
        search: '',
        sortBy: resetSort ? 'name' : catalogProv.sortBy,
        sortDirection: resetSort ? 'asc' : catalogProv.sortDirection,
      );
      
      // Manejar navegación inteligente desde Alertas
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args != null && args is Product) {
        _showProductForm(context, context.read<CatalogProvider>(), product: args);
      }
    });
  }

  void _handleRemoteBarcodeScan(String barcode) {
    _debounceTimer?.cancel();
    setState(() {
      _searchController.text = barcode;
    });
    context.read<CatalogProvider>().loadProducts(page: 1, search: barcode);
    SnackBarService.success(context, 'Buscando código escaneado: $barcode');
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
    await showDialog<int?>(
      context: context,
      builder: (_) => const CategoriesManagerDialog(),
    );
    if (mounted) {
      context.read<CatalogProvider>().loadProducts(page: 1, search: _searchController.text.trim());
    }
  }

  Future<void> _openBrandsManager(BuildContext context) async {
    await showDialog<int?>(
      context: context,
      builder: (_) => const BrandsManagerDialog(),
    );
    if (mounted) {
      context.read<CatalogProvider>().loadProducts(page: 1, search: _searchController.text.trim());
    }
  }

  Future<void> _openRubrosManager(BuildContext context) async {
    final hasMultiRubro = context.read<SettingsProvider>().features.multiRubro;
    if (!hasMultiRubro) {
      PlanUpgradeDialog.show(
        context,
        featureName: 'Gestión de Rubros',
        description: 'La gestión de múltiples rubros comerciales es exclusiva del Plan Premium.',
      );
      return;
    }
    await showDialog<int?>(
      context: context,
      builder: (_) => const RubrosManagerDialog(),
    );
    if (mounted) {
      context.read<CatalogProvider>().loadMetadata(force: true);
      context.read<CatalogProvider>().loadProducts(page: 1, search: _searchController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return RemoteScannerListener(
      debugLabel: 'CatalogScreen',
      onBarcodeScanned: _handleRemoteBarcodeScan,
      child: Consumer<CatalogProvider>(
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

                    final compactOutlinedStyle = OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    );

                    final isNeedsReviewFilter = provider.sortBy == 'needs_catalog_review';

                    final actionRow = Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.blue),
                          tooltip: 'Recargar Catálogo',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            provider.loadProducts(
                              page: 1,
                              search: _searchController.text.trim(),
                            );
                          },
                        ),
                        const SizedBox(width: 6),
                        Tooltip(
                          message: isNeedsReviewFilter
                              ? 'Quitar filtro y volver a ver todo el catálogo'
                              : 'Filtrar productos creados rápido desde el POS pendientes de completar ficha',
                          child: OutlinedButton.icon(
                            key: const ValueKey('catalog_needs_review_filter_btn'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              backgroundColor: isNeedsReviewFilter ? Colors.amber.shade100 : Colors.amber.shade50.withValues(alpha: 0.45),
                              side: BorderSide(
                                color: isNeedsReviewFilter ? Colors.amber.shade800 : Colors.amber.shade400,
                                width: isNeedsReviewFilter ? 1.5 : 1.0,
                              ),
                            ),
                            icon: Icon(
                              isNeedsReviewFilter ? Icons.close_rounded : Icons.bolt_rounded,
                              size: 17,
                              color: Colors.amber.shade900,
                            ),
                            label: Text(
                              'Por revisar',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: isNeedsReviewFilter ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                            onPressed: provider.isLoading
                                ? null
                                : () {
                                    setState(() => _selectedProducts.clear());
                                    if (isNeedsReviewFilter) {
                                      provider.loadProducts(
                                        page: 1,
                                        search: _searchController.text.trim(),
                                        sortBy: 'name',
                                        sortDirection: 'asc',
                                      );
                                    } else {
                                      provider.loadProducts(
                                        page: 1,
                                        search: _searchController.text.trim(),
                                        sortBy: 'needs_catalog_review',
                                        sortDirection: 'desc',
                                      );
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          style: compactOutlinedStyle,
                          icon: const Icon(Icons.category_rounded, size: 18),
                          label: const Text('Rubros'),
                          onPressed: () async {
                            final hasMultiRubro = context.read<SettingsProvider>().features.multiRubro;
                            if (!hasMultiRubro) {
                              PlanUpgradeDialog.show(
                                context,
                                featureName: 'Gestión de Rubros',
                                description: 'La gestión de múltiples rubros comerciales es exclusiva del Plan Premium.',
                              );
                              return;
                            }
                            final auth = await AdminPinDialog.verify(context, action: 'Gestionar Rubros', permissionKey: 'manage_catalog');
                            if (auth && context.mounted) _openRubrosManager(context);
                          },
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          style: compactOutlinedStyle,
                          icon: const Icon(Icons.label_outline, size: 18),
                          label: const Text('Categorías'),
                          onPressed: () async {
                            final auth = await AdminPinDialog.verify(context, action: 'Gestionar Categorías', permissionKey: 'manage_catalog');
                            if (auth && context.mounted) _openCategoriesManager(context);
                          },
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          style: compactOutlinedStyle,
                          icon: const Icon(Icons.branding_watermark_outlined, size: 18),
                          label: const Text('Marcas'),
                          onPressed: () async {
                            final auth = await AdminPinDialog.verify(context, action: 'Gestionar Marcas', permissionKey: 'manage_catalog');
                            if (auth && context.mounted) _openBrandsManager(context);
                          },
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.history, color: Colors.deepOrange),
                          tooltip: 'Historial de Aumentos',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => BulkPriceHistoryDialog(provider: provider),
                          ),
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.trending_up, size: 18, color: Colors.deepOrange),
                          label: const Text('Aumento Masivo', style: TextStyle(color: Colors.deepOrange)),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            side: const BorderSide(color: Colors.deepOrange),
                          ),
                          onPressed: provider.isLoading
                              ? null
                              : () async {
                                  final auth = await AdminPinDialog.verify(context, action: 'Aumento Masivo de Precios', permissionKey: 'manage_catalog');
                                  if (auth && context.mounted) _showBulkUpdateDialog(context, provider);
                                },
                        ),
                        const SizedBox(width: 6),
                        PopupMenuButton<String>(
                          tooltip: 'Opciones de Excel',
                          offset: const Offset(0, 40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'import',
                              child: Row(
                                children: [
                                  Icon(Icons.upload_file, color: Colors.green, size: 20),
                                  SizedBox(width: 8),
                                  Text('Importar Excel'),
                                ],
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.download, color: Colors.green, size: 20),
                                  SizedBox(width: 8),
                                  Text('Exportar Lista'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (String result) async {
                            if (result == 'import') {
                              final auth = await AdminPinDialog.verify(context, action: 'Importar Catálogo', permissionKey: 'manage_catalog');
                              if (auth && context.mounted) {
                                showDialog(
                                  context: context,
                                  builder: (_) => const CatalogImportDialog(),
                                );
                              }
                            } else if (result == 'export') {
                              final auth = await AdminPinDialog.verify(context, action: 'Exportar Catálogo', permissionKey: 'manage_catalog');
                              if (auth && context.mounted) {
                                provider.exportCatalogToExcel(context);
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.green),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.table_view, size: 18, color: Colors.green),
                                SizedBox(width: 6),
                                Text('Excel', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                                SizedBox(width: 2),
                                Icon(Icons.arrow_drop_down, size: 18, color: Colors.green),
                              ],
                            ),
                          ),
                        ),
                        if (context.watch<SettingsProvider?>()?.features.production ?? false) ...[
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: Colors.deepOrange.shade800,
                              side: BorderSide(color: Colors.deepOrange.shade300),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            icon: const Icon(Icons.bakery_dining_outlined, size: 18),
                            label: const Text('Producción'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => ProductionOrdersDialog(provider: provider),
                              ).then((_) {
                                if (mounted) {
                                  context.read<InventoryAlertsProvider>().fetchAlerts();
                                }
                              });
                            },
                          ),
                        ],
                        const SizedBox(width: 6),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Nuevo Producto'),
                          onPressed: () async {
                            final auth = await AdminPinDialog.verify(context, action: 'Crear Nuevo Producto', permissionKey: 'manage_catalog');
                            if (auth && context.mounted) _showProductForm(context, provider);
                          },
                        ),
                      ],
                    );

                    if (constraints.maxWidth < 750) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          searchWidget,
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: actionRow,
                          ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          flex: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 500),
                            child: searchWidget,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          flex: 8,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: actionRow,
                            ),
                          ),
                        ),
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
              // ── Barra de acciones en lote (encima del checkbox "seleccionar todos") ──
              if (_selectedProducts.isNotEmpty) _buildBulkActionsBar(provider),
              // ── Product Table ───────────────────────────────────────────────
              Expanded(
                child: Builder(
                  builder: (context) {
                    final isNeedsReviewFilter = provider.sortBy == 'needs_catalog_review';
                    final displayedProducts = isNeedsReviewFilter
                        ? provider.products.where((p) => p.needsCatalogReview).toList()
                        : provider.products;

                    if (displayedProducts.isEmpty && !provider.isLoading) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isNeedsReviewFilter ? Icons.check_circle_outline_rounded : Icons.inventory_2_outlined,
                              size: 80,
                              color: isNeedsReviewFilter ? Colors.amber.shade600 : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              isNeedsReviewFilter
                                  ? 'No hay productos rápidos pendientes de revisión'
                                  : 'No se encontraron productos',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                            ),
                            if (isNeedsReviewFilter) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.list_alt_rounded, size: 18),
                                label: const Text('Ver todo el catálogo'),
                                onPressed: () {
                                  provider.loadProducts(
                                    page: 1,
                                    search: _searchController.text.trim(),
                                    sortBy: 'name',
                                    sortDirection: 'asc',
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        const double minW = 1180.0;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: minW,
                              maxWidth: constraints.maxWidth > minW ? constraints.maxWidth : minW,
                            ),
                            child: _buildProductsTable(displayedProducts, provider),
                          ),
                        );
                      },
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
                        icon: const Icon(Icons.first_page),
                        onPressed: provider.currentPage > 1 ? () => provider.loadProducts(page: 1) : null,
                        tooltip: 'Primera página',
                      ),
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
                      IconButton(
                        icon: const Icon(Icons.last_page),
                        onPressed: provider.currentPage < provider.lastPage ? () => provider.loadProducts(page: provider.lastPage) : null,
                        tooltip: 'Última página',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
      ),
    );
  }

  /// Barra contextual de acciones en lote, alineada a la izquierda
  /// justo encima del checkbox "seleccionar todos" de la tabla.
  Widget _buildBulkActionsBar(CatalogProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(top: BorderSide(color: Colors.blue.shade100)),
      ),
      child: Row(
        children: [
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
                case 7: _bulkUpdateSupplier(provider); break;
                case 8: _bulkUpdateBrand(provider); break;
                case 12: _bulkGenerateQuote(); break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.folder_outlined, color: Colors.orange, size: 20), SizedBox(width: 12), Expanded(child: Text('Asignar Categoría'))])),
              const PopupMenuItem(value: 8, child: Row(children: [Icon(Icons.branding_watermark_outlined, color: Colors.indigo, size: 20), SizedBox(width: 12), Expanded(child: Text('Asignar Marca'))])),
              const PopupMenuItem(value: 7, child: Row(children: [Icon(Icons.local_shipping_outlined, color: Colors.brown, size: 20), SizedBox(width: 12), Expanded(child: Text('Asignar Proveedor'))])),
              const PopupMenuItem(value: 12, child: Row(children: [Icon(Icons.request_quote_outlined, color: Colors.teal, size: 20), SizedBox(width: 12), Expanded(child: Text('Generar Presupuesto'))])),
              const PopupMenuItem(value: 2, child: Row(children: [Icon(Icons.power_settings_new, color: Colors.teal, size: 20), SizedBox(width: 12), Expanded(child: Text('Cambiar Estado'))])),
              const PopupMenuItem(value: 3, child: Row(children: [Icon(Icons.trending_up, color: Colors.deepOrange, size: 20), SizedBox(width: 12), Expanded(child: Text('Actualizar Precios'))])),
              const PopupMenuItem(value: 4, child: Row(children: [Icon(Icons.print_outlined, color: Colors.deepPurple, size: 20), SizedBox(width: 12), Expanded(child: Text('Imprimir Etiquetas'))])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 5, child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 20), SizedBox(width: 12), Expanded(child: Text('Eliminar Todo'))])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 6, child: Row(children: [Icon(Icons.deselect, color: Colors.grey, size: 20), SizedBox(width: 12), Expanded(child: Text('Cancelar Selección'))])),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade800,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
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
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              '${_selectedProducts.length} producto(s) seleccionado(s)',
              style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Limpiar'),
            onPressed: () => setState(() => _selectedProducts.clear()),
          ),
        ],
      ),
    );
  }

  Widget _buildProductAvatar(Product p) {
    final uri = p.imageUrl != null && p.imageUrl!.isNotEmpty ? Uri.tryParse(p.imageUrl!) : null;
    final hasImage = uri != null &&
        uri.hasScheme &&
        uri.hasAuthority &&
        uri.host.isNotEmpty;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.isSoldByWeight ? Colors.orange.shade50 : Colors.blue.shade50,
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: ClipOval(
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: p.imageUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Icon(
                  p.isSoldByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                  size: 20,
                  color: p.isSoldByWeight ? Colors.orange.shade700 : Colors.blue.shade700,
                ),
              )
            : Icon(
                p.isSoldByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
                size: 20,
                color: p.isSoldByWeight ? Colors.orange.shade700 : Colors.blue.shade700,
              ),
      ),
    );
  }

  void _openProductBatches(CatalogProvider provider, Product p) {
    if (p.isCombo || p.isService) return;
    showDialog(
      context: context,
      builder: (_) => ProductBatchesDialog(provider: provider, product: p),
    ).then((_) {
      if (!mounted) return;
      try {
        context.read<InventoryAlertsProvider>().fetchAlerts();
      } catch (_) {}
    });
  }

  Widget _buildExpiryCell(Product p, CatalogProvider provider) {
    final canManageLots = !p.isCombo && !p.isService;
    final rawExp = p.expirationDate;
    if (rawExp != null && rawExp.isNotEmpty) {
      final expDt = DateTime.tryParse(rawExp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final daysLeft = expDt != null
          ? DateTime(expDt.year, expDt.month, expDt.day).difference(today).inDays
          : 999;
      final label = expDt != null
          ? '${expDt.day.toString().padLeft(2, '0')}/${expDt.month.toString().padLeft(2, '0')}/${expDt.year}'
          : rawExp;
      final configuredPreAlert =
          (p.expiryAlertDays != null && p.expiryAlertDays! > 0)
              ? p.expiryAlertDays!
              : 15;
      final shelfLife =
          (p.vencimientoDias != null && p.vencimientoDias! > 0)
              ? p.vencimientoDias
              : null;

      final int criticalDays;
      final int preAlertThreshold;
      if (shelfLife != null && shelfLife <= 5) {
        criticalDays = (shelfLife * 0.35).floor().clamp(1, 2);
        preAlertThreshold = math
            .max(criticalDays + 1, (shelfLife * 0.65).floor())
            .clamp(criticalDays, math.max(criticalDays, shelfLife - 1));
      } else {
        criticalDays = configuredPreAlert <= 5
            ? (configuredPreAlert * 0.35).floor().clamp(1, 2)
            : 3;
        preAlertThreshold = shelfLife != null
            ? math.min(configuredPreAlert, math.max(criticalDays, shelfLife - 1))
            : configuredPreAlert;
      }

      final Color fgColor;
      final Color bgColor;
      final Color borderColor;
      if (daysLeft <= 0) {
        fgColor = Colors.white;
        bgColor = Colors.red.shade700;
        borderColor = Colors.red.shade900;
      } else if (daysLeft <= criticalDays) {
        fgColor = Colors.red.shade800;
        bgColor = Colors.red.shade50;
        borderColor = Colors.red.shade300;
      } else if (daysLeft <= preAlertThreshold) {
        fgColor = Colors.amber.shade900;
        bgColor = Colors.amber.shade50;
        borderColor = Colors.amber.shade400;
      } else {
        fgColor = Colors.green.shade800;
        bgColor = Colors.green.shade50;
        borderColor = Colors.green.shade300;
      }

      final String baseTooltipMsg;
      if (expDt == null) {
        baseTooltipMsg = 'Vencimiento: $label';
      } else if (daysLeft < 0) {
        final overdue = -daysLeft;
        baseTooltipMsg = 'Vencido hace $overdue día${overdue == 1 ? '' : 's'} ($label)';
      } else if (daysLeft == 0) {
        baseTooltipMsg = '¡Vence HOY! ($label)';
      } else if (daysLeft == 1) {
        baseTooltipMsg = 'Vence mañana ($label)';
      } else {
        baseTooltipMsg = 'Vence el $label (en $daysLeft días)';
      }

      final tooltipMsg = canManageLots
          ? '$baseTooltipMsg • Clic para ver/administrar lotes'
          : baseTooltipMsg;

      final badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (daysLeft <= 0) ...[
                Icon(Icons.warning_amber_rounded, size: 12, color: fgColor),
                const SizedBox(width: 3),
              ] else if (p.trackBatches && canManageLots) ...[
                Icon(Icons.layers_outlined, size: 12, color: fgColor),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      );

      return Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: tooltipMsg,
          child: canManageLots
              ? InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _openProductBatches(provider, p),
                  child: badge,
                )
              : badge,
        ),
      );
    }

    if (p.vencimientoDias != null) {
      final dias = p.vencimientoDias!;
      final fgColor = dias <= 30
          ? Colors.red.shade700
          : (dias <= 90 ? Colors.amber.shade900 : Colors.green.shade700);
      final chip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: canManageLots
              ? Border.all(color: fgColor.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p.trackBatches && canManageLots) ...[
              Icon(Icons.layers_outlined, size: 12, color: fgColor),
              const SizedBox(width: 3),
            ],
            Text(
              '$dias d',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fgColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );

      return Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: canManageLots
              ? 'Vence $dias días después del envasado • Clic para ver/administrar lotes'
              : 'Vence $dias días después del envasado',
          child: canManageLots
              ? InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _openProductBatches(provider, p),
                  child: chip,
                )
              : chip,
        ),
      );
    }

    if (canManageLots) {
      final isBatchActive = p.trackBatches;
      final fg = isBatchActive ? Colors.deepOrange.shade700 : Colors.grey.shade600;
      final bg = isBatchActive ? Colors.orange.shade50 : Colors.grey.shade100;
      final border = isBatchActive ? Colors.orange.shade300 : Colors.grey.shade300;
      return Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: isBatchActive
              ? 'Control por lotes activo (sin vencimiento cargado) • Clic para administrar lotes'
              : 'Clic para ingresar o administrar lotes de vencimiento',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _openProductBatches(provider, p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBatchActive) ...[
                    Icon(Icons.layers_outlined, size: 12, color: fg),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    isBatchActive ? 'Lotes' : '+ Lote',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13));
  }

  Widget _buildProductsTable(List<Product> products, CatalogProvider provider) {
    final sp = context.watch<SettingsProvider?>();
    final canSeeSupplier = sp?.features.suppliers ?? false;
    final canUseBatches = sp == null
        ? true
        : (sp.features.batchExpiration || sp.features.production);

    // Anchos fijos calibrados para columnas cortas/fechas y flex equilibrado para texto/precios
    const double wCheck = 38;
    const double wFoto = 46;
    const double wId = 48;
    const double wBal = 58;
    const double wActivo = 70;
    const double wVto = 116;
    final double wAcciones = canUseBatches ? 168 : 136;

    const int fNombre = 5;
    const int fBarcode = 3;
    const int fInterno = 2;
    const int fCat = 2;
    const int fBrand = 2;
    const int fProv = 2;
    const int fCosto = 2;
    const int fVenta = 2;
    const int fStock = 2;

    Widget tableCell({
      int? flex,
      double? width,
      EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      required Widget child,
    }) {
      final padded = Padding(padding: padding, child: child);
      if (width != null) {
        return SizedBox(width: width, child: padded);
      }
      return Expanded(flex: flex ?? 1, child: padded);
    }

    TextStyle headerStyle() => const TextStyle(fontWeight: FontWeight.bold, fontSize: 13);

    // Sortable header button (width fija o flex)
    Widget sortHeader({
      int? flex,
      double? width,
      required String label,
      required String sortKey,
      String initialDirection = 'asc',
      String? tooltip,
    }) {
      final isActive = provider.sortBy == sortKey;
      final isAsc = provider.sortDirection == 'asc';
      Widget headerBody = InkWell(
        onTap: () {
          final newDir = isActive
              ? (isAsc ? 'desc' : 'asc')
              : initialDirection;
          provider.loadProducts(page: 1, sortBy: sortKey, sortDirection: newDir);
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
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
                const SizedBox(width: 2),
                Icon(
                  isAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 13,
                  color: Colors.blue.shade700,
                ),
              ],
            ],
          ),
        ),
      );
      if (tooltip != null) {
        headerBody = Tooltip(message: tooltip, child: headerBody);
      }
      if (width != null) {
        return SizedBox(width: width, child: headerBody);
      }
      return Expanded(flex: flex ?? 1, child: headerBody);
    }

    final vtoTooltip = provider.sortBy == 'expiration_date'
        ? (provider.sortDirection == 'desc'
            ? 'Vencimientos más lejanos/recientes primero (clic para invertir)'
            : 'Vencimientos más próximos o vencidos primero (clic para invertir)')
        : 'Ordenar por fecha de vencimiento (más recientes primero)';

    Widget headerRow() => Container(
          color: Colors.grey.shade100,
          child: Row(
            children: [
              tableCell(
                width: wCheck,
                child: Checkbox(
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
              const SizedBox(
                width: wFoto,
                child: Center(
                  child: Icon(Icons.image_outlined, size: 18, color: Colors.blueGrey),
                ),
              ),
              sortHeader(width: wId, label: '#', sortKey: 'id'),
              sortHeader(flex: fNombre, label: 'Nombre', sortKey: 'name'),
              sortHeader(flex: fBarcode, label: 'Cód. Barras', sortKey: 'barcode'),
              sortHeader(flex: fInterno, label: 'Cód. Interno', sortKey: 'internal_code'),
              sortHeader(flex: fCat, label: 'Categoría', sortKey: 'category_id'),
              sortHeader(flex: fBrand, label: 'Marca', sortKey: 'brand_id'),
              if (canSeeSupplier) sortHeader(flex: fProv, label: 'Proveedor', sortKey: 'supplier_id'),
              sortHeader(flex: fCosto, label: 'Costo', sortKey: 'cost_price'),
              sortHeader(flex: fVenta, label: 'Venta', sortKey: 'selling_price'),
              sortHeader(flex: fStock, label: 'Stock', sortKey: 'stock'),
              sortHeader(
                width: wBal,
                label: 'Bal.',
                sortKey: 'is_sold_by_weight',
                tooltip: 'Venta por peso / Balanza',
              ),
              sortHeader(
                width: wActivo,
                label: 'Activo',
                sortKey: 'active',
                tooltip: 'Estado activo en POS',
              ),
              if (canUseBatches)
                sortHeader(
                  width: wVto,
                  label: 'VTO.',
                  sortKey: 'expiration_date',
                  initialDirection: 'desc',
                  tooltip: vtoTooltip,
                ),
              tableCell(
                width: wAcciones,
                child: Text('Acciones', style: headerStyle(), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );

    Widget productRow(Product p, int index) => Material(
          color: _selectedProducts.containsKey(p.id) ? Colors.blue.shade50 : (index.isOdd ? Colors.grey.shade50 : Colors.white),
          child: InkWell(
            onTap: () {
              if (_selectedProducts.isNotEmpty) {
                setState(() {
                  if (_selectedProducts.containsKey(p.id)) {
                    _selectedProducts.remove(p.id);
                  } else {
                    _selectedProducts[p.id] = p;
                  }
                });
              } else {
                _showProductForm(context, provider, product: p);
              }
            },
            child: Row(
              children: [
              tableCell(
                width: wCheck,
                child: Checkbox(
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
              SizedBox(
                width: wFoto,
                child: Center(
                  child: _buildProductAvatar(p),
                ),
              ),
              tableCell(width: wId, child: Text(p.id.toString(), style: TextStyle(color: Colors.grey.shade500, fontSize: 12), overflow: TextOverflow.ellipsis)),
              tableCell(
                flex: fNombre,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(p.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                    if (p.needsCatalogReview) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Producto creado al vuelo desde el POS. Abrilo y guardalo para completar su ficha.',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Text(
                            '⚡ Revisar',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              tableCell(flex: fBarcode, child: Text(p.barcode ?? '—', style: TextStyle(fontSize: 12, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)),
              tableCell(flex: fInterno, child: Text(p.internalCode, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
              tableCell(flex: fCat, child: Text(p.category?.name ?? '—', overflow: TextOverflow.ellipsis)),
              tableCell(
                flex: fBrand,
                child: p.brand != null
                    ? Text(p.brand!.name, overflow: TextOverflow.ellipsis)
                    : Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              ),
              if (canSeeSupplier) tableCell(flex: fProv, child: Text(p.supplier?.name ?? '—', overflow: TextOverflow.ellipsis)),
              tableCell(flex: fCosto, child: Text('\$${p.costPrice.toCurrency()}', overflow: TextOverflow.ellipsis)),
              tableCell(flex: fVenta, child: Text('\$${p.sellingPrice.toCurrency()}', style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),

              tableCell(
                flex: fStock,
                child: p.isService
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Text(
                          '💼 Servicio',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.teal.shade800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : Text(
                        p.stock.toUnitStockDisplay(
                          isSoldByWeight: p.isSoldByWeight,
                          unitSuffix: 'un.',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              tableCell(width: wBal, child: Align(alignment: Alignment.centerLeft, child: Icon(p.isSoldByWeight ? Icons.scale : Icons.inventory_2, size: 18, color: p.isSoldByWeight ? Colors.deepPurple : Colors.blueGrey))),
              tableCell(width: wActivo, child: Align(alignment: Alignment.centerLeft, child: Icon(p.active ? Icons.check_circle : Icons.cancel, color: p.active ? Colors.green : Colors.red, size: 20))),
              if (canUseBatches) tableCell(width: wVto, child: _buildExpiryCell(p, provider)),
              tableCell(width: wAcciones, child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.print_outlined, size: 18),
                    color: Colors.deepPurple,
                    tooltip: 'Imprimir Etiquetas',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => showDialog(context: context, builder: (_) => PrintLabelsDialog(products: [p])),
                  ),
                  if (canUseBatches && !p.isCombo && !p.isService)
                    IconButton(
                      icon: Icon(
                        Icons.layers_outlined,
                        size: 18,
                        color: p.trackBatches ? Colors.deepOrange.shade700 : Colors.blueGrey,
                      ),
                      tooltip: p.trackBatches ? 'Lotes y Vencimientos' : 'Administrar Lotes',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _openProductBatches(provider, p),
                    ),
                  IconButton(
                    icon: const Icon(Icons.warehouse_outlined, size: 18),
                    color: Colors.teal,
                    tooltip: 'Ajuste de Stock',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () async {
                      final auth = await AdminPinDialog.verify(context, action: 'Eliminar Producto', permissionKey: 'manage_catalog');
                      if (auth && context.mounted) _confirmDelete(context, provider, p);
                    },
                  ),
                ],
              )),
            ],
          ),
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
      barrierDismissible: true,
      builder: (_) => StockAdjustmentDialog(provider: provider, product: p),
    ).then((_) {
      if (mounted) {
        context.read<InventoryAlertsProvider>().fetchAlerts();
      }
    });
  }

  void _showProductForm(BuildContext ctx, CatalogProvider provider, {Product? product}) {
    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (_) => ProductFormDialog(
        provider: provider,
        product: product,
      ),
    ).then((_) {
      if (mounted) {
        context.read<InventoryAlertsProvider>().fetchAlerts();
      }
    });
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
    final auth = await AdminPinDialog.verify(context, action: 'Asignar Categoría en Lote', permissionKey: 'manage_catalog');
    if (!auth) return;

    if (provider.categories.isEmpty && mounted) {
      await provider.loadMetadata();
    }
    if (!mounted) return;

    int defaultCat = -1;
    if (_selectedProducts.isNotEmpty) {
      final firstCatId = _selectedProducts.values.first.category?.id;
      if (firstCatId != null &&
          _selectedProducts.values.every((p) => p.category?.id == firstCatId) &&
          provider.categories.any((c) => c.id == firstCatId)) {
        defaultCat = firstCatId;
      }
    }

    final sortedCategories = sortByAlphabeticalName(provider.categories, (c) => c.name);
    int? newCategory = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        int? selected = defaultCat;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Asignar Categoría'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SearchableSelectField<int?>(
                value: selected,
                clearValue: -1,
                showClearButton: false,
                labelText: 'Elige la nueva categoría',
                dialogTitle: 'Seleccionar Categoría',
                searchHintText: 'Buscar categoría o rubro...',
                prefixIcon: Icons.category_outlined,
                border: const OutlineInputBorder(),
                options: [
                  const SearchableSelectOption<int?>(
                    value: -1,
                    label: '— Quitar Categoría —',
                    isResetOption: true,
                  ),
                  ...sortedCategories.map((c) {
                    final rId = c.rubroId ?? c.rubro?.id;
                    final rubroName = (rId != null
                            ? provider.rubros.where((r) => r.id == rId).firstOrNull?.name
                            : null) ??
                        c.rubro?.name;
                    final hasRubro = rubroName != null && rubroName.trim().isNotEmpty;
                    return SearchableSelectOption<int?>(
                      value: c.id,
                      label: c.name,
                      subtitle: hasRubro ? 'Rubro: $rubroName' : null,
                      searchKeywords: hasRubro ? [rubroName] : const [],
                    );
                  }),
                ],
                onChanged: (val) => setDialogState(() => selected = val),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
                onPressed: () {
                  if (selected == null) {
                    SnackBarService.error(ctx, 'Selecciona una categoría o "— Quitar Categoría —"');
                    return;
                  }
                  Navigator.pop(ctx, selected);
                },
                child: const Text('Asignar'),
              ),
            ],
          ),
        );
      },
    );

    if (newCategory != null && mounted) {
      final clear = newCategory == -1;
      final finalCat = clear ? null : newCategory;
      final msg = await provider.bulkUpdateProducts(
        _selectedProducts.keys.toList(),
        categoryId: finalCat,
        clearCategory: clear,
      );
      if (mounted) {
        if (msg != null) {
          SnackBarService.success(context, msg);
          setState(() => _selectedProducts.clear());
        } else {
          SnackBarService.error(context, provider.errorMessage ?? 'Error al actualizar categoría');
        }
      }
    }
  }

  Future<void> _bulkGenerateQuote() async {
    final hasQuotes = context.read<SettingsProvider>().features.quotes;
    if (!hasQuotes) {
      PlanUpgradeDialog.show(
        context,
        featureName: 'Generador de Presupuestos',
        description: 'La creación de presupuestos es exclusiva del Plan Premium.',
      );
      return;
    }

    final products = _selectedProducts.values.toList();
    if (products.isEmpty) return;

    bool hasQuoteProv = false;
    try {
      final quoteProv = Provider.of<QuoteProvider?>(context, listen: false);
      if (quoteProv != null) {
        hasQuoteProv = true;
        quoteProv.clearCart();
        for (final p in products) {
          quoteProv.addToCart(p, quantity: 1.0);
        }
      }
    } catch (_) {}

    try {
      final posProv = Provider.of<PosProvider?>(context, listen: false);
      if (posProv != null) {
        posProv.clearCart();
        for (final p in products) {
          if (!p.isSoldByWeight) {
            posProv.requestAddToCart(p);
          } else {
            posProv.submitWeighedProduct(p, 1.0);
          }
        }
      }
    } catch (_) {}

    setState(() => _selectedProducts.clear());

    if (mounted && hasQuoteProv) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QuoteScreen()),
      );
    }
  }

  Future<void> _bulkUpdateBrand(CatalogProvider provider) async {
    final auth = await AdminPinDialog.verify(
      context,
      action: 'Asignar Marca en Lote',
      permissionKey: 'manage_catalog',
    );
    if (!auth) return;

    if (provider.brands.isEmpty && mounted) {
      await provider.loadBrands();
    }
    if (!mounted) return;

    int defaultBrand = -1;
    if (_selectedProducts.isNotEmpty) {
      final firstBrandId = _selectedProducts.values.first.brand?.id;
      if (firstBrandId != null &&
          _selectedProducts.values.every((p) => p.brand?.id == firstBrandId) &&
          provider.brands.any((b) => b.id == firstBrandId)) {
        defaultBrand = firstBrandId;
      }
    }

    final sortedBrands = sortByAlphabeticalName(provider.brands, (b) => b.name);
    int? newBrand = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        int? selected = defaultBrand;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Asignar Marca en Lote'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SearchableSelectField<int?>(
                value: selected,
                clearValue: -1,
                showClearButton: false,
                labelText: 'Elige la nueva marca',
                dialogTitle: 'Seleccionar Marca',
                searchHintText: 'Buscar marca...',
                prefixIcon: Icons.branding_watermark_outlined,
                border: const OutlineInputBorder(),
                options: [
                  const SearchableSelectOption<int?>(
                    value: -1,
                    label: '— Quitar Marca —',
                    isResetOption: true,
                  ),
                  ...sortedBrands.map(
                    (b) => SearchableSelectOption<int?>(value: b.id, label: b.name),
                  ),
                ],
                onChanged: (val) => setDialogState(() => selected = val),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: () {
                  if (selected == null) {
                    SnackBarService.error(ctx, 'Selecciona una marca o "— Quitar Marca —"');
                    return;
                  }
                  Navigator.pop(ctx, selected);
                },
                child: const Text('Asignar'),
              ),
            ],
          ),
        );
      },
    );

    if (newBrand != null && mounted) {
      final clear = newBrand == -1;
      final finalBrand = clear ? null : newBrand;
      final msg = await provider.bulkUpdateProducts(
        _selectedProducts.keys.toList(),
        brandId: finalBrand,
        clearBrand: clear,
      );
      if (mounted) {
        if (msg != null) {
          SnackBarService.success(context, msg);
          setState(() => _selectedProducts.clear());
        } else {
          SnackBarService.error(context, provider.errorMessage ?? 'Error al asignar marca');
        }
      }
    }
  }

  Future<void> _bulkUpdateSupplier(CatalogProvider provider) async {
    final hasSuppliers = context.read<SettingsProvider>().features.suppliers;
    if (!hasSuppliers) {
      PlanUpgradeDialog.show(
        context,
        featureName: 'Gestión de Proveedores',
        description: 'La asignación y filtrado por proveedores es exclusiva del Plan Premium.',
      );
      return;
    }

    final auth = await AdminPinDialog.verify(context, action: 'Asignar Proveedor en Lote', permissionKey: 'manage_catalog');
    if (!auth) return;

    // Precargar proveedores
    if (mounted) {
      await context.read<SupplierProvider>().fetchSuppliers();
    }

    if (!mounted) return;
    
    final supplierProv = context.read<SupplierProvider>();

    int defaultSupplier = -1;
    if (_selectedProducts.isNotEmpty) {
      final firstSupplierId = _selectedProducts.values.first.supplier?.id;
      if (firstSupplierId != null &&
          _selectedProducts.values.every((p) => p.supplier?.id == firstSupplierId) &&
          supplierProv.suppliers.any((s) => s.id == firstSupplierId)) {
        defaultSupplier = firstSupplierId;
      }
    }

    final sortedSuppliers = sortByAlphabeticalName(supplierProv.suppliers, (s) => s.name);
    int? newSupplier = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        int? selected = defaultSupplier;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Asignar Proveedor'),
            content: supplierProv.isLoading
                ? const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()))
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: SearchableSelectField<int?>(
                      value: selected,
                      clearValue: -1,
                      showClearButton: false,
                      labelText: 'Elige el nuevo proveedor',
                      dialogTitle: 'Seleccionar Proveedor',
                      searchHintText: 'Buscar proveedor o CUIT...',
                      prefixIcon: Icons.local_shipping_outlined,
                      border: const OutlineInputBorder(),
                      options: [
                        const SearchableSelectOption<int?>(
                          value: -1,
                          label: '— Quitar Proveedor —',
                          isResetOption: true,
                        ),
                        ...sortedSuppliers.map((s) {
                          final hasCuit = s.cuit != null && s.cuit!.trim().isNotEmpty;
                          return SearchableSelectOption<int?>(
                            value: s.id,
                            label: s.name,
                            subtitle: hasCuit ? 'CUIT: ${s.cuit!.trim()}' : null,
                            searchKeywords: hasCuit ? [s.cuit!.trim()] : const [],
                          );
                        }),
                      ],
                      onChanged: (val) => setDialogState(() => selected = val),
                    ),
                  ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.brown.shade600),
                onPressed: () {
                  if (selected == null) {
                    SnackBarService.error(ctx, 'Selecciona un proveedor o "— Quitar Proveedor —"');
                    return;
                  }
                  Navigator.pop(ctx, selected);
                },
                child: const Text('Asignar'),
              ),
            ],
          ),
        );
      },
    );

    if (newSupplier != null && mounted) {
      final clear = newSupplier == -1;
      final finalSup = clear ? null : newSupplier;
      final msg = await provider.bulkUpdateProducts(_selectedProducts.keys.toList(), supplierId: finalSup, clearSupplier: clear);
      if (mounted) {
        if (msg != null) {
          SnackBarService.success(context, msg);
          setState(() => _selectedProducts.clear());
        } else {
          SnackBarService.error(context, provider.errorMessage ?? 'Error al asignar proveedor');
        }
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

  const ProductFormDialog({super.key, required this.provider, this.product});

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
  String? _priceAnchor; // 'cost' | 'selling' | null (detecta automáticamente qué precio ingresó primero el usuario)
  bool _costIsAuto = false;
  bool _priceIsAuto = false;
  bool _isSoldByWeight = false;
  bool _active = true;
  bool _isCombo = false;
  bool _isService = false;
  bool _showExpirationSection = false;
  bool _trackBatches = false;
  String _lotDeductionPolicy = 'fefo';
  bool _allowSellExpired = false;
  bool _hasProductionRecipe = false;
  late TextEditingController _recipeYieldCtrl;
  late TextEditingController _initialBatchCodeCtrl;
  List<Map<String, dynamic>> _recipeIngredients = [];
  List<Map<String, dynamic>> _comboIngredients = [];
  final Map<int, TextEditingController> _comboQtyCtrls = {};
  final Map<int, TextEditingController> _comboCustomPartsCtrls = {};
  final Set<int> _expandedComboFractionIds = <int>{};
  bool? _manualPortionPricingMode;
  final TextEditingController _comboInlineSearchCtrl = TextEditingController();
  final FocusNode _comboInlineSearchFocus = FocusNode();
  List<Product> _comboInlineSearchResults = [];
  bool _isSearchingInlineCombo = false;
  Timer? _comboInlineSearchDebounce;
  List<Map<String, dynamic>> _priceTiers = [];
  bool _expandPriceTiers = false;
  String _unitType = 'un';
  double _ivaRate = 21.0;
  int? _categoryId;
  int? _brandId;
  int? _supplierId;
  late TextEditingController _expiryCtrl;
  late TextEditingController _expiryAlertDaysCtrl;
  DateTime? _expirationDate;

  // Foto del producto
  String? _selectedImagePath;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _isUploadingImage = false;
  bool _deleteExistingImage = false;
  bool _clearStalePriceCard = false;
  bool _clearStalePriceWholesale = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _internalCodeCtrl = TextEditingController(text: p?.internalCode ?? '');
    _costCtrl = TextEditingController(
      text: (p != null && p.costPrice > 0) ? p.costPrice.toArsInput() : '',
    );
    _priceCtrl = TextEditingController(text: p != null ? p.sellingPrice.toArsInput() : '');
    _marginCtrl = TextEditingController();
    final hasFractionalStock =
        p != null && (p.stock - p.stock.roundToDouble()).abs() > 0.0005;
    _stockCtrl = TextEditingController(
      text: p != null
          ? ((p.isSoldByWeight || hasFractionalStock)
              ? _formatComboQtyForInput(p.stock)
              : p.stock.toStringAsFixed(0))
          : '0',
    );
    
    _loadSavedMargin();
    
    _costCtrl.addListener(_onCostChanged);
    _marginCtrl.addListener(_onMarginChanged);
    _priceCtrl.addListener(_onPriceChanged);
    _minStockCtrl = TextEditingController(text: (p?.minStock != null) ? p!.minStock!.toStringAsFixed(0) : '');
    _isSoldByWeight = p?.isSoldByWeight ?? false;
    _active = p?.active ?? true;
    _isCombo = p?.isCombo ?? false;
    _isService = p?.isService ?? false;
    if (_isCombo && p?.comboIngredients != null) {
      _comboIngredients = p!.comboIngredients!
          .map((ing) => Map<String, dynamic>.from(ing))
          .toList();
    }
    if (p?.priceTiers != null) {
      _priceTiers = List<Map<String, dynamic>>.from(p!.priceTiers!);
      _expandPriceTiers = _priceTiers.isNotEmpty;
    }
    _unitType = p?.unitType ?? 'un';
    final rawIva = p?.ivaRate ?? 21.0;
    _ivaRate = const [0.0, 10.5, 21.0, 27.0].contains(rawIva) ? rawIva : 21.0;
    _categoryId = p?.category?.id;
    _brandId = p?.brand?.id;
    _supplierId = p?.supplier?.id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final canSeeSupplier = context.read<SettingsProvider?>()?.features.suppliers ?? false;
      if (canSeeSupplier) {
        context.read<SupplierProvider>().fetchSuppliers();
      }
    });
    _expiryCtrl = TextEditingController(
      text: p?.vencimientoDias != null ? p!.vencimientoDias.toString() : '',
    );
    _expiryAlertDaysCtrl = TextEditingController(
      text: (p?.expiryAlertDays ?? 15).toString(),
    );
    if (p?.expirationDate != null && p!.expirationDate!.isNotEmpty) {
      _expirationDate = DateTime.tryParse(p.expirationDate!);
    }
    _trackBatches = p?.trackBatches ?? false;
    _lotDeductionPolicy = p?.lotDeductionPolicy ?? 'fefo';
    _allowSellExpired = p?.allowSellExpired ?? false;
    _hasProductionRecipe = p?.hasProductionRecipe ?? false;
    _recipeYieldCtrl = TextEditingController(
      text: (p?.recipeYieldQuantity ?? 1.0).toQty(),
    );
    _initialBatchCodeCtrl = TextEditingController();
    if (p?.recipeIngredients != null) {
      _recipeIngredients = p!.recipeIngredients!
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    _showExpirationSection = _trackBatches ||
        _expirationDate != null ||
        (p?.vencimientoDias != null && p!.vencimientoDias! > 0);
  }

  void _handleFormBarcodeScan(String barcode) {
    if (_isService) {
      SnackBarService.warning(
        context,
        'Los servicios u honorarios no llevan código de barras.',
      );
      return;
    }
    if (_isCombo && _comboInlineSearchFocus.hasFocus) {
      _onInlineComboSearchSubmitted(barcode);
      return;
    }
    setState(() {
      _barcodeCtrl.text = barcode;
    });
    SnackBarService.success(context, 'Código escaneado: $barcode');
  }

  double get _comboRecipeTotalCost => _comboIngredients.fold<double>(
        0.0,
        (acc, ing) =>
            acc +
            ((ing['cost_price'] as num?)?.toDouble() ?? 0.0) *
                ((ing['quantity'] as num?)?.toDouble() ?? 0.0),
      );

  List<Product> _filterEligibleInlineComboProducts(List<Product> rawResults) {
    final excludeId = widget.product?.id;
    return rawResults.where((p) {
      if (p.isCombo) return false;
      if (excludeId != null && p.id == excludeId) return false;
      return true;
    }).toList();
  }

  void _onInlineComboSearchChanged(String rawQuery) {
    _comboInlineSearchDebounce?.cancel();
    final q = rawQuery.trim();
    if (q.isEmpty) {
      setState(() {
        _comboInlineSearchResults = [];
        _isSearchingInlineCombo = false;
      });
      return;
    }
    _comboInlineSearchDebounce =
        Timer(const Duration(milliseconds: 280), () async {
      if (!mounted) return;
      setState(() => _isSearchingInlineCombo = true);
      final raw = await widget.provider.searchProductsForCombo(q);
      if (!mounted) return;
      setState(() {
        _isSearchingInlineCombo = false;
        _comboInlineSearchResults = _filterEligibleInlineComboProducts(raw);
      });
    });
  }

  Future<void> _onInlineComboSearchSubmitted(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty || !mounted) return;
    _comboInlineSearchDebounce?.cancel();
    setState(() => _isSearchingInlineCombo = true);
    final raw = await widget.provider.searchProductsForCombo(q);
    if (!mounted) return;
    final eligible = _filterEligibleInlineComboProducts(raw);
    final exact = RemoteScannerService.findExactProductMatch(
      eligible,
      q,
      activeOnly: false,
    );
    final chosen = exact ?? (eligible.length == 1 ? eligible.first : null);
    if (chosen != null) {
      _addProductToComboRecipe(chosen);
      return;
    }
    setState(() {
      _isSearchingInlineCombo = false;
      _comboInlineSearchResults = eligible;
    });
    if (eligible.isEmpty) {
      SnackBarService.info(
        context,
        'No se encontraron productos elegibles para "$q".',
      );
    }
  }

  void _addProductToComboRecipe(Product p) {
    final alreadyAdded = _comboIngredients.any((ing) => ing['id'] == p.id);
    if (alreadyAdded) {
      setState(() {
        _isSearchingInlineCombo = false;
        _comboInlineSearchCtrl.clear();
        _comboInlineSearchResults = [];
      });
      SnackBarService.info(
        context,
        '"${p.name}" ya está agregado al combo.',
      );
      return;
    }
    setState(() {
      _comboIngredients.add({
        'id': p.id,
        'name': p.name,
        'quantity': 1.0,
        'cost_price': p.costPrice,
        'selling_price': p.sellingPrice,
        'stock': p.stock,
        'unit_type': p.unitType,
        'is_sold_by_weight': p.isSoldByWeight,
      });
      _getComboQtyCtrl(p.id, 1.0);
      _isSearchingInlineCombo = false;
      _comboInlineSearchCtrl.clear();
      _comboInlineSearchResults = [];
    });
  }

  @override
  void dispose() {
    _costCtrl.removeListener(_onCostChanged);
    _marginCtrl.removeListener(_onMarginChanged);
    _priceCtrl.removeListener(_onPriceChanged);
    _comboInlineSearchDebounce?.cancel();
    _comboInlineSearchCtrl.dispose();
    _comboInlineSearchFocus.dispose();
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _internalCodeCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _marginCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    _expiryCtrl.dispose();
    _expiryAlertDaysCtrl.dispose();
    _recipeYieldCtrl.dispose();
    _initialBatchCodeCtrl.dispose();
    for (final ctrl in _comboQtyCtrls.values) {
      ctrl.dispose();
    }
    _comboQtyCtrls.clear();
    for (final ctrl in _comboCustomPartsCtrls.values) {
      ctrl.dispose();
    }
    _comboCustomPartsCtrls.clear();
    super.dispose();
  }

  Future<void> _loadSavedMargin() async {
    if (_isEditing) {
      final cost = ArsThousandsInputFormatter.parse(_costCtrl.text);
      final price = ArsThousandsInputFormatter.parse(_priceCtrl.text);
      if (cost > 0) {
        _priceAnchor = 'cost';
        final margin = ((price - cost) / cost) * 100;
        _isAutoCalculating = true;
        _marginCtrl.text = margin.toCleanMargin();
        _isAutoCalculating = false;
      } else if (price > 0) {
        _priceAnchor = 'selling';
      }
    }
  }

  void _onCostChanged() {
    if (_isAutoCalculating) return;
    final costStr = _costCtrl.text.trim();
    final marginStr = _marginCtrl.text.replaceAll(',', '.').trim();
    final priceStr = _priceCtrl.text.trim();

    _costIsAuto = false;

    if (costStr.isEmpty) {
      if (_priceIsAuto) {
        _isAutoCalculating = true;
        _priceCtrl.clear();
        _priceIsAuto = false;
        _isAutoCalculating = false;
      }
      if (_priceAnchor == 'cost') {
        _priceAnchor = priceStr.isNotEmpty ? 'selling' : null;
      }
      return;
    }

    final cost = ArsThousandsInputFormatter.parse(costStr);
    if (cost <= 0) return;

    // Si Venta está vacía o fue autocalculada -> el ancla es Costo y calcula Venta si hay %
    if (priceStr.isEmpty || _priceIsAuto) {
      _priceAnchor = 'cost';
      if (marginStr.isNotEmpty) {
        final margin = double.tryParse(marginStr) ?? 0.0;
        final newPrice = cost * (1 + (margin / 100));
        _isAutoCalculating = true;
        _priceCtrl.text = newPrice.toArsInput();
        _priceIsAuto = true;
        _isAutoCalculating = false;
      }
      return;
    }

    // Si Venta fue escrita manualmente antes y ahora el usuario escribe Costo manualmente -> calcula % Utilidad
    final price = ArsThousandsInputFormatter.parse(priceStr);
    if (price > 0) {
      final margin = ((price - cost) / cost) * 100;
      _isAutoCalculating = true;
      _marginCtrl.text = margin.toCleanMargin();
      _isAutoCalculating = false;
    }
    _priceAnchor = 'cost';
  }

  void _onMarginChanged() {
    if (_isAutoCalculating) return;
    final costStr = _costCtrl.text.trim();
    final marginStr = _marginCtrl.text.replaceAll(',', '.').trim();
    final priceStr = _priceCtrl.text.trim();

    if (marginStr.isEmpty) {
      if (_costIsAuto) {
        _isAutoCalculating = true;
        _costCtrl.clear();
        _costIsAuto = false;
        _isAutoCalculating = false;
      }
      if (_priceIsAuto) {
        _isAutoCalculating = true;
        _priceCtrl.clear();
        _priceIsAuto = false;
        _isAutoCalculating = false;
      }
      return;
    }

    final margin = double.tryParse(marginStr);
    if (margin == null) return;

    // Si Costo está vacío o fue autocalculado y el usuario escribió Precio Venta -> calcula Costo desde Venta + %
    if ((costStr.isEmpty || _costIsAuto) &&
        priceStr.isNotEmpty &&
        !_priceIsAuto) {
      final price = ArsThousandsInputFormatter.parse(priceStr);
      if (price > 0 && margin > -100) {
        final newCost = price / (1 + (margin / 100));
        _isAutoCalculating = true;
        _costCtrl.text = newCost.toArsInput();
        _costIsAuto = true;
        _isAutoCalculating = false;
      }
      return;
    }

    // Regla "Costo como Ancla": si hay Costo firme (> 0), siempre calcula Precio Venta desde Costo + %
    final cost = ArsThousandsInputFormatter.parse(costStr);
    if (cost > 0) {
      final newPrice = cost * (1 + (margin / 100));
      _isAutoCalculating = true;
      _priceCtrl.text = newPrice.toArsInput();
      _priceIsAuto = true;
      _isAutoCalculating = false;
    }
  }

  void _onPriceChanged() {
    if (_isCombo) {
      if (mounted) setState(() {});
      return;
    }
    if (_isAutoCalculating) return;
    final costStr = _costCtrl.text.trim();
    final marginStr = _marginCtrl.text.replaceAll(',', '.').trim();
    final priceStr = _priceCtrl.text.trim();

    _priceIsAuto = false;

    if (priceStr.isEmpty) {
      if (_costIsAuto) {
        _isAutoCalculating = true;
        _costCtrl.clear();
        _costIsAuto = false;
        _isAutoCalculating = false;
      }
      if (_priceAnchor == 'selling') {
        _priceAnchor = costStr.isNotEmpty ? 'cost' : null;
      }
      return;
    }

    final price = ArsThousandsInputFormatter.parse(priceStr);
    if (price <= 0) return;

    // Si Costo está vacío o fue autocalculado -> el ancla es Venta y calcula Costo si hay %
    if (costStr.isEmpty || _costIsAuto) {
      _priceAnchor = 'selling';
      if (marginStr.isNotEmpty) {
        final margin = double.tryParse(marginStr) ?? 0.0;
        if (margin > -100) {
          final newCost = price / (1 + (margin / 100));
          _isAutoCalculating = true;
          _costCtrl.text = newCost.toArsInput();
          _costIsAuto = true;
          _isAutoCalculating = false;
        }
      }
      return;
    }

    // Regla "Costo como Ancla": si Costo fue ingresado manualmente antes y el usuario edita Venta -> Costo no se toca y recalcula % Utilidad
    final cost = ArsThousandsInputFormatter.parse(costStr);
    if (cost > 0) {
      final margin = ((price - cost) / cost) * 100;
      _isAutoCalculating = true;
      _marginCtrl.text = margin.toCleanMargin();
      _isAutoCalculating = false;
    }
    _priceAnchor = 'cost';
  }

  Future<void> _pickProductImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        final ext = file.extension?.toLowerCase() ??
            (file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '');
        if (ext.isNotEmpty && !['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
          if (mounted) {
            SnackBarService.error(context, 'Formato no soportado ($ext). Usa JPG, PNG o WEBP.');
          }
          return;
        }
        int fileSize = file.size > 0 ? file.size : (file.bytes?.length ?? 0);
        if (fileSize == 0 && file.path != null && file.path!.isNotEmpty) {
          try {
            final ioFile = File(file.path!);
            if (ioFile.existsSync()) {
              fileSize = ioFile.lengthSync();
            }
          } catch (_) {}
        }
        if (fileSize > 2 * 1024 * 1024) {
          if (mounted) {
            SnackBarService.error(context, 'La imagen supera los 2MB permitidos (máx 2048 KB).');
          }
          return;
        }
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null && file.path!.isNotEmpty) {
          try {
            final ioFile = File(file.path!);
            if (ioFile.existsSync()) {
              bytes = ioFile.readAsBytesSync();
            }
          } catch (_) {}
        }
        setState(() {
          _selectedImagePath = file.path;
          _selectedImageBytes = bytes;
          _selectedImageName = file.name;
          _deleteExistingImage = false;
        });
      }
    } catch (e) {
      debugPrint('Error seleccionando imagen de producto: $e');
      if (mounted) {
        SnackBarService.error(context, 'Error al seleccionar imagen: $e');
      }
    }
  }

  void _showImagePreviewDialog() {
    final resolvedImageUrl = _deleteExistingImage ? null : resolveImageUrl(widget.product?.imageUrl);
    showDialog(
      context: context,
      builder: (dialogCtx) => ProductImagePreviewDialog(
        title: _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'Foto del Producto',
        imageUrl: resolvedImageUrl,
        imagePath: _selectedImagePath,
        imageBytes: _selectedImageBytes,
        onChangeImage: () async {
          await _pickProductImage();
        },
        onRemoveImage: () {
          setState(() {
            _selectedImagePath = null;
            _selectedImageBytes = null;
            _selectedImageName = null;
            _deleteExistingImage = true;
          });
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isCombo && _comboIngredients.isEmpty) {
      SnackBarService.error(
        context,
        'Debes añadir al menos un producto incluido en el Combo / Fracción antes de guardar.',
      );
      return;
    }
    if (_isCombo && _comboIngredients.any((ing) => ((ing['quantity'] as num?) ?? 0) <= 0)) {
      SnackBarService.error(
        context,
        'La cantidad de cada producto incluido en el Combo debe ser mayor a 0.',
      );
      return;
    }

    final parsedStock = double.tryParse(_stockCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final initialStock = widget.product != null
        ? (double.tryParse(widget.product!.stock.toStringAsFixed(widget.product!.isSoldByWeight ? 3 : 0)) ?? widget.product!.stock)
        : null;
    final stockModified = !_isEditing || initialStock == null || (parsedStock - initialStock).abs() > 0.0001;

    final effectiveCostPrice = (_isCombo && !_isService && _comboRecipeTotalCost > 0)
        ? ((_comboRecipeTotalCost * 100).roundToDouble() / 100.0)
        : ArsThousandsInputFormatter.parse(_costCtrl.text);

    final serializedComboIngredients = (_isCombo && !_isService)
        ? _comboIngredients.map((ing) {
            final copy = Map<String, dynamic>.from(ing);
            final rawQ = (copy['quantity'] as num?)?.toDouble() ?? 1.0;
            copy['quantity'] = roundQtyForStorage(rawQ);
            return copy;
          }).toList()
        : null;

    final data = {
      'name': _nameCtrl.text.trim(),
      'barcode': _barcodeCtrl.text.trim(),
      if (_internalCodeCtrl.text.isNotEmpty) 'internal_code': _internalCodeCtrl.text.trim(),
      'cost_price': effectiveCostPrice,
      'selling_price': ArsThousandsInputFormatter.parse(_priceCtrl.text),
      'iva_rate': _ivaRate,
      if (stockModified) 'stock': parsedStock,
      'min_stock': _minStockCtrl.text.trim().isNotEmpty ? double.tryParse(_minStockCtrl.text.replaceAll(',', '.')) : null,
      'is_sold_by_weight': _isService ? false : _isSoldByWeight,
      'is_combo': _isService ? false : _isCombo,
      'is_service': _isService,
      if (serializedComboIngredients != null)
        'combo_ingredients': serializedComboIngredients,
      if (_isEditing || _priceTiers.isNotEmpty) 'price_tiers': _priceTiers,
      'unit_type': _unitType,
      'active': _active,
      'needs_catalog_review': false,
      if (_clearStalePriceCard) 'price_card': null,
      if (_clearStalePriceWholesale) 'price_wholesale': null,
      'category_id': _categoryId,
      'brand_id': _isService ? null : _brandId,
      'supplier_id': _isService ? null : _supplierId,
      'vencimiento_dias': _expiryCtrl.text.trim().isNotEmpty
          ? int.tryParse(_expiryCtrl.text.trim())
          : null,
      'expiration_date': _expirationDate != null
          ? '${_expirationDate!.year.toString().padLeft(4, '0')}-${_expirationDate!.month.toString().padLeft(2, '0')}-${_expirationDate!.day.toString().padLeft(2, '0')}'
          : null,
      'expiry_alert_days': _expiryAlertDaysCtrl.text.trim().isNotEmpty
          ? int.tryParse(_expiryAlertDaysCtrl.text.trim())
          : 15,
      'track_batches': (_isService || _isCombo) ? false : _trackBatches,
      'lot_deduction_policy': _lotDeductionPolicy,
      'allow_sell_expired': _allowSellExpired,
      'has_production_recipe':
          (_isService || _isCombo) ? false : _hasProductionRecipe,
      if (!_isService && !_isCombo && _hasProductionRecipe) ...{
        'recipe_yield_quantity':
            double.tryParse(_recipeYieldCtrl.text.replaceAll(',', '.').trim()) ??
                1.0,
        'recipe_ingredients': _recipeIngredients
            .map(
              (r) => {
                'ingredient_product_id': r['ingredient_product_id'] ?? r['id'],
                'quantity':
                    double.tryParse(r['quantity']?.toString() ?? '1') ?? 1.0,
                'waste_pct':
                    double.tryParse((r['waste_pct'] ?? 0).toString()) ?? 0.0,
              },
            )
            .toList(),
      },
      if (!_isEditing && _initialBatchCodeCtrl.text.trim().isNotEmpty)
        'initial_batch_code': _initialBatchCodeCtrl.text.trim(),
    };

    bool ok = false;
    int? targetProductId = _isEditing ? widget.product!.id : null;

    final hasPermission = await AdminPinDialog.protectAction(
      context,
      action: _isEditing ? 'Editar Producto' : 'Crear Producto',
      permissionKey: AppPermissions.manageCatalog,
      onAuthorized: () async {
        if (_isEditing) {
          ok = await widget.provider.updateProduct(widget.product!.id, data);
        } else {
          ok = await widget.provider.createProduct(data);
          targetProductId = widget.provider.lastCreatedProduct?.id;
        }
      },
    );

    if (!hasPermission) return;

    if (mounted) {
      if (ok) {
        bool imageUploadSuccess = true;
        String? imageUploadError;

        final hadRemoteImage = widget.product?.imageUrl != null && widget.product!.imageUrl!.trim().isNotEmpty;
        if (_selectedImagePath != null || _selectedImageBytes != null) {
          if (targetProductId != null) {
            setState(() => _isUploadingImage = true);
            final uploadResult = await widget.provider.uploadProductImage(
              targetProductId!,
              _selectedImagePath ?? '',
              bytes: _selectedImageBytes,
              filename: _selectedImageName,
            );
            if (mounted) setState(() => _isUploadingImage = false);

            if (uploadResult == null) {
              imageUploadSuccess = false;
              imageUploadError = widget.provider.errorMessage?.replaceAll('Exception: ', '');
            }
          } else {
            imageUploadSuccess = false;
            imageUploadError = 'No se pudo obtener el identificador del producto para asociar la foto.';
          }
        } else if (_deleteExistingImage && targetProductId != null && _isEditing && hadRemoteImage) {
          try {
            final delSuccess = await widget.provider.deleteProductImage(targetProductId!);
            if (!delSuccess) {
              imageUploadSuccess = false;
              imageUploadError = widget.provider.errorMessage?.replaceAll('Exception: ', '') ?? 'Error al eliminar la foto del producto.';
            }
          } catch (e) {
            debugPrint('Error eliminando imagen del producto: $e');
            imageUploadSuccess = false;
            imageUploadError = e.toString();
          }
        }

        final margin = double.tryParse(_marginCtrl.text.replaceAll(',', '.')) ?? 0.0;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('last_profit_margin', margin);

        if (!mounted) return;
        if (targetProductId != null) {
          Product? syncedProd;
          try {
            syncedProd = widget.provider.products.where((p) => p.id == targetProductId).firstOrNull ??
                widget.provider.lastCreatedProduct;
          } catch (_) {}
          if (syncedProd != null) {
            try {
              context.read<PosProvider?>()?.syncUpdatedCatalogProduct(syncedProd);
            } catch (_) {}
            try {
              context.read<OfferProvider?>()?.syncUpdatedProduct(syncedProd);
            } catch (_) {}
          }
        }
        Navigator.of(context).pop();
        if (imageUploadSuccess) {
          SnackBarService.success(context, _isEditing ? 'Producto actualizado correctamente.' : '¡Producto creado exitosamente!');
        } else {
          SnackBarService.warning(
            context,
            'Producto guardado, pero no se pudo subir la foto: ${imageUploadError ?? "Error al procesar la imagen."}',
          );
        }
      } else {
        SnackBarService.error(context, widget.provider.errorMessage ?? 'Error desconocido.');
      }
    }
  }

  String? _resolveCategoryRubroName(Category? cat) {
    if (cat == null) return null;
    final rId = cat.rubroId ?? cat.rubro?.id;
    if (rId != null) {
      try {
        final found = widget.provider.rubros.where((r) => r.id == rId).firstOrNull?.name;
        if (found != null && found.trim().isNotEmpty) return found;
      } catch (_) {}
    }
    final direct = cat.rubro?.name;
    return (direct != null && direct.trim().isNotEmpty) ? direct : null;
  }

  Widget _buildCategorySelector(List<Category> categories) {
    final sortedCategories = sortByAlphabeticalName(categories, (c) => c.name);
    final hasSelection = sortedCategories.any((c) => c.id == _categoryId);
    final selectedCat = hasSelection
        ? sortedCategories.where((c) => c.id == _categoryId).firstOrNull
        : null;
    final selectedRubroName = _resolveCategoryRubroName(selectedCat);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SearchableSelectField<int?>(
            value: hasSelection ? _categoryId : null,
            clearValue: null,
            labelText: 'Categoría',
            dialogTitle: 'Seleccionar Categoría',
            searchHintText: 'Buscar categoría o rubro...',
            prefixIcon: Icons.category_outlined,
            helperText: (selectedRubroName != null && selectedRubroName.trim().isNotEmpty)
                ? 'Rubro: $selectedRubroName'
                : null,
            helperStyle: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.deepPurple.shade700,
            ),
            options: [
              const SearchableSelectOption<int?>(
                value: null,
                label: '— Sin categoría —',
                isResetOption: true,
              ),
              ...sortedCategories.map((c) {
                final rubroName = _resolveCategoryRubroName(c);
                return SearchableSelectOption<int?>(
                  value: c.id,
                  label: c.name,
                  subtitle: rubroName != null ? 'Rubro: $rubroName' : null,
                  searchKeywords: rubroName != null ? [rubroName] : const [],
                );
              }),
            ],
            onChanged: (val) => setState(() => _categoryId = val),
            onCreateNew: (query) => _showCreateCategoryQuickDialog(initialName: query),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Crear categoría',
          child: IconButton.filledTonal(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateCategoryQuickDialog(),
          ),
        ),
      ],
    );
  }

  Future<void> _showCreateCategoryQuickDialog({String? initialName}) async {
    final nameCtrl = TextEditingController(text: initialName ?? '');
    final settingsProv = context.read<SettingsProvider>();
    final isPremium = settingsProv.features.multiRubro;
    final provider = context.read<CatalogProvider>();

    if (isPremium && provider.rubros.isEmpty) {
      await provider.loadRubros();
    }

    if (!mounted) return;

    final initialRubros = sortByAlphabeticalName(provider.rubros, (r) => r.name);
    int? selectedRubroId =
        initialRubros.isNotEmpty ? initialRubros.first.id : null;

    final createdId = await showDialog<int?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> openCreateRubro({String? suggestedName}) async {
            final newRubroId = await RubrosManagerDialog.showQuickCreateDialog(
              ctx,
              initialName: suggestedName,
            );
            if (newRubroId != null && ctx.mounted) {
              setDialogState(() {
                selectedRubroId = newRubroId;
              });
            }
          }

          return AlertDialog(
            title: const Text('Nueva Categoría'),
            content: SizedBox(
              width: 360,
              child: Consumer<CatalogProvider>(
                builder: (_, p, __) {
                  final sortedRubros =
                      sortByAlphabeticalName(p.rubros, (r) => r.name);
                  if (isPremium &&
                      sortedRubros.isNotEmpty &&
                      !sortedRubros.any((r) => r.id == selectedRubroId)) {
                    selectedRubroId = sortedRubros.first.id;
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.label_outline),
                        ),
                        autofocus: true,
                      ),
                      if (isPremium) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: SearchableSelectField<int?>(
                                value: selectedRubroId,
                                showClearButton: false,
                                labelText: 'Rubro Padre',
                                hintText: sortedRubros.isEmpty
                                    ? 'Sin rubros creados aún'
                                    : null,
                                dialogTitle: 'Seleccionar Rubro Padre',
                                searchHintText: 'Buscar rubro...',
                                emptySearchText: 'No hay rubros registrados',
                                prefixIcon: Icons.category_outlined,
                                border: const OutlineInputBorder(),
                                options: sortedRubros
                                    .map((r) => SearchableSelectOption<int?>(
                                          value: r.id,
                                          label: r.name,
                                        ))
                                    .toList(),
                                onChanged: (val) {
                                  setDialogState(() {
                                    selectedRubroId = val;
                                  });
                                },
                                onCreateNew: (query) =>
                                    openCreateRubro(suggestedName: query),
                                createLabelBuilder: (query) =>
                                    query.trim().isEmpty
                                        ? 'Crear nuevo rubro'
                                        : 'Crear rubro "${query.trim()}"',
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              tooltip: 'Crear nuevo rubro',
                              onPressed: () => openCreateRubro(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              Consumer<CatalogProvider>(
                builder: (_, p, __) => FilledButton(
                  onPressed: p.isLoading
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          final newId = await p.createCategory(
                            nameCtrl.text.trim(),
                            rubroId: isPremium ? selectedRubroId : null,
                          );
                          if (newId != null && ctx.mounted) {
                            Navigator.pop(ctx, newId);
                          }
                        },
                  child: const Text('Crear'),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (createdId != null && mounted) {
      setState(() {
        _categoryId = createdId;
      });
    }
  }

  Future<void> _showCreateBrandQuickDialog({String? initialName}) async {
    final nameCtrl = TextEditingController(text: initialName ?? '');
    final createdId = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva Marca'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre',
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
                      if (newId != null && ctx.mounted) Navigator.pop(ctx, newId);
                    },
              child: const Text('Crear'),
            ),
          ),
        ],
      ),
    );
    if (createdId != null && mounted) setState(() => _brandId = createdId);
  }

  Widget _buildBrandSelector(List<Brand> brands) {
    final sortedBrands = sortByAlphabeticalName(brands, (b) => b.name);
    final hasSelection = sortedBrands.any((b) => b.id == _brandId);

    return Row(
      children: [
        Expanded(
          child: SearchableSelectField<int?>(
            value: hasSelection ? _brandId : null,
            clearValue: null,
            labelText: 'Marca',
            dialogTitle: 'Seleccionar Marca',
            searchHintText: 'Buscar marca...',
            prefixIcon: Icons.branding_watermark_outlined,
            options: [
              const SearchableSelectOption<int?>(
                value: null,
                label: '— Sin marca —',
                isResetOption: true,
              ),
              ...sortedBrands.map(
                (b) => SearchableSelectOption<int?>(value: b.id, label: b.name),
              ),
            ],
            onChanged: (val) => setState(() => _brandId = val),
            onCreateNew: (query) => _showCreateBrandQuickDialog(initialName: query),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Crear marca',
          child: IconButton.filledTonal(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateBrandQuickDialog(),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryAndBrandSection(
    BuildContext context,
    List<Category> categories,
    List<Brand> brands,
  ) {
    final isNarrow = MediaQuery.of(context).size.width < 450;
    final categoryWidget = _buildCategorySelector(categories);

    if (isNarrow || _isService) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          categoryWidget,
          if (!_isService) ...[
            const SizedBox(height: 12),
            _buildBrandSelector(brands),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: categoryWidget),
        const SizedBox(width: 16),
        Expanded(child: _buildBrandSelector(brands)),
      ],
    );
  }

  Widget _buildProductImagePicker() {
    final resolvedImageUrl = _deleteExistingImage ? null : resolveImageUrl(widget.product?.imageUrl);
    final hasValidExistingImage = resolvedImageUrl != null && resolvedImageUrl.isNotEmpty;
    final hasSelected = _selectedImageBytes != null || (_selectedImagePath != null && _selectedImagePath!.isNotEmpty);
    final hasAny = hasSelected || hasValidExistingImage;

    Widget imageContent;
    if (_isUploadingImage) {
      imageContent = const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_selectedImageBytes != null) {
      imageContent = Image.memory(
        _selectedImageBytes!,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
      );
    } else if (_selectedImagePath != null && _selectedImagePath!.isNotEmpty) {
      imageContent = Image.file(
        File(_selectedImagePath!),
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 36, color: Colors.grey),
      );
    } else if (hasValidExistingImage) {
      imageContent = Image.network(
        resolvedImageUrl,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 36, color: Colors.grey),
      );
    } else {
      imageContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 32, color: Colors.grey.shade500),
          const SizedBox(height: 4),
          Text(
            'Subir Foto',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
        ],
      );
    }

    final isNarrow = MediaQuery.of(context).size.width < 450;

    final imageCard = InkWell(
      onTap: _isUploadingImage ? null : (hasAny ? _showImagePreviewDialog : _pickProductImage),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        key: const ValueKey('product_image_container'),
        width: isNarrow ? 80 : 90,
        height: isNarrow ? 80 : 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasSelected ? const Color(0xFF673AB7) : Colors.grey.shade300,
            width: hasSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Center(child: imageContent),
      ),
    );

    final imageWithBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        imageCard,
        if (hasAny)
          Positioned(
            top: -6,
            right: -6,
            child: IconButton(
              tooltip: 'Quitar foto',
              icon: const Icon(Icons.close, color: Colors.white, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: Colors.black38,
                padding: EdgeInsets.zero,
                minimumSize: const Size(24, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _isUploadingImage
                  ? null
                  : () {
                      setState(() {
                        _selectedImagePath = null;
                        _selectedImageBytes = null;
                        _selectedImageName = null;
                        _deleteExistingImage = true;
                      });
                    },
            ),
          ),
      ],
    );

    final actionsWidget = OutlinedButton.icon(
      onPressed: _isUploadingImage ? null : _pickProductImage,
      icon: const Icon(Icons.photo_library_outlined, size: 14),
      label: Text(hasAny ? 'Cambiar Foto' : 'Seleccionar Foto', style: const TextStyle(fontSize: 11)),
    );

    if (isNarrow) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            imageWithBadge,
            const SizedBox(height: 6),
            actionsWidget,
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          imageWithBadge,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Foto del Producto',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Visible en la cuadrícula de ventas del POS (PNG, JPG o WEBP).',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                actionsWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductImagePickerColumn() {
    final resolvedImageUrl = _deleteExistingImage ? null : resolveImageUrl(widget.product?.imageUrl);
    final hasValidExistingImage = resolvedImageUrl != null && resolvedImageUrl.isNotEmpty;
    final hasSelected = _selectedImageBytes != null || (_selectedImagePath != null && _selectedImagePath!.isNotEmpty);
    final hasAny = hasSelected || hasValidExistingImage;

    Widget imageContent;
    if (_isUploadingImage) {
      imageContent = const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_selectedImageBytes != null) {
      imageContent = Image.memory(
        _selectedImageBytes!,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
      );
    } else if (_selectedImagePath != null && _selectedImagePath!.isNotEmpty) {
      imageContent = Image.file(
        File(_selectedImagePath!),
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 36, color: Colors.grey),
      );
    } else if (hasValidExistingImage) {
      imageContent = Image.network(
        resolvedImageUrl,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 36, color: Colors.grey),
      );
    } else {
      imageContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 32, color: Colors.grey.shade500),
          const SizedBox(height: 4),
          Text(
            'Subir Foto',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
        ],
      );
    }

    final imageCard = InkWell(
      onTap: _isUploadingImage ? null : (hasAny ? _showImagePreviewDialog : _pickProductImage),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        key: const ValueKey('product_image_container'),
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasSelected ? const Color(0xFF673AB7) : Colors.grey.shade300,
            width: hasSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Center(child: imageContent),
      ),
    );

    final imageWithBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        imageCard,
        if (hasAny)
          Positioned(
            top: -6,
            right: -6,
            child: IconButton(
              tooltip: 'Quitar foto',
              icon: const Icon(Icons.close, color: Colors.white, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: Colors.black38,
                padding: EdgeInsets.zero,
                minimumSize: const Size(24, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _isUploadingImage
                  ? null
                  : () {
                      setState(() {
                        _selectedImagePath = null;
                        _selectedImageBytes = null;
                        _selectedImageName = null;
                        _deleteExistingImage = true;
                      });
                    },
            ),
          ),
      ],
    );

    final actionsWidget = OutlinedButton.icon(
      onPressed: _isUploadingImage ? null : _pickProductImage,
      icon: const Icon(Icons.photo_library_outlined, size: 13),
      label: Text(hasAny ? 'Cambiar Foto' : 'Seleccionar Foto', style: const TextStyle(fontSize: 10.5)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 30),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Foto del Producto',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 6),
          imageWithBadge,
          const SizedBox(height: 6),
          actionsWidget,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANTE: usar context.watch (no widget.provider) para que el dropdown
    // se reconstruya automáticamente cuando el provider notifica cambios
    // (ej: cuando se crea una categoría/marca nueva desde el diálogo rápido).
    final provider = context.watch<CatalogProvider>();
    final supplierProv = context.watch<SupplierProvider>();
    final settingsProv = context.watch<SettingsProvider>();
    final canSeeSupplier = settingsProv.features.suppliers;
    final isResponsableInscripto = settingsProv.settings?.isResponsableInscripto ?? false;
    final isNarrow = MediaQuery.of(context).size.width < 450;
    
    final categories = provider.categories;
    final brands = provider.brands;
    final suppliers = supplierProv.suppliers;
    final isBusy = provider.isLoading || _isUploadingImage;

    return RemoteScannerListener(
      debugLabel: 'ProductFormDialog',
      onBarcodeScanned: _handleFormBarcodeScan,
      child: PopScope(
        canPop: !isBusy,
        child: AlertDialog(
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              _isEditing ? 'Editar Producto' : 'Nuevo Producto',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
          ),
          if (_isEditing && widget.product != null)
            IconButton(
              key: const Key('product_share_button'),
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Compartir producto',
              onPressed: () => ProductShareHelper.shareProduct(
                widget.product!,
                context: context,
              ),
            ),
          IconButton(
            onPressed: isBusy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Cerrar',
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: isNarrow ? 260 : 640,
          maxWidth: 640,
        ),
        child: SizedBox(
          width: 640,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Selector Superior de Tipo de Ítem (Fijo arriba: 0px salto al cambiar pestaña) ──
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SegmentedButton<String>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            if (_isCombo) return Colors.deepPurple.shade50;
                            if (_isService) return Colors.teal.shade50;
                            return const Color(0xFFEFF6FF);
                          }
                          return const Color(0xFFF8FAFC);
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            if (_isCombo) return Colors.deepPurple.shade800;
                            if (_isService) return Colors.teal.shade800;
                            return const Color(0xFF1D4ED8);
                          }
                          return const Color(0xFF475569);
                        }),
                        side: WidgetStatePropertyAll(
                          BorderSide(color: Colors.blueGrey.shade200),
                        ),
                      ),
                      segments: const [
                        ButtonSegment<String>(
                          value: 'product',
                          icon: Icon(Icons.inventory_2_outlined, size: 16),
                          label: Text(
                            'Producto Físico',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        ButtonSegment<String>(
                          value: 'service',
                          icon: Icon(Icons.work_outline_rounded, size: 16),
                          label: Text(
                            'Servicio / Honorario',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        ButtonSegment<String>(
                          value: 'combo',
                          icon: Icon(Icons.layers_outlined, size: 16),
                          label: Text(
                            'Combo / Fracción',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      selected: {
                        _isCombo ? 'combo' : (_isService ? 'service' : 'product')
                      },
                      onSelectionChanged: (selection) {
                        final mode = selection.first;
                        setState(() {
                          _isCombo = mode == 'combo';
                          _isService = mode == 'service';
                          if (_isService) {
                            _isSoldByWeight = false;
                            _unitType = 'un';
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        if (isNarrow) ...[
                          _buildProductImagePicker(),
                          const SizedBox(height: 12),
                          // Nombre
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: InputDecoration(
                              labelText: _isService ? 'Nombre del Servicio / Honorario *' : 'Nombre del Producto *',
                              prefixIcon: const Icon(Icons.label_outline),
                              isDense: true,
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'El nombre es obligatorio' : null,
                          ),
                          const SizedBox(height: 12),
                          // Código Interno (PLU) + Código de barras
                          TextFormField(
                            controller: _internalCodeCtrl,
                            maxLength: 5,
                            decoration: const InputDecoration(
                              labelText: 'PLU (Interno) *',
                              prefixIcon: Icon(Icons.numbers),
                              counterText: '',
                              helperText: '5 dígitos numéricos',
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          if (!_isService) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _barcodeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Código de Barras (EAN)',
                                prefixIcon: Icon(Icons.qr_code_scanner),
                                helperText: 'Dejar vacío si es pesable',
                                isDense: true,
                              ),
                            ),
                          ],
                        ] else ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Lado izquierdo: Selector de Foto
                              _buildProductImagePickerColumn(),
                              const SizedBox(width: 16),
                              // Lado derecho: Nombre y Códigos (Grilla fija sin saltos horizontales)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextFormField(
                                      controller: _nameCtrl,
                                      decoration: InputDecoration(
                                        labelText: _isService ? 'Nombre del Servicio / Honorario *' : 'Nombre del Producto *',
                                        prefixIcon: const Icon(Icons.label_outline),
                                        isDense: true,
                                      ),
                                      validator: (v) => v == null || v.isEmpty ? 'El nombre es obligatorio' : null,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                              isDense: true,
                                            ),
                                            keyboardType: TextInputType.number,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 6,
                                          child: AnimatedOpacity(
                                            duration: const Duration(milliseconds: 180),
                                            opacity: _isService ? 0.45 : 1.0,
                                            child: TextFormField(
                                              controller: _barcodeCtrl,
                                              enabled: !_isService,
                                              decoration: InputDecoration(
                                                labelText: 'Código de Barras (EAN)',
                                                prefixIcon: const Icon(Icons.qr_code_scanner),
                                                helperText: _isService ? 'No aplica en servicios' : 'Dejar vacío si es pesable',
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        // Categoría y Marca (En Servicio/Honorario oculta Marca y expande Categoría)
                        _buildCategoryAndBrandSection(context, categories, brands),
                        const SizedBox(height: 12),
                        if (canSeeSupplier && !_isService)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Builder(
                              builder: (_) {
                                final sortedSuppliers =
                                    sortByAlphabeticalName(suppliers, (s) => s.name);
                                final hasSelection =
                                    sortedSuppliers.any((s) => s.id == _supplierId);
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: SearchableSelectField<int?>(
                                        value: hasSelection ? _supplierId : null,
                                        clearValue: null,
                                        isDense: true,
                                        labelText: 'Proveedor',
                                        dialogTitle: 'Seleccionar Proveedor',
                                        searchHintText: 'Buscar proveedor o CUIT...',
                                        prefixIcon: Icons.local_shipping_outlined,
                                        options: [
                                          const SearchableSelectOption<int?>(
                                            value: null,
                                            label: '— Sin proveedor —',
                                            isResetOption: true,
                                          ),
                                          ...sortedSuppliers.map((s) {
                                            final hasCuit =
                                                s.cuit != null && s.cuit!.trim().isNotEmpty;
                                            return SearchableSelectOption<int?>(
                                              value: s.id,
                                              label: s.name,
                                              subtitle: hasCuit
                                                  ? 'CUIT: ${s.cuit!.trim()}'
                                                  : null,
                                              searchKeywords: hasCuit
                                                  ? [s.cuit!.trim()]
                                                  : const [],
                                            );
                                          }),
                                        ],
                                        onChanged: (val) =>
                                            setState(() => _supplierId = val),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: 'Crear Nuevo Proveedor',
                                      child: IconButton.filledTonal(
                                        icon: const Icon(Icons.add),
                                        onPressed: () async {
                                          final createdId = await showDialog<int>(
                                            context: context,
                                            builder: (ctx) => const SupplierFormDialog(),
                                          );
                                          if (createdId != null && mounted) {
                                            setState(() => _supplierId = createdId);
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Recargar Proveedores',
                                      child: IconButton.filledTonal(
                                        icon: const Icon(Icons.refresh),
                                        onPressed: () {
                                          context.read<SupplierProvider>().fetchSuppliers();
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        // --- SECCIÓN CONTEXTUAL POR TIPO DE ÍTEM ---
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                          child: _isService
                              ? Column(
                                  key: const ValueKey<String>('product_form_service_section'),
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildPriceCostIvaSection(
                                      isNarrow: isNarrow,
                                      isResponsableInscripto: isResponsableInscripto,
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.teal.shade200),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.verified_outlined, size: 18, color: Colors.teal.shade800),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Configuración Fiscal de Servicio / Honorario (AFIP Concepto 2)',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.teal.shade900,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.teal.shade300),
                                                ),
                                                child: Text(
                                                  'Sin Stock Físico',
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.teal.shade800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Este ítem no descuenta unidades de inventario ni genera alertas de reposición o vencimiento. Al facturarse en ARCA/AFIP, reporta automáticamente Concepto 2 (Servicios) con su período facturado.',
                                            style: TextStyle(
                                              fontSize: 11.8,
                                              height: 1.35,
                                              color: Colors.teal.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: SwitchListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text(
                                            'Servicio Activo (Visible en cuadrícula del POS)',
                                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                          ),
                                          subtitle: const Text(
                                            'Permite facturar este servicio u honorario directamente desde la caja.',
                                            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                          ),
                                          value: _active,
                                          onChanged: (v) => setState(() => _active = v),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : _isCombo
                                  ? Column(
                                      key: const ValueKey<String>('product_form_combo_section'),
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _buildComboRecipeSection(isNarrow),
                                        const SizedBox(height: 12),
                                        _buildPriceCostIvaSection(
                                          isNarrow: isNarrow,
                                          isResponsableInscripto: isResponsableInscripto,
                                        ),
                                        const SizedBox(height: 12),
                                        _buildPriceTiersSection(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: SwitchListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              title: const Text(
                                                'Activo en POS (Visible para venta rápida)',
                                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                              ),
                                              value: _active,
                                              onChanged: (v) => setState(() => _active = v),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      key: const ValueKey<String>('product_form_physical_section'),
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _buildPriceCostIvaSection(
                                          isNarrow: isNarrow,
                                          isResponsableInscripto: isResponsableInscripto,
                                        ),
                                        const SizedBox(height: 12),
                                        _buildPriceTiersSection(),
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: isNarrow
                                              ? Column(
                                                  children: [
                                                    TextFormField(
                                                      controller: _stockCtrl,
                                                      decoration: InputDecoration(
                                                        labelText: 'Stock inicial',
                                                        suffixText: _unitType,
                                                        prefixIcon: const Icon(Icons.inventory_2_outlined),
                                                        isDense: true,
                                                      ),
                                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    TextFormField(
                                                      controller: _minStockCtrl,
                                                      decoration: const InputDecoration(
                                                        labelText: 'Stock Mínimo (Alerta)',
                                                        prefixIcon: Icon(Icons.notification_important_outlined),
                                                        helperText: 'Opcional: Dejar vacío para no alertar',
                                                        isDense: true,
                                                      ),
                                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    ),
                                                  ],
                                                )
                                              : Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 4,
                                                      child: TextFormField(
                                                        controller: _stockCtrl,
                                                        decoration: InputDecoration(
                                                          labelText: 'Stock inicial',
                                                          suffixText: _unitType,
                                                          prefixIcon: const Icon(Icons.inventory_2_outlined),
                                                          isDense: true,
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
                                                          isDense: true,
                                                        ),
                                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                        if (isNarrow)
                                          Column(
                                            children: [
                                              DropdownButtonFormField<String>(
                                                key: ValueKey('unit_type_narrow_$_unitType'),
                                                isExpanded: true,
                                                initialValue: _unitType,
                                                decoration: const InputDecoration(
                                                  labelText: 'Unidad de Medida',
                                                  prefixIcon: Icon(Icons.square_foot),
                                                  isDense: true,
                                                ),
                                                items: const [
                                                  DropdownMenuItem(value: 'un', child: Text('Unidades')),
                                                  DropdownMenuItem(value: 'kg', child: Text('Kilogramos')),
                                                  DropdownMenuItem(value: 'g', child: Text('Gramos')),
                                                  DropdownMenuItem(value: 'lt', child: Text('Litros')),
                                                ],
                                                onChanged: (val) => setState(() {
                                                  _unitType = val ?? 'un';
                                                  _isSoldByWeight = _unitType != 'un';
                                                }),
                                              ),
                                              SwitchListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: const Text('Venta p/peso (balanza)'),
                                                value: _isSoldByWeight,
                                                onChanged: (v) => setState(() {
                                                  _isSoldByWeight = v;
                                                  if (v && _unitType == 'un') {
                                                    _unitType = 'kg';
                                                  } else if (!v) {
                                                    _unitType = 'un';
                                                  }
                                                }),
                                              ),
                                              SwitchListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: const Text('Activo (Visible en POS)'),
                                                value: _active,
                                                onChanged: (v) => setState(() => _active = v),
                                              ),
                                            ],
                                          )
                                        else
                                          Row(
                                            children: [
                                              Expanded(
                                                flex: 4,
                                                child: DropdownButtonFormField<String>(
                                                  key: ValueKey('unit_type_wide_$_unitType'),
                                                  isExpanded: true,
                                                  initialValue: _unitType,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Unidad de Medida',
                                                    prefixIcon: Icon(Icons.square_foot),
                                                    isDense: true,
                                                  ),
                                                  items: const [
                                                    DropdownMenuItem(value: 'un', child: Text('Unidades')),
                                                    DropdownMenuItem(value: 'kg', child: Text('Kilogramos')),
                                                    DropdownMenuItem(value: 'g', child: Text('Gramos')),
                                                    DropdownMenuItem(value: 'lt', child: Text('Litros')),
                                                  ],
                                                  onChanged: (val) => setState(() {
                                                    _unitType = val ?? 'un';
                                                    _isSoldByWeight = _unitType != 'un';
                                                  }),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                flex: 4,
                                                child: SwitchListTile(
                                                  dense: true,
                                                  contentPadding: EdgeInsets.zero,
                                                  title: const Text('Venta p/peso', style: TextStyle(fontSize: 13)),
                                                  value: _isSoldByWeight,
                                                  onChanged: (v) => setState(() {
                                                    _isSoldByWeight = v;
                                                    if (v && _unitType == 'un') {
                                                      _unitType = 'kg';
                                                    } else if (!v) {
                                                      _unitType = 'un';
                                                    }
                                                  }),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 4,
                                                child: SwitchListTile(
                                                  dense: true,
                                                  contentPadding: EdgeInsets.zero,
                                                  title: const Text('Activo en POS', style: TextStyle(fontSize: 13)),
                                                  value: _active,
                                                  onChanged: (v) => setState(() => _active = v),
                                                ),
                                              ),
                                            ],
                                          ),
                                        // ── Control de Vencimiento y Alertas ──
                                        Builder(
                                          builder: (ctx) {
                                            SettingsProvider? sp;
                                            try {
                                              sp = ctx.watch<SettingsProvider?>();
                                            } catch (_) {}
                                            final canUseBatches = sp == null
                                                ? true
                                                : (sp.features.batchExpiration || sp.features.production);
                                            final canUseProduction =
                                                sp == null ? true : sp.features.production;
                                            final showExpBox = canUseBatches ||
                                                _trackBatches ||
                                                _expirationDate != null ||
                                                _expiryCtrl.text.trim().isNotEmpty;
                                            final showProdBox = canUseProduction || _hasProductionRecipe;

                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                if (showExpBox)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 8),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                      decoration: BoxDecoration(
                                                        color: Colors.orange.shade50.withValues(alpha: 0.45),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: Colors.orange.shade200),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Wrap(
                                                            alignment: WrapAlignment.spaceBetween,
                                                            crossAxisAlignment: WrapCrossAlignment.center,
                                                            spacing: 6,
                                                            runSpacing: 4,
                                                            children: [
                                                              Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  Flexible(
                                                                    child: Text(
                                                                      'Control de Vencimiento y Alertas (Opcional)',
                                                                      style: TextStyle(
                                                                        fontWeight: FontWeight.bold,
                                                                        fontSize: 12.5,
                                                                        color: Colors.orange.shade900,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(width: 4),
                                                                  Tooltip(
                                                                    message:
                                                                        'Cascada de Pre-Alerta: Pre -> 7d -> 3d -> Vto.\n'
                                                                        'Vida útil: ej. 90 calcula VTO = hoy + 90 días al ingresar mercadería o imprimir etiquetas.',
                                                                    child: Icon(
                                                                      Icons.info_outline_rounded,
                                                                      size: 15,
                                                                      color: Colors.orange.shade800,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              TextButton.icon(
                                                                style: TextButton.styleFrom(
                                                                  visualDensity: VisualDensity.compact,
                                                                  foregroundColor: Colors.orange.shade900,
                                                                ),
                                                                onPressed: () => setState(() => _showExpirationSection = !_showExpirationSection),
                                                                icon: Icon(
                                                                  _showExpirationSection ? Icons.expand_less_rounded : Icons.add_rounded,
                                                                  size: 17,
                                                                ),
                                                                label: Text(
                                                                  _showExpirationSection ? 'Ocultar' : 'Configurar vencimiento',
                                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          if (_showExpirationSection) ...[
                                                            const SizedBox(height: 8),
                                                            LayoutBuilder(
                                                              builder: (context, expConstraints) {
                                                                final Widget dateField = InkWell(
                                                                  onTap: () async {
                                                                    final picked = await showCompactDatePicker(
                                                                      context: context,
                                                                      initialDate: _expirationDate ?? DateTime.now().add(const Duration(days: 30)),
                                                                      firstDate: DateTime(2020),
                                                                      lastDate: DateTime(2100),
                                                                      helpText: 'Fecha de Vencimiento del Lote',
                                                                    );
                                                                    if (!mounted) return;
                                                                    if (picked != null) {
                                                                      setState(() {
                                                                        _expirationDate = picked;
                                                                        if (_expiryCtrl.text.trim().isEmpty) {
                                                                          final now = DateTime.now();
                                                                          final today = DateTime(now.year, now.month, now.day);
                                                                          final expDay = DateTime(picked.year, picked.month, picked.day);
                                                                          final diff = expDay.difference(today).inDays;
                                                                          if (diff >= 1 && diff <= 3650) {
                                                                            _expiryCtrl.text = diff.toString();
                                                                          }
                                                                        }
                                                                      });
                                                                    }
                                                                  },
                                                                  child: InputDecorator(
                                                                    decoration: InputDecoration(
                                                                      labelText: 'Fecha de Vencimiento (Lote)',
                                                                      prefixIcon: const Icon(Icons.calendar_today_outlined, size: 17),
                                                                      border: const OutlineInputBorder(),
                                                                      isDense: true,
                                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                                      suffixIcon: _expirationDate != null
                                                                          ? IconButton(
                                                                              tooltip: 'Quitar fecha de vencimiento',
                                                                              icon: const Icon(Icons.clear, size: 16),
                                                                              onPressed: () => setState(() => _expirationDate = null),
                                                                            )
                                                                          : null,
                                                                    ),
                                                                    child: Text(
                                                                      _expirationDate != null
                                                                          ? '${_expirationDate!.day.toString().padLeft(2, '0')}/${_expirationDate!.month.toString().padLeft(2, '0')}/${_expirationDate!.year}'
                                                                          : 'Sin fecha fija',
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: TextStyle(
                                                                        fontSize: 12.5,
                                                                        fontWeight: _expirationDate != null ? FontWeight.bold : FontWeight.normal,
                                                                        color: _expirationDate != null ? Colors.black87 : Colors.grey.shade600,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                );

                                                                final Widget preAlertField = TextFormField(
                                                                  controller: _expiryAlertDaysCtrl,
                                                                  decoration: const InputDecoration(
                                                                    labelText: 'Pre-Alerta',
                                                                    suffixText: 'días',
                                                                    border: OutlineInputBorder(),
                                                                    isDense: true,
                                                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                                  ),
                                                                  keyboardType: TextInputType.number,
                                                                );

                                                                final Widget shelfLifeField = TextFormField(
                                                                  controller: _expiryCtrl,
                                                                  decoration: const InputDecoration(
                                                                    labelText: 'Validez',
                                                                    prefixIcon: Icon(Icons.hourglass_bottom_outlined, size: 17),
                                                                    suffixText: 'días',
                                                                    border: OutlineInputBorder(),
                                                                    isDense: true,
                                                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                                  ),
                                                                  keyboardType: TextInputType.number,
                                                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                                                  onChanged: (v) {
                                                                    final n = int.tryParse(v.trim());
                                                                    if (n != null && n > 0 && n <= 3650) {
                                                                      setState(() {
                                                                        _expirationDate = DateTime.now().add(Duration(days: n));
                                                                      });
                                                                    }
                                                                  },
                                                                  validator: (v) {
                                                                    if (v == null || v.trim().isEmpty) return null;
                                                                    final n = int.tryParse(v.trim());
                                                                    if (n == null || n < 1 || n > 3650) {
                                                                      return 'Ingresá un número entre 1 y 3650';
                                                                    }
                                                                    return null;
                                                                  },
                                                                );

                                                                if (expConstraints.maxWidth >= 480) {
                                                                  return Row(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      Expanded(flex: 5, child: dateField),
                                                                      const SizedBox(width: 8),
                                                                      Expanded(flex: 3, child: preAlertField),
                                                                      const SizedBox(width: 8),
                                                                      Expanded(flex: 3, child: shelfLifeField),
                                                                    ],
                                                                  );
                                                                }
                                                                return Column(
                                                                  children: [
                                                                    dateField,
                                                                    const SizedBox(height: 8),
                                                                    Row(
                                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                                      children: [
                                                                        Expanded(child: preAlertField),
                                                                        const SizedBox(width: 8),
                                                                        Expanded(child: shelfLifeField),
                                                                      ],
                                                                    ),
                                                                  ],
                                                                );
                                                              },
                                                            ),
                                                          ],
                                                          _buildBatchTrackingSubpanel(),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                if (showProdBox) _buildProductionRecipeSection(),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        Consumer<CatalogProvider>(
          builder: (_, p, __) {
            final isBusy = p.isLoading || _isUploadingImage;
            return TextButton(
              onPressed: isBusy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            );
          },
        ),
        Consumer<CatalogProvider>(
          builder: (_, p, __) {
            final isBusy = p.isLoading || _isUploadingImage;
            return FilledButton(
              onPressed: isBusy ? null : _submit,
              child: isBusy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEditing ? 'Guardar Cambios' : 'Crear Producto'),
            );
          },
        ),
      ],
      ),
      ),
    );
  }

  Widget _buildBatchTrackingSubpanel() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Controlar vencimientos por lotes',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
              subtitle: const Text(
                'Cada compra u horneado crea un lote propio y las ventas descuentan automáticamente por orden.',
                style: TextStyle(fontSize: 11),
              ),
              value: _trackBatches,
              onChanged: (v) => setState(() {
                _trackBatches = v;
                if (v) _showExpirationSection = true;
              }),
            ),
          ),
          if (_trackBatches) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) {
                final policyField = DropdownButtonFormField<String>(
                  initialValue: _lotDeductionPolicy,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Orden de salida en caja',
                    isDense: true,
                    prefixIcon: Icon(Icons.sort, size: 18),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'fefo',
                      child: Text('Vence antes sale primero (recomendado)'),
                    ),
                    DropdownMenuItem(
                      value: 'fifo',
                      child: Text('Más antiguo en stock sale primero'),
                    ),
                  ],
                  onChanged: (val) => setState(() => _lotDeductionPolicy = val ?? 'fefo'),
                );

                final initialBatchField = !_isEditing
                    ? TextFormField(
                        controller: _initialBatchCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Código Lote Inicial (opcional)',
                          hintText: 'Ej. LOTE-APERTURA',
                          isDense: true,
                          prefixIcon: Icon(Icons.qr_code_outlined, size: 18),
                        ),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.layers_outlined, size: 17),
                          label: const Text('Ver / Administrar Lotes'),
                          onPressed: () {
                            if (widget.product == null) return;
                            showDialog(
                              context: context,
                              builder: (_) => ProductBatchesDialog(
                                provider: widget.provider,
                                product: widget.product!,
                              ),
                            );
                          },
                        ),
                      );

                if (c.maxWidth >= 480) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: policyField),
                      const SizedBox(width: 8),
                      Expanded(flex: 5, child: initialBatchField),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    policyField,
                    const SizedBox(height: 8),
                    initialBatchField,
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Permitir vender lotes vencidos sin PIN de supervisor',
                  style: TextStyle(fontSize: 12),
                ),
                value: _allowSellExpired,
                onChanged: (v) => setState(() => _allowSellExpired = v),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double get _productionRecipeTotalCost => _recipeIngredients.fold<double>(
        0.0,
        (acc, ing) {
          final q = double.tryParse(ing['quantity']?.toString() ?? '0') ?? 0.0;
          final c = double.tryParse(ing['cost_price']?.toString() ?? '0') ?? 0.0;
          final w = double.tryParse((ing['waste_pct'] ?? 0).toString()) ?? 0.0;
          return acc + (q * (1.0 + w / 100.0) * c);
        },
      );

  Future<void> _openRecipeIngredientPicker() async {
    List<Product> remote = const [];
    try {
      remote = await widget.provider.fetchAllActiveProductsForProduction();
    } catch (_) {
      remote = const [];
    }
    if (!mounted) return;
    final pool = <int, Product>{
      for (final p in widget.provider.products) p.id: p,
      for (final p in remote) p.id: p,
    };

    bool isEligibleIngredient(Product p) =>
        !p.isCombo &&
        !p.isService &&
        p.active &&
        p.id != widget.product?.id &&
        !_recipeIngredients.any(
          (r) => ((r['ingredient_product_id'] as num?)?.toInt() ??
                  (r['id'] as num?)?.toInt()) ==
              p.id,
        );

    SearchableSelectOption<int> buildOption(Product p) => SearchableSelectOption<int>(
          value: p.id,
          label: p.name,
          subtitle: 'Stock: ${p.stock.toQty()} ${p.unitType} • Costo: \$${p.costPrice.toCurrency()}',
          badgeText: p.hasProductionRecipe
              ? 'SEMI-ELABORADO'
              : (p.trackBatches ? 'CON LOTES' : null),
          searchKeywords: [
            p.internalCode,
            if (p.barcode != null && p.barcode!.isNotEmpty) p.barcode!,
          ],
        );

    final options = pool.values.where(isEligibleIngredient).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    int? selectedId;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar Insumo / Semi-Elaborado a Receta'),
        content: SizedBox(
          width: 440,
          child: SearchableSelectField<int>(
            value: selectedId,
            labelText: 'Materia prima o sub-receta',
            prefixIcon: Icons.search,
            searchHintText: 'Buscar por nombre, código o barras...',
            options: options.map(buildOption).toList(),
            onRemoteSearch: (q) async {
              final found = await widget.provider.searchProductsRemote(q, perPage: 80);
              final matched = <SearchableSelectOption<int>>[];
              for (final p in found) {
                pool[p.id] = p;
                if (isEligibleIngredient(p)) {
                  matched.add(buildOption(p));
                }
              }
              return matched;
            },
            onChanged: (id) {
              selectedId = id;
              if (id != null) Navigator.pop(ctx);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (selectedId != null && mounted) {
      final p = pool[selectedId!];
      if (p != null) {
        setState(() {
          _recipeIngredients.add({
            'id': p.id,
            'ingredient_product_id': p.id,
            'name': p.name,
            'quantity': 1.0,
            'waste_pct': 0.0,
            'cost_price': p.costPrice,
            'stock': p.stock,
            'unit_type': p.unitType,
            'track_batches': p.trackBatches,
          });
        });
      }
    }
  }

  Widget _buildProductionRecipeSection() {
    final yieldQty = double.tryParse(_recipeYieldCtrl.text.replaceAll(',', '.').trim()) ?? 1.0;
    final totalCost = _productionRecipeTotalCost;
    final unitCost = yieldQty > 0 ? totalCost / yieldQty : totalCost;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.deepOrange.shade50.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.deepOrange.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Icon(Icons.bakery_dining_outlined, size: 18, color: Colors.deepOrange.shade800),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Receta de Elaboración Propia (Cocina / Pastelería)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: Colors.deepOrange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: const Text(
                  'Mantiene stock físico por lotes al registrar tandas de producción (admite sub-recetas multi-nivel).',
                  style: TextStyle(fontSize: 11),
                ),
                value: _hasProductionRecipe,
                onChanged: (v) => setState(() => _hasProductionRecipe = v),
              ),
            ),
            if (_hasProductionRecipe) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 190,
                    child: TextFormField(
                      controller: _recipeYieldCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Rendimiento receta ($_unitType)',
                        isDense: true,
                        prefixIcon: const Icon(Icons.scale_outlined, size: 18),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 17),
                    label: const Text('Agregar insumo'),
                    onPressed: _openRecipeIngredientPicker,
                  ),
                  if (_recipeIngredients.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.calculate_outlined, size: 17),
                      label: Text('Aplicar costo (\$${unitCost.toCurrency()})'),
                      onPressed: () {
                        setState(() {
                          _costCtrl.text = unitCost.toArsInput();
                        });
                      },
                    ),
                ],
              ),
              if (_recipeIngredients.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Aún no agregaste insumos a la receta.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                  ),
                )
              else ...[
                const SizedBox(height: 8),
                ...List.generate(_recipeIngredients.length, (idx) {
                  final r = _recipeIngredients[idx];
                  final qty = double.tryParse(r['quantity']?.toString() ?? '1') ?? 1.0;
                  final waste = double.tryParse((r['waste_pct'] ?? 0).toString()) ?? 0.0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['name']?.toString() ?? 'Insumo',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                              ),
                              Text(
                                'Costo: \$${((r['cost_price'] as num?)?.toDouble() ?? 0).toCurrency()} / ${r['unit_type'] ?? 'un'}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 82,
                          child: TextFormField(
                            initialValue: qty.toQty(),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: r['unit_type']?.toString() ?? 'un',
                              isDense: true,
                            ),
                            onChanged: (v) {
                              final parsed = double.tryParse(v.replaceAll(',', '.').trim());
                              if (parsed != null && parsed > 0) {
                                setState(() => _recipeIngredients[idx]['quantity'] = parsed);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 72,
                          child: TextFormField(
                            initialValue: waste.toQty(),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: '% Merma',
                              isDense: true,
                            ),
                            onChanged: (v) {
                              final parsed = double.tryParse(v.replaceAll(',', '.').trim()) ?? 0.0;
                              setState(() => _recipeIngredients[idx]['waste_pct'] = parsed.clamp(0.0, 100.0));
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar',
                          icon: const Icon(Icons.close, size: 17),
                          onPressed: () => setState(() => _recipeIngredients.removeAt(idx)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReadonlyMetricBox({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: valueColor ?? const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStalePriceCardWarning() {
    final staleCardPrice = widget.product?.priceCard;
    final staleWholesalePrice = widget.product?.priceWholesale;
    final hasCard = _isEditing && staleCardPrice != null && staleCardPrice > 0;
    final hasWholesale =
        _isEditing && staleWholesalePrice != null && staleWholesalePrice > 0;
    if (!hasCard && !hasWholesale) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _priceCtrl,
      builder: (context, _, __) {
        final currentSelling = ArsThousandsInputFormatter.parse(_priceCtrl.text);
        final isCardBelowSelling =
            hasCard && currentSelling > staleCardPrice + 0.01;
        if (!isCardBelowSelling && !hasWholesale) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.amber.shade900),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isCardBelowSelling
                          ? 'Precio Tarjeta fijo (\$${staleCardPrice.toCurrency()}) menor al Precio Venta (\$${currentSelling.toCurrency()})'
                          : 'Este producto tiene Precio Mayorista fijo (\$${staleWholesalePrice!.toCurrency()}) heredado en BD',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                isCardBelowSelling
                    ? 'Si no se limpia, al elegir Lista Tarjeta en el POS se cobrará este importe fijo en lugar del recargo porcentual global.'
                    : 'Podés limpiarlo al guardar para que el producto utilice exclusivamente el % Mayorista global.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.amber.shade900,
                ),
              ),
              if (isCardBelowSelling)
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    visualDensity: VisualDensity.compact,
                    value: _clearStalePriceCard,
                    onChanged: (val) =>
                        setState(() => _clearStalePriceCard = val ?? false),
                    title: Text(
                      'Limpiar precio Tarjeta fijo al guardar (usar % global)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ),
              if (hasWholesale)
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    visualDensity: VisualDensity.compact,
                    value: _clearStalePriceWholesale,
                    onChanged: (val) => setState(
                        () => _clearStalePriceWholesale = val ?? false),
                    title: Text(
                      'Limpiar precio Mayorista fijo (\$${staleWholesalePrice.toCurrency()}) al guardar (usar % global)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPriceCostIvaSection({
    required bool isNarrow,
    required bool isResponsableInscripto,
  }) {
    Widget withStalePriceCardWarning(Widget child) {
      final warning = _buildStalePriceCardWarning();
      if (warning is SizedBox) return child;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [child, warning],
      );
    }
    Widget buildPriceField() => TextFormField(
          controller: _priceCtrl,
          decoration: InputDecoration(
            labelText: _isService ? 'Importe / Honorario *' : 'Precio Venta *',
            prefixText: '\$ ',
            isDense: true,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [ArsThousandsInputFormatter()],
          validator: (v) {
            final price = ArsThousandsInputFormatter.tryParse(v);
            if (price == null) return 'Ingrese un precio válido';
            if (!_isCombo && !_isService) {
              final cost = ArsThousandsInputFormatter.parse(_costCtrl.text);
              if (cost > 0 && price < cost) {
                return 'El precio de venta debe ser mayor o igual al costo';
              }
            }
            return null;
          },
        );

    Widget buildIvaField() => DropdownButtonFormField<double>(
          initialValue: _ivaRate,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'IVA AFIP',
            prefixIcon: isNarrow
                ? const Icon(Icons.account_balance_outlined, size: 18)
                : null,
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 21.0, child: Text('21%')),
            DropdownMenuItem(value: 10.5, child: Text('10.5%')),
            DropdownMenuItem(value: 27.0, child: Text('27%')),
            DropdownMenuItem(value: 0.0, child: Text('0% Ex.')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _ivaRate = v);
          },
        );

    if (_isService) {
      if (isNarrow) {
        return withStalePriceCardWarning(Column(
          children: [
            buildPriceField(),
            if (isResponsableInscripto) ...[
              const SizedBox(height: 12),
              buildIvaField(),
            ],
          ],
        ));
      }
      return withStalePriceCardWarning(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: buildPriceField()),
          if (isResponsableInscripto) ...[
            const SizedBox(width: 12),
            Expanded(flex: 4, child: buildIvaField()),
          ],
        ],
      ));
    }

    if (_isCombo) {
      final recipeCost = _comboRecipeTotalCost;
      final comboPrice = ArsThousandsInputFormatter.parse(_priceCtrl.text);
      final hasComboMargin = recipeCost > 0 && comboPrice > 0;
      final comboMarginPct = hasComboMargin
          ? ((comboPrice - recipeCost) / recipeCost) * 100.0
          : 0.0;
      final marginText = hasComboMargin
          ? '${comboMarginPct.toCleanMargin()}%'
          : '—';
      final marginColor = !hasComboMargin
          ? const Color(0xFF64748B)
          : (comboMarginPct >= 0
              ? Colors.green.shade700
              : Colors.red.shade700);

      final costMetric = _buildReadonlyMetricBox(
        label: 'Costo Receta (Calc.)',
        value: _comboIngredients.isEmpty ? '—' : '\$${recipeCost.toCurrency()}',
      );
      final marginMetric = _buildReadonlyMetricBox(
        label: '% Margen Receta',
        value: marginText,
        valueColor: marginColor,
      );

      if (isNarrow) {
        return withStalePriceCardWarning(Column(
          children: [
            Row(
              children: [
                Expanded(child: costMetric),
                const SizedBox(width: 8),
                Expanded(child: marginMetric),
              ],
            ),
            const SizedBox(height: 12),
            buildPriceField(),
            if (isResponsableInscripto) ...[
              const SizedBox(height: 12),
              buildIvaField(),
            ],
          ],
        ));
      }

      return withStalePriceCardWarning(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: costMetric),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: marginMetric),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: buildPriceField()),
          if (isResponsableInscripto) ...[
            const SizedBox(width: 12),
            Expanded(flex: 2, child: buildIvaField()),
          ],
        ],
      ));
    }

    // Producto Físico estándar
    if (isNarrow) {
      return withStalePriceCardWarning(Column(
        children: [
          TextFormField(
            controller: _costCtrl,
            decoration: const InputDecoration(
              labelText: 'Precio Costo (Opc.)',
              prefixText: '\$ ',
              helperText: 'Opcional (\$0) o calculado desde Venta + %',
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ArsThousandsInputFormatter()],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final parsed = ArsThousandsInputFormatter.tryParse(v);
              if (parsed == null || parsed < 0) return 'Ingrese un monto válido';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _marginCtrl,
            decoration: const InputDecoration(
              labelText: '% Margen',
              suffixText: '%',
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          buildPriceField(),
          if (isResponsableInscripto) ...[
            const SizedBox(height: 12),
            buildIvaField(),
          ],
        ],
      ));
    }

    return withStalePriceCardWarning(Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _costCtrl,
            decoration: const InputDecoration(
              labelText: 'Precio Costo (Opc.)',
              prefixText: '\$ ',
              hintText: '0',
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ArsThousandsInputFormatter()],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final parsed = ArsThousandsInputFormatter.tryParse(v);
              if (parsed == null || parsed < 0) return 'Monto inválido';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _marginCtrl,
            decoration: const InputDecoration(
              labelText: '% Margen',
              suffixText: '%',
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: buildPriceField()),
        if (isResponsableInscripto) ...[
          const SizedBox(width: 12),
          Expanded(flex: 2, child: buildIvaField()),
        ],
      ],
    ));
  }

  Widget _buildComboRecipeSection(bool isNarrow) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50.withValues(alpha: 0.45),
        border: Border.all(color: Colors.deepPurple.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers_rounded,
                        size: 17, color: Colors.deepPurple.shade700),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Productos incluidos en el Combo (${_comboIngredients.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Colors.deepPurple.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.deepPurple.shade800,
                  side: BorderSide(color: Colors.deepPurple.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.playlist_add_rounded, size: 17),
                label: const Text(
                  'Añadir Producto',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                onPressed: () async {
                  await _showIngredientSearchDialog(context, widget.provider);
                },
              ),
            ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('catalog_combo_inline_search'),
            controller: _comboInlineSearchCtrl,
            focusNode: _comboInlineSearchFocus,
            textInputAction: TextInputAction.search,
            onChanged: _onInlineComboSearchChanged,
            onSubmitted: _onInlineComboSearchSubmitted,
            decoration: InputDecoration(
              hintText: 'Buscar o pistolear producto para incluir...',
              hintStyle: const TextStyle(fontSize: 12.5),
              prefixIcon: const Icon(Icons.qr_code_scanner, size: 19),
              suffixIcon: _isSearchingInlineCombo
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_comboInlineSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Limpiar búsqueda',
                          icon: const Icon(Icons.clear, size: 17),
                          onPressed: () {
                            setState(() {
                              _comboInlineSearchCtrl.clear();
                              _comboInlineSearchResults = [];
                            });
                          },
                        )
                      : null),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          if (_comboInlineSearchResults.isNotEmpty) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Material(
                color: Colors.white,
                elevation: 1,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.deepPurple.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _comboInlineSearchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, idx) {
                      final p = _comboInlineSearchResults[idx];
                      final alreadyIn =
                          _comboIngredients.any((ing) => ing['id'] == p.id);
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'PLU: ${p.internalCode} · Stock: ${p.stock.toUnitStockDisplay(isSoldByWeight: p.isSoldByWeight, unitSuffix: p.unitType)} · \$${p.sellingPrice.toCurrency()}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: alreadyIn
                            ? Icon(Icons.check_circle,
                                color: Colors.green.shade600, size: 18)
                            : Icon(Icons.add_circle_outline,
                                color: Colors.deepPurple.shade600, size: 19),
                        onTap: () => _addProductToComboRecipe(p),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
          if (_comboIngredients.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Buscá o pistoleá arriba los productos incluidos y definí la cantidad que se descontará del stock al vender este combo.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            ..._comboIngredients.map((ing) {
              final ingKey = (ing['id'] as num?)?.toInt() ?? ing.hashCode;
              final qty = (ing['quantity'] as num?)?.toDouble() ?? 1.0;
              final unitCost = (ing['cost_price'] as num?)?.toDouble() ?? 0.0;
              final unitSell =
                  (ing['selling_price'] as num?)?.toDouble() ?? 0.0;
              final availStock = (ing['stock'] as num?)?.toDouble();
              final unitType = ing['unit_type']?.toString() ?? 'un';
              final exceedsStock = availStock != null && qty > availStock;
              final hasFractionalQty =
                  (qty - qty.roundToDouble()).abs() >= 0.0005;
              final showFractionBar =
                  _expandedComboFractionIds.contains(ingKey);

              final infoWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ing['name']?.toString() ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      if (availStock != null)
                        Text(
                          'Stock: ${availStock.toUnitStockDisplay(unitSuffix: unitType)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: exceedsStock
                                ? Colors.amber.shade800
                                : Colors.grey.shade700,
                          ),
                        ),
                      Text(
                        'Costo u.: \$${unitCost.toCurrency()}',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade700),
                      ),
                      Text(
                        'Venta u.: \$${unitSell.toCurrency()}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      if (qty > 0)
                        Text(
                          'Subtotal normal: \$${(unitSell * qty).toCurrency()}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple.shade700,
                          ),
                        ),
                    ],
                  ),
                ],
              );

              final controlsRow = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 82,
                    child: TextFormField(
                      key: ValueKey('combo_ing_qty_${ing['id']}'),
                      controller: _getComboQtyCtrl(ingKey, qty),
                      decoration: const InputDecoration(
                        labelText: 'Cant.',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(),
                        errorStyle: TextStyle(fontSize: 10),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,/]')),
                      ],
                      validator: (v) {
                        final parsed = parseQuantityOrFraction(v ?? '');
                        if (parsed == null || parsed <= 0) return '> 0';
                        return null;
                      },
                      onChanged: (v) {
                        final parsed = parseQuantityOrFraction(v);
                        setState(() {
                          ing['quantity'] = parsed ?? 0.0;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: showFractionBar
                        ? 'Ocultar fracciones'
                        : 'Fraccionar porción (1/6, 1/8, 1/16, ÷ N...)',
                    child: InkWell(
                      key: Key('catalog_combo_fraction_toggle_$ingKey'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() {
                        if (showFractionBar) {
                          _expandedComboFractionIds.remove(ingKey);
                        } else {
                          _expandedComboFractionIds.add(ingKey);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 7),
                        decoration: BoxDecoration(
                          color: (showFractionBar || hasFractionalQty)
                              ? Colors.deepPurple.shade600
                              : Colors.deepPurple.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (showFractionBar || hasFractionalQty)
                                ? Colors.deepPurple.shade600
                                : Colors.deepPurple.shade200,
                          ),
                        ),
                        child: Text(
                          '1/x',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: (showFractionBar || hasFractionalQty)
                                ? Colors.white
                                : Colors.deepPurple.shade700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Quitar del combo',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _comboQtyCtrls.remove(ingKey)?.dispose();
                      _comboCustomPartsCtrls.remove(ingKey)?.dispose();
                      _expandedComboFractionIds.remove(ingKey);
                      _comboIngredients.remove(ing);
                    }),
                  ),
                ],
              );

              return Container(
                key: ValueKey('combo_ing_row_${ing['id']}'),
                margin: const EdgeInsets.only(bottom: 8.0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: exceedsStock ? Colors.red.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: exceedsStock
                        ? Colors.red.shade300
                        : Colors.deepPurple.shade100,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNarrow) ...[
                      infoWidget,
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: controlsRow,
                      ),
                    ] else
                      Row(
                        children: [
                          Expanded(child: infoWidget),
                          const SizedBox(width: 8),
                          controlsRow,
                        ],
                      ),
                    if (showFractionBar)
                      _buildComboFractionCalculatorBar(ing, ingKey, qty),
                    if (exceedsStock)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 15, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'La cantidad (${qty.toQty()}) supera tu stock disponible actual (${availStock.toQty()} $unitType).',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }),
            _buildComboLiveSummaryCard(),
          ],
        ],
      ),
    );
  }

  // --- SECCIÓN PRECIOS POR VOLUMEN ---
  Widget _buildPriceTiersSection() {
    final isExpanded = _expandPriceTiers || _priceTiers.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: isExpanded ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withValues(alpha: 0.55),
        border: Border.all(color: Colors.blue.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text.rich(
                  TextSpan(
                    text: 'Precios Mayoristas',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: Colors.blue.shade900,
                    ),
                    children: [
                      if (_priceTiers.isEmpty)
                        TextSpan(
                          text: ' · Sin escalas',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.blueGrey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () {
                  setState(() {
                    _expandPriceTiers = true;
                    _priceTiers.add({
                      // Sugerimos x10 para agilizar
                      'min_quantity': 10,
                      'unit_price':
                          ArsThousandsInputFormatter.parse(_priceCtrl.text),
                    });
                  });
                },
                icon: const Icon(Icons.add, size: 17),
                label: const Text(
                  'Añadir escala',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
            ),
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
                        initialValue: (tier['unit_price'] as num).toArsInput(),
                        decoration: const InputDecoration(labelText: 'Precio Unitario (\$)', isDense: true, prefixText: '\$ ', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [ArsThousandsInputFormatter()],
                        onChanged: (v) => _priceTiers[idx]['unit_price'] = ArsThousandsInputFormatter.parse(v),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Requerido';
                          if (ArsThousandsInputFormatter.tryParse(v) == null) return 'Precio inválido';
                          return null;
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.deepOrange),
                      tooltip: 'Eliminar escala',
                      onPressed: () => setState(() {
                        _priceTiers.removeAt(idx);
                        if (_priceTiers.isEmpty) _expandPriceTiers = false;
                      }),
                    ),
                  ],
                ),
              );
            }),
            const Text(
              'Nota: Si vende unidades fraccionadas, puede usar decimales (Ej: 5.5).',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  String _formatComboQtyForInput(double q) => formatQuantityInput(q);

  TextEditingController _getComboQtyCtrl(int ingId, double initialQty) {
    return _comboQtyCtrls.putIfAbsent(
      ingId,
      () => TextEditingController(text: _formatComboQtyForInput(initialQty)),
    );
  }

  TextEditingController _getComboCustomPartsCtrl(int ingId) {
    return _comboCustomPartsCtrls.putIfAbsent(
      ingId,
      () => TextEditingController(),
    );
  }

  void _applyComboFraction(Map<String, dynamic> ing, double fractionQty) {
    final ingId = (ing['id'] as num?)?.toInt();
    setState(() {
      ing['quantity'] = fractionQty;
      if (ingId != null) {
        final ctrl = _comboQtyCtrls[ingId];
        final formatted = _formatComboQtyForInput(fractionQty);
        if (ctrl != null) {
          ctrl.text = formatted;
          ctrl.selection = TextSelection.collapsed(offset: formatted.length);
        }
      }
    });
  }

  void _applyCustomComboParts(Map<String, dynamic> ing, int ingKey) {
    final raw = _comboCustomPartsCtrls[ingKey]?.text.trim() ?? '';
    final parts = int.tryParse(raw);
    if (parts == null || parts < 2 || parts > 100) {
      SnackBarService.warning(
        context,
        'Ingresá una cantidad de partes entre 2 y 100 (ej: 16).',
      );
      return;
    }
    _applyComboFraction(ing, 1.0 / parts);
  }

  Widget _buildComboFractionCalculatorBar(
    Map<String, dynamic> ing,
    int ingKey,
    double currentQty,
  ) {
    const fractions = <({String label, double qty})>[
      (label: '1/6', qty: 0.167),
      (label: '1/8', qty: 0.125),
      (label: '1/10', qty: 0.100),
      (label: '1/12', qty: 0.083),
      (label: '1', qty: 1.0),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Porción:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          ...fractions.map((f) {
            final selected = (currentQty - f.qty).abs() < 0.0006;
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _applyComboFraction(ing, f.qty),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.deepPurple.shade600
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected
                        ? Colors.deepPurple.shade600
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  f.label == '1'
                      ? '1 entero'
                      : '${f.label} (${f.qty.toStringAsFixed(3)})',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : Colors.grey.shade800,
                  ),
                ),
              ),
            );
          }),
          Text(
            'o ÷',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(
            width: 48,
            height: 26,
            child: TextField(
              key: Key('catalog_combo_parts_$ingKey'),
              controller: _getComboCustomPartsCtrl(ingKey),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              onSubmitted: (_) => _applyCustomComboParts(ing, ingKey),
              decoration: InputDecoration(
                hintText: '16',
                hintStyle: TextStyle(fontSize: 10.5, color: Colors.grey.shade400),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          InkWell(
            key: Key('catalog_combo_apply_parts_$ingKey'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => _applyCustomComboParts(ing, ingKey),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.deepPurple.shade300),
              ),
              child: Text(
                '1/N',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.deepPurple.shade800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _calcComboIngredientFit(double availStock, double qty) =>
      calcUnitsFitStock(availStock, qty);

  Widget _buildComboPromoPriceButton({
    required Key key,
    required double targetPrice,
    required String label,
    required String appliedLabel,
    required double currentPrice,
    bool isMarkup = false,
  }) {
    final isApplied =
        currentPrice > 0 && (currentPrice - targetPrice).abs() < 0.01;
    return OutlinedButton.icon(
      key: key,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        foregroundColor:
            isApplied ? Colors.green.shade800 : Colors.deepPurple.shade800,
        backgroundColor:
            isApplied ? Colors.green.shade50 : Colors.deepPurple.shade50,
        side: BorderSide(
          color:
              isApplied ? Colors.green.shade300 : Colors.deepPurple.shade300,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      onPressed: () {
        setState(() {
          _priceCtrl.text = targetPrice.toArsInput();
        });
      },
      icon: Icon(
        isApplied
            ? Icons.check_circle_outline
            : (isMarkup
                ? Icons.trending_up_rounded
                : Icons.local_offer_outlined),
        size: 14,
      ),
      label: Text(
        isApplied ? appliedLabel : label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildComboLiveSummaryCard() {
    double totalCost = 0.0;
    double totalIndividualSelling = 0.0;
    int? possibleCombos;

    for (final ing in _comboIngredients) {
      final qty = (ing['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (ing['cost_price'] as num?)?.toDouble() ?? 0.0;
      final unitSell = (ing['selling_price'] as num?)?.toDouble() ?? 0.0;
      final availStock = (ing['stock'] as num?)?.toDouble();

      if (qty > 0) {
        totalCost += unitCost * qty;
        totalIndividualSelling += unitSell * qty;
        if (availStock != null) {
          final fit = _calcComboIngredientFit(availStock, qty);
          if (possibleCombos == null || fit < possibleCombos) {
            possibleCombos = fit;
          }
        }
      } else {
        possibleCombos = 0;
      }
    }

    final bool autoFractionMode =
        ComboFractionPricing.hasFractionalQuantities(_comboIngredients);
    final bool isFractionMode = _manualPortionPricingMode ?? autoFractionMode;
    final comboPrice = ArsThousandsInputFormatter.parse(_priceCtrl.text);
    final profit = comboPrice - totalCost;
    final savings = totalIndividualSelling - comboPrice;
    final discountPct = totalIndividualSelling > 0
        ? (savings / totalIndividualSelling) * 100
        : 0.0;
    final armables = possibleCombos ?? 0;
    final basePriceAlreadyApplied = totalIndividualSelling > 0 &&
        comboPrice > 0 &&
        (comboPrice - totalIndividualSelling).abs() < 0.01;
    final yieldSummary = isFractionMode
        ? ComboFractionPricing.computeWholeUnitYield(
            ingredients: _comboIngredients,
            appliedPrice: comboPrice,
            proportionalBaseTotal: totalIndividualSelling,
          )
        : null;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calculate_outlined,
                        size: 17, color: Colors.deepPurple.shade700),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isFractionMode
                            ? 'Cálculo de Porción / Fracción'
                            : 'Resumen para calcular tu Precio de Combo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: Colors.deepPurple.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ComboFractionPricing.buildModeToggle(
                      isFractionMode: isFractionMode,
                      onChanged: (val) =>
                          setState(() => _manualPortionPricingMode = val),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: armables > 0
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: armables > 0
                              ? Colors.green.shade300
                              : Colors.red.shade300,
                        ),
                      ),
                      child: Text(
                        isFractionMode
                            ? 'Porciones/Fracciones armables hoy: $armables'
                            : 'Combos armables hoy: $armables',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: armables > 0
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Costo Total Ingredientes: \$${totalCost.toCurrency()}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                isFractionMode
                    ? 'Valor proporcional: \$${totalIndividualSelling.toCurrency()}'
                    : 'Suma Venta por Separado: \$${totalIndividualSelling.toCurrency()}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800),
              ),
              if (totalIndividualSelling > 0) ...[
                basePriceAlreadyApplied
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 14, color: Colors.green.shade800),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Base \$${totalIndividualSelling.toCurrency()} aplicada',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : OutlinedButton.icon(
                        key: const Key('catalog_apply_base_price_btn'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          foregroundColor: Colors.deepPurple.shade800,
                          backgroundColor: Colors.deepPurple.shade50,
                          side: BorderSide(color: Colors.deepPurple.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            _priceCtrl.text =
                                totalIndividualSelling.toArsInput();
                          });
                        },
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                        label: Text(
                          isFractionMode
                              ? 'Base (\$${totalIndividualSelling.toCurrency()})'
                              : 'Aplicar \$${totalIndividualSelling.toCurrency()} al precio',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                Builder(
                  builder: (_) {
                    final suggestions = ComboFractionPricing.buildSuggestions(
                      baseTotal: totalIndividualSelling,
                      isFractionMode: isFractionMode,
                    );
                    return Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          isFractionMode
                              ? 'Recomendado fracción:'
                              : 'Recomendado combo:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepPurple.shade800,
                          ),
                        ),
                        for (final s in suggestions)
                          _buildComboPromoPriceButton(
                            key: Key('catalog_apply_${s.keySuffix}_btn'),
                            targetPrice: s.targetPrice,
                            label: s.buttonLabel,
                            appliedLabel: s.appliedLabel,
                            currentPrice: comboPrice,
                            isMarkup: isFractionMode,
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
          if (comboPrice > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  isFractionMode
                      ? 'Tu Ganancia por Fracción: \$${profit.toCurrency()}'
                      : 'Tu Ganancia por Combo: \$${profit.toCurrency()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: profit >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
                if (totalIndividualSelling > 0 && savings > 0.01)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Text(
                      'Ahorro p/ el cliente: -\$${savings.toCurrency()} (-${discountPct.toStringAsFixed(1)}%)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade800,
                      ),
                    ),
                  )
                else if (totalIndividualSelling > 0 && savings < -0.01)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Text(
                      isFractionMode
                          ? '+\$${(-savings).toCurrency()} (+${(-discountPct).toStringAsFixed(1)}% vs proporcional)'
                          : '+\$${(-savings).toCurrency()} (+${(-discountPct).toStringAsFixed(1)}% vs sueltos)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                if (yieldSummary != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Text(
                      yieldSummary.formatSummary(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                  ),
              ],
            ),
          ],
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

  List<Product> _filterEligibleComboProducts(List<dynamic> rawResults) {
    return rawResults.where((p) {
      if (p.isCombo) return false;
      if (widget.excludeProductId != null && p.id == widget.excludeProductId) {
        return false;
      }
      return true;
    }).cast<Product>().toList();
  }

  Future<void> _doSearch(String query) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await widget.provider.searchProductsForCombo(query);
    if (!mounted) return;
    setState(() {
      _firstLoad = false;
      _loading = false;
      _results = _filterEligibleComboProducts(results);
    });
  }

  Future<void> _onSearchSubmittedOrScanned(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty || !mounted) return;
    _debounce?.cancel();
    _searchCtrl.text = q;
    _searchCtrl.selection = TextSelection.collapsed(offset: q.length);
    setState(() => _loading = true);

    final rawResults = await widget.provider.searchProductsForCombo(q);
    if (!mounted) return;

    final eligible = _filterEligibleComboProducts(rawResults);
    final exact = RemoteScannerService.findExactProductMatch(
      eligible,
      q,
      activeOnly: false,
    );
    final Product? chosen =
        exact ?? (eligible.length == 1 ? eligible.first : null);

    if (chosen != null) {
      final alreadyAdded =
          widget.comboIngredients.any((ing) => ing['id'] == chosen.id);
      if (alreadyAdded) {
        setState(() {
          _firstLoad = false;
          _loading = false;
          _results = eligible;
        });
        SnackBarService.info(
          context,
          '"${chosen.name}" ya está agregado al combo.',
        );
        return;
      }
      _addIngredient(chosen);
      _searchCtrl.clear();
      SnackBarService.success(context, 'Agregado al combo: ${chosen.name}');
      await _doSearch('');
      return;
    }

    setState(() {
      _firstLoad = false;
      _loading = false;
      _results = eligible;
    });
    if (eligible.isEmpty) {
      SnackBarService.info(
        context,
        'No se encontraron productos elegibles para "$q".',
      );
    }
  }

  void _addIngredient(dynamic p) {
    final alreadyAdded = widget.comboIngredients.any((ing) => ing['id'] == p.id);
    if (alreadyAdded) return;
    setState(() {
      widget.comboIngredients.add({
        'id': p.id,
        'name': p.name,
        'quantity': 1.0,
        'cost_price': p.costPrice,
        'selling_price': p.sellingPrice,
        'stock': p.stock,
        'unit_type': p.unitType,
        'is_sold_by_weight': p.isSoldByWeight,
      });
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return RemoteScannerListener(
      debugLabel: 'ComboIngredientPickerDialog',
      onBarcodeScanned: _onSearchSubmittedOrScanned,
      child: AlertDialog(
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
                onSubmitted: _onSearchSubmittedOrScanned,
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
                      subtitle: Text('Stock: ${p.stock.toQty()} ${p.unitType} | Costo: \$${p.costPrice.toCurrency()} | Venta: \$${p.sellingPrice.toCurrency()}'),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODAL DE AUMENTO MASIVO DE PRECIOS
// ─────────────────────────────────────────────────────────────────────────────
class BulkPriceUpdateDialog extends StatefulWidget {

  final CatalogProvider provider;
  final List<int>? targetProductIds;

  const BulkPriceUpdateDialog({super.key, required this.provider, this.targetProductIds});

  @override
  State<BulkPriceUpdateDialog> createState() => _BulkPriceUpdateDialogState();
}

class _BulkPriceUpdateDialogState extends State<BulkPriceUpdateDialog> {
  final _percentCtrl = TextEditingController();
  int? _selectedCategoryId;
  int? _selectedBrandId;
  int? _selectedSupplierId;
  String _roundingRule = 'none';
  String _targetField = 'selling_price';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final canSeeSupplier = context.read<SettingsProvider?>()?.features.suppliers ?? false;
      if (canSeeSupplier) {
        final supplierProv = context.read<SupplierProvider?>();
        if (supplierProv != null && supplierProv.suppliers.isEmpty && !supplierProv.isLoading) {
          supplierProv.fetchSuppliers();
        }
      }
    });
  }

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

    final canSeeSupplier = context.read<SettingsProvider?>()?.features.suppliers ?? false;

    // 1. Obtener la previsualización del backend
    final previewData = await widget.provider.bulkPricePreview(
      percentage: pct,
      roundingRule: _roundingRule,
      targetField: _targetField,
      productIds: widget.targetProductIds,
      categoryId: _selectedCategoryId,
      brandId: _selectedBrandId,
      supplierId: canSeeSupplier ? _selectedSupplierId : null,
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

    // Armar resumen visual de los filtros activos para el diálogo de confirmación
    final activeFilterLabels = <String>[];
    if (widget.targetProductIds != null && widget.targetProductIds!.isNotEmpty) {
      activeFilterLabels.add('Selección manual (${widget.targetProductIds!.length} prod.)');
    } else {
      if (_selectedCategoryId != null) {
        final catName = widget.provider.categories
            .where((c) => c.id == _selectedCategoryId)
            .map((c) => c.name)
            .firstOrNull;
        if (catName != null) activeFilterLabels.add('Categoría: $catName');
      }
      if (_selectedBrandId != null) {
        final brName = widget.provider.brands
            .where((b) => b.id == _selectedBrandId)
            .map((b) => b.name)
            .firstOrNull;
        if (brName != null) activeFilterLabels.add('Marca: $brName');
      }
      if (canSeeSupplier && _selectedSupplierId != null) {
        final supName = (context.read<SupplierProvider?>()?.suppliers ?? const [])
            .where((s) => s.id == _selectedSupplierId)
            .map((s) => s.name)
            .firstOrNull;
        if (supName != null) activeFilterLabels.add('Proveedor: $supName');
      }
    }
    final filterSummaryText = activeFilterLabels.isEmpty
        ? 'Todo el catálogo'
        : activeFilterLabels.join(' • ');

    // 2. Mostrar diálogo de Confirmación con Previsualización (sin ListView dentro de IntrinsicWidth)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Confirmar Aumento'),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
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
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blueGrey.shade200),
                  ),
                  child: Text(
                    'Alcance: $filterSummaryText',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey.shade800,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _targetField == 'cost_price'
                      ? 'Ejemplos de cómo quedará el Costo:'
                      : 'Ejemplos de cómo quedará el Precio de Venta:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < examples.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: Colors.grey.shade300),
                        Builder(
                          builder: (_) {
                            final ex = examples[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      ex['name']?.toString() ?? '',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      '\$${(num.tryParse(ex['old_price'].toString()) ?? 0).toCurrency()}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        decoration: TextDecoration.lineThrough,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      ' \$${(num.tryParse(ex['new_price'].toString()) ?? 0).toCurrency()}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                if (examples.any((ex) => (num.tryParse(ex['old_price'].toString()) ?? 0) == 0)) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Atención: Los productos con precio \$0 se mantendrán en \$0 al calcular porcentaje. Asigna su precio individualmente o desde el importador masivo.',
                            style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
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

    if (confirmed != true || !mounted) return;

    // 3. Ejecutar actualización real manteniendo el diálogo montado mientras procesa
    final message = await widget.provider.bulkPriceUpdate(
      percentage: pct,
      roundingRule: _roundingRule,
      targetField: _targetField,
      productIds: widget.targetProductIds,
      categoryId: _selectedCategoryId,
      brandId: _selectedBrandId,
      supplierId: canSeeSupplier ? _selectedSupplierId : null,
    );

    if (!mounted) return;

    if (message != null) {
      SnackBarService.success(context, '¡Precios actualizados! $message');
      Navigator.of(context).pop();
    } else {
      SnackBarService.error(context, widget.provider.errorMessage ?? 'Error al actualizar precios.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.provider.categories;
    final brands = widget.provider.brands;
    final supplierProv = context.watch<SupplierProvider?>();
    final canSeeSupplier = (context.watch<SettingsProvider?>()?.features.suppliers ?? false) && supplierProv != null;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Row(
        children: [
          Icon(Icons.trending_up, color: Colors.deepOrange.shade700),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Aumento Masivo de Precios'),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
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
                initialValue: _targetField,
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
                initialValue: _roundingRule,
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
                SearchableSelectField<int?>(
                  value: _selectedCategoryId,
                  clearValue: null,
                  labelText: 'Filtrar por Categoría',
                  dialogTitle: 'Filtrar por Categoría',
                  searchHintText: 'Buscar categoría o rubro...',
                  prefixIcon: Icons.folder_outlined,
                  border: const OutlineInputBorder(),
                  options: [
                    const SearchableSelectOption<int?>(
                      value: null,
                      label: 'Todas las categorías',
                      isResetOption: true,
                    ),
                    ...sortByAlphabeticalName(categories, (c) => c.name).map((c) {
                      final rId = c.rubroId ?? c.rubro?.id;
                      final rubroName = (rId != null
                              ? widget.provider.rubros
                                  .where((r) => r.id == rId)
                                  .firstOrNull
                                  ?.name
                              : null) ??
                          c.rubro?.name;
                      final hasRubro = rubroName != null && rubroName.trim().isNotEmpty;
                      return SearchableSelectOption<int?>(
                        value: c.id,
                        label: c.name,
                        subtitle: hasRubro ? 'Rubro: $rubroName' : null,
                        searchKeywords: hasRubro ? [rubroName] : const [],
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _selectedCategoryId = val),
                ),
                const SizedBox(height: 12),
                SearchableSelectField<int?>(
                  value: _selectedBrandId,
                  clearValue: null,
                  labelText: 'Filtrar por Marca',
                  dialogTitle: 'Filtrar por Marca',
                  searchHintText: 'Buscar marca...',
                  prefixIcon: Icons.branding_watermark_outlined,
                  border: const OutlineInputBorder(),
                  options: [
                    const SearchableSelectOption<int?>(
                      value: null,
                      label: 'Todas las marcas',
                      isResetOption: true,
                    ),
                    ...sortByAlphabeticalName(brands, (b) => b.name).map(
                      (b) => SearchableSelectOption<int?>(value: b.id, label: b.name),
                    ),
                  ],
                  onChanged: (val) => setState(() => _selectedBrandId = val),
                ),
                if (canSeeSupplier) ...[
                  const SizedBox(height: 12),
                  Consumer<SupplierProvider>(
                    builder: (context, supplierProv, _) {
                      final sortedSuppliers =
                          sortByAlphabeticalName(supplierProv.suppliers, (s) => s.name);
                      return SearchableSelectField<int?>(
                        value: _selectedSupplierId,
                        clearValue: null,
                        labelText: 'Filtrar por Proveedor',
                        dialogTitle: 'Filtrar por Proveedor',
                        searchHintText: 'Buscar proveedor o CUIT...',
                        prefixIcon: Icons.local_shipping_outlined,
                        border: const OutlineInputBorder(),
                        options: [
                          const SearchableSelectOption<int?>(
                            value: null,
                            label: 'Todos los proveedores',
                            isResetOption: true,
                          ),
                          ...sortedSuppliers.map((s) {
                            final hasCuit = s.cuit != null && s.cuit!.trim().isNotEmpty;
                            return SearchableSelectOption<int?>(
                              value: s.id,
                              label: s.name,
                              subtitle: hasCuit ? 'CUIT: ${s.cuit!.trim()}' : null,
                              searchKeywords: hasCuit ? [s.cuit!.trim()] : const [],
                            );
                          }),
                        ],
                        onChanged: (val) => setState(() => _selectedSupplierId = val),
                      );
                    },
                  ),
                ],
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.blue.shade700, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Aplicando a ${widget.targetProductIds!.length} productos seleccionados',
                          style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
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

  const BulkPriceHistoryDialog({super.key, required this.provider});

  @override
  State<BulkPriceHistoryDialog> createState() => _BulkPriceHistoryDialogState();
}

class _BulkPriceHistoryDialogState extends State<BulkPriceHistoryDialog> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      widget.provider.fetchPriceHistory();
      if (context.read<SettingsProvider>().features.suppliers) {
        final supplierProv = context.read<SupplierProvider>();
        if (supplierProv.suppliers.isEmpty && !supplierProv.isLoading) {
          supplierProv.fetchSuppliers();
        }
      }
    });
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: const Row(
        children: [
          Icon(Icons.history),
          SizedBox(width: 8),
          Expanded(child: Text('Historial de Aumentos')),
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

                final rawFilters = history['filters'];
                final filterParts = <String>[];
                if (rawFilters is Map) {
                  final catId = int.tryParse(rawFilters['category_id']?.toString() ?? '');
                  if (catId != null) {
                    final catName = p.categories.where((c) => c.id == catId).map((c) => c.name).firstOrNull;
                    filterParts.add('Cat: ${catName ?? '#$catId'}');
                  }
                  final brId = int.tryParse(rawFilters['brand_id']?.toString() ?? '');
                  if (brId != null) {
                    final brName = p.brands.where((b) => b.id == brId).map((b) => b.name).firstOrNull;
                    filterParts.add('Marca: ${brName ?? '#$brId'}');
                  }
                  final supId = int.tryParse(rawFilters['supplier_id']?.toString() ?? '');
                  if (supId != null) {
                    final suppliers = ctx.read<SupplierProvider>().suppliers;
                    final supName = suppliers.where((s) => s.id == supId).map((s) => s.name).firstOrNull;
                    filterParts.add('Prov: ${supName ?? '#$supId'}');
                  }
                }
                final filterText = filterParts.isEmpty ? 'Todo el catálogo' : filterParts.join(' • ');
                
                return ListTile(
                  leading: Icon(
                    isReverted ? Icons.undo : Icons.trending_up,
                    color: isReverted ? Colors.grey : (pct >= 0 ? Colors.green : Colors.red),
                  ),
                  title: Text('Aumento: ${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}% ($targetField)'),
                  subtitle: Text('Fecha: $formattedDate | Afectados: ${history['affected_count']} \nRedondeo: $roundingRule | Filtro: $filterText'),
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



