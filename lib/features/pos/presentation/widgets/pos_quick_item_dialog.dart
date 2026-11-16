import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/scale_serial_service.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/utils/combo_fraction_pricing.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

/// Resultado devuelto por [PosQuickItemDialog]: incluye el ítem armado
/// y, cuando se armó un Combo tomando ítems existentes del carrito, la lista
/// de líneas originales a reemplazar en el carrito para no duplicar cobros ni stock.
class PosQuickItemResult {
  final CartItem item;
  final List<CartItem> replacedCartItems;

  const PosQuickItemResult({
    required this.item,
    this.replacedCartItems = const [],
  });
}

class PosQuickItemDialog extends StatefulWidget {
  final PriceTier activeTier;
  final double wholesaleFactor;
  final double cardFactor;
  final double customFactor;
  final String? customTierLabel;
  final String? initialQuery;

  const PosQuickItemDialog({
    super.key,
    this.activeTier = PriceTier.base,
    this.wholesaleFactor = 1.0,
    this.cardFactor = 1.0,
    this.customFactor = 1.0,
    this.customTierLabel,
    this.initialQuery,
  });

  static Future<PosQuickItemResult?> show(
    BuildContext context, {
    PriceTier activeTier = PriceTier.base,
    double wholesaleFactor = 1.0,
    double cardFactor = 1.0,
    double customFactor = 1.0,
    String? customTierLabel,
    String? initialQuery,
  }) {
    return showDialog<PosQuickItemResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PosQuickItemDialog(
        activeTier: activeTier,
        wholesaleFactor: wholesaleFactor,
        cardFactor: cardFactor,
        customFactor: customFactor,
        customTierLabel: customTierLabel,
        initialQuery: initialQuery,
      ),
    );
  }

  @override
  State<PosQuickItemDialog> createState() => _PosQuickItemDialogState();
}

