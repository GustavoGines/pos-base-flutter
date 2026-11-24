import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/presentation/widgets/compact_date_range_picker_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/pos_search_history_popover.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_hardware_calculator_dialog.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import '../providers/quote_provider.dart';
import '../../data/quote_repository.dart';
import '../widgets/quote_success_dialog.dart';
import 'package:intl/intl.dart';

class QuoteScreen extends StatefulWidget {
  const QuoteScreen({super.key});

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchHistoryPortalController = OverlayPortalController();
  static const Object _searchHistoryTapGroupId =
      'quote_search_history_popover';
  int _historyHighlightIndex = -1;

  String _searchQuery = '';
  List<Product> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounceTimer;

  // Formulario del encabezado del presupuesto
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _validUntil = DateTime.now().add(const Duration(days: 7));

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleQuoteHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
      // Inyectar los factores globales de precios al provider de presupuestos
      final settings = context.read<SettingsProvider>().settings;
      if (settings != null) {
        final ws = settings.globalWholesalePercentage != 0
            ? settings.wholesalePriceFactor
            : 1.0;
        final card = settings.globalCardPercentage != 0
            ? settings.cardPriceFactor
            : 1.0;
        context.read<QuoteProvider>().setGlobalFactors(
              wholesale: ws,
              card: card,
              ignoreFixedPrices: settings.ignoreProductFixedPrices,
            );
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleQuoteHardwareKey);
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool _handleQuoteHardwareKey(KeyEvent event) {
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
    if (_searchCtrl.text.trim().isEmpty &&
        (_searchFocus.hasFocus || _searchHistoryPortalController.isShowing)) {
      final localTerminal =
          tryGetLocalTerminalProvider(context, listen: false);
      final catalog = context.read<CatalogProvider>();
      final terms = localTerminal?.recentTermsForScope(
            LocalTerminalProvider.scopeQuotes,
          ) ??
          const <String>[];
      final products = _resolveRecentQuoteProducts(catalog, localTerminal);
      final total = terms.length + products.length;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown && total > 0) {
        if (!_searchHistoryPortalController.isShowing) {
          _showSearchHistoryPopoverIfAvailable(initialHighlightIndex: 0);
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
          _applyRecentQuoteTerm(terms[_historyHighlightIndex]);
          return true;
        }
        final pIdx = _historyHighlightIndex - terms.length;
        if (pIdx >= 0 && pIdx < products.length) {
          final prod = products[pIdx];
          _hideSearchHistoryPopover();
          _recordQuoteHistory(product: prod);
          _addProduct(prod);
          return true;
        }
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.f7) {
      final settingsProv = context.read<SettingsProvider>();
      final rubros = Provider.of<CatalogProvider?>(context, listen: false)?.safeRubros ??
          const [];
      if (settingsProv.canUseHardwareCalculatorFor(rubros: rubros)) {
        _hideSearchHistoryPopover();
        _openHardwareCalculator();
        return true;
      }
    }
    return false;
  }

