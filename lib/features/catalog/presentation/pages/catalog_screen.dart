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
import '../../domain/entities/rubro.dart';
import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import '../widgets/catalog_import_dialog.dart';
import '../widgets/supplier_quick_grid_dialog.dart';
import '../../domain/entities/brand.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/plan_upgrade_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/pos_search_history_popover.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/searchable_select_field.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import '../widgets/categories_manager_dialog.dart';
import '../widgets/brands_manager_dialog.dart';
import '../widgets/rubros_manager_dialog.dart';
import '../widgets/catalog_quick_create_dialogs.dart';
import '../widgets/print_labels_dialog.dart';
import '../widgets/product_image_preview_dialog.dart';
import '../widgets/product_hardware_fields_section.dart';
import '../widgets/product_f7_calc_config_panel.dart';
import '../../../pos/domain/services/hardware_calculator_engine.dart';
import '../../../auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import '../../../suppliers/models/supplier_model.dart';
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
  final _searchFocusNode = FocusNode();
  final _searchHistoryPortalController = OverlayPortalController();
  static const Object _searchHistoryTapGroupId =
      'catalog_search_history_popover';
  int _historyHighlightIndex = -1;
  Timer? _debounceTimer;
  final Map<int, Product> _selectedProducts = {};
  int? _contextMenuProductId;
  bool _showFiltersBar = false;
  CatalogProvider? _catalogProviderRef;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _catalogProviderRef = context.read<CatalogProvider?>();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleCatalogSearchHistoryKey);
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
    _hideSearchHistoryPopover();
    setState(() {
      _searchController.text = barcode;
    });
    context.read<CatalogProvider>().loadProducts(page: 1, search: barcode);
    SnackBarService.success(context, 'Buscando código escaneado: $barcode');
  }

  @override
  void dispose() {
    _catalogProviderRef?.safeClearCatalogFiltersSilently();
    HardwareKeyboard.instance.removeHandler(_handleCatalogSearchHistoryKey);
    _debounceTimer?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _handleCatalogSearchHistoryKey(KeyEvent event) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _searchHistoryPortalController.isShowing) {
      _hideSearchHistoryPopover();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        _searchHistoryPortalController.isShowing) {
      _hideSearchHistoryPopover();
      return false;
    }
    if (_searchController.text.trim().isEmpty &&
        (_searchFocusNode.hasFocus ||
            _searchHistoryPortalController.isShowing)) {
      final localTerminal =
          tryGetLocalTerminalProvider(context, listen: false);
      final terms = localTerminal?.recentTermsForScope(
            LocalTerminalProvider.scopeCatalog,
          ) ??
          const <String>[];
      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          terms.isNotEmpty) {
        if (!_searchHistoryPortalController.isShowing) {
          _showSearchHistoryPopoverIfAvailable(initialHighlightIndex: 0);
        } else {
          setState(() {
            _historyHighlightIndex =
                (_historyHighlightIndex + 1).clamp(0, terms.length - 1);
          });
        }
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          _searchHistoryPortalController.isShowing) {
        setState(() {
          _historyHighlightIndex =
              _historyHighlightIndex <= 0 ? -1 : _historyHighlightIndex - 1;
        });
        return true;
      }
      if ((event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
          _searchHistoryPortalController.isShowing &&
          _historyHighlightIndex >= 0 &&
          _historyHighlightIndex < terms.length) {
        _applyCatalogSearchTerm(terms[_historyHighlightIndex]);
        return true;
      }
    }
    return false;
  }

  void _showSearchHistoryPopoverIfAvailable({int initialHighlightIndex = -1}) {
    if (!mounted || _searchController.text.trim().isNotEmpty) return;
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    if (localTerminal == null) return;
    final terms =
        localTerminal.recentTermsForScope(LocalTerminalProvider.scopeCatalog);
    if (terms.isEmpty) return;
    if (_historyHighlightIndex != initialHighlightIndex) {
      setState(() => _historyHighlightIndex = initialHighlightIndex);
    }
    if (!_searchHistoryPortalController.isShowing) {
      _searchHistoryPortalController.show();
    }
  }

  void _hideSearchHistoryPopover() {
    if (_historyHighlightIndex != -1 && mounted) {
      setState(() => _historyHighlightIndex = -1);
    } else {
      _historyHighlightIndex = -1;
    }
    if (_searchHistoryPortalController.isShowing) {
      _searchHistoryPortalController.hide();
    }
  }

  void _recordCatalogSearchTermIfValid(String term) {
    if (!LocalTerminalProvider.isValidRecentSearchTerm(term)) return;
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    if (localTerminal == null) return;
    unawaited(localTerminal.recordRecentSearchForScope(
      LocalTerminalProvider.scopeCatalog,
      term: term,
    ));
  }

  void _applyCatalogSearchTerm(String term) {
    final clean = term.trim();
    if (clean.isEmpty || !mounted) return;
    _hideSearchHistoryPopover();
    _debounceTimer?.cancel();
    _searchController.text = clean;
    _searchController.selection = TextSelection.collapsed(offset: clean.length);
    _recordCatalogSearchTermIfValid(clean);
    _searchFocusNode.requestFocus();
    unawaited(
      context.read<CatalogProvider>().loadProducts(page: 1, search: clean),
    );
  }

  Widget _buildCatalogSearchHistoryOverlay(
    BuildContext overlayContext,
    OverlayChildLayoutInfo info,
  ) {
    return PosSearchHistoryPopover.buildAnchoredOverlay(
      info: info,
      maxWidth: 560.0,
      maxOverlayHeight: 280.0,
      child: Builder(
        builder: (ctx) {
          final localTerminal = tryGetLocalTerminalProvider(ctx, listen: true);
          final terms = localTerminal?.recentTermsForScope(
                LocalTerminalProvider.scopeCatalog,
              ) ??
              const <String>[];

          if (localTerminal == null || terms.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _hideSearchHistoryPopover();
            });
            return const SizedBox.shrink();
          }

          return PosSearchHistoryPopover(
            containerKey: const ValueKey('catalog_search_history_overlay'),
            terms: terms,
            products: const [],
            showProducts: false,
            highlightedIndex: _historyHighlightIndex,
            tapGroupId: _searchHistoryTapGroupId,
            maxWidth: 560.0,
            maxHeight: 280.0,
            onDismiss: _hideSearchHistoryPopover,
            onClearAll: () {
              unawaited(localTerminal.clearRecentSearchesForScope(
                LocalTerminalProvider.scopeCatalog,
              ));
              _hideSearchHistoryPopover();
              _searchFocusNode.requestFocus();
            },
            onSelectTerm: _applyCatalogSearchTerm,
            onRemoveTerm: (term) {
              final willBeEmpty = terms.length <= 1;
              unawaited(localTerminal.removeRecentTermForScope(
                LocalTerminalProvider.scopeCatalog,
                term,
              ));
              if (willBeEmpty) {
                _hideSearchHistoryPopover();
              } else if (_historyHighlightIndex != -1) {
                setState(() => _historyHighlightIndex = -1);
              }
            },
            onSelectProduct: (_) {},
            onRemoveProduct: (_) {},
          );
        },
      ),
    );
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      _hideSearchHistoryPopover();
    }
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || _searchController.text.trim() != trimmed) return;
      final catalog = context.read<CatalogProvider>();
      await catalog.loadProducts(page: 1, search: value);
      if (!mounted || _searchController.text.trim() != trimmed) return;
      if (trimmed.isNotEmpty && catalog.products.isNotEmpty) {
        _recordCatalogSearchTermIfValid(trimmed);
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
          appBar: GlobalAppBar(
            currentRoute: '/catalog',
            showBackButton: Navigator.of(context).canPop(),
          ),
          body: Column(
            children: [
              // ── Toolbar: Search + Actions ─────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final searchWidget = TapRegion(
                      groupId: _searchHistoryTapGroupId,
                      child: OverlayPortal.overlayChildLayoutBuilder(
                        controller: _searchHistoryPortalController,
                        overlayChildBuilder: _buildCatalogSearchHistoryOverlay,
                        child: ListenableBuilder(
                          listenable: _searchController,
                          builder: (context, _) => TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onTap: () {
                              if (_searchController.text.trim().isEmpty) {
                                _showSearchHistoryPopoverIfAvailable();
                              }
                            },
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
                                  : Builder(
                                      builder: (ctx) {
                                        final localTerminal =
                                            tryGetLocalTerminalProvider(ctx,
                                                listen: true);
                                        final hasTerms = localTerminal != null &&
                                            localTerminal
                                                .recentTermsForScope(
                                                    LocalTerminalProvider
                                                        .scopeCatalog)
                                                .isNotEmpty;
                                        if (!hasTerms) {
                                          return const SizedBox.shrink();
                                        }
                                        return Focus(
                                          canRequestFocus: false,
                                          descendantsAreFocusable: false,
                                          child: Tooltip(
                                            message: 'Búsquedas recientes',
                                            child: IconButton(
                                              key: const ValueKey(
                                                  'catalog_search_history_toggle_btn'),
                                              icon: Icon(
                                                Icons.history_rounded,
                                                size: 20,
                                                color:
                                                    _searchHistoryPortalController
                                                            .isShowing
                                                        ? const Color(0xFF0F766E)
                                                        : Colors
                                                            .blueGrey.shade600,
                                              ),
                                              onPressed: () {
                                                if (_searchHistoryPortalController
                                                    .isShowing) {
                                                  _hideSearchHistoryPopover();
                                                } else {
                                                  _showSearchHistoryPopoverIfAvailable();
                                                }
                                                _searchFocusNode.requestFocus();
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                    );

                    final compactOutlinedStyle = OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    );

                    final activeFiltersCount = provider.safeActiveCatalogFiltersCount;
                    final filtersBarExpanded = _showFiltersBar ||
                        provider.safeFilterCategoryId != null ||
                        provider.safeFilterBrandId != null ||
                        provider.safeFilterActive != null;
                    final hasFiltersHighlight =
                        activeFiltersCount > 0 || filtersBarExpanded;

                    final filtersToggleBtn = Tooltip(
                      message: filtersBarExpanded
                          ? 'Ocultar barra de filtros'
                          : 'Filtrar catálogo por Proveedor, Categoría, Marca o Estado',
                      child: OutlinedButton.icon(
                        key: const ValueKey('catalog_toggle_filters_btn'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 11,
                          ),
                          backgroundColor: hasFiltersHighlight
                              ? AppColors.primarySoft
                              : Colors.white,
                          foregroundColor: hasFiltersHighlight
                              ? AppColors.primaryDark
                              : Colors.blueGrey.shade800,
                          side: BorderSide(
                            color: hasFiltersHighlight
                                ? AppColors.primary
                                : Colors.grey.shade400,
                            width: hasFiltersHighlight ? 1.4 : 1.0,
                          ),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 17),
                        label: Text(
                          activeFiltersCount > 0
                              ? 'Filtros ($activeFiltersCount)'
                              : 'Filtros',
                          style: TextStyle(
                            fontWeight: hasFiltersHighlight
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          final next = !_showFiltersBar;
                          setState(() => _showFiltersBar = next);
                          if (next) {
                            _ensureFiltersMetadataLoaded(provider);
                          }
                        },
                      ),
                    );

                    final searchAndFilters = Row(
                      children: [
                        Expanded(child: searchWidget),
                        const SizedBox(width: 8),
                        filtersToggleBtn,
                      ],
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
                          offset: const Offset(0, 42),
                          elevation: 14,
                          color: GlobalAppBar.kNavDropdownBg,
                          surfaceTintColor: Colors.transparent,
                          shadowColor: const Color(0x73020617),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(
                              color: GlobalAppBar.kNavDropdownBorder,
                              width: 1.5,
                            ),
                          ),
                          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                            _buildDarkPopupOption<String>(
                              value: 'import',
                              icon: Icons.upload_file,
                              label: 'Importar Excel',
                              accent: AppColors.emeraldLight,
                            ),
                            _buildDarkPopupOption<String>(
                              value: 'export',
                              icon: Icons.download,
                              label: 'Exportar Lista',
                              accent: AppColors.tealLight,
                            ),
                            _buildDarkPopupOption<String>(
                              value: 'quick_grid',
                              icon: Icons.grid_on_rounded,
                              label: 'Carga en Grilla',
                              accent: AppColors.indigoLight,
                            ),
                          ],
                          onSelected: (String result) async {
                            if (result == 'import') {
                              final auth = await AdminPinDialog.verify(context, action: 'Importar Catálogo', permissionKey: 'manage_catalog');
                              if (auth && context.mounted) {
                                showDialog(
                                  context: context,
                                  builder: (_) => CatalogImportDialog(
                                    initialSupplierId: provider.safeFilterSupplierId,
                                    initialSupplierName: provider.safeFilterSupplierName,
                                  ),
                                );
                              }
                            } else if (result == 'export') {
                              final auth = await AdminPinDialog.verify(context, action: 'Exportar Catálogo', permissionKey: 'manage_catalog');
                              if (auth && context.mounted) {
                                provider.exportCatalogToExcel(context);
                              }
                            } else if (result == 'quick_grid') {
                              final pin = await AdminPinDialog.verifyAndGetPin(
                                context,
                                action: 'Carga Rápida en Grilla',
                                permissionKey: 'manage_catalog',
                              );
                              if (pin != null && context.mounted) {
                                _showSupplierQuickGridDialog(
                                  context,
                                  provider,
                                  alreadyAuthorized: true,
                                  authorizedAdminPin:
                                      pin == 'ALREADY_AUTHORIZED' ? null : pin,
                                );
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
                          searchAndFilters,
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
                          flex: 5,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: searchAndFilters,
                          ),
                        ),
                        const SizedBox(width: 14),
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
              // ── Panel plegable de Filtros (Proveedor / Categoría / Marca / Estado) ──
              if (_showFiltersBar ||
                  provider.safeFilterCategoryId != null ||
                  provider.safeFilterBrandId != null ||
                  provider.safeFilterActive != null)
                _buildFiltersBar(provider),
              // ── Filtro Activo por Proveedor ────────────────────────────────
              if (provider.safeFilterSupplierId != null)
                _buildSupplierFilterBanner(provider),
              // ── Barra de acciones en lote (encima del checkbox "seleccionar todos") ──
              if (_selectedProducts.isNotEmpty) _buildBulkActionsBar(provider),
              // ── Product Table ───────────────────────────────────────────────
              Expanded(
                child: Builder(
                  builder: (context) {
                    final isNeedsReviewFilter = provider.sortBy == 'needs_catalog_review';
                    final hasActiveFilters = provider.safeActiveCatalogFiltersCount > 0;
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
                            ] else if (hasActiveFilters) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (provider.safeFilterSupplierId != null)
                                    FilledButton.tonalIcon(
                                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                                      label: const Text('Cambiar proveedor'),
                                      onPressed: () => _openQuickSupplierSwitcher(provider),
                                    ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                                    label: const Text('Quitar filtros'),
                                    onPressed: () {
                                      setState(() => _selectedProducts.clear());
                                      provider.safeClearAllCatalogFilters();
                                    },
                                  ),
                                ],
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
            offset: const Offset(0, 46),
            elevation: 14,
            color: GlobalAppBar.kNavDropdownBg,
            surfaceTintColor: Colors.transparent,
            shadowColor: const Color(0x73020617),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(
                color: GlobalAppBar.kNavDropdownBorder,
                width: 1.5,
              ),
            ),
            onSelected: (val) {
              switch (val) {
                case 1: _bulkUpdateCategory(provider); break;
                case 2: _bulkToggleActive(provider); break;
                case 3:
                  AdminPinDialog.verify(context, action: 'Aumento Masivo Lote', permissionKey: 'manage_catalog').then((auth) {
                    if (auth && context.mounted) {
                      showDialog<bool>(
                        context: context,
                        builder: (_) => BulkPriceUpdateDialog(
                          provider: provider,
                          targetProductIds: _selectedProducts.keys.toList(),
                        ),
                      ).then((updated) {
                        if (updated == true && mounted) {
                          setState(() => _selectedProducts.clear());
                        }
                      });
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
              _buildDarkPopupOption<int>(
                value: 1,
                icon: Icons.folder_outlined,
                label: 'Asignar Categoría',
                accent: AppColors.amberLight,
              ),
              _buildDarkPopupOption<int>(
                value: 8,
                icon: Icons.branding_watermark_outlined,
                label: 'Asignar Marca',
                accent: AppColors.indigoLight,
              ),
              _buildDarkPopupOption<int>(
                value: 7,
                icon: Icons.local_shipping_outlined,
                label: 'Asignar Proveedor',
                accent: AppColors.orangeLight,
              ),
              _buildDarkPopupOption<int>(
                value: 12,
                icon: Icons.request_quote_outlined,
                label: 'Generar Presupuesto',
                accent: AppColors.tealLight,
              ),
              _buildDarkPopupOption<int>(
                value: 2,
                icon: Icons.power_settings_new,
                label: 'Cambiar Estado',
                accent: AppColors.emeraldLight,
              ),
              _buildDarkPopupOption<int>(
                value: 3,
                icon: Icons.trending_up,
                label: 'Actualizar Precios',
                accent: AppColors.amberLight,
              ),
              _buildDarkPopupOption<int>(
                value: 4,
                icon: Icons.print_outlined,
                label: 'Imprimir Etiquetas',
                accent: const Color(0xFF60A5FA),
              ),
              const PopupMenuItem<int>(
                enabled: false,
                height: 10,
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFF263859),
                ),
              ),
              _buildDarkPopupOption<int>(
                value: 5,
                icon: Icons.delete_outline,
                label: 'Eliminar Todo',
                accent: const Color(0xFFFB7185),
                isDanger: true,
              ),
              const PopupMenuItem<int>(
                enabled: false,
                height: 10,
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFF263859),
                ),
              ),
              _buildDarkPopupOption<int>(
                value: 6,
                icon: Icons.deselect,
                label: 'Cancelar Selección',
                accent: AppColors.darkSubtitle,
              ),
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

  void _ensureFiltersMetadataLoaded(CatalogProvider provider) {
    if (provider.categories.isEmpty || provider.brands.isEmpty) {
      provider.loadMetadata();
    }
    final canSeeSupplier =
        context.read<SettingsProvider?>()?.features.suppliers ?? false;
    if (canSeeSupplier) {
      try {
        final supProv = context.read<SupplierProvider?>();
        if (supProv != null &&
            supProv.suppliers.isEmpty &&
            !supProv.isLoading) {
          supProv.fetchSuppliers();
        }
      } catch (_) {}
    }
  }

  Future<void> _openQuickSupplierSwitcher(CatalogProvider provider) async {
    SupplierProvider? supplierProv;
    try {
      supplierProv = context.read<SupplierProvider?>();
    } catch (_) {}
    if (supplierProv == null) return;

    if (supplierProv.suppliers.isEmpty && !supplierProv.isLoading) {
      await supplierProv.fetchSuppliers();
    }
    if (!mounted) return;

    final result = await showDialog<int?>(
      context: context,
      builder: (_) => _QuickSupplierPickerDialog(
        currentSupplierId: provider.safeFilterSupplierId,
      ),
    );
    if (!mounted || result == null) return;

    if (result == -1) {
      setState(() => _selectedProducts.clear());
      await provider.safeSetSupplierFilter(null);
      return;
    }

    final matched =
        supplierProv.suppliers.where((s) => s.id == result).firstOrNull;
    setState(() => _selectedProducts.clear());
    await provider.safeSetSupplierFilter(
      result,
      supplierName: matched?.name,
    );
  }

  Widget _buildFiltersBar(CatalogProvider provider) {
    final sp = context.watch<SettingsProvider?>();
    final canSeeSupplier = sp?.features.suppliers ?? false;
    SupplierProvider? supplierProv;
    if (canSeeSupplier) {
      try {
        supplierProv = context.watch<SupplierProvider?>();
      } catch (_) {}
    }

    final sortedSuppliers = sortByAlphabeticalName(
      supplierProv?.suppliers ?? const <Supplier>[],
      (s) => s.name,
    );
    final sortedCategories = sortByAlphabeticalName(
      provider.categories,
      (c) => c.name,
    );
    final sortedBrands = sortByAlphabeticalName(
      provider.brands,
      (b) => b.name,
    );

    final activeSupplierId = provider.safeFilterSupplierId;
    final activeCategoryId = provider.safeFilterCategoryId;
    final activeBrandId = provider.safeFilterBrandId;
    final activeStatus = provider.safeFilterActive;
    final activeCount = provider.safeActiveCatalogFiltersCount;

    final hasMatchingSupplier = activeSupplierId != null &&
        sortedSuppliers.any((s) => s.id == activeSupplierId);
    final fallbackSupName = provider.safeFilterSupplierName;
    final showFallbackSupplier = !hasMatchingSupplier &&
        activeSupplierId != null &&
        fallbackSupName != null &&
        fallbackSupName.isNotEmpty;

    Widget buildSupplierFilter() => SearchableSelectField<int?>(
          key: const ValueKey('catalog_filter_supplier_field'),
          value: (hasMatchingSupplier || showFallbackSupplier)
              ? activeSupplierId
              : null,
          clearValue: null,
          isDense: true,
          labelText: 'Proveedor',
          dialogTitle: 'Filtrar por Proveedor',
          searchHintText: 'Buscar proveedor o CUIT...',
          prefixIcon: Icons.local_shipping_outlined,
          border: const OutlineInputBorder(),
          options: [
            const SearchableSelectOption<int?>(
              value: null,
              label: '— Todos los proveedores —',
              isResetOption: true,
            ),
            if (showFallbackSupplier)
              SearchableSelectOption<int?>(
                value: activeSupplierId,
                label: fallbackSupName,
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
          onChanged: (val) {
            setState(() => _selectedProducts.clear());
            if (val == null) {
              provider.safeSetSupplierFilter(null);
            } else {
              final matched =
                  sortedSuppliers.where((s) => s.id == val).firstOrNull;
              provider.safeSetSupplierFilter(
                val,
                supplierName: matched?.name ?? fallbackSupName,
              );
            }
          },
        );

    Widget buildCategoryFilter() => SearchableSelectField<int?>(
          key: const ValueKey('catalog_filter_category_field'),
          value: sortedCategories.any((c) => c.id == activeCategoryId)
              ? activeCategoryId
              : null,
          clearValue: null,
          isDense: true,
          labelText: 'Categoría',
          dialogTitle: 'Filtrar por Categoría',
          searchHintText: 'Buscar categoría o rubro...',
          prefixIcon: Icons.category_outlined,
          border: const OutlineInputBorder(),
          options: [
            const SearchableSelectOption<int?>(
              value: null,
              label: '— Todas las categorías —',
              isResetOption: true,
            ),
            ...sortedCategories.map((c) {
              final rId = c.rubroId ?? c.rubro?.id;
              final rubroName = (rId != null
                      ? provider.rubros
                          .where((r) => r.id == rId)
                          .firstOrNull
                          ?.name
                      : null) ??
                  c.rubro?.name;
              final hasRubro =
                  rubroName != null && rubroName.trim().isNotEmpty;
              return SearchableSelectOption<int?>(
                value: c.id,
                label: c.name,
                subtitle: hasRubro ? 'Rubro: $rubroName' : null,
                searchKeywords: hasRubro ? [rubroName] : const [],
              );
            }),
          ],
          onChanged: (val) {
            setState(() => _selectedProducts.clear());
            provider.safeSetCategoryFilter(val);
          },
        );

    Widget buildBrandFilter() => SearchableSelectField<int?>(
          key: const ValueKey('catalog_filter_brand_field'),
          value: sortedBrands.any((b) => b.id == activeBrandId)
              ? activeBrandId
              : null,
          clearValue: null,
          isDense: true,
          labelText: 'Marca',
          dialogTitle: 'Filtrar por Marca',
          searchHintText: 'Buscar marca...',
          prefixIcon: Icons.branding_watermark_outlined,
          border: const OutlineInputBorder(),
          options: [
            const SearchableSelectOption<int?>(
              value: null,
              label: '— Todas las marcas —',
              isResetOption: true,
            ),
            ...sortedBrands.map(
              (b) => SearchableSelectOption<int?>(value: b.id, label: b.name),
            ),
          ],
          onChanged: (val) {
            setState(() => _selectedProducts.clear());
            provider.safeSetBrandFilter(val);
          },
        );

    Widget buildStatusFilter() => DropdownButtonFormField<bool?>(
          key: const ValueKey('catalog_filter_active_dropdown'),
          isExpanded: true,
          initialValue: activeStatus,
          decoration: const InputDecoration(
            labelText: 'Estado POS',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem<bool?>(value: null, child: Text('Todos')),
            DropdownMenuItem<bool?>(value: true, child: Text('Activos')),
            DropdownMenuItem<bool?>(value: false, child: Text('Inactivos')),
          ],
          onChanged: (val) {
            setState(() => _selectedProducts.clear());
            provider.safeSetActiveFilter(val);
          },
        );

    Widget buildClearBtn() => TextButton.icon(
          key: const ValueKey('catalog_clear_all_filters_btn'),
          onPressed: activeCount == 0
              ? null
              : () {
                  setState(() => _selectedProducts.clear());
                  provider.safeClearAllCatalogFilters();
                },
          icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
          label: const Text('Limpiar'),
        );

    return Container(
      key: const ValueKey('catalog_filters_bar'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0)),
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 880) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (canSeeSupplier && supplierProv != null) ...[
                  Expanded(flex: 3, child: buildSupplierFilter()),
                  const SizedBox(width: 10),
                ],
                Expanded(flex: 2, child: buildCategoryFilter()),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: buildBrandFilter()),
                const SizedBox(width: 10),
                SizedBox(width: 142, child: buildStatusFilter()),
                const SizedBox(width: 6),
                buildClearBtn(),
              ],
            );
          }

          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canSeeSupplier && supplierProv != null)
                SizedBox(
                  width: math.min(250.0, constraints.maxWidth),
                  child: buildSupplierFilter(),
                ),
              SizedBox(
                width: math.min(220.0, constraints.maxWidth),
                child: buildCategoryFilter(),
              ),
              SizedBox(
                width: math.min(200.0, constraints.maxWidth),
                child: buildBrandFilter(),
              ),
              SizedBox(
                width: math.min(142.0, constraints.maxWidth),
                child: buildStatusFilter(),
              ),
              buildClearBtn(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSupplierFilterBanner(CatalogProvider provider) {
    final supplierName = provider.safeFilterSupplierName ??
        'Proveedor #${provider.safeFilterSupplierId}';
    final isFallback185 = provider.safeSupplierFilterFallbackActive;
    final canPopBack = Navigator.of(context).canPop();
    final canSwitchSupplier =
        (context.watch<SettingsProvider?>()?.features.suppliers ?? false) &&
            (() {
              try {
                return context.read<SupplierProvider?>() != null;
              } catch (_) {
                return false;
              }
            })();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.navyStart, AppColors.navyEnd],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.teal, width: 2),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.tealLight.withValues(alpha: 0.45),
                  ),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: AppColors.tealLight,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Mostrando catálogo de proveedor:',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkSubtitle,
                      ),
                    ),
                    if (canSwitchSupplier)
                      Tooltip(
                        message: 'Clic para cambiar de proveedor sin volver atrás',
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            key: const ValueKey(
                                'catalog_banner_switch_supplier_btn'),
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _openQuickSupplierSwitcher(provider),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.tealLight
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 280),
                                    child: Text(
                                      supplierName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: AppColors.tealLight,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        supplierName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    if (isFallback185)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: AppColors.amberLight.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text(
                          'Compatibilidad v1.8.5: filtrado local',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.amberLight,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                key: const ValueKey('catalog_new_for_supplier_btn'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Nuevo de este Proveedor'),
                onPressed: () async {
                  final auth = await AdminPinDialog.verify(
                    context,
                    action: 'Crear Nuevo Producto',
                    permissionKey: 'manage_catalog',
                  );
                  if (auth && mounted) {
                    _showProductForm(context, provider);
                  }
                },
              ),
              OutlinedButton.icon(
                key: const ValueKey('catalog_supplier_quick_grid_btn'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.tealLight,
                  side: BorderSide(
                    color: AppColors.tealLight.withValues(alpha: 0.5),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                ),
                icon: const Icon(Icons.grid_on_rounded, size: 16),
                label: const Text('Carga en Grilla'),
                onPressed: () async {
                  final pin = await AdminPinDialog.verifyAndGetPin(
                    context,
                    action: 'Carga Rápida en Grilla',
                    permissionKey: 'manage_catalog',
                  );
                  if (pin != null && mounted) {
                    _showSupplierQuickGridDialog(
                      context,
                      provider,
                      alreadyAuthorized: true,
                      authorizedAdminPin:
                          pin == 'ALREADY_AUTHORIZED' ? null : pin,
                    );
                  }
                },
              ),
              if (canPopBack)
                OutlinedButton.icon(
                  key: const ValueKey('catalog_back_to_suppliers_btn'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Volver a Proveedores'),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              OutlinedButton.icon(
                key: const ValueKey('catalog_clear_supplier_filter_btn'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.darkSubtitle,
                  side: BorderSide(
                    color: AppColors.darkSubtitle.withValues(alpha: 0.45),
                  ),
                ),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Quitar filtro'),
                onPressed: () {
                  setState(() => _selectedProducts.clear());
                  provider.setSupplierFilter(null);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductsTable(List<Product> products, CatalogProvider provider) {
    final sp = context.watch<SettingsProvider?>();
    final profile = sp?.safeVerticalProfile ??
        BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
    final canSeeSupplier = sp?.features.suppliers ?? false;
    final canUseBatches = sp == null
        ? true
        : (sp.features.batchExpiration || sp.features.production);

    // Anchos fijos calibrados para columnas cortas/fechas y flex equilibrado para texto/precios
    const double wCheck = 38;
    const double wFoto = 46;
    const double wId = 48;
    const double wBal = 58;
    const double wUnidad = 92;
    const double wActivo = 70;
    const double wVto = 116;
    const double wAcciones = 44;

    const int fNombre = 5;
    const int fBarcode = 3;
    const int fInterno = 2;
    const int fSupplierSku = 2;
    const int fSpec = 2;
    const int fStorageLoc = 2;
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
              if (profile.showSupplierSkuColumnInCatalog)
                sortHeader(
                  flex: fSupplierSku,
                  label: 'Cód. Prov.',
                  sortKey: 'supplier_sku',
                  tooltip: 'Código de artículo del proveedor',
                ),
              if (profile.showSpecColumnInCatalog)
                sortHeader(
                  flex: fSpec,
                  label: profile.specColumnHeader,
                  sortKey: 'technical_spec',
                  tooltip: profile.specFieldLabel,
                ),
              sortHeader(flex: fCat, label: 'Categoría', sortKey: 'category_id'),
              sortHeader(flex: fBrand, label: 'Marca', sortKey: 'brand_id'),
              if (canSeeSupplier) sortHeader(flex: fProv, label: 'Proveedor', sortKey: 'supplier_id'),
              if (profile.showLocationColumnInCatalog)
                sortHeader(
                  flex: fStorageLoc,
                  label: 'Ubicación',
                  sortKey: 'storage_location',
                  tooltip: profile.locationFieldLabel,
                ),
              sortHeader(flex: fCosto, label: 'Costo', sortKey: 'cost_price'),
              sortHeader(flex: fVenta, label: 'Venta', sortKey: 'selling_price'),
              sortHeader(flex: fStock, label: 'Stock', sortKey: 'stock'),
              if (profile.showUnitColumnInCatalog)
                sortHeader(
                  width: wUnidad,
                  label: 'Unidad',
                  sortKey: 'unit_type',
                  tooltip: 'Unidad de venta y fraccionamiento',
                )
              else if (profile.showBalColumnInCatalog)
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
              const SizedBox(
                width: wAcciones,
                child: Tooltip(
                  message: 'Acciones (clic en ⋮ o clic derecho en cualquier fila)',
                  child: Center(
                    child: Icon(Icons.more_vert_rounded, size: 18, color: Colors.blueGrey),
                  ),
                ),
              ),
            ],
          ),
        );

    Widget cellTooltip({
      required String? message,
      required Widget child,
    }) {
      final clean = message?.trim() ?? '';
      if (clean.isEmpty) return child;
      return Tooltip(
        message: clean,
        waitDuration: const Duration(milliseconds: 350),
        showDuration: const Duration(seconds: 4),
        child: child,
      );
    }

    Widget productRow(Product p, int index) {
      final isContextActive = _contextMenuProductId == p.id;
      final isSelected = _selectedProducts.containsKey(p.id);
      final nameTooltip = (p.technicalSpec != null && p.technicalSpec!.trim().isNotEmpty)
          ? '${p.name} • ${p.technicalSpec!.trim()}'
          : p.name;
      final catRubroId = p.category?.rubroId ?? p.category?.rubro?.id;
      final catRubroName = (catRubroId != null
              ? provider.rubros.where((r) => r.id == catRubroId).firstOrNull?.name
              : null) ??
          p.category?.rubro?.name;
      final categoryTooltip = p.category == null
          ? null
          : (catRubroName != null && catRubroName.trim().isNotEmpty
              ? '${p.category!.name} • Rubro: ${catRubroName.trim()}'
              : p.category!.name);
      final supplierCuit = p.supplier?.cuit?.trim() ?? '';
      final supplierTooltip = p.supplier == null
          ? null
          : (supplierCuit.isNotEmpty
              ? '${p.supplier!.name} • CUIT: $supplierCuit'
              : p.supplier!.name);
      final hasSupplierSku =
          p.supplierSku != null && p.supplierSku!.trim().isNotEmpty;
      final hasStorageLoc =
          p.storageLocation != null && p.storageLocation!.trim().isNotEmpty;
      return Material(
        color: isContextActive
            ? Colors.indigo.shade50
            : (isSelected
                ? Colors.blue.shade50
                : (index.isOdd ? Colors.grey.shade50 : Colors.white)),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) =>
              _showProductContextMenu(context, details.globalPosition, provider, p),
          onLongPressStart: (details) =>
              _showProductContextMenu(context, details.globalPosition, provider, p),
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
                      child: cellTooltip(
                        message: nameTooltip,
                        child: Text(p.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                    ),
                    if (!profile.showSpecColumnInCatalog &&
                        p.technicalSpec != null &&
                        p.technicalSpec!.trim().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blueGrey.shade200),
                        ),
                        child: Text(
                          p.technicalSpec!.trim(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey.shade800,
                          ),
                        ),
                      ),
                    ],
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
              if (profile.showSupplierSkuColumnInCatalog)
                tableCell(
                  flex: fSupplierSku,
                  child: hasSupplierSku
                      ? cellTooltip(
                          message: 'Cód. Prov.: ${p.supplierSku!.trim()}',
                          child: Text(
                            p.supplierSku!.trim(),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.brown.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ),
              if (profile.showSpecColumnInCatalog)
                tableCell(
                  flex: fSpec,
                  child: (p.technicalSpec != null && p.technicalSpec!.trim().isNotEmpty)
                      ? cellTooltip(
                          message: p.technicalSpec!.trim(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade50,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: Colors.blueGrey.shade200),
                            ),
                            child: Text(
                              p.technicalSpec!.trim(),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey.shade800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                      : Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ),
              tableCell(
                flex: fCat,
                child: p.category != null
                    ? cellTooltip(
                        message: categoryTooltip,
                        child: Text(p.category!.name, overflow: TextOverflow.ellipsis),
                      )
                    : Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              ),
              tableCell(
                flex: fBrand,
                child: p.brand != null
                    ? cellTooltip(
                        message: p.brand!.name,
                        child: Text(p.brand!.name, overflow: TextOverflow.ellipsis),
                      )
                    : Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              ),
              if (canSeeSupplier)
                tableCell(
                  flex: fProv,
                  child: p.supplier != null
                      ? cellTooltip(
                          message: supplierTooltip,
                          child: Text(p.supplier!.name, overflow: TextOverflow.ellipsis),
                        )
                      : Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ),
              if (profile.showLocationColumnInCatalog)
                tableCell(
                  flex: fStorageLoc,
                  child: hasStorageLoc
                      ? cellTooltip(
                          message: p.storageLocation!.trim(),
                          child: Text(
                            p.storageLocation!.trim(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF0F766E),
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ),
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
                          unitSuffix: p.unitShortLabel,
                          weightUnit: p.unitShortLabel,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              if (profile.showUnitColumnInCatalog)
                tableCell(
                  width: wUnidad,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.isSoldByWeight
                            ? Colors.deepPurple.shade50
                            : Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: p.isSoldByWeight
                              ? Colors.deepPurple.shade200
                              : Colors.blueGrey.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p.unitShortLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: p.isSoldByWeight
                                  ? Colors.deepPurple.shade800
                                  : Colors.blueGrey.shade800,
                            ),
                          ),
                          if (p.calcConfig != null && p.calcConfig!.isNotEmpty) ...[
                            const SizedBox(width: 3),
                            Tooltip(
                              message: 'Calculadora F7 configurada',
                              child: Icon(
                                Icons.straighten_rounded,
                                size: 12,
                                color: Colors.teal.shade700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              else if (profile.showBalColumnInCatalog)
                tableCell(width: wBal, child: Align(alignment: Alignment.centerLeft, child: Icon(p.isSoldByWeight ? Icons.scale : Icons.inventory_2, size: 18, color: p.isSoldByWeight ? Colors.deepPurple : Colors.blueGrey))),
              tableCell(width: wActivo, child: Align(alignment: Alignment.centerLeft, child: Icon(p.active ? Icons.check_circle : Icons.cancel, color: p.active ? Colors.green : Colors.red, size: 20))),
              if (canUseBatches) tableCell(width: wVto, child: _buildExpiryCell(p, provider)),
              tableCell(
                width: wAcciones,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Center(
                  child: Builder(
                    builder: (btnCtx) => IconButton(
                      key: ValueKey('catalog_row_actions_${p.id}'),
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 19,
                        color: isContextActive
                            ? Colors.indigo.shade700
                            : Colors.blueGrey.shade600,
                      ),
                      tooltip: 'Más acciones (o clic derecho)',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      splashRadius: 18,
                      onPressed: () {
                        final box = btnCtx.findRenderObject() as RenderBox?;
                        final anchor = box != null
                            ? box.localToGlobal(Offset(box.size.width, box.size.height))
                            : Offset.zero;
                        _showProductContextMenu(context, anchor, provider, p);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      );
    }

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

  void _showProductForm(
    BuildContext ctx,
    CatalogProvider provider, {
    Product? product,
    Product? duplicateFrom,
  }) {
    final useActiveSupplier = product == null && duplicateFrom == null;
    showDialog<Product>(
      context: ctx,
      barrierDismissible: true,
      builder: (_) => ProductFormDialog(
        provider: provider,
        product: product,
        duplicateFrom: duplicateFrom,
        initialSupplierId:
            useActiveSupplier ? provider.safeFilterSupplierId : null,
        initialSupplierName:
            useActiveSupplier ? provider.safeFilterSupplierName : null,
      ),
    ).then((_) {
      if (mounted) {
        context.read<InventoryAlertsProvider>().fetchAlerts();
      }
    });
  }

  void _showSupplierQuickGridDialog(
    BuildContext ctx,
    CatalogProvider provider, {
    bool alreadyAuthorized = false,
    String? authorizedAdminPin,
  }) {
    showDialog<int>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => SupplierQuickGridDialog(
        provider: provider,
        initialSupplierId: provider.safeFilterSupplierId,
        initialSupplierName: provider.safeFilterSupplierName,
        alreadyAuthorized: alreadyAuthorized,
        authorizedAdminPin: authorizedAdminPin,
      ),
    ).then((createdCount) {
      if (mounted && (createdCount ?? 0) > 0) {
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

    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Eliminar Lote',
      message:
          '¿Está seguro que desea eliminar DEFINITIVAMENTE los ${_selectedProducts.length} productos seleccionados?\nEsta acción no se puede deshacer.',
      confirmLabel: 'Eliminar Todo',
      cancelLabel: 'Cancelar',
      icon: Icons.delete_forever,
      isDestructive: true,
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

    int? newCategory = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        int? selected = defaultCat;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> createNewCategory({String? initialName}) async {
              final createdId = await CatalogQuickCreateDialogs.showCreateCategory(
                ctx,
                initialName: initialName,
                subtitle: 'Creá una categoría rápida para asignarla al lote',
              );
              if (createdId != null && ctx.mounted) {
                setDialogState(() => selected = createdId);
              }
            }

            return Consumer<CatalogProvider>(
              builder: (_, liveProvider, __) {
                final sortedCategories = sortByAlphabeticalName(
                  liveProvider.categories,
                  (c) => c.name,
                );
                return AppModalShell(
                  title: 'Asignar Categoría',
                  subtitle: 'Aplicá o quitá la categoría a los productos seleccionados',
                  icon: Icons.category_outlined,
                  accent: AppModalAccent.orange,
                  compact: true,
                  maxWidth: 480,
                  useAlertDialogWrapper: true,
                  onClose: () => Navigator.pop(ctx),
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SearchableSelectField<int?>(
                          key: const ValueKey('bulk_category_select_field'),
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
                                      ? liveProvider.rubros.where((r) => r.id == rId).firstOrNull?.name
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
                          onCreateNew: (query) => createNewCategory(initialName: query),
                          createLabelBuilder: (query) => 'Crear categoría "${query.trim()}"',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Crear nueva categoría',
                        child: IconButton.filledTonal(
                          key: const ValueKey('bulk_create_category_btn'),
                          icon: const Icon(Icons.add),
                          onPressed: () => createNewCategory(),
                        ),
                      ),
                    ],
                  ),
                  footerActions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
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
                );
              },
            );
          },
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

  Future<void> _bulkGenerateQuote() => _generateQuoteForProducts(
        _selectedProducts.values.toList(),
        clearSelection: true,
      );

  Future<void> _generateQuoteForProducts(
    List<Product> products, {
    bool clearSelection = false,
  }) async {
    final hasQuotes = context.read<SettingsProvider>().features.quotes;
    if (!hasQuotes) {
      PlanUpgradeDialog.show(
        context,
        featureName: 'Generador de Presupuestos',
        description: 'La creación de presupuestos es exclusiva del Plan Premium.',
      );
      return;
    }

    if (products.isEmpty) return;

    QuoteProvider? quoteProv;
    try {
      quoteProv = Provider.of<QuoteProvider?>(context, listen: false);
      if (quoteProv != null) {
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

    if (mounted && quoteProv != null) {
      final previousCreatedQuote = quoteProv.lastCreatedQuote;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QuoteScreen()),
      );
      final emittedNewQuote = quoteProv.lastCreatedQuote != null &&
          !identical(quoteProv.lastCreatedQuote, previousCreatedQuote);
      if (clearSelection && emittedNewQuote && mounted) {
        setState(() => _selectedProducts.clear());
      }
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

    int? newBrand = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        int? selected = defaultBrand;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> createNewBrand({String? initialName}) async {
              final createdId = await CatalogQuickCreateDialogs.showCreateBrand(
                ctx,
                initialName: initialName,
                subtitle: 'Creá una marca rápida para asignarla al lote',
              );
              if (createdId != null && ctx.mounted) {
                setDialogState(() => selected = createdId);
              }
            }

            return Consumer<CatalogProvider>(
              builder: (_, liveProvider, __) {
                final sortedBrands = sortByAlphabeticalName(
                  liveProvider.brands,
                  (b) => b.name,
                );
                return AppModalShell(
                  title: 'Asignar Marca en Lote',
                  subtitle: 'Aplicá o quitá la marca a los productos seleccionados',
                  icon: Icons.branding_watermark_outlined,
                  accent: AppModalAccent.indigo,
                  compact: true,
                  maxWidth: 480,
                  useAlertDialogWrapper: true,
                  onClose: () => Navigator.pop(ctx),
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SearchableSelectField<int?>(
                          key: const ValueKey('bulk_brand_select_field'),
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
                          onCreateNew: (query) => createNewBrand(initialName: query),
                          createLabelBuilder: (query) => 'Crear marca "${query.trim()}"',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Crear nueva marca',
                        child: IconButton.filledTonal(
                          key: const ValueKey('bulk_create_brand_btn'),
                          icon: const Icon(Icons.add),
                          onPressed: () => createNewBrand(),
                        ),
                      ),
                    ],
                  ),
                  footerActions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
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
                );
              },
            );
          },
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

    int? newSupplier = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        int? selected = defaultSupplier;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> createNewSupplier({String? initialQuery}) async {
              final createdId = await CatalogQuickCreateDialogs.showCreateSupplier(
                ctx,
                initialQuery: initialQuery,
              );
              if (createdId != null && ctx.mounted) {
                setDialogState(() => selected = createdId);
              }
            }

            return Consumer<SupplierProvider>(
              builder: (_, liveSupplierProv, __) {
                final sortedSuppliers = sortByAlphabeticalName(
                  liveSupplierProv.suppliers,
                  (s) => s.name,
                );
                return AppModalShell(
                  title: 'Asignar Proveedor',
                  subtitle: 'Asociá un proveedor a los productos seleccionados',
                  icon: Icons.local_shipping_outlined,
                  accent: AppModalAccent.indigo,
                  compact: true,
                  maxWidth: 480,
                  useAlertDialogWrapper: true,
                  onClose: () => Navigator.pop(ctx),
                  body: liveSupplierProv.isLoading
                      ? const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()))
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: SearchableSelectField<int?>(
                                key: const ValueKey('bulk_supplier_select_field'),
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
                                onCreateNew: (query) => createNewSupplier(initialQuery: query),
                                createLabelBuilder: (query) => 'Crear proveedor "${query.trim()}"',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Crear nuevo proveedor',
                              child: IconButton.filledTonal(
                                key: const ValueKey('bulk_create_supplier_btn'),
                                icon: const Icon(Icons.add),
                                onPressed: () => createNewSupplier(),
                              ),
                            ),
                          ],
                        ),
                  footerActions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
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
                );
              },
            );
          },
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
      builder: (ctx) => AppModalShell(
        title: 'Cambiar Estado (Activo/Inactivo)',
        subtitle: 'Aplicá el estado en POS a los productos seleccionados',
        icon: Icons.published_with_changes_outlined,
        accent: AppModalAccent.blue,
        compact: true,
        maxWidth: 520,
        onClose: () => Navigator.pop(ctx, null),
        body: const Text(
          '¿Qué estado desea aplicar a los productos seleccionados?',
          style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
        ),
        footerActions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
          FilledButton.icon(
            icon: const Icon(Icons.cancel_outlined),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            label: const Text('Dar de Baja (Desactivar)'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
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
    final confirmed = await AppConfirmDialog.show(
      ctx,
      title: 'Confirmar Eliminación',
      message: '¿Seguro de eliminar el producto "${p.name}"?\nEsta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
      cancelLabel: 'Cancelar',
      icon: Icons.delete_outline,
      isDestructive: true,
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

  bool _hasValidProductImageUrl(String? rawUrl) {
    final resolved = resolveImageUrl(rawUrl);
    if (resolved == null || resolved.trim().isEmpty) return false;
    final uri = Uri.tryParse(resolved.trim());
    return uri != null &&
        uri.hasScheme &&
        uri.hasAuthority &&
        uri.host.isNotEmpty;
  }

  PopupMenuItem<T> _buildDarkPopupOption<T>({
    required T value,
    required IconData icon,
    required String label,
    required Color accent,
    bool isDanger = false,
  }) {
    return PopupMenuItem<T>(
      value: value,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: accent.withValues(alpha: 0.32),
              ),
            ),
            child: Icon(icon, size: 16.5, color: accent),
          ),
          const SizedBox(width: 11),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isDanger ? FontWeight.w700 : FontWeight.w500,
                color: isDanger
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFFF1F5F9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildContextMenuItem({
    required String value,
    required IconData icon,
    required Color color,
    required String label,
    Color? textColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuickPriceDialog(
    BuildContext ctx,
    CatalogProvider provider,
    Product p,
  ) async {
    await showDialog<Product>(
      context: ctx,
      barrierDismissible: true,
      builder: (_) => _QuickPriceEditDialog(provider: provider, product: p),
    );
  }

  Future<void> _showProductContextMenu(
    BuildContext ctx,
    Offset globalPosition,
    CatalogProvider provider,
    Product p,
  ) async {
    final RenderBox? overlay =
        Overlay.of(ctx).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final sp = ctx.read<SettingsProvider?>();
    final canSeeSupplier = sp?.features.suppliers ?? false;
    final canUseQuotes = sp?.features.quotes ?? false;
    final canUseBatches = sp == null
        ? true
        : (sp.features.batchExpiration || sp.features.production);
    final canUseProduction = sp?.features.production ?? false;
    final isBulkContext =
        _selectedProducts.length > 1 && _selectedProducts.containsKey(p.id);
    final resolvedImgUrl =
        _hasValidProductImageUrl(p.imageUrl) ? resolveImageUrl(p.imageUrl) : null;

    setState(() => _contextMenuProductId = p.id);

    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    final String? selectedAction;
    try {
      selectedAction = await showMenu<String>(
        context: ctx,
        position: position,
        elevation: 8,
        constraints: const BoxConstraints(minWidth: 235, maxWidth: 310),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        items: isBulkContext
            ? <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  enabled: false,
                  height: 40,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_selectedProducts.length} productos seleccionados',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      Text(
                        'Acciones rápidas sobre el lote',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(height: 6),
                _buildContextMenuItem(
                  value: 'bulk_category',
                  icon: Icons.folder_outlined,
                  color: Colors.orange,
                  label: 'Asignar Categoría',
                ),
                _buildContextMenuItem(
                  value: 'bulk_brand',
                  icon: Icons.branding_watermark_outlined,
                  color: Colors.indigo,
                  label: 'Asignar Marca',
                ),
                if (canSeeSupplier)
                  _buildContextMenuItem(
                    value: 'bulk_supplier',
                    icon: Icons.local_shipping_outlined,
                    color: Colors.brown,
                    label: 'Asignar Proveedor',
                  ),
                _buildContextMenuItem(
                  value: 'bulk_prices',
                  icon: Icons.trending_up,
                  color: Colors.deepOrange,
                  label: 'Actualizar Precios',
                ),
                if (canUseQuotes)
                  _buildContextMenuItem(
                    value: 'bulk_quote',
                    icon: Icons.request_quote_outlined,
                    color: Colors.teal,
                    label: 'Generar Presupuesto',
                  ),
                _buildContextMenuItem(
                  value: 'bulk_status',
                  icon: Icons.power_settings_new,
                  color: Colors.teal.shade700,
                  label: 'Cambiar Estado (Activar / Desactivar)',
                ),
                _buildContextMenuItem(
                  value: 'bulk_labels',
                  icon: Icons.print_outlined,
                  color: Colors.deepPurple,
                  label: 'Imprimir Etiquetas (${_selectedProducts.length})',
                ),
                const PopupMenuDivider(height: 6),
                _buildContextMenuItem(
                  value: 'bulk_delete',
                  icon: Icons.delete_outline,
                  color: Colors.red,
                  label: 'Eliminar Seleccionados (${_selectedProducts.length})',
                  textColor: Colors.red.shade700,
                ),
                _buildContextMenuItem(
                  value: 'bulk_clear',
                  icon: Icons.deselect,
                  color: Colors.grey.shade600,
                  label: 'Limpiar Selección',
                ),
              ]
            : <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  enabled: false,
                  height: 44,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        p.isService
                            ? '\$${p.sellingPrice.toCurrency()} • Servicio'
                            : '\$${p.sellingPrice.toCurrency()} • Stock: ${p.stock.toUnitStockDisplay(isSoldByWeight: p.isSoldByWeight, unitSuffix: p.unitShortLabel, weightUnit: p.unitShortLabel)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(height: 6),
                _buildContextMenuItem(
                  value: 'edit',
                  icon: Icons.edit_outlined,
                  color: Colors.blue,
                  label: 'Editar producto',
                ),
                _buildContextMenuItem(
                  value: 'quick_price',
                  icon: Icons.price_change_outlined,
                  color: Colors.deepOrange,
                  label: 'Cambiar precio rápido',
                ),
                _buildContextMenuItem(
                  value: 'quick_classify',
                  icon: Icons.label_important_outline_rounded,
                  color: Colors.indigo,
                  label: canSeeSupplier
                      ? 'Clasificación rápida (Cat. / Marca / Prov.)'
                      : 'Clasificación rápida (Cat. / Marca)',
                ),
                if (!p.isService)
                  _buildContextMenuItem(
                    value: 'adjust_stock',
                    icon: Icons.warehouse_outlined,
                    color: Colors.teal,
                    label: 'Ajustar stock',
                  ),
                if (canUseBatches && !p.isCombo && !p.isService)
                  _buildContextMenuItem(
                    value: 'batches',
                    icon: Icons.layers_outlined,
                    color: Colors.deepOrange.shade700,
                    label: 'Lotes y vencimientos',
                  ),
                if (canUseProduction && !p.isCombo && !p.isService)
                  _buildContextMenuItem(
                    value: 'produce',
                    icon: Icons.bakery_dining_outlined,
                    color: Colors.brown.shade700,
                    label: 'Elaborar / Hornear ahora',
                  ),
                const PopupMenuDivider(height: 6),
                _buildContextMenuItem(
                  value: 'duplicate',
                  icon: Icons.copy_all_outlined,
                  color: Colors.indigo,
                  label: 'Duplicar producto',
                ),
                _buildContextMenuItem(
                  value: 'print_label',
                  icon: Icons.print_outlined,
                  color: Colors.deepPurple,
                  label: 'Imprimir etiqueta',
                ),
                _buildContextMenuItem(
                  value: 'share',
                  icon: Icons.share_outlined,
                  color: Colors.green.shade700,
                  label: 'Compartir ficha (WhatsApp)',
                ),
                _buildContextMenuItem(
                  value: 'copy_code',
                  icon: Icons.qr_code_2_outlined,
                  color: Colors.blueGrey,
                  label: (p.barcode != null && p.barcode!.trim().isNotEmpty)
                      ? 'Copiar código de barras'
                      : (p.internalCode.trim().isNotEmpty
                          ? 'Copiar código interno'
                          : (p.supplierSku != null && p.supplierSku!.trim().isNotEmpty
                              ? 'Copiar código de proveedor'
                              : 'Copiar código interno')),
                ),
                if (canUseQuotes)
                  _buildContextMenuItem(
                    value: 'quote',
                    icon: Icons.request_quote_outlined,
                    color: Colors.teal.shade700,
                    label: 'Generar presupuesto',
                  ),
                if (canSeeSupplier && p.supplier != null)
                  _buildContextMenuItem(
                    value: 'filter_by_supplier',
                    icon: Icons.local_shipping_outlined,
                    color: Colors.teal.shade800,
                    label: 'Ver productos de este proveedor',
                  ),
                if (resolvedImgUrl != null)
                  _buildContextMenuItem(
                    value: 'view_image',
                    icon: Icons.image_search_outlined,
                    color: Colors.purple,
                    label: 'Ver foto ampliada',
                  ),
                const PopupMenuDivider(height: 6),
                _buildContextMenuItem(
                  value: 'toggle_active',
                  icon: p.active
                      ? Icons.visibility_off_outlined
                      : Icons.check_circle_outline,
                  color: p.active ? Colors.amber.shade800 : Colors.green.shade700,
                  label: p.active ? 'Desactivar en POS' : 'Activar en POS',
                ),
                _buildContextMenuItem(
                  value: 'delete',
                  icon: Icons.delete_outline,
                  color: Colors.red,
                  label: 'Eliminar producto',
                  textColor: Colors.red.shade700,
                ),
              ],
      );
    } finally {
      if (mounted) {
        setState(() {
          if (_contextMenuProductId == p.id) {
            _contextMenuProductId = null;
          }
        });
      }
    }

    if (selectedAction == null || !mounted) return;

    switch (selectedAction) {
      case 'bulk_category':
        await _bulkUpdateCategory(provider);
        break;
      case 'bulk_brand':
        await _bulkUpdateBrand(provider);
        break;
      case 'bulk_supplier':
        await _bulkUpdateSupplier(provider);
        break;
      case 'bulk_prices':
        final auth = await AdminPinDialog.verify(
          context,
          action: 'Aumento Masivo Lote',
          permissionKey: 'manage_catalog',
        );
        if (auth && mounted) {
          final updated = await showDialog<bool>(
            context: context,
            builder: (_) => BulkPriceUpdateDialog(
              provider: provider,
              targetProductIds: _selectedProducts.keys.toList(),
            ),
          );
          if (updated == true && mounted) {
            setState(() => _selectedProducts.clear());
          }
        }
        break;
      case 'bulk_quote':
        await _bulkGenerateQuote();
        break;
      case 'bulk_status':
        await _bulkToggleActive(provider);
        break;
      case 'bulk_labels':
        await showDialog(
          context: context,
          builder: (_) =>
              PrintLabelsDialog(products: _selectedProducts.values.toList()),
        );
        break;
      case 'bulk_delete':
        await _confirmBulkDelete(provider);
        break;
      case 'bulk_clear':
        setState(() => _selectedProducts.clear());
        break;
      case 'edit':
        final auth = await AdminPinDialog.verify(
          context,
          action: 'Editar Producto',
          permissionKey: 'manage_catalog',
        );
        if (auth && mounted) _showProductForm(context, provider, product: p);
        break;
      case 'quick_price':
        final auth = await AdminPinDialog.verify(
          context,
          action: 'Cambiar Precio Rápido',
          permissionKey: 'manage_catalog',
        );
        if (auth && mounted) await _showQuickPriceDialog(context, provider, p);
        break;
      case 'quick_classify':
        final auth = await AdminPinDialog.verify(
          context,
          action: 'Clasificación Rápida',
          permissionKey: 'manage_catalog',
        );
        if (auth && mounted) {
          await showDialog<bool>(
            context: context,
            builder: (_) => _QuickProductClassificationDialog(
              provider: provider,
              product: p,
            ),
          );
        }
        break;
      case 'filter_by_supplier':
        if (p.supplier != null) {
          setState(() => _selectedProducts.clear());
          await provider.safeSetSupplierFilter(
            p.supplier!.id,
            supplierName: p.supplier!.name,
          );
        }
        break;
      case 'adjust_stock':
        final auth = await AdminPinDialog.verify(
          context,
          action: 'Ajustar Stock',
          permissionKey: 'adjust_stock',
        );
        if (auth && mounted) _showStockAdjustment(context, provider, p);
        break;
      case 'batches':
        _openProductBatches(provider, p);
        break;
      case 'produce':
        await showDialog(
          context: context,
          builder: (_) =>
              ProductionOrdersDialog(provider: provider, initialProduct: p),
        );
        if (mounted) {
          try {
            context.read<InventoryAlertsProvider>().fetchAlerts();
          } catch (_) {}
        }
        break;
      case 'duplicate':
        final auth = await AdminPinDialog.verify(
          context,
          action: 'Duplicar Producto',
          permissionKey: 'manage_catalog',
        );
        if (auth && mounted) {
          _showProductForm(context, provider, duplicateFrom: p);
        }
        break;
      case 'print_label':
        await showDialog(
          context: context,
          builder: (_) => PrintLabelsDialog(products: [p]),
        );
        break;
      case 'share':
        await ProductShareHelper.shareProduct(p, context: context);
        break;
      case 'copy_code':
        final barcodeText = p.barcode?.trim() ?? '';
        final internalText = p.internalCode.trim();
        final supplierSkuText = p.supplierSku?.trim() ?? '';
        final String code;
        final String snackMessage;
        if (barcodeText.isNotEmpty) {
          code = barcodeText;
          snackMessage = 'Código de barras copiado: $code';
        } else if (internalText.isNotEmpty) {
          code = internalText;
          snackMessage = 'Código interno copiado: $code';
        } else if (supplierSkuText.isNotEmpty) {
          code = supplierSkuText;
          snackMessage = 'Código de proveedor copiado: $code';
        } else {
          code = '';
          snackMessage = 'El producto no tiene código para copiar.';
        }
        if (code.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: code));
        }
        if (mounted) {
          if (code.isNotEmpty) {
            SnackBarService.success(context, snackMessage);
          } else {
            SnackBarService.info(context, snackMessage);
          }
        }
        break;
      case 'quote':
        await _generateQuoteForProducts([p]);
        break;
      case 'view_image':
        if (resolvedImgUrl != null) {
          await showDialog(
            context: context,
            builder: (_) => ProductImagePreviewDialog(
              title: p.name,
              imageUrl: resolvedImgUrl,
            ),
          );
        }
        break;
      case 'toggle_active':
        final nextActive = !p.active;
        final auth = await AdminPinDialog.verify(
          context,
          action: nextActive ? 'Activar Producto en POS' : 'Desactivar Producto en POS',
          permissionKey: 'manage_catalog',
        );
        if (auth && mounted) {
          final msg = await provider.bulkUpdateProducts([p.id], active: nextActive);
          if (!mounted) return;
          if (msg != null) {
            SnackBarService.success(
              context,
              nextActive
                  ? '"${p.name}" activado en POS.'
                  : '"${p.name}" desactivado en POS.',
            );
          } else {
            SnackBarService.error(
              context,
              provider.errorMessage ?? 'Error al cambiar estado del producto.',
            );
          }
        }
        break;
      case 'delete':
        final auth = await AdminPinDialog.verify(
          context,
          action: 'Eliminar Producto',
          permissionKey: 'manage_catalog',
        );
        if (auth && mounted) _confirmDelete(context, provider, p);
        break;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORMULARIO CREAR / EDITAR PRODUCTO
// ─────────────────────────────────────────────────────────────────────────────
class ProductFormDialog extends StatefulWidget {
  final CatalogProvider provider;
  final Product? product;
  final Product? duplicateFrom;
  final int? initialSupplierId;
  final String? initialSupplierName;
  final String? initialName;
  final String? initialBarcode;
  final String? initialSupplierSku;
  final bool lockInitialStockToZero;

  const ProductFormDialog({
    super.key,
    required this.provider,
    this.product,
    this.duplicateFrom,
    this.initialSupplierId,
    this.initialSupplierName,
    this.initialName,
    this.initialBarcode,
    this.initialSupplierSku,
    this.lockInitialStockToZero = false,
  });

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _barcodeCtrl;
  late TextEditingController _internalCodeCtrl;
  late TextEditingController _supplierSkuCtrl;
  late TextEditingController _technicalSpecCtrl;
  late TextEditingController _storageLocationCtrl;
  late TextEditingController _purchasePackageCtrl;
  late TextEditingController _conversionFactorCtrl;
  late TextEditingController _packageCostCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _marginCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _minStockCtrl;
  final FocusNode _nameFocusNode = FocusNode();
  int _batchCreatedCount = 0;
  Map<String, dynamic>? _calcConfig;
  bool _clearCalcConfig = false;
  bool _isAutoCalculating = false;
  String? _priceAnchor; // 'cost' | 'selling' | null (detecta automáticamente qué precio ingresó primero el usuario)
  bool _costIsAuto = false;
  bool _priceIsAuto = false;
  bool _isSoldByWeight = false;
  bool _userCustomizedUnit = false;
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
  bool get _isDuplicating => widget.product == null && widget.duplicateFrom != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final source = p ?? widget.duplicateFrom;
    final cleanInitialName = widget.initialName?.trim();
    final cleanInitialBarcode = widget.initialBarcode?.trim();
    final cleanInitialSupplierSku = widget.initialSupplierSku?.trim();
    _nameCtrl = TextEditingController(
      text: p?.name ??
          (_isDuplicating
              ? '${source!.name} (Copia)'
              : (cleanInitialName ?? '')),
    );
    _barcodeCtrl = TextEditingController(
      text: p?.barcode ?? (_isDuplicating ? '' : (cleanInitialBarcode ?? '')),
    );
    _internalCodeCtrl = TextEditingController(text: p?.internalCode ?? '');
    _supplierSkuCtrl = TextEditingController(
      text: source?.supplierSku ??
          (_isDuplicating ? '' : (cleanInitialSupplierSku ?? '')),
    );
    _technicalSpecCtrl = TextEditingController(text: source?.technicalSpec ?? '');
    _storageLocationCtrl = TextEditingController(text: source?.storageLocation ?? '');
    _purchasePackageCtrl =
        TextEditingController(text: source?.purchasePackageName ?? '');
    _conversionFactorCtrl = TextEditingController(
      text: source?.conversionFactor != null && source!.conversionFactor! > 0
          ? formatQuantityInput(source.conversionFactor!)
          : '',
    );
    _packageCostCtrl = TextEditingController(
      text: (source != null &&
              source.costPrice > 0 &&
              source.conversionFactor != null &&
              source.conversionFactor! > 0)
          ? (source.costPrice * source.conversionFactor!).toArsInput()
          : '',
    );
    _calcConfig = source?.calcConfig != null
        ? Map<String, dynamic>.from(source!.calcConfig!)
        : null;
    _costCtrl = TextEditingController(
      text: (source != null && source.costPrice > 0)
          ? source.costPrice.toArsInput()
          : '',
    );
    _priceCtrl = TextEditingController(
      text: source != null ? source.sellingPrice.toArsInput() : '',
    );
    _marginCtrl = TextEditingController();
    final hasFractionalStock =
        p != null && (p.stock - p.stock.roundToDouble()).abs() > 0.0005;
    _stockCtrl = TextEditingController(
      text: (widget.lockInitialStockToZero && p == null)
          ? '0'
          : (p != null
              ? ((p.isSoldByWeight || hasFractionalStock)
                  ? _formatComboQtyForInput(p.stock)
                  : p.stock.toStringAsFixed(0))
              : '0'),
    );
    
    _loadSavedMargin();
    
    _costCtrl.addListener(_onCostChanged);
    _marginCtrl.addListener(_onMarginChanged);
    _priceCtrl.addListener(_onPriceChanged);
    _minStockCtrl = TextEditingController(
      text: (source?.minStock != null) ? source!.minStock!.toStringAsFixed(0) : '',
    );
    SettingsProvider? initialSettingsProv;
    try {
      initialSettingsProv = context.read<SettingsProvider?>();
    } catch (_) {}
    final baseProfile = initialSettingsProv?.safeVerticalProfile ??
        BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);

    _userCustomizedUnit = source != null;
    _isSoldByWeight = source?.isSoldByWeight ?? baseProfile.defaultSoldByWeight;
    _active = source?.active ?? true;
    _isCombo = source?.isCombo ?? false;
    _isService = source?.isService ?? false;
    if (_isCombo && source?.comboIngredients != null) {
      _comboIngredients = source!.comboIngredients!
          .map((ing) => Map<String, dynamic>.from(ing))
          .toList();
    }
    if (source?.priceTiers != null) {
      _priceTiers = List<Map<String, dynamic>>.from(source!.priceTiers!);
      _expandPriceTiers = _priceTiers.isNotEmpty;
    }
    _unitType = source?.unitType ?? baseProfile.defaultUnitType;
    final rawIva = source?.ivaRate ?? 21.0;
    _ivaRate = const [0.0, 10.5, 21.0, 27.0].contains(rawIva) ? rawIva : 21.0;
    _categoryId = source?.category?.id;
    _brandId = source?.brand?.id;
    _supplierId = source?.supplier?.id ?? widget.initialSupplierId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final canSeeSupplier = context.read<SettingsProvider?>()?.features.suppliers ?? false;
      if (canSeeSupplier) {
        context.read<SupplierProvider>().fetchSuppliers();
      }
    });
    _expiryCtrl = TextEditingController(
      text: source?.vencimientoDias != null ? source!.vencimientoDias.toString() : '',
    );
    _expiryAlertDaysCtrl = TextEditingController(
      text: (source?.expiryAlertDays ?? 15).toString(),
    );
    if (p?.expirationDate != null && p!.expirationDate!.isNotEmpty) {
      _expirationDate = DateTime.tryParse(p.expirationDate!);
    }
    _trackBatches = source?.trackBatches ?? false;
    _lotDeductionPolicy = source?.lotDeductionPolicy ?? 'fefo';
    _allowSellExpired = source?.allowSellExpired ?? false;
    _hasProductionRecipe = source?.hasProductionRecipe ?? false;
    _recipeYieldCtrl = TextEditingController(
      text: (source?.recipeYieldQuantity ?? 1.0).toQty(),
    );
    _initialBatchCodeCtrl = TextEditingController();
    if (source?.recipeIngredients != null) {
      _recipeIngredients = source!.recipeIngredients!
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    _showExpirationSection = _trackBatches ||
        _expirationDate != null ||
        (source?.vencimientoDias != null && source!.vencimientoDias! > 0);
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
    _nameFocusNode.dispose();
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _internalCodeCtrl.dispose();
    _supplierSkuCtrl.dispose();
    _technicalSpecCtrl.dispose();
    _storageLocationCtrl.dispose();
    _purchasePackageCtrl.dispose();
    _conversionFactorCtrl.dispose();
    _packageCostCtrl.dispose();
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
    if (_isEditing || _isDuplicating) {
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

  Future<void> _submit({bool keepOpenForNext = false}) async {
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

    final isStockLockedToZero = widget.lockInitialStockToZero && !_isEditing;
    final parsedStock = isStockLockedToZero
        ? 0.0
        : (double.tryParse(_stockCtrl.text.replaceAll(',', '.')) ?? 0.0);
    final initialStock = widget.product != null
        ? (double.tryParse(widget.product!.stock.toStringAsFixed(widget.product!.isSoldByWeight ? 3 : 0)) ?? widget.product!.stock)
        : null;
    final stockModified = isStockLockedToZero ||
        !_isEditing ||
        initialStock == null ||
        (parsedStock - initialStock).abs() > 0.0001;

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

    final supplierSkuText = _supplierSkuCtrl.text.trim();
    final storageLocationText = _storageLocationCtrl.text.trim();
    final technicalSpecText = _technicalSpecCtrl.text.trim();
    final purchasePackageText = _purchasePackageCtrl.text.trim();
    final parsedConversionFactor = _conversionFactorCtrl.text.trim().isNotEmpty
        ? double.tryParse(_conversionFactorCtrl.text.trim().replaceAll(',', '.'))
        : null;

    final data = {
      'name': _nameCtrl.text.trim(),
      'barcode': _barcodeCtrl.text.trim(),
      if (_internalCodeCtrl.text.isNotEmpty) 'internal_code': _internalCodeCtrl.text.trim(),
      'supplier_sku': _isService || supplierSkuText.isEmpty ? null : supplierSkuText,
      'storage_location':
          _isService || storageLocationText.isEmpty ? null : storageLocationText,
      'technical_spec':
          _isService || technicalSpecText.isEmpty ? null : technicalSpecText,
      'purchase_package_name': (_isService || _isCombo || purchasePackageText.isEmpty)
          ? null
          : purchasePackageText,
      'conversion_factor': (_isService || _isCombo || parsedConversionFactor == null)
          ? null
          : roundQtyForStorage(parsedConversionFactor),
      if (!_isService && !_isCombo && (_calcConfig != null || _clearCalcConfig))
        'calc_config': _calcConfig,
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
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('last_profit_margin', margin);
        } catch (_) {}

        if (!mounted) return;
        Product? resultProd;
        if (targetProductId != null) {
          try {
            resultProd = widget.provider.products
                    .where((p) => p.id == targetProductId)
                    .firstOrNull ??
                widget.provider.lastCreatedProduct ??
                widget.provider.lastUpdatedProduct;
          } catch (_) {}
        }
        if (resultProd == null) {
          try {
            resultProd = _isEditing
                ? widget.provider.lastUpdatedProduct
                : widget.provider.lastCreatedProduct;
          } catch (_) {}
        }
        if (resultProd != null) {
          if (targetProductId != null && _calcConfig != null) {
            await HardwareCalculatorEngine.saveLocalCacheForProduct(
              targetProductId!,
              _calcConfig!,
            );
          } else if (targetProductId != null && _clearCalcConfig) {
            await HardwareCalculatorEngine.clearLocalCacheForProduct(
              targetProductId!,
            );
          }
          if (!mounted) return;
          try {
            context.read<PosProvider?>()?.syncUpdatedCatalogProduct(resultProd);
          } catch (_) {}
          try {
            context.read<OfferProvider?>()?.syncUpdatedProduct(resultProd);
          } catch (_) {}
        }
        if (keepOpenForNext && !_isEditing) {
          final savedName = _nameCtrl.text.trim();
          _resetFormForNextProduct();
          if (imageUploadSuccess) {
            SnackBarService.success(
              context,
              '¡"$savedName" guardado (#$_batchCreatedCount)! Cargá el siguiente.',
            );
          } else {
            SnackBarService.warning(
              context,
              '"$savedName" guardado, pero falló la foto: ${imageUploadError ?? "Error al procesar imagen."}',
            );
          }
          return;
        }
        Navigator.of(context).pop(resultProd);
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

  void _resetFormForNextProduct() {
    setState(() {
      _batchCreatedCount++;
      _isAutoCalculating = true;
      _nameCtrl.clear();
      _barcodeCtrl.clear();
      _internalCodeCtrl.clear();
      _supplierSkuCtrl.clear();
      _technicalSpecCtrl.clear();
      _storageLocationCtrl.clear();
      _conversionFactorCtrl.clear();
      _packageCostCtrl.clear();
      _costCtrl.clear();
      _priceCtrl.clear();
      _stockCtrl.text = '0';
      _minStockCtrl.clear();
      _isAutoCalculating = false;

      _costIsAuto = false;
      _priceIsAuto = false;
      _priceAnchor = null;
      _calcConfig = null;
      _clearCalcConfig = false;
      _selectedImagePath = null;
      _selectedImageBytes = null;
      _selectedImageName = null;
      _deleteExistingImage = false;
      _comboIngredients.clear();
      for (final c in _comboQtyCtrls.values) {
        c.dispose();
      }
      _comboQtyCtrls.clear();
      for (final c in _comboCustomPartsCtrls.values) {
        c.dispose();
      }
      _comboCustomPartsCtrls.clear();
      _expandedComboFractionIds.clear();
      _priceTiers.clear();
      _expandPriceTiers = false;
      _initialBatchCodeCtrl.clear();
      // Mantiene fijados: _supplierId, _categoryId, _brandId, _unitType,
      // _isSoldByWeight, _ivaRate, _marginCtrl y _purchasePackageCtrl.
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFocusNode.requestFocus();
      }
    });
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

  Rubro? _resolveCategoryRubro(Category? cat) {
    if (cat == null) return null;
    final rId = cat.rubroId ?? cat.rubro?.id;
    if (rId != null) {
      try {
        final found =
            widget.provider.safeRubros.where((r) => r.id == rId).firstOrNull;
        if (found != null) return found;
      } catch (_) {}
    }
    return cat.rubro;
  }

  BusinessVerticalProfile _resolveEffectiveFormProfile(
    SettingsProvider? settingsProv,
    List<Category> categories, {
    int? categoryIdOverride,
  }) {
    final baseProfile = settingsProv?.safeVerticalProfile ??
        BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
    final effectiveCategoryId = categoryIdOverride ?? _categoryId;
    if (!(settingsProv?.features.multiRubro ?? false) ||
        effectiveCategoryId == null) {
      return baseProfile;
    }
    final cat = categories.where((c) => c.id == effectiveCategoryId).firstOrNull;
    final rubro = _resolveCategoryRubro(cat);
    return baseProfile.forCategoryRubro(rubro);
  }

  void _applyCategoryDefaultUnitIfUntouched(
    int? nextCategoryId,
    List<Category> categories,
  ) {
    if (_isEditing || _isDuplicating || _userCustomizedUnit) return;
    SettingsProvider? sp;
    try {
      sp = context.read<SettingsProvider?>();
    } catch (_) {}
    final nextProfile = _resolveEffectiveFormProfile(
      sp,
      categories,
      categoryIdOverride: nextCategoryId,
    );
    _unitType = nextProfile.defaultUnitType;
    _isSoldByWeight = nextProfile.defaultSoldByWeight;
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
            helperStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.indigo,
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
            onChanged: (val) => setState(() {
              _categoryId = val;
              _applyCategoryDefaultUnitIfUntouched(val, categories);
            }),
            onCreateNew: (query) => _showCreateCategoryQuickDialog(initialName: query),
            createLabelBuilder: (query) => 'Crear categoría "${query.trim()}"',
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
    final createdId = await CatalogQuickCreateDialogs.showCreateCategory(
      context,
      initialName: initialName,
      subtitle: 'Creá una categoría rápida para este producto',
    );
    if (createdId != null && mounted) {
      List<Category> currentCategories;
      try {
        currentCategories = context.read<CatalogProvider>().categories;
      } catch (_) {
        currentCategories = widget.provider.categories;
      }
      setState(() {
        _categoryId = createdId;
        _applyCategoryDefaultUnitIfUntouched(createdId, currentCategories);
      });
    }
  }

  Future<void> _showCreateBrandQuickDialog({String? initialName}) async {
    final createdId = await CatalogQuickCreateDialogs.showCreateBrand(
      context,
      initialName: initialName,
      subtitle: 'Creá una marca rápida para asignarla al producto',
    );
    if (createdId != null && mounted) {
      setState(() => _brandId = createdId);
    }
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
            createLabelBuilder: (query) => 'Crear marca "${query.trim()}"',
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

  static const Map<String, String> _unitDropdownLabels = {
    'un': 'Unidades',
    'kg': 'Kilogramos',
    'g': 'Gramos',
    'lt': 'Litros',
    'mt': 'Metros (mt)',
    'm2': 'Metros² (m²)',
    'm3': 'Metros³ (m³)',
    'bolsa': 'Bolsa',
    'rollo': 'Rollo',
    'caja': 'Caja',
    'par': 'Par',
    'docena': 'Docenas',
  };

  List<DropdownMenuItem<String>> _buildUnitDropdownItems(
    BusinessVerticalProfile profile,
  ) {
    final items = <MapEntry<String, String>>[
      for (final key in profile.allowedUnitKeys)
        MapEntry(key, _unitDropdownLabels[key] ?? Product.shortLabelFor(key)),
    ];

    final normalizedCurrent = _unitType.trim();
    if (normalizedCurrent.isNotEmpty &&
        !items.any((entry) => entry.key == normalizedCurrent)) {
      items.add(
        MapEntry(
          normalizedCurrent,
          _unitDropdownLabels[normalizedCurrent] ??
              Product.shortLabelFor(normalizedCurrent),
        ),
      );
    }

    return items
        .map(
          (entry) => DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value),
          ),
        )
        .toList();
  }

  void _onUnitTypeChanged(String? val) {
    final nextUnit = (val == null || val.trim().isEmpty) ? 'un' : val.trim();
    setState(() {
      _userCustomizedUnit = true;
      _unitType = nextUnit;
      // Unidades discretas (un, bolsa, rollo, caja, par) NO activan fraccionado por defecto;
      // unidades métricas/peso/líquido sí habilitan venta decimal/corte.
      _isSoldByWeight = !Product.discreteUnitTypes.contains(nextUnit);
    });
  }

  void _onFractionalSwitchChanged(bool v, BusinessVerticalProfile profile) {
    setState(() {
      _userCustomizedUnit = true;
      _isSoldByWeight = v;
      if (!profile.isHardwareStore) {
        if (v && Product.discreteUnitTypes.contains(_unitType)) {
          _unitType = 'kg';
        } else if (!v) {
          _unitType = 'un';
        }
      }
    });
  }

  Widget _buildUnitAndWeightSection({
    required bool isNarrow,
    required BusinessVerticalProfile profile,
  }) {
    final showFractionSwitch = profile.showFractionSwitchInForm || _isSoldByWeight;
    final unitDropdown = DropdownButtonFormField<String>(
      key: ValueKey('unit_type_${isNarrow ? 'narrow' : 'wide'}_$_unitType'),
      isExpanded: true,
      initialValue: _unitType,
      decoration: const InputDecoration(
        labelText: 'Unidad de Medida',
        prefixIcon: Icon(Icons.square_foot),
        isDense: true,
      ),
      items: _buildUnitDropdownItems(profile),
      onChanged: _onUnitTypeChanged,
    );

    final fractionSwitch = SwitchListTile(
      key: const ValueKey('product_fractional_switch'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        isNarrow
            ? profile.weightSwitchLabelNarrow
            : profile.weightSwitchLabelWide,
        style: isNarrow ? null : const TextStyle(fontSize: 13),
      ),
      value: _isSoldByWeight,
      onChanged: (v) => _onFractionalSwitchChanged(v, profile),
    );

    final activeSwitch = SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        isNarrow ? 'Activo (Visible en POS)' : 'Activo en POS',
        style: isNarrow ? null : const TextStyle(fontSize: 13),
      ),
      value: _active,
      onChanged: (v) => setState(() => _active = v),
    );

    final unitShort = Product.shortLabelFor(_unitType);
    final Widget fractionalExplanationBanner = profile.showFractionalExplanationBanner
        ? Container(
            key: const ValueKey('product_fractional_explanation_banner'),
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _isSoldByWeight
                  ? const Color(0xFFF0FDFA)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isSoldByWeight
                    ? const Color(0xFF99F6E4)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isSoldByWeight
                      ? Icons.content_cut_rounded
                      : Icons.inventory_2_outlined,
                  size: 14,
                  color: _isSoldByWeight
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _isSoldByWeight
                        ? 'Fraccionable / Corte activo: En mostrador POS pedirá la cantidad o medida exacta en $unitShort (ej. 0.5, 1.25, 2.5 $unitShort) o permitirá usar la Calculadora F7.'
                        : 'Venta por unidad entera: En mostrador POS sumará 1 $unitShort directo al carrito sin pedir medida decimal.',
                    style: TextStyle(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w600,
                      color: _isSoldByWeight
                          ? const Color(0xFF0F766E)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          unitDropdown,
          if (showFractionSwitch) fractionSwitch,
          activeSwitch,
          if (profile.showFractionalExplanationBanner)
            fractionalExplanationBanner,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(flex: showFractionSwitch ? 4 : 6, child: unitDropdown),
            if (showFractionSwitch) ...[
              const SizedBox(width: 10),
              Expanded(flex: 4, child: fractionSwitch),
            ],
            SizedBox(width: showFractionSwitch ? 8 : 12),
            Expanded(flex: showFractionSwitch ? 4 : 6, child: activeSwitch),
          ],
        ),
        if (profile.showFractionalExplanationBanner) fractionalExplanationBanner,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANTE: usar context.watch (no widget.provider) para que el dropdown
    // se reconstruya automáticamente cuando el provider notifica cambios
    // (ej: cuando se crea una categoría/marca nueva desde el diálogo rápido).
    final provider = context.watch<CatalogProvider>();
    final supplierProv = context.watch<SupplierProvider>();
    SettingsProvider? settingsProv;
    try {
      settingsProv = context.watch<SettingsProvider?>();
    } catch (_) {}
    final canSeeSupplier = settingsProv?.features.suppliers ?? true;
    final isResponsableInscripto = settingsProv?.settings?.isResponsableInscripto ?? false;
    final categories = provider.categories;
    final brands = provider.brands;
    final suppliers = supplierProv.suppliers;
    final baseProfile = settingsProv?.safeVerticalProfile ??
        BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
    final formProfile = _resolveEffectiveFormProfile(settingsProv, categories);
    final isNarrow = MediaQuery.of(context).size.width < 450;
    final isBusy = provider.isLoading || _isUploadingImage;

    final screenSize = MediaQuery.of(context).size;
    final horizontalInset = isNarrow ? 10.0 : 24.0;
    final verticalInset = isNarrow ? 10.0 : 18.0;
    final dialogWidth =
        (screenSize.width - (horizontalInset * 2)).clamp(240.0, 660.0);

    return RemoteScannerListener(
      debugLabel: 'ProductFormDialog',
      onBarcodeScanned: _handleFormBarcodeScan,
      child: PopScope(
        canPop: !isBusy,
        child: AlertDialog(
          alignment: Alignment.center,
          insetPadding: EdgeInsets.symmetric(
            horizontal: horizontalInset,
            vertical: verticalInset,
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          titlePadding: EdgeInsets.zero,
          contentPadding: EdgeInsets.zero,
          actionsPadding: EdgeInsets.zero,
          content: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: isNarrow ? 240 : 640,
              maxWidth: 660,
              maxHeight: screenSize.height * (screenSize.height < 580 ? 0.96 : 0.92),
            ),
            child: SizedBox(
              width: dialogWidth,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppModalHeader(
                      title: _isEditing
                          ? 'Editar Producto'
                          : (_isDuplicating
                              ? 'Duplicar Producto'
                              : 'Nuevo Producto'),
                      subtitle: _isCombo
                          ? 'Combo / Pack o Fracción con descuento automático'
                          : (_isService
                              ? 'Servicio / Honorario sin control de stock'
                              : 'Ficha completa de catálogo, stock y precios'),
                      icon: _isCombo
                          ? Icons.layers_outlined
                          : (_isService
                              ? Icons.work_outline_rounded
                              : Icons.inventory_2_outlined),
                      accent: _isCombo
                          ? AppModalAccent.indigo
                          : (_isService
                              ? AppModalAccent.teal
                              : AppModalAccent.blue),
                      compact: isNarrow,
                      closeTooltip: 'Cerrar',
                      onClose:
                          isBusy ? null : () => Navigator.of(context).pop(),
                      trailing: _isEditing && widget.product != null
                          ? IconButton(
                              key: const Key('product_share_button'),
                              icon: const Icon(
                                Icons.share_outlined,
                                color: Colors.white70,
                                size: 20,
                              ),
                              tooltip: 'Compartir producto',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => ProductShareHelper.shareProduct(
                                widget.product!,
                                context: context,
                              ),
                            )
                          : null,
                    ),
                    // ── Selector Superior de Tipo de Ítem (Fijo arriba: 0px salto al cambiar pestaña) ──
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        isNarrow ? 12 : 20,
                        10,
                        isNarrow ? 12 : 20,
                        10,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceMuted,
                        border: Border(
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SegmentedButton<String>(
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              padding: const WidgetStatePropertyAll(
                                EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                              backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  if (_isCombo) return Colors.indigo.shade50;
                                  if (_isService) return AppColors.tealSoft;
                                  return AppColors.primarySoft;
                                }
                                return Colors.white;
                              }),
                              foregroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  if (_isCombo) return AppColors.indigo;
                                  if (_isService) return AppColors.tealDark;
                                  return AppColors.primaryDark;
                                }
                                return AppColors.textSecondary;
                              }),
                              side: WidgetStatePropertyAll(
                                BorderSide(color: Colors.blueGrey.shade200),
                              ),
                            ),
                            segments: [
                              ButtonSegment<String>(
                                value: 'product',
                                icon: const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  baseProfile.productTabLabel,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ButtonSegment<String>(
                                value: 'service',
                                icon: const Icon(
                                  Icons.work_outline_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  baseProfile.serviceTabLabel,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ButtonSegment<String>(
                                value: 'combo',
                                icon: const Icon(
                                  Icons.layers_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  baseProfile.comboTabLabel,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            selected: {
                              _isCombo
                                  ? 'combo'
                                  : (_isService ? 'service' : 'product')
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
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          isNarrow ? 14 : 20,
                          12,
                          isNarrow ? 14 : 20,
                          12,
                        ),
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
                            focusNode: _nameFocusNode,
                            decoration: InputDecoration(
                              labelText: _isService
                                  ? baseProfile.serviceNameFieldLabel
                                  : baseProfile.productNameFieldLabel,
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
                              decoration: InputDecoration(
                                labelText: 'Código de Barras (EAN)',
                                prefixIcon: const Icon(Icons.qr_code_scanner),
                                helperText: baseProfile.barcodeHelperText,
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
                                      focusNode: _nameFocusNode,
                                      decoration: InputDecoration(
                                        labelText: _isService
                                            ? baseProfile.serviceNameFieldLabel
                                            : baseProfile.productNameFieldLabel,
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
                                                helperText: _isService
                                                    ? 'No aplica en servicios'
                                                    : baseProfile.barcodeHelperText,
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
                                final hasMatchingSupplier =
                                    sortedSuppliers.any((s) => s.id == _supplierId);
                                final fallbackSupplierName =
                                    widget.initialSupplierName?.trim();
                                final showFallbackInitialSupplier = !hasMatchingSupplier &&
                                    _supplierId != null &&
                                    _supplierId == widget.initialSupplierId &&
                                    fallbackSupplierName != null &&
                                    fallbackSupplierName.isNotEmpty;
                                final hasSelection =
                                    hasMatchingSupplier || showFallbackInitialSupplier;
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
                                          if (showFallbackInitialSupplier)
                                            SearchableSelectOption<int?>(
                                              value: _supplierId,
                                              label: fallbackSupplierName,
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
                                        onCreateNew: (query) async {
                                          final createdId =
                                              await CatalogQuickCreateDialogs
                                                  .showCreateSupplier(
                                            context,
                                            initialQuery: query,
                                          );
                                          if (createdId != null && mounted) {
                                            setState(
                                                () => _supplierId = createdId);
                                          }
                                        },
                                        createLabelBuilder: (query) =>
                                            'Crear proveedor "${query.trim()}"',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: 'Crear Nuevo Proveedor',
                                      child: IconButton.filledTonal(
                                        icon: const Icon(Icons.add),
                                        onPressed: () async {
                                          final createdId =
                                              await CatalogQuickCreateDialogs
                                                  .showCreateSupplier(context);
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
                        if (!_isService)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ProductHardwareAndSupplierFieldsSection(
                              isHardwareStore: formProfile.isHardwareStore,
                              profile: formProfile,
                              showDimensionHelper: formProfile.canUseHardwareCalculator,
                              productNameGetter: () => _nameCtrl.text.trim(),
                              onApplyHardwareDimension: (specText, calcConfig) {
                                setState(() {
                                  _technicalSpecCtrl.text = specText;
                                  _calcConfig = calcConfig;
                                  _clearCalcConfig = false;
                                  if (!_isSoldByWeight &&
                                      (_unitType == 'm2' || _unitType == 'mt')) {
                                    _isSoldByWeight = true;
                                  }
                                });
                              },
                              isService: _isService,
                              isCombo: _isCombo,
                              isNarrow: isNarrow,
                              unitLabel: Product.shortLabelFor(_unitType),
                              supplierSkuCtrl: _supplierSkuCtrl,
                              technicalSpecCtrl: _technicalSpecCtrl,
                              storageLocationCtrl: _storageLocationCtrl,
                              purchasePackageCtrl: _purchasePackageCtrl,
                              conversionFactorCtrl: _conversionFactorCtrl,
                              packageCostCtrl: _packageCostCtrl,
                              unitCostCtrl: _costCtrl,
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
                                                      enabled: !(widget.lockInitialStockToZero && !_isEditing),
                                                      readOnly: widget.lockInitialStockToZero && !_isEditing,
                                                      decoration: InputDecoration(
                                                        labelText: (widget.lockInitialStockToZero && !_isEditing)
                                                            ? 'Stock inicial (0 por comprobante)'
                                                            : 'Stock inicial',
                                                        helperText: (widget.lockInitialStockToZero && !_isEditing)
                                                            ? 'El stock se sumará al confirmar el comprobante.'
                                                            : null,
                                                        suffixText: Product.shortLabelFor(_unitType),
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
                                                        enabled: !(widget.lockInitialStockToZero && !_isEditing),
                                                        readOnly: widget.lockInitialStockToZero && !_isEditing,
                                                        decoration: InputDecoration(
                                                          labelText: (widget.lockInitialStockToZero && !_isEditing)
                                                              ? 'Stock inicial (0 por comprobante)'
                                                              : 'Stock inicial',
                                                          helperText: (widget.lockInitialStockToZero && !_isEditing)
                                                              ? 'Se sumará al confirmar el comprobante.'
                                                              : null,
                                                          suffixText: Product.shortLabelFor(_unitType),
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
                                        _buildUnitAndWeightSection(
                                          isNarrow: isNarrow,
                                          profile: formProfile,
                                        ),
                                        if (formProfile.canUseHardwareCalculator) ...[
                                          const SizedBox(height: 10),
                                          ProductF7CalcConfigPanel(
                                            calcConfig: _calcConfig,
                                            productNameHint: _nameCtrl.text.trim(),
                                            productNameListenable: _nameCtrl,
                                            technicalSpecHint: _technicalSpecCtrl.text.trim(),
                                            technicalSpecListenable: _technicalSpecCtrl,
                                            onChanged: (nextConfig) {
                                              setState(() {
                                                _calcConfig = nextConfig;
                                                _clearCalcConfig = nextConfig == null;
                                              });
                                            },
                                          ),
                                        ],
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
                AppModalFooter(
                  padding: EdgeInsets.fromLTRB(
                    isNarrow ? 12 : 20,
                    10,
                    isNarrow ? 12 : 20,
                    10,
                  ),
                  actions: [
                    Consumer<CatalogProvider>(
                      builder: (_, p, __) {
                        final isBusy = p.isLoading || _isUploadingImage;
                        return TextButton(
                          onPressed:
                              isBusy ? null : () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        );
                      },
                    ),
                    if (!_isEditing)
                      Consumer<CatalogProvider>(
                        builder: (_, p, __) {
                          final isBusy = p.isLoading || _isUploadingImage;
                          return OutlinedButton.icon(
                            key: const Key('product_save_and_create_another_btn'),
                            onPressed:
                                isBusy ? null : () => _submit(keepOpenForNext: true),
                            icon: const Icon(Icons.playlist_add_rounded, size: 18),
                            label: Text(
                              _batchCreatedCount > 0
                                  ? 'Guardar y Crear Otro ($_batchCreatedCount)'
                                  : 'Guardar y Crear Otro',
                            ),
                          );
                        },
                      ),
                    Consumer<CatalogProvider>(
                      builder: (_, p, __) {
                        final isBusy = p.isLoading || _isUploadingImage;
                        return FilledButton(
                          key: const Key('product_submit_btn'),
                          onPressed: isBusy ? null : () => _submit(),
                          child: isBusy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isEditing ? 'Guardar Cambios' : 'Crear Producto',
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
      builder: (ctx) => AppModalShell(
        title: 'Agregar Insumo / Semi-Elaborado a Receta',
        subtitle: 'Buscá la materia prima o sub-receta a descontar al elaborar',
        icon: Icons.restaurant_menu_outlined,
        accent: AppModalAccent.orange,
        compact: true,
        maxWidth: 480,
        onClose: () => Navigator.pop(ctx),
        body: SearchableSelectField<int>(
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
        footerActions: [
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
        color: Colors.indigo.shade50.withValues(alpha: 0.45),
        border: Border.all(color: Colors.indigo.shade200),
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
                        size: 17, color: Colors.indigo.shade700),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Productos incluidos en el Combo (${_comboIngredients.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.indigo.shade800,
                  side: BorderSide(color: Colors.indigo.shade300),
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
                    border: Border.all(color: Colors.indigo.shade200),
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
                                color: Colors.indigo.shade600, size: 19),
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
                            color: Colors.indigo.shade700,
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
                              ? AppColors.indigo
                              : Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (showFractionBar || hasFractionalQty)
                                ? AppColors.indigo
                                : Colors.indigo.shade200,
                          ),
                        ),
                        child: Text(
                          '1/x',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: (showFractionBar || hasFractionalQty)
                                ? Colors.white
                                : Colors.indigo.shade700,
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
                        : Colors.indigo.shade100,
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
                      ? AppColors.indigo
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected
                        ? AppColors.indigo
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
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.indigo.shade300),
              ),
              child: Text(
                '1/N',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.indigo.shade800,
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
            isApplied ? Colors.green.shade800 : Colors.indigo.shade800,
        backgroundColor:
            isApplied ? Colors.green.shade50 : Colors.indigo.shade50,
        side: BorderSide(
          color:
              isApplied ? Colors.green.shade300 : Colors.indigo.shade300,
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
        border: Border.all(color: Colors.indigo.shade200),
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
                        size: 17, color: Colors.indigo.shade700),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isFractionMode
                            ? 'Cálculo de Porción / Fracción'
                            : 'Resumen para calcular tu Precio de Combo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: Colors.indigo.shade900,
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
                          foregroundColor: Colors.indigo.shade800,
                          backgroundColor: Colors.indigo.shade50,
                          side: BorderSide(color: Colors.indigo.shade300),
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
                            color: Colors.indigo.shade800,
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
      child: AppModalShell(
        title: 'Buscar Producto para el Combo',
        subtitle: 'Escaneá código o buscá por nombre / PLU',
        icon: Icons.layers_outlined,
        accent: AppModalAccent.indigo,
        compact: true,
        maxWidth: 480,
        maxHeight: 460,
        expandBody: true,
        topBar: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            onSubmitted: _onSearchSubmittedOrScanned,
            decoration: InputDecoration(
              labelText: 'Nombre, código de barras o PLU...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
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
        ),
        bodyPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        body: _firstLoad
            ? const Center(child: CircularProgressIndicator())
            : (_results.isEmpty
                ? const Center(child: Text('No hay resultados'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final p = _results[i];
                      final alreadyAdded =
                          widget.comboIngredients.any((ing) => ing['id'] == p.id);
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text(
                          'Stock: ${p.stock.toQty()} ${p.unitType} | Costo: \$${p.costPrice.toCurrency()} | Venta: \$${p.sellingPrice.toCurrency()}',
                        ),
                        onTap: alreadyAdded ? null : () => _addIngredient(p),
                        trailing: alreadyAdded
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.deepOrange,
                                ),
                                tooltip: 'Agregar al Combo',
                                onPressed: () => _addIngredient(p),
                              ),
                      );
                    },
                  )),
        footerActions: [
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
      builder: (ctx) => AppModalShell(
        title: 'Confirmar Aumento',
        subtitle: 'Revisá el impacto antes de actualizar el catálogo',
        icon: Icons.warning_amber_rounded,
        accent: AppModalAccent.orange,
        compact: true,
        maxWidth: 480,
        onClose: () => Navigator.pop(ctx, false),
        bodyPadding: const EdgeInsets.all(18),
        body: Column(
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
        footerActions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
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
      Navigator.of(context).pop(true);
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
    return AppModalShell(
      title: 'Aumento Masivo de Precios',
      subtitle: 'Actualización porcentual con redondeo y reversión',
      icon: Icons.trending_up_rounded,
      accent: AppModalAccent.orange,
      compact: true,
      maxWidth: 480,
      expandBody: false,
      bodyPadding: const EdgeInsets.all(18),
      body: Column(
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
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        Consumer<CatalogProvider>(
          builder: (_, p, __) => FilledButton.icon(
            icon: const Icon(Icons.preview),
            label: p.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
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
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Revertir Aumento',
      message:
          '¿Estás seguro de que deseas deshacer este lote de aumentos? Los precios de todos los productos afectados volverán a su estado anterior.',
      confirmLabel: 'Revertir Lote',
      icon: Icons.settings_backup_restore_rounded,
      isDestructive: true,
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
    return AppModalShell(
      title: 'Historial de Aumentos',
      subtitle: 'Auditoría y reversión de ajustes masivos',
      icon: Icons.history_rounded,
      accent: AppModalAccent.orange,
      maxWidth: 640,
      maxHeight: 500,
      expandBody: true,
      bodyPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      body: Consumer<CatalogProvider>(
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
      footerActions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _QuickPriceEditDialog extends StatefulWidget {
  final CatalogProvider provider;
  final Product product;

  const _QuickPriceEditDialog({
    required this.provider,
    required this.product,
  });

  @override
  State<_QuickPriceEditDialog> createState() => _QuickPriceEditDialogState();
}

class _QuickPriceEditDialogState extends State<_QuickPriceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _costCtrl;
  late final TextEditingController _marginCtrl;
  late final TextEditingController _priceCtrl;
  bool _isAutoCalculating = false;
  bool _priceIsAuto = false;
  bool _costIsAuto = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _costCtrl = TextEditingController(
      text: p.costPrice > 0 ? p.costPrice.toArsInput() : '',
    );
    _priceCtrl = TextEditingController(
      text: p.sellingPrice > 0 ? p.sellingPrice.toArsInput() : '',
    );
    final initialMargin = (p.costPrice > 0 && p.sellingPrice > 0)
        ? ((p.sellingPrice - p.costPrice) / p.costPrice) * 100
        : 0.0;
    _marginCtrl = TextEditingController(
      text: p.costPrice > 0 ? initialMargin.toCleanMargin() : '',
    );

    _costCtrl.addListener(_onCostChanged);
    _marginCtrl.addListener(_onMarginChanged);
    _priceCtrl.addListener(_onPriceChanged);
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    _marginCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
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
      return;
    }

    final cost = ArsThousandsInputFormatter.parse(costStr);
    if (cost <= 0) return;

    if (priceStr.isEmpty || _priceIsAuto) {
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

    final price = ArsThousandsInputFormatter.parse(priceStr);
    if (price > 0) {
      final margin = ((price - cost) / cost) * 100;
      _isAutoCalculating = true;
      _marginCtrl.text = margin.toCleanMargin();
      _isAutoCalculating = false;
    }
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
      } else if (_priceIsAuto) {
        _isAutoCalculating = true;
        _priceCtrl.clear();
        _priceIsAuto = false;
        _isAutoCalculating = false;
      }
      return;
    }

    final margin = double.tryParse(marginStr);
    if (margin == null || margin <= -100) return;

    final cost = costStr.isNotEmpty ? ArsThousandsInputFormatter.parse(costStr) : 0.0;
    if (cost > 0) {
      final newPrice = cost * (1 + (margin / 100));
      _isAutoCalculating = true;
      _priceCtrl.text = newPrice.toArsInput();
      _priceIsAuto = true;
      _isAutoCalculating = false;
    } else if (priceStr.isNotEmpty && !widget.product.isCombo) {
      final price = ArsThousandsInputFormatter.parse(priceStr);
      if (price > 0) {
        final newCost = price / (1 + (margin / 100));
        _isAutoCalculating = true;
        _costCtrl.text = newCost.toArsInput();
        _costIsAuto = true;
        _isAutoCalculating = false;
      }
    }
  }

  void _onPriceChanged() {
    if (_isAutoCalculating) return;
    final costStr = _costCtrl.text.trim();
    final priceStr = _priceCtrl.text.trim();
    final marginStr = _marginCtrl.text.replaceAll(',', '.').trim();

    _priceIsAuto = false;

    if (priceStr.isEmpty) {
      if (_costIsAuto) {
        _isAutoCalculating = true;
        _costCtrl.clear();
        _costIsAuto = false;
        _isAutoCalculating = false;
      }
      return;
    }

    final price = ArsThousandsInputFormatter.parse(priceStr);
    if (price <= 0) return;

    final cost = costStr.isNotEmpty ? ArsThousandsInputFormatter.parse(costStr) : 0.0;
    if (cost > 0) {
      final margin = ((price - cost) / cost) * 100;
      _isAutoCalculating = true;
      _marginCtrl.text = margin.toCleanMargin();
      _isAutoCalculating = false;
    } else if (marginStr.isNotEmpty && !widget.product.isCombo) {
      final margin = double.tryParse(marginStr);
      if (margin != null && margin > -100) {
        final newCost = price / (1 + (margin / 100));
        _isAutoCalculating = true;
        _costCtrl.text = newCost.toArsInput();
        _costIsAuto = true;
        _isAutoCalculating = false;
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final newSelling = ArsThousandsInputFormatter.parse(_priceCtrl.text);
    final newCost = _costCtrl.text.trim().isNotEmpty
        ? ArsThousandsInputFormatter.parse(_costCtrl.text)
        : 0.0;

    setState(() => _saving = true);
    final updated = await widget.provider.updateProductPriceFromPos(
      widget.product.id,
      sellingPrice: newSelling,
      costPrice: widget.product.isCombo ? null : newCost,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (updated != null) {
      try {
        context.read<PosProvider?>()?.syncUpdatedCatalogProduct(updated);
      } catch (_) {}
      try {
        context.read<OfferProvider?>()?.syncUpdatedProduct(updated);
      } catch (_) {}
      Navigator.of(context).pop(updated);
      SnackBarService.success(
        context,
        'Precio de "${widget.product.name}" actualizado a \$${updated.sellingPrice.toCurrency()}.',
      );
    } else {
      SnackBarService.error(
        context,
        widget.provider.errorMessage ?? 'No se pudo actualizar el precio.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return AppModalShell(
      title: 'Cambiar Precio Rápido',
      subtitle: p.name,
      icon: Icons.price_change_outlined,
      accent: AppModalAccent.amber,
      compact: true,
      maxWidth: 460,
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      bodyPadding: const EdgeInsets.all(18),
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              p.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Actual: Costo \$${p.costPrice.toCurrency()} • Venta \$${p.sellingPrice.toCurrency()}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    controller: _costCtrl,
                    readOnly: p.isCombo,
                    decoration: InputDecoration(
                      labelText: p.isCombo ? 'Costo Combo' : 'Costo (\$)',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [ArsThousandsInputFormatter()],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _marginCtrl,
                    decoration: const InputDecoration(
                      labelText: '% Margen',
                      suffixText: '%',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    controller: _priceCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Precio Venta *',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [ArsThousandsInputFormatter()],
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Requerido';
                      }
                      final parsed = ArsThousandsInputFormatter.tryParse(val);
                      if (parsed == null || parsed <= 0) {
                        return 'Mayor a 0';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      footerActions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text('Guardar Precio'),
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

/// Modal liviano y buscable para cambiar de proveedor al instante desde el banner del catálogo.
class _QuickSupplierPickerDialog extends StatefulWidget {
  final int? currentSupplierId;

  const _QuickSupplierPickerDialog({this.currentSupplierId});

  @override
  State<_QuickSupplierPickerDialog> createState() =>
      _QuickSupplierPickerDialogState();
}

class _QuickSupplierPickerDialogState
    extends State<_QuickSupplierPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supplierProv = context.watch<SupplierProvider>();
    final sorted = sortByAlphabeticalName(
      supplierProv.suppliers,
      (s) => s.name,
    );
    final normQuery = normalizeSearchText(_query);
    final filtered = normQuery.isEmpty
        ? sorted
        : sorted.where((s) {
            final nameMatch = normalizeSearchText(s.name).contains(normQuery);
            final cuitMatch = s.cuit != null &&
                normalizeSearchText(s.cuit!).contains(normQuery);
            return nameMatch || cuitMatch;
          }).toList();

    final maxListHeight =
        math.min(340.0, MediaQuery.of(context).size.height * 0.48);

    return AppModalShell(
      title: 'Cambiar Proveedor',
      subtitle: 'Elegí otro proveedor para filtrar el catálogo al instante',
      icon: Icons.local_shipping_outlined,
      accent: AppModalAccent.teal,
      compact: true,
      maxWidth: 440,
      onClose: () => Navigator.of(context).pop(),
      topBar: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: AppColors.surfaceMuted,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: TextField(
          key: const ValueKey('quick_supplier_switcher_search_field'),
          controller: _searchCtrl,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Buscar proveedor o CUIT...',
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.search, size: 19),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 17),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          ),
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      body: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxListHeight),
        child: supplierProv.isLoading && sorted.isEmpty
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  if (normQuery.isEmpty)
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      tileColor: AppColors.surfaceMuted,
                      leading: const Icon(Icons.filter_alt_off_outlined,
                          size: 18, color: AppColors.textSecondary),
                      title: const Text(
                        '— Ver todos los proveedores —',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(-1),
                    ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No hay proveedores que coincidan.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    )
                  else
                    ...filtered.map((s) {
                      final isSelected = s.id == widget.currentSupplierId;
                      final hasCuit =
                          s.cuit != null && s.cuit!.trim().isNotEmpty;
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        tileColor: isSelected ? AppColors.primarySoft : null,
                        title: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? AppColors.primaryDark
                                : AppColors.textPrimary,
                          ),
                        ),
                        subtitle: hasCuit
                            ? Text(
                                'CUIT: ${s.cuit!.trim()}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.blueGrey.shade600,
                                ),
                              )
                            : null,
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: AppColors.primaryDark,
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(s.id),
                      );
                    }),
                ],
              ),
      ),
      footerLeading: TextButton.icon(
        icon: const Icon(Icons.add, size: 17),
        label: const Text('Nuevo Proveedor'),
        onPressed: () async {
          final createdId = await CatalogQuickCreateDialogs.showCreateSupplier(
            context,
            initialQuery: _query,
          );
          if (createdId != null && context.mounted) {
            Navigator.of(context).pop(createdId);
          }
        },
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

/// Mini-modal de clasificación rápida para 1 producto (Categoría, Marca, Proveedor y Ubicación)
/// con buscador y alta rápida "+" inline sin necesidad de abrir la ficha completa.
class _QuickProductClassificationDialog extends StatefulWidget {
  final CatalogProvider provider;
  final Product product;

  const _QuickProductClassificationDialog({
    required this.provider,
    required this.product,
  });

  @override
  State<_QuickProductClassificationDialog> createState() =>
      _QuickProductClassificationDialogState();
}

class _QuickProductClassificationDialogState
    extends State<_QuickProductClassificationDialog> {
  late int? _categoryId;
  late int? _brandId;
  late int? _supplierId;
  late final TextEditingController _storageLocationCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.product.category?.id;
    _brandId = widget.product.brand?.id;
    _supplierId = widget.product.supplier?.id;
    _storageLocationCtrl = TextEditingController(
      text: widget.product.storageLocation ?? '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.provider.categories.isEmpty ||
          widget.provider.brands.isEmpty) {
        widget.provider.loadMetadata();
      }
      final canSeeSupplier =
          context.read<SettingsProvider?>()?.features.suppliers ?? false;
      if (canSeeSupplier) {
        try {
          final supProv = context.read<SupplierProvider?>();
          if (supProv != null &&
              supProv.suppliers.isEmpty &&
              !supProv.isLoading) {
            supProv.fetchSuppliers();
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _storageLocationCtrl.dispose();
    super.dispose();
  }

  Future<void> _createCategory({String? initialName}) async {
    final createdId = await CatalogQuickCreateDialogs.showCreateCategory(
      context,
      initialName: initialName,
      subtitle: 'Creá una categoría rápida para este producto',
    );
    if (createdId != null && mounted) {
      setState(() => _categoryId = createdId);
    }
  }

  Future<void> _createBrand({String? initialName}) async {
    final createdId = await CatalogQuickCreateDialogs.showCreateBrand(
      context,
      initialName: initialName,
      subtitle: 'Creá una marca rápida para este producto',
    );
    if (createdId != null && mounted) {
      setState(() => _brandId = createdId);
    }
  }

  Future<void> _createSupplier({String? initialQuery}) async {
    final createdId = await CatalogQuickCreateDialogs.showCreateSupplier(
      context,
      initialQuery: initialQuery,
    );
    if (createdId != null && mounted) {
      setState(() => _supplierId = createdId);
    }
  }

  Future<void> _save({
    required bool canSeeSupplier,
    required bool showStorageLocation,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);

    final locText = _storageLocationCtrl.text.trim();
    final payload = <String, dynamic>{
      'category_id': _categoryId,
      'brand_id': _brandId,
      if (canSeeSupplier) 'supplier_id': _supplierId,
      if (showStorageLocation)
        'storage_location': locText.isEmpty ? null : locText,
    };

    final ok = await widget.provider.updateProduct(widget.product.id, payload);
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      final updated = widget.provider.lastUpdatedProduct;
      if (updated != null) {
        try {
          context.read<PosProvider?>()?.syncUpdatedCatalogProduct(updated);
        } catch (_) {}
        try {
          context.read<OfferProvider?>()?.syncUpdatedProduct(updated);
        } catch (_) {}
      }
      Navigator.of(context).pop(true);
      SnackBarService.success(
        context,
        'Clasificación de "${widget.product.name}" actualizada.',
      );
    } else {
      SnackBarService.error(
        context,
        widget.provider.errorMessage ?? 'No se pudo actualizar el producto.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final catalogProv = context.watch<CatalogProvider>();
    final sp = context.watch<SettingsProvider?>();
    final profile = sp?.safeVerticalProfile ??
        BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
    final showStorageLocation =
        profile.showLocationColumnInCatalog && !p.isService;
    SupplierProvider? supplierProv;
    try {
      supplierProv = context.watch<SupplierProvider?>();
    } catch (_) {}
    final canSeeSupplier =
        (sp?.features.suppliers ?? false) && supplierProv != null;

    final sortedCategories =
        sortByAlphabeticalName(catalogProv.categories, (c) => c.name);
    final sortedBrands =
        sortByAlphabeticalName(catalogProv.brands, (b) => b.name);
    final sortedSuppliers = sortByAlphabeticalName(
      supplierProv?.suppliers ?? const <Supplier>[],
      (s) => s.name,
    );

    final hasMatchingCat =
        _categoryId != null && sortedCategories.any((c) => c.id == _categoryId);
    final showFallbackCat =
        !hasMatchingCat && _categoryId != null && p.category?.id == _categoryId;

    final hasMatchingBrand =
        _brandId != null && sortedBrands.any((b) => b.id == _brandId);
    final showFallbackBrand =
        !hasMatchingBrand && _brandId != null && p.brand?.id == _brandId;

    final hasMatchingSup =
        _supplierId != null && sortedSuppliers.any((s) => s.id == _supplierId);
    final showFallbackSup =
        !hasMatchingSup && _supplierId != null && p.supplier?.id == _supplierId;

    return AppModalShell(
      title: 'Clasificación Rápida',
      subtitle: p.name,
      icon: Icons.label_important_outline_rounded,
      accent: AppModalAccent.indigo,
      compact: true,
      maxWidth: 480,
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      bodyPadding: const EdgeInsets.all(18),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SearchableSelectField<int?>(
                  key: const ValueKey('quick_classify_category_field'),
                  value: (hasMatchingCat || showFallbackCat) ? _categoryId : null,
                  clearValue: null,
                  isDense: true,
                  enabled: !_saving,
                  labelText: 'Categoría',
                  dialogTitle: 'Seleccionar Categoría',
                  searchHintText: 'Buscar categoría o rubro...',
                  prefixIcon: Icons.category_outlined,
                  border: const OutlineInputBorder(),
                  options: [
                    const SearchableSelectOption<int?>(
                      value: null,
                      label: '— Sin categoría —',
                      isResetOption: true,
                    ),
                    if (showFallbackCat && p.category != null)
                      SearchableSelectOption<int?>(
                        value: p.category!.id,
                        label: p.category!.name,
                      ),
                    ...sortedCategories.map((c) {
                      final rId = c.rubroId ?? c.rubro?.id;
                      final rubroName = (rId != null
                              ? catalogProv.rubros
                                  .where((r) => r.id == rId)
                                  .firstOrNull
                                  ?.name
                              : null) ??
                          c.rubro?.name;
                      final hasRubro =
                          rubroName != null && rubroName.trim().isNotEmpty;
                      return SearchableSelectOption<int?>(
                        value: c.id,
                        label: c.name,
                        subtitle: hasRubro ? 'Rubro: $rubroName' : null,
                        searchKeywords: hasRubro ? [rubroName] : const [],
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _categoryId = val),
                  onCreateNew: (q) => _createCategory(initialName: q),
                  createLabelBuilder: (q) => 'Crear categoría "${q.trim()}"',
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Crear nueva categoría',
                child: IconButton.filledTonal(
                  key: const ValueKey('quick_classify_create_category_btn'),
                  icon: const Icon(Icons.add),
                  onPressed: _saving ? null : () => _createCategory(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SearchableSelectField<int?>(
                  key: const ValueKey('quick_classify_brand_field'),
                  value: (hasMatchingBrand || showFallbackBrand) ? _brandId : null,
                  clearValue: null,
                  isDense: true,
                  enabled: !_saving,
                  labelText: 'Marca',
                  dialogTitle: 'Seleccionar Marca',
                  searchHintText: 'Buscar marca...',
                  prefixIcon: Icons.branding_watermark_outlined,
                  border: const OutlineInputBorder(),
                  options: [
                    const SearchableSelectOption<int?>(
                      value: null,
                      label: '— Sin marca —',
                      isResetOption: true,
                    ),
                    if (showFallbackBrand && p.brand != null)
                      SearchableSelectOption<int?>(
                        value: p.brand!.id,
                        label: p.brand!.name,
                      ),
                    ...sortedBrands.map(
                      (b) => SearchableSelectOption<int?>(
                        value: b.id,
                        label: b.name,
                      ),
                    ),
                  ],
                  onChanged: (val) => setState(() => _brandId = val),
                  onCreateNew: (q) => _createBrand(initialName: q),
                  createLabelBuilder: (q) => 'Crear marca "${q.trim()}"',
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Crear nueva marca',
                child: IconButton.filledTonal(
                  key: const ValueKey('quick_classify_create_brand_btn'),
                  icon: const Icon(Icons.add),
                  onPressed: _saving ? null : () => _createBrand(),
                ),
              ),
            ],
          ),
          if (canSeeSupplier) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SearchableSelectField<int?>(
                    key: const ValueKey('quick_classify_supplier_field'),
                    value:
                        (hasMatchingSup || showFallbackSup) ? _supplierId : null,
                    clearValue: null,
                    isDense: true,
                    enabled: !_saving,
                    labelText: 'Proveedor',
                    dialogTitle: 'Seleccionar Proveedor',
                    searchHintText: 'Buscar proveedor o CUIT...',
                    prefixIcon: Icons.local_shipping_outlined,
                    border: const OutlineInputBorder(),
                    options: [
                      const SearchableSelectOption<int?>(
                        value: null,
                        label: '— Sin proveedor —',
                        isResetOption: true,
                      ),
                      if (showFallbackSup && p.supplier != null)
                        SearchableSelectOption<int?>(
                          value: p.supplier!.id,
                          label: p.supplier!.name,
                        ),
                      ...sortedSuppliers.map((s) {
                        final hasCuit =
                            s.cuit != null && s.cuit!.trim().isNotEmpty;
                        return SearchableSelectOption<int?>(
                          value: s.id,
                          label: s.name,
                          subtitle: hasCuit ? 'CUIT: ${s.cuit!.trim()}' : null,
                          searchKeywords: hasCuit ? [s.cuit!.trim()] : const [],
                        );
                      }),
                    ],
                    onChanged: (val) => setState(() => _supplierId = val),
                    onCreateNew: (q) => _createSupplier(initialQuery: q),
                    createLabelBuilder: (q) => 'Crear proveedor "${q.trim()}"',
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Crear nuevo proveedor',
                  child: IconButton.filledTonal(
                    key: const ValueKey('quick_classify_create_supplier_btn'),
                    icon: const Icon(Icons.add),
                    onPressed: _saving ? null : () => _createSupplier(),
                  ),
                ),
              ],
            ),
          ],
          if (showStorageLocation) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('quick_classify_location_field'),
              controller: _storageLocationCtrl,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Ubicación en depósito / estantería',
                hintText: 'Ej: Estante 2, Pasillo A, Galpón...',
                prefixIcon: Icon(Icons.location_on_outlined, size: 19),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _save(
                canSeeSupplier: canSeeSupplier,
                showStorageLocation: showStorageLocation,
              ),
            ),
          ],
        ],
      ),
      footerActions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          key: const ValueKey('quick_classify_save_btn'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
          onPressed: _saving
              ? null
              : () => _save(
                    canSeeSupplier: canSeeSupplier,
                    showStorageLocation: showStorageLocation,
                  ),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}