class _PosQuickItemDialogState extends State<PosQuickItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _detailsController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _costController = TextEditingController();
  final _marginController = TextEditingController();

  final _nameFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _quantityFocus = FocusNode();

  bool _isComboMode = false;
  bool _isServiceMode = false;
  bool _saveToCatalog = true;
  bool _userToggledSaveToCatalog = false;
  bool _isSoldByWeight = false;
  bool _isReadingScale = false;
  double _ivaRate = 21.0;
  bool _isUpdatingCalc = false;
  String? _priceAnchor; // 'cost' | 'selling'
  bool _costIsAuto = false;
  bool _priceIsAuto = false;

  // Constructor rápido de Combo / Promoción en mostrador
  static const List<(String, double)> _comboPortionPresets = [
    ('1/6', 0.167),
    ('1/8', 0.125),
    ('1/10', 0.1),
    ('1/12', 0.083),
    ('1', 1.0),
  ];
  final List<Map<String, dynamic>> _comboIngredients = [];
  final Map<int, TextEditingController> _comboQtyCtrls = {};
  final Map<int, TextEditingController> _comboCustomPartsCtrls = {};
  final Set<int> _expandedFractionIngredientIds = <int>{};
  bool? _manualPortionPricingMode;
  final _comboSearchCtrl = TextEditingController();
  final _comboSearchFocus = FocusNode();
  List<Product> _comboSearchResults = [];
  bool _isSearchingCombo = false;
  Timer? _comboSearchDebounce;
  final List<CartItem> _pulledCartItems = [];
  bool _replacePulledCartItems = true;
  String? _scannedReferenceCode;

  static bool _looksLikeBarcode(String raw) =>
      RegExp(r'^(?=.*\d)[A-Za-z0-9\-_]{5,32}$').hasMatch(raw.trim());

  Future<void> _readWeightFromScale(String comPort) async {
    final trimmedPort = comPort.trim();
    if (trimmedPort.isEmpty) {
      showTerminalPeripheralsDialog(context);
      return;
    }
    if (_isReadingScale) return;
    setState(() => _isReadingScale = true);
    try {
      final result = await ScaleSerialService.instance.readWeight(trimmedPort);
      if (!mounted) return;
      if (result.success && result.weightKg != null) {
        final weightStr = result.weightKg!.toStringAsFixed(3);
        setState(() {
          _quantityController.text = weightStr;
          _quantityController.selection = TextSelection.fromPosition(
            TextPosition(offset: weightStr.length),
          );
        });
        SnackBarService.success(context, 'Lectura exitosa: $weightStr Kg');
      } else {
        SnackBarService.error(
          context,
          result.errorMessage ?? 'No se pudo obtener el peso de la balanza.',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al comunicar con la balanza: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isReadingScale = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleDialogKey);

    final rawInitial = widget.initialQuery?.trim() ?? '';
    final prefilledAsName =
        rawInitial.isNotEmpty && !_looksLikeBarcode(rawInitial);
    if (rawInitial.isNotEmpty) {
      if (prefilledAsName) {
        _nameController.text = rawInitial;
      } else {
        _scannedReferenceCode = rawInitial;
        _detailsController.text = 'Cód. consultado: $rawInitial';
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (prefilledAsName) {
          _priceFocus.requestFocus();
        } else {
          _nameFocus.requestFocus();
        }
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleDialogKey);
    _comboSearchDebounce?.cancel();
    _comboSearchCtrl.dispose();
    _comboSearchFocus.dispose();
    for (final ctrl in _comboQtyCtrls.values) {
      ctrl.dispose();
    }
    _comboQtyCtrls.clear();
    for (final ctrl in _comboCustomPartsCtrls.values) {
      ctrl.dispose();
    }
    _comboCustomPartsCtrls.clear();
    _nameController.dispose();
    _detailsController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _marginController.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    _quantityFocus.dispose();
    super.dispose();
  }

  String _formatComboQty(double qty) => formatQuantityInput(qty);

  double get _comboIndividualTotal => _comboIngredients.fold<double>(
        0.0,
        (acc, ing) =>
            acc +
            ((ing['selling_price'] as num?)?.toDouble() ?? 0.0) *
                ((ing['quantity'] as num?)?.toDouble() ?? 1.0),
      );

  double get _comboCostTotal => _comboIngredients.fold<double>(
        0.0,
        (acc, ing) =>
            acc +
            ((ing['cost_price'] as num?)?.toDouble() ?? 0.0) *
                ((ing['quantity'] as num?)?.toDouble() ?? 1.0),
      );

  TextEditingController _qtyCtrlForIngredient(int productId, double qty) {
    return _comboQtyCtrls.putIfAbsent(
      productId,
      () => TextEditingController(text: _formatComboQty(qty)),
    );
  }

  String _buildComboIngredientsSummary() {
    return _comboIngredients
        .map((ing) =>
            '${_formatComboQty((ing['quantity'] as num?)?.toDouble() ?? 1.0)}x ${ing['name']}')
        .join(' + ');
  }

  Widget _buildReadonlyComboMetricBox({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurple.shade100),
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

  Widget _buildComboPriceSuggestionButton({
    required Key key,
    required double targetPrice,
    required String label,
    required String appliedLabel,
    required double currentUnitPrice,
    bool isMarkup = false,
  }) {
    final isApplied =
        currentUnitPrice > 0 && (currentUnitPrice - targetPrice).abs() < 0.01;
    return OutlinedButton.icon(
      key: key,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        foregroundColor:
            isApplied ? Colors.green.shade800 : Colors.deepPurple.shade800,
        backgroundColor:
            isApplied ? Colors.green.shade50 : Colors.deepPurple.shade50,
        side: BorderSide(
          color:
              isApplied ? Colors.green.shade300 : Colors.deepPurple.shade300,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      onPressed: () {
        setState(() {
          _priceIsAuto = false;
          _priceController.text = targetPrice.toArsInput();
        });
      },
      icon: Icon(
        isApplied
            ? Icons.check_circle_outline
            : (isMarkup
                ? Icons.trending_up_rounded
                : Icons.auto_fix_high_rounded),
        size: 13.5,
      ),
      label: Text(
        isApplied ? appliedLabel : label,
        style: const TextStyle(fontSize: 11.2, fontWeight: FontWeight.w700),
      ),
    );
  }

  void _addIngredientToCombo(Product product, {double qty = 1.0}) {
    if (product.id <= 0) return;
    final existingIdx =
        _comboIngredients.indexWhere((e) => e['id'] == product.id);
    setState(() {
      if (existingIdx >= 0) {
        final newQty =
            ((_comboIngredients[existingIdx]['quantity'] as num?)?.toDouble() ??
                    1.0) +
                qty;
        _comboIngredients[existingIdx]['quantity'] = newQty;
        _comboQtyCtrls[product.id]?.text = _formatComboQty(newQty);
      } else {
        _comboIngredients.add({
          'id': product.id,
          'name': product.name,
          'quantity': qty,
          'cost_price': product.costPrice,
          'selling_price': product.sellingPrice,
          'stock': product.stock,
          'is_sold_by_weight': product.isSoldByWeight,
        });
        _qtyCtrlForIngredient(product.id, qty);
      }
      _comboSearchCtrl.clear();
      _comboSearchResults = [];
    });
  }

  void _updateComboIngredientQty(int productId, double newQty) {
    final idx = _comboIngredients.indexWhere((e) => e['id'] == productId);
    if (idx < 0) return;
    setState(() {
      _comboIngredients[idx]['quantity'] = newQty;
    });
  }

  void _applyComboIngredientPreset(int productId, double presetQty) {
    final idx = _comboIngredients.indexWhere((e) => e['id'] == productId);
    if (idx < 0) return;
    setState(() {
      _comboIngredients[idx]['quantity'] = presetQty;
      final ctrl = _qtyCtrlForIngredient(productId, presetQty);
      final text = _formatComboQty(presetQty);
      ctrl.text = text;
      ctrl.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  TextEditingController _customPartsCtrlForIngredient(int productId) {
    return _comboCustomPartsCtrls.putIfAbsent(
      productId,
      () => TextEditingController(),
    );
  }

  void _applyCustomComboIngredientParts(int productId) {
    final raw = _comboCustomPartsCtrls[productId]?.text.trim() ?? '';
    final parts = int.tryParse(raw);
    if (parts == null || parts < 2 || parts > 100) {
      SnackBarService.warning(
        context,
        'Ingresá una cantidad de partes entre 2 y 100 (ej: 16).',
      );
      return;
    }
    _applyComboIngredientPreset(productId, 1.0 / parts);
  }

  void _removeComboIngredient(int productId) {
    setState(() {
      _comboIngredients.removeWhere((e) => e['id'] == productId);
      _comboQtyCtrls.remove(productId)?.dispose();
      _comboCustomPartsCtrls.remove(productId)?.dispose();
      _expandedFractionIngredientIds.remove(productId);
      _pulledCartItems.removeWhere((c) => c.product.id == productId);
    });
  }

  List<CartItem> _getEligibleCartItems() {
    try {
      final cart = context.read<PosProvider>().cart;
      return cart
          .where((c) =>
              !c.isTemporary &&
              !c.product.isService &&
              !c.product.isCombo &&
              c.product.id > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _pullItemsFromCart() {
    final eligible = _getEligibleCartItems();
    if (eligible.isEmpty) {
      SnackBarService.info(
        context,
        'No hay productos de catálogo elegibles en el carrito.',
      );
      return;
    }

    final merged = <int, Map<String, dynamic>>{};
    for (final cartItem in eligible) {
      final p = cartItem.product;
      final lineQty = cartItem.quantity;
      if (merged.containsKey(p.id)) {
        merged[p.id]!['quantity'] =
            ((merged[p.id]!['quantity'] as num).toDouble()) + lineQty;
      } else {
        merged[p.id] = {
          'id': p.id,
          'name': p.name,
          'quantity': lineQty,
          'cost_price': p.costPrice,
          'selling_price': p.sellingPrice,
          'stock': p.stock,
          'is_sold_by_weight': p.isSoldByWeight,
        };
      }
    }

    setState(() {
      for (final ctrl in _comboQtyCtrls.values) {
        ctrl.dispose();
      }
      _comboQtyCtrls.clear();
      for (final ctrl in _comboCustomPartsCtrls.values) {
        ctrl.dispose();
      }
      _comboCustomPartsCtrls.clear();
      _comboIngredients
        ..clear()
        ..addAll(merged.values);
      for (final ing in _comboIngredients) {
        _qtyCtrlForIngredient(
          ing['id'] as int,
          (ing['quantity'] as num).toDouble(),
        );
      }
      _pulledCartItems
        ..clear()
        ..addAll(eligible);
      _replacePulledCartItems = true;
      _quantityController.text = '1';
      if (_nameController.text.trim().isEmpty) {
        _nameController.text =
            'Combo Mostrador (${_comboIngredients.length} art.)';
      }
    });
    _priceFocus.requestFocus();
  }

  void _onComboSearchChanged(String rawQuery) {
    _comboSearchDebounce?.cancel();
    final q = rawQuery.trim();
    if (q.isEmpty) {
      setState(() {
        _comboSearchResults = [];
        _isSearchingCombo = false;
      });
      return;
    }

    // Coincidencia local instantánea (0 ms)
    List<Product> localMatches = [];
    try {
      final catalog = context.read<CatalogProvider>();
      final qLower = q.toLowerCase();
      localMatches = catalog.products
          .where((p) =>
              p.active &&
              !p.isCombo &&
              !p.isService &&
              (p.name.toLowerCase().contains(qLower) ||
                  (p.barcode?.toLowerCase().contains(qLower) ?? false) ||
                  p.internalCode.toLowerCase().contains(qLower)))
          .take(15)
          .toList();
    } catch (_) {}

    setState(() {
      _comboSearchResults = localMatches;
      _isSearchingCombo = true;
    });

    _comboSearchDebounce = Timer(const Duration(milliseconds: 260), () async {
      if (!mounted) return;
      try {
        final remote = await context.read<CatalogProvider>().searchProductsForCombo(q);
        if (!mounted || _comboSearchCtrl.text.trim() != q) return;
        final filtered = remote
            .where((p) => p.active && !p.isCombo && !p.isService)
            .take(25)
            .toList();
        setState(() {
          _comboSearchResults = filtered;
          _isSearchingCombo = false;
        });
      } catch (_) {
        if (mounted) {
          setState(() => _isSearchingCombo = false);
        }
      }
    });
  }

  Future<void> _onComboSearchSubmitted(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty) return;

    // Si hay coincidencia exacta de código de barras/interno o único resultado, agregar directo
    Product? exactMatch =
        RemoteScannerService.findExactProductMatch(_comboSearchResults, q);
    if (exactMatch != null) {
      _addIngredientToCombo(exactMatch);
      _comboSearchFocus.requestFocus();
      return;
    }

    if (_comboSearchResults.length == 1) {
      _addIngredientToCombo(_comboSearchResults.first);
      _comboSearchFocus.requestFocus();
      return;
    }

    try {
      final remote = await context.read<CatalogProvider>().searchProductsForCombo(q);
      if (!mounted) return;
      final eligible =
          remote.where((p) => p.active && !p.isCombo && !p.isService).toList();
      if (eligible.isEmpty) {
        SnackBarService.info(context, 'No se encontraron productos para "$q".');
        return;
      }
      final exactRemote =
          RemoteScannerService.findExactProductMatch(eligible, q);
      if (exactRemote != null) {
        _addIngredientToCombo(exactRemote);
        _comboSearchFocus.requestFocus();
        return;
      }
      if (eligible.length == 1) {
        _addIngredientToCombo(eligible.first);
        _comboSearchFocus.requestFocus();
      } else {
        setState(() {
          _comboSearchResults = eligible.take(25).toList();
          _isSearchingCombo = false;
        });
      }
    } catch (_) {}
  }

  void _handleRemoteBarcodeScan(String barcode) {
    final clean = barcode.trim();
    if (clean.isEmpty || !mounted) return;
    if (_isComboMode) {
      _comboSearchDebounce?.cancel();
      _comboSearchCtrl.text = clean;
      _comboSearchCtrl.selection = TextSelection.collapsed(offset: clean.length);
      _onComboSearchSubmitted(clean);
    } else {
      SnackBarService.warning(
        context,
        'Cambiá a la pestaña "Combo / Fracción" para escanear ingredientes.',
      );
    }
  }

  double _parseArs(String text) => ArsThousandsInputFormatter.parse(text);

  double _parseDouble(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0.0;
  }

  void _onSellingPriceChanged(String val) {
    if (_isUpdatingCalc) return;
    if (_isComboMode && _comboIngredients.isNotEmpty) {
      _priceIsAuto = false;
      setState(() {});
      return;
    }
    _isUpdatingCalc = true;
    _priceIsAuto = false;
    final price = _parseArs(val);
    final marginStr = _marginController.text.trim();
    final costStr = _costController.text.trim();
    final margin = _parseDouble(marginStr);
    final cost = _parseArs(costStr);

    if (val.trim().isEmpty) {
      if (_costIsAuto) {
        _costController.clear();
        _costIsAuto = false;
      }
      if (_priceAnchor == 'selling') {
        _priceAnchor = costStr.isNotEmpty ? 'cost' : null;
      }
    } else if (price > 0) {
      if (costStr.isEmpty || _costIsAuto) {
        _priceAnchor = 'selling';
        if (marginStr.isNotEmpty && margin > -100) {
          final calcCost = price / (1.0 + (margin / 100.0));
          _costController.text = calcCost.toArsInput();
          _costIsAuto = true;
        }
      } else if (cost > 0) {
        final calcMargin = ((price - cost) / cost) * 100.0;
        _marginController.text = calcMargin.toCleanMargin();
        _priceAnchor = 'selling';
      }
    }
    _isUpdatingCalc = false;
    setState(() {});
  }

  void _onMarginChanged(String val) {
    if (_isUpdatingCalc || (_isComboMode && _comboIngredients.isNotEmpty)) {
      return;
    }
    _isUpdatingCalc = true;
    final marginStr = val.trim();
    final priceStr = _priceController.text.trim();
    final costStr = _costController.text.trim();

    if (marginStr.isEmpty) {
      if (_costIsAuto) {
        _costController.clear();
        _costIsAuto = false;
      }
      if (_priceIsAuto) {
        _priceController.clear();
        _priceIsAuto = false;
      }
      _isUpdatingCalc = false;
      setState(() {});
      return;
    }

    final margin = _parseDouble(marginStr);
    final price = _parseArs(priceStr);
    final cost = _parseArs(costStr);

    if ((_priceAnchor == 'selling' || costStr.isEmpty || _costIsAuto) &&
        price > 0 &&
        !_priceIsAuto &&
        margin > -100) {
      final calcCost = price / (1.0 + (margin / 100.0));
      _costController.text = calcCost.toArsInput();
      _costIsAuto = true;
    } else if (cost > 0) {
      final calcPrice = cost * (1.0 + (margin / 100.0));
      _priceController.text = calcPrice.toArsInput();
      _priceIsAuto = true;
    }
    _isUpdatingCalc = false;
    setState(() {});
  }

  void _onCostChanged(String val) {
    if (_isUpdatingCalc || (_isComboMode && _comboIngredients.isNotEmpty)) {
      return;
    }
    _isUpdatingCalc = true;
    _costIsAuto = false;
    final costStr = val.trim();
    final priceStr = _priceController.text.trim();
    final marginStr = _marginController.text.trim();
    final cost = _parseArs(costStr);
    final price = _parseArs(priceStr);
    final margin = _parseDouble(marginStr);

    if (costStr.isEmpty) {
      if (_priceIsAuto) {
        _priceController.clear();
        _priceIsAuto = false;
      }
      if (_priceAnchor == 'cost') {
        _priceAnchor = priceStr.isNotEmpty ? 'selling' : null;
      }
    } else if (cost > 0) {
      if (priceStr.isEmpty || _priceIsAuto) {
        _priceAnchor = 'cost';
        if (marginStr.isNotEmpty) {
          final calcPrice = cost * (1.0 + (margin / 100.0));
          _priceController.text = calcPrice.toArsInput();
          _priceIsAuto = true;
        }
      } else if (price > 0) {
        final calcMargin = ((price - cost) / cost) * 100.0;
        _marginController.text = calcMargin.toCleanMargin();
        _priceAnchor = 'cost';
      }
    }
    _isUpdatingCalc = false;
    setState(() {});
  }

  bool _isSubmitted = false;

  /// Atajos globales del diálogo, independientes del campo que tenga el foco:
  /// - Esc → Cancelar y cerrar.
  /// - Enter / NumpadEnter → Agregar al carrito (Shift+Enter: salto de línea en Notas).
  ///   Si se presiona en la Descripción con el precio aún vacío, salta al Precio.
  bool _handleDialogKey(KeyEvent event) {
    if (!mounted || _isSubmitted) return false;
    if (event is! KeyDownEvent) return false;
    // Si hay un menú desplegable (ej. IVA) abierto encima, no interceptar.
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) return false;
      if (_comboSearchFocus.hasFocus) return false;

      if (_nameFocus.hasFocus &&
          _nameController.text.trim().isNotEmpty &&
          _priceController.text.trim().isEmpty) {
        _priceFocus.requestFocus();
        return true;
      }
      _submit();
      return true;
    }
    return false;
  }

  void _submit() {
    if (_isSubmitted) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_isComboMode && _comboIngredients.isNotEmpty) {
      for (final ing in _comboIngredients) {
        final q = (ing['quantity'] as num?)?.toDouble() ?? 0.0;
        if (q <= 0) {
          SnackBarService.warning(
            context,
            'La cantidad del ingrediente "${ing['name']}" debe ser mayor a 0.',
          );
          return;
        }
      }
    }

    _isSubmitted = true;

    final name = _nameController.text.trim();
    final details = _detailsController.text.trim();
    final qty = _parseDouble(_quantityController.text);
    final sellingPrice = _parseArs(_priceController.text);
    final rawCostPrice = _parseArs(_costController.text);
    final effectiveCostPrice = (_isComboMode && _comboIngredients.isNotEmpty)
        ? _comboCostTotal
        : (rawCostPrice > 0 ? rawCostPrice : 0.0);

    final serializedIngredients = (_isComboMode && _comboIngredients.isNotEmpty)
        ? _comboIngredients.map((e) {
            final copy = Map<String, dynamic>.from(e);
            if (_saveToCatalog) {
              final rawQty = (copy['quantity'] as num?)?.toDouble() ?? 1.0;
              copy['quantity'] = roundQtyForStorage(rawQty);
            }
            return copy;
          }).toList()
        : null;

    final product = Product(
      id: 0, // ID 0 identifica producto temporal o alta on-the-fly pendiente de persistir
      name: name,
      internalCode: _isComboMode
          ? 'COMBO-POS'
          : (_isServiceMode ? 'SERV-POS' : 'TEMP-POS'),
      costPrice: effectiveCostPrice >= 0 ? effectiveCostPrice : 0.0,
      sellingPrice: sellingPrice,
      stock: 0.0,
      active: true,
      isSoldByWeight: _isServiceMode ? false : _isSoldByWeight,
      isCombo: _isComboMode,
      isService: _isServiceMode,
      unitType: (!_isServiceMode && _isSoldByWeight) ? 'kg' : 'un',
      ivaRate: _ivaRate,
      needsCatalogReview: _saveToCatalog,
      comboIngredients: serializedIngredients,
    );

    final cartItem = CartItem(
      product: product,
      quantity: qty > 0 ? qty : 1.0,
      activeTier: PriceTier.base, // El precio ingresado en mostrador ya es el precio final pactado
      wholesaleFactor: 1.0,
      cardFactor: 1.0,
      customFactor: 1.0,
      isTemporary: !_saveToCatalog,
      saveToCatalog: _saveToCatalog,
      customDescription: name,
      customDetails: details.isNotEmpty ? details : null,
    );

    final shouldReplacePulled =
        _isComboMode && _replacePulledCartItems && _pulledCartItems.isNotEmpty;

    Navigator.of(context).pop(
      PosQuickItemResult(
        item: cartItem,
        replacedCartItems: shouldReplacePulled
            ? List<CartItem>.from(_pulledCartItems)
            : const [],
      ),
    );
  }

  Widget _buildComboBuilderSection(double currentUnitPrice) {
    final eligibleCart = _getEligibleCartItems();
    final individualTotal = _comboIndividualTotal;
    final savings = individualTotal - currentUnitPrice;
    final savingsPct =
        individualTotal > 0 ? (savings / individualTotal) * 100.0 : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_rounded,
                      size: 16, color: Colors.deepPurple.shade700),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Ingredientes para descuento de stock (${_comboIngredients.length})',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.deepPurple.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              if (eligibleCart.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: _pullItemsFromCart,
                  icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 15),
                  label: Text(
                    'Tomar ítems actuales del Carrito (${eligibleCart.length})',
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade100,
                    foregroundColor: Colors.deepPurple.shade900,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                  ),
                ),
            ],
          ),
          if (_pulledCartItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(
                () => _replacePulledCartItems = !_replacePulledCartItems,
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: _replacePulledCartItems,
                    onChanged: (v) => setState(
                      () => _replacePulledCartItems = v ?? true,
                    ),
                    visualDensity: VisualDensity.compact,
                    activeColor: Colors.deepPurple.shade700,
                  ),
                  Expanded(
                    child: Text(
                      'Reemplazar las ${_pulledCartItems.length} líneas tomadas del carrito por este Combo (evita doble cobro y doble descuento)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _comboSearchCtrl,
            focusNode: _comboSearchFocus,
            onChanged: _onComboSearchChanged,
            onEditingComplete: () {},
            onSubmitted: _onComboSearchSubmitted,
            decoration: InputDecoration(
              hintText: 'Buscar o pistolear producto para incluir en el combo...',
              prefixIcon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              suffixIcon: _isSearchingCombo
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_comboSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _comboSearchCtrl.clear();
                            setState(() => _comboSearchResults = []);
                          },
                        )
                      : null),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: Colors.deepPurple.shade200),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: _comboSearchResults.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 155),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurple.shade200),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _comboSearchResults.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, thickness: 0.6),
                          itemBuilder: (ctx, i) {
                            final p = _comboSearchResults[i];
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '\$${p.sellingPrice.toCurrency()} · Stock: ${p.stock.toUnitStockDisplay(isSoldByWeight: p.isSoldByWeight)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: p.stock <= 0
                                      ? Colors.amber.shade900
                                      : Colors.blueGrey.shade700,
                                ),
                              ),
                              trailing: Icon(Icons.add_circle_outline_rounded,
                                  size: 18, color: Colors.deepPurple.shade700),
                              onTap: () => _addIngredientToCombo(p),
                            );
                          },
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_comboIngredients.isNotEmpty) ...[
            const SizedBox(height: 8),
            Column(
              children: _comboIngredients.map((ing) {
                final pid = ing['id'] as int;
                final qty = (ing['quantity'] as num?)?.toDouble() ?? 1.0;
                final stock = (ing['stock'] as num?)?.toDouble() ?? 0.0;
                final isWeight = ing['is_sold_by_weight'] == true;
                final sellPrice =
                    (ing['selling_price'] as num?)?.toDouble() ?? 0.0;
                final ctrl = _qtyCtrlForIngredient(pid, qty);
                final hasFractionalQty = (qty - qty.roundToDouble()).abs() >= 0.0005;
                final showFractions = _expandedFractionIngredientIds.contains(pid);

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.deepPurple.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ing['name']?.toString() ?? 'Producto #$pid',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Lista: \$${sellPrice.toCurrency()} · Stock: ${stock.toUnitStockDisplay(isSoldByWeight: isWeight)}',
                                  style: TextStyle(
                                    fontSize: 10.8,
                                    color: stock <= 0
                                        ? Colors.amber.shade900
                                        : Colors.blueGrey.shade600,
                                    fontWeight: stock <= 0
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 78,
                            child: TextField(
                              controller: ctrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,/]'),
                                ),
                              ],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Cant.',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 7),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(7),
                                ),
                              ),
                              onChanged: (v) {
                                final parsed = parseQuantityOrFraction(v);
                                if (parsed != null && parsed > 0) {
                                  _updateComboIngredientQty(pid, parsed);
                                }
                              },
                              onSubmitted: (v) {
                                final parsed = parseQuantityOrFraction(v);
                                if (parsed != null && parsed > 0) {
                                  _applyComboIngredientPreset(pid, parsed);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: showFractions
                                ? 'Ocultar fracciones'
                                : 'Fraccionar porción (1/6, 1/8, 1/16, ÷ N...)',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => setState(() {
                                if (showFractions) {
                                  _expandedFractionIngredientIds.remove(pid);
                                } else {
                                  _expandedFractionIngredientIds.add(pid);
                                }
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 6),
                                decoration: BoxDecoration(
                                  color: (showFractions || hasFractionalQty)
                                      ? Colors.deepPurple.shade600
                                      : Colors.deepPurple.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: (showFractions || hasFractionalQty)
                                        ? Colors.deepPurple.shade600
                                        : Colors.deepPurple.shade200,
                                  ),
                                ),
                                child: Text(
                                  '1/x',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: (showFractions || hasFractionalQty)
                                        ? Colors.white
                                        : Colors.deepPurple.shade700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removeComboIngredient(pid),
                            icon: const Icon(Icons.close_rounded, size: 17),
                            color: Colors.red.shade600,
                            tooltip: 'Quitar del combo',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      if (showFractions) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Fracción:',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.blueGrey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            for (final preset in _comboPortionPresets)
                              ActionChip(
                                label: Text(
                                  preset.$1,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: (qty - preset.$2).abs() < 0.001
                                        ? Colors.white
                                        : Colors.deepPurple.shade800,
                                  ),
                                ),
                                backgroundColor: (qty - preset.$2).abs() < 0.001
                                    ? Colors.deepPurple.shade600
                                    : Colors.deepPurple.shade50,
                                side: BorderSide(
                                  color: Colors.deepPurple.shade200,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onPressed: () =>
                                    _applyComboIngredientPreset(pid, preset.$2),
                              ),
                            Text(
                              'o ÷',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.blueGrey.shade600,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(
                              width: 48,
                              height: 26,
                              child: TextField(
                                key: Key('quick_combo_parts_$pid'),
                                controller: _customPartsCtrlForIngredient(pid),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                                onSubmitted: (_) =>
                                    _applyCustomComboIngredientParts(pid),
                                decoration: InputDecoration(
                                  hintText: 'N',
                                  hintStyle: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.blueGrey.shade300,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              key: Key('quick_combo_apply_parts_$pid'),
                              borderRadius: BorderRadius.circular(6),
                              onTap: () =>
                                  _applyCustomComboIngredientParts(pid),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.deepPurple.shade300,
                                  ),
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
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Builder(
              builder: (_) {
                final bool autoFractionMode =
                    ComboFractionPricing.hasFractionalQuantities(
                        _comboIngredients);
                final bool isFractionMode =
                    _manualPortionPricingMode ?? autoFractionMode;
                final baseTarget =
                    ProductPricingCalculator.roundMoney(individualTotal);
                final suggestions = ComboFractionPricing.buildSuggestions(
                  baseTotal: individualTotal,
                  isFractionMode: isFractionMode,
                );
                final yieldSummary = isFractionMode
                    ? ComboFractionPricing.computeWholeUnitYield(
                        ingredients: _comboIngredients,
                        appliedPrice: currentUnitPrice,
                        proportionalBaseTotal: individualTotal,
                      )
                    : null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          isFractionMode
                              ? 'Valor proporcional: \$${individualTotal.toCurrency()} · Fracción: \$${currentUnitPrice.toCurrency()}'
                              : 'Suma lista: \$${individualTotal.toCurrency()} · Combo: \$${currentUnitPrice.toCurrency()}',
                          style: TextStyle(
                            fontSize: 11.8,
                            fontWeight: FontWeight.w700,
                            color: Colors.deepPurple.shade900,
                          ),
                        ),
                        ComboFractionPricing.buildModeToggle(
                          isFractionMode: isFractionMode,
                          onChanged: (val) =>
                              setState(() => _manualPortionPricingMode = val),
                        ),
                        if (currentUnitPrice > 0 &&
                            individualTotal > 0 &&
                            savings > 0.01)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Text(
                              'Ahorro \$${savings.toCurrency()} (-${savingsPct.toStringAsFixed(1)}%)',
                              style: TextStyle(
                                fontSize: 10.8,
                                fontWeight: FontWeight.w800,
                                color: Colors.green.shade800,
                              ),
                            ),
                          )
                        else if (currentUnitPrice > 0 &&
                            individualTotal > 0 &&
                            savings < -0.01)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Text(
                              '+\$${(-savings).toCurrency()} (+${(-savingsPct).toStringAsFixed(1)}%)',
                              style: TextStyle(
                                fontSize: 10.8,
                                fontWeight: FontWeight.w800,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (individualTotal > 0) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            isFractionMode
                                ? 'Sugerido fracción:'
                                : 'Sugerido s/ porciones:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepPurple.shade800,
                            ),
                          ),
                          _buildComboPriceSuggestionButton(
                            key: const Key('quick_combo_apply_base_btn'),
                            targetPrice: baseTarget,
                            label: 'Usar \$${baseTarget.toCurrency()}',
                            appliedLabel:
                                'Base \$${baseTarget.toCurrency()} aplicada',
                            currentUnitPrice: currentUnitPrice,
                          ),
                          for (final s in suggestions)
                            _buildComboPriceSuggestionButton(
                              key: Key('quick_combo_apply_${s.keySuffix}_btn'),
                              targetPrice: s.targetPrice,
                              label: s.buttonLabel,
                              appliedLabel: s.appliedLabel,
                              currentUnitPrice: currentUnitPrice,
                              isMarkup: isFractionMode,
                            ),
                        ],
                      ),
                    ],
                    if (yieldSummary != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
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
                  ],
                );
              },
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Opcional: seleccioná productos del catálogo o tomalos del carrito para que la venta descuente su stock automáticamente.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.deepPurple.shade700,
                ),
              ),
            ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectMode(String mode) {
    final nextCombo = mode == 'combo';
    final nextService = mode == 'service';
    if (nextCombo == _isComboMode && nextService == _isServiceMode) return;
    setState(() {
      _isComboMode = nextCombo;
      _isServiceMode = nextService;
      if (!_userToggledSaveToCatalog) {
        _saveToCatalog = !nextCombo;
      }
      if (_isServiceMode) {
        _isSoldByWeight = false;
        _costController.clear();
        _marginController.clear();
      }
    });
  }

  Widget _buildModeSelector() {
    final activeMode = _isComboMode
        ? 'combo'
        : (_isServiceMode ? 'service' : 'product');
    final Alignment pillAlignment = activeMode == 'combo'
        ? Alignment.centerRight
        : (activeMode == 'service'
            ? Alignment.center
            : Alignment.centerLeft);
    final Color activeColor = activeMode == 'combo'
        ? Colors.deepPurple.shade700
        : (activeMode == 'service'
            ? Colors.teal.shade700
            : const Color(0xFF1D4ED8));
    final Color activeBorder = activeMode == 'combo'
        ? Colors.deepPurple.shade200
        : (activeMode == 'service'
            ? Colors.teal.shade200
            : const Color(0xFFBFDBFE));

    const tabs = [
      ('product', Icons.bolt_rounded, 'Producto Rápido'),
      ('service', Icons.work_outline_rounded, 'Servicio / Honorario'),
      ('combo', Icons.inventory_2_outlined, 'Combo / Fracción'),
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: pillAlignment,
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1.0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: activeBorder, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: tabs.map((tab) {
              final isSelected = activeMode == tab.$1;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => _selectMode(tab.$1),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tab.$2,
                              size: 16,
                              color: isSelected
                                  ? activeColor
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? activeColor
                                      : const Color(0xFF475569),
                                ),
                                child: Text(
                                  tab.$3,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogHeader({required bool isCompact}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 14 : 22,
        isCompact ? 12 : 18,
        isCompact ? 14 : 22,
        isCompact ? 8 : 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.all(isCompact ? 8 : 10),
                decoration: BoxDecoration(
                  color: _isComboMode
                      ? Colors.deepPurple.shade50
                      : (_isServiceMode
                          ? Colors.teal.shade50
                          : Colors.amber.shade50),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.85, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  ),
                  child: Icon(
                    _isComboMode
                        ? Icons.layers_rounded
                        : (_isServiceMode
                            ? Icons.work_outline_rounded
                            : Icons.flash_on_rounded),
                    key: ValueKey<String>(
                      _isComboMode
                          ? 'icon_combo'
                          : (_isServiceMode ? 'icon_service' : 'icon_product'),
                    ),
                    color: _isComboMode
                        ? Colors.deepPurple.shade700
                        : (_isServiceMode
                            ? Colors.teal.shade700
                            : Colors.amber.shade800),
                    size: isCompact ? 20 : 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.14),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.centerLeft,
                        children: <Widget>[
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      child: Text(
                        _isComboMode
                            ? 'Combo / Oferta Rápida en Mostrador'
                            : (_isServiceMode
                                ? 'Servicio / Honorario en Mostrador'
                                : 'Producto Rápido en Mostrador'),
                        key: ValueKey<String>(
                          _isComboMode
                              ? 'title_combo'
                              : (_isServiceMode
                                  ? 'title_service'
                                  : 'title_product'),
                        ),
                        style: TextStyle(
                          fontSize: isCompact ? 15.5 : 17.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Se imprime en Ticket Térmico, PDF A4 y Factura Fiscal ARCA/AFIP',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Cerrar (Esc)',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildModeSelector(),
        ],
      ),
    );
  }

  Widget _buildDialogFooter({
    required double previewSubtotal,
    required bool isCompact,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 14 : 22,
        12,
        isCompact ? 14 : 22,
        14,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0)),
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(18),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SUBTOTAL LÍNEA',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                '\$${previewSubtotal.toArsInput()}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar (Esc)'),
              ),
              ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text('Agregar al Carrito (Enter)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 14 : 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isResponsableInscripto =
        context.watch<SettingsProvider?>()?.settings?.isResponsableInscripto ?? false;
    final qty = _parseDouble(_quantityController.text);
    final unitPrice = _parseArs(_priceController.text);
    final previewSubtotal = ((qty > 0 ? qty : 0.0) * (unitPrice > 0 ? unitPrice : 0.0));
    final screenSize = MediaQuery.of(context).size;
    final isCompactWidth = screenSize.width < 480;
    final isShortScreen = screenSize.height < 580;
    final horizontalInset = isCompactWidth ? 10.0 : 24.0;
    final verticalInset = isShortScreen ? 8.0 : 24.0;
    final dialogWidth =
        (screenSize.width - (horizontalInset * 2)).clamp(240.0, 684.0);

    return RemoteScannerListener(
      debugLabel: 'PosQuickItemDialog',
      onBarcodeScanned: _handleRemoteBarcodeScan,
      child: Focus(
        autofocus: false,
        child: Dialog(
        alignment: Alignment.center,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalInset,
          vertical: verticalInset,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 684,
            maxHeight: screenSize.height * (isShortScreen ? 0.96 : 0.92),
          ),
          child: SizedBox(
            width: dialogWidth,
            child: Builder(
              builder: (_) {
                final header = _buildDialogHeader(isCompact: isCompactWidth);
                final footer = _buildDialogFooter(
                  previewSubtotal: previewSubtotal,
                  isCompact: isCompactWidth,
                );
                const divider = Divider(height: 1, color: Color(0xFFE2E8F0));
                final formBody = Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompactWidth ? 14 : 22,
                    14,
                    isCompactWidth ? 14 : 22,
                    14,
                  ),
                  child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_scannedReferenceCode != null) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.shade300),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.qr_code_rounded,
                                    size: 16,
                                    color: Colors.amber.shade900,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Código consultado en F5: "$_scannedReferenceCode". Escribí la descripción e importe para cobrarlo.',
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
                          ],

                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 280),
                            reverseDuration: const Duration(milliseconds: 220),
                            firstCurve: Curves.easeOut,
                            secondCurve: Curves.easeOutCubic,
                            sizeCurve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            crossFadeState: _isComboMode
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            firstChild: const SizedBox(
                              width: double.infinity,
                              height: 0,
                            ),
                            secondChild: _buildComboBuilderSection(
                              unitPrice > 0 ? unitPrice : 0.0,
                            ),
                          ),

                          // 1. Campos obligatorios arriba: Nombre + Fila Precio/Cantidad/IVA
                          TextFormField(
                            controller: _nameController,
                            focusNode: _nameFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) => _priceFocus.requestFocus(),
                            decoration: InputDecoration(
                              labelText: _isComboMode
                                  ? 'Nombre del Combo / Fracción *'
                                  : (_isServiceMode
                                      ? 'Descripción del Servicio / Honorario *'
                                      : 'Descripción del Producto *'),
                              hintText: _isComboMode
                                  ? 'Ej: Combo Asado Familiar / Promo 2x1...'
                                  : (_isServiceMode
                                      ? 'Ej: Honorarios Monotributo / Consulta Profesional...'
                                      : 'Ej: Mercadería recién ingresada / Artículo varios...'),
                              prefixIcon: const Icon(Icons.description_outlined, size: 20),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Ingresa una descripción para el comprobante';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // Fila: Precio Unitario + Cantidad + IVA
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: TextFormField(
                                  controller: _priceController,
                                  focusNode: _priceFocus,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: const [
                                    ArsThousandsInputFormatter(),
                                  ],
                                  textInputAction: TextInputAction.next,
                                  onChanged: _onSellingPriceChanged,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: _isServiceMode
                                        ? 'Importe / Honorario Unit. *'
                                        : 'Precio Venta Unit. *',
                                    prefixText: '\$ ',
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    isDense: true,
                                  ),
                                  validator: (val) {
                                    final p = _parseArs(val ?? '');
                                    if (p <= 0) {
                                      return 'Ingresa un precio > 0';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _quantityController,
                                  focusNode: _quantityFocus,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) => setState(() {}),
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: _isSoldByWeight ? 'Peso (Kg) *' : 'Cantidad *',
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    isDense: true,
                                    suffixIcon: _isSoldByWeight
                                        ? Consumer<LocalTerminalProvider>(
                                            builder: (ctx, localTerminal, _) {
                                              final comPort = localTerminal.scaleComPort;
                                              final isConfigured = comPort.trim().isNotEmpty;
                                              return IconButton(
                                                tooltip: isConfigured
                                                    ? 'Leer peso desde Balanza ($comPort)'
                                                    : 'Configurar puerto COM de Balanza',
                                                onPressed: _isReadingScale
                                                    ? null
                                                    : () => _readWeightFromScale(comPort),
                                                icon: _isReadingScale
                                                    ? const SizedBox(
                                                        width: 15,
                                                        height: 15,
                                                        child: CircularProgressIndicator(strokeWidth: 2),
                                                      )
                                                    : Icon(
                                                        Icons.scale_rounded,
                                                        size: 18,
                                                        color: isConfigured
                                                            ? Colors.indigo.shade700
                                                            : Colors.blueGrey.shade400,
                                                      ),
                                              );
                                            },
                                          )
                                        : null,
                                  ),
                                  validator: (val) {
                                    final q = _parseDouble(val ?? '');
                                    if (q <= 0) {
                                      return '> 0';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              if (isResponsableInscripto) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<double>(
                                    isExpanded: true,
                                    initialValue: _ivaRate,
                                    decoration: InputDecoration(
                                      labelText: 'IVA AFIP',
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      isDense: true,
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 21.0, child: Text('21%', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 10.5, child: Text('10.5%', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 27.0, child: Text('27%', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 0.0, child: Text('0% Ex.', overflow: TextOverflow.ellipsis)),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) setState(() => _ivaRate = v);
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 2. Opcional: Detalle / Notas para ticket y factura
                          TextFormField(
                            controller: _detailsController,
                            minLines: 1,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: _isComboMode
                                  ? 'Detalle de artículos incluidos (Opcional — sale en ticket/factura)'
                                  : (_isServiceMode
                                      ? 'Período / Expediente / Detalle para Factura (Opcional)'
                                      : 'Notas adicionales para Factura / Ticket (Opcional)'),
                              hintText: _isComboMode
                                  ? (_comboIngredients.isNotEmpty
                                      ? 'Opcional — usá el botón derecho para copiar los ingredientes'
                                      : 'Ej: Incluye 1 Coca-Cola 2.25L + 2 Doc. Empanadas')
                                  : (_isServiceMode
                                      ? 'Ej: Período Mensual Noviembre 2026 / Expte. N° 4182'
                                      : 'Ej: Marca / Medida / Observación solicitada por el cliente'),
                              prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                              suffixIcon: (_isComboMode && _comboIngredients.isNotEmpty)
                                  ? Tooltip(
                                      message:
                                          'Copiar resumen de ingredientes al comprobante',
                                      child: IconButton(
                                        key: const Key('quick_combo_copy_details_btn'),
                                        icon: Icon(
                                          Icons.playlist_add_rounded,
                                          size: 20,
                                          color: Colors.deepPurple.shade700,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _detailsController.text =
                                                _buildComboIngredientsSummary();
                                          });
                                        },
                                      ),
                                    )
                                  : null,
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),

                    // Panel Contextual con Expansión Suave hacia abajo: Costo y Margen (Productos/Combos) vs Ficha Fiscal (Servicios)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (currentChild, previousChildren) => Stack(
                            alignment: Alignment.topCenter,
                            children: <Widget>[
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          ),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.04),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: !_isServiceMode
                              ? AnimatedContainer(
                                  key: const ValueKey<String>('quick_item_cost_panel'),
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _isComboMode
                                        ? Colors.deepPurple.shade50.withValues(alpha: 0.18)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _isComboMode
                                          ? Colors.deepPurple.shade200
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(minHeight: 32),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.calculate_outlined, size: 16, color: Color(0xFF475569)),
                                            const SizedBox(width: 6),
                                             Expanded(
                                               child: Text(
                                                 (_isComboMode && _comboIngredients.isNotEmpty)
                                                     ? 'Rentabilidad del Combo (Calculada s/ Ingredientes)'
                                                     : 'Costo y Margen (Opcional · Cálculo Automático)',
                                                 maxLines: 1,
                                                 overflow: TextOverflow.ellipsis,
                                                 style: const TextStyle(
                                                   fontSize: 12,
                                                   fontWeight: FontWeight.w700,
                                                   color: Color(0xFF475569),
                                                 ),
                                               ),
                                             ),
                                            AnimatedSwitcher(
                                              duration: const Duration(milliseconds: 200),
                                              switchInCurve: Curves.easeOutCubic,
                                              switchOutCurve: Curves.easeInCubic,
                                              transitionBuilder: (child, animation) =>
                                                  FadeTransition(
                                                opacity: animation,
                                                child: ScaleTransition(
                                                  scale: Tween<double>(begin: 0.92, end: 1.0)
                                                      .animate(animation),
                                                  child: child,
                                                ),
                                              ),
                                              child: !_isComboMode
                                                  ? Row(
                                                      key: const ValueKey<String>('trailing_weight'),
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        ChoiceChip(
                                                          label: const Text('Por Peso (Kg)', style: TextStyle(fontSize: 11)),
                                                          selected: _isSoldByWeight,
                                                          visualDensity: VisualDensity.compact,
                                                          onSelected: (v) => setState(() => _isSoldByWeight = v),
                                                        ),
                                                        if (_isSoldByWeight) ...[
                                                          const SizedBox(width: 6),
                                                          Consumer<LocalTerminalProvider>(
                                                            builder: (ctx, localTerminal, _) {
                                                              final comPort = localTerminal.scaleComPort;
                                                              final isConfigured = comPort.trim().isNotEmpty;
                                                              return OutlinedButton.icon(
                                                                onPressed: _isReadingScale
                                                                    ? null
                                                                    : () => _readWeightFromScale(comPort),
                                                                icon: const Icon(Icons.scale_rounded, size: 14),
                                                                label: Text(
                                                                  isConfigured ? 'Leer Balanza' : 'Config. Balanza',
                                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                                                ),
                                                                style: OutlinedButton.styleFrom(
                                                                  visualDensity: VisualDensity.compact,
                                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                                  foregroundColor: isConfigured ? Colors.indigo.shade700 : Colors.blueGrey,
                                                                  side: BorderSide(
                                                                    color: isConfigured ? Colors.indigo.shade300 : Colors.blueGrey.shade300,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ],
                                                      ],
                                                    )
                                                  : Container(
                                                      key: const ValueKey<String>('trailing_combo_badge'),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.deepPurple.shade50,
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: Colors.deepPurple.shade200),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.layers_outlined, size: 13, color: Colors.deepPurple.shade700),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            'Pack / Promo',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w700,
                                                              color: Colors.deepPurple.shade800,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (_isComboMode && _comboIngredients.isNotEmpty)
                                        Builder(
                                          builder: (_) {
                                            final recipeCost = _comboCostTotal;
                                            final currentPrice = _parseArs(_priceController.text);
                                            final hasMargin = recipeCost > 0 && currentPrice > 0;
                                            final marginPct = hasMargin
                                                ? ((currentPrice - recipeCost) / recipeCost) * 100.0
                                                : 0.0;
                                            final marginText = hasMargin
                                                ? '${marginPct.toCleanMargin()}%'
                                                : (currentPrice > 0 && recipeCost <= 0
                                                    ? 'Sin costo base'
                                                    : 'Ingresá precio');
                                            final marginColor = !hasMargin
                                                ? const Color(0xFF64748B)
                                                : (marginPct >= 0
                                                    ? Colors.green.shade700
                                                    : Colors.red.shade700);
                                            return Row(
                                              children: [
                                                Expanded(
                                                  child: _buildReadonlyComboMetricBox(
                                                    label: 'Costo Receta (Calc.)',
                                                    value: '\$${recipeCost.toCurrency()}',
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: _buildReadonlyComboMetricBox(
                                                    label: '% Margen Combo',
                                                    value: marginText,
                                                    valueColor: marginColor,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        )
                                      else
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: _costController,
                                                keyboardType: TextInputType.number,
                                                inputFormatters: const [
                                                  ArsThousandsInputFormatter(),
                                                ],
                                                onChanged: _onCostChanged,
                                                decoration: InputDecoration(
                                                  labelText: 'Precio de Costo (Opcional)',
                                                  hintText: '0',
                                                  prefixText: '\$ ',
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  isDense: true,
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: TextFormField(
                                                controller: _marginController,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                onChanged: _onMarginChanged,
                                                decoration: InputDecoration(
                                                  labelText: '% Ganancia s/Costo',
                                                  hintText: 'Ej: 30',
                                                  suffixText: '%',
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  isDense: true,
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                )
                              : Container(
                                  key: const ValueKey<String>('quick_item_service_panel'),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.teal.shade200),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(minHeight: 32),
                                        child: Row(
                                          children: [
                                            Icon(Icons.verified_outlined, size: 16, color: Colors.teal.shade800),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Modalidad Servicio / Honorario (AFIP Concepto 2)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.teal.shade900,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.teal.shade300),
                                              ),
                                              child: Text(
                                                'Sin Stock Físico',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.teal.shade800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(minHeight: 42),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'No descuenta inventario ni requiere costo de reposición. En Facturas A, B y C informa automáticamente el período facturado reglamentario ante ARCA/AFIP.',
                                            style: TextStyle(
                                              fontSize: 11.8,
                                              height: 1.35,
                                              color: Colors.teal.shade900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),

                    // Toggle: Guardar permanentemente en el catálogo vs Solo por esta venta
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: _saveToCatalog
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _saveToCatalog
                              ? const Color(0xFF93C5FD)
                              : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          dense: true,
                          value: _saveToCatalog,
                          onChanged: (val) => setState(() {
                            _userToggledSaveToCatalog = true;
                            _saveToCatalog = val;
                          }),
                          title: Text(
                            'Guardar en el Catálogo',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _saveToCatalog
                                  ? const Color(0xFF1E3A8A)
                                  : const Color(0xFF92400E),
                            ),
                          ),
                          subtitle: Text(
                            _saveToCatalog
                                ? (_isComboMode
                                    ? 'Creará el Combo en Productos ("Por revisar") con descuento automático de sus ingredientes.'
                                    : (_isServiceMode
                                        ? 'Quedará disponible en el Catálogo como Servicio sin requerir ni descontar stock físico.'
                                        : 'Se creará automáticamente en Productos (marcado "Pendiente de revisión" para completar código/rubro luego).'))
                                : (_isComboMode
                                    ? (_comboIngredients.isNotEmpty
                                        ? 'Solo para esta venta: no altera el catálogo, pero SÍ descuenta el stock de sus ${_comboIngredients.length} ingredientes al cobrar.'
                                        : 'Solo para esta venta: no altera el catálogo ni descuenta stock (sin ingredientes). Queda en ticket y factura.')
                                    : 'Solo para esta venta: no altera el catálogo ni bloquea stock. Queda registrado en el historial, ticket y factura.'),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _saveToCatalog
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ),
                    ),
                        ],
                      ),
                    ),
                );
                if (isShortScreen) {
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [header, divider, formBody, footer],
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    divider,
                    Flexible(
                      child: SingleChildScrollView(child: formBody),
                    ),
                    footer,
                  ],
                );
              },
            ),
          ),
        ),
      ),
      ),
    );
  }
}