  List<Product> _resolveRecentQuoteProducts(
    CatalogProvider catalog,
    LocalTerminalProvider? localTerminal,
  ) {
    final ids = localTerminal?.recentProductIdsForScope(
          LocalTerminalProvider.scopeQuotes,
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

  bool _hasQuoteHistoryEntries(
    CatalogProvider catalog,
    LocalTerminalProvider? localTerminal,
  ) {
    if (localTerminal == null) return false;
    final terms =
        localTerminal.recentTermsForScope(LocalTerminalProvider.scopeQuotes);
    if (terms.isNotEmpty) return true;
    return _resolveRecentQuoteProducts(catalog, localTerminal).isNotEmpty;
  }

  void _showSearchHistoryPopoverIfAvailable({int initialHighlightIndex = -1}) {
    if (!mounted || _searchCtrl.text.trim().isNotEmpty) return;
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    final catalog = context.read<CatalogProvider>();
    if (!_hasQuoteHistoryEntries(catalog, localTerminal)) return;
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

  void _recordQuoteHistory({String? term, Product? product}) {
    if (product != null) {
      try {
        context.read<CatalogProvider>().registerRecentlySeenProducts([product]);
      } catch (_) {}
    }
    final validTerm =
        (term != null && LocalTerminalProvider.isValidRecentSearchTerm(term))
            ? term
            : null;
    final prodId = (product != null && product.active) ? product.id : null;
    if (validTerm == null && prodId == null) return;
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    if (localTerminal == null) return;
    unawaited(localTerminal.recordRecentSearchForScope(
      LocalTerminalProvider.scopeQuotes,
      term: validTerm,
      selectedProductId: prodId,
    ));
  }

  void _applyRecentQuoteTerm(String term) {
    final clean = term.trim();
    if (clean.isEmpty || !mounted) return;
    _hideSearchHistoryPopover();
    _searchCtrl.text = clean;
    _searchCtrl.selection = TextSelection.collapsed(offset: clean.length);
    _onSearchChanged(clean);
    _recordQuoteHistory(term: clean);
    _searchFocus.requestFocus();
  }

  Widget _buildSearchHistoryOverlay(
    BuildContext overlayContext,
    OverlayChildLayoutInfo info,
  ) {
    return PosSearchHistoryPopover.buildAnchoredOverlay(
      info: info,
      maxWidth: 560.0,
      maxOverlayHeight: 360.0,
      child: Consumer<CatalogProvider>(
        builder: (ctx, catalog, _) {
          final localTerminal = tryGetLocalTerminalProvider(ctx, listen: true);
          final terms = localTerminal?.recentTermsForScope(
                LocalTerminalProvider.scopeQuotes,
              ) ??
              const <String>[];
          final products =
              _resolveRecentQuoteProducts(catalog, localTerminal);

          if (localTerminal == null || (terms.isEmpty && products.isEmpty)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _hideSearchHistoryPopover();
            });
            return const SizedBox.shrink();
          }

          return PosSearchHistoryPopover(
            containerKey: const ValueKey('quote_search_history_overlay'),
            terms: terms,
            products: products,
            highlightedIndex: _historyHighlightIndex,
            tapGroupId: _searchHistoryTapGroupId,
            maxWidth: 560.0,
            maxHeight: 360.0,
            onDismiss: _hideSearchHistoryPopover,
            onClearAll: () {
              unawaited(localTerminal.clearRecentSearchesForScope(
                LocalTerminalProvider.scopeQuotes,
              ));
              _hideSearchHistoryPopover();
              _searchFocus.requestFocus();
            },
            onSelectTerm: _applyRecentQuoteTerm,
            onRemoveTerm: (term) {
              final willBeEmpty = terms.length <= 1 && products.isEmpty;
              unawaited(localTerminal.removeRecentTermForScope(
                LocalTerminalProvider.scopeQuotes,
                term,
              ));
              if (willBeEmpty) {
                _hideSearchHistoryPopover();
              } else if (_historyHighlightIndex != -1) {
                setState(() => _historyHighlightIndex = -1);
              }
            },
            onSelectProduct: (p) {
              _hideSearchHistoryPopover();
              _recordQuoteHistory(product: p);
              _addProduct(p);
            },
            onRemoveProduct: (productId) {
              final willBeEmpty = products.length <= 1 && terms.isEmpty;
              unawaited(localTerminal.removeRecentProductIdForScope(
                LocalTerminalProvider.scopeQuotes,
                productId,
              ));
              if (willBeEmpty) {
                _hideSearchHistoryPopover();
              } else if (_historyHighlightIndex != -1) {
                setState(() => _historyHighlightIndex = -1);
              }
            },
            priceResolver: (p) => (
              price: _resolvePreviewPrice(p),
              crossedOutPrice: null,
              hasActiveOffer: false,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openHardwareCalculator({
    Product? initialProduct,
    CartItem? replacingCartItem,
  }) async {
    final settingsProv = context.read<SettingsProvider>();
    final rubros = Provider.of<CatalogProvider?>(context, listen: false)?.safeRubros ??
        const [];
    if (!settingsProv.canUseHardwareCalculatorFor(
      product: initialProduct,
      rubros: rubros,
    )) {
      return;
    }
    final out = await PosHardwareCalculatorDialog.show(
      context,
      initialProduct: initialProduct,
      replacingCartItem: replacingCartItem,
      target: HardwareCalculatorTarget.quote,
    );
    if (!mounted) return;
    if (out != null &&
        out.searchComplementKeyword != null &&
        out.searchComplementKeyword!.trim().isNotEmpty) {
      final kw = out.searchComplementKeyword!.trim();
      _searchCtrl.text = kw;
      _searchCtrl.selection = TextSelection.collapsed(offset: kw.length);
      _onSearchChanged(kw);
    }
    _searchFocus.requestFocus();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    final q = value.trim();
    if (q.isNotEmpty) {
      _hideSearchHistoryPopover();
    }
    if (q.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _isSearching = false;
        _historyHighlightIndex = -1;
      });
      return;
    }
    setState(() => _searchQuery = q);
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted || _searchQuery.isEmpty) return;
      setState(() => _isSearching = true);
      final results = (await context.read<PosProvider>().search(q))
          .where((p) => p.active)
          .toList();
      if (!mounted) return;
      context.read<CatalogProvider>().registerRecentlySeenProducts(results);
      if (results.isNotEmpty) {
        _recordQuoteHistory(term: q);
      }
      setState(() { _searchResults = results; _isSearching = false; });
    });
  }

  Future<void> _onSearchSubmittedOrScanned(String rawQuery) async {
    _hideSearchHistoryPopover();
    final q = rawQuery.trim();
    if (q.isEmpty || !mounted) return;
    _debounceTimer?.cancel();
    _searchCtrl.text = q;
    _searchCtrl.selection = TextSelection.collapsed(offset: q.length);
    setState(() {
      _searchQuery = q;
      _isSearching = true;
    });

    try {
      final rawResults = await context.read<PosProvider>().search(q);
      if (!mounted) return;
      final results = rawResults.where((p) => p.active).toList();
      context.read<CatalogProvider>().registerRecentlySeenProducts(results);
      final exact = RemoteScannerService.findExactProductMatch(results, q);
      final Product? match = exact ??
          (results.length == 1 && results.first.active ? results.first : null);
      if (match != null) {
        setState(() => _isSearching = false);
        _recordQuoteHistory(term: q, product: match);
        _addProduct(match);
        return;
      }
      if (results.isEmpty) {
        final catalog = context.read<CatalogProvider>();
        var inactiveExact = RemoteScannerService.findExactProductMatch(
          catalog.products.where((p) => !p.active),
          q,
          activeOnly: false,
        );
        if (inactiveExact == null &&
            RegExp(r'^[A-Za-z0-9\-_]{3,32}$').hasMatch(q)) {
          final remoteAll = await catalog.searchProductsRemote(
            q,
            perPage: 10,
            activeOnly: false,
          );
          if (!mounted) return;
          inactiveExact = RemoteScannerService.findExactProductMatch(
            remoteAll.where((p) => !p.active),
            q,
            activeOnly: false,
          );
        }
        if (inactiveExact != null) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
          SnackBarService.warning(
            context,
            'El producto "${inactiveExact.name}" está dado de baja (inactivo) y no puede agregarse.',
          );
          return;
        }
      }
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
      if (results.isEmpty) {
        SnackBarService.info(
          context,
          'No se encontraron productos para "$q".',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _addProduct(Product product) {
    if (!product.active) {
      SnackBarService.warning(
        context,
        'El producto "${product.name}" está dado de baja (inactivo).',
      );
      return;
    }
    final activeSearch = _searchCtrl.text.trim();
    if (activeSearch.isNotEmpty) {
      _recordQuoteHistory(term: activeSearch, product: product);
    }
    if (product.isSoldByWeight) {
      _showWeightDialog(product);
    } else {
      context.read<QuoteProvider>().addToCart(product);
      _searchCtrl.clear();
      setState(() { _searchQuery = ''; _searchResults = []; });
      _searchFocus.requestFocus();
    }
  }

  void _showWeightDialog(Product product) {
    final settingsProv = context.read<SettingsProvider>();
    final rubros = Provider.of<CatalogProvider?>(context, listen: false)?.safeRubros ??
        const [];
    final businessUsesScale =
        settingsProv.safeVerticalProfile.canUseScaleWeight;
    final preferDiscreteUn = product.isDiscreteFractionalItem(
      businessUsesScaleWeight: businessUsesScale,
    );
    final isHardwareStore = settingsProv.safeIsHardwareStore;
    final canUseCalc = settingsProv.canUseHardwareCalculatorFor(
      product: product,
      rubros: rubros,
    );
    final isMetricOrHardware = isHardwareStore ||
        product.isMetricOrLiquidUnit ||
        preferDiscreteUn ||
        !businessUsesScale;
    final unitShort = Product.resolveQuantityUnitLabel(
      unitType: product.unitType,
      isSoldByWeight: product.isSoldByWeight,
      preferDiscreteUn: preferDiscreteUn,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => _QuoteFractionalQuantityDialog(
        product: product,
        unitShort: unitShort,
        isMetricOrHardware: isMetricOrHardware,
        canUseCalc: canUseCalc,
        onConfirm: (qty) {
          context.read<QuoteProvider>().addToCart(product, quantity: qty);
          _searchCtrl.clear();
          setState(() {
            _searchQuery = '';
            _searchResults = [];
          });
          _searchFocus.requestFocus();
        },
        onOpenCalculator: () => _openHardwareCalculator(initialProduct: product),
      ),
    );
  }

  // -- Generar el presupuesto ------------------------------------------------
  Future<void> _onGenerateQuote() async {
    final provider = context.read<QuoteProvider>();
    if (provider.cart.isEmpty) {
      SnackBarService.error(context, 'Agregue al menos un producto al presupuesto.');
      return;
    }

    // -- Diálogo de confirmación con datos del cliente ---------------------
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _QuoteHeaderDialog(
        nameCtrl: _customerNameCtrl,
        phoneCtrl: _customerPhoneCtrl,
        notesCtrl: _notesCtrl,
        validUntil: _validUntil,
        onValidUntilChanged: (d) => setState(() => _validUntil = d),
        total: provider.cartTotal,
      ),
    );

    if (confirmed != true || !mounted) return;

    final settings = context.read<SettingsProvider>().settings;
    final currentUser = context.read<AuthProvider>().currentUser;
    final userId = currentUser?['id'] != null ? int.tryParse(currentUser!['id'].toString()) : null;
    final vendorName = currentUser?['name'] ?? 'VENDEDOR';

    final quote = await provider.generateQuote(
      customerName: _customerNameCtrl.text.trim().isEmpty ? null : _customerNameCtrl.text.trim(),
      customerPhone: _customerPhoneCtrl.text.trim().isEmpty ? null : _customerPhoneCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      validUntil: _validUntil?.toIso8601String().substring(0, 10),
      userId: userId,
    );

    if (!mounted) return;

    if (quote == null) {
      SnackBarService.error(context, provider.errorMessage ?? 'Error al generar presupuesto.');
      return;
    }

    // -- PDF + WhatsApp -----------------------------------------------------
    await _showQuoteSuccessDialog(quote, settings?.companyName ?? 'Mi Negocio', settings, vendorName);
  }

  Future<void> _showQuoteSuccessDialog(
    Quote quote,
    String businessName,
    dynamic settings,
    String vendorName,
  ) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuoteSuccessDialog(
        quote: quote,
        businessName: businessName,
        businessAddress: settings?.address,
        businessPhone: settings?.phone,
        customerPhone: quote.customerPhone,
        vendorName: vendorName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RemoteScannerListener(
      debugLabel: 'QuoteScreen',
      onBarcodeScanned: _onSearchSubmittedOrScanned,
      child: Scaffold(
      appBar: const GlobalAppBar(currentRoute: '/quotes/new', title: 'Nuevo Presupuesto', showBackButton: true),
      body: Row(
        children: [
          // -- Panel Izquierdo: Buscador ------------------------------------
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildSearchBar(),
                Expanded(child: _buildSearchResults()),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
            // -- Panel Derecho: Carrito ---------------------------------------
            Expanded(
              flex: 4,
              child: _buildCart(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers de lista de precios (delegado al QuoteProvider) ─────────────────

  /// Para precios de preview en la grilla — lee el motor CartItem
  double _resolvePreviewPrice(Product p) {
    final qProvider = context.read<QuoteProvider>();
    final ignoreFixed =
        context.read<SettingsProvider>().settings?.ignoreProductFixedPrices ??
            true;
    switch (qProvider.activeTier) {
      case PriceTier.wholesale:
        if (!ignoreFixed && p.priceWholesale != null && p.priceWholesale! > 0) {
          return p.priceWholesale!;
        }
        return p.sellingPrice * qProvider.wholesaleFactor;
      case PriceTier.card:
        if (!ignoreFixed && p.priceCard != null && p.priceCard! > 0) {
          return p.priceCard!;
        }
        return p.sellingPrice * qProvider.cardFactor;
      case PriceTier.custom:
        return p.sellingPrice * qProvider.customFactor;
      case PriceTier.base:
        return p.sellingPrice;
    }
  }

  Widget _buildSearchBar() {
    return Consumer<QuoteProvider>(
      builder: (_, qProvider, __) {
        final appSettings = context.watch<SettingsProvider>().settings;
        final hasMultiPrice = appSettings?.hasAnyAlternativePriceTier == true;
        final tierColor = qProvider.activePriceListColor;
        final customTiers = appSettings?.activeCustomPriceTiers ?? const [];

        final quoteTierItems = <DropdownMenuItem<String>>[
          const DropdownMenuItem(value: 'base', child: Text('Precio Base')),
          if (appSettings?.isWholesaleTierAvailable == true)
            const DropdownMenuItem(
                value: 'wholesale', child: Text('Mayorista')),
          if (appSettings?.isCardTierAvailable == true)
            const DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
          ...customTiers.map((ct) {
            final name = ct['name']?.toString().trim() ?? '';
            return DropdownMenuItem(value: name, child: Text(name));
          }),
        ];
        final rawTierKey =
            _tierToKey(qProvider.activeTier, qProvider.customTierLabel);
        final safeTierKey =
            quoteTierItems.any((item) => item.value == rawTierKey)
                ? rawTierKey
                : 'base';
        if (hasMultiPrice &&
            rawTierKey != safeTierKey &&
            qProvider.activeTier != PriceTier.base) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) qProvider.setPriceTier(PriceTier.base);
          });
        }

        return Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade50,
          child: Row(
            children: [
              Expanded(
                child: TapRegion(
                  groupId: _searchHistoryTapGroupId,
                  child: OverlayPortal.overlayChildLayoutBuilder(
                    controller: _searchHistoryPortalController,
                    overlayChildBuilder: _buildSearchHistoryOverlay,
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onTap: () {
                        if (_searchCtrl.text.trim().isEmpty) {
                          _showSearchHistoryPopoverIfAvailable();
                        }
                      },
                      onChanged: _onSearchChanged,
                      onSubmitted: _onSearchSubmittedOrScanned,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Buscar producto por nombre o código...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                            : _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {
                                        _searchQuery = '';
                                        _searchResults = [];
                                        _historyHighlightIndex = -1;
                                      });
                                    },
                                  )
                                : Consumer<CatalogProvider>(
                                    builder: (ctx, catalog, _) {
                                      final localTerminal =
                                          tryGetLocalTerminalProvider(ctx,
                                              listen: true);
                                      if (!_hasQuoteHistoryEntries(
                                          catalog, localTerminal)) {
                                        return const SizedBox.shrink();
                                      }
                                      return Focus(
                                        canRequestFocus: false,
                                        descendantsAreFocusable: false,
                                        child: Tooltip(
                                          message: 'Búsquedas recientes',
                                          child: IconButton(
                                            key: const ValueKey(
                                                'quote_search_history_toggle_btn'),
                                            icon: Icon(
                                              Icons.history_rounded,
                                              size: 20,
                                              color:
                                                  _searchHistoryPortalController
                                                          .isShowing
                                                      ? const Color(0xFF0F766E)
                                                      : Colors.blueGrey.shade600,
                                            ),
                                            onPressed: () {
                                              if (_searchHistoryPortalController
                                                  .isShowing) {
                                                _hideSearchHistoryPopover();
                                              } else {
                                                _showSearchHistoryPopoverIfAvailable();
                                              }
                                              _searchFocus.requestFocus();
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              if (context.watch<SettingsProvider>().canUseHardwareCalculatorFor(
                    rubros: context.watch<CatalogProvider?>()?.safeRubros ??
                        const [],
                  )) ...[
                const SizedBox(width: 10),
                Tooltip(
                  message:
                      'Calculadora Ferretera: Machimbre, Chapas y Pintura (F7)',
                  child: ElevatedButton.icon(
                    onPressed: () => _openHardwareCalculator(),
                    icon: const Icon(Icons.straighten_rounded, size: 18),
                    label: const Text(
                      'Calculadora (F7)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
              if (hasMultiPrice) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: tierColor, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: safeTierKey,
                      icon: Icon(Icons.expand_more, color: tierColor, size: 18),
                      style: TextStyle(
                        color: tierColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      onChanged: (v) {
                        if (v == null) return;
                        switch (v) {
                          case 'base':
                            qProvider.setPriceTier(PriceTier.base);
                            break;
                          case 'wholesale':
                            qProvider.setPriceTier(PriceTier.wholesale);
                            break;
                          case 'card':
                            qProvider.setPriceTier(PriceTier.card);
                            break;
                          default:
                            // Lista custom del JSON
                            final t = customTiers.firstWhere(
                              (ct) => (ct['name'] ?? '').toString().trim() == v,
                              orElse: () => {'modifier': 0.0},
                            );
                            final mod = (t['modifier'] as num?)?.toDouble() ?? 0.0;
                            qProvider.setPriceTier(
                              PriceTier.custom,
                              customFactor: 1.0 + (mod / 100),
                              customLabel: v,
                            );
                        }
                      },
                      items: quoteTierItems,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _tierToKey(PriceTier tier, String? label) {
    switch (tier) {
      case PriceTier.wholesale: return 'wholesale';
      case PriceTier.card:      return 'card';
      case PriceTier.custom:    return label ?? 'base';
      case PriceTier.base:      return 'base';
    }
  }

  Widget _buildSearchResults() {
    final qProvider = context.watch<QuoteProvider>();
    if (_searchQuery.isEmpty) {
      return _buildQuickAccessGrid();
    }
    if (_searchResults.isEmpty && !_isSearching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Sin resultados para "$_searchQuery"', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _buildProductTile(_searchResults[i], qProvider),
    );
  }

  Widget _buildQuickAccessGrid() {
    final qProvider = context.watch<QuoteProvider>();
    final products = context.watch<CatalogProvider>().activeProducts;
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Busca productos arriba', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _buildProductCard(products[i], qProvider),
    );
  }

  Widget _buildProductCard(Product p, QuoteProvider qProvider) {
    final tierColor = qProvider.activePriceListColor;
    final tierLabel = qProvider.activePriceListLabel;
    final price = _resolvePreviewPrice(p);
    final isBase = qProvider.activeTier == PriceTier.base;
    return InkWell(
      onTap: () => _addProduct(p),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: !isBase ? tierColor.withValues(alpha: 0.5) : Colors.grey.shade200,
            width: !isBase ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(p.isSoldByWeight ? Icons.scale : Icons.inventory_2_outlined,
                size: 28, color: Colors.indigo.shade400),
            const SizedBox(height: 6),
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('\$${price.toCurrency()}',
                style: TextStyle(fontSize: 11, color: tierColor, fontWeight: FontWeight.bold)),
            if (!isBase)
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(tierLabel,
                    style: TextStyle(fontSize: 9, color: tierColor, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductTile(Product p, QuoteProvider qProvider) {
    final tierColor = qProvider.activePriceListColor;
    final tierLabel = qProvider.activePriceListLabel;
    final price = _resolvePreviewPrice(p);
    final isBase = qProvider.activeTier == PriceTier.base;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: p.isSoldByWeight ? Colors.orange.shade50 : Colors.indigo.shade50,
        child: Icon(p.isSoldByWeight ? Icons.scale : Icons.inventory_2_outlined,
            size: 18,
            color: p.isSoldByWeight ? Colors.orange.shade700 : Colors.indigo.shade700),
      ),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Row(
        children: [
          Text('\$${price.toCurrency()}',
              style: TextStyle(color: tierColor, fontSize: 12, fontWeight: FontWeight.bold)),
          if (!isBase)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tierLabel,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: tierColor)),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
        onPressed: () => _addProduct(p),
      ),
      onTap: () => _addProduct(p),
    );
  }


  // -- Carrito ---------------------------------------------------------------

  Widget _buildCart() {
    return Consumer<QuoteProvider>(
      builder: (_, provider, __) {
        final cart = provider.cart;
        final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);

        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade700,
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Presupuesto',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  if (cart.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (dCtx) => AppModalShell(
                          title: '¿Limpiar presupuesto?',
                          icon: Icons.delete_sweep_rounded,
                          accent: AppModalAccent.red,
                          compact: true,
                          maxWidth: 400,
                          useAlertDialogWrapper: true,
                          onClose: () => Navigator.pop(dCtx),
                          bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                          body: const Text(
                            'Se borrarán todos los ítems agregados.',
                          ),
                          footerActions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.danger,
                              ),
                              onPressed: () {
                                provider.clearCart();
                                Navigator.pop(dCtx);
                              },
                              child: const Text('Limpiar'),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.delete_sweep, color: Colors.white70, size: 18),
                      label: const Text('Limpiar', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                ],
              ),
            ),

            // Lista de ítems
            Expanded(
              child: cart.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('Agregá productos para\ngenerar el presupuesto',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _buildCartItem(cart[i], provider),
                    ),
            ),

            // Total + Botón
            if (cart.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(fmt.format(provider.cartTotal),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: Colors.indigo.shade700)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.indigo.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: provider.isLoading ? null : _onGenerateQuote,
                        icon: provider.isLoading
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.description_rounded),
                        label: const Text('Generar Presupuesto',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCartItem(CartItem item, QuoteProvider provider) {
    final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);
    final tierColor = provider.activePriceListColor;
    final tierLabel = provider.activePriceListLabel;
    final isBase = item.activeTier == PriceTier.base;
    final isFractional = (item.quantity - item.quantity.roundToDouble()).abs() > 0.001;
    final settingsProv = context.watch<SettingsProvider>();
    final isHardwareStore = settingsProv.safeIsHardwareStore;
    final businessUsesScale =
        settingsProv.safeVerticalProfile.canUseScaleWeight;
    final preferDiscreteUn = item.product.isDiscreteFractionalItem(
      businessUsesScaleWeight: businessUsesScale,
    );
    final isMetricOrHardware = isHardwareStore ||
        item.product.isMetricOrLiquidUnit ||
        preferDiscreteUn ||
        !businessUsesScale;
    final unitShort = Product.resolveQuantityUnitLabel(
      unitType: item.product.unitType,
      isSoldByWeight: item.product.isSoldByWeight,
      preferDiscreteUn: preferDiscreteUn,
    );
    final qtyDisplay = item.product.isSoldByWeight
        ? '${item.quantity.toQty()} $unitShort'
        : (isFractional
            ? '${item.quantity.toQty()} $unitShort'
            : '${item.quantity.toInt()}');
    final effectiveDetails = item.effectiveReceiptDetails();
    return ListTile(
      dense: true,
      title: Text(item.effectiveDisplayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${fmt.format(item.unitPrice)} x $qtyDisplay',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              if (!isBase) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.1),
                    border: Border.all(color: tierColor.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.customTierLabel ?? tierLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: tierColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (effectiveDetails != null && effectiveDetails.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '📝 $effectiveDetails',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.indigo.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(fmt.format(item.subtotal),
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => provider.removeFromCart(item),
          ),
        ],
      ),
      onTap: () async {
        final ctrl = TextEditingController(
          text: (item.product.isSoldByWeight || isFractional)
              ? item.quantity.toQty()
              : item.quantity.toInt().toString(),
        );
        final canCalc = context.read<SettingsProvider>().canUseHardwareCalculatorFor(
              product: item.product,
              rubros: Provider.of<CatalogProvider?>(context, listen: false)?.safeRubros ??
                  const [],
            );
        bool openCalc = false;
        await showDialog(
          context: context,
          builder: (ctx) => AppModalShell(
            title: 'Editar cantidad - ${item.product.name}',
            icon: Icons.edit_rounded,
            accent: AppModalAccent.indigo,
            compact: true,
            maxWidth: 420,
            useAlertDialogWrapper: true,
            onClose: () => Navigator.pop(ctx),
            bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            body: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: item.product.isSoldByWeight
                    ? (isMetricOrHardware ? 'Cantidad ($unitShort)' : 'Kg')
                    : 'Cantidad',
                suffixText: item.product.isSoldByWeight
                    ? (isMetricOrHardware ? unitShort.toUpperCase() : 'KG')
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            footerActions: [
              if (canCalc && item.product.id > 0)
                TextButton.icon(
                  onPressed: () {
                    openCalc = true;
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.straighten_rounded, size: 17),
                  label: const Text('Recalcular (F7)'),
                ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: () {
                  final qty = double.tryParse(ctrl.text.replaceAll(',', '.'));
                  if (qty != null && qty > 0) {
                    if ((qty - item.quantity).abs() > 0.0005 &&
                        item.customDetails != null &&
                        item.customDetails!.trim().isNotEmpty) {
                      item.customDetails = null;
                    }
                    provider.updateQuantity(item, qty);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Actualizar'),
              ),
            ],
          ),
        );
        ctrl.dispose();
        if (openCalc && mounted) {
          await _openHardwareCalculator(
            initialProduct: item.product,
            replacingCartItem: item,
          );
        }
      },
    );
  }
}

// -- Diálogo de cabecera del presupuesto --------------------------------------

class _QuoteHeaderDialog extends StatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController notesCtrl;
  final DateTime? validUntil;
  final ValueChanged<DateTime?> onValidUntilChanged;
  final double total;

  const _QuoteHeaderDialog({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.notesCtrl,
    required this.validUntil,
    required this.onValidUntilChanged,
    required this.total,
  });

  @override
  State<_QuoteHeaderDialog> createState() => _QuoteHeaderDialogState();
}

class _QuoteHeaderDialogState extends State<_QuoteHeaderDialog> {
  late DateTime? _validUntil;

  @override
  void initState() {
    super.initState();
    _validUntil = widget.validUntil;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);
    return AppModalShell(
      title: 'Datos del Presupuesto',
      subtitle: 'Cliente, vigencia y condiciones comerciales',
      icon: Icons.description_outlined,
      accent: AppModalAccent.indigo,
      compact: true,
      maxWidth: 460,
      onClose: () => Navigator.pop(context, false),
      bodyPadding: const EdgeInsets.all(18),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total del Presupuesto',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  fmt.format(widget.total),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.indigo,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Datos del Cliente (Opcional)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.nameCtrl,
            decoration: InputDecoration(
              labelText: 'Nombre del cliente',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: widget.phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Teléfono (para WhatsApp)',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              helperText: 'Ej: 5491123456789 (con código de país)',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              const Text('Válido hasta:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final picked = await showCompactDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    helpText: 'Fecha de Validez del Presupuesto',
                  );
                  if (picked != null) {
                    setState(() => _validUntil = picked);
                    widget.onValidUntilChanged(picked);
                  }
                },
                child: Text(
                  _validUntil != null
                      ? DateFormat('dd/MM/yyyy').format(_validUntil!)
                      : 'Seleccionar fecha',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.notesCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Condiciones / Notas (Opcional)',
              prefixIcon: const Icon(Icons.notes_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              hintText: 'Ej: Precios sujetos a disponibilidad de stock.',
            ),
          ),
        ],
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.description_rounded),
          label: const Text('Generar'),
        ),
      ],
    );
  }
}

class _QuoteFractionalQuantityDialog extends StatefulWidget {
  final Product product;
  final String unitShort;
  final bool isMetricOrHardware;
  final bool canUseCalc;
  final ValueChanged<double> onConfirm;
  final VoidCallback onOpenCalculator;

  const _QuoteFractionalQuantityDialog({
    required this.product,
    required this.unitShort,
    required this.isMetricOrHardware,
    required this.canUseCalc,
    required this.onConfirm,
    required this.onOpenCalculator,
  });

  @override
  State<_QuoteFractionalQuantityDialog> createState() =>
      _QuoteFractionalQuantityDialogState();
}

class _QuoteFractionalQuantityDialogState
    extends State<_QuoteFractionalQuantityDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    final valid = parsed != null && parsed > 0;
    return AppModalShell(
      title: widget.isMetricOrHardware
          ? 'Cantidad / Medida (${widget.unitShort}) - ${widget.product.name}'
          : 'Peso (Kg) - ${widget.product.name}',
      icon: widget.isMetricOrHardware
          ? Icons.straighten_rounded
          : Icons.scale_rounded,
      accent: widget.isMetricOrHardware
          ? AppModalAccent.teal
          : AppModalAccent.amber,
      compact: true,
      maxWidth: 420,
      useAlertDialogWrapper: true,
      onClose: () => Navigator.pop(context),
      bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.isMetricOrHardware
                  ? 'Cantidad (${widget.unitShort})'
                  : 'Kg',
              suffixText: widget.isMetricOrHardware
                  ? widget.unitShort.toUpperCase()
                  : 'KG',
              border: const OutlineInputBorder(),
            ),
          ),
          if (widget.canUseCalc) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onOpenCalculator();
              },
              icon: const Icon(Icons.calculate_outlined, size: 17),
              label: const Text('Abrir Calculadora F7'),
            ),
          ],
        ],
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: valid
              ? () {
                  Navigator.pop(context);
                  widget.onConfirm(parsed);
                }
              : null,
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}



