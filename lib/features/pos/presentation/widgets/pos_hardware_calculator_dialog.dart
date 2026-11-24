import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/pos_search_history_popover.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/services/hardware_calculator_engine.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

/// Destino del cálculo cuando se abre la Calculadora Ferretera:
/// - [pos]: agrega al carrito del POS o emite un Presupuesto Independiente sin tocar el carrito POS.
/// - [quote]: agrega directamente al carrito de la pantalla `QuoteScreen`.
enum HardwareCalculatorTarget {
  pos,
  quote,
}

class HardwareCalculatorOutput {
  final Product? product;
  final double billingQuantity;
  final String customDetails;
  final String? searchComplementKeyword;
  final bool addedToTarget;
  final Quote? createdQuote;

  const HardwareCalculatorOutput({
    this.product,
    required this.billingQuantity,
    required this.customDetails,
    this.searchComplementKeyword,
    this.addedToTarget = false,
    this.createdQuote,
  });
}

class PosHardwareCalculatorDialog extends StatefulWidget {
  final Product? initialProduct;
  final CartItem? replacingCartItem;
  final HardwareCalculatorTarget target;
  final ValueChanged<String>? onSearchComplementRequested;

  const PosHardwareCalculatorDialog({
    super.key,
    this.initialProduct,
    this.replacingCartItem,
    this.target = HardwareCalculatorTarget.pos,
    this.onSearchComplementRequested,
  });

  static Future<HardwareCalculatorOutput?> show(
    BuildContext context, {
    Product? initialProduct,
    CartItem? replacingCartItem,
    HardwareCalculatorTarget target = HardwareCalculatorTarget.pos,
    ValueChanged<String>? onSearchComplementRequested,
  }) {
    return showDialog<HardwareCalculatorOutput>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PosHardwareCalculatorDialog(
        initialProduct: initialProduct ?? replacingCartItem?.product,
        replacingCartItem: replacingCartItem,
        target: target,
        onSearchComplementRequested: onSearchComplementRequested,
      ),
    );
  }

  @override
  State<PosHardwareCalculatorDialog> createState() =>
      _PosHardwareCalculatorDialogState();
}

