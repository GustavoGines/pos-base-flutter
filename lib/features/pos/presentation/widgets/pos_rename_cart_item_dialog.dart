import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'package:frontend_desktop/core/utils/scale_serial_service.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class PosRenameCartItemResult {
  final String? customDescription;
  final String? customDetails;
  final double? newUnitPrice;
  final bool clearManualUnitPrice;
  final double? newCostPrice;
  final bool clearManualCostPrice;
  final double? newManualSubtotal;
  final bool clearManualSubtotal;
  final double? newQuantity;
  final double? newIvaRate;
  final bool ivaRateChanged;
  final String? newBarcode;
  final bool barcodeChanged;
  final bool updateCatalogInDb;
  final bool updateCatalogName;
  final bool updateIvaInDb;
  final double? newShelfStockBeforeSale;
  final bool shelfStockChanged;
  final bool sellingPriceChanged;
  final bool costPriceChanged;

  const PosRenameCartItemResult({
    this.customDescription,
    this.customDetails,
    this.newUnitPrice,
    this.clearManualUnitPrice = false,
    this.newCostPrice,
    this.clearManualCostPrice = false,
    this.newManualSubtotal,
    this.clearManualSubtotal = false,
    this.newQuantity,
    this.newIvaRate,
    this.ivaRateChanged = false,
    this.newBarcode,
    this.barcodeChanged = false,
    this.updateCatalogInDb = false,
    this.updateCatalogName = false,
    this.updateIvaInDb = false,
    this.newShelfStockBeforeSale,
    this.shelfStockChanged = false,
    this.sellingPriceChanged = false,
    this.costPriceChanged = false,
  });
}

class PosRenameCartItemDialog extends StatefulWidget {
  final CartItem item;
  final bool focusQuantityInitially;
  final VoidCallback? onOpenHardwareCalculator;

  const PosRenameCartItemDialog({
    super.key,
    required this.item,
    this.focusQuantityInitially = false,
    this.onOpenHardwareCalculator,
  });

  static Future<PosRenameCartItemResult?> show(
    BuildContext context, {
    required CartItem item,
    bool focusQuantityInitially = false,
    VoidCallback? onOpenHardwareCalculator,
  }) {
    return showDialog<PosRenameCartItemResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PosRenameCartItemDialog(
        item: item,
        focusQuantityInitially: focusQuantityInitially,
        onOpenHardwareCalculator: onOpenHardwareCalculator,
      ),
    );
  }

  @override
  State<PosRenameCartItemDialog> createState() =>
      _PosRenameCartItemDialogState();
}

