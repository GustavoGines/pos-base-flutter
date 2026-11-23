import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/pos_search_history_popover.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/services/product_pricing_calculator.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

/// Modal rápido de consulta de precios y stock sin agregar al carrito (`F5`).
/// Pensado para pistoleo continuo de códigos de barras o búsqueda por nombre.
class PosPriceLookupDialog extends StatefulWidget {
  final bool canAddToCart;
  final ValueChanged<String>? onQuickCreateRequested;
  final ValueChanged<String>? onAssociateBarcodeRequested;
  final ValueChanged<Product>? onHardwareCalculatorRequested;

  const PosPriceLookupDialog({
    super.key,
    this.canAddToCart = true,
    this.onQuickCreateRequested,
    this.onAssociateBarcodeRequested,
    this.onHardwareCalculatorRequested,
  });

  static Future<Product?> show(
    BuildContext context, {
    bool canAddToCart = true,
    ValueChanged<String>? onQuickCreateRequested,
    ValueChanged<String>? onAssociateBarcodeRequested,
    ValueChanged<Product>? onHardwareCalculatorRequested,
  }) {
    return showDialog<Product>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PosPriceLookupDialog(
        canAddToCart: canAddToCart,
        onQuickCreateRequested: onQuickCreateRequested,
        onAssociateBarcodeRequested: onAssociateBarcodeRequested,
        onHardwareCalculatorRequested: onHardwareCalculatorRequested,
      ),
    );
  }

  @override
  State<PosPriceLookupDialog> createState() => _PosPriceLookupDialogState();
}

class _PosPriceLookupDialogState extends State<PosPriceLookupDialog> {
  static final RegExp _barcodePattern =
      RegExp(r'^(?=.*\d)[A-Za-z0-9\-_]{5,32}$');

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchHistoryPortalController = OverlayPortalController();
  static const Object _searchHistoryTapGroupId = 'f5_search_history_popover';
  int _historyHighlightIndex = -1;

  Timer? _debounce;
  bool _isSearching = false;
  String? _notFoundQuery;
  List<Product> _results = [];
  Product? _selectedProduct;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _looksLikeBarcode(String raw) => _barcodePattern.hasMatch(raw.trim());

  void _triggerQuickCreate() {
    final q = _notFoundQuery?.trim();
    final cb = widget.onQuickCreateRequested;
    if (q == null || q.isEmpty || cb == null) return;
    Navigator.of(context).pop();
    cb(q);
  }

  void _triggerAssociateBarcode() {
    final q = _notFoundQuery?.trim();
    final cb = widget.onAssociateBarcodeRequested;
    if (q == null || q.isEmpty || cb == null) return;
    Navigator.of(context).pop();
    cb(q);
  }