class _PosHardwareCalculatorDialogState
    extends State<PosHardwareCalculatorDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Buscador de producto integrado en el modal
  final _productSearchCtrl = TextEditingController();
  final _productSearchFocus = FocusNode();
  final _skuHistoryPortalController = OverlayPortalController();
  static const Object _skuHistoryTapGroupId = 'f7_sku_search_history_popover';
  int _skuHistoryHighlightIndex = -1;
  Timer? _searchDebounce;
  bool _isSearchingProducts = false;
  List<Product> _searchResults = [];
  Product? _selectedProduct;
  HardwareCalcTab? _selectedProductInitialTab;
  int _selectRequestSeq = 0;
  bool _skuConfigDirty = false;

  // Lista de precios activa en vivo dentro de la calculadora
  PriceTier _previewTier = PriceTier.base;
  String? _previewCustomTierLabel;
  double _previewCustomFactor = 1.0;

  // ── Controles Pestaña 1: Machimbre / Maderas ────────────────────────────
  bool _woodUseDirectM2 = false;
  final _woodRoomWidthCtrl = TextEditingController(text: '4');
  final _woodRoomLengthCtrl = TextEditingController(text: '3');
  final _woodDirectM2Ctrl = TextEditingController(text: '12');
  double _woodWastePct = 10.0;

  String _woodInchPreset = '4'; // '3', '4', '5', '6', 'custom'
  final _woodNominalWidthCmCtrl = TextEditingController(text: '10.16');
  final _woodUsefulWidthCmCtrl = TextEditingController(text: '8.8');
  final _woodBoardLengthMCtrl = TextEditingController(text: '3.00');
  WoodPricingMode _woodPricingMode = WoodPricingMode.perBoard;
  M2BillingBasis _woodM2Basis = M2BillingBasis.nominal;
  final _woodBoardsPerPackCtrl = TextEditingController(text: '10');
  bool _woodRoundToFullPack = false;

  // ── Controles Pestaña 2: Chapas / Techos ────────────────────────────────
  bool _roofUseDirectM2 = false;
  final _roofWidthCtrl = TextEditingController(text: '6');
  final _roofSlopeLengthCtrl = TextEditingController(text: '4');
  final _roofDirectM2Ctrl = TextEditingController(text: '24');
  double _roofWastePct = 10.0;
  final _sheetNominalWidthMCtrl = TextEditingController(text: '1.10');
  final _sheetUsefulWidthMCtrl = TextEditingController(text: '1.00');
  final _sheetLengthMCtrl = TextEditingController(text: '4.50');
  final _sheetLongOverlapCmCtrl = TextEditingController(text: '20');
  RoofPricingMode _roofPricingMode = RoofPricingMode.perSheet;

  // ── Controles Pestaña 3: Pintura / Membrana ─────────────────────────────
  bool _paintUseDirectM2 = false;
  final _paintWallWidthCtrl = TextEditingController(text: '5');
  final _paintWallHeightCtrl = TextEditingController(text: '2.60');
  final _paintDirectM2Ctrl = TextEditingController(text: '13');
  int _paintCoats = 2;
  PaintYieldMode _paintYieldMode = PaintYieldMode.perCoat;
  final _paintYieldCtrl = TextEditingController(text: '10');
  final _paintContainerLitersCtrl = TextEditingController(text: '4');
  final double _paintWastePct = 0.0;

  bool _currentItemAdded = false;
  bool _isSavingQuote = false;
  bool _missingWoodWidthWarning = false;
  String? _detectedWoodThicknessLabel;

  HardwareCalcTab get _activeTab =>
      HardwareCalcTab.values[_tabController.index];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleF7SkuHistoryKey);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    // Inicializar lista de precios desde el provider correspondiente
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.target == HardwareCalculatorTarget.quote) {
        final qProv = context.read<QuoteProvider>();
        setState(() {
          _previewTier = qProv.activeTier;
          _previewCustomTierLabel = qProv.customTierLabel;
          _previewCustomFactor = qProv.customFactor;
        });
      } else if (widget.replacingCartItem != null) {
        final item = widget.replacingCartItem!;
        setState(() {
          _previewTier = item.activeTier;
          _previewCustomTierLabel = item.customTierLabel;
          _previewCustomFactor = item.customFactor;
        });
      } else {
        final posProv = context.read<PosProvider>();
        setState(() {
          _previewTier = posProv.activeTier;
          _previewCustomTierLabel = posProv.customTierLabel;
          _previewCustomFactor = posProv.currentCustomFactor;
        });
      }
    });

    if (widget.initialProduct != null) {
      _selectProduct(widget.initialProduct!);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleF7SkuHistoryKey);
    _searchDebounce?.cancel();
    _tabController.dispose();
    _productSearchCtrl.dispose();
    _productSearchFocus.dispose();
    _woodRoomWidthCtrl.dispose();
    _woodRoomLengthCtrl.dispose();
    _woodDirectM2Ctrl.dispose();
    _woodNominalWidthCmCtrl.dispose();
    _woodUsefulWidthCmCtrl.dispose();
    _woodBoardLengthMCtrl.dispose();
    _woodBoardsPerPackCtrl.dispose();
    _roofWidthCtrl.dispose();
    _roofSlopeLengthCtrl.dispose();
    _roofDirectM2Ctrl.dispose();
    _sheetNominalWidthMCtrl.dispose();
    _sheetUsefulWidthMCtrl.dispose();
    _sheetLengthMCtrl.dispose();
    _sheetLongOverlapCmCtrl.dispose();
    _paintWallWidthCtrl.dispose();
    _paintWallHeightCtrl.dispose();
    _paintDirectM2Ctrl.dispose();
    _paintYieldCtrl.dispose();
    _paintContainerLitersCtrl.dispose();
    super.dispose();
  }

  double _parseNum(String raw, [double fallback = 0.0]) {
    final cleaned = raw.trim().replaceAll(',', '.');
    return double.tryParse(cleaned) ?? fallback;
  }

  Future<void> _selectProduct(Product product) async {
    final prevQuery = _productSearchCtrl.text.trim();
    _hideSkuHistoryPopover();
    final reqId = ++_selectRequestSeq;
    final autoRes =
        await HardwareCalculatorEngine.resolveAutoDetectForProduct(product);
    final config = autoRes.config;
    if (!mounted || reqId != _selectRequestSeq) return;
    _recordSkuHistory(
      term: prevQuery,
      product: product,
    );

    setState(() {
      _selectedProduct = product;
      _productSearchCtrl.clear();
      _searchResults = [];
      _skuConfigDirty = false;
      _currentItemAdded = false;

      final type = config['type']?.toString() ?? 'wood';
      _missingWoodWidthWarning = autoRes.missingWidthWarning && type == 'wood';
      _detectedWoodThicknessLabel = autoRes.detectedThicknessLabel;
      if (type == 'roof') {
        _tabController.index = 1;
        _selectedProductInitialTab = HardwareCalcTab.roof;
        final nomW = _toDouble(config['nominal_width_m'], 1.10);
        final useW = _toDouble(config['useful_width_m'], 1.00);
        final lenM = _toDouble(config['length_m'], 4.50);
        final overlapM = _toDouble(config['longitudinal_overlap_m'], 0.20);
        _sheetNominalWidthMCtrl.text = _fmtInput(nomW);
        _sheetUsefulWidthMCtrl.text = _fmtInput(useW);
        _sheetLengthMCtrl.text = _fmtInput(lenM);
        _sheetLongOverlapCmCtrl.text = _fmtInput(overlapM * 100, decimals: 0);
        final pm = config['pricing_mode']?.toString() ?? 'per_sheet';
        _roofPricingMode = pm == 'per_linear_meter'
            ? RoofPricingMode.perLinearMeter
            : (pm == 'per_m2' ? RoofPricingMode.perM2 : RoofPricingMode.perSheet);
      } else if (type == 'paint') {
        _tabController.index = 2;
        _selectedProductInitialTab = HardwareCalcTab.paint;
        final yld = _toDouble(config['yield_m2_per_liter'], 10.0);
        final cap = _toDouble(config['container_liters'], 4.0);
        final coats = (config['default_coats'] as num?)?.toInt() ?? 2;
        final ym = config['yield_mode']?.toString() ?? 'per_coat';
        _paintYieldCtrl.text = _fmtInput(yld);
        _paintContainerLitersCtrl.text = _fmtInput(cap);
        _paintCoats = coats.clamp(1, 20);
        _paintYieldMode = ym == 'final_total'
            ? PaintYieldMode.finalTotal
            : PaintYieldMode.perCoat;
      } else {
        _tabController.index = 0;
        _selectedProductInitialTab = HardwareCalcTab.wood;
        final preset = config['inch_preset']?.toString() ?? '4';
        final nomW = _toDouble(config['nominal_width_m'], 0.1016);
        final useW = _toDouble(config['useful_width_m'], 0.088);
        final lenM = _toDouble(config['length_m'], 3.00);
        final packSize = (config['boards_per_pack'] as num?)?.toInt() ?? 10;
        final roundPack = config['round_to_full_pack'] == true;
        final waste = _toDouble(config['default_waste_pct'], 10.0);
        final pm = config['pricing_mode']?.toString() ?? 'per_board';
        final basis = config['m2_billing_basis']?.toString() ?? 'nominal';

        _woodInchPreset = preset;
        _woodNominalWidthCmCtrl.text = _fmtInput(nomW * 100);
        _woodUsefulWidthCmCtrl.text = _fmtInput(useW * 100);
        _woodBoardLengthMCtrl.text = _fmtInput(lenM);
        _woodBoardsPerPackCtrl.text = packSize.toString();
        _woodRoundToFullPack = roundPack;
        _woodWastePct = waste;
        _woodM2Basis =
            basis == 'useful' ? M2BillingBasis.useful : M2BillingBasis.nominal;
        switch (pm) {
          case 'per_m2':
            _woodPricingMode = WoodPricingMode.perM2;
            break;
          case 'per_linear_meter':
            _woodPricingMode = WoodPricingMode.perLinearMeter;
            break;
          case 'per_pack':
            _woodPricingMode = WoodPricingMode.perPack;
            break;
          default:
            _woodPricingMode = WoodPricingMode.perBoard;
        }
      }
    });
  }

  double _toDouble(dynamic val, double fallback) {
    if (val is num) return val.toDouble();
    if (val != null) return double.tryParse(val.toString()) ?? fallback;
    return fallback;
  }

  String _fmtInput(double val, {int decimals = 2}) {
    if ((val - val.roundToDouble()).abs() < 0.001) {
      return val.round().toString();
    }
    return val
        .toStringAsFixed(decimals)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  Map<String, dynamic> _buildCurrentConfigSnapshot() {
    switch (_activeTab) {
      case HardwareCalcTab.wood:
        return {
          'type': 'wood',
          'inch_preset': _woodInchPreset,
          'nominal_width_m':
              (_parseNum(_woodNominalWidthCmCtrl.text, 10.16) / 100.0),
          'useful_width_m':
              (_parseNum(_woodUsefulWidthCmCtrl.text, 8.8) / 100.0),
          'length_m': _parseNum(_woodBoardLengthMCtrl.text, 3.00),
          'pricing_mode': _woodPricingMode == WoodPricingMode.perM2
              ? 'per_m2'
              : (_woodPricingMode == WoodPricingMode.perLinearMeter
                  ? 'per_linear_meter'
                  : (_woodPricingMode == WoodPricingMode.perPack
                      ? 'per_pack'
                      : 'per_board')),
          'm2_billing_basis':
              _woodM2Basis == M2BillingBasis.useful ? 'useful' : 'nominal',
          'boards_per_pack':
              int.tryParse(_woodBoardsPerPackCtrl.text.trim()) ?? 10,
          'round_to_full_pack': _woodRoundToFullPack,
          'default_waste_pct': _woodWastePct,
        };
      case HardwareCalcTab.roof:
        return {
          'type': 'roof',
          'nominal_width_m': _parseNum(_sheetNominalWidthMCtrl.text, 1.10),
          'useful_width_m': _parseNum(_sheetUsefulWidthMCtrl.text, 1.00),
          'length_m': _parseNum(_sheetLengthMCtrl.text, 4.50),
          'longitudinal_overlap_m':
              (_parseNum(_sheetLongOverlapCmCtrl.text, 20.0) / 100.0),
          'pricing_mode': _roofPricingMode == RoofPricingMode.perLinearMeter
              ? 'per_linear_meter'
              : (_roofPricingMode == RoofPricingMode.perM2
                  ? 'per_m2'
                  : 'per_sheet'),
        };
      case HardwareCalcTab.paint:
        return {
          'type': 'paint',
          'yield_m2_per_liter': _parseNum(_paintYieldCtrl.text, 10.0),
          'yield_mode': _paintYieldMode == PaintYieldMode.finalTotal
              ? 'final_total'
              : 'per_coat',
          'container_liters': _parseNum(_paintContainerLitersCtrl.text, 4.0),
          'default_coats': _paintCoats,
          'default_waste_pct': _paintWastePct,
        };
    }
  }

  bool _isValidConfigSnapshot(Map<String, dynamic> snap) {
    final type = snap['type']?.toString();
    if (type == 'wood') {
      final nom = (snap['nominal_width_m'] as num?)?.toDouble();
      final use = (snap['useful_width_m'] as num?)?.toDouble();
      final len = (snap['length_m'] as num?)?.toDouble();
      final pack = (snap['boards_per_pack'] as num?)?.toInt();
      final waste = (snap['default_waste_pct'] as num?)?.toDouble();
      return nom != null &&
          nom.isFinite &&
          nom >= 0.001 &&
          nom <= 50 &&
          use != null &&
          use.isFinite &&
          use >= 0.001 &&
          use <= nom + 1e-6 &&
          len != null &&
          len.isFinite &&
          len >= 0.05 &&
          len <= 50 &&
          pack != null &&
          pack >= 1 &&
          pack <= 500 &&
          waste != null &&
          waste.isFinite &&
          waste >= 0 &&
          waste <= 100;
    }
    if (type == 'roof') {
      final nom = (snap['nominal_width_m'] as num?)?.toDouble();
      final use = (snap['useful_width_m'] as num?)?.toDouble();
      final len = (snap['length_m'] as num?)?.toDouble();
      final overlap = (snap['longitudinal_overlap_m'] as num?)?.toDouble();
      return nom != null &&
          nom.isFinite &&
          nom >= 0.001 &&
          nom <= 50 &&
          use != null &&
          use.isFinite &&
          use >= 0.001 &&
          use <= nom + 1e-6 &&
          len != null &&
          len.isFinite &&
          len >= 0.05 &&
          len <= 50 &&
          overlap != null &&
          overlap.isFinite &&
          overlap >= 0 &&
          overlap <= 5 &&
          overlap < len;
    }
    if (type == 'paint') {
      final yld = (snap['yield_m2_per_liter'] as num?)?.toDouble();
      final cap = (snap['container_liters'] as num?)?.toDouble();
      final coats = (snap['default_coats'] as num?)?.toInt();
      final waste = (snap['default_waste_pct'] as num?)?.toDouble();
      return yld != null &&
          yld.isFinite &&
          yld >= 0.05 &&
          yld <= 500 &&
          cap != null &&
          cap.isFinite &&
          cap >= 0.05 &&
          cap <= 1000 &&
          coats != null &&
          coats >= 1 &&
          coats <= 20 &&
          waste != null &&
          waste.isFinite &&
          waste >= 0 &&
          waste <= 100;
    }
    return false;
  }

  /// Guarda silenciosamente el `calc_config` en caché local (0 ms) y en el servidor (`PATCH /calc-config`).
  Future<void> _persistSelectedProductConfigIfNeeded() async {
    final prod = _selectedProduct;
    if (prod == null || prod.id <= 0) return;
    if (!_activeSummary().isValid) return;
    final snapshot = _buildCurrentConfigSnapshot();
    if (!_isValidConfigSnapshot(snapshot)) return;
    await HardwareCalculatorEngine.saveLocalCacheForProduct(prod.id, snapshot);
    if (!mounted) return;
    try {
      final catalogProv = context.read<CatalogProvider>();
      // Fire-and-forget al servidor para no demorar la respuesta visual del mostrador
      unawaited(catalogProv.updateProductCalcConfigFromPos(prod.id, snapshot));
    } catch (_) {}
  }

  List<Product> _resolveRecentSkuProducts(
    CatalogProvider catalog,
    LocalTerminalProvider? localTerminal,
  ) {
    final ids = localTerminal?.recentProductIdsForScope(
          LocalTerminalProvider.scopeHardwareCalc,
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

  bool _hasSkuHistoryEntries(
    CatalogProvider catalog,
    LocalTerminalProvider? localTerminal,
  ) {
    if (localTerminal == null) return false;
    final terms = localTerminal.recentTermsForScope(
      LocalTerminalProvider.scopeHardwareCalc,
    );
    if (terms.isNotEmpty) return true;
    return _resolveRecentSkuProducts(catalog, localTerminal).isNotEmpty;
  }

  bool _handleF7SkuHistoryKey(KeyEvent event) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    if (event is! KeyDownEvent) return false;
    if (_selectedProduct != null) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _skuHistoryPortalController.isShowing) {
      _hideSkuHistoryPopover();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        _skuHistoryPortalController.isShowing) {
      _hideSkuHistoryPopover();
      return false;
    }
    if (_productSearchCtrl.text.trim().isEmpty &&
        (_productSearchFocus.hasFocus ||
            _skuHistoryPortalController.isShowing)) {
      final localTerminal =
          tryGetLocalTerminalProvider(context, listen: false);
      final catalog = context.read<CatalogProvider>();
      final terms = localTerminal?.recentTermsForScope(
            LocalTerminalProvider.scopeHardwareCalc,
          ) ??
          const <String>[];
      final products = _resolveRecentSkuProducts(catalog, localTerminal);
      final total = terms.length + products.length;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown && total > 0) {
        if (!_skuHistoryPortalController.isShowing) {
          _showSkuHistoryPopoverIfAvailable(initialHighlightIndex: 0);
        } else {
          setState(() {
            _skuHistoryHighlightIndex =
                (_skuHistoryHighlightIndex + 1).clamp(0, total - 1);
          });
        }
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          _skuHistoryPortalController.isShowing) {
        setState(() {
          _skuHistoryHighlightIndex = _skuHistoryHighlightIndex <= 0
              ? -1
              : _skuHistoryHighlightIndex - 1;
        });
        return true;
      }
      if ((event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
          _skuHistoryPortalController.isShowing &&
          _skuHistoryHighlightIndex >= 0) {
        if (_skuHistoryHighlightIndex < terms.length) {
          final term = terms[_skuHistoryHighlightIndex];
          _hideSkuHistoryPopover();
          _productSearchCtrl.text = term;
          _productSearchCtrl.selection =
              TextSelection.collapsed(offset: term.length);
          _onProductSearchChanged(term);
          _productSearchFocus.requestFocus();
          return true;
        }
        final pIdx = _skuHistoryHighlightIndex - terms.length;
        if (pIdx >= 0 && pIdx < products.length) {
          _hideSkuHistoryPopover();
          _selectProduct(products[pIdx]);
          return true;
        }
      }
    }
    return false;
  }

  void _showSkuHistoryPopoverIfAvailable({int initialHighlightIndex = -1}) {
    if (!mounted ||
        _selectedProduct != null ||
        _productSearchCtrl.text.trim().isNotEmpty) {
      return;
    }
    final localTerminal = tryGetLocalTerminalProvider(context, listen: false);
    final catalog = context.read<CatalogProvider>();
    if (!_hasSkuHistoryEntries(catalog, localTerminal)) return;
    if (_skuHistoryHighlightIndex != initialHighlightIndex) {
      setState(() => _skuHistoryHighlightIndex = initialHighlightIndex);
    }
    if (!_skuHistoryPortalController.isShowing) {
      _skuHistoryPortalController.show();
    }
  }

  void _hideSkuHistoryPopover() {
    if (_skuHistoryHighlightIndex != -1 && mounted) {
      setState(() => _skuHistoryHighlightIndex = -1);
    } else {
      _skuHistoryHighlightIndex = -1;
    }
    if (_skuHistoryPortalController.isShowing) {
      _skuHistoryPortalController.hide();
    }
  }

  void _recordSkuHistory({String? term, Product? product}) {
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
      LocalTerminalProvider.scopeHardwareCalc,
      term: validTerm,
      selectedProductId: prodId,
    ));
  }

  Widget _buildSkuHistoryOverlay(
    BuildContext overlayContext,
    OverlayChildLayoutInfo info,
  ) {
    return PosSearchHistoryPopover.buildAnchoredOverlay(
      info: info,
      maxWidth: 560.0,
      maxOverlayHeight: 320.0,
      child: Consumer<CatalogProvider>(
        builder: (ctx, catalog, _) {
          final localTerminal = tryGetLocalTerminalProvider(ctx, listen: true);
          final terms = localTerminal?.recentTermsForScope(
                LocalTerminalProvider.scopeHardwareCalc,
              ) ??
              const <String>[];
          final products = _resolveRecentSkuProducts(catalog, localTerminal);

          if (localTerminal == null || (terms.isEmpty && products.isEmpty)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _hideSkuHistoryPopover();
            });
            return const SizedBox.shrink();
          }

          return PosSearchHistoryPopover(
            containerKey: const ValueKey('f7_sku_search_history_overlay'),
            terms: terms,
            products: products,
            highlightedIndex: _skuHistoryHighlightIndex,
            tapGroupId: _skuHistoryTapGroupId,
            maxWidth: 560.0,
            maxHeight: 320.0,
            productActionIcon: Icons.straighten_rounded,
            onDismiss: _hideSkuHistoryPopover,
            onClearAll: () {
              unawaited(localTerminal.clearRecentSearchesForScope(
                LocalTerminalProvider.scopeHardwareCalc,
              ));
              _hideSkuHistoryPopover();
              _productSearchFocus.requestFocus();
            },
            onSelectTerm: (term) {
              _hideSkuHistoryPopover();
              _productSearchCtrl.text = term;
              _productSearchCtrl.selection =
                  TextSelection.collapsed(offset: term.length);
              _onProductSearchChanged(term);
              _productSearchFocus.requestFocus();
            },
            onRemoveTerm: (term) {
              final willBeEmpty = terms.length <= 1 && products.isEmpty;
              unawaited(localTerminal.removeRecentTermForScope(
                LocalTerminalProvider.scopeHardwareCalc,
                term,
              ));
              if (willBeEmpty) {
                _hideSkuHistoryPopover();
              } else if (_skuHistoryHighlightIndex != -1) {
                setState(() => _skuHistoryHighlightIndex = -1);
              }
            },
            onSelectProduct: (p) {
              _hideSkuHistoryPopover();
              _selectProduct(p);
            },
            onRemoveProduct: (productId) {
              final willBeEmpty = products.length <= 1 && terms.isEmpty;
              unawaited(localTerminal.removeRecentProductIdForScope(
                LocalTerminalProvider.scopeHardwareCalc,
                productId,
              ));
              if (willBeEmpty) {
                _hideSkuHistoryPopover();
              } else if (_skuHistoryHighlightIndex != -1) {
                setState(() => _skuHistoryHighlightIndex = -1);
              }
            },
            priceResolver: (p) => (
              price: _resolveUnitPriceForProduct(p, 1.0) ?? p.sellingPrice,
              crossedOutPrice: null,
              hasActiveOffer: false,
            ),
          );
        },
      ),
    );
  }

  void _onProductSearchChanged(String raw) {
    _searchDebounce?.cancel();
    final q = raw.trim();
    if (q.isNotEmpty) {
      _hideSkuHistoryPopover();
    }
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchingProducts = false;
      });
      return;
    }

    // Búsqueda inmediata en memoria + remota con debounce
    final catalog = context.read<CatalogProvider>();
    final localMatches = catalog.activeProducts
        .where((p) => matchesSpanishSearchQuery(q, [
              p.name,
              p.barcode,
              p.internalCode,
              p.supplierSku,
              p.technicalSpec,
            ]))
        .take(12)
        .toList();

    setState(() {
      _searchResults = localMatches;
      _isSearchingProducts = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 260), () async {
      try {
        final remote = await catalog.searchProductsRemote(q, perPage: 20);
        if (!mounted || _productSearchCtrl.text.trim() != q) return;
        catalog.registerRecentlySeenProducts(remote);
        final byId = <int, Product>{for (final p in localMatches) p.id: p};
        for (final p in remote) {
          if (p.active) byId[p.id] = p;
        }
        final mergedResults = byId.values.take(15).toList();
        if (mergedResults.isNotEmpty) {
          _recordSkuHistory(term: q);
        }
        setState(() {
          _searchResults = mergedResults;
          _isSearchingProducts = false;
        });
      } catch (_) {
        if (mounted) setState(() => _isSearchingProducts = false);
      }
    });
  }

  WoodCalculationResult _computeWood() {
    final area = _woodUseDirectM2
        ? _parseNum(_woodDirectM2Ctrl.text)
        : (_parseNum(_woodRoomWidthCtrl.text) *
            _parseNum(_woodRoomLengthCtrl.text));
    final nomW = _parseNum(_woodNominalWidthCmCtrl.text) / 100.0;
    final useW = _parseNum(_woodUsefulWidthCmCtrl.text) / 100.0;
    final lenM = _parseNum(_woodBoardLengthMCtrl.text);
    final packSize = int.tryParse(_woodBoardsPerPackCtrl.text.trim()) ?? 10;

    return HardwareCalculatorEngine.calculateWood(
      targetAreaM2: area,
      nominalWidthM: nomW,
      usefulWidthM: useW,
      boardLengthM: lenM,
      wastePercent: _woodWastePct,
      pricingMode: _woodPricingMode,
      m2BillingBasis: _woodM2Basis,
      boardsPerPack: packSize,
      roundToFullPack: _woodRoundToFullPack,
      inchLabel: _woodInchPreset != 'custom' ? _woodInchPreset : null,
    );
  }

  RoofCalculationResult _computeRoof() {
    if (_roofUseDirectM2) {
      return HardwareCalculatorEngine.calculateRoofByArea(
        targetAreaM2: _parseNum(_roofDirectM2Ctrl.text),
        sheetNominalWidthM: _parseNum(_sheetNominalWidthMCtrl.text),
        sheetUsefulWidthM: _parseNum(_sheetUsefulWidthMCtrl.text),
        sheetLengthM: _parseNum(_sheetLengthMCtrl.text),
        wastePercent: _roofWastePct,
        pricingMode: _roofPricingMode,
      );
    }
    return HardwareCalculatorEngine.calculateRoof(
      roofWidthM: _parseNum(_roofWidthCtrl.text),
      roofSlopeLengthM: _parseNum(_roofSlopeLengthCtrl.text),
      sheetNominalWidthM: _parseNum(_sheetNominalWidthMCtrl.text),
      sheetUsefulWidthM: _parseNum(_sheetUsefulWidthMCtrl.text),
      sheetLengthM: _parseNum(_sheetLengthMCtrl.text),
      longitudinalOverlapM: _parseNum(_sheetLongOverlapCmCtrl.text) / 100.0,
      pricingMode: _roofPricingMode,
    );
  }

  PaintCalculationResult _computePaint() {
    final area = _paintUseDirectM2
        ? _parseNum(_paintDirectM2Ctrl.text)
        : (_parseNum(_paintWallWidthCtrl.text) *
            _parseNum(_paintWallHeightCtrl.text));
    return HardwareCalculatorEngine.calculatePaint(
      surfaceAreaM2: area,
      coats: _paintCoats,
      yieldM2PerLiter: _parseNum(_paintYieldCtrl.text),
      containerLiters: _parseNum(_paintContainerLitersCtrl.text),
      yieldMode: _paintYieldMode,
      wastePercent: _paintWastePct,
    );
  }

  ({
    bool isValid,
    String? error,
    double billingQty,
    String billingUnit,
    String primaryHeadline,
    String secondarySubtitle,
    String customDetailsNote,
    List<ComplementSuggestion> complements,
  }) _activeSummary() {
    switch (_activeTab) {
      case HardwareCalcTab.wood:
        final r = _computeWood();
        if (!r.isValid) {
          return (
            isValid: false,
            error: r.errorMessage,
            billingQty: 0,
            billingUnit: '',
            primaryHeadline: 'Completá las medidas',
            secondarySubtitle: r.errorMessage ?? '',
            customDetailsNote: '',
            complements: const [],
          );
        }
        final packBadge = _woodPricingMode == WoodPricingMode.perPack
            ? ' (${r.packsNeeded} paq.${r.looseBoardsRemainder > 0 ? " + ${r.looseBoardsRemainder} sueltas" : ""})'
            : '';
        return (
          isValid: true,
          error: null,
          billingQty: r.billingQuantity,
          billingUnit: r.billingUnitLabel,
          primaryHeadline:
              '${r.totalBoardsDelivered} ${r.totalBoardsDelivered == 1 ? "Tabla" : "Tablas"} de ${_fmtInput(_parseNum(_woodBoardLengthMCtrl.text))}m$packBadge',
          secondarySubtitle:
              'Cubre ${r.usefulAreaCoveredM2.toQty()} m² útiles · ${r.nominalAreaDeliveredM2.toQty()} m² nom. · ${r.totalLinearMeters.toQty()} ml',
          customDetailsNote: r.customDetailsNote,
          complements: r.complements,
        );
      case HardwareCalcTab.roof:
        final r = _computeRoof();
        if (!r.isValid) {
          return (
            isValid: false,
            error: r.errorMessage,
            billingQty: 0,
            billingUnit: '',
            primaryHeadline: 'Completá las medidas del techo',
            secondarySubtitle: r.errorMessage ?? '',
            customDetailsNote: '',
            complements: const [],
          );
        }
        final roofSurplusText = r.surplusPerColumnM > 0.05
            ? ' (sobra ${r.surplusPerColumnM.toQty()}m/hilada)'
            : '';
        final roofSecondarySubtitle = r.isAreaEstimate
            ? 'Estimado p/ ${r.roofAreaM2.toQty()} m²${r.wastePercent > 0 ? " (+${r.wastePercent.toInt()}%)" : ""} · cubre ${r.usefulAreaCoveredM2.toQty()} m² útiles · ${r.totalLinearMeters.toQty()} ml'
            : '${r.columnsAcrossWidth} ${r.columnsAcrossWidth == 1 ? "hilada" : "hiladas"} × ${r.rowsAlongSlope} ${r.rowsAlongSlope == 1 ? "tramo" : "tramos"} · cubre ${r.coveredSlopeLengthM.toQty()}m p/ ${r.roofSlopeLengthM.toQty()}m$roofSurplusText · ${r.totalLinearMeters.toQty()} ml';
        return (
          isValid: true,
          error: null,
          billingQty: r.billingQuantity,
          billingUnit: r.billingUnitLabel,
          primaryHeadline:
              '${r.totalSheetsNeeded} ${r.totalSheetsNeeded == 1 ? "Chapa" : "Chapas"} de ${_fmtInput(_parseNum(_sheetLengthMCtrl.text))}m',
          secondarySubtitle: roofSecondarySubtitle,
          customDetailsNote: r.customDetailsNote,
          complements: r.complements,
        );
      case HardwareCalcTab.paint:
        final r = _computePaint();
        if (!r.isValid) {
          return (
            isValid: false,
            error: r.errorMessage,
            billingQty: 0,
            billingUnit: '',
            primaryHeadline: 'Completá la superficie a pintar',
            secondarySubtitle: r.errorMessage ?? '',
            customDetailsNote: '',
            complements: const [],
          );
        }
        return (
          isValid: true,
          error: null,
          billingQty: r.billingQuantity,
          billingUnit: r.billingUnitLabel,
          primaryHeadline:
              '${r.containersNeeded} ${r.containersNeeded == 1 ? "Envase" : "Envases"} de ${_fmtInput(r.containerLiters)} L/Kg',
          secondarySubtitle:
              'Necesita ${r.totalLitersNeeded.toQty()} L/Kg totales → Lleva ${r.totalLitersDelivered.toQty()} L/Kg',
          customDetailsNote: r.customDetailsNote,
          complements: r.complements,
        );
    }
  }

  double? _resolveUnitPriceForProduct(Product product, double billingQty) {
    final settings = context.read<SettingsProvider>().settings;
    if (widget.target == HardwareCalculatorTarget.quote) {
      final qProv = context.read<QuoteProvider>();
      final calc = ProductPricingCalculator.calculate(
        product: product,
        quantity: billingQty > 0 ? billingQty : 1.0,
        activeTier: _previewTier,
        wholesaleFactor:
            settings?.wholesalePriceFactor ?? qProv.wholesaleFactor,
        cardFactor: settings?.cardPriceFactor ?? qProv.cardFactor,
        customFactor: _previewCustomFactor,
        promotionalPrice: null,
        hasExplicitOffer: false,
        ignoreFixedPrices:
            settings?.ignoreProductFixedPrices ?? qProv.ignoreFixedPrices,
      );
      return calc.finalUnitPrice;
    }

    final pos = context.read<PosProvider>();
    final offerProv = context.read<OfferProvider>();
    final promoPrice = offerProv.getDiscountedPrice(product);
    final hasOffer = promoPrice != null &&
        promoPrice > 0 &&
        promoPrice < product.sellingPrice;

    final calc = ProductPricingCalculator.calculate(
      product: product,
      quantity: billingQty > 0 ? billingQty : 1.0,
      activeTier: _previewTier,
      wholesaleFactor: settings?.wholesalePriceFactor ?? pos.wholesaleFactor,
      cardFactor: settings?.cardPriceFactor ?? pos.cardFactor,
      customFactor: _previewCustomFactor,
      promotionalPrice: promoPrice,
      hasExplicitOffer: hasOffer,
      cardSurchargeOnOffersMode: pos.cardSurchargeOnOffersMode,
      discountTierOnOffersMode: pos.discountTierOnOffersMode,
      ignoreFixedPrices:
          settings?.ignoreProductFixedPrices ?? pos.ignoreProductFixedPrices,
    );
    return calc.finalUnitPrice;
  }

  String _tabDisplayName(HardwareCalcTab tab) {
    switch (tab) {
      case HardwareCalcTab.wood:
        return 'Machimbre / Maderas';
      case HardwareCalcTab.roof:
        return 'Chapas / Techos';
      case HardwareCalcTab.paint:
        return 'Pintura / Membrana';
    }
  }

  String _tierDisplayName(PriceTier tier, String? customLabel) {
    switch (tier) {
      case PriceTier.base:
        return 'Lista Base';
      case PriceTier.wholesale:
        return 'Mayorista';
      case PriceTier.card:
        return 'Tarjeta';
      case PriceTier.custom:
        return customLabel ?? 'Personalizada';
    }
  }

  Future<void> _handleAddToTarget({bool closeAfter = true}) async {
    final summary = _activeSummary();
    if (!summary.isValid || summary.billingQty <= 0) {
      SnackBarService.warning(
        context,
        summary.error ?? 'Revisá las medidas antes de agregar.',
      );
      return;
    }
    final prod = _selectedProduct;
    if (prod == null) {
      SnackBarService.info(
        context,
        'Seleccioná un producto del catálogo arriba para agregar este cálculo.',
      );
      _productSearchFocus.requestFocus();
      return;
    }

    final settings = context.read<SettingsProvider>().settings;

    if (widget.target == HardwareCalculatorTarget.quote) {
      final qProv = context.read<QuoteProvider>();
      final tierMismatch = qProv.activeTier != _previewTier ||
          (_previewTier == PriceTier.custom &&
              qProv.customTierLabel != _previewCustomTierLabel);

      if (tierMismatch && qProv.cart.isNotEmpty) {
        final previewLabel =
            _tierDisplayName(_previewTier, _previewCustomTierLabel);
        final decision = await showDialog<String>(
          context: context,
          builder: (ctx) => AppModalShell(
            title: 'Lista de precios diferente',
            icon: Icons.price_change_rounded,
            accent: AppModalAccent.amber,
            compact: true,
            maxWidth: 440,
            useAlertDialogWrapper: true,
            onClose: () => Navigator.pop(ctx, 'cancel'),
            bodyPadding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            body: Text(
              'El presupuesto actual usa "${qProv.activePriceListLabel}" y calculaste con "$previewLabel". ¿Cómo querés continuar?',
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            footerActions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancelar'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, 'keep_cart'),
                child: Text('Mantener "${qProv.activePriceListLabel}"'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'change_all'),
                child: const Text('Cambiar todo el presupuesto'),
              ),
            ],
          ),
        );
        if (!mounted || decision == null || decision == 'cancel') return;
        if (decision == 'change_all') {
          qProv.setPriceTier(
            _previewTier,
            customFactor: _previewCustomFactor,
            customLabel: _previewCustomTierLabel,
          );
        }
      } else if (tierMismatch) {
        qProv.setPriceTier(
          _previewTier,
          customFactor: _previewCustomFactor,
          customLabel: _previewCustomTierLabel,
        );
      }

      await _persistSelectedProductConfigIfNeeded();
      if (!mounted) return;

      qProv.addToCart(
        prod,
        quantity: summary.billingQty,
        customDetails: summary.customDetailsNote,
        ignoreFixedPrices: settings?.ignoreProductFixedPrices,
        replacingItem: widget.replacingCartItem,
      );
    } else {
      final posProv = context.read<PosProvider>();
      final tierMismatch = posProv.activeTier != _previewTier ||
          (_previewTier == PriceTier.custom &&
              posProv.customTierLabel != _previewCustomTierLabel);
      final hasOtherCartItems = posProv.cart.isNotEmpty &&
          !(widget.replacingCartItem != null && posProv.cart.length == 1);

      if (tierMismatch && hasOtherCartItems) {
        final cartLabel =
            _tierDisplayName(posProv.activeTier, posProv.customTierLabel);
        final previewLabel =
            _tierDisplayName(_previewTier, _previewCustomTierLabel);
        final decision = await showDialog<String>(
          context: context,
          builder: (ctx) => AppModalShell(
            title: 'Lista de precios diferente',
            icon: Icons.price_change_rounded,
            accent: AppModalAccent.amber,
            compact: true,
            maxWidth: 440,
            useAlertDialogWrapper: true,
            onClose: () => Navigator.pop(ctx, 'cancel'),
            bodyPadding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            body: Text(
              'El carrito actual usa "$cartLabel" y este cálculo usa "$previewLabel". ¿Cómo querés aplicarlo?',
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            footerActions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancelar'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, 'item_only'),
                child: const Text('Solo este ítem'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'change_all'),
                child: const Text('Cambiar todo el carrito'),
              ),
            ],
          ),
        );
        if (!mounted || decision == null || decision == 'cancel') return;
        if (decision == 'change_all') {
          posProv.setPriceTier(
            _previewTier,
            wholesaleFactor: settings?.wholesalePriceFactor,
            cardFactor: settings?.cardPriceFactor,
            customFactor: _previewCustomFactor,
            customLabel: _previewCustomTierLabel,
          );
        }
      } else if (tierMismatch) {
        posProv.setPriceTier(
          _previewTier,
          wholesaleFactor: settings?.wholesalePriceFactor,
          cardFactor: settings?.cardPriceFactor,
          customFactor: _previewCustomFactor,
          customLabel: _previewCustomTierLabel,
        );
      }

      await _persistSelectedProductConfigIfNeeded();
      if (!mounted) return;

      final offerProv = context.read<OfferProvider>();
      final promoPrice = offerProv.getDiscountedPrice(prod);
      final promoOffer = offerProv.getActiveOfferForProduct(
        prod.id,
        basePrice: prod.sellingPrice,
      );

      posProv.addCalculatedHardwareItem(
        prod,
        quantity: summary.billingQty,
        customDetails: summary.customDetailsNote,
        overrideTier: _previewTier,
        overrideCustomFactor: _previewCustomFactor,
        overrideCustomLabel: _previewCustomTierLabel,
        promotionalPrice: promoPrice,
        promotionalLabel: promoOffer?.name,
        promotionalPeriodType: promoOffer?.periodType,
        replacingItem: widget.replacingCartItem,
      );
    }

    setState(() {
      _currentItemAdded = true;
    });

    if (closeAfter && mounted) {
      Navigator.of(context).pop(
        HardwareCalculatorOutput(
          product: prod,
          billingQuantity: summary.billingQty,
          customDetails: summary.customDetailsNote,
          addedToTarget: true,
        ),
      );
    } else if (mounted) {
      SnackBarService.success(
        context,
        '✅ "${prod.name}" (${summary.billingQty.toQty()} ${summary.billingUnit}) agregado.',
      );
    }
  }

  /// Punto 4 UX: "Enviar a Presupuesto" directo desde la calculadora SIN borrar ni alterar
  /// el carrito que el cajero ya tiene armado en la Terminal POS.
  Future<void> _handleSendToStandaloneQuote() async {
    final summary = _activeSummary();
    if (!summary.isValid || summary.billingQty <= 0) {
      SnackBarService.warning(
        context,
        summary.error ?? 'Revisá las medidas antes de presupuestar.',
      );
      return;
    }
    final prod = _selectedProduct;
    if (prod == null) {
      SnackBarService.info(
        context,
        'Seleccioná un producto del catálogo arriba para armar el presupuesto.',
      );
      _productSearchFocus.requestFocus();
      return;
    }

    await _persistSelectedProductConfigIfNeeded();
    if (!mounted) return;

    if (widget.target == HardwareCalculatorTarget.quote) {
      await _handleAddToTarget(closeAfter: true);
      return;
    }

    final unitPrice = _resolveUnitPriceForProduct(prod, summary.billingQty) ??
        prod.sellingPrice;
    final subtotal =
        ProductPricingCalculator.roundMoney(unitPrice * summary.billingQty);

    final posProv = context.read<PosProvider>();
    final nameCtrl =
        TextEditingController(text: posProv.selectedCustomer?.name ?? '');
    final phoneCtrl =
        TextEditingController(text: posProv.selectedCustomer?.phone ?? '');
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppModalShell(
        title: 'Emitir Presupuesto Rápido de este Cálculo',
        icon: Icons.request_quote_rounded,
        accent: AppModalAccent.indigo,
        compact: true,
        maxWidth: 460,
        useAlertDialogWrapper: true,
        onClose: () => Navigator.pop(ctx, false),
        bodyPadding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined,
                      size: 18, color: Colors.teal.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tu carrito actual de caja NO se borrará ni modificará.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.teal.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prod.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary.customDetailsNote,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${summary.billingQty.toQty()} ${summary.billingUnit} × \$${unitPrice.toCurrency()}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '\$${subtotal.toCurrency()}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.indigo.shade800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre del Cliente (Opcional)',
                prefixIcon: Icon(Icons.person_outline, size: 19),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp / Teléfono (Opcional)',
                prefixIcon: Icon(Icons.phone_outlined, size: 19),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Observaciones adicionales (Opcional)',
                prefixIcon: Icon(Icons.notes_outlined, size: 19),
                border: OutlineInputBorder(),
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.indigo,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.description_rounded, size: 18),
            label: const Text('Generar PDF / WhatsApp'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      notesCtrl.dispose();
      return;
    }

    setState(() => _isSavingQuote = true);
    try {
      final quoteRepo = context.read<QuoteProvider>().repository;
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUser?['id'] != null
          ? int.tryParse(auth.currentUser!['id'].toString())
          : null;
      final priceListKey = _previewTier == PriceTier.custom
          ? (_previewCustomTierLabel ?? 'base')
          : _previewTier.name;

      final quote = await quoteRepo.createQuote(
        items: [
          QuoteItem(
            productId: prod.id > 0 ? prod.id : null,
            productName: prod.name,
            customDetails: summary.customDetailsNote,
            unitPrice: unitPrice,
            quantity: summary.billingQty,
            subtotal: subtotal,
            product: prod,
            imageUrl: prod.imageUrl,
          ),
        ],
        customerName:
            nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        customerPhone:
            phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        userId: userId,
        priceList: priceListKey,
      );

      if (!mounted) return;
      final enrichedItems = quote.items.map((item) {
        final hasDetails =
            item.customDetails != null && item.customDetails!.trim().isNotEmpty;
        return QuoteItem(
          productId: item.productId,
          productName: item.productName,
          customDetails:
              hasDetails ? item.customDetails : summary.customDetailsNote,
          unitPrice: item.unitPrice,
          quantity: item.quantity,
          subtotal: item.subtotal,
          product: item.product ?? prod,
          imageUrl: item.imageUrl ?? prod.imageUrl,
        );
      }).toList();

      final enrichedQuote = Quote(
        id: quote.id,
        quoteNumber: quote.quoteNumber,
        status: quote.status,
        subtotal: quote.subtotal,
        total: quote.total,
        customerName: quote.customerName,
        customerPhone: quote.customerPhone,
        notes: quote.notes,
        validUntil: quote.validUntil,
        items: enrichedItems,
        createdAt: quote.createdAt,
        priceList: quote.priceList,
      );

      Navigator.of(context).pop(
        HardwareCalculatorOutput(
          product: prod,
          billingQuantity: summary.billingQty,
          customDetails: summary.customDetailsNote,
          addedToTarget: false,
          createdQuote: enrichedQuote,
        ),
      );
    } catch (e) {
      if (mounted) {
        SnackBarService.error(
          context,
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      notesCtrl.dispose();
      if (mounted) setState(() => _isSavingQuote = false);
    }
  }

  /// Punto 4 UX: Al tocar "Buscar complemento" (clavos, autoperforantes, tirantes),
  /// si el producto principal está seleccionado y aún no fue agregado al carrito,
  /// pregunta si desea agregarlo primero o solo ir a buscar el complemento,
  /// para jamás perder el cálculo realizado por accidente.
  Future<void> _handleComplementSearchTap(ComplementSuggestion comp) async {
    final summary = _activeSummary();
    if (_selectedProduct != null && !_currentItemAdded && summary.isValid) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AppModalShell(
          title: 'Buscar complemento: "${comp.searchKeyword}"',
          icon: Icons.handyman_rounded,
          accent: AppModalAccent.amber,
          compact: true,
          maxWidth: 460,
          useAlertDialogWrapper: true,
          onClose: () => Navigator.pop(ctx, 'cancel'),
          bodyPadding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          body: Text(
            'Tenés calculado "${_selectedProduct!.name}" (${summary.primaryHeadline}) pero todavía no lo agregaste.\n\n¿Querés agregarlo ahora antes de buscar "${comp.searchKeyword}"?',
            style: const TextStyle(fontSize: 13.5, height: 1.4),
          ),
          footerActions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Volver al Cálculo'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'search_only'),
              child: const Text('Solo Buscar Complemento'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'add_and_search'),
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 17),
              label: const Text('Agregar Cálculo y Buscar'),
            ),
          ],
        ),
      );

      if (choice == null || choice == 'cancel' || !mounted) return;
      if (choice == 'add_and_search') {
        await _handleAddToTarget(closeAfter: false);
      }
    }

    if (!mounted) return;
    widget.onSearchComplementRequested?.call(comp.searchKeyword);
    Navigator.of(context).pop(
      HardwareCalculatorOutput(
        product: _selectedProduct,
        billingQuantity: summary.billingQty,
        customDetails: summary.customDetailsNote,
        searchComplementKeyword: comp.searchKeyword,
        addedToTarget: _currentItemAdded,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final modalMaxWidth =
        math.min(1000.0, math.max(320.0, screenSize.width - 32));
    final modalMaxHeight =
        math.min(900.0, math.max(460.0, screenSize.height - 16));
    final summary = _activeSummary();
    final prod = _selectedProduct;
    final unitPrice = (prod != null && summary.isValid)
        ? _resolveUnitPriceForProduct(prod, summary.billingQty)
        : prod?.sellingPrice;
    final totalMoney = (unitPrice != null && summary.isValid)
        ? ProductPricingCalculator.roundMoney(unitPrice * summary.billingQty)
        : null;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: modalMaxWidth,
        height: modalMaxHeight,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            _buildHeader(screenSize.height),
            _buildProductSelectorAndTierBar(),
            _buildTabBar(),
            if (_selectedProduct != null &&
                _selectedProductInitialTab != null &&
                _activeTab != _selectedProductInitialTab)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: Colors.amber.shade50,
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El producto "${_selectedProduct!.name}" tiene configuración inicial de ${_tabDisplayName(_selectedProductInitialTab!)}. Si agregás desde esta pestaña se recalculará con las medidas actuales.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildWoodTab(),
                  _buildRoofTab(),
                  _buildPaintTab(),
                ],
              ),
            ),
            _buildLiveResultAndActionsFooter(
              summary: summary,
              unitPrice: unitPrice,
              totalMoney: totalMoney,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double screenHeight) {
    return AppModalHeader(
      title: 'Calculadora Rápida de Mostrador Ferretero (F7)',
      subtitle:
          'Calculá al instante tablas, paquetes, chapas o litros para consulta rápida, carrito o presupuesto',
      icon: Icons.straighten_rounded,
      accent: AppModalAccent.teal,
      compact: true,
    );
  }

  ButtonStyle get _tealSegmentedStyle => SegmentedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textSecondary,
        selectedBackgroundColor: AppColors.tealSoft,
        selectedForegroundColor: AppColors.tealDark,
        side: const BorderSide(color: AppColors.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  ChoiceChip _tealChoiceChip({
    required Widget label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      label: label,
      selected: selected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      selectedColor: AppColors.tealSoft,
      checkmarkColor: AppColors.tealDark,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? const Color(0xFF14B8A6) : AppColors.borderStrong,
      ),
      labelStyle: TextStyle(
        color: selected ? AppColors.tealDark : AppColors.textPrimary,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: onSelected,
    );
  }

  Widget _buildProductSelectorAndTierBar() {
    final settings = context.watch<SettingsProvider>().settings;
    final hasMultiPrice = settings?.hasAnyAlternativePriceTier == true;
    final customTiers = settings?.activeCustomPriceTiers ?? const [];

    final tierItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'base', child: Text('🏪 Lista Base')),
      if (settings?.isWholesaleTierAvailable == true)
        const DropdownMenuItem(value: 'wholesale', child: Text('🏭 Mayorista')),
      if (settings?.isCardTierAvailable == true)
        const DropdownMenuItem(value: 'card', child: Text('💳 Tarjeta')),
      ...customTiers.map((t) {
        final name = t['name']?.toString().trim() ?? '';
        final mod = (t['modifier'] as num?)?.toDouble() ?? 0.0;
        final sign = mod >= 0 ? '+' : '';
        return DropdownMenuItem(
          value: 'custom_$name',
          child: Text('🏷️ $name ($sign${mod.toStringAsFixed(0)}%)'),
        );
      }),
    ];

    final currentTierKey = _previewTier == PriceTier.custom
        ? (_previewCustomTierLabel != null
            ? 'custom_$_previewCustomTierLabel'
            : 'base')
        : _previewTier.name;
    final safeTierKey =
        tierItems.any((i) => i.value == currentTierKey) ? currentTierKey : 'base';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Buscador / Producto seleccionado
              Expanded(
                child: _selectedProduct != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: Color(0xFF16A34A), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedProduct!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      color: Color(0xFF14532D),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Cód: ${_selectedProduct!.internalCode} · Stock: ${_selectedProduct!.stock.toQty()} · Precio Lista: \$${_selectedProduct!.sellingPrice.toCurrency()}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF166534),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectRequestSeq++;
                                  _selectedProduct = null;
                                  _selectedProductInitialTab = null;
                                  _skuConfigDirty = false;
                                  _currentItemAdded = false;
                                });
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    _productSearchFocus.requestFocus();
                                  }
                                });
                              },
                              icon: const Icon(Icons.swap_horiz_rounded,
                                  size: 16),
                              label: const Text('Cambiar SKU',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      )
                    : TapRegion(
                        groupId: _skuHistoryTapGroupId,
                        child: OverlayPortal.overlayChildLayoutBuilder(
                          controller: _skuHistoryPortalController,
                          overlayChildBuilder: _buildSkuHistoryOverlay,
                          child: TextField(
                            controller: _productSearchCtrl,
                            focusNode: _productSearchFocus,
                            onTap: () {
                              if (_productSearchCtrl.text.trim().isEmpty) {
                                _showSkuHistoryPopoverIfAvailable();
                              }
                            },
                            onChanged: _onProductSearchChanged,
                            decoration: InputDecoration(
                              hintText:
                                  'Opcional: Buscá un producto del catálogo (ej. "Machimbre 4", "Chapa", "Látex") para ver precio total...',
                              hintStyle: const TextStyle(fontSize: 12.5),
                              prefixIcon: _isSearchingProducts
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    )
                                  : const Icon(Icons.search_rounded, size: 20),
                              suffixIcon: _productSearchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _productSearchCtrl.clear();
                                        _onProductSearchChanged('');
                                      },
                                    )
                                  : Builder(
                                      builder: (ctx) {
                                        final localTerminal =
                                            tryGetLocalTerminalProvider(ctx,
                                                listen: true);
                                        final catalog =
                                            ctx.watch<CatalogProvider>();
                                        if (!_hasSkuHistoryEntries(
                                            catalog, localTerminal)) {
                                          return const SizedBox.shrink();
                                        }
                                        return Focus(
                                          canRequestFocus: false,
                                          descendantsAreFocusable: false,
                                          child: Tooltip(
                                            message: 'Búsquedas recientes (F7)',
                                            child: IconButton(
                                              key: const ValueKey(
                                                  'f7_sku_history_toggle_btn'),
                                              icon: Icon(
                                                Icons.history_rounded,
                                                size: 19,
                                                color:
                                                    _skuHistoryPortalController
                                                            .isShowing
                                                        ? const Color(0xFF0F766E)
                                                        : Colors.blueGrey.shade600,
                                              ),
                                              onPressed: () {
                                                if (_skuHistoryPortalController
                                                    .isShowing) {
                                                  _hideSkuHistoryPopover();
                                                } else {
                                                  _showSkuHistoryPopoverIfAvailable();
                                                }
                                                _productSearchFocus
                                                    .requestFocus();
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              if (hasMultiPrice) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueGrey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: safeTierKey,
                      isDense: true,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                      items: tierItems,
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() {
                          if (val == 'base') {
                            _previewTier = PriceTier.base;
                            _previewCustomTierLabel = null;
                            _previewCustomFactor = 1.0;
                          } else if (val == 'wholesale') {
                            _previewTier = PriceTier.wholesale;
                            _previewCustomTierLabel = null;
                            _previewCustomFactor = 1.0;
                          } else if (val == 'card') {
                            _previewTier = PriceTier.card;
                            _previewCustomTierLabel = null;
                            _previewCustomFactor = 1.0;
                          } else if (val.startsWith('custom_')) {
                            final label = val.substring(7);
                            final match = customTiers.firstWhere(
                              (t) =>
                                  (t['name'] ?? '').toString().trim() == label,
                              orElse: () => const {'modifier': 0.0},
                            );
                            final mod =
                                (match['modifier'] as num?)?.toDouble() ?? 0.0;
                            _previewTier = PriceTier.custom;
                            _previewCustomTierLabel = label;
                            _previewCustomFactor = 1.0 + (mod / 100.0);
                          }
                        });
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Resultados desplegables del buscador de producto
          if (_selectedProduct == null && _searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 165),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final item = _searchResults[i];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      item.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    subtitle: Text(
                      'Cód: ${item.internalCode} · Stock: ${item.stock.toQty()}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      '\$${item.sellingPrice.toCurrency()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF15803D),
                      ),
                    ),
                    onTap: () => _selectProduct(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF0F766E),
        unselectedLabelColor: Colors.blueGrey.shade600,
        indicatorColor: const Color(0xFF0F766E),
        indicatorWeight: 3,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
        tabs: const [
          Tab(
            height: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.carpenter_rounded, size: 18),
                  SizedBox(width: 7),
                  Text('🪵 Machimbre / Maderas'),
                ],
              ),
            ),
          ),
          Tab(
            height: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.roofing_rounded, size: 18),
                  SizedBox(width: 7),
                  Text('🏠 Chapas / Techos'),
                ],
              ),
            ),
          ),
          Tab(
            height: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.format_paint_rounded, size: 18),
                  SizedBox(width: 7),
                  Text('🎨 Pintura / Membrana'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PESTAÑA 1: MACHIMBRE / MADERAS ─────────────────────────────────────────
  Widget _buildWoodTab() {
    final res = _computeWood();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Columna Izquierda: Qué necesita cubrir el cliente
              Expanded(
                flex: 5,
                child: _sectionCard(
                  title: '1. ¿Qué superficie necesita cubrir el cliente?',
                  icon: Icons.aspect_ratio_rounded,
                  accent: const Color(0xFF0F766E),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<bool>(
                          style: _tealSegmentedStyle,
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Ancho × Largo (Pieza)',
                                  style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.grid_on_rounded, size: 16),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('m² Directos',
                                  style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.square_foot_rounded, size: 16),
                            ),
                          ],
                          selected: {_woodUseDirectM2},
                          onSelectionChanged: (s) =>
                              setState(() => _woodUseDirectM2 = s.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_woodUseDirectM2)
                        Row(
                          children: [
                            Expanded(
                              child: _numField(
                                controller: _woodRoomWidthCtrl,
                                label: 'Ancho pieza (m)',
                                suffix: 'm',
                                marksSkuConfigDirty: false,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('×',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              child: _numField(
                                controller: _woodRoomLengthCtrl,
                                label: 'Largo pieza (m)',
                                suffix: 'm',
                                marksSkuConfigDirty: false,
                              ),
                            ),
                          ],
                        )
                      else
                        _numField(
                          controller: _woodDirectM2Ctrl,
                          label: 'Superficie total a cubrir',
                          suffix: 'm²',
                          marksSkuConfigDirty: false,
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Margen por desperdicio / cortes:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [0.0, 5.0, 10.0, 15.0].map((pct) {
                          final selected = (_woodWastePct - pct).abs() < 0.1;
                          return _tealChoiceChip(
                            label: Text(
                              pct == 0 ? '0% (Exacto)' : '+${pct.toInt()}%',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: selected,
                            onSelected: (_) => setState(() {
                              _woodWastePct = pct;
                              _skuConfigDirty = true;
                            }),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Columna Derecha: Medidas de la Tabla y Modalidad de Precio
              Expanded(
                flex: 6,
                child: _sectionCard(
                  title: '2. Medida del Machimbre y Modalidad de Cobro',
                  icon: Icons.tune_rounded,
                  accent: const Color(0xFF1D4ED8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_missingWoodWidthWarning) ...[
                        Container(
                          key: const ValueKey('pos_f7_missing_width_warning'),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 16, color: Colors.amber.shade900),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Se detectó ${_detectedWoodThicknessLabel ?? "el espesor"} y el largo, pero falta el ancho de la tabla. Confirmá las pulgadas (4", 6", 8", etc.) antes de calcular.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Text(
                        'Pulgada (Ancho Nominal vs. Útil con encastre):',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          ...HardwareCalculatorEngine.woodInchPresets.map((p) {
                            final selected = _woodInchPreset == p.key;
                            return ChoiceChip(
                              key: ValueKey('pos_f7_wood_inch_${p.key}'),
                              label: Text('${p.key}"',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              selected: selected,
                              showCheckmark: false,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              selectedColor: AppColors.tealSoft,
                              checkmarkColor: AppColors.tealDark,
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: selected
                                    ? const Color(0xFF14B8A6)
                                    : AppColors.borderStrong,
                              ),
                              labelStyle: TextStyle(
                                color: selected
                                    ? AppColors.tealDark
                                    : AppColors.textPrimary,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              onSelected: (_) => setState(() {
                                _woodInchPreset = p.key;
                                _woodNominalWidthCmCtrl.text =
                                    _fmtInput(p.nominalWidthM * 100);
                                _woodUsefulWidthCmCtrl.text =
                                    _fmtInput(p.usefulWidthM * 100);
                                _missingWoodWidthWarning = false;
                                _skuConfigDirty = true;
                              }),
                            );
                          }),
                          _tealChoiceChip(
                            label: const Text('Manual'),
                            selected: _woodInchPreset == 'custom',
                            onSelected: (_) => setState(() {
                              _woodInchPreset = 'custom';
                              _missingWoodWidthWarning = false;
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _numField(
                              controller: _woodUsefulWidthCmCtrl,
                              label: 'Ancho ÚTIL (cubre)',
                              suffix: 'cm',
                              onChanged: (_) => setState(() {
                                _woodInchPreset = 'custom';
                                _missingWoodWidthWarning = false;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numField(
                              controller: _woodNominalWidthCmCtrl,
                              label: 'Ancho NOMINAL',
                              suffix: 'cm',
                              onChanged: (_) => setState(() {
                                _woodInchPreset = 'custom';
                                _missingWoodWidthWarning = false;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numField(
                              controller: _woodBoardLengthMCtrl,
                              label: 'Largo Tabla',
                              suffix: 'm',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: ['2.00', '2.40', '3.00', '3.60', '4.00', '4.20']
                            .map((l) => ActionChip(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 0),
                                  label: Text('${l}m',
                                      style: const TextStyle(fontSize: 11)),
                                  onPressed: () => setState(() {
                                    _woodBoardLengthMCtrl.text = l;
                                    _skuConfigDirty = true;
                                  }),
                                ))
                            .toList(),
                      ),
                      const Divider(height: 10),
                      const Text(
                        '¿Cómo está cargado el precio en tu catálogo?',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          _modeChip(
                            label: 'Por Tabla (u.)',
                            selected:
                                _woodPricingMode == WoodPricingMode.perBoard,
                            onTap: () => setState(() =>
                                _woodPricingMode = WoodPricingMode.perBoard),
                          ),
                          _modeChip(
                            label: 'Por m²',
                            selected: _woodPricingMode == WoodPricingMode.perM2,
                            onTap: () => setState(
                                () => _woodPricingMode = WoodPricingMode.perM2),
                          ),
                          _modeChip(
                            label: 'Por Metro Lineal (ml)',
                            selected: _woodPricingMode ==
                                WoodPricingMode.perLinearMeter,
                            onTap: () => setState(() => _woodPricingMode =
                                WoodPricingMode.perLinearMeter),
                          ),
                          _modeChip(
                            label: 'Por Paquete',
                            selected:
                                _woodPricingMode == WoodPricingMode.perPack,
                            onTap: () => setState(() =>
                                _woodPricingMode = WoodPricingMode.perPack),
                          ),
                        ],
                      ),
                      if (_woodPricingMode == WoodPricingMode.perM2) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Protección contra subfacturación por encastre:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: SegmentedButton<M2BillingBasis>(
                                  style: _tealSegmentedStyle,
                                  segments: const [
                                    ButtonSegment(
                                      value: M2BillingBasis.nominal,
                                      label: Text(
                                        'Cobrar m² Nominales (Estándar)',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: M2BillingBasis.useful,
                                      label: Text(
                                        'Cobrar m² Útiles',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                  ],
                                  selected: {_woodM2Basis},
                                  onSelectionChanged: (s) => setState(() {
                                    _woodM2Basis = s.first;
                                    _skuConfigDirty = true;
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_woodPricingMode == WoodPricingMode.perPack) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SizedBox(
                              width: 130,
                              child: _numField(
                                controller: _woodBoardsPerPackCtrl,
                                label: 'Tablas x Paquete',
                                suffix: 'u.',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: _woodRoundToFullPack,
                                title: const Text(
                                  'Redondear a paquete cerrado',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                                onChanged: (v) => setState(() {
                                  _woodRoundToFullPack = v ?? false;
                                  _skuConfigDirty = true;
                                }),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (res.isValid && res.complements.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildComplementsBar(res.complements),
          ],
        ],
      ),
    );
  }

  // ── PESTAÑA 2: CHAPAS / TECHOS ─────────────────────────────────────────────
  Widget _buildRoofTab() {
    final res = _computeRoof();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _sectionCard(
                  title: '1. Dimensiones del Techo a Cubrir',
                  icon: Icons.roofing_rounded,
                  accent: const Color(0xFF0F766E),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<bool>(
                          key: const ValueKey('roof_input_mode_segmented'),
                          style: _tealSegmentedStyle,
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Ancho × Caída',
                                  style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.grid_on_rounded, size: 16),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('m² Directos',
                                  style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.square_foot_rounded, size: 16),
                            ),
                          ],
                          selected: {_roofUseDirectM2},
                          onSelectionChanged: (s) => setState(() {
                            final nextDirect = s.first;
                            if (nextDirect && !_roofUseDirectM2) {
                              final currentArea =
                                  _parseNum(_roofWidthCtrl.text) *
                                      _parseNum(_roofSlopeLengthCtrl.text);
                              if (currentArea > 0) {
                                _roofDirectM2Ctrl.text = _fmtInput(currentArea);
                              }
                            }
                            _roofUseDirectM2 = nextDirect;
                          }),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!_roofUseDirectM2) ...[
                        _numField(
                          controller: _roofWidthCtrl,
                          label: 'Ancho del Techo (perpendicular a la caída)',
                          suffix: 'm',
                          marksSkuConfigDirty: false,
                        ),
                        const SizedBox(height: 10),
                        _numField(
                          controller: _roofSlopeLengthCtrl,
                          label: 'Largo de la Caída / Agua (pendiente)',
                          suffix: 'm',
                          marksSkuConfigDirty: false,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Superficie geométrica del techo: ${(_parseNum(_roofWidthCtrl.text) * _parseNum(_roofSlopeLengthCtrl.text)).toQty()} m²',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.teal.shade800,
                          ),
                        ),
                        if (res.isValid && res.rowsAlongSlope > 1) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Text(
                              'La caída (${res.roofSlopeLengthM.toQty()}m) supera el largo de la chapa (${_fmtInput(_parseNum(_sheetLengthMCtrl.text))}m): requiere ${res.rowsAlongSlope} tramos por hilada (${res.surplusPerColumnM > 0.05 ? "cubre ${res.coveredSlopeLengthM.toQty()}m, recorte ${res.surplusPerColumnM.toQty()}m/hilada" : "medida exacta"}).',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ] else ...[
                        _numField(
                          fieldKey: const ValueKey('roof_direct_m2_field'),
                          controller: _roofDirectM2Ctrl,
                          label: 'Superficie total del techo',
                          suffix: 'm²',
                          marksSkuConfigDirty: false,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Margen por cortes / solapes:',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [0.0, 5.0, 10.0, 15.0].map((pct) {
                            final selected = (_roofWastePct - pct).abs() < 0.1;
                            return _tealChoiceChip(
                              label: Text(
                                pct == 0 ? '0% (Exacto)' : '+${pct.toInt()}%',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _roofWastePct = pct),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Text(
                            'Cálculo orientativo por superficie. En chapas, el largo de la caída puede requerir más unidades por cortes o solapes; confirmá Ancho × Caída antes de entregar.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade900,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 6,
                child: _sectionCard(
                  title: '2. Medida de Chapa, Solapes y Modalidad',
                  icon: Icons.straighten_rounded,
                  accent: const Color(0xFF1D4ED8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _numField(
                              controller: _sheetNominalWidthMCtrl,
                              label: 'Ancho Total Chapa',
                              suffix: 'm',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numField(
                              controller: _sheetUsefulWidthMCtrl,
                              label: 'Ancho ÚTIL (c/ solape)',
                              suffix: 'm',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _numField(
                              controller: _sheetLengthMCtrl,
                              label: 'Largo de Chapa disponible',
                              suffix: 'm',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numField(
                              controller: _sheetLongOverlapCmCtrl,
                              label: 'Solape Longitudinal',
                              suffix: 'cm',
                              enabled: !_roofUseDirectM2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          '2.00',
                          '2.50',
                          '3.00',
                          '3.50',
                          '4.00',
                          '4.50',
                          '5.00',
                          '6.00'
                        ]
                            .map((l) => ActionChip(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 0),
                                  label: Text('${l}m',
                                      style: const TextStyle(fontSize: 11)),
                                  onPressed: () => setState(() {
                                    _sheetLengthMCtrl.text = l;
                                    _skuConfigDirty = true;
                                  }),
                                ))
                            .toList(),
                      ),
                      const Divider(height: 10),
                      const Text(
                        '¿Cómo está cargado el precio en tu catálogo?',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          _modeChip(
                            label: 'Por Chapa (Unidad)',
                            selected:
                                _roofPricingMode == RoofPricingMode.perSheet,
                            onTap: () => setState(() =>
                                _roofPricingMode = RoofPricingMode.perSheet),
                          ),
                          _modeChip(
                            label: 'Por Metro Lineal (ml)',
                            selected: _roofPricingMode ==
                                RoofPricingMode.perLinearMeter,
                            onTap: () => setState(() => _roofPricingMode =
                                RoofPricingMode.perLinearMeter),
                          ),
                          _modeChip(
                            label: 'Por m²',
                            selected: _roofPricingMode == RoofPricingMode.perM2,
                            onTap: () => setState(() =>
                                _roofPricingMode = RoofPricingMode.perM2),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (res.isValid && res.complements.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildComplementsBar(res.complements),
          ],
        ],
      ),
    );
  }

  // ── PESTAÑA 3: PINTURA Y MEMBRANA LÍQUIDA ─────────────────────────────────
  Widget _buildPaintTab() {
    final res = _computePaint();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _sectionCard(
                  title: '1. Superficie a Pintar / Impermeabilizar',
                  icon: Icons.format_paint_rounded,
                  accent: const Color(0xFF0F766E),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<bool>(
                          style: _tealSegmentedStyle,
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Ancho × Alto/Largo',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('m² Totales',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                          selected: {_paintUseDirectM2},
                          onSelectionChanged: (s) =>
                              setState(() => _paintUseDirectM2 = s.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_paintUseDirectM2)
                        Row(
                          children: [
                            Expanded(
                              child: _numField(
                                controller: _paintWallWidthCtrl,
                                label: 'Largo / Ancho (m)',
                                suffix: 'm',
                                marksSkuConfigDirty: false,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('×',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              child: _numField(
                                controller: _paintWallHeightCtrl,
                                label: 'Alto / Fondo (m)',
                                suffix: 'm',
                                marksSkuConfigDirty: false,
                              ),
                            ),
                          ],
                        )
                      else
                        _numField(
                          controller: _paintDirectM2Ctrl,
                          label: 'Superficie total (m²)',
                          suffix: 'm²',
                          marksSkuConfigDirty: false,
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Cantidad de manos:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [1, 2, 3, 4].map((c) {
                          return _tealChoiceChip(
                            label: Text('$c ${c == 1 ? "mano" : "manos"}'),
                            selected: _paintCoats == c,
                            onSelected: (_) => setState(() => _paintCoats = c),
                          );
                        }).toList(),
                      ),
                      if (_paintYieldMode == PaintYieldMode.finalTotal) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Nota: En modo "Rendimiento final (Membrana)", las manos son referencia visual; el cálculo usa el rendimiento total final.',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 6,
                child: _sectionCard(
                  title: '2. Rendimiento y Capacidad del Envase (SKU)',
                  icon: Icons.science_rounded,
                  accent: const Color(0xFF1D4ED8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Presets rápidos por tipo de producto:',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          ActionChip(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            label: const Text('Látex (10 m²/L x mano)',
                                style: TextStyle(fontSize: 11.5)),
                            onPressed: () => setState(() {
                              _paintYieldMode = PaintYieldMode.perCoat;
                              _paintYieldCtrl.text = '10';
                              _paintCoats = 2;
                              _skuConfigDirty = true;
                            }),
                          ),
                          ActionChip(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            label: const Text('Sintético (12 m²/L x mano)',
                                style: TextStyle(fontSize: 11.5)),
                            onPressed: () => setState(() {
                              _paintYieldMode = PaintYieldMode.perCoat;
                              _paintYieldCtrl.text = '12';
                              _paintCoats = 2;
                              _skuConfigDirty = true;
                            }),
                          ),
                          ActionChip(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            label: const Text(
                                'Membrana Líquida (1 m²/Kg final)',
                                style: TextStyle(fontSize: 11.5)),
                            onPressed: () => setState(() {
                              _paintYieldMode = PaintYieldMode.finalTotal;
                              _paintYieldCtrl.text = '1.0';
                              _paintContainerLitersCtrl.text = '20';
                              _paintCoats = 3;
                              _skuConfigDirty = true;
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _numField(
                              controller: _paintYieldCtrl,
                              label: _paintYieldMode == PaintYieldMode.finalTotal
                                  ? 'Rendimiento FINAL (m²/L o Kg)'
                                  : 'Rendimiento POR MANO (m²/L)',
                              suffix: 'm²/L',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numField(
                              controller: _paintContainerLitersCtrl,
                              label: 'Litros / Kg del Envase',
                              suffix: 'L/Kg',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: ['1', '4', '10', '20']
                            .map((cap) => ActionChip(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 0),
                                  label: Text('$cap L/Kg',
                                      style: const TextStyle(fontSize: 11)),
                                  onPressed: () => setState(() {
                                    _paintContainerLitersCtrl.text = cap;
                                    _skuConfigDirty = true;
                                  }),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<PaintYieldMode>(
                          style: _tealSegmentedStyle,
                          segments: const [
                            ButtonSegment(
                              value: PaintYieldMode.perCoat,
                              label: Text(
                                'Rendimiento por mano (× manos)',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                            ButtonSegment(
                              value: PaintYieldMode.finalTotal,
                              label: Text(
                                'Rendimiento final (Membrana)',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                          selected: {_paintYieldMode},
                          onSelectionChanged: (s) => setState(() {
                            _paintYieldMode = s.first;
                            _skuConfigDirty = true;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (res.isValid && res.complements.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildComplementsBar(res.complements),
          ],
        ],
      ),
    );
  }

  Widget _buildComplementsBar(List<ComplementSuggestion> complements) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              color: Colors.amber.shade900, size: 20),
          const SizedBox(width: 8),
          Text(
            'Complementos sugeridos:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.amber.shade900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: complements.map((c) {
                return Tooltip(
                  message:
                      '${c.detailHint}\nToca para buscar "${c.searchKeyword}" en el catálogo',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _handleComplementSearchTap(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              '${c.title}: ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: Color(0xFF475569)),
                            ),
                          ),
                          Text(
                            c.quantityLabel,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(Icons.search_rounded,
                              size: 14, color: Colors.blue.shade700),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _singularUnitLabel(String unitLabel) {
    switch (unitLabel) {
      case 'chapas':
        return 'chapa';
      case 'tablas':
        return 'tabla';
      case 'paquetes':
        return 'paquete';
      case 'envases':
        return 'envase';
      default:
        return unitLabel;
    }
  }

  Widget _buildLiveResultAndActionsFooter({
    required ({
      bool isValid,
      String? error,
      double billingQty,
      String billingUnit,
      String primaryHeadline,
      String secondarySubtitle,
      String customDetailsNote,
      List<ComplementSuggestion> complements,
    }) summary,
    required double? unitPrice,
    required double? totalMoney,
  }) {
    final hasQuotes =
        context.watch<SettingsProvider>().settings?.features.quotes ?? true;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Panel de Resultado Gigante en Vivo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: summary.isValid
                  ? const Color(0xFFF0FDFA)
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: summary.isValid
                    ? const Color(0xFF5EEAD4)
                    : Colors.red.shade200,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F766E),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'RESULTADO A ENTREGAR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          if (summary.isValid) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Facturación: ${summary.billingQty.toQty()} ${summary.billingUnit}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary.primaryHeadline,
                        style: TextStyle(
                          fontSize: 18.5,
                          fontWeight: FontWeight.w900,
                          color: summary.isValid
                              ? const Color(0xFF0F172A)
                              : Colors.red.shade800,
                        ),
                      ),
                      Text(
                        summary.secondarySubtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Precio Total en Vivo (si hay SKU seleccionado)
                if (_selectedProduct != null && totalMoney != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF16A34A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Unitario: \$${unitPrice!.toCurrency()} / ${_singularUnitLabel(summary.billingUnit)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '\$${totalMoney.toCurrency()}',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Text(
                      'Elegí un producto arriba\npara ver el \$ Total',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Botones de Acción para los 2 escenarios de mostrador
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    if (_skuConfigDirty &&
                        _selectedProduct != null &&
                        summary.isValid &&
                        (_selectedProductInitialTab == null ||
                            _activeTab == _selectedProductInitialTab)) {
                      await _persistSelectedProductConfigIfNeeded();
                    }
                    if (mounted) Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Solo Consulta · Cerrar (Esc)'),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.target == HardwareCalculatorTarget.pos &&
                        hasQuotes)
                      OutlinedButton.icon(
                        onPressed: (!summary.isValid ||
                                _selectedProduct == null ||
                                _isSavingQuote)
                            ? null
                            : _handleSendToStandaloneQuote,
                        icon:
                            const Icon(Icons.request_quote_outlined, size: 18),
                        label: const Text('📄 Enviar a Presupuesto'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.indigo,
                          side: const BorderSide(color: AppColors.indigo),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: (!summary.isValid || _selectedProduct == null)
                          ? null
                          : () => _handleAddToTarget(closeAfter: true),
                      icon:
                          const Icon(Icons.add_shopping_cart_rounded, size: 19),
                      label: Text(
                        widget.replacingCartItem != null
                            ? 'Actualizar Línea en Carrito'
                            : (widget.target == HardwareCalculatorTarget.quote
                                ? 'Agregar al Presupuesto'
                                : 'Agregar al Carrito'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.tealDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color accent,
    required Widget child,
  }) {
    return AppSectionCard(
      title: title,
      icon: icon,
      accent: accent,
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }

  Widget _numField({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    required String suffix,
    bool marksSkuConfigDirty = true,
    bool enabled = true,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      maxLength: 10,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      onChanged: (v) {
        if (marksSkuConfigDirty) _skuConfigDirty = true;
        onChanged?.call(v);
        setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        suffixText: suffix,
        counterText: '',
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _modeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return _tealChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      selected: selected,
      onSelected: (_) {
        _skuConfigDirty = true;
        onTap();
      },
    );
  }
}