class _PosRenameCartItemDialogState extends State<PosRenameCartItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descController;
  late final TextEditingController _detailsController;
  late final TextEditingController _qtyController;
  late final TextEditingController _priceController;
  late final TextEditingController _subtotalController;
  late final TextEditingController _costController;
  late final TextEditingController _marginController;
  late final TextEditingController _discountPctController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _shelfStockController;
  late final TextEditingController _customPartsController;

  final _descFocus = FocusNode();
  final _qtyFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _subtotalFocus = FocusNode();
  final _barcodeFocus = FocusNode();
  final _customPartsFocus = FocusNode();

  bool _isUpdatingCalc = false;
  bool _costExplicitlyEdited = false;
  bool _priceExplicitlyEdited = false;
  bool _restoredToCatalogPrices = false;
  bool _updateCatalogInDb = false;
  bool _updateCatalogName = false;
  bool _expandCatalogZone = false;
  bool _showBarcodeEditor = false;
  bool _barcodeCapturedByScanner = false;
  bool _showPortionsBar = false;
  double? _manualSubtotalOverride;
  late double _ivaRate;

  bool get _isTempOrUnregistered =>
      widget.item.isTemporary ||
      widget.item.saveToCatalog ||
      widget.item.product.id <= 0;

  bool get _isSoldByWeight => widget.item.product.isSoldByWeight;

  double get _catalogBaseSellingPrice => widget.item.product.sellingPrice;
  double get _catalogBaseCostPrice => widget.item.product.costPrice;
  String get _originalBarcode => (widget.item.product.barcode ?? '').trim();

  /// Calcula el precio unitario sugerido por lista/volumen/oferta para una cantidad dada.
  double _defaultCartPriceForQuantity(double qty) {
    final safeQty = qty > 0 ? qty : widget.item.quantity;
    final hasExplicitOffer = (widget.item.promotionalLabel != null &&
            widget.item.promotionalLabel!.trim().isNotEmpty) ||
        (widget.item.promotionalPeriodType != null &&
            widget.item.promotionalPeriodType!.trim().isNotEmpty) ||
        (widget.item.activeTier == PriceTier.base &&
            widget.item.promotionalPrice != null &&
            widget.item.promotionalPrice! > 0 &&
            widget.item.agreedUnitPrice == null);

    return ProductPricingCalculator.calculate(
      product: widget.item.product,
      quantity: safeQty,
      activeTier: widget.item.activeTier,
      wholesaleFactor: widget.item.wholesaleFactor,
      cardFactor: widget.item.cardFactor,
      customFactor: widget.item.customFactor,
      promotionalPrice: widget.item.promotionalPrice,
      hasExplicitOffer: hasExplicitOffer,
      agreedUnitPrice: null,
      cardSurchargeOnOffersMode: widget.item.cardSurchargeOnOffersMode,
      discountTierOnOffersMode: widget.item.discountTierOnOffersMode,
    ).finalUnitPrice;
  }

  double get _currentQty {
    final parsed = parseQuantityOrFraction(_qtyController.text);
    if (parsed == null || parsed <= 0) return widget.item.quantity;
    if (widget.item.product.isService) return parsed.roundToDouble();
    return (parsed * 10000).roundToDouble() / 10000.0;
  }

  String _formatQtyForInput(double val) => formatQuantityInput(val);

  double get _catalogDefaultCartPrice =>
      _defaultCartPriceForQuantity(_currentQty);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleDialogKey);
    _descController = TextEditingController(
      text: widget.item.effectiveDisplayName,
    );
    _detailsController = TextEditingController(
      text: widget.item.customDetails ?? '',
    );

    final initialQty = widget.item.quantity;
    _qtyController = TextEditingController(
      text: _formatQtyForInput(initialQty),
    );
    _shelfStockController = TextEditingController(
      text: _isTempOrUnregistered
          ? ''
          : _formatQtyForInput(widget.item.product.stock),
    );
    _customPartsController = TextEditingController();

    final initialSelling = widget.item.unitPrice;
    final initialCost = widget.item.effectiveCostPrice;
    final initialSubtotal = widget.item.subtotal;
    _manualSubtotalOverride = widget.item.manualSubtotal;

    _priceController = TextEditingController(
      text: initialSelling > 0 ? initialSelling.toArsInput() : '',
    );
    _subtotalController = TextEditingController(
      text: initialSubtotal > 0 ? initialSubtotal.toArsInput() : '',
    );
    _costController = TextEditingController(
      text: initialCost > 0 ? initialCost.toArsInput() : '',
    );
    _marginController = TextEditingController(
      text: (initialCost > 0 && initialSelling > 0)
          ? (((initialSelling - initialCost) / initialCost) * 100.0)
              .toCleanMargin()
          : '',
    );

    final refPrice = _defaultCartPriceForQuantity(initialQty);
    final initialDiscPct = (refPrice > 0 && initialSelling < refPrice - 0.005)
        ? (((refPrice - initialSelling) / refPrice) * 100.0)
        : 0.0;
    _discountPctController = TextEditingController(
      text: initialDiscPct > 0.04 ? initialDiscPct.toCleanMargin() : '',
    );

    _barcodeController = TextEditingController(text: _originalBarcode);
    final rawIva = widget.item.product.ivaRate;
    _ivaRate = const [0.0, 10.5, 21.0, 27.0].contains(rawIva) ? rawIva : 21.0;
    _showPortionsBar = !_isSoldByWeight &&
        !widget.item.product.isService &&
        ((initialQty - initialQty.roundToDouble()).abs() >= 0.0005 ||
            (widget.item.product.stock - widget.item.product.stock.roundToDouble())
                    .abs() >=
                0.0005);

    if (widget.item.manualUnitPrice != null) {
      _priceExplicitlyEdited = true;
    }
    if (widget.item.manualCostPrice != null) {
      _costExplicitlyEdited = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.focusQuantityInitially) {
          _qtyFocus.requestFocus();
          _qtyController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _qtyController.text.length,
          );
        } else {
          _descFocus.requestFocus();
          _descController.selection = TextSelection(
            baseOffset: _descController.text.length,
            extentOffset: 0,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleDialogKey);
    _descController.dispose();
    _detailsController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    _subtotalController.dispose();
    _costController.dispose();
    _marginController.dispose();
    _discountPctController.dispose();
    _barcodeController.dispose();
    _shelfStockController.dispose();
    _customPartsController.dispose();
    _descFocus.dispose();
    _qtyFocus.dispose();
    _priceFocus.dispose();
    _subtotalFocus.dispose();
    _barcodeFocus.dispose();
    _customPartsFocus.dispose();
    super.dispose();
  }

  double _parseArs(String text) => ArsThousandsInputFormatter.parse(text);

  double _parseDouble(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0.0;
  }

  void _syncDiscountFieldFromUnitPrice(double unitPrice, double qty) {
    final refPrice = _defaultCartPriceForQuantity(qty);
    if (refPrice > 0 && unitPrice > 0 && unitPrice < refPrice - 0.005) {
      final pct = ((refPrice - unitPrice) / refPrice) * 100.0;
      _discountPctController.text = pct > 0.04 ? pct.toCleanMargin() : '';
    } else {
      _discountPctController.clear();
    }
  }

  /// Cuando cambia la Cantidad / Peso dentro del diálogo:
  /// - Si el usuario no había forzado un precio manual y el producto tiene escalones por volumen (`priceTiers`),
  ///   actualiza automáticamente el Precio Unitario al escalón correspondiente.
  /// - Recalcula el Total de Línea (`Subtotal`).
  void _onQuantityChanged(String val) {
    if (_isUpdatingCalc) return;
    final parsed = parseQuantityOrFraction(val);
    if (parsed == null || parsed <= 0) {
      setState(() {});
      return;
    }

    _isUpdatingCalc = true;
    _manualSubtotalOverride = null;
    final qty = widget.item.product.isService
        ? parsed.roundToDouble()
        : (parsed * 10000).roundToDouble() / 10000.0;

    double unitPrice = _parseArs(_priceController.text);
    if (!_priceExplicitlyEdited && !_isTempOrUnregistered) {
      final tierPrice = _defaultCartPriceForQuantity(qty);
      if (tierPrice > 0 && (tierPrice - unitPrice).abs() >= 0.005) {
        unitPrice = tierPrice;
        _priceController.text = unitPrice.toArsInput();
      }
    }

    final cost = _parseArs(_costController.text);
    if (cost > 0 && unitPrice > 0) {
      _marginController.text =
          (((unitPrice - cost) / cost) * 100.0).toCleanMargin();
    }

    final newSub = ((unitPrice * qty) * 100).roundToDouble() / 100.0;
    _subtotalController.text = newSub > 0 ? newSub.toArsInput() : '';
    _syncDiscountFieldFromUnitPrice(unitPrice, qty);

    _isUpdatingCalc = false;
    setState(() {});
  }

  void _stepUnitQuantity(int delta) {
    if (_isSoldByWeight) return;
    if (widget.item.product.isService ||
        (_currentQty - _currentQty.roundToDouble()).abs() < 0.001) {
      final next = (_currentQty.round() + delta).clamp(1, 99999);
      _qtyController.text = next.toString();
    } else {
      final candidate = _currentQty + delta;
      final next = candidate < 0.001
          ? 1.0
          : (candidate > 99999 ? 99999.0 : candidate);
      _qtyController.text = _formatQtyForInput(next);
    }
    _onQuantityChanged(_qtyController.text);
  }

  void _applyQuickPortion(String label, double fractionQty) {
    final cleanedBase = _descController.text
        .replaceFirst(RegExp(r'^Porción\s*\([^)]+\)\s*-\s*'), '')
        .trim();
    final targetName =
        cleanedBase.isNotEmpty ? cleanedBase : widget.item.product.name;
    if (label == '1' && (fractionQty - 1.0).abs() < 0.0005) {
      _descController.text = targetName;
    } else {
      _descController.text = 'Porción ($label) - $targetName';
    }
    _qtyController.text = _formatQtyForInput(fractionQty);
    _onQuantityChanged(_qtyController.text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subtotalFocus.requestFocus();
      _subtotalController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _subtotalController.text.length,
      );
    });
  }

  void _applyCustomParts() {
    final parts = int.tryParse(_customPartsController.text.trim());
    if (parts == null || parts < 2 || parts > 100) {
      SnackBarService.warning(
        context,
        'Ingresá una cantidad válida de partes (entre 2 y 100, ej: 16).',
      );
      return;
    }
    _applyQuickPortion('1/$parts', 1.0 / parts);
  }

  Future<void> _readWeightFromScale(String comPort) async {
    final trimmedPort = comPort.trim();
    if (trimmedPort.isEmpty) {
      if (mounted) {
        SnackBarService.warning(
          context,
          'La balanza no está configurada en esta terminal.',
        );
      }
      return;
    }

    try {
      final result = await ScaleSerialService.instance.readWeight(trimmedPort);
      if (!mounted) return;
      if (result.success && result.weightKg != null) {
        final weightStr = result.weightKg!.toStringAsFixed(3);
        _qtyController.text = weightStr;
        _onQuantityChanged(weightStr);
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
    }
  }

  /// Regla "Costo como Ancla":
  /// Cuando el usuario modifica el Precio de Venta Unitario, el Costo jamás se toca;
  /// se recalculan el Total de Línea, el % de Descuento y el % de Margen.
  void _onSellingPriceChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;
    _priceExplicitlyEdited = true;
    _manualSubtotalOverride = null;

    final price = _parseArs(val);
    final cost = _parseArs(_costController.text);
    final qty = _currentQty;

    if (cost > 0 && price > 0) {
      final calcMargin = ((price - cost) / cost) * 100.0;
      _marginController.text = calcMargin.toCleanMargin();
    } else if (val.trim().isEmpty) {
      _marginController.clear();
    }

    final lineSub = ((price * qty) * 100).roundToDouble() / 100.0;
    _subtotalController.text = lineSub > 0 ? lineSub.toArsInput() : '';
    _syncDiscountFieldFromUnitPrice(price, qty);

    // Si aplicó una rebaja respecto al precio de lista, desmarcar por seguridad el guardado en BD
    if (price > 0 && price < _catalogDefaultCartPrice - 0.005) {
      _updateCatalogInDb = false;
    }

    _isUpdatingCalc = false;
    setState(() {});
  }

  /// Punto 1: Cuando el cajero escribe el "Subtotal Final Pactado ($)" (ej: "Llevo 3, ¿me los dejás en $10.000 los tres?"):
  /// Calcula el precio unitario, retiene `manualSubtotal` si la división deja residuo de centavos,
  /// mantiene el Costo como ancla inamovible y desmarca el guardado en BD por seguridad.
  void _onLineSubtotalChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;
    _priceExplicitlyEdited = true;

    final targetSubtotal = _parseArs(val);
    final qty = _currentQty;
    final cost = _parseArs(_costController.text);

    if (targetSubtotal > 0 && qty > 0) {
      final unitPrice = ((targetSubtotal / qty) * 100).roundToDouble() / 100.0;
      _priceController.text = unitPrice.toArsInput();

      final recomputedSub = ((unitPrice * qty) * 100).roundToDouble() / 100.0;
      if ((targetSubtotal - recomputedSub).abs() >= 0.005) {
        _manualSubtotalOverride = targetSubtotal;
      } else {
        _manualSubtotalOverride = null;
      }

      if (cost > 0 && unitPrice > 0) {
        final calcMargin = ((unitPrice - cost) / cost) * 100.0;
        _marginController.text = calcMargin.toCleanMargin();
      }

      final refSub = _defaultCartPriceForQuantity(qty) * qty;
      if (refSub > 0 && targetSubtotal < refSub - 0.005) {
        final pct = ((refSub - targetSubtotal) / refSub) * 100.0;
        _discountPctController.text = pct > 0.04 ? pct.toCleanMargin() : '';
        _updateCatalogInDb = false;
      } else {
        _discountPctController.clear();
      }
    } else if (val.trim().isEmpty) {
      _manualSubtotalOverride = null;
      _priceController.clear();
      _marginController.clear();
      _discountPctController.clear();
    }

    _isUpdatingCalc = false;
    setState(() {});
  }

  /// Punto 1: Cuando el cajero escribe un % de Descuento o toca un chip rápido (-5%, -10%, -15%, -20%).
  void _onDiscountPercentageChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;
    _manualSubtotalOverride = null;

    final discStr = val.trim();
    final discPct = _parseDouble(discStr).clamp(0.0, 99.9);
    final qty = _currentQty;
    final refPrice = _defaultCartPriceForQuantity(qty);
    final cost = _parseArs(_costController.text);

    if (discStr.isNotEmpty && discPct > 0 && refPrice > 0) {
      _priceExplicitlyEdited = true;
      final discountedUnit =
          ((refPrice * (1.0 - (discPct / 100.0))) * 100).roundToDouble() / 100.0;
      _priceController.text = discountedUnit.toArsInput();

      final newSub = ((discountedUnit * qty) * 100).roundToDouble() / 100.0;
      _subtotalController.text = newSub > 0 ? newSub.toArsInput() : '';

      if (cost > 0 && discountedUnit > 0) {
        final calcMargin = ((discountedUnit - cost) / cost) * 100.0;
        _marginController.text = calcMargin.toCleanMargin();
      }
      // Un descuento de mostrador nunca debe pisar por accidente el precio de catálogo en BD
      _updateCatalogInDb = false;
    } else if (discStr.isEmpty || discPct == 0) {
      _priceExplicitlyEdited = false;
      _priceController.text = refPrice > 0 ? refPrice.toArsInput() : '';
      final newSub = ((refPrice * qty) * 100).roundToDouble() / 100.0;
      _subtotalController.text = newSub > 0 ? newSub.toArsInput() : '';
      if (cost > 0 && refPrice > 0) {
        _marginController.text =
            (((refPrice - cost) / cost) * 100.0).toCleanMargin();
      }
    }

    _isUpdatingCalc = false;
    setState(() {});
  }

  void _applyQuickDiscountChip(double pct) {
    final currentPct = _parseDouble(_discountPctController.text);
    if ((currentPct - pct).abs() < 0.05) {
      // Si ya estaba activo ese mismo chip, al volver a tocarlo restaura el precio sin descuento
      _discountPctController.clear();
      _onDiscountPercentageChanged('');
    } else {
      _discountPctController.text = pct.toCleanMargin();
      _onDiscountPercentageChanged(_discountPctController.text);
    }
  }

  /// Cuando el usuario edita explícitamente el Costo:
  /// Si hay un % de Margen cargado, recalcula el Precio de Venta manteniendo ese margen.
  /// Si no había margen y hay Precio de Venta, calcula el nuevo % de Margen.
  void _onCostPriceChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;
    _costExplicitlyEdited = true;

    final cost = _parseArs(val);
    final marginStr = _marginController.text.trim();
    final margin = _parseDouble(marginStr);
    final price = _parseArs(_priceController.text);
    final qty = _currentQty;

    if (cost > 0) {
      if (marginStr.isNotEmpty && margin > -100) {
        final calcSelling = cost * (1.0 + (margin / 100.0));
        _priceController.text = calcSelling.toArsInput();
        _priceExplicitlyEdited = true;
        _manualSubtotalOverride = null;
        final newSub = ((calcSelling * qty) * 100).roundToDouble() / 100.0;
        _subtotalController.text = newSub > 0 ? newSub.toArsInput() : '';
        _syncDiscountFieldFromUnitPrice(calcSelling, qty);
      } else if (price > 0) {
        final calcMargin = ((price - cost) / cost) * 100.0;
        _marginController.text = calcMargin.toCleanMargin();
      }
    } else if (val.trim().isEmpty) {
      _marginController.clear();
    }

    _isUpdatingCalc = false;
    setState(() {});
  }

  /// Cuando el usuario edita el % de Margen:
  /// El Costo actúa como ancla fija y se recalcula el Precio de Venta.
  void _onMarginChanged(String val) {
    if (_isUpdatingCalc) return;
    _isUpdatingCalc = true;

    final marginStr = val.trim();
    final margin = _parseDouble(marginStr);
    final cost = _parseArs(_costController.text);
    final price = _parseArs(_priceController.text);
    final qty = _currentQty;

    if (marginStr.isNotEmpty && margin > -100) {
      if (cost > 0) {
        final calcSelling = cost * (1.0 + (margin / 100.0));
        _priceController.text = calcSelling.toArsInput();
        _priceExplicitlyEdited = true;
        _manualSubtotalOverride = null;
        final newSub = ((calcSelling * qty) * 100).roundToDouble() / 100.0;
        _subtotalController.text = newSub > 0 ? newSub.toArsInput() : '';
        _syncDiscountFieldFromUnitPrice(calcSelling, qty);
      } else if (price > 0) {
        final calcCost = price / (1.0 + (margin / 100.0));
        _costController.text = calcCost.toArsInput();
        _costExplicitlyEdited = true;
      }
    }

    _isUpdatingCalc = false;
    setState(() {});
  }

  void _restoreCatalogName() {
    setState(() {
      _descController.text = widget.item.product.name;
    });
  }

  void _restoreCatalogPrices() {
    _isUpdatingCalc = true;
    final qty = _currentQty;
    final origPrice = _defaultCartPriceForQuantity(qty);
    final origCost = _catalogBaseCostPrice;
    final origSub = ((origPrice * qty) * 100).roundToDouble() / 100.0;
    _priceController.text = origPrice > 0 ? origPrice.toArsInput() : '';
    _subtotalController.text = origSub > 0 ? origSub.toArsInput() : '';
    _costController.text = origCost > 0 ? origCost.toArsInput() : '';
    _marginController.text = (origCost > 0 && origPrice > 0)
        ? (((origPrice - origCost) / origCost) * 100.0).toCleanMargin()
        : '';
    _discountPctController.clear();
    _manualSubtotalOverride = null;
    final rawIva = widget.item.product.ivaRate;
    _ivaRate = const [0.0, 10.5, 21.0, 27.0].contains(rawIva) ? rawIva : 21.0;
    _priceExplicitlyEdited = false;
    _costExplicitlyEdited = false;
    _restoredToCatalogPrices = true;
    _updateCatalogInDb = false;
    _updateCatalogName = false;
    _isUpdatingCalc = false;
    setState(() {});
  }

  bool get _hasSellingPriceChanged {
    final parsedPrice = _parseArs(_priceController.text);
    if (parsedPrice <= 0) return false;
    if (_updateCatalogInDb && !_isTempOrUnregistered) {
      return (parsedPrice - _catalogBaseSellingPrice).abs() >= 0.005;
    }
    return _priceExplicitlyEdited ||
        _manualSubtotalOverride != null ||
        (parsedPrice - _catalogDefaultCartPrice).abs() >= 0.005;
  }

  bool get _hasCostPriceChanged {
    if (!_costExplicitlyEdited) return false;
    final costText = _costController.text.trim();
    if (costText.isEmpty) return _catalogBaseCostPrice > 0.005;
    final parsedCost = _parseArs(costText);
    return (parsedCost - _catalogBaseCostPrice).abs() >= 0.005;
  }

  bool get _hasBarcodeChanged {
    if (_isTempOrUnregistered || widget.item.product.isCombo) return false;
    final candidate = _barcodeController.text.trim();
    return candidate.isNotEmpty && candidate != _originalBarcode;
  }

  bool get _hasIvaRateChanged {
    final origIva = const [0.0, 10.5, 21.0, 27.0]
            .contains(widget.item.product.ivaRate)
        ? widget.item.product.ivaRate
        : 21.0;
    return (_ivaRate - origIva).abs() >= 0.01;
  }

  double? get _parsedShelfStockBeforeSale {
    final raw = _shelfStockController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  bool get _hasShelfStockChanged {
    if (_isTempOrUnregistered ||
        widget.item.product.isService ||
        widget.item.product.isCombo) {
      return false;
    }
    final parsed = _parsedShelfStockBeforeSale;
    if (parsed == null) return false;
    return (parsed - widget.item.product.stock).abs() >= 0.0005;
  }

  bool get _hasCatalogNameUpdate {
    if (_isTempOrUnregistered || !_updateCatalogName) return false;
    final clean = _descController.text.trim();
    return clean.isNotEmpty && clean != widget.item.product.name.trim();
  }

  int get _pendingDbChangeCount {
    if (_isTempOrUnregistered) return 0;
    int count = 0;
    if (_hasCatalogNameUpdate) count++;
    if (_hasShelfStockChanged) count++;
    if (_hasIvaRateChanged) count++;
    if (_updateCatalogInDb && (_hasSellingPriceChanged || _hasCostPriceChanged)) {
      count++;
    }
    if (_hasBarcodeChanged) count++;
    return count;
  }

  bool get _hasAnyDbChange => _pendingDbChangeCount > 0;

  double get _effectiveLineSubtotal {
    final price = _parseArs(_priceController.text);
    final qty = _currentQty;
    final calc = ((price * qty) * 100).roundToDouble() / 100.0;
    if (_manualSubtotalOverride != null && _manualSubtotalOverride! > 0) {
      final maxTol = (0.02 * qty.abs()) > 0.05 ? (0.02 * qty.abs()) : 0.05;
      if ((_manualSubtotalOverride! - calc).abs() <= maxTol + 0.001) {
        return _manualSubtotalOverride!;
      }
    }
    return calc;
  }

  double get _customerSavingsAmount {
    final refSub = _catalogDefaultCartPrice * _currentQty;
    final effSub = _effectiveLineSubtotal;
    if (refSub > 0 && effSub > 0 && effSub < refSub - 0.01) {
      return refSub - effSub;
    }
    return 0.0;
  }

  bool _isSubmitted = false;

  /// Atajos globales del diálogo, independientes del campo que tenga el foco:
  /// - Esc → Cancelar y cerrar.
  /// - Enter / NumpadEnter → Aplicar (excepto si el foco está en el lector de código de barras,
  ///   donde el Enter del láser solo confirma la captura del EAN sin cerrar el diálogo).
  bool _handleDialogKey(KeyEvent event) {
    if (!mounted || _isSubmitted) return false;
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) return false;
      if (_customPartsFocus.hasFocus) {
        _applyCustomParts();
        return true;
      }
      if (_barcodeFocus.hasFocus) {
        _barcodeFocus.unfocus();
        setState(() {
          _barcodeCapturedByScanner = _barcodeController.text.trim().isNotEmpty;
        });
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
    _isSubmitted = true;

    final cleanDesc = _descController.text.trim();
    final cleanDetails = _detailsController.text.trim();
    final parsedPriceVal = _parseArs(_priceController.text);
    final parsedPrice = parsedPriceVal > 0 ? parsedPriceVal : null;
    final costText = _costController.text.trim();
    final parsedCost = costText.isNotEmpty ? _parseArs(costText) : null;
    final qty = _currentQty;
    final qtyChanged = (qty - widget.item.quantity).abs() >= 0.0005;

    final sellingChanged = _hasSellingPriceChanged;
    final costChanged = _hasCostPriceChanged;
    final ivaChanged = _hasIvaRateChanged;
    final barcodeChanged = _hasBarcodeChanged;
    final cleanBarcode = _barcodeController.text.trim();
    final nameChangedInDb = _hasCatalogNameUpdate;
    final shelfChanged = _hasShelfStockChanged;
    final shelfStockVal = shelfChanged ? _parsedShelfStockBeforeSale : null;

    final shouldUpdatePriceCostInDb = !_isTempOrUnregistered &&
        _updateCatalogInDb &&
        (sellingChanged || costChanged);
    final updateIvaInDb = !_isTempOrUnregistered && ivaChanged;

    final preserveUneditedAgreedPrice = widget.item.hasAgreedPrice &&
        !_priceExplicitlyEdited &&
        !_restoredToCatalogPrices &&
        _manualSubtotalOverride == null &&
        !shouldUpdatePriceCostInDb &&
        parsedPrice != null &&
        (parsedPrice - widget.item.agreedUnitPrice!).abs() < 0.005;

    Navigator.of(context).pop(
      PosRenameCartItemResult(
        customDescription: cleanDesc,
        customDetails: cleanDetails.isNotEmpty ? cleanDetails : null,
        newUnitPrice: (!preserveUneditedAgreedPrice &&
                parsedPrice != null &&
                parsedPrice > 0)
            ? parsedPrice
            : null,
        clearManualUnitPrice: !_isTempOrUnregistered &&
            !preserveUneditedAgreedPrice &&
            !sellingChanged &&
            !shouldUpdatePriceCostInDb,
        newCostPrice: costChanged ? (parsedCost ?? 0.0) : null,
        clearManualCostPrice:
            !_isTempOrUnregistered && !costChanged && !shouldUpdatePriceCostInDb,
        newManualSubtotal:
            shouldUpdatePriceCostInDb ? null : _manualSubtotalOverride,
        clearManualSubtotal:
            _manualSubtotalOverride == null || shouldUpdatePriceCostInDb,
        newQuantity: qtyChanged ? qty : null,
        newIvaRate: ivaChanged ? _ivaRate : null,
        ivaRateChanged: ivaChanged,
        newBarcode: barcodeChanged ? cleanBarcode : null,
        barcodeChanged: barcodeChanged,
        updateCatalogInDb: shouldUpdatePriceCostInDb,
        updateCatalogName: nameChangedInDb,
        updateIvaInDb: updateIvaInDb,
        newShelfStockBeforeSale: shelfStockVal,
        shelfStockChanged: shelfChanged,
        sellingPriceChanged: sellingChanged,
        costPriceChanged: costChanged,
      ),
    );
  }

  String _buildDbImpactSummary() {
    final parsedPrice = _parseArs(_priceController.text);
    final parsedCost = _parseArs(_costController.text);
    final sellingChanged = parsedPrice > 0 &&
        (parsedPrice - _catalogBaseSellingPrice).abs() >= 0.005;
    final costChanged = _hasCostPriceChanged;

    if (!sellingChanged && !costChanged) {
      return 'Modificá el Precio de Venta y/o el Costo arriba para actualizar la Base de Datos.';
    }
    if (sellingChanged && !costChanged) {
      final costInfo = _catalogBaseCostPrice > 0
          ? 'El Costo (\$${_catalogBaseCostPrice.toArsInput()}) queda 100% intacto.'
          : 'El Costo no se modifica.';
      return 'Se guardará el nuevo Precio de Venta (\$${parsedPrice.toArsInput()}) en la Base de Datos. $costInfo';
    }
    if (sellingChanged && costChanged) {
      return 'Se guardarán en la Base de Datos el nuevo Precio de Venta (\$${parsedPrice.toArsInput()}) y el nuevo Costo (\$${parsedCost.toArsInput()}).';
    }
    return 'Se guardará el nuevo Costo (\$${parsedCost.toArsInput()}) en la Base de Datos (el Precio de Venta se mantiene en \$${_catalogBaseSellingPrice.toArsInput()}).';
  }

  void _handleRemoteBarcodeScan(String barcode) {
    final clean = barcode.trim();
    if (clean.isEmpty || !mounted) return;
    if (_isTempOrUnregistered || widget.item.product.isCombo) {
      SnackBarService.warning(
        context,
        'Este ítem no admite asignar código de barras desde aquí.',
      );
      return;
    }
    setState(() {
      _expandCatalogZone = true;
      _showBarcodeEditor = true;
      _barcodeController.text = clean;
      _barcodeCapturedByScanner = _barcodeController.text.trim().isNotEmpty;
    });
    _barcodeFocus.unfocus();
    SnackBarService.success(
      context,
      '🔫 Código $clean capturado. Presioná Enter o "Aplicar" para guardarlo en BD.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isResponsableInscripto =
        context.watch<SettingsProvider?>()?.settings?.isResponsableInscripto ?? false;
    final originalName = widget.item.product.name;
    final showRestorePrices = !_isTempOrUnregistered &&
        (_hasSellingPriceChanged ||
            _hasCostPriceChanged ||
            _hasIvaRateChanged ||
            widget.item.hasManualPriceOverride);
    final savings = _customerSavingsAmount;
    final refSub = _catalogDefaultCartPrice * _currentQty;
    final savingsPct =
        (refSub > 0 && savings > 0) ? ((savings / refSub) * 100.0) : 0.0;
    final currentDiscInput = _parseDouble(_discountPctController.text);

    final settingsProv = context.watch<SettingsProvider?>();
    final rubros =
        Provider.of<CatalogProvider?>(context, listen: false)?.safeRubros ??
            const [];
    final profile = settingsProv?.safeVerticalProfile ??
        BusinessVerticalProfile.fromType(BusinessVerticalProfile.retail);
    final isHardwareStore = profile.isHardwareStore;
    final canRecalcHardware = widget.onOpenHardwareCalculator != null &&
        !_isTempOrUnregistered &&
        (settingsProv?.canUseHardwareCalculatorFor(
              product: widget.item.product,
              rubros: rubros,
            ) ??
            false);
    final preferDiscrete = widget.item.product.isDiscreteFractionalItem(
      businessUsesScaleWeight: profile.canUseScaleWeight,
    );
    final isHardwareFractional = _isSoldByWeight &&
        (isHardwareStore ||
            widget.item.product.isMetricOrLiquidUnit ||
            preferDiscrete ||
            !profile.canUseScaleWeight);
    final unitShortLabel = Product.resolveQuantityUnitLabel(
      unitType: widget.item.product.unitType,
      isSoldByWeight: _isSoldByWeight,
      preferDiscreteUn: preferDiscrete,
    );
    final unitSuffixUpper = isHardwareFractional
        ? unitShortLabel.toUpperCase()
        : (_isSoldByWeight ? 'KG' : 'UN');

    return RemoteScannerListener(
      debugLabel: 'PosRenameCartItemDialog',
      onBarcodeScanned: _handleRemoteBarcodeScan,
      child: Focus(
        autofocus: false,
        child: AppModalShell(
          title: _isTempOrUnregistered
              ? 'Editar Ítem Rápido en Carrito'
              : 'Editar Línea en Carrito (Ctrl+E)',
          subtitle: _isTempOrUnregistered
              ? 'Ítem Rápido de Mostrador'
              : 'Catálogo original: $originalName',
          icon: Icons.edit_note_rounded,
          accent:
              _hasAnyDbChange ? AppModalAccent.blue : AppModalAccent.indigo,
          maxWidth: 700,
          expandBody: false,
          bodyPadding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          body: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                  // Campo de descripción personalizada
                  TextFormField(
                    controller: _descController,
                    focusNode: _descFocus,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText:
                          'Descripción a imprimir en Factura A/B/C y Ticket *',
                      hintText: originalName,
                      prefixIcon:
                          const Icon(Icons.drive_file_rename_outline, size: 20),
                      suffixIcon: !_isTempOrUnregistered
                          ? IconButton(
                              onPressed: _restoreCatalogName,
                              tooltip: 'Restaurar nombre original del catálogo',
                              icon: const Icon(Icons.restore_rounded, size: 19),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'La descripción no puede quedar vacía';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // ── Punto 6: Fila Unificada de Cantidad / Peso + Notas ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: _isSoldByWeight ? 6 : 5,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!_isSoldByWeight) ...[
                               SizedBox(
                                height: 42,
                                width: 36,
                                child: OutlinedButton(
                                  onPressed: () => _stepUnitQuantity(-1),
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                  child: const Icon(Icons.remove, size: 17),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: TextFormField(
                                controller: _qtyController,
                                focusNode: _qtyFocus,
                                keyboardType: widget.item.product.isService
                                    ? TextInputType.number
                                    : const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: widget.item.product.isService
                                    ? [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ]
                                    : [
                                        FilteringTextInputFormatter.allow(
                                          _isSoldByWeight
                                              ? RegExp(r'[0-9.,]')
                                              : RegExp(r'[0-9.,/]'),
                                        ),
                                      ],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                                onChanged: _onQuantityChanged,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: isHardwareFractional
                                      ? 'Cantidad ($unitShortLabel)'
                                      : (_isSoldByWeight
                                          ? 'Peso (KG)'
                                          : 'Cantidad'),
                                  suffixText: unitSuffixUpper,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
                                validator: (val) {
                                  final parsed =
                                      parseQuantityOrFraction(val ?? '');
                                  final minQ = widget.item.product.isService
                                      ? 1.0
                                      : 0.001;
                                  final maxQ = (_isSoldByWeight &&
                                          !isHardwareFractional)
                                      ? 1000.0
                                      : 100000.0;
                                  if (parsed == null ||
                                      parsed < minQ ||
                                      parsed >= maxQ) {
                                    return (_isSoldByWeight &&
                                            !isHardwareFractional)
                                        ? '0.001 a 999 Kg'
                                        : 'Cantidad inválida';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            if (!_isSoldByWeight) ...[
                              const SizedBox(width: 6),
                              SizedBox(
                                height: 42,
                                width: 36,
                                child: OutlinedButton(
                                  onPressed: () => _stepUnitQuantity(1),
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                  child: const Icon(Icons.add, size: 17),
                                ),
                              ),
                            ],
                            if (_isSoldByWeight && profile.canUseScaleWeight) ...[
                              const SizedBox(width: 6),
                              Consumer<LocalTerminalProvider>(
                                builder: (ctx, localTerminal, _) {
                                  final comPort = localTerminal.scaleComPort;
                                  final isConfigured =
                                      comPort.trim().isNotEmpty;
                                  return SizedBox(
                                    height: 42,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        if (!isConfigured) {
                                          showTerminalPeripheralsDialog(
                                              context);
                                          return;
                                        }
                                        _readWeightFromScale(comPort);
                                      },
                                      icon: Icon(
                                        Icons.scale_rounded,
                                        size: 16,
                                        color: isConfigured
                                            ? Colors.blueGrey.shade700
                                            : Colors.grey,
                                      ),
                                      label: Text(
                                        isConfigured ? 'Balanza' : 'Config.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isConfigured
                                              ? Colors.blueGrey.shade800
                                              : Colors.grey,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(9),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 6,
                        child: TextFormField(
                          controller: _detailsController,
                          maxLines: 1,
                          decoration: InputDecoration(
                            labelText: 'Notas en línea (Opcional)',
                            hintText: 'Ej: N° de serie, color...',
                            prefixIcon:
                                const Icon(Icons.notes_rounded, size: 19),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      if (!_isSoldByWeight && !widget.item.product.isService) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: _showPortionsBar
                              ? 'Ocultar fracciones rápidas'
                              : 'Mostrar fracciones rápidas (1/8, 1/6, 1/4, 1/2)',
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton(
                              onPressed: () => setState(
                                () => _showPortionsBar = !_showPortionsBar,
                              ),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                backgroundColor: _showPortionsBar
                                    ? const Color(0xFFEDE9FE)
                                    : null,
                                foregroundColor: _showPortionsBar
                                    ? const Color(0xFF5B21B6)
                                    : const Color(0xFF475569),
                                side: BorderSide(
                                  color: _showPortionsBar
                                      ? const Color(0xFF7C3AED)
                                      : const Color(0xFFCBD5E1),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                              child: const Text(
                                '1/x',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!_isSoldByWeight &&
                      !widget.item.product.isService &&
                      _showPortionsBar) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Porción rápida:',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                        for (final chip in const <({String label, double qty})>[
                          (label: '1/8', qty: 0.125),
                          (label: '2/8', qty: 0.250),
                          (label: '1/6', qty: 0.167),
                          (label: '1/4', qty: 0.250),
                          (label: '1/2', qty: 0.500),
                          (label: '1', qty: 1.0),
                        ])
                          InkWell(
                            borderRadius: BorderRadius.circular(7),
                            onTap: () =>
                                _applyQuickPortion(chip.label, chip.qty),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: ((_currentQty - chip.qty).abs() <
                                            0.0006 &&
                                        (_descController.text.contains(
                                                '(${chip.label})') ||
                                            (chip.label != '2/8' &&
                                                chip.label != '1') ||
                                            (chip.label == '1' &&
                                                !_descController.text
                                                    .contains('Porción ('))))
                                    ? const Color(0xFFEDE9FE)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: ((_currentQty - chip.qty).abs() <
                                              0.0006 &&
                                          (_descController.text.contains(
                                                  '(${chip.label})') ||
                                              (chip.label != '2/8' &&
                                                  chip.label != '1') ||
                                              (chip.label == '1' &&
                                                  !_descController.text
                                                      .contains('Porción ('))))
                                      ? const Color(0xFF7C3AED)
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Text(
                                chip.label == '1'
                                    ? '1 entero'
                                    : '${chip.label} (${chip.qty.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')})',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: ((_currentQty - chip.qty).abs() <
                                              0.0006 &&
                                          (_descController.text.contains(
                                                  '(${chip.label})') ||
                                              (chip.label != '2/8' &&
                                                  chip.label != '1') ||
                                              (chip.label == '1' &&
                                                  !_descController.text
                                                      .contains('Porción ('))))
                                      ? const Color(0xFF5B21B6)
                                      : const Color(0xFF334155),
                                ),
                              ),
                            ),
                          ),
                        const Text(
                          'o ÷',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        SizedBox(
                          width: 54,
                          height: 28,
                          child: TextField(
                            key: const Key('rename_custom_parts_input'),
                            controller: _customPartsController,
                            focusNode: _customPartsFocus,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                            onSubmitted: (_) => _applyCustomParts(),
                            decoration: InputDecoration(
                              hintText: '16',
                              hintStyle: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 5,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          key: const Key('rename_apply_custom_parts_btn'),
                          borderRadius: BorderRadius.circular(7),
                          onTap: _applyCustomParts,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE9FE),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: const Color(0xFF7C3AED),
                              ),
                            ),
                            child: const Text(
                              'Aplicar (1/N)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  // ── Sección de Precio de Venta, Subtotal Pactado, Descuento Rápido, Costo y % Margen ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.price_change_outlined,
                              size: 17,
                              color: Colors.indigo.shade700,
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Precio, Descuento Rápido y Rentabilidad',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            if (showRestorePrices)
                              TextButton.icon(
                                onPressed: _restoreCatalogPrices,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon:
                                    const Icon(Icons.restore_rounded, size: 15),
                                label: Text(
                                  'Restaurar (\$${_catalogDefaultCartPrice.toArsInput()})',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Precio de Venta Unitario
                            Expanded(
                              flex: 4,
                              child: TextFormField(
                                controller: _priceController,
                                focusNode: _priceFocus,
                                keyboardType: TextInputType.number,
                                inputFormatters: const [
                                  ArsThousandsInputFormatter(),
                                ],
                                onChanged: _onSellingPriceChanged,
                                onFieldSubmitted: (_) => _submit(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Precio Unit.',
                                  prefixText: '\$ ',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
                                validator: (val) {
                                  final parsed = _parseArs(val ?? '');
                                  if (parsed <= 0) {
                                    return 'Precio inválido';
                                  }
                                  if (_updateCatalogInDb &&
                                      !_isTempOrUnregistered) {
                                    final effectiveCost = _hasCostPriceChanged
                                        ? _parseArs(_costController.text)
                                        : _catalogBaseCostPrice;
                                    if (effectiveCost > 0 &&
                                        parsed < effectiveCost - 0.005) {
                                      return 'Menor al costo (\$${effectiveCost.toArsInput()})';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 7),

                            // 2. Total de Línea / Subtotal Pactado ("3 por $10.000")
                            Expanded(
                              flex: 4,
                              child: TextFormField(
                                controller: _subtotalController,
                                focusNode: _subtotalFocus,
                                keyboardType: TextInputType.number,
                                inputFormatters: const [
                                  ArsThousandsInputFormatter(),
                                ],
                                onChanged: _onLineSubtotalChanged,
                                onFieldSubmitted: (_) => _submit(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: Colors.indigo.shade900,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Total Línea',
                                  prefixText: '\$ ',
                                  filled: true,
                                  fillColor: const Color(0xFFEEF2FF),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),

                            // 3. Precio de Costo (Ancla)
                            Expanded(
                              flex: 4,
                              child: TextFormField(
                                controller: _costController,
                                enabled: !widget.item.product.isCombo,
                                keyboardType: TextInputType.number,
                                inputFormatters: const [
                                  ArsThousandsInputFormatter(),
                                ],
                                onChanged: _onCostPriceChanged,
                                onFieldSubmitted: (_) => _submit(),
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: widget.item.product.isCombo
                                      ? 'Costo Receta'
                                      : 'Costo',
                                  prefixText: '\$ ',
                                  hintText: '0',
                                  filled: true,
                                  fillColor: widget.item.product.isCombo
                                      ? Colors.grey.shade100
                                      : Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),

                            // 4. % de Margen
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _marginController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true, signed: true),
                                onChanged: _onMarginChanged,
                                onFieldSubmitted: (_) => _submit(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal.shade800,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Margen',
                                  suffixText: '%',
                                  hintText: '0',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── Punto 1: Barra de Descuento Rápido por Línea (% chips + input + IVA AFIP en 1 sola línea) ──
                        if (!_isTempOrUnregistered) ...[
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.local_offer_outlined,
                                size: 15,
                                color: Color(0xFF475569),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'Desc. rápido:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(width: 6),
                              for (final pct in const [5.0, 10.0, 15.0, 20.0])
                                Padding(
                                  padding: const EdgeInsets.only(right: 5),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(7),
                                    onTap: () => _applyQuickDiscountChip(pct),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: (currentDiscInput - pct).abs() <
                                                0.05
                                            ? const Color(0xFF059669)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color:
                                              (currentDiscInput - pct).abs() <
                                                      0.05
                                                  ? const Color(0xFF059669)
                                                  : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                      child: Text(
                                        '-${pct.toInt()}%',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              (currentDiscInput - pct).abs() <
                                                      0.05
                                                  ? Colors.white
                                                  : const Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              SizedBox(
                                width: 98,
                                child: TextFormField(
                                  controller: _discountPctController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: _onDiscountPercentageChanged,
                                  onFieldSubmitted: (_) => _submit(),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF047857),
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Desc. %',
                                    labelStyle: const TextStyle(fontSize: 11.5),
                                    suffixText: '%',
                                    hintText: '0',
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (isResponsableInscripto &&
                                  _isTempOrUnregistered) ...[
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<double>(
                                    initialValue: _ivaRate,
                                    isExpanded: true,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E293B),
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'IVA AFIP',
                                      labelStyle: const TextStyle(fontSize: 11.5),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 7),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      isDense: true,
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 21.0, child: Text('21%')),
                                      DropdownMenuItem(value: 10.5, child: Text('10.5%')),
                                      DropdownMenuItem(value: 27.0, child: Text('27%')),
                                      DropdownMenuItem(value: 0.0, child: Text('0% Ex.')),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => _ivaRate = v);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],

                        // Badge de ahorro en vivo para el cliente
                        if (savings > 0.01) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFA7F3D0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.savings_outlined,
                                  size: 16,
                                  color: Color(0xFF047857),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'El cliente ahorra \$${savings.toCurrency()} (-${savingsPct.toCleanMargin()}%) en esta línea'
                                    '${_manualSubtotalOverride != null ? ' · Subtotal pactado exacto: \$${_manualSubtotalOverride!.toCurrency()}' : ''}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF065F46),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Fin Zona 1 (Precios / Descuentos / Total de línea)
                      ],
                    ),
                  ),

                  // ── Zona 2 (Colapsable): Corregir en Catálogo (BD) ──
                  if (!_isTempOrUnregistered) ...[
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: _hasAnyDbChange
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _hasAnyDbChange
                              ? const Color(0xFF3B82F6)
                              : const Color(0xFFE2E8F0),
                          width: _hasAnyDbChange ? 1.3 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => setState(
                                () => _expandCatalogZone = !_expandCatalogZone),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.settings_suggest_rounded,
                                    size: 18,
                                    color: _hasAnyDbChange
                                        ? const Color(0xFF1D4ED8)
                                        : const Color(0xFF475569),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Corregir en catálogo (BD)',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: _hasAnyDbChange
                                            ? const Color(0xFF1E3A8A)
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _hasAnyDbChange
                                          ? const Color(0xFFDBEAFE)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: _hasAnyDbChange
                                            ? const Color(0xFF93C5FD)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Text(
                                      _hasAnyDbChange
                                          ? '$_pendingDbChangeCount cambio${_pendingDbChangeCount == 1 ? '' : 's'} en BD'
                                          : 'Stock · Nombre · Precio · IVA · EAN',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: _hasAnyDbChange
                                            ? const Color(0xFF1D4ED8)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    _expandCatalogZone
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    size: 20,
                                    color: const Color(0xFF64748B),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_expandCatalogZone) ...[
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 1. Stock físico en góndola + Alícuota IVA AFIP (en fila si ambos aplican)
                                  if ((!widget.item.product.isService &&
                                          !widget.item.product.isCombo) ||
                                      isResponsableInscripto) ...[
                                    Builder(
                                      builder: (_) {
                                        final showStock =
                                            !widget.item.product.isService &&
                                                !widget.item.product.isCombo;

                                        Widget buildStockField() =>
                                            TextFormField(
                                              controller:
                                                  _shelfStockController,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                  decimal: true),
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .allow(RegExp(r'[0-9.,]')),
                                              ],
                                              onChanged: (_) =>
                                                  setState(() {}),
                                              onFieldSubmitted: (_) =>
                                                  _submit(),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: _hasShelfStockChanged
                                                    ? const Color(0xFF1D4ED8)
                                                    : const Color(0xFF0F172A),
                                              ),
                                              decoration: InputDecoration(
                                                labelText: isResponsableInscripto
                                                    ? 'Stock físico en góndola'
                                                    : 'Stock físico en góndola (antes de esta venta)',
                                                helperText: (widget.item.product
                                                                .minStock ??
                                                            0) >
                                                        0
                                                    ? 'Stock en BD: ${widget.item.product.stock.toUnitStockDisplay(isSoldByWeight: _isSoldByWeight, unitSuffix: isHardwareFractional ? unitShortLabel : 'u', weightUnit: isHardwareFractional ? unitShortLabel : 'kg')} · Mín. alerta: ${widget.item.product.minStock!.toUnitStockDisplay(isSoldByWeight: _isSoldByWeight, unitSuffix: isHardwareFractional ? unitShortLabel : 'u', weightUnit: isHardwareFractional ? unitShortLabel : 'kg')}'
                                                    : 'Stock en BD: ${widget.item.product.stock.toUnitStockDisplay(isSoldByWeight: _isSoldByWeight, unitSuffix: isHardwareFractional ? unitShortLabel : 'u', weightUnit: isHardwareFractional ? unitShortLabel : 'kg')}',
                                                suffixText: unitSuffixUpper,
                                                prefixIcon: const Icon(
                                                    Icons.inventory_2_outlined,
                                                    size: 18),
                                                suffixIcon: _hasShelfStockChanged
                                                    ? IconButton(
                                                        tooltip:
                                                            'Restaurar stock del catálogo',
                                                        icon: const Icon(
                                                            Icons.restore_rounded,
                                                            size: 18),
                                                        onPressed: () {
                                                          setState(() {
                                                            _shelfStockController
                                                                    .text =
                                                                _formatQtyForInput(
                                                                    widget
                                                                        .item
                                                                        .product
                                                                        .stock);
                                                          });
                                                        },
                                                      )
                                                    : null,
                                                filled: true,
                                                fillColor: Colors.white,
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                isDense: true,
                                              ),
                                              validator: (v) {
                                                final raw = (v ?? '').trim();
                                                if (raw.isEmpty) return null;
                                                final parsed = double.tryParse(
                                                    raw.replaceAll(',', '.'));
                                                if (parsed == null ||
                                                    parsed < 0 ||
                                                    parsed >= 1000000) {
                                                  return 'Ingresá un stock válido (>= 0)';
                                                }
                                                return null;
                                              },
                                            );

                                        Widget buildIvaDropdown() =>
                                            DropdownButtonFormField<double>(
                                              initialValue: _ivaRate,
                                              isExpanded: true,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: _hasIvaRateChanged
                                                    ? const Color(0xFF1D4ED8)
                                                    : const Color(0xFF1E293B),
                                              ),
                                              decoration: InputDecoration(
                                                labelText:
                                                    'Alícuota IVA en Catálogo (BD)',
                                                labelStyle: const TextStyle(
                                                    fontSize: 11.5),
                                                helperText: _hasIvaRateChanged &&
                                                        showStock
                                                    ? 'Se actualizará en BD'
                                                    : null,
                                                helperStyle: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF1D4ED8),
                                                ),
                                                filled: true,
                                                fillColor: Colors.white,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 8),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                isDense: true,
                                              ),
                                              items: const [
                                                DropdownMenuItem(
                                                    value: 21.0,
                                                    child: Text('IVA 21%')),
                                                DropdownMenuItem(
                                                    value: 10.5,
                                                    child: Text('IVA 10.5%')),
                                                DropdownMenuItem(
                                                    value: 27.0,
                                                    child: Text('IVA 27%')),
                                                DropdownMenuItem(
                                                    value: 0.0,
                                                    child: Text('0% Exento')),
                                              ],
                                              onChanged: (v) {
                                                if (v != null) {
                                                  setState(() => _ivaRate = v);
                                                }
                                              },
                                            );

                                        if (showStock && isResponsableInscripto) {
                                          return Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                  flex: 6,
                                                  child: buildStockField()),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                  flex: 4,
                                                  child: buildIvaDropdown()),
                                            ],
                                          );
                                        }
                                        if (showStock) {
                                          return buildStockField();
                                        }
                                        return Row(
                                          children: [
                                            Expanded(child: buildIvaDropdown()),
                                            if (_hasIvaRateChanged) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 6),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFDBEAFE),
                                                  borderRadius:
                                                      BorderRadius.circular(7),
                                                ),
                                                child: const Text(
                                                  'Se actualizará en BD',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF1D4ED8),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                    if (!widget.item.product.isService &&
                                        !widget.item.product.isCombo &&
                                        _hasShelfStockChanged &&
                                        _parsedShelfStockBeforeSale !=
                                            null) ...[
                                      const SizedBox(height: 6),
                                      Builder(
                                        builder: (_) {
                                          final target =
                                              _parsedShelfStockBeforeSale!;
                                          final delta = target -
                                              widget.item.product.stock;
                                          final afterSale =
                                              target - _currentQty;
                                          final sign = delta > 0 ? '+' : '';
                                          final suffix = isHardwareFractional
                                              ? unitShortLabel
                                              : (_isSoldByWeight ? 'kg' : 'u');
                                          return Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFECFDF5),
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFFA7F3D0)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.inventory_rounded,
                                                  size: 15,
                                                  color: Color(0xFF065F46),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    '${delta > 0 ? 'Ajuste de inventario' : 'Descuento de inventario'}: $sign${delta.toQty()} $suffix · Al cobrar esta línea quedarán: ${afterSale.toUnitStockDisplay(isSoldByWeight: _isSoldByWeight, unitSuffix: suffix, weightUnit: suffix)}',
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFF065F46),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                  ],

                                  // 2. Opciones de actualización en Catálogo (Nombre y Precio/Costo) agrupadas
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: (_updateCatalogName ||
                                                _updateCatalogInDb)
                                            ? const Color(0xFF60A5FA)
                                            : const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      children: [
                                        InkWell(
                                          onTap: () => setState(() =>
                                              _updateCatalogName =
                                                  !_updateCatalogName),
                                          child: Container(
                                            color: _updateCatalogName
                                                ? const Color(0xFFEFF6FF)
                                                : Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  height: 22,
                                                  width: 22,
                                                  child: Checkbox(
                                                    value: _updateCatalogName,
                                                    activeColor:
                                                        const Color(0xFF2563EB),
                                                    onChanged: (val) =>
                                                        setState(() =>
                                                            _updateCatalogName =
                                                                val ?? false),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons
                                                      .drive_file_rename_outline_rounded,
                                                  size: 16,
                                                  color: _updateCatalogName
                                                      ? const Color(0xFF1D4ED8)
                                                      : const Color(0xFF64748B),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Guardar la descripción editada como nombre oficial en Catálogo',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              Color(0xFF334155),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 1),
                                                      Text(
                                                        _hasCatalogNameUpdate
                                                            ? 'BD: "${widget.item.product.name}" → "${_descController.text.trim()}"'
                                                            : 'Actual en BD: "${widget.item.product.name}"',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: _hasCatalogNameUpdate
                                                              ? const Color(
                                                                  0xFF1D4ED8)
                                                              : const Color(
                                                                  0xFF64748B),
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const Divider(
                                            height: 1,
                                            color: Color(0xFFE2E8F0)),
                                        InkWell(
                                          onTap: () => setState(() =>
                                              _updateCatalogInDb =
                                                  !_updateCatalogInDb),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 180),
                                            color: _updateCatalogInDb
                                                ? const Color(0xFFDBEAFE)
                                                : Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  height: 22,
                                                  width: 22,
                                                  child: Checkbox(
                                                    value: _updateCatalogInDb,
                                                    activeColor:
                                                        const Color(0xFF2563EB),
                                                    onChanged: (val) =>
                                                        setState(() =>
                                                            _updateCatalogInDb =
                                                                val ?? false),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons.save_outlined,
                                                  size: 16,
                                                  color: _updateCatalogInDb
                                                      ? const Color(0xFF1D4ED8)
                                                      : const Color(0xFF64748B),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Actualizar precio/costo permanentemente en el Catálogo (BD)',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: _updateCatalogInDb
                                                              ? const Color(
                                                                  0xFF1D4ED8)
                                                              : const Color(
                                                                  0xFF334155),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 1),
                                                      Text(
                                                        _updateCatalogInDb
                                                            ? _buildDbImpactSummary()
                                                            : 'Desmarcado: cualquier cambio de precio, descuento o costo aplica SOLO a esta venta.',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: _updateCatalogInDb
                                                              ? const Color(
                                                                  0xFF1E40AF)
                                                              : const Color(
                                                                  0xFF64748B),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // 5. Código de barras (Pistolear EAN)
                                  if (!widget.item.product.isCombo) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _hasBarcodeChanged
                                            ? const Color(0xFFF0FDF4)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _hasBarcodeChanged
                                              ? const Color(0xFF22C55E)
                                              : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.qr_code_scanner_rounded,
                                                size: 17,
                                                color: _hasBarcodeChanged
                                                    ? const Color(0xFF15803D)
                                                    : const Color(0xFF475569),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _hasBarcodeChanged
                                                      ? 'Nuevo código EAN listo para guardar en BD: ${_barcodeController.text.trim()}'
                                                      : (_originalBarcode
                                                              .isNotEmpty
                                                          ? 'Código de barras actual: $_originalBarcode'
                                                          : 'Sin código de barras asignado'),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        _hasBarcodeChanged
                                                            ? FontWeight.w700
                                                            : FontWeight.w600,
                                                    color: _hasBarcodeChanged
                                                        ? const Color(
                                                            0xFF166534)
                                                        : const Color(
                                                            0xFF334155),
                                                  ),
                                                ),
                                              ),
                                              TextButton.icon(
                                                onPressed: () {
                                                  setState(() {
                                                    _showBarcodeEditor =
                                                        !_showBarcodeEditor;
                                                    _barcodeCapturedByScanner =
                                                        false;
                                                  });
                                                  if (_showBarcodeEditor) {
                                                    WidgetsBinding.instance
                                                        .addPostFrameCallback(
                                                            (_) {
                                                      if (mounted) {
                                                        _barcodeFocus
                                                            .requestFocus();
                                                        _barcodeController
                                                                .selection =
                                                            TextSelection(
                                                          baseOffset: 0,
                                                          extentOffset:
                                                              _barcodeController
                                                                  .text.length,
                                                        );
                                                      }
                                                    });
                                                  }
                                                },
                                                style: TextButton.styleFrom(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                icon: Icon(
                                                  _showBarcodeEditor
                                                      ? Icons
                                                          .keyboard_arrow_up_rounded
                                                      : Icons.barcode_reader,
                                                  size: 16,
                                                ),
                                                label: Text(
                                                  _showBarcodeEditor
                                                      ? 'Ocultar'
                                                      : 'Pistolear código nuevo',
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (_showBarcodeEditor) ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: TextFormField(
                                                    controller:
                                                        _barcodeController,
                                                    focusNode: _barcodeFocus,
                                                    inputFormatters: [
                                                      FilteringTextInputFormatter
                                                          .deny(RegExp(r'\s')),
                                                    ],
                                                    onChanged: (_) {
                                                      setState(() {
                                                        _barcodeCapturedByScanner =
                                                            false;
                                                      });
                                                    },
                                                    onFieldSubmitted: (_) {
                                                      _barcodeFocus.unfocus();
                                                      setState(() {
                                                        _barcodeCapturedByScanner =
                                                            _barcodeController
                                                                .text
                                                                .trim()
                                                                .isNotEmpty;
                                                      });
                                                    },
                                                    decoration: InputDecoration(
                                                      labelText:
                                                          'Escanear o escribir Código de Barras (se guarda en BD)',
                                                      hintText:
                                                          'Pistoleá el envase ahora...',
                                                      prefixIcon: const Icon(
                                                          Icons
                                                              .qr_code_2_rounded,
                                                          size: 19),
                                                      suffixIcon:
                                                          _hasBarcodeChanged
                                                              ? IconButton(
                                                                  onPressed:
                                                                      () {
                                                                    setState(
                                                                        () {
                                                                      _barcodeController
                                                                              .text =
                                                                          _originalBarcode;
                                                                      _barcodeCapturedByScanner =
                                                                          false;
                                                                    });
                                                                  },
                                                                  tooltip:
                                                                      'Restaurar código original',
                                                                  icon: const Icon(
                                                                      Icons
                                                                          .restore_rounded,
                                                                      size: 18),
                                                                )
                                                              : null,
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      isDense: true,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (_barcodeCapturedByScanner &&
                                                _hasBarcodeChanged)
                                              const Padding(
                                                padding:
                                                    EdgeInsets.only(top: 5),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.check_circle_rounded,
                                                      size: 14,
                                                      color: Color(0xFF15803D),
                                                    ),
                                                    SizedBox(width: 5),
                                                    Expanded(
                                                      child: Text(
                                                        'Código capturado por el lector. Presioná Enter o "Aplicar" para guardarlo en la Base de Datos.',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              Color(0xFF15803D),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            footerLeading: canRecalcHardware
                ? OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenHardwareCalculator!();
                    },
                    icon: const Icon(Icons.straighten_rounded, size: 17),
                    label: const Text('Recalcular por m² / Medidas'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.tealDark,
                      side: const BorderSide(color: AppColors.tealDark),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                : null,
            footerActions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar (Esc)'),
              ),
              ElevatedButton.icon(
                onPressed: _submit,
                icon: Icon(
                  _hasAnyDbChange
                      ? Icons.save_rounded
                      : Icons.check_rounded,
                  size: 18,
                ),
                label: Text(
                  _hasAnyDbChange
                      ? 'Aplicar y Guardar en BD (Enter)'
                      : 'Aplicar en Comprobante (Enter)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}