  bool _handleKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_searchHistoryPortalController.isShowing) {
        _hideHistoryPopover();
        return true;
      }
      Navigator.of(context).pop();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        _searchHistoryPortalController.isShowing) {
      _hideHistoryPopover();
      return false;
    }
    if (_searchCtrl.text.trim().isEmpty) {
      final localTerminal =
          tryGetLocalTerminalProvider(context, listen: false);
      final catalog = context.read<CatalogProvider>();
      final terms = localTerminal?.recentTermsForScope(
            LocalTerminalProvider.scopePosCounter,
          ) ??
          const <String>[];
      final products = _resolveRecentProducts(catalog, localTerminal);
      final total = terms.length + products.length;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown && total > 0) {
        if (!_searchHistoryPortalController.isShowing) {
          _showHistoryPopoverIfAvailable(initialHighlightIndex: 0);
        } else {
          setState(() {
            _historyHighlightIndex =
                (_historyHighlightIndex + 1).clamp(0, total - 1);
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
          _historyHighlightIndex >= 0) {
        if (_historyHighlightIndex < terms.length) {
          _applyRecentTerm(terms[_historyHighlightIndex]);
          return true;
        }
        final pIdx = _historyHighlightIndex - terms.length;
        if (pIdx >= 0 && pIdx < products.length) {
          _applyRecentProduct(products[pIdx]);
          return true;
        }
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.f3 &&
        _notFoundQuery != null &&
        widget.onQuickCreateRequested != null) {
      _hideHistoryPopover();
      _triggerQuickCreate();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f7 &&
        _selectedProduct != null &&
        widget.onHardwareCalculatorRequested != null &&
        context.read<SettingsProvider>().canUseHardwareCalculator) {
      _hideHistoryPopover();
      final prod = _selectedProduct!;
      Navigator.of(context).pop();
      widget.onHardwareCalculatorRequested!(prod);
      return true;
    }
    return false;
  }

  List<Product> _resolveRecentProducts(
    CatalogProvider catalog,
    LocalTerminalProvider? localTerminal,
  ) {
    final ids = localTerminal?.recentProductIdsForScope(
          LocalTerminalProvider.scopePosCounter,
        ) ??
        const <int>[];
    if (ids.isEmpty) return const [];
    final resolved = catalog.resolveRecentProducts(ids, activeOnly: true);
    final missing = catalog.unhydratedRecentProductIds(ids);
    if (missing.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(catalog.syncPinnedProducts(missing));
      });
    }
    return resolved;
  }

  bool _hasHistoryEntries(
    CatalogProvider catalog,
    LocalTerminalProvider? localTerminal,
  ) {
    if (localTerminal == null) return false;
    final terms = localTerminal.recentTermsForScope(
      LocalTerminalProvider.scopePosCounter,
    );
    if (terms.isNotEmpty) return true;
    return _resolveRecentProducts(catalog, localTerminal).isNotEmpty;
  }

  void _showHistoryPopoverIfAvailable({int initialHighlightIndex = -1}) {
    if (!mounted || _searchCtrl.text.trim().isNotEmpty) return;
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    final catalog = context.read<CatalogProvider>();
    if (!_hasHistoryEntries(catalog, localTerminal)) return;
    if (_historyHighlightIndex != initialHighlightIndex) {
      setState(() => _historyHighlightIndex = initialHighlightIndex);
    }
    if (!_searchHistoryPortalController.isShowing) {
      _searchHistoryPortalController.show();
    }
  }

  void _hideHistoryPopover() {
    if (_historyHighlightIndex != -1 && mounted) {
      setState(() => _historyHighlightIndex = -1);
    } else {
      _historyHighlightIndex = -1;
    }
    if (_searchHistoryPortalController.isShowing) {
      _searchHistoryPortalController.hide();
    }
  }

  void _recordHistory({String? term, Product? product}) {
    if (product != null) {
      try {
        context.read<CatalogProvider>().registerRecentlySeenProducts([product]);
      } catch (_) {}
    }
    final validTerm =
        (term != null && LocalTerminalProvider.isValidRecentSearchTerm(term))
            ? term
            : null;
    final productId = (product != null && product.active) ? product.id : null;
    if (validTerm == null && productId == null) return;
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    if (localTerminal == null) return;
    unawaited(localTerminal.recordRecentSearchForScope(
      LocalTerminalProvider.scopePosCounter,
      term: validTerm,
      selectedProductId: productId,
    ));
  }

  Future<void> _applyRecentTerm(String term) async {
    final clean = term.trim();
    if (clean.isEmpty || !mounted) return;
    _hideHistoryPopover();
    _debounce?.cancel();
    _searchCtrl.text = clean;
    _searchCtrl.selection = TextSelection.collapsed(offset: clean.length);
    setState(() {
      _isSearching = true;
      _notFoundQuery = null;
    });
    _searchFocus.requestFocus();
    await _executeRemoteSearch(clean, selectOnSingleOrExact: true);
  }

  void _applyRecentProduct(Product product) {
    _hideHistoryPopover();
    _debounce?.cancel();
    _recordHistory(product: product);
    setState(() {
      _searchCtrl.clear();
      _results = [product];
      _selectedProduct = product;
      _isSearching = false;
      _notFoundQuery = null;
    });
    _searchFocus.requestFocus();
  }

  List<Product> _searchLocalCatalog(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];

    try {
      final catalog = context.read<CatalogProvider>();
      final seenIds = <int>{};
      final combined = <Product>[];
      for (final source in [
        catalog.activeProducts,
        catalog.pinnedExtraProducts,
        catalog.weightOnlyProducts,
      ]) {
        for (final p in source) {
          if (seenIds.add(p.id) && p.active) {
            combined.add(p);
          }
        }
      }

      final exact = <Product>[];
      final partial = <Product>[];
      for (final p in combined) {
        final barcode = p.barcode?.trim().toLowerCase() ?? '';
        final code = p.internalCode.trim().toLowerCase();
        final sku = p.supplierSku?.trim().toLowerCase() ?? '';
        if (barcode == q || code == q || sku == q) {
          exact.add(p);
        } else if (matchesSpanishSearchQuery(q, [
          p.name,
          p.barcode,
          p.internalCode,
          p.supplierSku,
          p.technicalSpec,
        ])) {
          partial.add(p);
        }
      }
      return [...exact, ...partial].take(20).toList();
    } catch (_) {
      return const [];
    }
  }

  Product? _findExactBarcodeOrCode(List<Product> items, String rawQuery) =>
      RemoteScannerService.findExactProductMatch(items, rawQuery);

  void _handleRemoteBarcodeScan(String barcode) {
    final clean = barcode.trim();
    if (clean.isEmpty || !mounted) return;
    _searchCtrl.text = clean;
    _searchCtrl.selection = TextSelection.collapsed(offset: clean.length);
    _onSubmitted(clean);
  }

  void _onQueryChanged(String rawValue) {
    _debounce?.cancel();
    final q = rawValue.trim();
    if (q.isNotEmpty) {
      _hideHistoryPopover();
    }
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _notFoundQuery = null;
        _historyHighlightIndex = -1;
      });
      return;
    }

    final local = _searchLocalCatalog(q);
    final exactLocal = _findExactBarcodeOrCode(local, q);
    setState(() {
      _results = local;
      _notFoundQuery = null;
      _isSearching = true;
      if (exactLocal != null) {
        _selectedProduct = exactLocal;
      } else if (local.length == 1) {
        _selectedProduct = local.first;
      }
    });

    _debounce = Timer(const Duration(milliseconds: 240), () async {
      await _executeRemoteSearch(q, selectOnSingleOrExact: exactLocal == null);
    });
  }

  Future<void> _onSubmitted(String rawValue) async {
    _debounce?.cancel();
    final q = rawValue.trim();
    if (q.isEmpty) return;

    final local = _searchLocalCatalog(q);
    final exactLocal = _findExactBarcodeOrCode(local, q);
    if (exactLocal != null) {
      _selectAndSelectTextForNextScan(exactLocal, local);
      return;
    }

    setState(() {
      _isSearching = true;
      _notFoundQuery = null;
    });
    await _executeRemoteSearch(q, selectOnSingleOrExact: true, fromSubmit: true);
  }

  Future<void> _executeRemoteSearch(
    String query, {
    bool selectOnSingleOrExact = true,
    bool fromSubmit = false,
  }) async {
    try {
      final catalog = context.read<CatalogProvider>();
      final remote = await catalog.searchProductsRemote(query, perPage: 20);
      if (!mounted) return;
      catalog.registerRecentlySeenProducts(remote);
      if (_searchCtrl.text.trim() != query) return;

      final mergedById = <int, Product>{};
      for (final p in _searchLocalCatalog(query)) {
        mergedById[p.id] = p;
      }
      for (final p in remote) {
        if (p.active) mergedById[p.id] = p;
      }
      final merged = mergedById.values.toList();
      final exact = _findExactBarcodeOrCode(merged, query);

      if (selectOnSingleOrExact && (exact != null || merged.length == 1)) {
        final chosen = exact ?? merged.first;
        if (fromSubmit) {
          _selectAndSelectTextForNextScan(chosen, merged);
        } else {
          _recordHistory(term: query, product: chosen);
          setState(() {
            _results = merged;
            _selectedProduct = chosen;
            _isSearching = false;
            _notFoundQuery = null;
          });
        }
        return;
      }

      if (merged.isNotEmpty) {
        _recordHistory(
          term: query,
          product: fromSubmit ? merged.first : null,
        );
      }

      setState(() {
        _results = merged;
        _isSearching = false;
        _notFoundQuery = merged.isEmpty ? query : null;
        if (fromSubmit && merged.isNotEmpty) {
          _selectedProduct = merged.first;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          if (_results.isEmpty) _notFoundQuery = query;
        });
      }
    }
  }

  void _selectAndSelectTextForNextScan(Product product, List<Product> results) {
    _hideHistoryPopover();
    _recordHistory(term: _searchCtrl.text.trim(), product: product);
    setState(() {
      _results = results;
      _selectedProduct = product;
      _isSearching = false;
      _notFoundQuery = null;
    });
    _searchFocus.requestFocus();
    _searchCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchCtrl.text.length,
    );
  }

  void _resetLookup() {
    _debounce?.cancel();
    _hideHistoryPopover();
    setState(() {
      _searchCtrl.clear();
      _results = [];
      _selectedProduct = null;
      _notFoundQuery = null;
      _isSearching = false;
    });
    _searchFocus.requestFocus();
  }

  Widget _buildHistoryOverlay(
    BuildContext overlayContext,
    OverlayChildLayoutInfo info,
  ) {
    return PosSearchHistoryPopover.buildAnchoredOverlay(
      info: info,
      maxWidth: 560.0,
      maxOverlayHeight: 340.0,
      child: Consumer3<CatalogProvider, PosProvider, OfferProvider>(
        builder: (ctx, catalog, pos, offerProv, _) {
          final localTerminal = tryGetLocalTerminalProvider(ctx, listen: true);
          final terms = localTerminal?.recentTermsForScope(
                LocalTerminalProvider.scopePosCounter,
              ) ??
              const <String>[];
          final products = _resolveRecentProducts(catalog, localTerminal);

          if (localTerminal == null || (terms.isEmpty && products.isEmpty)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _hideHistoryPopover();
            });
            return const SizedBox.shrink();
          }

          return PosSearchHistoryPopover(
            containerKey: const ValueKey('f5_search_history_overlay'),
            terms: terms,
            products: products,
            highlightedIndex: _historyHighlightIndex,
            tapGroupId: _searchHistoryTapGroupId,
            maxWidth: 560.0,
            maxHeight: 340.0,
            productActionIcon: Icons.visibility_outlined,
            onDismiss: _hideHistoryPopover,
            onClearAll: () {
              unawaited(localTerminal.clearRecentSearchesForScope(
                LocalTerminalProvider.scopePosCounter,
              ));
              _hideHistoryPopover();
              _searchFocus.requestFocus();
            },
            onSelectTerm: _applyRecentTerm,
            onRemoveTerm: (term) {
              final willBeEmpty = terms.length <= 1 && products.isEmpty;
              unawaited(localTerminal.removeRecentTermForScope(
                LocalTerminalProvider.scopePosCounter,
                term,
              ));
              if (willBeEmpty) {
                _hideHistoryPopover();
              } else if (_historyHighlightIndex != -1) {
                setState(() => _historyHighlightIndex = -1);
              }
            },
            onSelectProduct: _applyRecentProduct,
            onRemoveProduct: (productId) {
              final willBeEmpty = products.length <= 1 && terms.isEmpty;
              unawaited(localTerminal.removeRecentProductIdForScope(
                LocalTerminalProvider.scopePosCounter,
                productId,
              ));
              if (willBeEmpty) {
                _hideHistoryPopover();
              } else if (_historyHighlightIndex != -1) {
                setState(() => _historyHighlightIndex = -1);
              }
            },
            priceResolver: (p) {
              final promoPrice = offerProv.getDiscountedPrice(p);
              final hasOffer = promoPrice != null &&
                  promoPrice > 0 &&
                  promoPrice < p.sellingPrice;
              final calc = ProductPricingCalculator.calculate(
                product: p,
                activeTier: pos.activeTier,
                wholesaleFactor: pos.wholesaleFactor,
                cardFactor: pos.cardFactor,
                customFactor: pos.currentCustomFactor,
                promotionalPrice: promoPrice,
                hasExplicitOffer: hasOffer,
                cardSurchargeOnOffersMode: pos.cardSurchargeOnOffersMode,
                discountTierOnOffersMode: pos.discountTierOnOffersMode,
                ignoreFixedPrices: pos.ignoreProductFixedPrices,
              );
              return (
                price: calc.finalUnitPrice,
                crossedOutPrice: calc.crossedOutPrice,
                hasActiveOffer: calc.hasActiveOffer,
              );
            },
          );
        },
      ),
    );
  }

  String _formatIngredientQty(double qty) {
    if ((qty - qty.roundToDouble()).abs() < 0.0005) {
      return '${qty.round()}u';
    }
    return '${qty.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}u';
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final offerProv = context.watch<OfferProvider>();
    SettingsProvider? settingsProv;
    try {
      settingsProv = context.watch<SettingsProvider>();
    } on ProviderNotFoundException catch (_) {
      settingsProv = context.watch<SettingsProvider?>();
    }
    final settings = settingsProv?.settings;
    final isResponsableInscripto = settings?.isResponsableInscripto ?? false;

    final product = _selectedProduct;

    List<ProductPriceTierPreview> multiPricePreviews = const [];
    double? promoPrice;
    String? promoName;

    if (product != null) {
      final discounted = offerProv.getDiscountedPrice(product);
      if (discounted != null &&
          discounted > 0 &&
          discounted < product.sellingPrice) {
        promoPrice = ProductPricingCalculator.roundMoney(discounted);
        promoName = offerProv
            .getActiveOfferForProduct(product.id, basePrice: product.sellingPrice)
            ?.name;
      }

      multiPricePreviews = ProductPricingCalculator.buildMultiPricePreviews(
        product: product,
        multiPriceEnabled: settings?.hasMultiPriceEnabled == true,
        wholesaleFactor: settings?.wholesalePriceFactor ?? pos.wholesaleFactor,
        cardFactor: settings?.cardPriceFactor ?? pos.cardFactor,
        customTiers: settings?.customPriceTiers ?? const [],
        promotionalPrice: promoPrice,
        hasExplicitOffer: promoPrice != null,
        cardSurchargeOnOffersMode: pos.cardSurchargeOnOffersMode,
        discountTierOnOffersMode: pos.discountTierOnOffersMode,
        ignoreFixedPrices: settings?.ignoreProductFixedPrices ??
            pos.ignoreProductFixedPrices,
      );
    }

    return RemoteScannerListener(
      debugLabel: 'PosPriceLookupDialog',
      onBarcodeScanned: _handleRemoteBarcodeScan,
      child: AppModalShell(
        title: 'Consultar Precio sin Agregar (F5)',
        subtitle:
            'Pistoleá el código de barras o buscá por nombre para verificar lista, oferta y stock',
        icon: Icons.qr_code_scanner_rounded,
        accent: AppModalAccent.blue,
        maxWidth: 680,
        expandBody: false,
        topBar: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          // Campo de escaneo/búsqueda (mantiene foco continuo en Enter USB) + Popover historial
          child: TapRegion(
            groupId: _searchHistoryTapGroupId,
            child: OverlayPortal.overlayChildLayoutBuilder(
              controller: _searchHistoryPortalController,
              overlayChildBuilder: _buildHistoryOverlay,
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                autofocus: true,
                onTap: () {
                  if (_searchCtrl.text.trim().isEmpty) {
                    _showHistoryPopoverIfAvailable();
                  }
                },
                onChanged: _onQueryChanged,
                onEditingComplete: () {},
                onSubmitted: _onSubmitted,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Escaneá código de barras o escribí nombre / SKU...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              tooltip: 'Limpiar',
                              onPressed: _resetLookup,
                            )
                          : Builder(
                              builder: (ctx) {
                                final localTerminal =
                                    tryGetLocalTerminalProvider(
                                  ctx,
                                  listen: true,
                                );
                                final catalog = ctx.watch<CatalogProvider>();
                                if (!_hasHistoryEntries(
                                  catalog,
                                  localTerminal,
                                )) {
                                  return const SizedBox.shrink();
                                }
                                return Focus(
                                  canRequestFocus: false,
                                  descendantsAreFocusable: false,
                                  child: Tooltip(
                                    message: 'Búsquedas recientes',
                                    child: IconButton(
                                      key: const ValueKey(
                                        'f5_search_history_toggle_btn',
                                      ),
                                      icon: Icon(
                                        Icons.history_rounded,
                                        size: 20,
                                        color: _searchHistoryPortalController
                                                .isShowing
                                            ? AppColors.primary
                                            : Colors.blueGrey.shade600,
                                      ),
                                      onPressed: () {
                                        if (_searchHistoryPortalController
                                            .isShowing) {
                                          _hideHistoryPopover();
                                        } else {
                                          _showHistoryPopoverIfAvailable();
                                        }
                                        _searchFocus.requestFocus();
                                      },
                                    ),
                                  ),
                                );
                              },
                            )),
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        bodyPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lista de coincidencias múltiples
            if (_results.length > 1) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 155),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, thickness: 0.6),
                      itemBuilder: (ctx, idx) {
                        final item = _results[idx];
                        final isSelected = product?.id == item.id;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: AppColors.primarySoft,
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            [
                              (item.barcode != null &&
                                      item.barcode!.trim().isNotEmpty)
                                  ? item.barcode!
                                  : (item.internalCode.trim().isNotEmpty
                                      ? item.internalCode
                                      : (item.supplierSku != null &&
                                              item.supplierSku!
                                                  .trim()
                                                  .isNotEmpty
                                          ? item.supplierSku!
                                          : 'Sin código')),
                              if (item.technicalSpec != null &&
                                  item.technicalSpec!.trim().isNotEmpty)
                                item.technicalSpec!.trim(),
                              if (item.storageLocation != null &&
                                  item.storageLocation!.trim().isNotEmpty)
                                'Ubic: ${item.storageLocation!.trim()}',
                              'Stock: ${item.stock.toUnitStockDisplay(isSoldByWeight: item.isSoldByWeight, unitSuffix: item.unitShortLabel, weightUnit: item.unitShortLabel)}',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            '\$${item.sellingPrice.toCurrency()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          onTap: () =>
                              _selectAndSelectTextForNextScan(item, _results),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],

            if (_notFoundQuery != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          color: Colors.amber.shade900,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No se encontró ningún producto activo para "$_notFoundQuery".',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.onQuickCreateRequested != null ||
                        (widget.onAssociateBarcodeRequested != null &&
                            _looksLikeBarcode(_notFoundQuery!))) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (widget.onQuickCreateRequested != null)
                            ElevatedButton.icon(
                              onPressed: _triggerQuickCreate,
                              icon:
                                  const Icon(Icons.flash_on_rounded, size: 17),
                              label: const Text('Producto Rápido (F3)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                            ),
                          if (widget.onAssociateBarcodeRequested != null &&
                              _looksLikeBarcode(_notFoundQuery!))
                            OutlinedButton.icon(
                              onPressed: _triggerAssociateBarcode,
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 16,
                              ),
                              label: const Text('Asociar código a existente'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF92400E),
                                side: BorderSide(color: Colors.amber.shade400),
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (product == null &&
                _results.isEmpty &&
                !_isSearching) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 28,
                      color: AppColors.textMuted,
                    ),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Listo para escanear. No modifica tu carrito actual.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (product != null) ...[
              if (_results.length > 1) const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre y badges
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (product.isCombo)
                          _LookupBadge(
                            label: 'Combo / Pack',
                            color: AppColors.indigo,
                            bgColor: Colors.indigo.shade50,
                          ),
                        if (product.isSoldByWeight)
                          _LookupBadge(
                            label: product.unitShortLabel != 'Kg'
                                ? 'Venta Fraccionada (${product.unitShortLabel})'
                                : 'Venta por Peso (Kg)',
                            color: Colors.indigo.shade700,
                            bgColor: Colors.indigo.shade50,
                          ),
                        if (product.isService)
                          _LookupBadge(
                            label: 'Servicio',
                            color: Colors.teal.shade800,
                            bgColor: Colors.teal.shade50,
                          ),
                        if (isResponsableInscripto)
                          _LookupBadge(
                            label: product.ivaRate <= 0
                                ? 'Exento 0%'
                                : 'IVA ${product.ivaRate == product.ivaRate.roundToDouble() ? product.ivaRate.round() : product.ivaRate}%',
                            color: Colors.blueGrey.shade800,
                            bgColor: Colors.blueGrey.shade100,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (product.barcode != null &&
                            product.barcode!.trim().isNotEmpty)
                          'EAN: ${product.barcode}',
                        if (product.internalCode.trim().isNotEmpty)
                          'Cód: ${product.internalCode}',
                        if (product.supplierSku != null &&
                            product.supplierSku!.trim().isNotEmpty)
                          'Cód. Prov: ${product.supplierSku!.trim()}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if ((product.storageLocation != null &&
                            product.storageLocation!.trim().isNotEmpty) ||
                        (product.technicalSpec != null &&
                            product.technicalSpec!.trim().isNotEmpty)) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (product.storageLocation != null &&
                              product.storageLocation!.trim().isNotEmpty)
                            _LookupBadge(
                              icon: Icons.place_outlined,
                              label:
                                  'Ubic: ${product.storageLocation!.trim()}',
                              color: Colors.amber.shade900,
                              bgColor: Colors.amber.shade50,
                            ),
                          if (product.technicalSpec != null &&
                              product.technicalSpec!.trim().isNotEmpty)
                            _LookupBadge(
                              icon: Icons.straighten_outlined,
                              label: product.technicalSpec!.trim(),
                              color: Colors.blueGrey.shade800,
                              bgColor: Colors.blueGrey.shade100,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Precio Principal + Oferta activa
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: promoPrice != null
                                    ? Colors.amber.shade400
                                    : AppColors.primaryBorder,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  promoPrice != null
                                      ? 'PRECIO OFERTA HOY${promoName != null ? ' ($promoName)' : ''}'
                                      : 'PRECIO LISTA / MOSTRADOR',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: promoPrice != null
                                        ? const Color(0xFFB45309)
                                        : AppColors.primaryDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    if (promoPrice != null) ...[
                                      Text(
                                        '\$${product.sellingPrice.toCurrency()}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade500,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Flexible(
                                      child: Text(
                                        '\$${(promoPrice ?? product.sellingPrice).toCurrency()}${product.isSoldByWeight ? ' /${product.unitShortLabel}' : ''}',
                                        style: TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w900,
                                          color: promoPrice != null
                                              ? const Color(0xFFB45309)
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: product.isService
                                ? Colors.teal.shade50
                                : (product.stock > 0
                                    ? Colors.green.shade50
                                    : Colors.red.shade50),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: product.isService
                                  ? Colors.teal.shade200
                                  : (product.stock > 0
                                      ? Colors.green.shade200
                                      : Colors.red.shade200),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'STOCK',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                product.isService
                                    ? 'Servicio'
                                    : product.stock.toUnitStockDisplay(
                                        isSoldByWeight: product.isSoldByWeight,
                                        unitSuffix: product.unitShortLabel,
                                        weightUnit: product.unitShortLabel,
                                      ),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: product.isService
                                      ? Colors.teal.shade800
                                      : (product.stock > 0
                                          ? Colors.green.shade800
                                          : Colors.red.shade800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (multiPricePreviews.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      // Listas de precios
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: multiPricePreviews
                            .map(
                              (preview) => _PriceTierCard(
                                label:
                                    '${preview.label}${preview.isFixedOverride ? ' (Fijo)' : ''}',
                                priceText:
                                    '\$${preview.price.toCurrency()}${product.isSoldByWeight ? '/${product.unitShortLabel}' : ''}',
                              ),
                            )
                            .toList(),
                      ),
                    ],

                    if (product.isCombo &&
                        product.comboIngredients != null &&
                        product.comboIngredients!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Composición del Combo:',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.indigo,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: product.comboIngredients!.map((ing) {
                          final qty =
                              (ing['quantity'] as num?)?.toDouble() ?? 1.0;
                          final name =
                              ing['name']?.toString() ?? 'Ingrediente';
                          return Chip(
                            label: Text(
                              '${_formatIngredientQty(qty)} $name',
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.indigo.shade50,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
        footerLeading: TextButton.icon(
          onPressed: _resetLookup,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Limpiar / Otra consulta'),
        ),
        footerActions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar (Esc)'),
          ),
          if (product != null &&
              widget.onHardwareCalculatorRequested != null &&
              (settingsProv?.canUseHardwareCalculator == true))
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onHardwareCalculatorRequested!(product);
              },
              icon: const Icon(Icons.straighten_rounded, size: 17),
              label: const Text('Calcular Superficie (F7)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.tealDark,
                side: const BorderSide(color: AppColors.tealDark),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          if (product != null && widget.canAddToCart)
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(product),
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: const Text('Agregar al carrito'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LookupBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;
  final IconData? icon;

  const _LookupBadge({
    required this.label,
    required this.color,
    required this.bgColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceTierCard extends StatelessWidget {
  final String label;
  final String priceText;

  const _PriceTierCard({
    required this.label,
    required this.priceText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            priceText,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
